//+------------------------------------------------------------------+
//| AnalyzeBacktestCSV.mq5                                           |
//| Fase 8 - Statistical Analyzer for QT_Forward_Journal.csv &       |
//| QT_Setups_Log.csv (Forward-Test Recap & Algorithm Evolution)     |
//| Place in: MQL5/Scripts/AnalyzeBacktestCSV.mq5                    |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.20"
#property script_show_inputs
#property strict

input string InpForwardJournalCsv = "QT_Forward_Journal.csv";
input string InpSetupsCsv         = "QT_Setups_Log.csv";
input string InpReportTxt         = "QT_Forward_Evolution_Report.txt";
input int    InpMonteCarloRuns    = 2500;  // Monte Carlo Bootstrap Iterations
input double InpRiskPctPerTrade   = 0.50;  // Risk % per 1R for Monte Carlo DD%

struct SBucketStats
  {
   string name;
   int    trades;
   int    wins;
   double grossWinR;
   double grossLossR;
   double netR;
   double netUsd;

   void Init(const string n)
     {
      name       = n;
      trades     = 0;
      wins       = 0;
      grossWinR  = 0.0;
      grossLossR = 0.0;
      netR       = 0.0;
      netUsd     = 0.0;
     }

   void Add(const double r, const double usd = 0.0)
     {
      trades++;
      netR   += r;
      netUsd += usd;
      if(r > 0.05 || (MathAbs(r) <= 0.05 && usd > 0.0))
        {
         wins++;
         grossWinR += MathMax(0.0, r);
        }
      else if(r < -0.05 || usd < 0.0)
         grossLossR += MathAbs(r);
     }

   string FormatRow() const
     {
      double wr  = (trades > 0 ? (double)wins * 100.0 / (double)trades : 0.0);
      double exp = (trades > 0 ? netR / (double)trades : 0.0);
      double pf  = (grossLossR > 1e-5 ? grossWinR / grossLossR : (grossWinR > 0.0 ? 99.9 : 0.0));
      return StringFormat("  %-14s | Trades: %4d | WR: %5.1f%% | Net R: %+7.2fR | Net $: %+9.2f | Exp: %+5.2fR | PF: %5.2f",
                          name, trades, wr, netR, netUsd, exp, pf);
     }
  };

