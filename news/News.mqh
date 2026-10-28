//+------------------------------------------------------------------+
//| News.mqh                                                         |
//| M11 - High-impact news filter (QT-MSNR-ICT EA)                   |
//| Place in: MQL5/Include/QT/News.mqh                               |
//|                                                                  |
//| RULE: block NEW entries while                                    |
//|       [event - PreHours, event + PostHours] contains "now"       |
//|       for a relevant HIGH-impact event (boundaries inclusive).   |
//|                                                                  |
//| Sources                                                          |
//|  - Strategy Tester: CSV in Common/Files (ExportNewsCSV.mq5)      |
//|  - Live: Forex Factory weekly JSON via WebRequest, fallback MT5  |
//|          built-in calendar, fallback local cache file            |
//|          (add https://nfs.faireconomy.media to Tools > Options > |
//|           Expert Advisors > Allow WebRequest)                    |
//|                                                                  |
//| All times are BROKER SERVER time (same as TimeCurrent()).        |
//|                                                                  |
//| Usage in the EA:                                                 |
//|   #include <QT/News.mqh>                                         |
//|   CNewsFilter g_news;                                            |
//|   OnInit : g_news.Init(_Symbol, "news_high_impact.csv",          |
//|                        NEWS_LIVE_FF_JSON, 5, 1, "", true, 60);   |
//|            EventSetTimer(1);                                     |
//|            g_news.Update(TimeCurrent());                         |
//|   OnTimer: g_news.Update(TimeCurrent());                         |
//|   Before any entry:                                              |
//|            string why;                                           |
//|            if(g_news.IsBlocked(TimeCurrent(), why)) { cancel     |
//|               pending orders; log why; return; }                 |
//+------------------------------------------------------------------+
#ifndef QT_NEWS_MQH
#define QT_NEWS_MQH

enum ENUM_NEWS_SOURCE
  {
   NEWS_LIVE_FF_JSON = 0,   // Live primary: Forex Factory weekly JSON
   NEWS_LIVE_MT5_CAL = 1    // Live primary: MT5 built-in calendar
  };

struct SNewsEvent
  {
   datetime time_server;
   string   currency;
   string   title;
   int      impact;         // 3 = High, 2 = Medium, 1 = Low
  };

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
string QTN_Sanitize(string s)
  {
   StringReplace(s, ",", " ");
   StringReplace(s, "\"", " ");
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   return s;
  }

int QTN_ImpactLevel(string s)
  {
   StringToLower(s);
   if(s == "high")
      return 3;
   if(s == "medium" || s == "moderate")
      return 2;
   if(s == "low")
      return 1;
   return 0;
  }

string QTN_ImpactLabel(const int lvl)
  {
   if(lvl >= 3)
      return "High";
   if(lvl == 2)
      return "Medium";
   return "Low";
  }

//--- current broker offset to GMT, rounded to 15 minutes
int QTN_ServerOffsetSec()
  {
   long d = (long)TimeTradeServer() - (long)TimeGMT();
   long r = (long)MathRound((double)d / 900.0) * 900;
   return (int)r;
  }

//--- value of a top-level string field in a flat JSON object
string QTN_JsonStr(const string obj, const string key)
  {
   string pat = "\"" + key + "\"";
   int p = StringFind(obj, pat);
   if(p < 0)
      return "";
   p = StringFind(obj, ":", p + StringLen(pat));
   if(p < 0)
      return "";
   p++;
   int len = StringLen(obj);
   while(p < len && StringGetCharacter(obj, p) == ' ')
      p++;
   if(p >= len || StringGetCharacter(obj, p) != '"')
      return "";
   p++;
   int q = p;
   while(q < len)
     {
      ushort c = StringGetCharacter(obj, q);
      if(c == '\\')
        {
         q += 2;
         continue;
        }
      if(c == '"')
         break;
      q++;
     }
   return StringSubstr(obj, p, q - p);
  }

//--- "2025-01-05T08:30:00-05:00" -> UTC datetime
bool QTN_ParseIso(const string s, datetime &utc)
  {
   if(StringLen(s) < 19)
      return false;
   string d = StringSubstr(s, 0, 10);
   StringReplace(d, "-", ".");
   string t = StringSubstr(s, 11, 8);
   datetime local = StringToTime(d + " " + t);
   if(local <= 0)
      return false;
   long off = 0;
   if(StringLen(s) >= 25)
     {
      ushort sign = StringGetCharacter(s, 19);
      long hh = StringToInteger(StringSubstr(s, 20, 2));
      long mm = StringToInteger(StringSubstr(s, 23, 2));
      off = hh * 3600 + mm * 60;
      if(sign == '-')
         off = -off;
     }
   utc = (datetime)((long)local - off);
   return true;
  }

