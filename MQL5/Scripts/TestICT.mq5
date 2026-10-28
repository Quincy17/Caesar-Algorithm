//+------------------------------------------------------------------+
//| TestICT.mq5                                                      |
//| Fase 5 - Unit Tests for ICT_Engine.mqh                           |
//| (EQH/EQL, Liquidity Sweep, MSS, and FVG Open/Partial/Filled)     |
//| Place in: MQL5/Scripts/TestICT.mq5                               |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.10"
#property strict

#include "../Include/QT/ICT_Engine.mqh"

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
   Print("=== Starting Fase 5 Unit Tests: ICT_Engine.mqh ===");

   datetime t0 = D'2026.10.27 12:00:00';

   //------------------------------------------------------------------
   // TEST 1: EQH / EQL Cluster Detection
   //------------------------------------------------------------------
   SSwingPoint swings[];
   ArrayResize(swings, 4);
   swings[0].Reset(); swings[0].type = SWING_HIGH; swings[0].price = 2750.40; swings[0].confirmTime = t0 - 600;
   swings[1].Reset(); swings[1].type = SWING_LOW;  swings[1].price = 2700.10; swings[1].confirmTime = t0 - 1200;
   swings[2].Reset(); swings[2].type = SWING_HIGH; swings[2].price = 2750.00; swings[2].confirmTime = t0 - 1800;
   swings[3].Reset(); swings[3].type = SWING_LOW;  swings[3].price = 2700.60; swings[3].confirmTime = t0 - 2400;

   SLiquidityPool pools[];
   int poolCnt = 0;
   // With ATR=10.0 and mult=0.10 -> tolerance = 1.00 (both Highs within 0.40, both Lows within 0.50)
   CICTEngine::DetectEqualHighsLows(swings, 4, TF_IDX_H1, 10.0, 0.10, 20, pools, poolCnt);

   Check(poolCnt == 2 &&
         pools[0].type == LIQ_POOL_EQH && MathAbs(pools[0].price - 2750.40) < 1e-5 &&
         pools[1].type == LIQ_POOL_EQL && MathAbs(pools[1].price - 2700.10) < 1e-5,
         "EQH (2750.40) and EQL (2700.10) clusters accurately detected within 0.1*ATR tolerance");

   //------------------------------------------------------------------
   // TEST 2: Liquidity Sweep & MSS Confirmation
   //------------------------------------------------------------------
   MqlRates sweepBar;
   // Sell-side sweep of EQL (2700.10): bar low dips to 2698.50, closes back above at 2703.00
   SetBar(sweepBar, t0 - 300, 2702.0, 2704.0, 2698.50, 2703.00);

   SSweepEvent sweepEv;
   bool swept = CICTEngine::DetectSweepOnBar(sweepBar, 2, TF_IDX_M15, pools, poolCnt, BIAS_BULL, sweepEv);
   Check(swept && sweepEv.signalDir == BIAS_BULL && sweepEv.poolType == LIQ_POOL_EQL &&
         MathAbs(sweepEv.extremeWickPrice - 2698.50) < 1e-5 && sweepEv.isMajorPool,
         "Bullish Sell-side Sweep of EQL detected (wick=2698.50, close=2703.00 > 2700.10)");

   // Opposing Swing High prior to sweep at 2710.00; next closed bar (shift 1) closes at 2714.00 (> 2710.00) -> MSS!
   SSwingPoint oppSwings[];
   ArrayResize(oppSwings, 1);
   oppSwings[0].Reset();
   oppSwings[0].type             = SWING_HIGH;
   oppSwings[0].pivotTime        = t0 - 900;
   oppSwings[0].confirmTime      = t0 - 600;
   oppSwings[0].pivotClosedShift = 4;
   oppSwings[0].price            = 2710.00;

   MqlRates mssBars[];
   ArrayResize(mssBars, 2);
   ArraySetAsSeries(mssBars, true);
   SetBar(mssBars[1], t0 - 300, 2702.0, 2704.0, 2698.50, 2703.00); // shift 2: sweep bar
   SetBar(mssBars[0], t0,       2703.0, 2716.0, 2702.50, 2714.00); // shift 1: displacement MSS bar (close 2714 > 2710)

   SMSSResult mssRes;
   bool mssOk = CICTEngine::CheckMSSAfterSweep(mssBars, 2, oppSwings, 1, sweepEv, TF_IDX_M15, mssRes);
   Check(mssOk && mssRes.confirmed && mssRes.direction == BIAS_BULL &&
         MathAbs(mssRes.brokenSwingPrice - 2710.00) < 1e-5,
         "Bullish MSS confirmed when displacement candle closes at 2714.00 (> opposing swing 2710.00)");

   //------------------------------------------------------------------
   // TEST 3: Fair Value Gap (FVG) Detection & Mitigation Lifecycle
   //------------------------------------------------------------------
   MqlRates fvgRates[];
   ArrayResize(fvgRates, 4);
   ArraySetAsSeries(fvgRates, true);
   // Candle 1 (index 3): high = 2705.0
   // Candle 2 (index 2): big displacement up
   // Candle 3 (index 1): low = 2715.0 -> Bullish FVG [2705.0 .. 2715.0], CE = 2710.0, size = 10.0
   // Candle 4 (index 0): low dips to 2712.0 (inside [2705, 2715]) -> PARTIAL mitigation
   SetBar(fvgRates[3], t0 - 900, 2700.0, 2705.0, 2699.0, 2704.0);
   SetBar(fvgRates[2], t0 - 600, 2704.0, 2718.0, 2703.5, 2717.0);
   SetBar(fvgRates[1], t0 - 300, 2717.0, 2722.0, 2715.0, 2720.0);
   SetBar(fvgRates[0], t0,       2720.0, 2721.0, 2712.0, 2718.0);

   SFVGZone fvgs[];
   int fvgCnt = 0;

   // Check on first 3 bars (index 1..3) -> status should be OPEN
   MqlRates fvgOpenSlice[];
   ArrayResize(fvgOpenSlice, 3);
   ArraySetAsSeries(fvgOpenSlice, true);
   for(int i = 0; i < 3; i++) fvgOpenSlice[i] = fvgRates[i + 1];
   CICTEngine::ScanRatesForFVG(fvgOpenSlice, 3, TF_IDX_M5, 10.0, 0.15, 50, fvgs, fvgCnt, 10);
   Check(fvgCnt == 1 && fvgs[0].direction == BIAS_BULL && fvgs[0].status == FVG_STATUS_OPEN &&
         MathAbs(fvgs[0].proximal - 2715.0) < 1e-5 &&
         MathAbs(fvgs[0].distal   - 2705.0) < 1e-5 &&
         MathAbs(fvgs[0].ce       - 2710.0) < 1e-5,
         "Bullish FVG detected (Proximal=2715.0, CE=2710.0, Distal=2705.0, Status=OPEN)");

   // Check with 4th bar dipping to 2712.0 -> status should transition to PARTIAL
   CICTEngine::ScanRatesForFVG(fvgRates, 4, TF_IDX_M5, 10.0, 0.15, 50, fvgs, fvgCnt, 10);
   Check(fvgCnt == 1 && fvgs[0].status == FVG_STATUS_PARTIAL,
         "Bullish FVG transitions to PARTIAL when subsequent candle low (2712.0) enters gap above distal (2705.0)");

   PrintFormat("=== TestICT finished: %d PASSED, %d FAILED ===", g_pass, g_fail);
  }
//+------------------------------------------------------------------+
