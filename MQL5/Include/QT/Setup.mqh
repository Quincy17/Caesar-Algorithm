//+------------------------------------------------------------------+
//| Setup.mqh                                                        |
//| M7 - Setup State Machine (S0..S6), M15/M5 POI Refinement & Score |
//| Place in: MQL5/Include/QT/Setup.mqh                              |
//|                                                                  |
//| State Machine Architecture (v1.21):                              |
//|  1. HTF Anchor Trackers (m_buyHtf / m_sellHtf):                  |
//|     - Dedicated to D1, H4, H1 MSNR Anchor POIs                   |
//|     - Retains 100% v1.12 logic (+$959.98 net profit)             |
//|  2. Daily Cycle Trackers (m_buyCycle / m_sellCycle):             |
//|     - Dedicated to AMDX / XAMD Phase M & Phase D Daily Engine    |
//|     - M15 POI Anchor only (M5 excluded)                          |
//|     - Strict Phase M: Q3 only, D1 bias aligned, range >= 115 p   |
//|     - Phase D & IRL->ERL as main daily entry engine              |
//|     - Mon & Fri open exclusively for Phase D entries             |
//+------------------------------------------------------------------+
#ifndef QT_SETUP_MQH
#define QT_SETUP_MQH

#include "Bias.mqh"

struct SSetupConfig
  {
   int                    minConfluenceScore; // Default 6
   double                 customMinRR;        // 0.0 = use profile default (1.5 / 2.0 / 3.0)
   int                    maxSetupBarsM5;     // Max age of setup in M5 bars (default 36 = 3 hours)
   ENUM_ENTRY_TYPE        entryType;          // ENTRY_FVG_CE (default), ENTRY_FVG_PROXIMAL, ENTRY_MARKET_MSS
   ENUM_CONFIRMATION_MODE confirmMode;        // CONFIRM_MODE_EITHER (default), CONFIRM_MODE_CISD_ONLY, CONFIRM_MODE_MSS_ONLY
   bool                   enableSniperEntry;  // Enable Fresh POI above BSL / below SSL (default true)
   double                 slBufferAtrMultM5;  // SL buffer = mult * ATR(M5) + spread (default 0.20)
   double                 maxSlAtrMultH1;     // Max SL width = mult * ATR(H1) (default 2.50)
   bool                   useM15M5Refinement; // Enable M15/M5 MSNR POI refinement for sharper entry
   double                 targetSlPips;       // Default manual SL distance = 60.0 pips ($6.00 on XAUUSD)
   double                 minSlPips;          // Minimum SL distance = 45.0 pips ($4.50 on XAUUSD)
   double                 maxSlPips;          // Maximum structural SL distance = 75.0 pips ($7.50 on XAUUSD)
   double                 partialTp1Pips;     // Mandatory Partial TP1 + BE distance = 100.0 pips ($10.00 on XAUUSD)
   double                 runnerTpPips;       // Default Full TP Runner distance = 300.0 pips ($30.00 on XAUUSD)
   bool                   enableDailyAmdxCycle;// Enable Daily AMDX/XAMD Phase M & Phase D Entry Engine (Default true)
   // Scalping specific parameters (v1.32)
   bool                       scalpAllowThursday; // Allow scalping on Thursdays (default false)
   ENUM_SCALP_SESSION_FILTER  scalpSessionMode;   // Scalping session filter (default SCALP_SESS_LONDON_ONLY)
   bool                       scalpFilterWeakPoi; // Filter M15_RBS & M15_Classic_V if score < 12 (default true)
   bool                       scalpUseEarlyBE;    // Stage-0.5 Early Defense (default true)
   double                     scalpEarlyBePips;   // Early BE distance = 30.0 pips ($3.00 on XAUUSD)
   double                     scalpEarlyBeBufferPts;// Buffer for early BE = 5.0 points
   double                     scalpSlPips;        // Scalping SL distance = 45.0 pips ($4.50 on XAUUSD)
   double                     scalpBePips;        // Scalping BE trigger = 45.0 pips ($4.50 on XAUUSD)
   double                     scalpPartialPips;   // Scalping Partial trigger = 45.0 pips ($4.50 on XAUUSD)
   double                     scalpPartialRatio;  // Scalping Partial lot ratio = 0.30 (30% lot, 70% runner)
   double                     scalpTpPips;        // Scalping max TP distance = 100.0 pips ($10.00 on XAUUSD)

   void SetDefaults()
     {
      minConfluenceScore   = 6;
      customMinRR          = 0.0;
      maxSetupBarsM5       = 36;
      entryType            = ENTRY_FVG_CE;
      confirmMode          = CONFIRM_MODE_EITHER;
      enableSniperEntry    = true;
      slBufferAtrMultM5    = 0.20;
      maxSlAtrMultH1       = 2.50;
      useM15M5Refinement   = true;
      targetSlPips         = 60.0;
      minSlPips            = 45.0;
      maxSlPips            = 75.0;
      partialTp1Pips       = 100.0;
      runnerTpPips         = 300.0;
      enableDailyAmdxCycle = true;
      scalpAllowThursday   = false;
      scalpSessionMode     = SCALP_SESS_LONDON_Q3_ONLY;
      scalpFilterWeakPoi   = true;
      scalpUseEarlyBE      = true;
      scalpEarlyBePips     = 30.0;
      scalpEarlyBeBufferPts= 5.0;
      scalpSlPips          = 45.0;
      scalpBePips          = 45.0;
      scalpPartialPips     = 45.0;
      scalpPartialRatio    = 0.30;
      scalpTpPips          = 100.0;
     }
  };

struct SConfluenceBreakdown
  {
   int ptsPoiTF;          // W1/D1=3, H4=2, H1=1, M15/M5=1
   int ptsPoiType;        // QM or RBS/SBR=2, Classic A/V=1
   int ptsPoiOverlap;     // +1 per overlapping TF (max +2)
   int ptsQ90;            // +1 if Q2 or Q3 90-minute block
   int ptsSession;        // +1 if London Q2 or NY AM Q3
   int ptsTrueDayOpen;    // +1 if Discount (Buy) / Premium (Sell) vs True Day Open
   int ptsTrueWeekOpen;   // +1 if Discount (Buy) / Premium (Sell) vs True Week Open
   int ptsSweep;          // +2 if EQH/EQL, PDH/PDL, or Session Extreme (+1 minor swing)
   int ptsSniper;         // +2 if Sniper Entry (Fresh HTF POI above BSL / below SSL)
   int ptsFvg;            // +1 if FVG present on displacement leg
   int ptsBiasScoreTF;    // +1/-1 per Score TF from Trade Profile
   int totalScore;

   void Reset()
     {
      ptsPoiTF        = 0;
      ptsPoiType      = 0;
      ptsPoiOverlap   = 0;
      ptsQ90          = 0;
      ptsSession      = 0;
      ptsTrueDayOpen  = 0;
      ptsTrueWeekOpen = 0;
      ptsSweep        = 0;
      ptsSniper       = 0;
      ptsFvg          = 0;
      ptsBiasScoreTF  = 0;
      totalScore      = 0;
     }
  };

struct SSetupTracker
  {
   string               setupId;
   ENUM_TRADE_PROFILE   profile;          // PROFILE_SCALPING, PROFILE_INTRADAY, or PROFILE_SWING
   ENUM_BIAS_DIR        direction;        // BIAS_BULL (Buy) or BIAS_BEAR (Sell)
   ENUM_SETUP_STATE     state;            // S0_IDLE .. S6_DONE
   datetime             createdTime;      // Server time when S1_POI_TOUCH started
   datetime             armedTime;        // Server time when S4_ARMED was reached
   datetime             lastM5BarTime;    // For tracking age in M5 bars
   int                  ageBarsM5;        // Number of M5 bars elapsed since S1_POI_TOUCH

   // Layer 1: QT Time & Daily AMDX/XAMD Narrative Snapshot at trigger
   ENUM_QT_QUARTER      weekQ;
   ENUM_QT_QUARTER      dayQ;
   ENUM_QT_SESSION      session;
   ENUM_QT_QUARTER      q90;
   bool                 isDailyCycleSetup; // True if triggered by AMDX/XAMD Phase M / Phase D daily engine
   ENUM_DAILY_CYCLE_TYPE cycleType;        // CYCLE_AMDX or CYCLE_XAMD
   ENUM_AMDX_PHASE      amdxPhase;         // PHASE_M (Manipulation Extreme) or PHASE_D (Distribution)
   ENUM_LIQ_NARRATIVE   narrative;         // NARRATIVE_ERL_TO_ERL, IRL_TO_ERL, ERL_TO_IRL

   // Layer 2: MSNR POI (HTF Anchor + optional M15/M5 Refinement)
   SMSNRLevel           anchorPOI;        // Primary touched POI (e.g. H4/H1 or M15)
   bool                 hasRefinedPOI;    // True if a nested M15/M5 fresh POI refined the zone
   SMSNRLevel           refinedPOI;       // M15/M5 refined MSNR POI
   int                  poiOverlapCount;  // Multi-TF overlap count

   // Layer 3: ICT Sweep, MSS, CISD & FVG
   SSweepEvent          sweep;
   SMSSResult           mss;
   bool                 isCisdConfirmed;  // True if confirmed via CISD (v1.31)
   SCISDResult          cisd;             // CISD data (v1.31)
   bool                 isSniperSetup;    // True if Fresh POI above BSL / below SSL (v1.31)
   bool                 hasFvg;
   SFVGZone             fvg;

   // Calculated Order Parameters (Valid at S4_ARMED)
   bool                 isMarketOrder;
   double               entryPrice;
   double               slPrice;
   double               tpPrice;
   double               tp1Price;         // Internal liquidity roadblock for 50% partial close
   string               dolLabel;
   double               rrRatio;

   // Confluence Score & Rejection Tracking
   SConfluenceBreakdown score;
   string               statusNote;       // Reason for rejection / cancellation if any
   bool                 loggedToCsv;      // True once setup evaluation was written to Setups_Log.csv
   ulong                orderTicket;      // Pending order or position ticket when placed

   void Reset(const ENUM_BIAS_DIR dir = BIAS_BULL, const ENUM_TRADE_PROFILE prof = PROFILE_INTRADAY)
     {
      setupId           = "";
      profile           = prof;
      direction         = dir;
      state             = SETUP_S0_IDLE;
      createdTime       = 0;
      armedTime         = 0;
      lastM5BarTime     = 0;
      ageBarsM5         = 0;
      weekQ             = QT_Q0;
      dayQ              = QT_Q0;
      session           = QT_SESSION_ASIA;
      q90               = QT_Q0;
      isDailyCycleSetup = false;
      cycleType         = CYCLE_AMDX;
      amdxPhase         = PHASE_NONE;
      narrative         = NARRATIVE_NONE;
      anchorPOI.Reset();
      hasRefinedPOI     = false;
      refinedPOI.Reset();
      poiOverlapCount   = 0;
      sweep.Reset();
      mss.Reset();
      isCisdConfirmed   = false;
      cisd.Reset();
      isSniperSetup     = false;
      hasFvg            = false;
      fvg.Reset();
      isMarketOrder     = false;
      entryPrice        = 0.0;
      slPrice           = 0.0;
      tpPrice           = 0.0;
      tp1Price          = 0.0;
      dolLabel          = "";
      rrRatio           = 0.0;
      score.Reset();
      statusNote        = "";
      loggedToCsv       = false;
      orderTicket       = 0;
     }
  };

string QTSetupStateToString(const ENUM_SETUP_STATE s)
  {
   switch(s)
     {
      case SETUP_S0_IDLE:      return "S0_IDLE";
      case SETUP_S1_POI_TOUCH: return "S1_POI_TOUCH";
      case SETUP_S2_SWEEP:     return "S2_SWEEP";
      case SETUP_S3_MSS:       return "S3_MSS";
      case SETUP_S4_ARMED:     return "S4_ARMED";
      case SETUP_S5_IN_TRADE:  return "S5_IN_TRADE";
      case SETUP_S6_DONE:      return "S6_DONE";
      default:                 return "UNKNOWN";
     }
  }

