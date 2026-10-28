//+------------------------------------------------------------------+
//| TestNews.mq5 - boundary tests for News.mqh                       |
//| Place in: MQL5/Scripts/TestNews.mq5 (News.mqh in Include/QT/)    |
//| Run on any chart; read results in the Experts tab.               |
//+------------------------------------------------------------------+
#property script_show_inputs
#include "../Include/QT/News.mqh"

int g_fail = 0;

void Check(const bool cond, const string msg)
  {
   if(cond)
      Print("ok:   ", msg);
   else
     {
      g_fail++;
      Print("FAIL: ", msg);
     }
  }

void OnStart()
  {
   const int H = 3600;
   string why;

   //--- window logic: pre = 5h, post = 1h, boundaries inclusive
   CNewsFilter nf;
   nf.Init(_Symbol, "unused.csv", NEWS_LIVE_FF_JSON, 5, 1, "USD", true, 60);
   datetime T = D'2026.01.09 15:30';          // e.g. NFP in server time (server = NY + 7h)
   nf.TestInject(T, "USD", "Test NFP");
   nf.TestMarkLoaded(T);

   Check(!nf.IsBlocked(T - 5 * H - 1, why), "T-5h-1s is allowed");
   Check(nf.IsBlocked(T - 5 * H, why),      "T-5h is blocked");
   Check(nf.IsBlocked(T - 1, why),          "T-1s is blocked");
   Check(nf.IsBlocked(T, why),              "T is blocked");
   Check(nf.IsBlocked(T + 1 * H, why),      "T+1h is blocked");
   Check(!nf.IsBlocked(T + 1 * H + 1, why), "T+1h+1s is allowed");

   //--- next window start
   string title;
   datetime ns = nf.NextWindowStart(T - 10 * H, title);
   Check(ns == T - 5 * H, "NextWindowStart = T-5h");

   //--- fail-safe: no data loaded -> blocked when failSafe = true
   CNewsFilter nf3;
   nf3.Init(_Symbol, "unused.csv", NEWS_LIVE_FF_JSON, 5, 1, "USD", true, 60);
   Check(nf3.IsBlocked(T, why) && why == "NEWS_DATA_UNAVAILABLE", "fail-safe blocks when no data");

   CNewsFilter nf4;
   nf4.Init(_Symbol, "unused.csv", NEWS_LIVE_FF_JSON, 5, 1, "USD", false, 60);
   Check(!nf4.IsBlocked(T, why), "failSafe=false allows when no data");

   //--- stale data (> 24h) -> fail-safe
   CNewsFilter nf5;
   nf5.Init(_Symbol, "unused.csv", NEWS_LIVE_FF_JSON, 5, 1, "USD", true, 60);
   nf5.TestInject(T, "USD", "Test");
   nf5.TestMarkLoaded(T - 30 * H);
   Check(nf5.IsBlocked(T + 10 * H, why) && why == "NEWS_DATA_STALE", "stale data triggers fail-safe");

   //--- helpers
   datetime utc = 0;
   Check(QTN_ParseIso("2026-01-09T08:30:00-05:00", utc) && utc == D'2026.01.09 13:30',
         "ISO parse: 08:30 -05:00 = 13:30 UTC");
   Check(QTN_ParseIso("2026-07-09T08:30:00-04:00", utc) && utc == D'2026.07.09 12:30',
         "ISO parse: 08:30 -04:00 = 12:30 UTC");
   Check(QTN_JsonStr("{\"title\":\"CPI m/m\",\"country\":\"USD\"}", "country") == "USD",
         "JSON string extraction");

   PrintFormat("TestNews finished: %d failure(s)", g_fail);
  }
//+------------------------------------------------------------------+
