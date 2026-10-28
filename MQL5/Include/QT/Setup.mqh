//+------------------------------------------------------------------+
//| Setup.mqh                                                        |
//| M7 - Setup State Machine (S0..S6), M15/M5 POI Refinement & Score |
//| Place in: MQL5/Include/QT/Setup.mqh                              |
//|                                                                  |
//| State Machine per Direction (BUY / SELL):                        |
//|  S0 IDLE      -> Bias aligned, Daye day & session/90m allowed    |
//|  S1 POI_TOUCH -> Price touches Fresh MSNR POI (H4/H1/D1 + M15/M5)|
//|  S2 SWEEP     -> Liquidity sweep inside/near POI on Trigger TF   |
//|  S3 MSS       -> Body close breaks opposing swing (displacement) |
//|  S4 ARMED     -> FVG / M15-M5 POI ready; Score & RR validated    |
//|  S5 IN_TRADE  -> Order filled & active                           |
//|  S6 DONE      -> Completed, expired, or invalidated              |
//+------------------------------------------------------------------+
#ifndef QT_SETUP_MQH
#define QT_SETUP_MQH

#include "Bias.mqh"

struct SSetupConfig
  {
   int             minConfluenceScore; // Default 6
   double          customMinRR;        // 0.0 = use profile default (1.5 / 2.0 / 3.0)
   int             maxSetupBarsM5;     // Max age of setup in M5 bars (default 36 = 3 hours)
   ENUM_ENTRY_TYPE entryType;          // ENTRY_FVG_CE (default), ENTRY_FVG_PROXIMAL, ENTRY_MARKET_MSS
   double          slBufferAtrMultM5;  // SL buffer = mult * ATR(M5) + spread (default 0.20)
   double          maxSlAtrMultH1;     // Max SL width = mult * ATR(H1) (default 2.50)
   bool            useM15M5Refinement; // Enable M15/M5 MSNR POI refinement for sharper entry

   void SetDefaults()
     {
      minConfluenceScore = 6;
      customMinRR        = 0.0;
      maxSetupBarsM5     = 36;
      entryType          = ENTRY_FVG_CE;
      slBufferAtrMultM5  = 0.20;
      maxSlAtrMultH1     = 2.50;
      useM15M5Refinement = true;
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
      ptsFvg          = 0;
      ptsBiasScoreTF  = 0;
      totalScore      = 0;
     }
  };

