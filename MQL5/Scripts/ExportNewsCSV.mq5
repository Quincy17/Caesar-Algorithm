//+------------------------------------------------------------------+
//| ExportNewsCSV.mq5                                                |
//| Exports historical economic-calendar events from the MT5         |
//| built-in calendar to a CSV (Common/Files) for backtesting the    |
//| news filter (News.mqh).                                          |
//|                                                                  |
//| Place in: MQL5/Scripts/ExportNewsCSV.mq5                         |
//| Run once on any chart (terminal must be online so the calendar   |
//| database is synced). Output: Common/Files/<InpFile>              |
//|                                                                  |
//| CSV columns: unix_server, datetime_server, currency, impact,     |
//|              title                                               |
//| All times are BROKER SERVER time (as returned by the calendar).  |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

input datetime InpFrom        = D'2022.01.01 00:00'; // Start date
input datetime InpTo          = 0;                   // End date (0 = now)
input string   InpFile        = "news_high_impact.csv";
input int      InpMinImpact   = 3;                   // 3 = High only, 2 = Medium and High
input string   InpCurrencies  = "";                  // Empty = all, or e.g. USD,EUR,GBP,JPY

ulong  g_cid[];
string g_ccur[];

//--- currency code of a calendar country (cached)
string CurrencyOf(const ulong country_id)
  {
   int n = ArraySize(g_cid);
   for(int i = 0; i < n; i++)
      if(g_cid[i] == country_id)
         return g_ccur[i];
   MqlCalendarCountry c;
   string cur = "";
   if(CalendarCountryById(country_id, c))
      cur = c.currency;
   ArrayResize(g_cid, n + 1);
   ArrayResize(g_ccur, n + 1);
   g_cid[n]  = country_id;
   g_ccur[n] = cur;
   return cur;
  }

string Sanitize(string s)
  {
   StringReplace(s, ",", " ");
   StringReplace(s, "\"", " ");
   StringReplace(s, "\r", " ");
   StringReplace(s, "\n", " ");
   return s;
  }

void OnStart()
  {
   datetime from = InpFrom;
   datetime to   = (InpTo > 0 ? InpTo : TimeTradeServer());
   if(to <= from)
     {
      Print("ExportNewsCSV: InpTo must be after InpFrom");
      return;
     }

   //--- optional currency whitelist -> ",USD,EUR,"
   string allowed = "";
   if(StringLen(InpCurrencies) > 0)
     {
      string parts[];
      int n = StringSplit(InpCurrencies, ',', parts);
      allowed = ",";
      for(int i = 0; i < n; i++)
        {
         StringTrimLeft(parts[i]);
         StringTrimRight(parts[i]);
         StringToUpper(parts[i]);
         if(StringLen(parts[i]) > 0)
            allowed += parts[i] + ",";
        }
     }

   int h = FileOpen(InpFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(h == INVALID_HANDLE)
     {
      PrintFormat("ExportNewsCSV: cannot open %s (error %d)", InpFile, GetLastError());
      return;
     }
   FileWrite(h, "#coverage", (long)from, (long)to);
   FileWrite(h, "unix_server", "datetime_server", "currency", "impact", "title");

   const int CHUNK = 30 * 86400;
   int total = 0;

   for(datetime a = from; a <= to; a += CHUNK)
     {
      datetime b = a + CHUNK - 1;
      if(b > to)
         b = to;

      MqlCalendarValue v[];
      ResetLastError();
      if(!CalendarValueHistory(v, a, b))
         continue;                      // no data in this window
      int cnt = ArraySize(v);
      if(cnt == 0)
         continue;

      //--- sort this window by time (key = time*100000 + index)
      long keys[];
      ArrayResize(keys, cnt);
      for(int i = 0; i < cnt; i++)
         keys[i] = (long)v[i].time * 100000 + i;
      ArraySort(keys);

      for(int k = 0; k < cnt; k++)
        {
         int i = (int)(keys[k] % 100000);

         MqlCalendarEvent ev;
         if(!CalendarEventById(v[i].event_id, ev))
            continue;
         if(ev.time_mode != CALENDAR_TIMEMODE_DATETIME)
            continue;                   // skip all-day / tentative / no-time
         int imp = (int)ev.importance;
         if(imp < InpMinImpact)
            continue;

         string cur = CurrencyOf(ev.country_id);
         StringToUpper(cur);
         if(StringLen(cur) == 0)
            continue;
         if(StringLen(allowed) > 0 && StringFind(allowed, "," + cur + ",") < 0)
            continue;

         string label = (imp >= 3 ? "High" : (imp == 2 ? "Medium" : "Low"));
         FileWrite(h,
                   (long)v[i].time,
                   TimeToString(v[i].time, TIME_DATE | TIME_MINUTES),
                   cur,
                   label,
                   Sanitize(ev.name));
         total++;
        }
     }

   FileClose(h);
   PrintFormat("ExportNewsCSV: %d events written to %s\\Files\\%s",
               total, TerminalInfoString(TERMINAL_COMMONDATA_PATH), InpFile);
   PrintFormat("Verify: open the CSV and check a known event, e.g. US Non-Farm Payrolls "
               "(08:30 NY = 15:30 server time if server = NY + 7h).");
  }
//+------------------------------------------------------------------+
