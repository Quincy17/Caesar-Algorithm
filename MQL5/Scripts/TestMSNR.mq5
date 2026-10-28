//+------------------------------------------------------------------+
//| TestMSNR.mq5                                                     |
//| Fase 3 & Fase 4 - Unit Tests for MSNR_Levels.mqh                 |
//| (Classic A, Classic V, RBS, SBR, Fresh/Touched/Broken, and QM)   |
//| Place in: MQL5/Scripts/TestMSNR.mq5                              |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.10"
#property strict

#include "../Include/QT/MSNR_Levels.mqh"

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

void SetBar(MqlRates &r, const datetime t, const double o, const double h, const double l, const double c)
  {
   ZeroMemory(r);
   r.time  = t;
   r.open  = o;
   r.high  = h;
   r.low   = l;
   r.close = c;
  }

void OnStart()
  {
   Print("=== Starting Fase 3 & Fase 4 Unit Tests: MSNR_Levels.mqh ===");

   SMSNRConfig cfg;
   cfg.SetDefaults();
   cfg.touchAtrMult = 0.05; // With ATR=10 -> tolerance = 0.50

   //------------------------------------------------------------------
   // TEST 1: Classic A (Fresh) -> Broken by Body Close -> Flips to RBS (Fresh)
   //------------------------------------------------------------------
   MqlRates rates[];
   ArrayResize(rates, 9);
   ArraySetAsSeries(rates, true);
   datetime t0 = D'2026.10.27 12:00:00';

   // Chronological order from oldest (index 8) to newest (index 0):
   // p = 5: Body Swing High at close = 2720.0 (confirmed at p - 2 = 3)
   // idx = 2: Still below 2720 -> Classic A is FRESH
   SetBar(rates[8], t0 - 8 * 300, 2700, 2706, 2698, 2705);
   SetBar(rates[7], t0 - 7 * 300, 2705, 2714, 2704, 2712);
   SetBar(rates[6], t0 - 6 * 300, 2712, 2725, 2710, 2720); // <-- Pivot Classic A at close=2720
   SetBar(rates[5], t0 - 5 * 300, 2720, 2721, 2708, 2710);
   SetBar(rates[4], t0 - 4 * 300, 2710, 2712, 2702, 2705); // <-- Confirmed at idx=4
   SetBar(rates[3], t0 - 3 * 300, 2705, 2715, 2703, 2714); // Untouched (high 2715 < 2719.5)
   SetBar(rates[2], t0 - 2 * 300, 2714, 2721, 2712, 2716); // Wick high=2721 touches 2720, close=2716 <= 2720 -> TOUCHED
   SetBar(rates[1], t0 - 1 * 300, 2716, 2732, 2715, 2730); // Body close=2730 > 2720 -> BROKEN -> Spawns RBS at 2720 (FRESH)
   SetBar(rates[0], t0 - 0 * 300, 2730, 2735, 2725, 2732); // Above RBS (low=2725 > 2720.5) -> RBS remains FRESH

   SSwingPoint wickSw[], bodySw[];
   int wCnt = 0, bCnt = 0;

   // A) Check at bar idx=3 (slice of oldest 6 bars: rates[3..8]) -> Classic A should be FRESH
   MqlRates sliceFresh[];
   ArrayResize(sliceFresh, 6);
   ArraySetAsSeries(sliceFresh, true);
   for(int i = 0; i < 6; i++) sliceFresh[i] = rates[i + 3];
   CSwingEngine::ScanRatesForSwings(sliceFresh, 6, TF_IDX_H1, 2, 50, wickSw, wCnt, bodySw, bCnt);

   SMSNRLevel lvlsA[];
   int cntA = 0;
   CMSNREngine::BuildLevelsForTF(sliceFresh, 6, bodySw, bCnt, TF_IDX_H1, 10.0, 0.20, cfg, lvlsA, cntA);
   Check(cntA == 1 && lvlsA[0].type == POI_CLASSIC_A && lvlsA[0].status == POI_STATUS_FRESH &&
         MathAbs(lvlsA[0].price - 2720.0) < 1e-5,
         "Classic A detected at body close 2720.0 with status FRESH");

   // B) Check at bar idx=2 (slice of 7 bars: rates[2..8]) -> Wick touched 2721, close=2716 -> TOUCHED
   MqlRates sliceTouched[];
   ArrayResize(sliceTouched, 7);
   ArraySetAsSeries(sliceTouched, true);
   for(int i = 0; i < 7; i++) sliceTouched[i] = rates[i + 2];
   CSwingEngine::ScanRatesForSwings(sliceTouched, 7, TF_IDX_H1, 2, 50, wickSw, wCnt, bodySw, bCnt);
   CMSNREngine::BuildLevelsForTF(sliceTouched, 7, bodySw, bCnt, TF_IDX_H1, 10.0, 0.20, cfg, lvlsA, cntA);
   Check(cntA == 1 && lvlsA[0].type == POI_CLASSIC_A && lvlsA[0].status == POI_STATUS_TOUCHED,
         "Classic A transitions to TOUCHED after wick reaches 2721 without body close break");

   // C) Check full 9 bars -> Body closed at 2730 (> 2720), flipping Classic A into RBS (FRESH) at 2720.0
   CSwingEngine::ScanRatesForSwings(rates, 9, TF_IDX_H1, 2, 50, wickSw, wCnt, bodySw, bCnt);
   CMSNREngine::BuildLevelsForTF(rates, 9, bodySw, bCnt, TF_IDX_H1, 10.0, 0.20, cfg, lvlsA, cntA);
   bool foundRbsFresh = false;
   for(int i = 0; i < cntA; i++)
     {
      if(lvlsA[i].type == POI_RBS && lvlsA[i].status == POI_STATUS_FRESH &&
         MathAbs(lvlsA[i].price - 2720.0) < 1e-5 && lvlsA[i].direction == BIAS_BULL)
         foundRbsFresh = true;
     }
   Check(foundRbsFresh, "Broken Classic A flips to RBS (Support, BIAS_BULL) at 2720.0 with status FRESH");

   //------------------------------------------------------------------
   // TEST 2: Quasimodo Bullish (QM_Bull) Detection at Left Shoulder Body
   //   5-swing body sequence:
   //   - Left Shoulder (Low 1) = 2700.0
   //   - Intermediate High     = 2720.0
   //   - Head (Lower Low)      = 2685.0 (< 2700.0)
   //   - Structure Break High  = 2735.0 (> 2720.0 with body close)
   //   -> QM Bullish Level must equal 2700.0 (Left Shoulder body)
   //------------------------------------------------------------------
   MqlRates qmRates[];
   ArrayResize(qmRates, 15);
   ArraySetAsSeries(qmRates, true);
   // Build from oldest (14) to newest (0) with N=1 for compact synthetic test
   SetBar(qmRates[14], t0 - 14 * 300, 2715, 2716, 2708, 2710);
   SetBar(qmRates[13], t0 - 13 * 300, 2710, 2711, 2698, 2700); // Swing 1: Left Shoulder Low = 2700.0
   SetBar(qmRates[12], t0 - 12 * 300, 2700, 2712, 2699, 2710);
   SetBar(qmRates[11], t0 - 11 * 300, 2710, 2722, 2709, 2720); // Swing 2: Intermediate High = 2720.0
   SetBar(qmRates[10], t0 - 10 * 300, 2720, 2721, 2702, 2705);
   SetBar(qmRates[9],  t0 -  9 * 300, 2705, 2706, 2680, 2685); // Swing 3: Head Lower Low = 2685.0 (< 2700)
   SetBar(qmRates[8],  t0 -  8 * 300, 2685, 2705, 2684, 2702);
   SetBar(qmRates[7],  t0 -  7 * 300, 2702, 2718, 2701, 2715);
   SetBar(qmRates[6],  t0 -  6 * 300, 2715, 2728, 2714, 2726); // Body close 2726 > 2720 (BOS!)
   SetBar(qmRates[5],  t0 -  5 * 300, 2726, 2738, 2725, 2735); // Swing 4: BOS High = 2735.0
   SetBar(qmRates[4],  t0 -  4 * 300, 2735, 2736, 2726, 2728);
   SetBar(qmRates[3],  t0 -  3 * 300, 2728, 2730, 2720, 2722);
   SetBar(qmRates[2],  t0 -  2 * 300, 2722, 2724, 2715, 2718);
   SetBar(qmRates[1],  t0 -  1 * 300, 2718, 2720, 2712, 2715);
   SetBar(qmRates[0],  t0 -  0 * 300, 2715, 2717, 2710, 2712); // Price still above 2700 -> QM Bull is FRESH

   CSwingEngine::ScanRatesForSwings(qmRates, 15, TF_IDX_H1, 1, 50, wickSw, wCnt, bodySw, bCnt);
   SMSNRLevel qmLvls[];
   int qmCnt = 0;
   CMSNREngine::BuildLevelsForTF(qmRates, 15, bodySw, bCnt, TF_IDX_H1, 10.0, 0.20, cfg, qmLvls, qmCnt);

   bool foundQmBull = false;
   for(int i = 0; i < qmCnt; i++)
     {
      if(qmLvls[i].type == POI_QM_BULL &&
         qmLvls[i].status == POI_STATUS_FRESH &&
         MathAbs(qmLvls[i].price - 2700.0) < 1e-5 &&
         MathAbs(qmLvls[i].qmHeadPrice - 2685.0) < 1e-5)
        {
         foundQmBull = true;
         break;
        }
     }
   Check(foundQmBull, "QM Bullish detected at Left Shoulder body price 2700.0 (Head=2685.0) with status FRESH");

   PrintFormat("=== TestMSNR finished: %d PASSED, %d FAILED ===", g_pass, g_fail);
  }
//+------------------------------------------------------------------+
