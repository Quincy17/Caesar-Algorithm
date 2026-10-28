//+------------------------------------------------------------------+
//| TestSetupAndRisk.mq5                                             |
//| Fase 6 & Fase 7 - Unit Tests for TradeProfile, Confluence Score  |
//| and Risk Volume Normalization                                    |
//| Place in: MQL5/Scripts/TestSetupAndRisk.mq5                      |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.10"
#property strict

#include "../Include/QT/Setup.mqh"
#include "../Include/QT/Risk.mqh"

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
   Print("=== Starting Fase 6 & Fase 7 Unit Tests: TradeProfile, Setup Score & Risk ===");

   //------------------------------------------------------------------
   // 1. Trade Profile Bias Gate & Score TF Bonus (PRD 4.10)
   //------------------------------------------------------------------
   STradeProfileSpec profIntraday;
   profIntraday.Configure(PROFILE_INTRADAY, BIAS_GATE_STRICT, true, true, true);

   // Intraday Gate = D1 & H4; Score = W1
   Check(profIntraday.allowPOITF[TF_IDX_H4]  &&
         profIntraday.allowPOITF[TF_IDX_H1]  &&
         profIntraday.allowPOITF[TF_IDX_M15] &&
         profIntraday.allowPOITF[TF_IDX_M5],
         "Intraday profile allows POI on H4, H1, M15, and M5 for precision entry");

   Check(profIntraday.CheckBiasGate(BIAS_BULL, BIAS_BEAR, BIAS_BULL, BIAS_BULL),
         "Intraday STRICT Gate passes BUY when D1=BULL & H4=BULL (even if W1=BEAR)");
   Check(!profIntraday.CheckBiasGate(BIAS_BULL, BIAS_BULL, BIAS_NEUTRAL, BIAS_BULL),
         "Intraday STRICT Gate blocks BUY when D1=NEUTRAL");
   Check(profIntraday.CalcBiasScoreBonus(BIAS_BULL, BIAS_BULL, BIAS_BULL, BIAS_BULL) == 1,
         "Intraday Score TF (W1) adds +1 when W1 aligns with BUY");
   Check(profIntraday.CalcBiasScoreBonus(BIAS_BULL, BIAS_BEAR, BIAS_BULL, BIAS_BULL) == -1,
         "Intraday Score TF (W1) subtracts -1 when W1 opposes BUY");

   //------------------------------------------------------------------
   // 2. Confluence Score Calculator Verification (PRD 4.7)
   //------------------------------------------------------------------
   SSetupTracker tr;
   tr.Reset(BIAS_BULL);
   tr.anchorPOI.tfIdx       = TF_IDX_H4;   // +2 pts
   tr.anchorPOI.type        = POI_QM_BULL; // +2 pts (QM / RBS / SBR)
   tr.hasRefinedPOI         = true;
   tr.refinedPOI.tfIdx      = TF_IDX_M5;
   tr.poiOverlapCount       = 2;           // +2 pts (H4 + H1 + M5 overlap)
   tr.sweep.valid           = true;
   tr.sweep.isMajorPool     = true;        // +2 pts (EQH/EQL or PDH/PDL)
   tr.hasFvg                = true;        // +1 pt  (FVG on displacement)

   QTState qt;
   qt.Reset();
   qt.session               = QT_SESSION_NY_AM; // +1 pt (London or NY AM)
   qt.q90                   = QT_Q2;            // +1 pt (Q2 or Q3 90m block)

   SBiasState bs;
   bs.Reset();
   bs.biasW1                = BIAS_BULL;        // +1 pt (Intraday Score TF W1 aligned)
   bs.biasD1                = BIAS_BULL;
   bs.biasH4                = BIAS_BULL;
   bs.isBelowTrueDayOpen    = true;             // +1 pt (Discount vs True Day Open)
   bs.isBelowTrueWeekOpen   = true;             // +1 pt (Discount vs True Week Open)

   SConfluenceBreakdown sc;
   CSetupEngine::CalcConfluenceScore(tr, qt, bs, profIntraday, sc);

   // Expected total: 2 (H4) + 2 (QM) + 2 (Overlap) + 1 (Q90) + 1 (Session) + 1 (TDO) + 1 (TWO) + 2 (Sweep) + 1 (FVG) + 1 (W1 Score) = 14
   Check(sc.totalScore == 14,
         StringFormat("Maximum Confluence Score calculation = %d (Expected 14)", sc.totalScore));

   //------------------------------------------------------------------
   // 3. Risk Lot Size Normalization & Patented Equity-Step Lot Verification
   //------------------------------------------------------------------
   Check(MathAbs(CRiskManager::NormalizeVolume(0.158, 0.01, 100.0, 0.01) - 0.15) < 1e-6,
         "NormalizeVolume floors 0.158 to 0.15 with step 0.01");
   Check(MathAbs(CRiskManager::NormalizeVolume(0.004, 0.01, 100.0, 0.01) - 0.0) < 1e-6,
         "NormalizeVolume returns 0.0 when raw lot (0.004) is below broker minLot (0.01)");
   Check(MathAbs(CRiskManager::NormalizeVolume(150.0, 0.01, 50.0, 0.01) - 50.0) < 1e-6,
         "NormalizeVolume clamps 150.0 to maxLot 50.0");

   Check(MathAbs(CRiskManager::CalcEquityStepLot(5000.0, 5000.0, 0.05, 0.01, 100.0, 0.01) - 0.05) < 1e-6,
         "CalcEquityStepLot: $5,000 USD equity -> 0.05 lot");
   Check(MathAbs(CRiskManager::CalcEquityStepLot(10000.0, 5000.0, 0.05, 0.01, 100.0, 0.01) - 0.10) < 1e-6,
         "CalcEquityStepLot: $10,000 USD equity -> 0.10 lot");
   Check(MathAbs(CRiskManager::CalcEquityStepLot(25000.0, 5000.0, 0.05, 0.01, 100.0, 0.01) - 0.25) < 1e-6,
         "CalcEquityStepLot: $25,000 USD equity -> 0.25 lot");
   Check(MathAbs(QTPipsToPrice("XAUUSD", 100.0) - 10.0) < 1e-6 &&
         MathAbs(QTPipsToPrice("XAUUSD", 60.0)  - 6.0)  < 1e-6 &&
         MathAbs(QTPipsToPrice("XAUUSD", 300.0) - 30.0) < 1e-6,
         "QTPipsToPrice(XAUUSD): 60 pips = $6.00, 100 pips = $10.00, 300 pips = $30.00");

   PrintFormat("=== TestSetupAndRisk finished: %d PASSED, %d FAILED ===", g_pass, g_fail);
  }
//+------------------------------------------------------------------+