//+------------------------------------------------------------------+
//| CSetupEngine Class                                               |
//+------------------------------------------------------------------+
class CSetupEngine
  {
private:
   SSetupConfig      m_cfg;

   // 1. Swing Engine (Pure HTF Engine: W1, D1, H4, H1 Anchor POIs)
   SSetupTracker     m_buySwing;
   SSetupTracker     m_sellSwing;

   // 2. Intraday Engine (Daily AMDX / XAMD Cycle: M15 POI)
   SSetupTracker     m_buyIntra;
   SSetupTracker     m_sellIntra;

   // 3. Scalping Engine (M15 / M5 POIs, London & NY AM Q2/Q3 90m blocks)
   SSetupTracker     m_buyScalp;
   SSetupTracker     m_sellScalp;

   // Log event queue for reliable CSV journaling without dropped setups
   SSetupTracker     m_logQueue[];

   int               m_seqCounter;
   int               m_lastDailyCycleDayKey;
   int               m_dailyCycleTradesFilledToday;

   void              PushLogEvent(const SSetupTracker &tr)
     {
      int cnt = ArraySize(m_logQueue);
      ArrayResize(m_logQueue, cnt + 1);
      m_logQueue[cnt] = tr;
     }

   //--- Find a Fresh M15/M5 MSNR POI nested inside an HTF (W1/D1/H4/H1) Body-to-Wick Anchor Zone
   bool              FindNestedRefinedPOI(const SMSNRLevel &anchor,
                                          CMSNREngine &msnr,
                                          const double refPrice,
                                          SMSNRLevel &outRefined) const
     {
      outRefined.Reset();
      if(anchor.tfIdx > TF_IDX_H1)
         return false; // Anchor is already LTF

      double zoneSpan = MathMax(anchor.tolerance * 2.0, anchor.zoneHigh - anchor.zoneLow);
      double nestLow  = anchor.zoneLow  - zoneSpan * 0.35;
      double nestHigh = anchor.zoneHigh + zoneSpan * 0.35;

      bool found = false;
      int  bestPriority = -1; // 2 = QM/Flip, 1 = Classic A/V
      double bestDist   = DBL_MAX;

      int ltfList[2] = { TF_IDX_M15, TF_IDX_M5 };
      for(int k = 0; k < 2; k++)
        {
         int tf = ltfList[k];
         int cnt = msnr.GetLevelCount(tf);
         for(int i = 0; i < cnt; i++)
           {
            SMSNRLevel lvl;
            if(!msnr.GetLevel(tf, i, lvl))
               continue;
            if(lvl.direction != anchor.direction || !lvl.IsFreshForEntry(3))
               continue;

            bool isNested = (lvl.price >= nestLow && lvl.price <= nestHigh) ||
                            (lvl.zoneLow <= anchor.zoneHigh && lvl.zoneHigh >= anchor.zoneLow);
            if(!isNested)
               continue;

            int prio = ((lvl.type == POI_QM_BULL || lvl.type == POI_QM_BEAR ||
                         lvl.type == POI_RBS     || lvl.type == POI_SBR) ? 2 : 1);
            double d = MathAbs(lvl.price - refPrice);

            if(prio > bestPriority || (prio == bestPriority && d < bestDist))
              {
               bestPriority = prio;
               bestDist     = d;
               outRefined   = lvl;
               found        = true;
              }
           }
        }
      return found;
     }

   //--- Find Fresh HTF POI (W1, D1, H4, H1) for the Pure HTF Engine
   bool              FindTouchedHTFPOI(const ENUM_BIAS_DIR dir,
                                       const MqlRates &m5Bar,
                                       CMSNREngine &msnr,
                                       const STradeProfileSpec &prof,
                                       SMSNRLevel &outAnchor,
                                       bool &outHasRefined,
                                       SMSNRLevel &outRefined,
                                       int &outOverlaps) const
     {
      outAnchor.Reset();
      outHasRefined = false;
      outRefined.Reset();
      outOverlaps   = 0;

      double proximityMargin = m5Bar.high - m5Bar.low;

      // Scan strictly HTF Body-to-Wick Anchors: W1, D1, H4, H1
      for(int tf = TF_IDX_W1; tf <= TF_IDX_H1; tf++)
        {
         if(!prof.allowPOITF[tf])
            continue;

         int cnt = msnr.GetLevelCount(tf);
         for(int i = 0; i < cnt; i++)
           {
            SMSNRLevel lvl;
            if(!msnr.GetLevel(tf, i, lvl))
               continue;
            if(lvl.direction != dir || !lvl.IsFreshForEntry(3))
               continue;

            bool touched = (m5Bar.low <= lvl.zoneHigh + proximityMargin * 0.20 &&
                            m5Bar.high >= lvl.zoneLow - proximityMargin * 0.20);
            if(!touched)
               continue;

            if(dir == BIAS_BULL && m5Bar.close < lvl.zoneLow)
               continue;
            if(dir == BIAS_BEAR && m5Bar.close > lvl.zoneHigh)
               continue;

            outAnchor = lvl;
            if(m_cfg.useM15M5Refinement)
               outHasRefined = FindNestedRefinedPOI(outAnchor, msnr, m5Bar.close, outRefined);
            outOverlaps = msnr.CountMultiTFOverlaps(outAnchor);
            if(outHasRefined && outOverlaps < 2)
               outOverlaps = MathMin(2, outOverlaps + 1);
            return true;
           }
        }
      return false;
     }

   //--- Find Fresh M15 POI for the Daily AMDX/XAMD Cycle Engine
   bool              FindTouchedCyclePOI(const ENUM_BIAS_DIR dir,
                                         const MqlRates &m5Bar,
                                         CMSNREngine &msnr,
                                         const SBiasState &biasState,
                                         const QTState &qtState,
                                         SMSNRLevel &outAnchor,
                                         int &outOverlaps) const
     {
      outAnchor.Reset();
      outOverlaps = 0;

      if(!m_cfg.enableDailyAmdxCycle || m_dailyCycleTradesFilledToday >= 1)
         return false;

      if(!biasState.dailyCycle.isActive || biasState.dailyCycle.manipulationDir != dir)
         return false;

      ENUM_AMDX_PHASE curPhase = biasState.dailyCycle.currentPhase;

      // Point 6: On Monday & Friday (cycle-only days), strictly allow PHASE_D only!
      if(qtState.isCycleOnlyDay && curPhase != PHASE_D)
         return false;

      double aHigh  = biasState.dailyCycle.phaseAHigh;
      double aLow   = biasState.dailyCycle.phaseALow;
      double aRange = MathAbs(aHigh - aLow);
      double aMid   = biasState.dailyCycle.phaseAMid;

      // Point 2: Stricter Phase M filters
      if(curPhase == PHASE_M)
        {
         // 1. Only Q3 90-minute block (Sweep confirmation/expansion)
         if(qtState.q90 != QT_Q3)
            return false;
         // 2. Must be strictly aligned with D1 bias!
         if(biasState.biasD1 != dir)
            return false;
         // 3. Phase A range must be at least 115 pips ($11.50)
         if(aRange < QTPipsToPrice(_Symbol, 115.0))
            return false;
        }

      double proximityMargin = m5Bar.high - m5Bar.low;

      // Point 5: M15 ONLY (M5 excluded from standalone cycle anchor!)
      int tf = TF_IDX_M15;
      int cnt = msnr.GetLevelCount(tf);
      for(int i = 0; i < cnt; i++)
        {
         SMSNRLevel lvl;
         if(!msnr.GetLevel(tf, i, lvl))
            continue;
         if(lvl.direction != dir || !lvl.IsFreshForEntry(3))
            continue;

         bool isFlipOrQm = (lvl.type == POI_RBS || lvl.type == POI_SBR ||
                            lvl.type == POI_QM_BULL || lvl.type == POI_QM_BEAR);

         if(curPhase == PHASE_M)
           {
            // Phase M (Manipulation Extreme): POI must be near the swept Phase A High (Sell) or Low (Buy)
            if(dir == BIAS_BULL && lvl.price > aLow + 0.35 * aRange)
               continue;
            if(dir == BIAS_BEAR && lvl.price < aHigh - 0.35 * aRange)
               continue;
           }
         else // PHASE_D (Distribution Pullback to IRL)
           {
            // Phase D: Require confirmed Flip/QM in Discount (Buy) / Premium (Sell)
            if(!isFlipOrQm)
               continue;
            if(dir == BIAS_BULL && m5Bar.close > aMid && !biasState.isBelowTrueDayOpen)
               continue;
            if(dir == BIAS_BEAR && m5Bar.close < aMid && !biasState.isAboveTrueDayOpen)
               continue;
           }

         bool touched = (m5Bar.low <= lvl.zoneHigh + proximityMargin * 0.20 &&
                         m5Bar.high >= lvl.zoneLow - proximityMargin * 0.20);
         if(!touched)
            continue;

         if(dir == BIAS_BULL && m5Bar.close < lvl.zoneLow)
            continue;
         if(dir == BIAS_BEAR && m5Bar.close > lvl.zoneHigh)
            continue;

         outAnchor   = lvl;
         outOverlaps = MathMin(2, msnr.CountMultiTFOverlaps(outAnchor) + 1);
         return true;
        }
      return false;
     }

   //--- Detect Institutional Sniper Entry Condition (v1.31)
   //    Sell: Fresh HTF/MTF Resistance sitting AT OR ABOVE valid Buy-Side Liquidity (BSL)
   //    Buy : Fresh HTF/MTF Support sitting AT OR BELOW valid Sell-Side Liquidity (SSL)
   bool              CheckSniperCondition(const ENUM_BIAS_DIR dir,
                                          const MqlRates &m5Bar,
                                          CMSNREngine &msnr,
                                          CICTEngine &ict,
                                          const double currentSpreadPrice,
                                          SMSNRLevel &outSniperPOI,
                                          int &outOverlaps,
                                          SSweepEvent &outSweep) const
     {
      outSniperPOI.Reset();
      outOverlaps = 0;
      outSweep.Reset();

      SLiquidityPool pools[];
      int poolCnt = 0;
      ict.GetPoolsArray(pools, poolCnt);
      if(poolCnt <= 0)
         return false;

      double proximityMargin = MathMax(currentSpreadPrice * 2.0, m5Bar.high - m5Bar.low);

      // Search higher timeframes first (H4, H1, D1, W1, M15)
      int sniperTfs[5] = { TF_IDX_H4, TF_IDX_H1, TF_IDX_D1, TF_IDX_W1, TF_IDX_M15 };

      if(dir == BIAS_BEAR)
        {
         // 1. Scan Buy-Side Liquidity (BSL) pools that price is sweeping or has pierced
         for(int p = 0; p < poolCnt; p++)
           {
            if(!pools[p].isBuySide || pools[p].formedTime >= m5Bar.time)
               continue;

            // Bar high must reach or pierce BSL pool
            if(m5Bar.high < pools[p].price - proximityMargin * 0.10)
               continue;

            // 2. Scan Fresh HTF/MTF Resistance POIs situated AT OR ABOVE this BSL pool
            for(int k = 0; k < 5; k++)
              {
               int tf = sniperTfs[k];
               int cnt = msnr.GetLevelCount(tf);
               for(int i = 0; i < cnt; i++)
                 {
                  SMSNRLevel lvl;
                  if(!msnr.GetLevel(tf, i, lvl))
                     continue;
                  if(lvl.direction != BIAS_BEAR || !lvl.IsFreshForEntry(3))
                     continue;

                  // POI must be located at or above the BSL level (allowing small tolerance)
                  if(lvl.zoneHigh < pools[p].price - proximityMargin * 0.20)
                     continue;

                  // Price must be touching/reacting inside this Fresh POI
                  bool touched = (m5Bar.high >= lvl.zoneLow - proximityMargin * 0.20 &&
                                  m5Bar.low <= lvl.zoneHigh + proximityMargin * 0.20);
                  if(!touched)
                     continue;

                  // Candle body must respect the POI (not blown through by body close)
                  if(m5Bar.close > lvl.zoneHigh + proximityMargin * 0.25)
                     continue;

                  outSniperPOI = lvl;
                  outOverlaps  = MathMin(2, msnr.CountMultiTFOverlaps(outSniperPOI) + 1);

                  outSweep.valid            = true;
                  outSweep.signalDir        = BIAS_BEAR;
                  outSweep.poolType         = pools[p].type;
                  outSweep.poolId           = pools[p].id;
                  outSweep.triggerTfIdx     = TF_IDX_M5;
                  outSweep.sweepBarTime     = m5Bar.time;
                  outSweep.sweepClosedShift = 1;
                  outSweep.sweptLevelPrice  = pools[p].price;
                  outSweep.extremeWickPrice = m5Bar.high;
                  outSweep.isMajorPool      = pools[p].IsMajorPool();
                  return true;
                 }
              }
           }
        }
      else if(dir == BIAS_BULL)
        {
         // 1. Scan Sell-Side Liquidity (SSL) pools that price is sweeping or has pierced
         for(int p = 0; p < poolCnt; p++)
           {
            if(pools[p].isBuySide || pools[p].formedTime >= m5Bar.time)
               continue;

            // Bar low must reach or pierce SSL pool
            if(m5Bar.low > pools[p].price + proximityMargin * 0.10)
               continue;

            // 2. Scan Fresh HTF/MTF Support POIs situated AT OR BELOW this SSL pool
            for(int k = 0; k < 5; k++)
              {
               int tf = sniperTfs[k];
               int cnt = msnr.GetLevelCount(tf);
               for(int i = 0; i < cnt; i++)
                 {
                  SMSNRLevel lvl;
                  if(!msnr.GetLevel(tf, i, lvl))
                     continue;
                  if(lvl.direction != BIAS_BULL || !lvl.IsFreshForEntry(3))
                     continue;

                  // POI must be located at or below the SSL level (allowing small tolerance)
                  if(lvl.zoneLow > pools[p].price + proximityMargin * 0.20)
                     continue;

                  // Price must be touching/reacting inside this Fresh POI
                  bool touched = (m5Bar.low <= lvl.zoneHigh + proximityMargin * 0.20 &&
                                  m5Bar.high >= lvl.zoneLow - proximityMargin * 0.20);
                  if(!touched)
                     continue;

                  // Candle body must respect the POI (not blown through by body close)
                  if(m5Bar.close < lvl.zoneLow - proximityMargin * 0.25)
                     continue;

                  outSniperPOI = lvl;
                  outOverlaps  = MathMin(2, msnr.CountMultiTFOverlaps(outSniperPOI) + 1);

                  outSweep.valid            = true;
                  outSweep.signalDir        = BIAS_BULL;
                  outSweep.poolType         = pools[p].type;
                  outSweep.poolId           = pools[p].id;
                  outSweep.triggerTfIdx     = TF_IDX_M5;
                  outSweep.sweepBarTime     = m5Bar.time;
                  outSweep.sweepClosedShift = 1;
                  outSweep.sweptLevelPrice  = pools[p].price;
                  outSweep.extremeWickPrice = m5Bar.low;
                  outSweep.isMajorPool      = pools[p].IsMajorPool();
                  return true;
                 }
              }
           }
        }

      return false;
     }

   //--- Find Fresh POI for Scalping Engine (v1.31: AMDX/XAMD Alignment & Sniper or Continuation)
   bool              FindTouchedScalpPOI(const ENUM_BIAS_DIR dir,
                                         const MqlRates &m5Bar,
                                         CMSNREngine &msnr,
                                         CICTEngine &ict,
                                         const SBiasState &biasState,
                                         const QTState &qtState,
                                         const STradeProfileSpec &prof,
                                         const double currentSpreadPrice,
                                         SMSNRLevel &outAnchor,
                                         int &outOverlaps,
                                         bool &outIsSniper,
                                         SSweepEvent &outSniperSweep) const
     {
      outAnchor.Reset();
      outOverlaps    = 0;
      outIsSniper    = false;
      outSniperSweep.Reset();

      // 1. Sniper Entry Check (Top Priority)
      if(m_cfg.enableSniperEntry)
        {
         if(CheckSniperCondition(dir, m5Bar, msnr, ict, currentSpreadPrice, outAnchor, outOverlaps, outSniperSweep))
           {
            outIsSniper = true;
            return true;
           }
        }

      // 2. Daily Cycle AMDX / XAMD Session Continuation (Phase D or Phase M)
      // Only allow continuation scalp if market is in Phase D (Expansion) aligned with manipulation direction
      if(biasState.dailyCycle.isActive && biasState.dailyCycle.currentPhase == PHASE_D)
        {
         // Direction MUST match session expansion direction
         if(dir != biasState.dailyCycle.manipulationDir)
            return false;

         double proximityMargin = MathMax(currentSpreadPrice * 2.0, m5Bar.high - m5Bar.low);

         // Scan M15 and H1 POIs for continuation pullback
         int contTfs[2] = { TF_IDX_M15, TF_IDX_H1 };
         for(int k = 0; k < 2; k++)
           {
            int tf = contTfs[k];
            int cnt = msnr.GetLevelCount(tf);
            for(int i = 0; i < cnt; i++)
              {
               SMSNRLevel lvl;
               if(!msnr.GetLevel(tf, i, lvl))
                  continue;
               if(lvl.direction != dir || !lvl.IsFreshForEntry(3))
                  continue;

               // Filter discount / premium
               if(dir == BIAS_BULL && m5Bar.close > biasState.dailyCycle.phaseAMid && !biasState.isBelowTrueDayOpen)
                  continue;
               if(dir == BIAS_BEAR && m5Bar.close < biasState.dailyCycle.phaseAMid && !biasState.isAboveTrueDayOpen)
                  continue;

               bool touched = (m5Bar.low <= lvl.zoneHigh + proximityMargin * 0.20 &&
                               m5Bar.high >= lvl.zoneLow - proximityMargin * 0.20);
               if(!touched)
                  continue;

               if(dir == BIAS_BULL && m5Bar.close < lvl.zoneLow)
                  continue;
               if(dir == BIAS_BEAR && m5Bar.close > lvl.zoneHigh)
                  continue;

               outAnchor   = lvl;
               outOverlaps = MathMin(2, msnr.CountMultiTFOverlaps(outAnchor));
               outIsSniper = false;
               return true;
              }
           }
        }

      return false;
     }

   //--- Detect Liquidity Sweep for HTF Setup (Trigger TF M15 + Secondary Trigger M5)
   bool              CheckSweepForHTFSetup(const SSetupTracker &tr,
                                           CMTFDataManager &mtf,
                                           CICTEngine &ict,
                                           const STradeProfileSpec &prof,
                                           SSweepEvent &outSweep) const
     {
      outSweep.Reset();
      SLiquidityPool pools[];
      int poolCnt = 0;
      ict.GetPoolsArray(pools, poolCnt);

      // 1. Primary Trigger TF (M15)
      MqlRates trigBar;
      if(mtf.GetClosedBar(prof.triggerTfIdx, 1, trigBar))
        {
         if(CICTEngine::DetectSweepOnBar(trigBar, 1, prof.triggerTfIdx, pools, poolCnt, tr.direction, outSweep))
            return true;
        }

      // 2. Secondary Trigger TF (M5)
      MqlRates secBar;
      if(prof.secondaryTriggerTfIdx != prof.triggerTfIdx &&
         mtf.GetClosedBar(prof.secondaryTriggerTfIdx, 1, secBar))
        {
         if(CICTEngine::DetectSweepOnBar(secBar, 1, prof.secondaryTriggerTfIdx, pools, poolCnt, tr.direction, outSweep))
            return true;

         double poiPrice = (tr.hasRefinedPOI ? tr.refinedPOI.price : tr.anchorPOI.price);
         if(tr.direction == BIAS_BULL && secBar.low < poiPrice && secBar.close > poiPrice)
           {
            outSweep.valid            = true;
            outSweep.signalDir        = BIAS_BULL;
            outSweep.poolType         = LIQ_POOL_SWING_LOW;
            outSweep.poolId           = tr.anchorPOI.id;
            outSweep.triggerTfIdx     = prof.secondaryTriggerTfIdx;
            outSweep.sweepBarTime     = secBar.time;
            outSweep.sweepClosedShift = 1;
            outSweep.sweptLevelPrice  = poiPrice;
            outSweep.extremeWickPrice = secBar.low;
            outSweep.isMajorPool      = true;
            return true;
           }
         if(tr.direction == BIAS_BEAR && secBar.high > poiPrice && secBar.close < poiPrice)
           {
            outSweep.valid            = true;
            outSweep.signalDir        = BIAS_BEAR;
            outSweep.poolType         = LIQ_POOL_SWING_HIGH;
            outSweep.poolId           = tr.anchorPOI.id;
            outSweep.triggerTfIdx     = prof.secondaryTriggerTfIdx;
            outSweep.sweepBarTime     = secBar.time;
            outSweep.sweepClosedShift = 1;
            outSweep.sweptLevelPrice  = poiPrice;
            outSweep.extremeWickPrice = secBar.high;
            outSweep.isMajorPool      = true;
            return true;
           }
        }
      return false;
     }

   //--- Detect Liquidity Sweep for Daily Cycle Setup (Swing Sweep + Phase A Manipulation Sweep)
   bool              CheckSweepForCycleSetup(const SSetupTracker &tr,
                                             CMTFDataManager &mtf,
                                             CICTEngine &ict,
                                             const STradeProfileSpec &prof,
                                             const SBiasState &biasState,
                                             SSweepEvent &outSweep) const
     {
      outSweep.Reset();

      // 1. Check standard M15 / M5 swing sweep first
      if(CheckSweepForHTFSetup(tr, mtf, ict, prof, outSweep))
         return true;

      // 2. Multi-Candle Sweep of Phase A High/Low
      MqlRates secBar;
      if(mtf.GetClosedBar(prof.secondaryTriggerTfIdx, 1, secBar))
        {
         double poiPrice = tr.anchorPOI.price;
         bool barRejected = (tr.direction == BIAS_BULL
                             ? (secBar.close > secBar.open && secBar.close >= poiPrice)
                             : (secBar.close < secBar.open && secBar.close <= poiPrice));
         if(barRejected)
           {
            int shiftEst = MathMax(1, (int)((secBar.time - biasState.dailyCycle.activeSweepTime) / 300) + 1);
            outSweep.valid            = true;
            outSweep.signalDir        = tr.direction;
            outSweep.poolType         = (tr.direction == BIAS_BULL ? LIQ_POOL_SESSION_LOW : LIQ_POOL_SESSION_HIGH);
            outSweep.poolId           = biasState.dailyCycle.phaseALabel;
            outSweep.triggerTfIdx     = prof.secondaryTriggerTfIdx;
            outSweep.sweepBarTime     = (biasState.dailyCycle.activeSweepTime > 0 ? biasState.dailyCycle.activeSweepTime : secBar.time);
            outSweep.sweepClosedShift = shiftEst;
            outSweep.sweptLevelPrice  = biasState.dailyCycle.activeSweepLevel;
            outSweep.extremeWickPrice = (tr.direction == BIAS_BULL
                                         ? MathMin(secBar.low,  biasState.dailyCycle.activeSweepExtreme)
                                         : MathMax(secBar.high, biasState.dailyCycle.activeSweepExtreme));
            outSweep.isMajorPool      = true;
            return true;
           }
        }
      return false;
     }

   //--- Step Machine for Pure HTF Setup (D1, H4, H1 Anchor)
   void              StepHTFTracker(SSetupTracker &tr,
                                    CMTFDataManager &mtf,
                                    CSwingEngine &swings,
                                    CMSNREngine &msnr,
                                    CICTEngine &ict,
                                    const QTState &qtState,
                                    const SBiasState &biasState,
                                    const STradeProfileSpec &prof,
                                    const double currentSpreadPrice,
                                    const bool isNewsBlocked,
                                    const string newsReason)
     {
      MqlRates m5Bar;
      if(!mtf.GetClosedBar(TF_IDX_M5, 1, m5Bar))
         return;

      bool biasGateOk = (tr.direction == BIAS_BULL ? biasState.allowBuy : biasState.allowSell);

      // Increment M5 bar age if setup is active (S1..S4)
      if(tr.state >= SETUP_S1_POI_TOUCH && tr.state <= SETUP_S4_ARMED)
        {
         if(m5Bar.time > tr.lastM5BarTime)
           {
            tr.ageBarsM5++;
            tr.lastM5BarTime = m5Bar.time;
           }

         if(isNewsBlocked)
           {
            tr.statusNote = "REJECT_NEWS: " + newsReason;
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if(!qtState.isTimeAllowed)
           {
            tr.statusNote = "CANCEL_TIME_WINDOW_ENDED";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if(!biasGateOk)
           {
            tr.statusNote = "CANCEL_BIAS_GATE_FLIPPED";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if(tr.ageBarsM5 > m_cfg.maxSetupBarsM5)
           {
            tr.statusNote = "CANCEL_SETUP_EXPIRED_MAX_BARS";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if((tr.direction == BIAS_BULL && m5Bar.close < tr.anchorPOI.zoneLow) ||
            (tr.direction == BIAS_BEAR && m5Bar.close > tr.anchorPOI.zoneHigh))
           {
            tr.statusNote = "CANCEL_POI_BODY_BROKEN";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
        }

      // S0: IDLE -> Wait for allowed time + HTF bias + Fresh HTF POI touch
      if(tr.state == SETUP_S0_IDLE)
        {
         if(!biasGateOk || !qtState.isTimeAllowed || isNewsBlocked)
            return;

         SMSNRLevel anchor, refined;
         bool hasRef  = false;
         int overlaps = 0;

         if(FindTouchedHTFPOI(tr.direction, m5Bar, msnr, prof, anchor, hasRef, refined, overlaps))
           {
            m_seqCounter++;
            tr.Reset(tr.direction, PROFILE_SWING);
            tr.setupId            = StringFormat("QT_SWING_%s_%I64d_%d",
                                                 (tr.direction == BIAS_BULL ? "BUY" : "SELL"),
                                                 (long)m5Bar.time,
                                                 m_seqCounter);
            tr.profile            = PROFILE_SWING;
            tr.state              = SETUP_S1_POI_TOUCH;
            tr.createdTime        = qtState.serverTime;
            tr.lastM5BarTime      = m5Bar.time;
            tr.ageBarsM5          = 0;
            tr.weekQ              = qtState.weekQ;
            tr.dayQ               = qtState.dayQ;
            tr.session            = qtState.session;
            tr.q90                = qtState.q90;
            tr.anchorPOI          = anchor;
            tr.hasRefinedPOI      = hasRef;
            tr.refinedPOI         = refined;
            tr.poiOverlapCount    = overlaps;
            tr.isDailyCycleSetup  = false;
            tr.narrative          = biasState.dailyCycle.narrative;
            tr.statusNote         = "S1_POI_TOUCH";
           }
        }

      // Refresh nested M15/M5 Refined POI inside HTF Anchor Zone if one just formed
      if(tr.state >= SETUP_S1_POI_TOUCH && tr.state <= SETUP_S3_MSS &&
         m_cfg.useM15M5Refinement && !tr.hasRefinedPOI)
        {
         SMSNRLevel candRef;
         if(FindNestedRefinedPOI(tr.anchorPOI, msnr, m5Bar.close, candRef))
           {
            tr.hasRefinedPOI   = true;
            tr.refinedPOI      = candRef;
            tr.poiOverlapCount = MathMin(2, MathMax(1, tr.poiOverlapCount + 1));
           }
        }

      // S1: POI_TOUCH -> Wait for Liquidity Sweep
      if(tr.state == SETUP_S1_POI_TOUCH)
        {
         SSweepEvent swEv;
         if(CheckSweepForHTFSetup(tr, mtf, ict, prof, swEv))
           {
            tr.sweep      = swEv;
            tr.state      = SETUP_S2_SWEEP;
            tr.statusNote = "S2_SWEEP_CONFIRMED";
           }
        }

      // S2: SWEEP -> Wait for MSS
      if(tr.state == SETUP_S2_SWEEP)
        {
         if(!ict.GetConfig().useMSS)
           {
            tr.mss.confirmed        = true;
            tr.mss.direction        = tr.direction;
            tr.mss.tfIdx            = tr.sweep.triggerTfIdx;
            tr.mss.mssBarTime       = m5Bar.time;
            tr.mss.mssClosedShift   = 1;
            tr.mss.brokenSwingPrice = tr.sweep.sweptLevelPrice;
            tr.state                = SETUP_S3_MSS;
            tr.statusNote           = "S3_MSS_BYPASSED";
           }
         else
           {
            int checkTfs[2] = { tr.sweep.triggerTfIdx, prof.entryTfIdx };
            for(int k = 0; k < 2; k++)
              {
               int tfIdx = checkTfs[k];
               MqlRates tRates[];
               int rCnt = mtf.GetClosedRatesArray(tfIdx, tRates);
               int sCnt = swings.GetWickSwingCount(tfIdx);
               SSwingPoint wSwings[];
               ArrayResize(wSwings, sCnt);
               for(int i = 0; i < sCnt; i++)
                  swings.GetWickSwing(tfIdx, i, wSwings[i]);

               SMSSResult mssRes;
               if(CICTEngine::CheckMSSAfterSweep(tRates, rCnt, wSwings, sCnt, tr.sweep, tfIdx, mssRes))
                 {
                  tr.mss        = mssRes;
                  tr.state      = SETUP_S3_MSS;
                  tr.statusNote = "S3_MSS_CONFIRMED";
                  break;
                 }
              }
           }
        }

      // S3: MSS -> Wait for FVG & Validate Parameters
      if(tr.state == SETUP_S3_MSS)
        {
         SFVGZone fvgFound;
         bool gotFvg = ict.FindRecentTradableFVG(prof.entryTfIdx, tr.direction, tr.sweep.sweepBarTime, fvgFound);
         if(!gotFvg && prof.triggerTfIdx != prof.entryTfIdx)
            gotFvg = ict.FindRecentTradableFVG(prof.triggerTfIdx, tr.direction, tr.sweep.sweepBarTime, fvgFound);

         if(!gotFvg && m_cfg.entryType != ENTRY_MARKET_MSS && !tr.hasRefinedPOI)
            return;

         tr.hasFvg = gotFvg;
         tr.fvg    = fvgFound;

         // 1. Entry Price
         if(m_cfg.entryType == ENTRY_MARKET_MSS)
           {
            tr.isMarketOrder = true;
            tr.entryPrice    = m5Bar.close;
           }
         else if(gotFvg)
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = (m_cfg.entryType == ENTRY_FVG_CE ? fvgFound.ce : fvgFound.proximal);
            if(tr.hasRefinedPOI &&
               tr.refinedPOI.price >= fvgFound.lowEdge &&
               tr.refinedPOI.price <= fvgFound.highEdge)
               tr.entryPrice = tr.refinedPOI.price;
           }
         else
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = tr.refinedPOI.price;
           }

         // 2. Stop Loss
         double atrM5    = mtf.GetATR(TF_IDX_M5);
         double atrH1    = mtf.GetATR(TF_IDX_H1);
         double slBuffer = m_cfg.slBufferAtrMultM5 * atrM5 + currentSpreadPrice;

         double minSlDist    = QTPipsToPrice(_Symbol, (m_cfg.minSlPips    > 0.0 ? m_cfg.minSlPips    : 45.0));
         double targetSlDist = QTPipsToPrice(_Symbol, (m_cfg.targetSlPips > 0.0 ? m_cfg.targetSlPips : 60.0));
         double maxSlDist    = QTPipsToPrice(_Symbol, (m_cfg.maxSlPips    > 0.0 ? m_cfg.maxSlPips    : 75.0));

         if(tr.direction == BIAS_BULL)
           {
            double baseLow = MathMin(tr.sweep.extremeWickPrice, m5Bar.low);
            if(tr.hasRefinedPOI && tr.refinedPOI.wickExtreme > 0.0 &&
               MathAbs(tr.entryPrice - tr.refinedPOI.wickExtreme) <= 0.8 * atrH1)
               baseLow = MathMin(baseLow, tr.refinedPOI.wickExtreme);
            tr.slPrice = baseLow - slBuffer;

            double rawSlDist = tr.entryPrice - tr.slPrice;
            if(rawSlDist < minSlDist)
               tr.slPrice = tr.entryPrice - targetSlDist;
            else if(rawSlDist > maxSlDist && rawSlDist <= maxSlDist * 1.65)
               tr.slPrice = tr.entryPrice - maxSlDist;

            if(m5Bar.close <= tr.slPrice)
              {
               tr.statusNote = "REJECT_PRICE_BELOW_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction);
               return;
              }
           }
         else
           {
            double baseHigh = MathMax(tr.sweep.extremeWickPrice, m5Bar.high);
            if(tr.hasRefinedPOI && tr.refinedPOI.wickExtreme > 0.0 &&
               MathAbs(tr.refinedPOI.wickExtreme - tr.entryPrice) <= 0.8 * atrH1)
               baseHigh = MathMax(baseHigh, tr.refinedPOI.wickExtreme);
            tr.slPrice = baseHigh + slBuffer;

            double rawSlDist = tr.slPrice - tr.entryPrice;
            if(rawSlDist < minSlDist)
               tr.slPrice = tr.entryPrice + targetSlDist;
            else if(rawSlDist > maxSlDist && rawSlDist <= maxSlDist * 1.65)
               tr.slPrice = tr.entryPrice + maxSlDist;

            if(m5Bar.close >= tr.slPrice)
              {
               tr.statusNote = "REJECT_PRICE_ABOVE_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction);
               return;
              }
           }

         double slDist = (tr.direction == BIAS_BULL ? (tr.entryPrice - tr.slPrice)
                                                    : (tr.slPrice - tr.entryPrice));
         if(slDist <= 1e-5)
           {
            tr.statusNote = "REJECT_INVALID_SL_DISTANCE";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         if(slDist > maxSlDist * 1.65 || (atrH1 > 0.0 && slDist > m_cfg.maxSlAtrMultH1 * atrH1))
           {
            tr.statusNote = StringFormat("REJECT_SL_TOO_WIDE (%.2f pips)", QTPriceToPips(_Symbol, slDist));
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         // 3. Target TP
         SDOLTarget dolTarget = (tr.direction == BIAS_BULL ? biasState.bullDOL : biasState.bearDOL);
         double minRR         = (m_cfg.customMinRR > 0.0 ? m_cfg.customMinRR : prof.minRR);

         double tp1Dist       = QTPipsToPrice(_Symbol, (m_cfg.partialTp1Pips > 0.0 ? m_cfg.partialTp1Pips : 100.0));
         double runnerDist    = QTPipsToPrice(_Symbol, (m_cfg.runnerTpPips   > 0.0 ? m_cfg.runnerTpPips   : 300.0));
         double minFullTpDist = MathMax(slDist * minRR, tp1Dist * 1.80);

         tr.tp1Price = (tr.direction == BIAS_BULL ? tr.entryPrice + tp1Dist : tr.entryPrice - tp1Dist);

         bool usedDol = false;
         if(dolTarget.valid)
           {
            double dolDist = (tr.direction == BIAS_BULL ? (dolTarget.price - tr.entryPrice)
                                                        : (tr.entryPrice - dolTarget.price));
            if(dolDist >= minFullTpDist && dolDist <= runnerDist * 1.25)
              {
               tr.tpPrice  = dolTarget.price;
               if(tr.narrative != NARRATIVE_NONE)
                  tr.dolLabel = StringFormat("%s_%s", dolTarget.label, QTNarrativeToString(tr.narrative));
               else
                  tr.dolLabel = dolTarget.label;
               usedDol     = true;
              }
           }

         if(!usedDol)
           {
            double projDist = MathMax(runnerDist, minFullTpDist);
            tr.tpPrice  = (tr.direction == BIAS_BULL ? tr.entryPrice + projDist
                                                     : tr.entryPrice - projDist);
            if(tr.narrative != NARRATIVE_NONE)
               tr.dolLabel = StringFormat("RUNNER_300P_%s", QTNarrativeToString(tr.narrative));
            else
               tr.dolLabel = "RUNNER_300P";
           }

         double reward = (tr.direction == BIAS_BULL ? (tr.tpPrice - tr.entryPrice)
                                                    : (tr.entryPrice - tr.tpPrice));
         tr.rrRatio = (reward > 0.0 ? reward / slDist : 0.0);

         if(tr.rrRatio + 1e-5 < minRR)
           {
            tr.statusNote = StringFormat("REJECT_RR_BELOW_MIN (%.2f < %.2f)", tr.rrRatio, minRR);
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         // 4. Confluence Score
         CalcConfluenceScore(tr, qtState, biasState, prof, tr.score);
         if(tr.score.totalScore < m_cfg.minConfluenceScore)
           {
            tr.statusNote = StringFormat("REJECT_LOW_SCORE (%d < %d)",
                                         tr.score.totalScore, m_cfg.minConfluenceScore);
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         tr.state      = SETUP_S4_ARMED;
         tr.armedTime  = qtState.serverTime;
         tr.statusNote = (tr.isSniperSetup ? "ARMED_SNIPER_SWING" : "ARMED_VALID");
         PushLogEvent(tr);
        }

      // S4: ARMED -> Price cancellation check
      if(tr.state == SETUP_S4_ARMED)
        {
         if(tr.direction == BIAS_BULL)
           {
            if(m5Bar.low <= tr.slPrice)
              {
               tr.statusNote = "CANCEL_HIT_SL_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SWING);
               return;
              }
            if(m5Bar.high >= tr.tpPrice)
              {
               tr.statusNote = "CANCEL_HIT_TP_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SWING);
               return;
              }
           }
         else
           {
            if(m5Bar.high >= tr.slPrice)
              {
               tr.statusNote = "CANCEL_HIT_SL_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SWING);
               return;
              }
            if(m5Bar.low <= tr.tpPrice)
              {
               tr.statusNote = "CANCEL_HIT_TP_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SWING);
               return;
              }
           }
        }
     }

   //--- Step Machine for Daily Cycle Setup (M15 Anchor, Phase M & Phase D Engine)
   void              StepCycleTracker(SSetupTracker &tr,
                                      CMTFDataManager &mtf,
                                      CSwingEngine &swings,
                                      CMSNREngine &msnr,
                                      CICTEngine &ict,
                                      const QTState &qtState,
                                      const SBiasState &biasState,
                                      const STradeProfileSpec &prof,
                                      const double currentSpreadPrice,
                                      const bool isNewsBlocked,
                                      const string newsReason)
     {
      MqlRates m5Bar;
      if(!mtf.GetClosedBar(TF_IDX_M5, 1, m5Bar))
         return;

      bool cycleGateOk = (tr.direction == BIAS_BULL ? biasState.allowBuyCycle : biasState.allowSellCycle);

      // Invalidation checks for active pre-trade setup (S1..S4)
      if(tr.state >= SETUP_S1_POI_TOUCH && tr.state <= SETUP_S4_ARMED)
        {
         if(m5Bar.time > tr.lastM5BarTime)
           {
            tr.ageBarsM5++;
            tr.lastM5BarTime = m5Bar.time;
           }

         if(isNewsBlocked)
           {
            tr.statusNote = "REJECT_NEWS: " + newsReason;
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if(!qtState.isCycleTimeAllowed)
           {
            tr.statusNote = "CANCEL_TIME_WINDOW_ENDED";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if(!cycleGateOk)
           {
            tr.statusNote = "CANCEL_BIAS_GATE_FLIPPED";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         // Point 6: On Monday & Friday (cycle-only days), strictly allow PHASE_D only
         if(qtState.isCycleOnlyDay && biasState.dailyCycle.currentPhase != PHASE_D)
           {
            tr.statusNote = "CANCEL_CYCLE_DAY_PHASE_NOT_D";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if(tr.ageBarsM5 > m_cfg.maxSetupBarsM5)
           {
            tr.statusNote = "CANCEL_SETUP_EXPIRED_MAX_BARS";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
         if((tr.direction == BIAS_BULL && m5Bar.close < tr.anchorPOI.zoneLow) ||
            (tr.direction == BIAS_BEAR && m5Bar.close > tr.anchorPOI.zoneHigh))
           {
            tr.statusNote = "CANCEL_POI_BODY_BROKEN";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }
        }

      // S0: IDLE -> Wait for cycle permission + Fresh M15 POI touch or Sniper setup
      if(tr.state == SETUP_S0_IDLE)
        {
         if(!cycleGateOk || !qtState.isCycleTimeAllowed || isNewsBlocked)
            return;

         SMSNRLevel anchor;
         int overlaps = 0;
         bool isSniper = false;
         SSweepEvent sniperSweep;

         if(m_cfg.enableSniperEntry &&
            CheckSniperCondition(tr.direction, m5Bar, msnr, ict, currentSpreadPrice, anchor, overlaps, sniperSweep))
           {
            isSniper = true;
           }
         else if(!FindTouchedCyclePOI(tr.direction, m5Bar, msnr, biasState, qtState, anchor, overlaps))
           {
            return;
           }

         m_seqCounter++;
         tr.Reset(tr.direction, PROFILE_INTRADAY);
         tr.setupId            = StringFormat("QT_INTRA_%s_%I64d_%d",
                                              (tr.direction == BIAS_BULL ? "BUY" : "SELL"),
                                              (long)m5Bar.time,
                                              m_seqCounter);
         tr.profile            = PROFILE_INTRADAY;
         tr.state              = (isSniper ? SETUP_S2_SWEEP : SETUP_S1_POI_TOUCH);
         tr.createdTime        = qtState.serverTime;
         tr.lastM5BarTime      = m5Bar.time;
         tr.ageBarsM5          = 0;
         tr.weekQ              = qtState.weekQ;
         tr.dayQ               = qtState.dayQ;
         tr.session            = qtState.session;
         tr.q90                = qtState.q90;
         tr.anchorPOI          = anchor;
         tr.hasRefinedPOI      = false;
         tr.poiOverlapCount    = overlaps;
         tr.isDailyCycleSetup  = true;
         tr.isSniperSetup      = isSniper;
         if(isSniper)
            tr.sweep           = sniperSweep;
         tr.cycleType          = biasState.dailyCycle.cycleType;
         tr.amdxPhase          = biasState.dailyCycle.currentPhase;
         tr.narrative          = biasState.dailyCycle.narrative;
         tr.statusNote         = (isSniper ? "S2_SNIPER_SWEEP" : "S1_POI_TOUCH");
        }

      // S1: POI_TOUCH -> Wait for Sweep
      if(tr.state == SETUP_S1_POI_TOUCH)
        {
         SSweepEvent swEv;
         if(CheckSweepForCycleSetup(tr, mtf, ict, prof, biasState, swEv))
           {
            tr.sweep      = swEv;
            tr.state      = SETUP_S2_SWEEP;
            tr.statusNote = "S2_SWEEP_CONFIRMED";
           }
        }

      // S2: SWEEP -> Wait for CISD or MSS
      if(tr.state == SETUP_S2_SWEEP)
        {
         bool confirmed = false;

         // 1. Check CISD on M5
         if(m_cfg.confirmMode == CONFIRM_MODE_CISD_ONLY || m_cfg.confirmMode == CONFIRM_MODE_EITHER)
           {
            MqlRates m5Rates[];
            int m5Cnt = mtf.GetClosedRatesArray(TF_IDX_M5, m5Rates);
            SCISDResult cisdRes;
            if(CICTEngine::CheckCISDAfterSweepOrTouch(m5Rates, m5Cnt, tr.sweep.sweepBarTime, tr.direction, TF_IDX_M5, cisdRes))
              {
               tr.isCisdConfirmed      = true;
               tr.cisd                 = cisdRes;
               tr.mss.confirmed        = true;
               tr.mss.direction        = tr.direction;
               tr.mss.tfIdx            = TF_IDX_M5;
               tr.mss.mssBarTime       = cisdRes.cisdBarTime;
               tr.mss.mssClosedShift   = cisdRes.cisdClosedShift;
               tr.mss.brokenSwingPrice = cisdRes.deliveryOpenPrice;
               tr.mss.brokenSwingTime  = cisdRes.deliveryStartTime;
               tr.state                = SETUP_S3_MSS;
               tr.statusNote           = "S3_CISD_CONFIRMED";
               confirmed               = true;
              }
           }

         // 2. Check MSS if not already confirmed by CISD
         if(!confirmed && (m_cfg.confirmMode == CONFIRM_MODE_MSS_ONLY || m_cfg.confirmMode == CONFIRM_MODE_EITHER))
           {
            if(!ict.GetConfig().useMSS)
              {
               tr.mss.confirmed        = true;
               tr.mss.direction        = tr.direction;
               tr.mss.tfIdx            = tr.sweep.triggerTfIdx;
               tr.mss.mssBarTime       = m5Bar.time;
               tr.mss.mssClosedShift   = 1;
               tr.mss.brokenSwingPrice = tr.sweep.sweptLevelPrice;
               tr.state                = SETUP_S3_MSS;
               tr.statusNote           = "S3_MSS_BYPASSED";
              }
            else
              {
               int checkTfs[2] = { tr.sweep.triggerTfIdx, prof.entryTfIdx };
               for(int k = 0; k < 2; k++)
                 {
                  int tfIdx = checkTfs[k];
                  MqlRates tRates[];
                  int rCnt = mtf.GetClosedRatesArray(tfIdx, tRates);
                  int sCnt = swings.GetWickSwingCount(tfIdx);
                  SSwingPoint wSwings[];
                  ArrayResize(wSwings, sCnt);
                  for(int i = 0; i < sCnt; i++)
                     swings.GetWickSwing(tfIdx, i, wSwings[i]);

                  SMSSResult mssRes;
                  if(CICTEngine::CheckMSSAfterSweep(tRates, rCnt, wSwings, sCnt, tr.sweep, tfIdx, mssRes))
                    {
                     tr.mss        = mssRes;
                     tr.state      = SETUP_S3_MSS;
                     tr.statusNote = "S3_MSS_CONFIRMED";
                     break;
                    }
                 }
              }
           }
        }

      // S3: MSS / CISD -> Wait for FVG & Validate Parameters
      if(tr.state == SETUP_S3_MSS)
        {
         SFVGZone fvgFound;
         bool gotFvg = ict.FindRecentTradableFVG(prof.entryTfIdx, tr.direction, tr.sweep.sweepBarTime, fvgFound);
         if(!gotFvg && prof.triggerTfIdx != prof.entryTfIdx)
            gotFvg = ict.FindRecentTradableFVG(prof.triggerTfIdx, tr.direction, tr.sweep.sweepBarTime, fvgFound);

         if(!gotFvg && m_cfg.entryType != ENTRY_MARKET_MSS && !tr.isCisdConfirmed)
            return;

         tr.hasFvg = gotFvg;
         tr.fvg    = fvgFound;

         // 1. Entry Price
         if(m_cfg.entryType == ENTRY_MARKET_MSS)
           {
            tr.isMarketOrder = true;
            tr.entryPrice    = m5Bar.close;
           }
         else if(gotFvg)
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = (m_cfg.entryType == ENTRY_FVG_CE ? fvgFound.ce : fvgFound.proximal);
           }
         else if(tr.isCisdConfirmed && tr.cisd.deliveryOpenPrice > 0.0)
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = tr.cisd.deliveryOpenPrice;
           }
         else
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = tr.anchorPOI.price;
           }

         // 2. Stop Loss (Calibrated: 45-75 pips, target 60 pips)
         double atrM5    = mtf.GetATR(TF_IDX_M5);
         double atrH1    = mtf.GetATR(TF_IDX_H1);
         double slBuffer = m_cfg.slBufferAtrMultM5 * atrM5 + currentSpreadPrice;

         double minSlDist    = QTPipsToPrice(_Symbol, (m_cfg.minSlPips    > 0.0 ? m_cfg.minSlPips    : 45.0));
         double targetSlDist = QTPipsToPrice(_Symbol, (m_cfg.targetSlPips > 0.0 ? m_cfg.targetSlPips : 60.0));
         double maxSlDist    = QTPipsToPrice(_Symbol, (m_cfg.maxSlPips    > 0.0 ? m_cfg.maxSlPips    : 75.0));

         if(tr.direction == BIAS_BULL)
           {
            double baseLow = MathMin(tr.sweep.extremeWickPrice, m5Bar.low);
            // Anchor SL below Phase M sweep extreme if within range
            if(tr.amdxPhase == PHASE_M && biasState.dailyCycle.activeSweepExtreme > 0.0 &&
               MathAbs(tr.entryPrice - biasState.dailyCycle.activeSweepExtreme) <= 0.8 * atrH1)
               baseLow = MathMin(baseLow, biasState.dailyCycle.activeSweepExtreme);

            tr.slPrice = baseLow - slBuffer;

            double rawSlDist = tr.entryPrice - tr.slPrice;
            if(rawSlDist < QTPipsToPrice(_Symbol, 18.0))
              {
               tr.statusNote = "REJECT_LTF_MICRO_NOISE_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction);
               return;
              }
            if(rawSlDist < minSlDist)
               tr.slPrice = tr.entryPrice - targetSlDist;
            else if(rawSlDist > maxSlDist && rawSlDist <= maxSlDist * 1.65)
               tr.slPrice = tr.entryPrice - maxSlDist;

            if(m5Bar.close <= tr.slPrice)
              {
               tr.statusNote = "REJECT_PRICE_BELOW_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction);
               return;
              }
           }
         else
           {
            double baseHigh = MathMax(tr.sweep.extremeWickPrice, m5Bar.high);
            // Anchor SL above Phase M sweep extreme if within range
            if(tr.amdxPhase == PHASE_M && biasState.dailyCycle.activeSweepExtreme > 0.0 &&
               MathAbs(biasState.dailyCycle.activeSweepExtreme - tr.entryPrice) <= 0.8 * atrH1)
               baseHigh = MathMax(baseHigh, biasState.dailyCycle.activeSweepExtreme);

            tr.slPrice = baseHigh + slBuffer;

            double rawSlDist = tr.slPrice - tr.entryPrice;
            if(rawSlDist < QTPipsToPrice(_Symbol, 18.0))
              {
               tr.statusNote = "REJECT_LTF_MICRO_NOISE_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction);
               return;
              }
            if(rawSlDist < minSlDist)
               tr.slPrice = tr.entryPrice + targetSlDist;
            else if(rawSlDist > maxSlDist && rawSlDist <= maxSlDist * 1.65)
               tr.slPrice = tr.entryPrice + maxSlDist;

            if(m5Bar.close >= tr.slPrice)
              {
               tr.statusNote = "REJECT_PRICE_ABOVE_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction);
               return;
              }
           }

         double slDist = (tr.direction == BIAS_BULL ? (tr.entryPrice - tr.slPrice)
                                                    : (tr.slPrice - tr.entryPrice));
         if(slDist <= 1e-5)
           {
            tr.statusNote = "REJECT_INVALID_SL_DISTANCE";
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         if(slDist > maxSlDist * 1.65 || (atrH1 > 0.0 && slDist > m_cfg.maxSlAtrMultH1 * atrH1))
           {
            tr.statusNote = StringFormat("REJECT_SL_TOO_WIDE (%.2f pips)", QTPriceToPips(_Symbol, slDist));
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         // 3. Target Determination (Phase M vs Phase D)
         SDOLTarget dolTarget = (tr.direction == BIAS_BULL ? biasState.bullDOL : biasState.bearDOL);
         double minRR         = (m_cfg.customMinRR > 0.0 ? m_cfg.customMinRR : prof.minRR);

         double tp1Dist       = QTPipsToPrice(_Symbol, (m_cfg.partialTp1Pips > 0.0 ? m_cfg.partialTp1Pips : 100.0));
         double runnerDist    = QTPipsToPrice(_Symbol, (m_cfg.runnerTpPips   > 0.0 ? m_cfg.runnerTpPips   : 300.0));
         double minPhaseADist = MathMax(slDist * minRR, tp1Dist * 1.15);

         tr.tp1Price = (tr.direction == BIAS_BULL ? tr.entryPrice + tp1Dist : tr.entryPrice - tp1Dist);

         bool targetValid = false;

         if(tr.amdxPhase == PHASE_M)
           {
            // Point 2: Phase M MUST target Phase A High (BUY) / Low (SELL). Do NOT fallback to runner!
            if(biasState.dailyCycle.phaseATargetPrice > 0.0)
              {
               double phaseADist = (tr.direction == BIAS_BULL
                                    ? (biasState.dailyCycle.phaseATargetPrice - tr.entryPrice)
                                    : (tr.entryPrice - biasState.dailyCycle.phaseATargetPrice));
               if(phaseADist >= minPhaseADist && phaseADist <= runnerDist * 1.35)
                 {
                  tr.tpPrice     = biasState.dailyCycle.phaseATargetPrice;
                  tr.dolLabel    = StringFormat("PHASE_M_%s_%s",
                                                (tr.direction == BIAS_BULL ? biasState.dailyCycle.phaseALabel + "_HIGH"
                                                                           : biasState.dailyCycle.phaseALabel + "_LOW"),
                                                QTNarrativeToString(tr.narrative));
                  targetValid    = true;
                 }
              }
            if(!targetValid)
              {
               // Phase A range is too narrow or distance insufficient -> REJECT (never fallback to runner on Phase M)
               tr.statusNote = "REJECT_PHASE_M_TARGET_TOO_CLOSE";
               PushLogEvent(tr);
               tr.Reset(tr.direction);
               return;
              }
           }
         else // PHASE_D (Distribution Pullback to IRL)
           {
            // Priority 1: Phase A Target
            if(biasState.dailyCycle.phaseATargetPrice > 0.0)
              {
               double phaseADist = (tr.direction == BIAS_BULL
                                    ? (biasState.dailyCycle.phaseATargetPrice - tr.entryPrice)
                                    : (tr.entryPrice - biasState.dailyCycle.phaseATargetPrice));
               if(phaseADist >= minPhaseADist && phaseADist <= runnerDist * 1.35)
                 {
                  tr.tpPrice     = biasState.dailyCycle.phaseATargetPrice;
                  tr.dolLabel    = StringFormat("PHASE_D_%s_%s",
                                                (tr.direction == BIAS_BULL ? biasState.dailyCycle.phaseALabel + "_HIGH"
                                                                           : biasState.dailyCycle.phaseALabel + "_LOW"),
                                                QTNarrativeToString(tr.narrative));
                  targetValid    = true;
                 }
              }
            // Priority 2: Standard DOL
            double minFullTpDist = MathMax(slDist * minRR, tp1Dist * 1.80);
            if(!targetValid && dolTarget.valid)
              {
               double dolDist = (tr.direction == BIAS_BULL ? (dolTarget.price - tr.entryPrice)
                                                           : (tr.entryPrice - dolTarget.price));
               if(dolDist >= minFullTpDist && dolDist <= runnerDist * 1.25)
                 {
                  tr.tpPrice  = dolTarget.price;
                  tr.dolLabel = StringFormat("%s_%s", dolTarget.label, QTNarrativeToString(tr.narrative));
                  targetValid = true;
                 }
              }
            // Priority 3: Fallback Runner 300 pips for Phase D
            if(!targetValid)
              {
               double projDist = MathMax(runnerDist, minFullTpDist);
               tr.tpPrice  = (tr.direction == BIAS_BULL ? tr.entryPrice + projDist
                                                        : tr.entryPrice - projDist);
               tr.dolLabel = StringFormat("PHASE_D_RUNNER_300P_%s", QTNarrativeToString(tr.narrative));
               targetValid = true;
              }
           }

         double reward = (tr.direction == BIAS_BULL ? (tr.tpPrice - tr.entryPrice)
                                                    : (tr.entryPrice - tr.tpPrice));
         tr.rrRatio = (reward > 0.0 ? reward / slDist : 0.0);

         if(tr.rrRatio + 1e-5 < minRR)
           {
            tr.statusNote = StringFormat("REJECT_RR_BELOW_MIN (%.2f < %.2f)", tr.rrRatio, minRR);
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         // 4. Confluence Score (Minimum 8 for LTF Cycle Setups)
         CalcConfluenceScore(tr, qtState, biasState, prof, tr.score);
         int reqScore = MathMax(m_cfg.minConfluenceScore, 8);
         if(tr.score.totalScore < reqScore)
           {
            tr.statusNote = StringFormat("REJECT_LOW_SCORE (%d < %d)",
                                         tr.score.totalScore, reqScore);
            PushLogEvent(tr);
            tr.Reset(tr.direction);
            return;
           }

         tr.state      = SETUP_S4_ARMED;
         tr.armedTime  = qtState.serverTime;
         tr.statusNote = (tr.isSniperSetup ? "ARMED_SNIPER_INTRA" : "ARMED_VALID");
         PushLogEvent(tr);
        }

      // S4: ARMED -> Price cancellation check
      if(tr.state == SETUP_S4_ARMED)
        {
         if(tr.direction == BIAS_BULL)
           {
            if(m5Bar.low <= tr.slPrice)
              {
               tr.statusNote = "CANCEL_HIT_SL_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_INTRADAY);
               return;
              }
            if(m5Bar.high >= tr.tpPrice)
              {
               tr.statusNote = "CANCEL_HIT_TP_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_INTRADAY);
               return;
              }
           }
         else
           {
            if(m5Bar.high >= tr.slPrice)
              {
               tr.statusNote = "CANCEL_HIT_SL_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_INTRADAY);
               return;
              }
            if(m5Bar.low <= tr.tpPrice)
              {
               tr.statusNote = "CANCEL_HIT_TP_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_INTRADAY);
               return;
              }
           }
        }
     }

   //--- Step Machine for Scalping Setup (M15/M5 POIs, London & NY AM Q2/Q3 90m blocks)
   void              StepScalpTracker(SSetupTracker &tr,
                                      CMTFDataManager &mtf,
                                      CSwingEngine &swings,
                                      CMSNREngine &msnr,
                                      CICTEngine &ict,
                                      const QTState &qtState,
                                      const SBiasState &biasState,
                                      const STradeProfileSpec &prof,
                                      const double currentSpreadPrice,
                                      const bool isNewsBlocked,
                                      const string newsReason)
     {
      MqlRates m5Bar;
      if(!mtf.GetClosedBar(TF_IDX_M5, 1, m5Bar))
         return;

      bool biasGateOk = prof.CheckBiasGate(tr.direction, biasState.biasW1, biasState.biasD1, biasState.biasH4);

      // Invalidation checks for active pre-trade setup (S1..S4)
      if(tr.state >= SETUP_S1_POI_TOUCH && tr.state <= SETUP_S4_ARMED)
        {
         if(m5Bar.time > tr.lastM5BarTime)
           {
            tr.ageBarsM5++;
            tr.lastM5BarTime = m5Bar.time;
           }

         if(isNewsBlocked)
           {
            tr.statusNote = "REJECT_NEWS: " + newsReason;
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }
         if(!qtState.isScalpTimeAllowed)
           {
            tr.statusNote = "CANCEL_SCALP_WINDOW_ENDED";
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }
         if(!biasGateOk)
           {
            tr.statusNote = "CANCEL_BIAS_GATE_FLIPPED";
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }
         // Scalping max lifespan: 18 M5 bars = 90 minutes (1 block)
         if(tr.ageBarsM5 > 18)
           {
            tr.statusNote = "CANCEL_SCALP_EXPIRED_90M";
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }
         if((tr.direction == BIAS_BULL && m5Bar.close < tr.anchorPOI.zoneLow) ||
            (tr.direction == BIAS_BEAR && m5Bar.close > tr.anchorPOI.zoneHigh))
           {
            tr.statusNote = "CANCEL_POI_BODY_BROKEN";
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }
        }

      // S0: IDLE -> Wait for Scalp permission + Fresh POI touch (AMDX Continuation or Sniper)
      if(tr.state == SETUP_S0_IDLE)
        {
         if(!biasGateOk || !qtState.isScalpTimeAllowed || isNewsBlocked)
            return;

         // v1.32 Scalping Toxic Day & Session Filters
         if(!m_cfg.scalpAllowThursday && qtState.dayeDayOfWeek == 4)
            return;

         if(m_cfg.scalpSessionMode == SCALP_SESS_LONDON_Q3_ONLY)
           {
            if(qtState.session != QT_SESSION_LONDON || qtState.q90 != QT_Q3)
               return;
           }
         else if(m_cfg.scalpSessionMode == SCALP_SESS_LONDON_ONLY)
           {
            if(qtState.session != QT_SESSION_LONDON)
               return;
           }

         SMSNRLevel anchor;
         int overlaps = 0;
         bool isSniper = false;
         SSweepEvent sniperSweep;

         if(FindTouchedScalpPOI(tr.direction, m5Bar, msnr, ict, biasState, qtState, prof, currentSpreadPrice, anchor, overlaps, isSniper, sniperSweep))
           {
            m_seqCounter++;
            tr.Reset(tr.direction, PROFILE_SCALPING);
            tr.setupId            = StringFormat("QT_SCALP_%s_%I64d_%d",
                                                 (tr.direction == BIAS_BULL ? "BUY" : "SELL"),
                                                 (long)m5Bar.time,
                                                 m_seqCounter);
            tr.profile            = PROFILE_SCALPING;
            tr.createdTime        = qtState.serverTime;
            tr.lastM5BarTime      = m5Bar.time;
            tr.ageBarsM5          = 0;
            tr.weekQ              = qtState.weekQ;
            tr.dayQ               = qtState.dayQ;
            tr.session            = qtState.session;
            tr.q90                = qtState.q90;
            tr.anchorPOI          = anchor;
            tr.hasRefinedPOI      = false;
            tr.poiOverlapCount    = overlaps;
            tr.isDailyCycleSetup  = biasState.dailyCycle.isActive;
            tr.cycleType          = biasState.dailyCycle.cycleType;
            tr.amdxPhase          = biasState.dailyCycle.currentPhase;
            tr.narrative          = biasState.dailyCycle.narrative;

            if(isSniper)
              {
               tr.isSniperSetup = true;
               tr.sweep         = sniperSweep;
               tr.state         = SETUP_S2_SWEEP;
               tr.statusNote    = "S2_SNIPER_SWEEP_CONFIRMED";
              }
            else
              {
               tr.isSniperSetup = false;
               tr.state         = SETUP_S1_POI_TOUCH;
               tr.statusNote    = "S1_POI_TOUCH";
              }
           }
        }

      // S1: POI_TOUCH -> Wait for Sweep on M5
      if(tr.state == SETUP_S1_POI_TOUCH)
        {
         SSweepEvent swEv;
         if(CheckSweepForHTFSetup(tr, mtf, ict, prof, swEv))
           {
            tr.sweep      = swEv;
            tr.state      = SETUP_S2_SWEEP;
            tr.statusNote = "S2_SWEEP_CONFIRMED";
           }
        }

      // S2: SWEEP -> Wait for MSS or CISD confirmation
      if(tr.state == SETUP_S2_SWEEP)
        {
         bool confirmed = false;

         // 1. Check CISD (Change in State of Delivery) on M5 if enabled
         if(m_cfg.confirmMode == CONFIRM_MODE_CISD_ONLY || m_cfg.confirmMode == CONFIRM_MODE_EITHER)
           {
            MqlRates m5Rates[];
            int m5Cnt = mtf.GetClosedRatesArray(TF_IDX_M5, m5Rates);
            SCISDResult cisdRes;
            if(CICTEngine::CheckCISDAfterSweepOrTouch(m5Rates, m5Cnt, tr.sweep.sweepBarTime, tr.direction, TF_IDX_M5, cisdRes))
              {
               tr.isCisdConfirmed      = true;
               tr.cisd                 = cisdRes;
               tr.mss.confirmed        = true;
               tr.mss.direction        = tr.direction;
               tr.mss.tfIdx            = TF_IDX_M5;
               tr.mss.mssBarTime       = cisdRes.cisdBarTime;
               tr.mss.mssClosedShift   = cisdRes.cisdClosedShift;
               tr.mss.brokenSwingPrice = cisdRes.deliveryOpenPrice;
               tr.mss.brokenSwingTime  = cisdRes.deliveryStartTime;
               tr.state                = SETUP_S3_MSS;
               tr.statusNote           = "S3_CISD_CONFIRMED";
               confirmed               = true;
              }
           }

         // 2. Check MSS if not already confirmed by CISD
         if(!confirmed && (m_cfg.confirmMode == CONFIRM_MODE_MSS_ONLY || m_cfg.confirmMode == CONFIRM_MODE_EITHER))
           {
            if(!ict.GetConfig().useMSS)
              {
               tr.mss.confirmed        = true;
               tr.mss.direction        = tr.direction;
               tr.mss.tfIdx            = TF_IDX_M5;
               tr.mss.mssBarTime       = m5Bar.time;
               tr.mss.mssClosedShift   = 1;
               tr.mss.brokenSwingPrice = tr.sweep.sweptLevelPrice;
               tr.state                = SETUP_S3_MSS;
               tr.statusNote           = "S3_MSS_BYPASSED";
              }
            else
              {
               int checkTfs[2] = { TF_IDX_M5, TF_IDX_M15 };
               for(int k = 0; k < 2; k++)
                 {
                  int tfIdx = checkTfs[k];
                  MqlRates tRates[];
                  int rCnt = mtf.GetClosedRatesArray(tfIdx, tRates);
                  int sCnt = swings.GetWickSwingCount(tfIdx);
                  SSwingPoint wSwings[];
                  ArrayResize(wSwings, sCnt);
                  for(int i = 0; i < sCnt; i++)
                     swings.GetWickSwing(tfIdx, i, wSwings[i]);

                  SMSSResult mssRes;
                  if(CICTEngine::CheckMSSAfterSweep(tRates, rCnt, wSwings, sCnt, tr.sweep, tfIdx, mssRes))
                    {
                     tr.mss        = mssRes;
                     tr.state      = SETUP_S3_MSS;
                     tr.statusNote = "S3_MSS_CONFIRMED";
                     break;
                    }
                 }
              }
           }
        }

      // S3: MSS -> Wait for FVG & Validate Parameters
      if(tr.state == SETUP_S3_MSS)
        {
         SFVGZone fvgFound;
         bool gotFvg = ict.FindRecentTradableFVG(TF_IDX_M5, tr.direction, tr.sweep.sweepBarTime, fvgFound);
         if(!gotFvg && m_cfg.entryType != ENTRY_MARKET_MSS && !tr.isCisdConfirmed)
            return;

         tr.hasFvg = gotFvg;
         tr.fvg    = fvgFound;

         // 1. Entry Price (Proximal Edge / IOFED or CE or Market or CISD Open)
         if(m_cfg.entryType == ENTRY_MARKET_MSS)
           {
            tr.isMarketOrder = true;
            tr.entryPrice    = m5Bar.close;
           }
         else if(gotFvg)
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = (m_cfg.entryType == ENTRY_FVG_CE ? fvgFound.ce : fvgFound.proximal);
           }
         else if(tr.isCisdConfirmed && tr.cisd.deliveryOpenPrice > 0.0)
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = tr.cisd.deliveryOpenPrice;
           }
         else
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = tr.anchorPOI.price;
           }

         // 2. Stop Loss: 50 pips ($5.00) user specified
         double targetSlDist = QTPipsToPrice(_Symbol, (m_cfg.scalpSlPips > 0.0 ? m_cfg.scalpSlPips : 50.0));
         double minSlDist    = QTPipsToPrice(_Symbol, 35.0);
         double maxSlDist    = QTPipsToPrice(_Symbol, 50.0);
         double atrM5        = mtf.GetATR(TF_IDX_M5);
         double slBuffer     = m_cfg.slBufferAtrMultM5 * atrM5 + currentSpreadPrice;

         if(tr.direction == BIAS_BULL)
           {
            double baseLow   = MathMin(tr.sweep.extremeWickPrice, m5Bar.low);
            tr.slPrice       = baseLow - slBuffer;
            double rawSlDist = tr.entryPrice - tr.slPrice;
            if(rawSlDist < minSlDist || rawSlDist > maxSlDist)
               tr.slPrice = tr.entryPrice - targetSlDist;

            if(m5Bar.close <= tr.slPrice)
              {
               tr.statusNote = "REJECT_PRICE_BELOW_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SCALPING);
               return;
              }
           }
         else
           {
            double baseHigh  = MathMax(tr.sweep.extremeWickPrice, m5Bar.high);
            tr.slPrice       = baseHigh + slBuffer;
            double rawSlDist = tr.slPrice - tr.entryPrice;
            if(rawSlDist < minSlDist || rawSlDist > maxSlDist)
               tr.slPrice = tr.entryPrice + targetSlDist;

            if(m5Bar.close >= tr.slPrice)
              {
               tr.statusNote = "REJECT_PRICE_ABOVE_SL";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SCALPING);
               return;
              }
           }

         double slDist = (tr.direction == BIAS_BULL ? (tr.entryPrice - tr.slPrice)
                                                    : (tr.slPrice - tr.entryPrice));
         if(slDist <= 1e-5)
           {
            tr.statusNote = "REJECT_INVALID_SL_DISTANCE";
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }

         // 3. Take Profit: 100 pips max ($10.00); BE and Partial: 50 pips ($5.00)
         double tpDist  = QTPipsToPrice(_Symbol, (m_cfg.scalpTpPips > 0.0 ? m_cfg.scalpTpPips : 100.0));
         double tp1Dist = QTPipsToPrice(_Symbol, (m_cfg.scalpPartialPips > 0.0 ? m_cfg.scalpPartialPips : 50.0));

         tr.tpPrice  = (tr.direction == BIAS_BULL ? tr.entryPrice + tpDist  : tr.entryPrice - tpDist);
         tr.tp1Price = (tr.direction == BIAS_BULL ? tr.entryPrice + tp1Dist : tr.entryPrice - tp1Dist);
         tr.dolLabel = (tr.isSniperSetup ? "SCALP_SNIPER_100P" : "SCALP_TP_100P");

         double reward = (tr.direction == BIAS_BULL ? (tr.tpPrice - tr.entryPrice)
                                                    : (tr.entryPrice - tr.tpPrice));
         tr.rrRatio = (reward > 0.0 ? reward / slDist : 0.0);

         if(tr.rrRatio + 1e-5 < prof.minRR)
           {
            tr.statusNote = StringFormat("REJECT_RR_BELOW_MIN (%.2f < %.2f)", tr.rrRatio, prof.minRR);
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }

         // 4. Confluence Score (Scalp threshold: 5)
         CalcConfluenceScore(tr, qtState, biasState, prof, tr.score);
         if(tr.score.totalScore < 5)
           {
            tr.statusNote = StringFormat("REJECT_LOW_SCORE (%d < 5)", tr.score.totalScore);
            PushLogEvent(tr);
            tr.Reset(tr.direction, PROFILE_SCALPING);
            return;
           }

         // 4b. v1.32 Weak POI Filter for Scalping (M15 RBS and Classic V require score >= 12)
         if(m_cfg.scalpFilterWeakPoi)
           {
            if((tr.anchorPOI.type == POI_RBS && tr.anchorPOI.tfIdx == TF_IDX_M15) ||
               (tr.anchorPOI.type == POI_CLASSIC_V && tr.anchorPOI.tfIdx == TF_IDX_M15))
              {
               if(tr.score.totalScore < 12)
                 {
                  tr.statusNote = StringFormat("REJECT_WEAK_M15_POI (%s score %d < 12)",
                                               tr.anchorPOI.id, tr.score.totalScore);
                  PushLogEvent(tr);
                  tr.Reset(tr.direction, PROFILE_SCALPING);
                  return;
                 }
              }
           }

         tr.state      = SETUP_S4_ARMED;
         tr.armedTime  = qtState.serverTime;
         tr.statusNote = (tr.isSniperSetup ? "ARMED_SNIPER_SCALP" : "ARMED_VALID");
         PushLogEvent(tr);
        }

      // S4: ARMED -> Price cancellation check
      if(tr.state == SETUP_S4_ARMED)
        {
         if(tr.direction == BIAS_BULL)
           {
            if(m5Bar.low <= tr.slPrice)
              {
               tr.statusNote = "CANCEL_HIT_SL_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SCALPING);
               return;
              }
            if(m5Bar.high >= tr.tpPrice)
              {
               tr.statusNote = "CANCEL_HIT_TP_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SCALPING);
               return;
              }
           }
         else
           {
            if(m5Bar.high >= tr.slPrice)
              {
               tr.statusNote = "CANCEL_HIT_SL_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SCALPING);
               return;
              }
            if(m5Bar.low <= tr.tpPrice)
              {
               tr.statusNote = "CANCEL_HIT_TP_BEFORE_ENTRY";
               PushLogEvent(tr);
               tr.Reset(tr.direction, PROFILE_SCALPING);
               return;
              }
           }
        }
     }

public:
                     CSetupEngine()
     {
      m_cfg.SetDefaults();
      m_buySwing.Reset(BIAS_BULL, PROFILE_SWING);
      m_sellSwing.Reset(BIAS_BEAR, PROFILE_SWING);
      m_buyIntra.Reset(BIAS_BULL, PROFILE_INTRADAY);
      m_sellIntra.Reset(BIAS_BEAR, PROFILE_INTRADAY);
      m_buyScalp.Reset(BIAS_BULL, PROFILE_SCALPING);
      m_sellScalp.Reset(BIAS_BEAR, PROFILE_SCALPING);
      ArrayResize(m_logQueue, 0);
      m_seqCounter                  = 0;
      m_lastDailyCycleDayKey        = 0;
      m_dailyCycleTradesFilledToday = 0;
     }

   void              Init(const SSetupConfig &cfg)
     {
      m_cfg = cfg;
      m_buySwing.Reset(BIAS_BULL, PROFILE_SWING);
      m_sellSwing.Reset(BIAS_BEAR, PROFILE_SWING);
      m_buyIntra.Reset(BIAS_BULL, PROFILE_INTRADAY);
      m_sellIntra.Reset(BIAS_BEAR, PROFILE_INTRADAY);
      m_buyScalp.Reset(BIAS_BULL, PROFILE_SCALPING);
      m_sellScalp.Reset(BIAS_BEAR, PROFILE_SCALPING);
      ArrayResize(m_logQueue, 0);
      m_lastDailyCycleDayKey        = 0;
      m_dailyCycleTradesFilledToday = 0;
     }

   SSetupConfig      GetConfig() const { return m_cfg; }

   // Retrieve setup for a specific profile and direction
   SSetupTracker     GetSetup(const ENUM_TRADE_PROFILE prof, const ENUM_BIAS_DIR dir) const
     {
      if(prof == PROFILE_SCALPING) return (dir == BIAS_BULL ? m_buyScalp : m_sellScalp);
      if(prof == PROFILE_SWING)    return (dir == BIAS_BULL ? m_buySwing : m_sellSwing);
      return (dir == BIAS_BULL ? m_buyIntra : m_sellIntra);
     }

   // Return all armed setups across all 3 active profiles
   int               GetArmedSetups(SSetupTracker &outSetups[]) const
     {
      ArrayResize(outSetups, 0);
      int cnt = 0;

      // Check Swing
      if(m_buySwing.state == SETUP_S4_ARMED)  { ArrayResize(outSetups, cnt + 1); outSetups[cnt++] = m_buySwing; }
      if(m_sellSwing.state == SETUP_S4_ARMED) { ArrayResize(outSetups, cnt + 1); outSetups[cnt++] = m_sellSwing; }

      // Check Intraday
      if(m_buyIntra.state == SETUP_S4_ARMED)  { ArrayResize(outSetups, cnt + 1); outSetups[cnt++] = m_buyIntra; }
      if(m_sellIntra.state == SETUP_S4_ARMED) { ArrayResize(outSetups, cnt + 1); outSetups[cnt++] = m_sellIntra; }

      // Check Scalping
      if(m_buyScalp.state == SETUP_S4_ARMED)  { ArrayResize(outSetups, cnt + 1); outSetups[cnt++] = m_buyScalp; }
      if(m_sellScalp.state == SETUP_S4_ARMED) { ArrayResize(outSetups, cnt + 1); outSetups[cnt++] = m_sellScalp; }

      return cnt;
     }

   // Backward-compatible getters
   SSetupTracker     GetBuySetup() const
     {
      if(m_buyIntra.orderTicket > 0 || m_buyIntra.state == SETUP_S4_ARMED)
         return m_buyIntra;
      if(m_buySwing.orderTicket > 0 || m_buySwing.state == SETUP_S4_ARMED)
         return m_buySwing;
      if(m_buyScalp.orderTicket > 0 || m_buyScalp.state == SETUP_S4_ARMED)
         return m_buyScalp;
      if(m_buyIntra.state != SETUP_S0_IDLE)
         return m_buyIntra;
      if(m_buySwing.state != SETUP_S0_IDLE)
         return m_buySwing;
      return m_buyScalp;
     }

   SSetupTracker     GetSellSetup() const
     {
      if(m_sellIntra.orderTicket > 0 || m_sellIntra.state == SETUP_S4_ARMED)
         return m_sellIntra;
      if(m_sellSwing.orderTicket > 0 || m_sellSwing.state == SETUP_S4_ARMED)
         return m_sellSwing;
      if(m_sellScalp.orderTicket > 0 || m_sellScalp.state == SETUP_S4_ARMED)
         return m_sellScalp;
      if(m_sellIntra.state != SETUP_S0_IDLE)
         return m_sellIntra;
      if(m_sellSwing.state != SETUP_S0_IDLE)
         return m_sellSwing;
      return m_sellScalp;
     }

   bool              PopLastLogEvent(SSetupTracker &outSetup)
     {
      int cnt = ArraySize(m_logQueue);
      if(cnt <= 0)
         return false;
      outSetup = m_logQueue[0];
      for(int i = 0; i < cnt - 1; i++)
         m_logQueue[i] = m_logQueue[i + 1];
      ArrayResize(m_logQueue, cnt - 1);
      return true;
     }

   //+------------------------------------------------------------------+
   //| Confluence Score Calculator (PRD 4.7 + 4.10 + M15/M5 Refinement) |
   //+------------------------------------------------------------------+
   static void       CalcConfluenceScore(const SSetupTracker &tr,
                                         const QTState &qtState,
                                         const SBiasState &biasState,
                                         const STradeProfileSpec &prof,
                                         SConfluenceBreakdown &outScore)
     {
      outScore.Reset();

      // 1. TF POI Points: W1/D1 = 3, H4 = 2, H1 = 1, M15/M5 = 1
      switch(tr.anchorPOI.tfIdx)
        {
         case TF_IDX_W1:
         case TF_IDX_D1:  outScore.ptsPoiTF = 3; break;
         case TF_IDX_H4:  outScore.ptsPoiTF = 2; break;
         default:         outScore.ptsPoiTF = 1; break; // H1, M15, M5
        }

      // 2. POI Type Points: QM or RBS/SBR = 2, Classic A or V = 1
      ENUM_POI_TYPE pType = tr.anchorPOI.type;
      if(pType == POI_QM_BULL || pType == POI_QM_BEAR || pType == POI_RBS || pType == POI_SBR)
         outScore.ptsPoiType = 2;
      else
         outScore.ptsPoiType = 1;

      // 3. Multi-TF POI Overlap / M15-M5 Refinement (+1 per TF, max +2)
      outScore.ptsPoiOverlap = MathMin(2, MathMax(0, tr.poiOverlapCount));

      // 4. 90-Minute Cycle Q2 or Q3 (+1)
      if(qtState.q90 == QT_Q2 || qtState.q90 == QT_Q3)
         outScore.ptsQ90 = 1;

      // 5. London Q2 or NY AM Q3 Session (+1)
      if(qtState.session == QT_SESSION_LONDON || qtState.session == QT_SESSION_NY_AM)
         outScore.ptsSession = 1;

      // 6. True Day Open & True Week Open Discount/Premium Alignment (+1 each)
      if(tr.direction == BIAS_BULL)
        {
         if(biasState.isBelowTrueDayOpen)  outScore.ptsTrueDayOpen  = 1;
         if(biasState.isBelowTrueWeekOpen) outScore.ptsTrueWeekOpen = 1;
        }
      else
        {
         if(biasState.isAboveTrueDayOpen)  outScore.ptsTrueDayOpen  = 1;
         if(biasState.isAboveTrueWeekOpen) outScore.ptsTrueWeekOpen = 1;
        }

      // 7. Sweep of EQH/EQL, PDH/PDL, or Session Extreme (+2; minor swing sweep +1)
      if(tr.sweep.valid)
         outScore.ptsSweep = (tr.sweep.isMajorPool ? 2 : 1);

      // 8. FVG present on displacement leg (+1)
      if(tr.hasFvg)
         outScore.ptsFvg = 1;

      // 8b. Institutional Sniper Entry Bonus (+2)
      if(tr.isSniperSetup)
         outScore.ptsSniper = 2;

      // 9. Trade Profile Score TFs (+1 aligned, 0 neutral, -1 opposing)
      outScore.ptsBiasScoreTF = prof.CalcBiasScoreBonus(tr.direction,
                                                        biasState.biasW1,
                                                        biasState.biasD1,
                                                        biasState.biasH4);

      outScore.totalScore = outScore.ptsPoiTF +
                            outScore.ptsPoiType +
                            outScore.ptsPoiOverlap +
                            outScore.ptsQ90 +
                            outScore.ptsSession +
                            outScore.ptsTrueDayOpen +
                            outScore.ptsTrueWeekOpen +
                            outScore.ptsSweep +
                            outScore.ptsSniper +
                            outScore.ptsFvg +
                            outScore.ptsBiasScoreTF;
     }

   //+------------------------------------------------------------------+
   //| Update Multi-Profile Tri-Engine Trackers                         |
   //+------------------------------------------------------------------+
   void              UpdateAllProfiles(CMTFDataManager &mtf,
                                       CSwingEngine &swings,
                                       CMSNREngine &msnr,
                                       CICTEngine &ict,
                                       const QTState &qtState,
                                       const SBiasState &biasState,
                                       const STradeProfileSpec &scalpSpec,
                                       const STradeProfileSpec &intraSpec,
                                       const STradeProfileSpec &swingSpec,
                                       const double currentSpreadPrice,
                                       const bool isNewsBlocked,
                                       const string newsReason,
                                       const bool enableScalp = true,
                                       const bool enableIntra = true,
                                       const bool enableSwing = true)
     {
      int curDayKey = qtState.dayeYear * 10000 + qtState.dayeMonth * 100 + qtState.dayeDay;
      if(curDayKey != m_lastDailyCycleDayKey)
        {
         m_lastDailyCycleDayKey        = curDayKey;
         m_dailyCycleTradesFilledToday = 0;
        }

      // 1. Step Swing Trackers (HTF MSNR POI Engine)
      if(enableSwing)
        {
         StepHTFTracker(m_buySwing,  mtf, swings, msnr, ict, qtState, biasState, swingSpec, currentSpreadPrice, isNewsBlocked, newsReason);
         StepHTFTracker(m_sellSwing, mtf, swings, msnr, ict, qtState, biasState, swingSpec, currentSpreadPrice, isNewsBlocked, newsReason);
        }

      // 2. Step Intraday Trackers (AMDX / XAMD Engine)
      if(enableIntra && m_cfg.enableDailyAmdxCycle)
        {
         StepCycleTracker(m_buyIntra,  mtf, swings, msnr, ict, qtState, biasState, intraSpec, currentSpreadPrice, isNewsBlocked, newsReason);
         StepCycleTracker(m_sellIntra, mtf, swings, msnr, ict, qtState, biasState, intraSpec, currentSpreadPrice, isNewsBlocked, newsReason);
        }

      // 3. Step Scalping Trackers (M15/M5 Engine)
      if(enableScalp)
        {
         StepScalpTracker(m_buyScalp,  mtf, swings, msnr, ict, qtState, biasState, scalpSpec, currentSpreadPrice, isNewsBlocked, newsReason);
         StepScalpTracker(m_sellScalp, mtf, swings, msnr, ict, qtState, biasState, scalpSpec, currentSpreadPrice, isNewsBlocked, newsReason);
        }
     }

   // Backward-compatible Update
   void              Update(CMTFDataManager &mtf,
                            CSwingEngine &swings,
                            CMSNREngine &msnr,
                            CICTEngine &ict,
                            const QTState &qtState,
                            const SBiasState &biasState,
                            const STradeProfileSpec &prof,
                            const double currentSpreadPrice,
                            const bool isNewsBlocked,
                            const string newsReason)
     {
      UpdateAllProfiles(mtf, swings, msnr, ict, qtState, biasState,
                        prof, prof, prof, currentSpreadPrice, isNewsBlocked, newsReason,
                        true, true, true);
     }

   //--- Transition helpers called by Execution Engine (M8)
   void              NotifyOrderPlaced(const ENUM_BIAS_DIR dir, const ulong ticket, const int profile = -1)
     {
      if(dir == BIAS_BULL)
        {
         if((profile < 0 || profile == PROFILE_SWING) && m_buySwing.state == SETUP_S4_ARMED)
            m_buySwing.orderTicket = ticket;
         if((profile < 0 || profile == PROFILE_INTRADAY) && m_buyIntra.state == SETUP_S4_ARMED)
            m_buyIntra.orderTicket = ticket;
         if((profile < 0 || profile == PROFILE_SCALPING) && m_buyScalp.state == SETUP_S4_ARMED)
            m_buyScalp.orderTicket = ticket;
        }
      else if(dir == BIAS_BEAR)
        {
         if((profile < 0 || profile == PROFILE_SWING) && m_sellSwing.state == SETUP_S4_ARMED)
            m_sellSwing.orderTicket = ticket;
         if((profile < 0 || profile == PROFILE_INTRADAY) && m_sellIntra.state == SETUP_S4_ARMED)
            m_sellIntra.orderTicket = ticket;
         if((profile < 0 || profile == PROFILE_SCALPING) && m_sellScalp.state == SETUP_S4_ARMED)
            m_sellScalp.orderTicket = ticket;
        }
     }

   void              NotifyTradeFilled(const ENUM_BIAS_DIR dir, const ulong ticket, CMSNREngine &msnr, const int profile = -1)
     {
      if(dir == BIAS_BULL)
        {
         if((profile < 0 || profile == PROFILE_SWING) && (m_buySwing.orderTicket == ticket || m_buySwing.state == SETUP_S4_ARMED))
           {
            m_buySwing.state       = SETUP_S5_IN_TRADE;
            m_buySwing.orderTicket = ticket;
            msnr.MarkLevelUsed(m_buySwing.anchorPOI.id);
            if(m_buySwing.hasRefinedPOI)
               msnr.MarkLevelUsed(m_buySwing.refinedPOI.id);
           }
         if((profile < 0 || profile == PROFILE_INTRADAY) && (m_buyIntra.orderTicket == ticket || m_buyIntra.state == SETUP_S4_ARMED))
           {
            m_buyIntra.state       = SETUP_S5_IN_TRADE;
            m_buyIntra.orderTicket = ticket;
            msnr.MarkLevelUsed(m_buyIntra.anchorPOI.id);
            m_dailyCycleTradesFilledToday++;
           }
         if((profile < 0 || profile == PROFILE_SCALPING) && (m_buyScalp.orderTicket == ticket || m_buyScalp.state == SETUP_S4_ARMED))
           {
            m_buyScalp.state       = SETUP_S5_IN_TRADE;
            m_buyScalp.orderTicket = ticket;
            msnr.MarkLevelUsed(m_buyScalp.anchorPOI.id);
           }
        }
      else if(dir == BIAS_BEAR)
        {
         if((profile < 0 || profile == PROFILE_SWING) && (m_sellSwing.orderTicket == ticket || m_sellSwing.state == SETUP_S4_ARMED))
           {
            m_sellSwing.state       = SETUP_S5_IN_TRADE;
            m_sellSwing.orderTicket = ticket;
            msnr.MarkLevelUsed(m_sellSwing.anchorPOI.id);
            if(m_sellSwing.hasRefinedPOI)
               msnr.MarkLevelUsed(m_sellSwing.refinedPOI.id);
           }
         if((profile < 0 || profile == PROFILE_INTRADAY) && (m_sellIntra.orderTicket == ticket || m_sellIntra.state == SETUP_S4_ARMED))
           {
            m_sellIntra.state       = SETUP_S5_IN_TRADE;
            m_sellIntra.orderTicket = ticket;
            msnr.MarkLevelUsed(m_sellIntra.anchorPOI.id);
            m_dailyCycleTradesFilledToday++;
           }
         if((profile < 0 || profile == PROFILE_SCALPING) && (m_sellScalp.orderTicket == ticket || m_sellScalp.state == SETUP_S4_ARMED))
           {
            m_sellScalp.state       = SETUP_S5_IN_TRADE;
            m_sellScalp.orderTicket = ticket;
            msnr.MarkLevelUsed(m_sellScalp.anchorPOI.id);
           }
        }
     }

   void              NotifySetupCompleted(const ENUM_BIAS_DIR dir, const string reason, const int profile = -1)
     {
      if(dir == BIAS_BULL)
        {
         if((profile < 0 || profile == PROFILE_SWING) && (m_buySwing.orderTicket > 0 || m_buySwing.state >= SETUP_S4_ARMED))
           {
            m_buySwing.statusNote = reason;
            m_buySwing.Reset(BIAS_BULL, PROFILE_SWING);
           }
         if((profile < 0 || profile == PROFILE_INTRADAY) && (m_buyIntra.orderTicket > 0 || m_buyIntra.state >= SETUP_S4_ARMED))
           {
            m_buyIntra.statusNote = reason;
            m_buyIntra.Reset(BIAS_BULL, PROFILE_INTRADAY);
           }
         if((profile < 0 || profile == PROFILE_SCALPING) && (m_buyScalp.orderTicket > 0 || m_buyScalp.state >= SETUP_S4_ARMED))
           {
            m_buyScalp.statusNote = reason;
            m_buyScalp.Reset(BIAS_BULL, PROFILE_SCALPING);
           }
        }
      else if(dir == BIAS_BEAR)
        {
         if((profile < 0 || profile == PROFILE_SWING) && (m_sellSwing.orderTicket > 0 || m_sellSwing.state >= SETUP_S4_ARMED))
           {
            m_sellSwing.statusNote = reason;
            m_sellSwing.Reset(BIAS_BEAR, PROFILE_SWING);
           }
         if((profile < 0 || profile == PROFILE_INTRADAY) && (m_sellIntra.orderTicket > 0 || m_sellIntra.state >= SETUP_S4_ARMED))
           {
            m_sellIntra.statusNote = reason;
            m_sellIntra.Reset(BIAS_BEAR, PROFILE_INTRADAY);
           }
         if((profile < 0 || profile == PROFILE_SCALPING) && (m_sellScalp.orderTicket > 0 || m_sellScalp.state >= SETUP_S4_ARMED))
           {
            m_sellScalp.statusNote = reason;
            m_sellScalp.Reset(BIAS_BEAR, PROFILE_SCALPING);
           }
        }
     }
  };

#endif // QT_SETUP_MQH
//+------------------------------------------------------------------+
