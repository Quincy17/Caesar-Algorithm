//+------------------------------------------------------------------+
//| Bias.mqh                                                         |
//| M6 - Multi-TF Bias (W1/D1/H4), Storyline, DOL & Roadblocks       |
//| Place in: MQL5/Include/QT/Bias.mqh                               |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Compute per-TF Bias (W1, D1, H4): BULL (+1), BEAR (-1),       |
//|    or NEUTRAL (0) on closed bars                                 |
//|  - Combine Primary Structure (last body close swing break +      |
//|    fresh HTF MSNR rejection) with Complementary Confirmation     |
//|  - Select Draw on Liquidity (DOL / 'The Objective') and          |
//|    intermediate Roadblocks (for TP / TP1 partial close)          |
//|  - Evaluate True Day Open & True Week Open Discount/Premium      |
//+------------------------------------------------------------------+
#ifndef QT_BIAS_MQH
#define QT_BIAS_MQH

#include "QT_Time.mqh"
#include "MTF_Data.mqh"
#include "Swings.mqh"
#include "MSNR_Levels.mqh"
#include "ICT_Engine.mqh"
#include "TradeProfile.mqh"

struct SDOLTarget
  {
   bool          valid;
   string        label;        // e.g. "PDH", "EQH_H1", "MSNR_H4_Classic_A"
   double        price;
   int           tfIdx;
   bool          isLiquidityPool;

   void Reset()
     {
      valid           = false;
      label           = "";
      price           = 0.0;
      tfIdx           = TF_IDX_H1;
      isLiquidityPool = true;
     }
  };

struct SDailyCycleState
  {
   bool                  isActive;
   ENUM_DAILY_CYCLE_TYPE cycleType;          // CYCLE_AMDX or CYCLE_XAMD
   ENUM_AMDX_PHASE       currentPhase;       // PHASE_A, PHASE_M, PHASE_D, PHASE_X
   ENUM_LIQ_NARRATIVE    narrative;          // NARRATIVE_ERL_TO_ERL, IRL_TO_ERL, ERL_TO_IRL
   string                phaseALabel;        // "ASIA_A" or "LONDON_A"
   double                phaseAHigh;         // Swing High of Phase A (Target for BUY)
   double                phaseALow;          // Swing Low of Phase A (Target for SELL)
   double                phaseAMid;          // 50% Equilibrium of Phase A range
   datetime              phaseAEndServer;    // Server timestamp when Phase A ended
   bool                  phaseAHighSwept;    // True if Phase A High was swept in Phase M
   bool                  phaseALowSwept;     // True if Phase A Low was swept in Phase M
   double                highSweepExtreme;   // Highest wick during Phase A High manipulation
   double                lowSweepExtreme;    // Lowest wick during Phase A Low manipulation
   datetime              highSweepTime;      // Bar timestamp of Phase A High sweep
   datetime              lowSweepTime;       // Bar timestamp of Phase A Low sweep
   ENUM_BIAS_DIR         manipulationDir;    // BIAS_BEAR (after High sweep) or BIAS_BULL (after Low sweep)
   double                activeSweepLevel;   // Swept Phase A boundary price
   double                activeSweepExtreme; // Extreme wick price of active sweep (for SL)
   datetime              activeSweepTime;    // Bar timestamp of active sweep
   double                phaseATargetPrice;  // Opposing Phase A boundary (phaseAHigh for BUY, phaseALow for SELL)

   void Reset()
     {
      isActive           = false;
      cycleType          = CYCLE_AMDX;
      currentPhase       = PHASE_NONE;
      narrative          = NARRATIVE_NONE;
      phaseALabel        = "";
      phaseAHigh         = 0.0;
      phaseALow          = 0.0;
      phaseAMid          = 0.0;
      phaseAEndServer    = 0;
      phaseAHighSwept    = false;
      phaseALowSwept     = false;
      highSweepExtreme   = 0.0;
      lowSweepExtreme    = 0.0;
      highSweepTime      = 0;
      lowSweepTime       = 0;
      manipulationDir    = BIAS_NEUTRAL;
      activeSweepLevel   = 0.0;
      activeSweepExtreme = 0.0;
      activeSweepTime    = 0;
      phaseATargetPrice  = 0.0;
     }
  };