void OnStart()
  {
   // 1. Analyze Setups Log (Armed vs Rejected by News, Score, RR, SL)
   int totalSetups      = 0;
   int armedSetups      = 0;
   int rejectedNews     = 0;
   int rejectedLowScore = 0;
   int rejectedLowRR    = 0;
   int rejectedWideSL   = 0;

   int hSet = FileOpen(InpSetupsCsv, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(hSet != INVALID_HANDLE)
     {
      bool isHeader = true;
      while(!FileIsEnding(hSet))
        {
         string line = FileReadString(hSet);
         if(StringLen(line) < 5) continue;
         if(isHeader) { isHeader = false; continue; }

         string cols[];
         int n = StringSplit(line, ',', cols);
         if(n < 9) continue;

         totalSetups++;
         string statusReason = cols[8];
         if(StringFind(statusReason, "ARMED_VALID") >= 0)            armedSetups++;
         else if(StringFind(statusReason, "REJECT_NEWS") >= 0)       rejectedNews++;
         else if(StringFind(statusReason, "REJECT_LOW_SCORE") >= 0)  rejectedLowScore++;
         else if(StringFind(statusReason, "REJECT_RR_BELOW") >= 0)   rejectedLowRR++;
         else if(StringFind(statusReason, "REJECT_SL_TOO_WIDE") >= 0) rejectedWideSL++;
        }
      FileClose(hSet);
     }

   // 2. Analyze Master Forward Journal (QT_Forward_Journal.csv)
   SBucketStats overall;
   overall.Init("OVERALL");

   SBucketStats byDay[5];
   byDay[0].Init("Mon (Q1)");
   byDay[1].Init("Tue (Q2)");
   byDay[2].Init("Wed (Q3)");
   byDay[3].Init("Thu (Q4)");
   byDay[4].Init("Fri (Q0)");

   SBucketStats bySession[4];
   bySession[0].Init("Asia (Q1)");
   bySession[1].Init("London (Q2)");
   bySession[2].Init("NY_AM (Q3)");
   bySession[3].Init("NY_PM (Q4)");

   SBucketStats byQ90[4];
   byQ90[0].Init("90m Q1");
   byQ90[1].Init("90m Q2");
   byQ90[2].Init("90m Q3");
   byQ90[3].Init("90m Q4");

   SBucketStats byRefinement[2];
   byRefinement[0].Init("M15/M5 Refined");
   byRefinement[1].Init("HTF Only");

   // Exit Outcome Counters
   int cntTpFull      = 0;
   int cntTp1ThenTp   = 0;
   int cntTp1ThenBe   = 0;
   int cntBeHit       = 0;
   int cntSlHit       = 0;
   int cntTimeStop    = 0;
   int cntFridayFlat  = 0;
   int cntManualOther = 0;

   // Algorithm Evolution Telemetry Accumulators
   double sumMfeR       = 0.0;
   double sumMaeR       = 0.0;
   double sumWinMaeR    = 0.0;
   int    slAfter08Mfe  = 0; // Losses that went >= +0.8R in profit before hitting SL

   double peakEquityR   = 0.0;
   double curEquityR    = 0.0;
   double maxDdR        = 0.0;
   double peakEquityUsd = 0.0;
   double curEquityUsd  = 0.0;
   double maxDdUsd      = 0.0;

   double tradeHistoryR[];
   int    tradeCountR = 0;

   int hJrn = FileOpen(InpForwardJournalCsv, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(hJrn != INVALID_HANDLE)
     {
      bool isHeader = true;
      while(!FileIsEnding(hJrn))
        {
         string line = FileReadString(hJrn);
         if(StringLen(line) < 10) continue;
         if(isHeader) { isHeader = false; continue; }

         string cols[];
         int n = StringSplit(line, ',', cols);
         if(n < 56) continue;

         string dow         = cols[12];
         string ses         = cols[17];
         string q90         = cols[18];
         string exitOutcome = cols[33];
         double netUsd      = StringToDouble(cols[38]);
         double realizedR   = StringToDouble(cols[39]);
         double mfeR        = StringToDouble(cols[42]);
         double maeR        = StringToDouble(cols[44]);
         string refinedPoi  = cols[53];

         overall.Add(realizedR, netUsd);
         ArrayResize(tradeHistoryR, tradeCountR + 1, 256);
         tradeHistoryR[tradeCountR] = realizedR;
         tradeCountR++;

         curEquityR += realizedR;
         if(curEquityR > peakEquityR) peakEquityR = curEquityR;
         if(peakEquityR - curEquityR > maxDdR) maxDdR = peakEquityR - curEquityR;

         curEquityUsd += netUsd;
         if(curEquityUsd > peakEquityUsd) peakEquityUsd = curEquityUsd;
         if(peakEquityUsd - curEquityUsd > maxDdUsd) maxDdUsd = peakEquityUsd - curEquityUsd;

         // Exit Outcome Tally
         if(exitOutcome == "TP_FULL")          cntTpFull++;
         else if(exitOutcome == "TP1_THEN_TP") cntTp1ThenTp++;
         else if(exitOutcome == "TP1_THEN_BE") cntTp1ThenBe++;
         else if(exitOutcome == "BE_HIT")      cntBeHit++;
         else if(exitOutcome == "SL_HIT")      cntSlHit++;
         else if(exitOutcome == "TIME_STOP")   cntTimeStop++;
         else if(exitOutcome == "FRIDAY_FLAT") cntFridayFlat++;
         else                                  cntManualOther++;

         // MFE / MAE Diagnostics
         sumMfeR += mfeR;
         sumMaeR += maeR;
         if(realizedR > 0.05)
            sumWinMaeR += maeR;
         if(exitOutcome == "SL_HIT" && mfeR >= 0.80)
            slAfter08Mfe++;

         // QT Breakdowns
         if(dow == "Mon")      byDay[0].Add(realizedR, netUsd);
         else if(dow == "Tue") byDay[1].Add(realizedR, netUsd);
         else if(dow == "Wed") byDay[2].Add(realizedR, netUsd);
         else if(dow == "Thu") byDay[3].Add(realizedR, netUsd);
         else if(dow == "Fri") byDay[4].Add(realizedR, netUsd);

         if(ses == "Asia")        bySession[0].Add(realizedR, netUsd);
         else if(ses == "London") bySession[1].Add(realizedR, netUsd);
         else if(ses == "NY_AM")  bySession[2].Add(realizedR, netUsd);
         else if(ses == "NY_PM")  bySession[3].Add(realizedR, netUsd);

         if(q90 == "Q1")      byQ90[0].Add(realizedR, netUsd);
         else if(q90 == "Q2") byQ90[1].Add(realizedR, netUsd);
         else if(q90 == "Q3") byQ90[2].Add(realizedR, netUsd);
         else if(q90 == "Q4") byQ90[3].Add(realizedR, netUsd);

         if(refinedPoi != "NONE" && StringLen(refinedPoi) > 0)
            byRefinement[0].Add(realizedR, netUsd);
         else
            byRefinement[1].Add(realizedR, netUsd);
        }
      FileClose(hJrn);
     }

   double avgMfeR    = (overall.trades > 0 ? sumMfeR / (double)overall.trades : 0.0);
   double avgMaeR    = (overall.trades > 0 ? sumMaeR / (double)overall.trades : 0.0);
   double avgWinMaeR = (overall.wins   > 0 ? sumWinMaeR / (double)overall.wins : 0.0);

   // 2B. Run Monte Carlo Bootstrap Simulation (Resampling with Replacement + Slippage Jitter)
   double mcDd50R  = 0.0, mcDd95R  = 0.0, mcDd99R  = 0.0;
   double mcNet5R  = 0.0, mcNet50R = 0.0, mcNet95R = 0.0;
   double mcProbProfitPct = 0.0;
   int    mcRuns = MathMax(100, InpMonteCarloRuns);

   if(tradeCountR >= 5)
     {
      MathSrand((int)GetTickCount());
      double simMaxDdR[];
      double simFinalNetR[];
      ArrayResize(simMaxDdR, mcRuns);
      ArrayResize(simFinalNetR, mcRuns);
      int profitableRuns = 0;

      for(int sim = 0; sim < mcRuns; sim++)
        {
         double eqR   = 0.0;
         double pkR   = 0.0;
         double mddR  = 0.0;
         for(int k = 0; k < tradeCountR; k++)
           {
            int idx = MathRand() % tradeCountR;
            // Small execution/slippage jitter: [-0.05R .. +0.02R]
            double jitterR = ((double)(MathRand() % 71) - 50.0) * 0.001;
            double rSample = tradeHistoryR[idx] + jitterR;
            eqR += rSample;
            if(eqR > pkR) pkR = eqR;
            if(pkR - eqR > mddR) mddR = pkR - eqR;
           }
         simMaxDdR[sim]    = mddR;
         simFinalNetR[sim] = eqR;
         if(eqR > 0.0)
            profitableRuns++;
        }

      ArraySort(simMaxDdR);
      ArraySort(simFinalNetR);

      mcDd50R  = simMaxDdR[(int)(mcRuns * 0.50)];
      mcDd95R  = simMaxDdR[(int)(mcRuns * 0.95)];
      mcDd99R  = simMaxDdR[(int)(mcRuns * 0.99)];

      mcNet5R  = simFinalNetR[(int)(mcRuns * 0.05)];
      mcNet50R = simFinalNetR[(int)(mcRuns * 0.50)];
      mcNet95R = simFinalNetR[(int)(mcRuns * 0.95)];
      mcProbProfitPct = (double)profitableRuns * 100.0 / (double)mcRuns;
     }

   // 3. Build & Write Report
   string rep = "";
   rep += "==========================================================================================\n";
   rep += "  EA QT-MSNR-ICT (MQL5) - Forward-Test Master Journal & Algorithm Evolution Report\n";
   rep += "==========================================================================================\n\n";

   rep += "--- 1. Setup Funnel & Pre-Trade Filter Rejections (QT_Setups_Log.csv) ---\n";
   rep += StringFormat("  Total Evaluated Setups : %d\n", totalSetups);
   rep += StringFormat("  Armed Valid Setups     : %d\n", armedSetups);
   rep += StringFormat("  Blocked by News [-5,+1]: %d\n", rejectedNews);
   rep += StringFormat("  Rejected by Low Score  : %d\n", rejectedLowScore);
   rep += StringFormat("  Rejected by Low RR     : %d\n", rejectedLowRR);
   rep += StringFormat("  Rejected by Wide SL    : %d\n\n", rejectedWideSL);

   rep += "--- 2. Closed-Trade Outcome Distribution (TP / SL / BE / Time Stop) ---\n";
   rep += StringFormat("  Total Closed Positions : %d\n", overall.trades);
   rep += StringFormat("  TP_FULL (Direct TP)    : %d\n", cntTpFull);
   rep += StringFormat("  TP1_THEN_TP (50%%+Runner): %d\n", cntTp1ThenTp);
   rep += StringFormat("  TP1_THEN_BE (50%%+BE)   : %d\n", cntTp1ThenBe);
   rep += StringFormat("  BE_HIT (Break-Even)    : %d\n", cntBeHit);
   rep += StringFormat("  SL_HIT (Full Loss)     : %d\n", cntSlHit);
   rep += StringFormat("  TIME_STOP (Profile End): %d\n", cntTimeStop);
   rep += StringFormat("  FRIDAY_FLAT (15:00 NY) : %d\n", cntFridayFlat);
   rep += StringFormat("  MANUAL / OTHER         : %d\n\n", cntManualOther);

   rep += "--- 3. Overall Financial & R-Multiple Performance ---\n";
   rep += overall.FormatRow() + "\n";
   rep += StringFormat("  Max Drawdown           : %.2fR  ($%.2f)\n\n", maxDdR, maxDdUsd);

   rep += StringFormat("--- 4. Monte Carlo Bootstrap Simulation (%d Iterations + Slippage Jitter) ---\n", mcRuns);
   rep += StringFormat("  Probability of Profit  : %.1f%%\n", mcProbProfitPct);
   rep += StringFormat("  Net Profit 5%%..95%% CI  : [%+.2fR .. %+.2fR] (Median: %+.2fR)\n", mcNet5R, mcNet95R, mcNet50R);
   rep += StringFormat("  50th Pct Max Drawdown  : %.2fR (~%.2f%% at %.2f%% risk/trade)\n", mcDd50R, mcDd50R * InpRiskPctPerTrade, InpRiskPctPerTrade);
   rep += StringFormat("  95th Pct Max Drawdown  : %.2fR (~%.2f%% at %.2f%% risk/trade)\n", mcDd95R, mcDd95R * InpRiskPctPerTrade, InpRiskPctPerTrade);
   rep += StringFormat("  99th Pct Worst-Case DD : %.2fR (~%.2f%% at %.2f%% risk/trade)\n\n", mcDd99R, mcDd99R * InpRiskPctPerTrade, InpRiskPctPerTrade);

   rep += "--- 4. Algorithm Evolution Telemetry (MFE / MAE / POI Diagnostics) ---\n";
   rep += StringFormat("  Avg MFE across trades  : +%.2fR (Max Favorable Excursion before close)\n", avgMfeR);
   rep += StringFormat("  Avg MAE across trades  : -%.2fR (Max Adverse Excursion drawdown)\n", avgMaeR);
   rep += StringFormat("  Avg MAE on Winners     : -%.2fR (How deep winners pull back before TP)\n", avgWinMaeR);
   rep += StringFormat("  SL Hits after >=+0.8R  : %d trades (Candidates for earlier BE trigger)\n", slAfter08Mfe);
   for(int i = 0; i < 2; i++) rep += byRefinement[i].FormatRow() + "\n";
   rep += "\n";

   rep += "--- 5. Performance by Daye Day (Weekly Cycle Q1..Q4, Q0) ---\n";
   for(int i = 0; i < 5; i++) rep += byDay[i].FormatRow() + "\n";
   rep += "\n";

   rep += "--- 6. Performance by Daily Session (Asia Q1..NY PM Q4) ---\n";
   for(int i = 0; i < 4; i++) rep += bySession[i].FormatRow() + "\n";
   rep += "\n";

   rep += "--- 7. Performance by 90-Minute Cycle (Q1..Q4) ---\n";
   for(int i = 0; i < 4; i++) rep += byQ90[i].FormatRow() + "\n";
   rep += "==========================================================================================\n";

   Print(rep);

   int hOut = FileOpen(InpReportTxt, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(hOut != INVALID_HANDLE)
     {
      FileWriteString(hOut, rep);
      FileClose(hOut);
      PrintFormat("[AnalyzeBacktestCSV] Report saved to Common\\Files\\%s", InpReportTxt);
     }
  }
//+------------------------------------------------------------------+
