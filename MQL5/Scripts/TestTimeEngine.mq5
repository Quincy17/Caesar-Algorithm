//+------------------------------------------------------------------+
//| TestTimeEngine.mq5                                               |
//| Fase 1 - Ground Truth Unit Tests for QT_Time.mqh                 |
//| Place in: MQL5/Scripts/TestTimeEngine.mq5                        |
//| Run on any chart; inspect output in the Experts tab.             |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.10"
#property strict

#include "../Include/QT/QT_Time.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const bool cond, const string msg)
  {
   if(cond)
     {
      g_pass++;
      Print("PASS: ", msg);
     }
   else
     {
      g_fail++;
      Print("FAIL: ", msg);
     }
  }

void OnStart()
  {
   Print("=== Starting Fase 1 Unit Tests: QT_Time.mqh ===");

   //------------------------------------------------------------------
   // 1. US DST Transition Tests (March & November 2026)
   //    - 2026 DST starts: Sunday, March 8, 2026 at 07:00 UTC (02:00 EST -> 03:00 EDT)
   //    - 2026 DST ends  : Sunday, Nov 1, 2026   at 06:00 UTC (02:00 EDT -> 01:00 EST)
   //------------------------------------------------------------------
   Check(!CQTTimeEngine::IsUsDstFromUTC(D'2026.03.08 06:59:59'), "DST 2026-03-08 06:59:59 UTC is Standard Time (EST)");
   Check( CQTTimeEngine::IsUsDstFromUTC(D'2026.03.08 07:00:00'), "DST 2026-03-08 07:00:00 UTC is Daylight Time (EDT)");
   Check( CQTTimeEngine::IsUsDstFromUTC(D'2026.11.01 05:59:59'), "DST 2026-11-01 05:59:59 UTC is Daylight Time (EDT)");
   Check(!CQTTimeEngine::IsUsDstFromUTC(D'2026.11.01 06:00:00'), "DST 2026-11-01 06:00:00 UTC is Standard Time (EST)");

   // Mode B test (Server = GMT+0)
   SQTTimeConfig cfgB;
   cfgB.SetDefaults();
   cfgB.convMode            = TIME_MODE_B_GMT_PLUS_USDST;
   cfgB.modeBServerGmtHours = 0;
   CQTTimeEngine engB;
   engB.Init(_Symbol, cfgB);

   Check(engB.ServerToNY(D'2026.01.15 13:30:00') == D'2026.01.15 08:30:00', "Mode B (UTC->EST): 13:30 UTC = 08:30 NY");
   Check(engB.ServerToNY(D'2026.07.15 12:30:00') == D'2026.07.15 08:30:00', "Mode B (UTC->EDT): 12:30 UTC = 08:30 NY");

   //------------------------------------------------------------------
   // 2. Mode A (Default: NY = Server - 7h) & Daye 18:00 NY Day Rollover
   //------------------------------------------------------------------
   SQTTimeConfig cfgA;
   cfgA.SetDefaults(); // Mode A (-7h), Intraday preset
   CQTTimeEngine engA;
   engA.Init(_Symbol, cfgA);

   QTState st;

   // Sunday 2026-10-25 17:59:59 NY (Server = 2026-10-26 00:59:59) -> still Sunday Q0
   engA.Evaluate(engA.NYToServer(D'2026.10.25 17:59:59'), st, false);
   Check(st.dayeDayOfWeek == 0 && st.weekQ == QT_Q0, "Sun 17:59:59 NY -> Sunday Daye day (weekQ = Q0)");

   // Sunday 2026-10-25 18:00:00 NY -> Monday Daye Day (2026-10-26, weekQ = Q1, Asia Q1, 90m Q1)
   engA.Evaluate(engA.NYToServer(D'2026.10.25 18:00:00'), st, false);
   Check(st.dayeYear == 2026 && st.dayeMonth == 10 && st.dayeDay == 26 &&
         st.dayeDayOfWeek == 1 && st.weekQ == QT_Q1 &&
         st.dayQ == QT_Q1 && st.session == QT_SESSION_ASIA && st.q90 == QT_Q1,
         "Sun 18:00:00 NY -> Rolls over to Monday 2026-10-26 Daye day (weekQ=Q1, Asia=Q1, 90m=Q1)");

   // Monday 2026-10-26 18:00:00 NY -> Tuesday Daye Day (2026-10-27, weekQ = Q2)
   engA.Evaluate(engA.NYToServer(D'2026.10.26 18:00:00'), st, false);
   Check(st.dayeDay == 27 && st.dayeDayOfWeek == 2 && st.weekQ == QT_Q2,
         "Mon 18:00:00 NY -> Rolls over to Tuesday 2026-10-27 Daye day (weekQ=Q2)");

   // Tuesday 2026-10-27 18:00:00 NY -> Wednesday Daye Day (2026-10-28, weekQ = Q3)
   engA.Evaluate(engA.NYToServer(D'2026.10.27 18:00:00'), st, false);
   Check(st.dayeDay == 28 && st.dayeDayOfWeek == 3 && st.weekQ == QT_Q3,
         "Tue 18:00:00 NY -> Rolls over to Wednesday 2026-10-28 Daye day (weekQ=Q3)");

   // Wednesday 2026-10-28 18:00:00 NY -> Thursday Daye Day (2026-10-29, weekQ = Q4)
   engA.Evaluate(engA.NYToServer(D'2026.10.28 18:00:00'), st, false);
   Check(st.dayeDay == 29 && st.dayeDayOfWeek == 4 && st.weekQ == QT_Q4,
         "Wed 18:00:00 NY -> Rolls over to Thursday 2026-10-29 Daye day (weekQ=Q4)");

   // Thursday 2026-10-29 18:00:00 NY -> Friday Daye Day (2026-10-30, weekQ = Q0)
   engA.Evaluate(engA.NYToServer(D'2026.10.29 18:00:00'), st, false);
   Check(st.dayeDay == 30 && st.dayeDayOfWeek == 5 && st.weekQ == QT_Q0 && !st.isTimeAllowed,
         "Thu 18:00:00 NY -> Rolls over to Friday 2026-10-30 Daye day (weekQ=Q0, blocked)");

   //------------------------------------------------------------------
   // 3. Daily Sessions & 90-Minute Quarters Verification
   //------------------------------------------------------------------
   // Asia 90m blocks: 18:00 (Q1), 19:30 (Q2), 21:00 (Q3), 22:30 (Q4)
   engA.Evaluate(engA.NYToServer(D'2026.10.26 19:29:00'), st, false);
   Check(st.session == QT_SESSION_ASIA && st.q90 == QT_Q1, "Asia 19:29 NY = 90m Q1");
   engA.Evaluate(engA.NYToServer(D'2026.10.26 19:30:00'), st, false);
   Check(st.session == QT_SESSION_ASIA && st.q90 == QT_Q2, "Asia 19:30 NY = 90m Q2 (True Session Open)");
   engA.Evaluate(engA.NYToServer(D'2026.10.26 21:00:00'), st, false);
   Check(st.session == QT_SESSION_ASIA && st.q90 == QT_Q3, "Asia 21:00 NY = 90m Q3");
   engA.Evaluate(engA.NYToServer(D'2026.10.26 22:30:00'), st, false);
   Check(st.session == QT_SESSION_ASIA && st.q90 == QT_Q4, "Asia 22:30 NY = 90m Q4");

   // London 90m blocks: 00:00 (Q1), 01:30 (Q2), 03:00 (Q3), 04:30 (Q4)
   engA.Evaluate(engA.NYToServer(D'2026.10.27 00:00:00'), st, false);
   Check(st.session == QT_SESSION_LONDON && st.dayQ == QT_Q2 && st.q90 == QT_Q1 && !st.isTimeAllowed,
         "Tue London 00:00 NY = Day Q2, 90m Q1 (Intraday blocks Q1)");
   engA.Evaluate(engA.NYToServer(D'2026.10.27 01:30:00'), st, false);
   Check(st.session == QT_SESSION_LONDON && st.dayQ == QT_Q2 && st.q90 == QT_Q2 && st.isTimeAllowed,
         "Tue London 01:30 NY = Day Q2, 90m Q2 (Allowed for Intraday)");
   engA.Evaluate(engA.NYToServer(D'2026.10.27 03:15:00'), st, false);
   Check(st.session == QT_SESSION_LONDON && st.dayQ == QT_Q2 && st.q90 == QT_Q3 && st.isTimeAllowed,
         "Tue London 03:15 NY = Day Q2, 90m Q3 (Allowed for Intraday)");

   // NY AM 90m blocks: 06:00 (Q1), 07:30 (Q2), 09:00 (Q3), 10:30 (Q4)
   engA.Evaluate(engA.NYToServer(D'2026.10.27 07:30:00'), st, false);
   Check(st.session == QT_SESSION_NY_AM && st.dayQ == QT_Q3 && st.q90 == QT_Q2 && st.isTimeAllowed,
         "Tue NY AM 07:30 NY = Day Q3, 90m Q2 (Allowed for Intraday)");

   // NY PM 90m blocks: 12:00 (Q1), 13:30 (Q2), 15:00 (Q3), 16:30 (Q4)
   engA.Evaluate(engA.NYToServer(D'2026.10.27 13:30:00'), st, false);
   Check(st.session == QT_SESSION_NY_PM && st.dayQ == QT_Q4 && st.q90 == QT_Q2 && !st.isTimeAllowed,
         "Tue NY PM 13:30 NY = Day Q4, 90m Q2 (Blocked for Intraday)");

   //------------------------------------------------------------------
   // 4. Monthly Quarters (Q1..Q4 & 5th Monday Q0) & True Open Anchors
   //------------------------------------------------------------------
   // October 2026 Mondays: Oct 5 (Q1), Oct 12 (Q2), Oct 19 (Q3), Oct 26 (Q4)
   engA.Evaluate(engA.NYToServer(D'2026.10.06 08:00:00'), st, false);
   Check(st.monthQ == QT_Q1, "2026-10-06 (1st Monday week) -> monthQ = Q1");
   engA.Evaluate(engA.NYToServer(D'2026.10.13 08:00:00'), st, false);
   Check(st.monthQ == QT_Q2, "2026-10-13 (2nd Monday week) -> monthQ = Q2");
   engA.Evaluate(engA.NYToServer(D'2026.10.20 08:00:00'), st, false);
   Check(st.monthQ == QT_Q3, "2026-10-20 (3rd Monday week) -> monthQ = Q3");
   engA.Evaluate(engA.NYToServer(D'2026.10.27 08:00:00'), st, false);
   Check(st.monthQ == QT_Q4, "2026-10-27 (4th Monday week) -> monthQ = Q4");

   // March 2026 has 5 Mondays: Mar 2, 9, 16, 23, 30 -> Mar 30 week is Q0
   engA.Evaluate(engA.NYToServer(D'2026.03.30 08:00:00'), st, false);
   Check(st.monthQ == QT_Q0, "2026-03-30 (5th Monday week) -> monthQ = Q0");

   // True Open Anchor Timestamps on Tuesday 2026-10-27 08:00 NY:
   // - True Year Open   : 1st Monday of April 2026 (Apr 6) -> Daye open = Sun 2026-04-05 18:00 NY
   // - True Month Open  : 2nd Monday of Oct 2026 (Oct 12)  -> Daye open = Sun 2026-10-11 18:00 NY
   // - True Week Open   : Mon 2026-10-26 18:00 NY
   // - True Day Open    : Tue 2026-10-27 00:00 NY
   // - True Session Open: Tue 2026-10-27 07:30 NY (NY AM)
   engA.Evaluate(engA.NYToServer(D'2026.10.27 08:00:00'), st, false);
   Check(st.trueOpens.yearOpen.time_ny    == D'2026.04.05 18:00:00', "True Year Open 2026 = 2026-04-05 18:00 NY (1st Mon Apr Daye Open)");
   Check(st.trueOpens.monthOpen.time_ny   == D'2026.10.11 18:00:00', "True Month Open Oct 2026 = 2026-10-11 18:00 NY (2nd Mon Oct Daye Open)");
   Check(st.trueOpens.weekOpen.time_ny    == D'2026.10.26 18:00:00', "True Week Open = 2026-10-26 18:00 NY (Mon 18:00 NY)");
   Check(st.trueOpens.dayOpen.time_ny     == D'2026.10.27 00:00:00', "True Day Open = 2026-10-27 00:00 NY");
   Check(st.trueOpens.sessionOpen.time_ny == D'2026.10.27 07:30:00', "True Session Open (NY AM) = 2026-10-27 07:30 NY");

   // Before 1st Monday of April 2026 (e.g. 2026-03-15) -> True Year Open falls back to April 2025 (2025-04-06 18:00 NY)
   engA.Evaluate(engA.NYToServer(D'2026.03.15 10:00:00'), st, false);
   Check(st.trueOpens.yearOpen.time_ny == D'2025.04.06 18:00:00', "True Year Open before Apr 2026 falls back to 2025-04-06 18:00 NY");

   //------------------------------------------------------------------
   // 5. Friday 15:00 NY Forced Flat Cutoff Check
   //------------------------------------------------------------------
   engA.Evaluate(engA.NYToServer(D'2026.10.30 14:59:00'), st, false);
   Check(!st.isFridayCutoffPassed, "Fri 14:59 NY -> before Friday Flat cutoff");
   engA.Evaluate(engA.NYToServer(D'2026.10.30 15:00:00'), st, false);
   Check( st.isFridayCutoffPassed, "Fri 15:00 NY -> Friday Flat cutoff triggered");

   PrintFormat("=== TestTimeEngine finished: %d PASSED, %d FAILED ===", g_pass, g_fail);
  }
//+------------------------------------------------------------------+