struct SBiasState
  {
   ENUM_BIAS_DIR    biasW1;
   ENUM_BIAS_DIR    biasD1;
   ENUM_BIAS_DIR    biasH4;

   ENUM_BIAS_DIR    structW1;
   ENUM_BIAS_DIR    structD1;
   ENUM_BIAS_DIR    structH4;

   // H4 Dealing Range (most recent confirmed Swing High & Swing Low on H4)
   double           h4RangeHigh;
   double           h4RangeLow;
   double           h4Equilibrium; // 50% of H4 dealing range
   bool             isH4Discount;  // Current price < h4Equilibrium
   bool             isH4Premium;   // Current price > h4Equilibrium

   // True Open Premium / Discount Context (for Confluence Score +1 each)
   bool             isBelowTrueDayOpen;  // Discount relative to 00:00 NY
   bool             isAboveTrueDayOpen;  // Premium relative to 00:00 NY
   bool             isBelowTrueWeekOpen; // Discount relative to Mon 18:00 NY
   bool             isAboveTrueWeekOpen; // Premium relative to Mon 18:00 NY

   // Overall Trade Direction permitted by active Trade Profile Gate
   bool             allowBuy;
   bool             allowSell;
   bool             allowBuyCycle;       // v1.21: Daily AMDX/XAMD cycle-only gate (separate from HTF gate)
   bool             allowSellCycle;      // v1.21: Daily AMDX/XAMD cycle-only gate (separate from HTF gate)
   ENUM_BIAS_DIR    storylineDir;        // Dominant direction (BIAS_BULL, BIAS_BEAR, or BIAS_NEUTRAL)

   // Daily AMDX / XAMD Cycle & ERL <-> IRL Narrative State
   SDailyCycleState dailyCycle;

   // Draw on Liquidity (DOL) & Internal Roadblocks per direction
   SDOLTarget       bullDOL;             // Primary upside objective for BUY
   SDOLTarget       bullInternalTP1;     // Nearest internal upside liquidity / roadblock for 50% partial
   SDOLTarget       bearDOL;             // Primary downside objective for SELL
   SDOLTarget       bearInternalTP1;     // Nearest internal downside liquidity / roadblock for 50% partial

   void Reset()
     {
      biasW1              = BIAS_NEUTRAL;
      biasD1              = BIAS_NEUTRAL;
      biasH4              = BIAS_NEUTRAL;
      structW1            = BIAS_NEUTRAL;
      structD1            = BIAS_NEUTRAL;
      structH4            = BIAS_NEUTRAL;
      h4RangeHigh         = 0.0;
      h4RangeLow          = 0.0;
      h4Equilibrium       = 0.0;
      isH4Discount        = false;
      isH4Premium         = false;
      isBelowTrueDayOpen  = false;
      isAboveTrueDayOpen  = false;
      isBelowTrueWeekOpen = false;
      isAboveTrueWeekOpen = false;
      allowBuy            = false;
      allowSell           = false;
      allowBuyCycle       = false;
      allowSellCycle      = false;
      storylineDir        = BIAS_NEUTRAL;
      dailyCycle.Reset();
      bullDOL.Reset();
      bullInternalTP1.Reset();
      bearDOL.Reset();
      bearInternalTP1.Reset();
     }
  };