struct SSetupTracker
  {
   string               setupId;
   ENUM_BIAS_DIR        direction;        // BIAS_BULL (Buy) or BIAS_BEAR (Sell)
   ENUM_SETUP_STATE     state;            // S0_IDLE .. S6_DONE
   datetime             createdTime;      // Server time when S1_POI_TOUCH started
   datetime             armedTime;        // Server time when S4_ARMED was reached
   datetime             lastM5BarTime;    // For tracking age in M5 bars
   int                  ageBarsM5;        // Number of M5 bars elapsed since S1_POI_TOUCH

   // Layer 1: QT Time Snapshot at trigger
   ENUM_QT_QUARTER      weekQ;
   ENUM_QT_QUARTER      dayQ;
   ENUM_QT_SESSION      session;
   ENUM_QT_QUARTER      q90;

   // Layer 2: MSNR POI (HTF Anchor + optional M15/M5 Refinement)
   SMSNRLevel           anchorPOI;        // Primary touched POI (e.g. H4/H1 or M15/M5)
   bool                 hasRefinedPOI;    // True if a nested M15/M5 fresh POI refined the zone
   SMSNRLevel           refinedPOI;       // M15/M5 refined MSNR POI
   int                  poiOverlapCount;  // Multi-TF overlap count

   // Layer 3: ICT Sweep, MSS & FVG
   SSweepEvent          sweep;
   SMSSResult           mss;
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

   void Reset(const ENUM_BIAS_DIR dir = BIAS_BULL)
     {
      setupId         = "";
      direction       = dir;
      state           = SETUP_S0_IDLE;
      createdTime     = 0;
      armedTime       = 0;
      lastM5BarTime   = 0;
      ageBarsM5       = 0;
      weekQ           = QT_Q0;
      dayQ            = QT_Q0;
      session         = QT_SESSION_ASIA;
      q90             = QT_Q0;
      anchorPOI.Reset();
      hasRefinedPOI   = false;
      refinedPOI.Reset();
      poiOverlapCount = 0;
      sweep.Reset();
      mss.Reset();
      hasFvg          = false;
      fvg.Reset();
      isMarketOrder   = false;
      entryPrice      = 0.0;
      slPrice         = 0.0;
      tpPrice         = 0.0;
      tp1Price        = 0.0;
      dolLabel        = "";
      rrRatio         = 0.0;
      score.Reset();
      statusNote      = "";
      loggedToCsv     = false;
      orderTicket     = 0;
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
   SSetupTracker     m_buySetup;
   SSetupTracker     m_sellSetup;
   SSetupTracker     m_lastEvaluatedSetup; // Snapshot of most recent S4/rejected setup for CSV logging
   bool              m_hasNewLogEvent;
   int               m_seqCounter;

   //--- Find a Fresh M15/M5 MSNR POI nested inside an HTF (W1/D1/H4/H1) Body-to-Wick Anchor Zone
   bool              FindNestedRefinedPOI(const SMSNRLevel &anchor,
                                          CMSNREngine &msnr,
                                          const double refPrice,
                                          SMSNRLevel &outRefined) const
     {
      outRefined.Reset();
      if(anchor.tfIdx > TF_IDX_H1)
         return false; // Anchor is already LTF (M15/M5)

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

            // Check if LTF POI price or zone is nested inside the HTF Body-to-Wick Anchor Zone
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

   //--- Find best touched Fresh POI on allowed timeframes (prioritizing HTF + M15/M5 nested refinement)
   bool              FindTouchedPOI(const ENUM_BIAS_DIR dir,
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

      bool foundAnchor = false;
      double proximityMargin = m5Bar.high - m5Bar.low;

      // 1. Scan from highest TF (W1=0) to lowest TF (M5=5) so HTF Body-to-Wick Anchor is captured first
      for(int tf = TF_IDX_W1; tf < QT_MTF_COUNT; tf++)
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

            // Check if M5 closed bar touched or entered the MSNR Body-to-Wick Zone [zoneLow, zoneHigh]
            bool touched = (m5Bar.low <= lvl.zoneHigh + proximityMargin * 0.20 &&
                            m5Bar.high >= lvl.zoneLow - proximityMargin * 0.20);
            if(!touched)
               continue;

            // Ensure body close did NOT already break past the distal wick of the POI zone
            if(dir == BIAS_BULL && m5Bar.close < lvl.zoneLow)
               continue;
            if(dir == BIAS_BEAR && m5Bar.close > lvl.zoneHigh)
               continue;

            outAnchor   = lvl;
            foundAnchor = true;
            break;
           }
         if(foundAnchor)
            break;
        }

      // 2. If HTF Anchor found, search for a Nested M15/M5 Refined POI inside the HTF Body-to-Wick Zone
      if(foundAnchor)
        {
         if(m_cfg.useM15M5Refinement && outAnchor.tfIdx <= TF_IDX_H1)
            outHasRefined = FindNestedRefinedPOI(outAnchor, msnr, m5Bar.close, outRefined);

         outOverlaps = msnr.CountMultiTFOverlaps(outAnchor);
         if(outHasRefined && outOverlaps < 2)
            outOverlaps = MathMin(2, outOverlaps + 1);
        }

      return foundAnchor;
     }

   //--- Detect Liquidity Sweep inside or near the active POI
   bool              CheckSweepForSetup(const SSetupTracker &tr,
                                        CMTFDataManager &mtf,
                                        CSwingEngine &swings,
                                        CICTEngine &ict,
                                        const STradeProfileSpec &prof,
                                        SSweepEvent &outSweep) const
     {
      outSweep.Reset();

      SLiquidityPool pools[];
      int poolCnt = 0;
      ict.GetPoolsArray(pools, poolCnt);

      // 1. Check on primary Trigger TF (e.g. M15 for Intraday/Scalp, H1 for Swing)
      MqlRates trigBar;
      if(mtf.GetClosedBar(prof.triggerTfIdx, 1, trigBar))
        {
         if(CICTEngine::DetectSweepOnBar(trigBar, 1, prof.triggerTfIdx, pools, poolCnt, tr.direction, outSweep))
            return true;
        }

      // 2. Check on secondary Trigger TF (e.g. M5 inside POI) for precision sweep
      if(prof.secondaryTriggerTfIdx != prof.triggerTfIdx)
        {
         MqlRates secBar;
         if(mtf.GetClosedBar(prof.secondaryTriggerTfIdx, 1, secBar))
           {
            if(CICTEngine::DetectSweepOnBar(secBar, 1, prof.secondaryTriggerTfIdx, pools, poolCnt, tr.direction, outSweep))
               return true;

            // Also check if secBar swept the anchor/refined POI level itself and closed back inside!
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
               outSweep.isMajorPool      = (tr.anchorPOI.tfIdx <= TF_IDX_H1);
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
               outSweep.isMajorPool      = (tr.anchorPOI.tfIdx <= TF_IDX_H1);
               return true;
              }
           }
        }

      return false;
     }

   //--- Update a single directional setup state machine (BUY or SELL)
   void              StepTracker(SSetupTracker &tr,
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

         // Common invalidation checks for active pre-trade setups (S1..S4)
         if(isNewsBlocked)
           {
            tr.statusNote       = "REJECT_NEWS: " + newsReason;
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }
         if(!qtState.isTimeAllowed)
           {
            tr.statusNote       = "CANCEL_TIME_WINDOW_ENDED";
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }
         if(!biasGateOk)
           {
            tr.statusNote       = "CANCEL_BIAS_GATE_FLIPPED";
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }
         if(tr.ageBarsM5 > m_cfg.maxSetupBarsM5)
           {
            tr.statusNote       = "CANCEL_SETUP_EXPIRED_MAX_BARS";
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }
         // Check if anchor POI was broken by body close
         if((tr.direction == BIAS_BULL && m5Bar.close < tr.anchorPOI.zoneLow) ||
            (tr.direction == BIAS_BEAR && m5Bar.close > tr.anchorPOI.zoneHigh))
           {
            tr.statusNote       = "CANCEL_POI_BODY_BROKEN";
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }
        }

      //----------------------------------------------------------------
      // STATE S0: IDLE -> Wait for allowed time + bias + Fresh POI touch
      //----------------------------------------------------------------
      if(tr.state == SETUP_S0_IDLE)
        {
         if(!biasGateOk || !qtState.isTimeAllowed || isNewsBlocked)
            return;

         SMSNRLevel anchor, refined;
         bool hasRef = false;
         int overlaps = 0;

         if(FindTouchedPOI(tr.direction, m5Bar, msnr, prof, anchor, hasRef, refined, overlaps))
           {
            m_seqCounter++;
            tr.Reset(tr.direction);
            tr.setupId         = StringFormat("QT_%s_%I64d_%d",
                                              (tr.direction == BIAS_BULL ? "BUY" : "SELL"),
                                              (long)m5Bar.time,
                                              m_seqCounter);
            tr.state           = SETUP_S1_POI_TOUCH;
            tr.createdTime     = qtState.serverTime;
            tr.lastM5BarTime   = m5Bar.time;
            tr.ageBarsM5       = 0;
            tr.weekQ           = qtState.weekQ;
            tr.dayQ            = qtState.dayQ;
            tr.session         = qtState.session;
            tr.q90             = qtState.q90;
            tr.anchorPOI       = anchor;
            tr.hasRefinedPOI   = hasRef;
            tr.refinedPOI      = refined;
            tr.poiOverlapCount = overlaps;
            tr.statusNote      = "S1_POI_TOUCH";
           }
        }

      // Refresh nested M15/M5 Refined POI inside HTF Anchor Zone if one just formed
      if(tr.state >= SETUP_S1_POI_TOUCH && tr.state <= SETUP_S3_MSS &&
         m_cfg.useM15M5Refinement && !tr.hasRefinedPOI && tr.anchorPOI.tfIdx <= TF_IDX_H1)
        {
         SMSNRLevel candRef;
         if(FindNestedRefinedPOI(tr.anchorPOI, msnr, m5Bar.close, candRef))
           {
            tr.hasRefinedPOI   = true;
            tr.refinedPOI      = candRef;
            tr.poiOverlapCount = MathMin(2, MathMax(1, tr.poiOverlapCount + 1));
           }
        }

      //----------------------------------------------------------------
      // STATE S1: POI_TOUCH -> Wait for Liquidity Sweep inside/near POI
      //----------------------------------------------------------------
      if(tr.state == SETUP_S1_POI_TOUCH)
        {
         SSweepEvent swEv;
         if(CheckSweepForSetup(tr, mtf, swings, ict, prof, swEv))
           {
            tr.sweep      = swEv;
            tr.state      = SETUP_S2_SWEEP;
            tr.statusNote = "S2_SWEEP_CONFIRMED";
           }
        }

      //----------------------------------------------------------------
      // STATE S2: SWEEP -> Wait for MSS (Body Close Displacement)
      //----------------------------------------------------------------
      if(tr.state == SETUP_S2_SWEEP)
        {
         if(!ict.GetConfig().useMSS)
           {
            // MSS disabled by user parameter -> advance directly to S3_MSS
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
            // Check MSS on sweep's trigger TF or entry TF (M5)
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

      //----------------------------------------------------------------
      // STATE S3: MSS -> Wait for FVG / M15-M5 POI & Validate Score/RR
      //----------------------------------------------------------------
      if(tr.state == SETUP_S3_MSS)
        {
         SFVGZone fvgFound;
         bool gotFvg = ict.FindRecentTradableFVG(prof.entryTfIdx, tr.direction, tr.sweep.sweepBarTime, fvgFound);
         if(!gotFvg && prof.triggerTfIdx != prof.entryTfIdx)
            gotFvg = ict.FindRecentTradableFVG(prof.triggerTfIdx, tr.direction, tr.sweep.sweepBarTime, fvgFound);

         // Wait for FVG unless entryType is Market on MSS or we have a fresh M15/M5 refined MSNR POI
         if(!gotFvg && m_cfg.entryType != ENTRY_MARKET_MSS && !tr.hasRefinedPOI)
            return;

         tr.hasFvg = gotFvg;
         tr.fvg    = fvgFound;

         // 1. Determine Entry Price
         if(m_cfg.entryType == ENTRY_MARKET_MSS)
           {
            tr.isMarketOrder = true;
            tr.entryPrice    = m5Bar.close;
           }
         else if(gotFvg)
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = (m_cfg.entryType == ENTRY_FVG_CE ? fvgFound.ce : fvgFound.proximal);

            // If a refined M15/M5 MSNR POI lies inside the FVG, refine entry to produce tighter SL
            if(tr.hasRefinedPOI &&
               tr.refinedPOI.price >= fvgFound.lowEdge &&
               tr.refinedPOI.price <= fvgFound.highEdge)
              {
               tr.entryPrice = tr.refinedPOI.price;
              }
           }
         else // Fallback to refined M15/M5 MSNR POI limit
           {
            tr.isMarketOrder = false;
            tr.entryPrice    = tr.refinedPOI.price;
           }

         // 2. Determine Stop Loss (beyond sweep extreme & refined LTF POI wick + buffer: 0.2 * ATR(M5) + spread)
         double atrM5    = mtf.GetATR(TF_IDX_M5);
         double atrH1    = mtf.GetATR(TF_IDX_H1);
         double slBuffer = m_cfg.slBufferAtrMultM5 * atrM5 + currentSpreadPrice;

         if(tr.direction == BIAS_BULL)
           {
            double baseLow = MathMin(tr.sweep.extremeWickPrice, m5Bar.low);
            if(tr.hasRefinedPOI && tr.refinedPOI.wickExtreme > 0.0 &&
               MathAbs(tr.entryPrice - tr.refinedPOI.wickExtreme) <= 0.8 * atrH1)
               baseLow = MathMin(baseLow, tr.refinedPOI.wickExtreme);
            tr.slPrice = baseLow - slBuffer;
           }
         else
           {
            double baseHigh = MathMax(tr.sweep.extremeWickPrice, m5Bar.high);
            if(tr.hasRefinedPOI && tr.refinedPOI.wickExtreme > 0.0 &&
               MathAbs(tr.refinedPOI.wickExtreme - tr.entryPrice) <= 0.8 * atrH1)
               baseHigh = MathMax(baseHigh, tr.refinedPOI.wickExtreme);
            tr.slPrice = baseHigh + slBuffer;
           }

         double slDist = MathAbs(tr.entryPrice - tr.slPrice);
         if(slDist <= 1e-5)
           {
            tr.statusNote       = "REJECT_INVALID_SL_DISTANCE";
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }

         // Check max SL width against H1 ATR multiple
         if(atrH1 > 0.0 && slDist > m_cfg.maxSlAtrMultH1 * atrH1)
           {
            tr.statusNote       = StringFormat("REJECT_SL_TOO_WIDE (%.2f > %.2f*ATR_H1)", slDist, m_cfg.maxSlAtrMultH1);
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }

         // 3. Determine Take Profit (DOL) & Internal TP1 Roadblock
         SDOLTarget dolTarget = (tr.direction == BIAS_BULL ? biasState.bullDOL : biasState.bearDOL);
         SDOLTarget tp1Target = (tr.direction == BIAS_BULL ? biasState.bullInternalTP1 : biasState.bearInternalTP1);
         double minRR         = (m_cfg.customMinRR > 0.0 ? m_cfg.customMinRR : prof.minRR);

         if(dolTarget.valid)
           {
            tr.tpPrice  = dolTarget.price;
            tr.dolLabel = dolTarget.label;
           }
         else
           {
            // Fallback: project minimum RR target if no external pool was in cache range
            tr.tpPrice  = (tr.direction == BIAS_BULL ? tr.entryPrice + slDist * minRR
                                                     : tr.entryPrice - slDist * minRR);
            tr.dolLabel = "RR_PROJECTED";
           }

         tr.tp1Price = (tp1Target.valid ? tp1Target.price :
                        (tr.direction == BIAS_BULL ? tr.entryPrice + slDist : tr.entryPrice - slDist));

         double reward = (tr.direction == BIAS_BULL ? (tr.tpPrice - tr.entryPrice)
                                                    : (tr.entryPrice - tr.tpPrice));
         tr.rrRatio = (reward > 0.0 ? reward / slDist : 0.0);

         if(tr.rrRatio + 1e-5 < minRR)
           {
            tr.statusNote       = StringFormat("REJECT_RR_BELOW_MIN (%.2f < %.2f)", tr.rrRatio, minRR);
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }

         // 4. Calculate Confluence Score (PRD 4.7 + 4.10)
         CalcConfluenceScore(tr, qtState, biasState, prof, tr.score);
         if(tr.score.totalScore < m_cfg.minConfluenceScore)
           {
            tr.statusNote       = StringFormat("REJECT_LOW_SCORE (%d < %d)",
                                               tr.score.totalScore, m_cfg.minConfluenceScore);
            m_lastEvaluatedSetup = tr;
            m_hasNewLogEvent    = true;
            tr.Reset(tr.direction);
            return;
           }

         // All mandatory gates passed -> S4_ARMED!
         tr.state            = SETUP_S4_ARMED;
         tr.armedTime        = qtState.serverTime;
         tr.statusNote       = "ARMED_VALID";
         m_lastEvaluatedSetup = tr;
         m_hasNewLogEvent    = true;
        }

      //----------------------------------------------------------------
      // STATE S4: ARMED -> Invalidate if price hits SL or TP before fill
      //----------------------------------------------------------------
      if(tr.state == SETUP_S4_ARMED)
        {
         if(tr.direction == BIAS_BULL)
           {
            if(m5Bar.low <= tr.slPrice)
              {
               tr.statusNote       = "CANCEL_HIT_SL_BEFORE_ENTRY";
               m_lastEvaluatedSetup = tr;
               m_hasNewLogEvent    = true;
               tr.Reset(tr.direction);
               return;
              }
            if(m5Bar.high >= tr.tpPrice)
              {
               tr.statusNote       = "CANCEL_HIT_TP_BEFORE_ENTRY";
               m_lastEvaluatedSetup = tr;
               m_hasNewLogEvent    = true;
               tr.Reset(tr.direction);
               return;
              }
           }
         else
           {
            if(m5Bar.high >= tr.slPrice)
              {
               tr.statusNote       = "CANCEL_HIT_SL_BEFORE_ENTRY";
               m_lastEvaluatedSetup = tr;
               m_hasNewLogEvent    = true;
               tr.Reset(tr.direction);
               return;
              }
            if(m5Bar.low <= tr.tpPrice)
              {
               tr.statusNote       = "CANCEL_HIT_TP_BEFORE_ENTRY";
               m_lastEvaluatedSetup = tr;
               m_hasNewLogEvent    = true;
               tr.Reset(tr.direction);
               return;
              }
           }
        }
     }