//+------------------------------------------------------------------+
//| CNewsFilter                                                      |
//+------------------------------------------------------------------+
class CNewsFilter
  {
private:
   SNewsEvent        m_ev[];
   int               m_count;
   int               m_preSec;
   int               m_postSec;
   int               m_impactMin;
   int               m_refreshSec;
   string            m_curList;      // ",EUR,USD,"
   string            m_csvFile;
   string            m_cacheFile;
   string            m_ffUrl;
   ENUM_NEWS_SOURCE  m_liveSource;
   bool              m_failSafe;
   bool              m_tester;
   bool              m_loaded;
   datetime          m_lastOk;
   datetime          m_nextTry;
   datetime          m_covFrom;
   datetime          m_covTo;
   datetime          m_savedAt;

   void              AddCur(string c)
     {
      StringToUpper(c);
      if(StringLen(c) == 0)
         return;
      if(StringFind(m_curList, "," + c + ",") < 0)
         m_curList += c + ",";
     }

   bool              Relevant(const string cur)
     {
      return (StringFind(m_curList, "," + cur + ",") >= 0);
     }

   void              Push(SNewsEvent &arr[], const datetime t, const string cur,
                          const string title, const int impact)
     {
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1, 512);
      arr[n].time_server = t;
      arr[n].currency    = cur;
      arr[n].title       = title;
      arr[n].impact      = impact;
     }

   void              Commit(SNewsEvent &tmp[])
     {
      int n = ArraySize(tmp);
      ArrayResize(m_ev, n);
      for(int i = 0; i < n; i++)
         m_ev[i] = tmp[i];
      m_count = n;
     }

   bool              LoadCsv(const string file)
     {
      int h = FileOpen(file, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("[News] cannot open %s (error %d)", file, GetLastError());
         return false;
        }
      SNewsEvent tmp[];
      datetime covFrom = 0, covTo = 0, saved = 0;

      while(!FileIsEnding(h))
        {
         string f[];
         int n = 0;
         while(true)
           {
            string s = FileReadString(h);
            ArrayResize(f, n + 1);
            f[n] = s;
            n++;
            if(FileIsLineEnding(h) || FileIsEnding(h))
               break;
           }
         if(n < 2)
            continue;
         if(f[0] == "#coverage" && n >= 3)
           {
            covFrom = (datetime)StringToInteger(f[1]);
            covTo   = (datetime)StringToInteger(f[2]);
            continue;
           }
         if(f[0] == "#saved")
           {
            saved = (datetime)StringToInteger(f[1]);
            continue;
           }
         if(StringGetCharacter(f[0], 0) == '#' || f[0] == "unix_server")
            continue;
         if(n < 4)
            continue;
         datetime t = (datetime)StringToInteger(f[0]);
         if(t <= 0)
            continue;
         string cur = f[2];
         StringToUpper(cur);
         int lvl = QTN_ImpactLevel(f[3]);
         if(lvl < m_impactMin || !Relevant(cur))
            continue;
         Push(tmp, t, cur, (n >= 5 ? f[4] : ""), lvl);
        }
      FileClose(h);

      if(ArraySize(tmp) == 0 && covTo == 0 && saved == 0)
         return false;
      Commit(tmp);
      m_covFrom = covFrom;
      m_covTo   = covTo;
      m_savedAt = saved;
      PrintFormat("[News] loaded %d relevant events from %s", m_count, file);
      return true;
     }

   void              SaveCsv(const string file, const datetime now)
     {
      int h = FileOpen(file, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(h == INVALID_HANDLE)
         return;
      FileWrite(h, "#saved", (long)now);
      FileWrite(h, "unix_server", "datetime_server", "currency", "impact", "title");
      for(int i = 0; i < m_count; i++)
         FileWrite(h, (long)m_ev[i].time_server,
                   TimeToString(m_ev[i].time_server, TIME_DATE | TIME_MINUTES),
                   m_ev[i].currency, QTN_ImpactLabel(m_ev[i].impact),
                   QTN_Sanitize(m_ev[i].title));
      FileClose(h);
     }

   int               ParseFF(const string json, SNewsEvent &out[])
     {
      int pos = 0, added = 0;
      int off = QTN_ServerOffsetSec();
      while(true)
        {
         int a = StringFind(json, "{", pos);
         if(a < 0)
            break;
         int b = StringFind(json, "}", a);
         if(b < 0)
            break;
         string obj = StringSubstr(json, a, b - a + 1);
         pos = b + 1;

         string cur = QTN_JsonStr(obj, "country");
         if(StringLen(cur) == 0)
            cur = QTN_JsonStr(obj, "currency");
         StringToUpper(cur);
         int lvl = QTN_ImpactLevel(QTN_JsonStr(obj, "impact"));
         if(lvl < m_impactMin || !Relevant(cur))
            continue;
         datetime utc = 0;
         if(!QTN_ParseIso(QTN_JsonStr(obj, "date"), utc))
            continue;
         Push(out, (datetime)((long)utc + off), cur, QTN_JsonStr(obj, "title"), lvl);
         added++;
        }
      return added;
     }

   bool              LoadFromFF()
     {
      char   post[];
      char   result[];
      string resHeaders;
      string headers = "User-Agent: Mozilla/5.0\r\n";
      ResetLastError();
      int code = WebRequest("GET", m_ffUrl, headers, 8000, post, result, resHeaders);
      if(code != 200)
        {
         PrintFormat("[News] FF request failed: http=%d err=%d "
                     "(allow the URL in Tools > Options > Expert Advisors)",
                     code, GetLastError());
         return false;
        }
      string json = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      SNewsEvent tmp[];
      int n = ParseFF(json, tmp);
      if(n <= 0)
        {
         Print("[News] FF response parsed to 0 events - check JSON field names");
         return false;
        }
      Commit(tmp);
      PrintFormat("[News] FF feed: %d relevant events", n);
      return true;
     }

   bool              LoadFromMt5Calendar(const datetime now)
     {
      MqlCalendarValue v[];
      datetime from = (datetime)((long)now - 86400);
      datetime to   = (datetime)((long)now + 7 * 86400);
      ResetLastError();
      if(!CalendarValueHistory(v, from, to))
        {
         PrintFormat("[News] MT5 calendar failed (err %d)", GetLastError());
         return false;
        }
      SNewsEvent tmp[];
      int cnt = ArraySize(v);
      for(int i = 0; i < cnt; i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(v[i].event_id, ev))
            continue;
         if(ev.time_mode != CALENDAR_TIMEMODE_DATETIME)
            continue;
         int lvl = (int)ev.importance;
         if(lvl < m_impactMin)
            continue;
         MqlCalendarCountry c;
         if(!CalendarCountryById(ev.country_id, c))
            continue;
         string cur = c.currency;
         StringToUpper(cur);
         if(!Relevant(cur))
            continue;
         Push(tmp, v[i].time, cur, ev.name, lvl);
        }
      if(ArraySize(tmp) == 0)
         return false;
      Commit(tmp);
      PrintFormat("[News] MT5 calendar: %d relevant events", m_count);
      return true;
     }

   bool              DataUsable(const datetime now, string &reason)
     {
      if(!m_loaded)
        {
         reason = "NEWS_DATA_UNAVAILABLE";
         return false;
        }
      if(m_tester)
        {
         if(m_covTo > 0 && (now < m_covFrom || now > m_covTo))
           {
            reason = "NEWS_CSV_OUT_OF_RANGE";
            return false;
           }
         return true;
        }
      if((long)now - (long)m_lastOk > 24 * 3600)
        {
         reason = "NEWS_DATA_STALE";
         return false;
        }
      return true;
     }