//+------------------------------------------------------------------+
//| CBiasEngine Class                                                |
//+------------------------------------------------------------------+
class CBiasEngine
  {
private:
   bool              m_strictConfirm; // If true, strict complementary conflict forces NEUTRAL
   SBiasState        m_state;

   //+------------------------------------------------------------------+
   //| Determine Structure Direction on a TF from Closed-Bar Body Break |
   //| of Recent Wick/Body Swings                                       |
   //+------------------------------------------------------------------+
   static ENUM_BIAS_DIR ComputeStructureDir(const MqlRates &rates[],
                                            const int ratesCount,
                                            CSwingEngine &swings,
                                            const int tfIdx)
     {
      if(ratesCount < 3)
         return BIAS_NEUTRAL;

      SSwingPoint lastHigh, lastLow;
      bool hasHigh = swings.GetLatestWickSwingByType(tfIdx, SWING_HIGH, lastHigh, 2);
      bool hasLow  = swings.GetLatestWickSwingByType(tfIdx, SWING_LOW,  lastLow,  2);

      if(!hasHigh && !hasLow)
         return BIAS_NEUTRAL;

      // Scan closed bars from older to newest (shift 1 = index 0) to find the most recent body close break
      datetime lastBullBreakTime = 0;
      datetime lastBearBreakTime = 0;

      int scanBars = MathMin(ratesCount - 1, 60);
      for(int i = scanBars; i >= 0; i--)
        {
         // Find most recent swing high & low confirmed prior to bar i
         for(int s = 0; s < swings.GetWickSwingCount(tfIdx); s++)
           {
            SSwingPoint sp;
            if(!swings.GetWickSwing(tfIdx, s, sp))
               continue;
            if(sp.confirmTime >= rates[i].time)
               continue;

            if(sp.type == SWING_HIGH && rates[i].close > sp.price)
              {
               if(rates[i].time > lastBullBreakTime)
                  lastBullBreakTime = rates[i].time;
               break;
              }
           }

         for(int s = 0; s < swings.GetWickSwingCount(tfIdx); s++)
           {
            SSwingPoint sp;
            if(!swings.GetWickSwing(tfIdx, s, sp))
               continue;
            if(sp.confirmTime >= rates[i].time)
               continue;

            if(sp.type == SWING_LOW && rates[i].close < sp.price)
              {
               if(rates[i].time > lastBearBreakTime)
                  lastBearBreakTime = rates[i].time;
               break;
              }
           }
        }

      if(lastBullBreakTime > lastBearBreakTime)
         return BIAS_BULL;
      if(lastBearBreakTime > lastBullBreakTime)
         return BIAS_BEAR;

      // Fallback: compare latest closed price against midpoint of most recent Swing High & Swing Low
      if(hasHigh && hasLow)
        {
         double mid = (lastHigh.price + lastLow.price) * 0.5;
         if(rates[0].close > lastHigh.price) return BIAS_BULL;
         if(rates[0].close < lastLow.price)  return BIAS_BEAR;
         return (rates[0].close >= mid ? BIAS_BULL : BIAS_BEAR);
        }

      return BIAS_NEUTRAL;
     }

   //--- Check if price is currently inside or rejecting a fresh HTF MSNR Body-to-Wick Zone on tfIdx
   static ENUM_BIAS_DIR CheckFreshMSNRRejection(CMSNREngine &msnr,
                                                const int tfIdx,
                                                const MqlRates &latestM5Bar)
     {
      int cnt = msnr.GetLevelCount(tfIdx);
      double curClose = latestM5Bar.close;
      double curHigh  = latestM5Bar.high;
      double curLow   = latestM5Bar.low;

      for(int i = 0; i < cnt; i++)
        {
         SMSNRLevel lvl;
         if(!msnr.GetLevel(tfIdx, i, lvl))
            continue;
         if(!lvl.IsFreshForEntry(3))
            continue;

         // 1. Price is currently inside the HTF Body-to-Wick Zone (and not closed beyond distal wick)
         bool inZone = (curLow <= lvl.zoneHigh && curHigh >= lvl.zoneLow);
         if(inZone)
           {
            if(lvl.direction == BIAS_BULL && curClose >= lvl.zoneLow)
               return BIAS_BULL;
            if(lvl.direction == BIAS_BEAR && curClose <= lvl.zoneHigh)
               return BIAS_BEAR;
           }

         // 2. Or HTF bar recently touched & rejected the level (shift 1..3)
         if(lvl.touchClosedShift >= 1 && lvl.touchClosedShift <= 3)
           {
            if(lvl.direction == BIAS_BULL && curClose >= lvl.price)
               return BIAS_BULL;
            if(lvl.direction == BIAS_BEAR && curClose <= lvl.price)
               return BIAS_BEAR;
           }
        }
      return BIAS_NEUTRAL;
     }

   //+------------------------------------------------------------------+
   //| Select DOL (Draw on Liquidity) & Internal TP1 Roadblock          |
   //+------------------------------------------------------------------+
   static void       SelectDOLForDirection(const ENUM_BIAS_DIR dir,
                                           const double currentPrice,
                                           const double minTargetDist,
                                           CICTEngine &ict,
                                           CMSNREngine &msnr,
                                           SDOLTarget &outInternalTP1,
                                           SDOLTarget &outPrimaryDOL)
     {
      outInternalTP1.Reset();
      outPrimaryDOL.Reset();

      double nearestDist = DBL_MAX;
      double bestDolDist = DBL_MAX;

      // 1. Scan Liquidity Pools (PDH/PDL, PWH/PWL, Session H/L, EQH/EQL, HTF Swings)
      int poolCnt = ict.GetPoolCount();
      for(int i = 0; i < poolCnt; i++)
        {
         SLiquidityPool p;
         if(!ict.GetPool(i, p))
            continue;
         if(p.isSwept || p.isBroken)
            continue;

         if(dir == BIAS_BULL && p.isBuySide && p.price > currentPrice + minTargetDist * 0.3)
           {
            double d = p.price - currentPrice;
            if(d < nearestDist)
              {
               nearestDist                    = d;
               outInternalTP1.valid           = true;
               outInternalTP1.price           = p.price;
               outInternalTP1.tfIdx           = p.tfIdx;
               outInternalTP1.label           = QTLiqPoolTypeToString(p.type) + "_" + QTTfIndexToString(p.tfIdx);
               outInternalTP1.isLiquidityPool = true;
              }
            if(d >= minTargetDist && (p.IsMajorPool() || p.tfIdx <= TF_IDX_H1) && d < bestDolDist)
              {
               bestDolDist                   = d;
               outPrimaryDOL.valid           = true;
               outPrimaryDOL.price           = p.price;
               outPrimaryDOL.tfIdx           = p.tfIdx;
               outPrimaryDOL.label           = QTLiqPoolTypeToString(p.type) + "_" + QTTfIndexToString(p.tfIdx);
               outPrimaryDOL.isLiquidityPool = true;
              }
           }
         else if(dir == BIAS_BEAR && !p.isBuySide && p.price < currentPrice - minTargetDist * 0.3)
           {
            double d = currentPrice - p.price;
            if(d < nearestDist)
              {
               nearestDist                    = d;
               outInternalTP1.valid           = true;
               outInternalTP1.price           = p.price;
               outInternalTP1.tfIdx           = p.tfIdx;
               outInternalTP1.label           = QTLiqPoolTypeToString(p.type) + "_" + QTTfIndexToString(p.tfIdx);
               outInternalTP1.isLiquidityPool = true;
              }
            if(d >= minTargetDist && (p.IsMajorPool() || p.tfIdx <= TF_IDX_H1) && d < bestDolDist)
              {
               bestDolDist                   = d;
               outPrimaryDOL.valid           = true;
               outPrimaryDOL.price           = p.price;
               outPrimaryDOL.tfIdx           = p.tfIdx;
               outPrimaryDOL.label           = QTLiqPoolTypeToString(p.type) + "_" + QTTfIndexToString(p.tfIdx);
               outPrimaryDOL.isLiquidityPool = true;
              }
           }
        }

      // 2. Scan Opposing Fresh MSNR Levels (W1, D1, H4, H1) as Roadblocks & Objective Candidates
      for(int tf = TF_IDX_W1; tf <= TF_IDX_H1; tf++)
        {
         int lCnt = msnr.GetLevelCount(tf);
         for(int i = 0; i < lCnt; i++)
           {
            SMSNRLevel lvl;
            if(!msnr.GetLevel(tf, i, lvl))
               continue;
            if(lvl.status != POI_STATUS_FRESH)
               continue;

            // Opposing level for BUY is a Resistance level (direction == BIAS_BEAR) above currentPrice
            if(dir == BIAS_BULL && lvl.direction == BIAS_BEAR && lvl.price > currentPrice + minTargetDist * 0.3)
              {
               double d = lvl.price - currentPrice;
               if(d < nearestDist)
                 {
                  nearestDist                    = d;
                  outInternalTP1.valid           = true;
                  outInternalTP1.price           = lvl.price;
                  outInternalTP1.tfIdx           = tf;
                  outInternalTP1.label           = "MSNR_" + QTTfIndexToString(tf) + "_" + QTPOITypeToString(lvl.type);
                  outInternalTP1.isLiquidityPool = false;
                 }
               if(d >= minTargetDist && d < bestDolDist)
                 {
                  bestDolDist                   = d;
                  outPrimaryDOL.valid           = true;
                  outPrimaryDOL.price           = lvl.price;
                  outPrimaryDOL.tfIdx           = tf;
                  outPrimaryDOL.label           = "MSNR_" + QTTfIndexToString(tf) + "_" + QTPOITypeToString(lvl.type);
                  outPrimaryDOL.isLiquidityPool = false;
                 }
              }
            else if(dir == BIAS_BEAR && lvl.direction == BIAS_BULL && lvl.price < currentPrice - minTargetDist * 0.3)
              {
               double d = currentPrice - lvl.price;
               if(d < nearestDist)
                 {
                  nearestDist                    = d;
                  outInternalTP1.valid           = true;
                  outInternalTP1.price           = lvl.price;
                  outInternalTP1.tfIdx           = tf;
                  outInternalTP1.label           = "MSNR_" + QTTfIndexToString(tf) + "_" + QTPOITypeToString(lvl.type);
                  outInternalTP1.isLiquidityPool = false;
                 }
               if(d >= minTargetDist && d < bestDolDist)
                 {
                  bestDolDist                   = d;
                  outPrimaryDOL.valid           = true;
                  outPrimaryDOL.price           = lvl.price;
                  outPrimaryDOL.tfIdx           = tf;
                  outPrimaryDOL.label           = "MSNR_" + QTTfIndexToString(tf) + "_" + QTPOITypeToString(lvl.type);
                  outPrimaryDOL.isLiquidityPool = false;
                 }
              }
           }
        }

      // If no extended DOL found beyond minTargetDist, fall back to nearest internal target
      if(!outPrimaryDOL.valid && outInternalTP1.valid)
         outPrimaryDOL = outInternalTP1;
     }

   //+------------------------------------------------------------------+
   //| Evaluate a Single Phase A Range [aStartSrv, aEndSrv) & Post-A    |
   //| Manipulation Sweeps (Phase M) and Distribution (Phase D)         |
   //+------------------------------------------------------------------+
   static bool       EvaluatePhaseARangeSweep(const MqlRates &m5Rates[],
                                              const int m5Cnt,
                                              const datetime aStartSrv,
                                              const datetime aEndSrv,
                                              const ENUM_DAILY_CYCLE_TYPE cycType,
                                              const string label,
                                              const double atrH1,
                                              SDailyCycleState &outCycle)
     {
      outCycle.Reset();
      if(m5Cnt <= 2 || aEndSrv <= aStartSrv || m5Rates[0].time < aEndSrv)
         return false;

      double aHigh  = -DBL_MAX;
      double aLow   =  DBL_MAX;
      int    aBars  = 0;

      for(int i = m5Cnt - 1; i >= 0; i--)
        {
         if(m5Rates[i].time >= aStartSrv && m5Rates[i].time < aEndSrv)
           {
            if(m5Rates[i].high > aHigh) aHigh = m5Rates[i].high;
            if(m5Rates[i].low  < aLow)  aLow  = m5Rates[i].low;
            aBars++;
           }
        }

      if(aBars < 4 || aHigh <= aLow)
         return false;

      double aRange = aHigh - aLow;
      double aMid   = (aHigh + aLow) * 0.5;

      outCycle.cycleType       = cycType;
      outCycle.phaseALabel     = label;
      outCycle.phaseAHigh      = aHigh;
      outCycle.phaseALow       = aLow;
      outCycle.phaseAMid       = aMid;
      outCycle.phaseAEndServer = aEndSrv;

      // Scan closed M5 bars from aEndSrv forward to newest closed bar (index 0)
      bool     hiSwept         = false;
      bool     loSwept         = false;
      double   hiExtreme       = aHigh;
      double   loExtreme       = aLow;
      datetime hiSweepTime     = 0;
      datetime loSweepTime     = 0;
      bool     hiTargetReached = false;
      bool     loTargetReached = false;

      for(int i = m5Cnt - 1; i >= 0; i--)
        {
         if(m5Rates[i].time < aEndSrv)
            continue;

         // 1. Check Buy-Side ERL Sweep (above Phase A High -> Bearish Manipulation)
         if(m5Rates[i].high > aHigh)
           {
            if(!hiSwept || hiTargetReached)
              {
               hiSwept         = true;
               hiTargetReached = false;
               hiExtreme       = m5Rates[i].high;
               hiSweepTime     = m5Rates[i].time;
              }
            else if(m5Rates[i].high >= hiExtreme)
              {
               hiExtreme   = m5Rates[i].high;
               hiSweepTime = m5Rates[i].time;
              }
           }
         else if(hiSwept && m5Rates[i].low <= aLow)
           {
            // Full ERL-to-ERL move from Phase A High to Phase A Low already completed
            hiTargetReached = true;
           }

         // 2. Check Sell-Side ERL Sweep (below Phase A Low -> Bullish Manipulation)
         if(m5Rates[i].low < aLow)
           {
            if(!loSwept || loTargetReached)
              {
               loSwept         = true;
               loTargetReached = false;
               loExtreme       = m5Rates[i].low;
               loSweepTime     = m5Rates[i].time;
              }
            else if(m5Rates[i].low <= loExtreme)
              {
               loExtreme   = m5Rates[i].low;
               loSweepTime = m5Rates[i].time;
              }
           }
         else if(loSwept && m5Rates[i].high >= aHigh)
           {
            // Full ERL-to-ERL move from Phase A Low to Phase A High already completed
            loTargetReached = true;
           }
        }

      double curClose   = m5Rates[0].close;
      double maxExcur   = MathMax(aRange * 0.85, 1.50 * MathMax(5.0, atrH1));

      bool validBearManip = (hiSwept && !hiTargetReached &&
                             (hiExtreme - aHigh) <= maxExcur &&
                             curClose <= aHigh + 0.25 * MathMax(4.0, atrH1) &&
                             curClose >  aLow  + 0.25 * aRange);

      bool validBullManip = (loSwept && !loTargetReached &&
                             (aLow - loExtreme) <= maxExcur &&
                             curClose >= aLow  - 0.25 * MathMax(4.0, atrH1) &&
                             curClose <  aHigh - 0.25 * aRange);

      outCycle.phaseAHighSwept  = validBearManip;
      outCycle.phaseALowSwept   = validBullManip;
      outCycle.highSweepExtreme = hiExtreme;
      outCycle.lowSweepExtreme  = loExtreme;
      outCycle.highSweepTime    = hiSweepTime;
      outCycle.lowSweepTime     = loSweepTime;

      if(!validBearManip && !validBullManip)
         return false;

      // If both sides were swept and neither target reached, choose the most recent manipulation
      ENUM_BIAS_DIR chosenDir = BIAS_NEUTRAL;
      if(validBearManip && validBullManip)
         chosenDir = (hiSweepTime >= loSweepTime ? BIAS_BEAR : BIAS_BULL);
      else if(validBearManip)
         chosenDir = BIAS_BEAR;
      else
         chosenDir = BIAS_BULL;

      outCycle.isActive        = true;
      outCycle.manipulationDir = chosenDir;

      if(chosenDir == BIAS_BEAR)
        {
         outCycle.activeSweepLevel   = aHigh;
         outCycle.activeSweepExtreme = hiExtreme;
         outCycle.activeSweepTime    = hiSweepTime;
         outCycle.phaseATargetPrice  = aLow;  // SELL targets Phase A Swing Low!

         int barsSinceSweep = (int)((m5Rates[0].time - hiSweepTime) / 300);
         if(barsSinceSweep <= 12 || curClose >= aHigh - 0.30 * aRange)
            outCycle.currentPhase = PHASE_M;  // Manipulation Extreme Top Entry
         else
            outCycle.currentPhase = PHASE_D;  // Distribution Pullback Entry
        }
      else
        {
         outCycle.activeSweepLevel   = aLow;
         outCycle.activeSweepExtreme = loExtreme;
         outCycle.activeSweepTime    = loSweepTime;
         outCycle.phaseATargetPrice  = aHigh; // BUY targets Phase A Swing High!

         int barsSinceSweep = (int)((m5Rates[0].time - loSweepTime) / 300);
         if(barsSinceSweep <= 12 || curClose <= aLow + 0.30 * aRange)
            outCycle.currentPhase = PHASE_M;  // Manipulation Extreme Bottom Entry
         else
            outCycle.currentPhase = PHASE_D;  // Distribution Pullback Entry
        }

      outCycle.narrative = (outCycle.currentPhase == PHASE_M ? NARRATIVE_ERL_TO_ERL : NARRATIVE_IRL_TO_ERL);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Master Evaluator: AMDX vs XAMD Daily Cycle & ERL <-> IRL         |
   //+------------------------------------------------------------------+
   static void       EvaluateDailyCycleAndNarrative(const MqlRates &m5Rates[],
                                                    const int m5Cnt,
                                                    const QTState &qtState,
                                                    const double atrH1,
                                                    SDailyCycleState &outState)
     {
      outState.Reset();
      if(m5Cnt <= 2 || qtState.dayeDayStartNY <= 0)
         return;

      datetime dayStartSrv = (datetime)((long)qtState.dayeDayStartNY - (long)qtState.nyOffsetFromServer);
      datetime q1StartSrv  = dayStartSrv;                        // 18:00 NY (Asia Q1)
      datetime q1EndSrv    = (datetime)((long)dayStartSrv + 6 * 3600);  // 00:00 NY (London Q2 start)
      datetime q2StartSrv  = q1EndSrv;
      datetime q2EndSrv    = (datetime)((long)dayStartSrv + 12 * 3600); // 06:00 NY (NY AM Q3 start)

      // 1. Evaluate Standard AMDX Cycle (Phase A = Q1 Asia [18:00 - 00:00 NY))
      SDailyCycleState amdxCycle;
      bool hasAmdx = EvaluatePhaseARangeSweep(m5Rates, m5Cnt, q1StartSrv, q1EndSrv,
                                              CYCLE_AMDX, "ASIA_A", atrH1, amdxCycle);

      // 2. When in NY AM (Q3) or NY PM (Q4), also evaluate Shifted XAMD Cycle (Phase A = Q2 London [00:00 - 06:00 NY))
      SDailyCycleState xamdCycle;
      bool hasXamd = false;
      if(qtState.session >= QT_SESSION_NY_AM)
        {
         hasXamd = EvaluatePhaseARangeSweep(m5Rates, m5Cnt, q2StartSrv, q2EndSrv,
                                            CYCLE_XAMD, "LONDON_A", atrH1, xamdCycle);
        }

      if(hasAmdx && hasXamd)
        {
         // If both Asia and London sweeps align in the same direction, merge for widest Phase A target & safest SL extreme
         if(amdxCycle.manipulationDir == xamdCycle.manipulationDir)
           {
            outState = xamdCycle;
            if(outState.manipulationDir == BIAS_BULL)
              {
               outState.activeSweepExtreme = MathMin(amdxCycle.activeSweepExtreme, xamdCycle.activeSweepExtreme);
               outState.phaseAHigh         = MathMax(amdxCycle.phaseAHigh, xamdCycle.phaseAHigh);
               outState.phaseATargetPrice  = outState.phaseAHigh;
              }
            else
              {
               outState.activeSweepExtreme = MathMax(amdxCycle.activeSweepExtreme, xamdCycle.activeSweepExtreme);
               outState.phaseALow          = MathMin(amdxCycle.phaseALow, xamdCycle.phaseALow);
               outState.phaseATargetPrice  = outState.phaseALow;
              }
           }
         else
           {
            // Prefer the fresher manipulation sweep (typically NY AM manipulation of London range in XAMD)
            outState = (xamdCycle.activeSweepTime >= amdxCycle.activeSweepTime ? xamdCycle : amdxCycle);
           }
        }
      else if(hasXamd)
         outState = xamdCycle;
      else if(hasAmdx)
         outState = amdxCycle;
      else
        {
         // Even if no Phase A sweep is active yet, set baseline narrative & phase
         outState.cycleType    = CYCLE_AMDX;
         outState.currentPhase = (qtState.session == QT_SESSION_ASIA   ? PHASE_A :
                                 (qtState.session == QT_SESSION_LONDON ? PHASE_M :
                                 (qtState.session == QT_SESSION_NY_AM  ? PHASE_D : PHASE_X)));
         outState.narrative    = NARRATIVE_IRL_TO_ERL;
        }
     }

public:
                     CBiasEngine()
     {
      m_strictConfirm = false;
      m_state.Reset();
     }

   void              Init(const bool strictComplementaryConfirm = false)
     {
      m_strictConfirm = strictComplementaryConfirm;
      m_state.Reset();
     }

   SBiasState        GetState() const { return m_state; }

   //+------------------------------------------------------------------+
   //| Update Multi-TF Bias, Storyline & DOL on Closed Bars             |
   //+------------------------------------------------------------------+
   SBiasState        Update(CMTFDataManager &mtf,
                            CSwingEngine &swings,
                            CMSNREngine &msnr,
                            CICTEngine &ict,
                            const QTState &qtState,
                            const STradeProfileSpec &profileSpec)
     {
      m_state.Reset();

      MqlRates w1Rates[], d1Rates[], h4Rates[], m5Rates[];
      int w1Cnt = mtf.GetClosedRatesArray(TF_IDX_W1, w1Rates);
      int d1Cnt = mtf.GetClosedRatesArray(TF_IDX_D1, d1Rates);
      int h4Cnt = mtf.GetClosedRatesArray(TF_IDX_H4, h4Rates);
      int m5Cnt = mtf.GetClosedRatesArray(TF_IDX_M5, m5Rates);

      if(m5Cnt <= 0)
         return m_state;

      double curClose = m5Rates[0].close;

      // 1. Primary Structure Direction (W1, D1, H4)
      m_state.structW1 = ComputeStructureDir(w1Rates, w1Cnt, swings, TF_IDX_W1);
      m_state.structD1 = ComputeStructureDir(d1Rates, d1Cnt, swings, TF_IDX_D1);
      m_state.structH4 = ComputeStructureDir(h4Rates, h4Cnt, swings, TF_IDX_H4);

      // Incorporate fresh HTF MSNR Zone rejection (MSNR Storyline starts at Fresh HTF SNR!)
      ENUM_BIAS_DIR rejW1 = CheckFreshMSNRRejection(msnr, TF_IDX_W1, m5Rates[0]);
      ENUM_BIAS_DIR rejD1 = CheckFreshMSNRRejection(msnr, TF_IDX_D1, m5Rates[0]);
      ENUM_BIAS_DIR rejH4 = CheckFreshMSNRRejection(msnr, TF_IDX_H4, m5Rates[0]);

      if(rejW1 != BIAS_NEUTRAL) m_state.structW1 = rejW1;
      if(rejD1 != BIAS_NEUTRAL) m_state.structD1 = rejD1;
      if(rejH4 != BIAS_NEUTRAL && (m_state.structD1 == rejH4 || rejD1 == rejH4))
         m_state.structH4 = rejH4;

      // 2. True Open Context (True Day Open 00:00 NY & True Week Open Mon 18:00 NY)
      if(qtState.trueOpens.dayOpen.valid && qtState.trueOpens.dayOpen.price > 0.0)
        {
         m_state.isBelowTrueDayOpen = (curClose < qtState.trueOpens.dayOpen.price);
         m_state.isAboveTrueDayOpen = (curClose > qtState.trueOpens.dayOpen.price);
        }
      if(qtState.trueOpens.weekOpen.valid && qtState.trueOpens.weekOpen.price > 0.0)
        {
         m_state.isBelowTrueWeekOpen = (curClose < qtState.trueOpens.weekOpen.price);
         m_state.isAboveTrueWeekOpen = (curClose > qtState.trueOpens.weekOpen.price);
        }

      // 3. H4 Dealing Range (50% Equilibrium for Premium / Discount)
      SSwingPoint h4High, h4Low;
      if(swings.GetLatestWickSwingByType(TF_IDX_H4, SWING_HIGH, h4High, 1) &&
         swings.GetLatestWickSwingByType(TF_IDX_H4, SWING_LOW,  h4Low,  1) &&
         h4High.price > h4Low.price)
        {
         m_state.h4RangeHigh   = h4High.price;
         m_state.h4RangeLow    = h4Low.price;
         m_state.h4Equilibrium = (h4High.price + h4Low.price) * 0.5;
         m_state.isH4Discount  = (curClose <= m_state.h4Equilibrium);
         m_state.isH4Premium   = (curClose >= m_state.h4Equilibrium);
        }

      // 4. Finalize W1, D1, H4 Bias
      m_state.biasW1 = m_state.structW1;
      m_state.biasD1 = m_state.structD1;
      m_state.biasH4 = m_state.structH4;

      // If strict complementary confirmation is enabled (PRD 4.10):
      if(m_strictConfirm)
        {
         if(qtState.trueOpens.weekOpen.valid)
           {
            if(m_state.biasW1 == BIAS_BULL && !m_state.isAboveTrueWeekOpen && rejW1 != BIAS_BULL)
               m_state.biasW1 = BIAS_NEUTRAL;
            if(m_state.biasW1 == BIAS_BEAR && !m_state.isBelowTrueWeekOpen && rejW1 != BIAS_BEAR)
               m_state.biasW1 = BIAS_NEUTRAL;
           }
         if(m_state.h4Equilibrium > 0.0)
           {
            if(m_state.biasH4 == BIAS_BULL && !m_state.isH4Discount && rejH4 != BIAS_BULL)
               m_state.biasH4 = BIAS_NEUTRAL;
            if(m_state.biasH4 == BIAS_BEAR && !m_state.isH4Premium && rejH4 != BIAS_BEAR)
               m_state.biasH4 = BIAS_NEUTRAL;
           }
        }

      // 5. Evaluate Daily AMDX / XAMD Cycle & ERL <-> IRL Liquidity Narrative
      double atrH1 = MathMax(1.0, mtf.GetATR(TF_IDX_H1));
      EvaluateDailyCycleAndNarrative(m5Rates, m5Cnt, qtState, atrH1, m_state.dailyCycle);
      if(m_state.dailyCycle.narrative == NARRATIVE_NONE)
        {
         if(rejD1 != BIAS_NEUTRAL || rejH4 != BIAS_NEUTRAL)
            m_state.dailyCycle.narrative = NARRATIVE_ERL_TO_IRL;
         else
            m_state.dailyCycle.narrative = NARRATIVE_IRL_TO_ERL;
        }

      // 6. Evaluate Trade Profile Bias Gates for BUY and SELL
      m_state.allowBuy  = profileSpec.CheckBiasGate(BIAS_BULL, m_state.biasW1, m_state.biasD1, m_state.biasH4);
      m_state.allowSell = profileSpec.CheckBiasGate(BIAS_BEAR, m_state.biasW1, m_state.biasD1, m_state.biasH4);

      // MSNR Storyline Reversal Rule: When price taps a Fresh D1 MSNR Support/Resistance (or H4 aligned with D1),
      // allow setups in that HTF POI's direction (LTF Sweep + MSS + FVG will confirm the trigger)
      if(rejD1 == BIAS_BULL || (rejH4 == BIAS_BULL && m_state.biasD1 == BIAS_BULL))
         m_state.allowBuy = true;
      if(rejD1 == BIAS_BEAR || (rejH4 == BIAS_BEAR && m_state.biasD1 == BIAS_BEAR))
         m_state.allowSell = true;

      // Daily AMDX / XAMD Cycle Rule (v1.21): When Phase A High/Low has been swept in Phase M or Phase D,
      // unlock a SEPARATE cycle-only gate (allowBuyCycle / allowSellCycle) if supported by D1 or H4 structure.
      // The HTF gate (allowBuy / allowSell) is no longer modified, so pure HTF setups keep v1.12 behaviour.
      if(m_state.dailyCycle.isActive)
        {
         if(m_state.dailyCycle.manipulationDir == BIAS_BULL &&
            (m_state.biasD1 == BIAS_BULL || m_state.biasH4 == BIAS_BULL))
           {
            m_state.allowBuyCycle = true;
           }
         if(m_state.dailyCycle.manipulationDir == BIAS_BEAR &&
            (m_state.biasD1 == BIAS_BEAR || m_state.biasH4 == BIAS_BEAR))
           {
            m_state.allowSellCycle = true;
           }
        }

      if(m_state.allowBuy && !m_state.allowSell)
         m_state.storylineDir = BIAS_BULL;
      else if(m_state.allowSell && !m_state.allowBuy)
         m_state.storylineDir = BIAS_BEAR;
      else if(m_state.allowBuy && m_state.allowSell)
         m_state.storylineDir = m_state.biasH4;
      else
         m_state.storylineDir = BIAS_NEUTRAL;

      // 6. Select DOL ('The Objective') & Internal TP1 Roadblocks
      double minTargetDist = MathMax(1.0, 0.8 * mtf.GetATR(TF_IDX_H1));
      SelectDOLForDirection(BIAS_BULL, curClose, minTargetDist, ict, msnr,
                            m_state.bullInternalTP1, m_state.bullDOL);
      SelectDOLForDirection(BIAS_BEAR, curClose, minTargetDist, ict, msnr,
                            m_state.bearInternalTP1, m_state.bearDOL);

      return m_state;
     }
  };

#endif // QT_BIAS_MQH
//+------------------------------------------------------------------+