public:
                     CSetupEngine()
     {
      m_cfg.SetDefaults();
      m_buySetup.Reset(BIAS_BULL);
      m_sellSetup.Reset(BIAS_BEAR);
      m_lastEvaluatedSetup.Reset(BIAS_BULL);
      m_hasNewLogEvent = false;
      m_seqCounter     = 0;
     }

   void              Init(const SSetupConfig &cfg)
     {
      m_cfg = cfg;
      m_buySetup.Reset(BIAS_BULL);
      m_sellSetup.Reset(BIAS_BEAR);
      m_lastEvaluatedSetup.Reset(BIAS_BULL);
      m_hasNewLogEvent = false;
     }

   SSetupConfig      GetConfig() const { return m_cfg; }
   SSetupTracker     GetBuySetup()  const { return m_buySetup; }
   SSetupTracker     GetSellSetup() const { return m_sellSetup; }

   bool              PopLastLogEvent(SSetupTracker &outSetup)
     {
      if(!m_hasNewLogEvent)
         return false;
      outSetup         = m_lastEvaluatedSetup;
      m_hasNewLogEvent = false;
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
                            outScore.ptsFvg +
                            outScore.ptsBiasScoreTF;
     }

   //+------------------------------------------------------------------+
   //| Update Both BUY and SELL Setup State Machines                    |
   //+------------------------------------------------------------------+
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
      StepTracker(m_buySetup,  mtf, swings, msnr, ict, qtState, biasState, prof, currentSpreadPrice, isNewsBlocked, newsReason);
      StepTracker(m_sellSetup, mtf, swings, msnr, ict, qtState, biasState, prof, currentSpreadPrice, isNewsBlocked, newsReason);
     }

   //--- Transition helpers called by Execution Engine (M8)
   void              NotifyOrderPlaced(const ENUM_BIAS_DIR dir, const ulong ticket)
     {
      if(dir == BIAS_BULL)
         m_buySetup.orderTicket = ticket;
      else if(dir == BIAS_BEAR)
         m_sellSetup.orderTicket = ticket;
     }

   void              NotifyTradeFilled(const ENUM_BIAS_DIR dir, const ulong ticket, CMSNREngine &msnr)
     {
      if(dir == BIAS_BULL)
        {
         m_buySetup.state       = SETUP_S5_IN_TRADE;
         m_buySetup.orderTicket = ticket;
         msnr.MarkLevelUsed(m_buySetup.anchorPOI.id);
         if(m_buySetup.hasRefinedPOI)
            msnr.MarkLevelUsed(m_buySetup.refinedPOI.id);
        }
      else if(dir == BIAS_BEAR)
        {
         m_sellSetup.state       = SETUP_S5_IN_TRADE;
         m_sellSetup.orderTicket = ticket;
         msnr.MarkLevelUsed(m_sellSetup.anchorPOI.id);
         if(m_sellSetup.hasRefinedPOI)
            msnr.MarkLevelUsed(m_sellSetup.refinedPOI.id);
        }
     }

   void              NotifySetupCompleted(const ENUM_BIAS_DIR dir, const string reason)
     {
      if(dir == BIAS_BULL)
        {
         m_buySetup.statusNote = reason;
         m_buySetup.Reset(BIAS_BULL);
        }
      else if(dir == BIAS_BEAR)
        {
         m_sellSetup.statusNote = reason;
         m_sellSetup.Reset(BIAS_BEAR);
        }
     }
  };

#endif // QT_SETUP_MQH
//+------------------------------------------------------------------+