public:
                     CNewsFilter()
     {
      m_count = 0;
      m_preSec = 5 * 3600;
      m_postSec = 3600;
      m_impactMin = 3;
      m_refreshSec = 3600;
      m_curList = ",";
      m_liveSource = NEWS_LIVE_FF_JSON;
      m_failSafe = true;
      m_tester = false;
      m_loaded = false;
      m_lastOk = 0;
      m_nextTry = 0;
      m_covFrom = 0;
      m_covTo = 0;
      m_savedAt = 0;
      m_ffUrl = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
      m_cacheFile = "news_cache.csv";
     }

   void              Init(const string symbol,
                          const string csvFile,
                          const ENUM_NEWS_SOURCE liveSource = NEWS_LIVE_FF_JSON,
                          const int preHours = 5,
                          const int postHours = 1,
                          const string extraCurrencies = "",
                          const bool failSafe = true,
                          const int refreshMin = 60,
                          const int impactMin = 3,
                          const string cacheFile = "news_cache.csv")
     {
      m_csvFile = csvFile;
      m_liveSource = liveSource;
      m_preSec = preHours * 3600;
      m_postSec = postHours * 3600;
      m_failSafe = failSafe;
      m_refreshSec = MathMax(refreshMin, 5) * 60;
      m_impactMin = impactMin;
      m_cacheFile = cacheFile;
      m_tester = (bool)MQLInfoInteger(MQL_TESTER);

      m_curList = ",";
      AddCur(SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE));
      AddCur(SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT));
      string parts[];
      int n = StringSplit(extraCurrencies, ',', parts);
      for(int i = 0; i < n; i++)
        {
         StringTrimLeft(parts[i]);
         StringTrimRight(parts[i]);
         AddCur(parts[i]);
        }
      PrintFormat("[News] currencies=%s pre=%dh post=%dh tester=%s",
                  m_curList, preHours, postHours, (m_tester ? "yes" : "no"));
     }

   //--- call from OnTimer (live) or OnTick/new bar (tester) with TimeCurrent()
   bool              Update(const datetime now)
     {
      if(m_tester)
        {
         if(!m_loaded)
           {
            m_loaded = LoadCsv(m_csvFile);
            m_lastOk = now;
            if(!m_loaded)
               PrintFormat("[News] tester CSV not loaded (fail-safe=%s)",
                           (m_failSafe ? "on: no entries" : "off: no filter"));
           }
         return m_loaded;
        }

      if(now < m_nextTry)
         return m_loaded;

      bool ok = false;
      if(m_liveSource == NEWS_LIVE_FF_JSON)
        {
         ok = LoadFromFF();
         if(!ok)
            ok = LoadFromMt5Calendar(now);
        }
      else
        {
         ok = LoadFromMt5Calendar(now);
         if(!ok)
            ok = LoadFromFF();
        }

      if(ok)
        {
         m_loaded = true;
         m_lastOk = now;
         m_nextTry = (datetime)((long)now + m_refreshSec);
         SaveCsv(m_cacheFile, now);
        }
      else
        {
         m_nextTry = (datetime)((long)now + 300);
         if(!m_loaded && LoadCsv(m_cacheFile))
           {
            m_loaded = true;
            m_lastOk = (m_savedAt > 0 ? m_savedAt : (datetime)((long)now - 25 * 3600));
           }
        }
      return m_loaded;
     }

   //--- true = DO NOT open new entries now
   bool              IsBlocked(const datetime now, string &reason)
     {
      reason = "";
      if(!DataUsable(now, reason))
         return m_failSafe;

      long n = (long)now;
      for(int i = 0; i < m_count; i++)
        {
         long t = (long)m_ev[i].time_server;
         if(n >= t - m_preSec && n <= t + m_postSec)
           {
            reason = StringFormat("NEWS %s %s @ %s", m_ev[i].currency, m_ev[i].title,
                                  TimeToString(m_ev[i].time_server, TIME_DATE | TIME_MINUTES));
            return true;
           }
        }
      return false;
     }

   //--- start time of the next blocked window after 'now' (0 = none known)
   datetime          NextWindowStart(const datetime now, string &title)
     {
      long best = 0;
      title = "";
      long n = (long)now;
      for(int i = 0; i < m_count; i++)
        {
         long s = (long)m_ev[i].time_server - m_preSec;
         if(s > n && (best == 0 || s < best))
           {
            best = s;
            title = m_ev[i].currency + " " + m_ev[i].title;
           }
        }
      return (datetime)best;
     }

   int               Count() const { return m_count; }

   //--- test helpers (used by TestNews.mq5)
   void              TestInject(const datetime t, const string cur, const string title)
     {
      AddCur(cur);
      Push(m_ev, t, cur, title, 3);
      m_count = ArraySize(m_ev);
     }
   void              TestMarkLoaded(const datetime now)
     {
      m_loaded = true;
      m_lastOk = now;
     }
  };

#endif
//+------------------------------------------------------------------+
