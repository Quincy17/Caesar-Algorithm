//+------------------------------------------------------------------+
//| ICT_Engine.mqh                                                   |
//| M5 - ICT Liquidity Engine: EQH/EQL, Pools, Sweep, MSS & FVG      |
//| Place in: MQL5/Include/QT/ICT_Engine.mqh                         |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Build Liquidity Pools: PDH/PDL (Daye 18:00 NY or Broker D1),  |
//|    PWH/PWL, QT Session High/Low (Asia, London, NY AM),           |
//|    EQH/EQL clusters, and HTF Swing Highs/Lows                    |
//|  - Detect closed-bar Liquidity Sweeps (wick pierces pool,        |
//|    body closes back inside)                                      |
//|  - Detect Market Structure Shift (MSS: body close breaks         |
//|    opposing swing after sweep)                                   |
//|  - Detect 3-candle Fair Value Gaps (FVG) on M5, M15, H1, H4      |
//|    with Proximal, CE (50%), Distal, and Open/Partial/Filled state|
//+------------------------------------------------------------------+
#ifndef QT_ICT_ENGINE_MQH
#define QT_ICT_ENGINE_MQH

#include "QT_Time.mqh"
#include "Swings.mqh"

enum ENUM_LIQ_POOL_TYPE
  {
   LIQ_POOL_NONE         = 0,
   LIQ_POOL_EQH          = 1, // Equal Highs cluster (Buy-side liquidity)
   LIQ_POOL_EQL          = 2, // Equal Lows cluster (Sell-side liquidity)
   LIQ_POOL_PDH          = 3, // Previous Day High
   LIQ_POOL_PDL          = 4, // Previous Day Low
   LIQ_POOL_PWH          = 5, // Previous Week High
   LIQ_POOL_PWL          = 6, // Previous Week Low
   LIQ_POOL_SESSION_HIGH = 7, // QT Session High (Asia / London / NY AM)
   LIQ_POOL_SESSION_LOW  = 8, // QT Session Low  (Asia / London / NY AM)
   LIQ_POOL_SWING_HIGH   = 9, // HTF/MTF Wick Swing High
   LIQ_POOL_SWING_LOW    = 10 // HTF/MTF Wick Swing Low
  };

enum ENUM_PDH_SOURCE
  {
   PDH_SOURCE_DAYE_18NY = 0, // Default: Daye trading day boundary (18:00 NY -> 18:00 NY)
   PDH_SOURCE_BROKER_D1 = 1  // Option : Broker D1 bar[1] High / Low
  };

struct SICTConfig
  {
   double          eqToleranceAtrMult; // Max price diff for EQH/EQL = mult * ATR(14), default 0.10
   int             eqLookbackSwings;   // Number of recent wick swings to scan for EQH/EQL, default 20
   double          minFvgAtrMult;      // Min FVG gap size = mult * ATR(14), default 0.15
   int             maxFvgAgeBars;      // Max bars to track FVG per TF, default 120
   bool            useMSS;             // Require MSS after Sweep (default true)
   ENUM_PDH_SOURCE pdhSource;          // Daye 18:00 NY (default) or Broker D1

   void SetDefaults()
     {
      eqToleranceAtrMult = 0.10;
      eqLookbackSwings   = 20;
      minFvgAtrMult      = 0.15;
      maxFvgAgeBars      = 120;
      useMSS             = true;
      pdhSource          = PDH_SOURCE_DAYE_18NY;
     }
  };

struct SLiquidityPool
  {
   string             id;
   ENUM_LIQ_POOL_TYPE type;
   bool               isBuySide;      // True = Buy-side liquidity above price (Highs); False = Sell-side (Lows)
   int                tfIdx;          // Originating timeframe index
   double             price;          // Liquidity level price
   datetime           formedTime;     // Timestamp when pool formed
   bool               isSwept;        // True if swept by wick (close inside)
   bool               isBroken;       // True if broken by body close (run through)
   datetime           sweptTime;      // Timestamp of sweep bar (0 if unswept)
   int                touchCount;     // Number of swings in cluster (>=2 for EQH/EQL)

   void Reset()
     {
      id         = "";
      type       = LIQ_POOL_NONE;
      isBuySide  = true;
      tfIdx      = TF_IDX_H1;
      price      = 0.0;
      formedTime = 0;
      isSwept    = false;
      isBroken   = false;
      sweptTime  = 0;
      touchCount = 1;
     }

   //--- High-value liquidity pool for +2 Confluence Score (EQH/EQL, PDH/PDL, Session Extreme, PWH/PWL)
   bool IsMajorPool() const
     {
      return (type == LIQ_POOL_EQH ||
              type == LIQ_POOL_EQL ||
              type == LIQ_POOL_PDH ||
              type == LIQ_POOL_PDL ||
              type == LIQ_POOL_PWH ||
              type == LIQ_POOL_PWL ||
              type == LIQ_POOL_SESSION_HIGH ||
              type == LIQ_POOL_SESSION_LOW);
     }
  };

struct SSweepEvent
  {
   bool               valid;
   ENUM_BIAS_DIR      signalDir;      // BIAS_BULL (after Sell-side low sweep) or BIAS_BEAR (after Buy-side high sweep)
   ENUM_LIQ_POOL_TYPE poolType;
   string             poolId;
   int                triggerTfIdx;   // TF on which sweep candle closed (e.g. M15, M5, H1)
   datetime           sweepBarTime;   // Open time of closed sweep bar
   int                sweepClosedShift;// Closed shift of sweep bar (1 = latest closed bar)
   double             sweptLevelPrice;// Price of the liquidity level that was swept
   double             extremeWickPrice;// Lowest low (for Bull) or Highest high (for Bear) of sweep bar -> used for SL!
   bool               isMajorPool;    // True if EQH/EQL, PDH/PDL, PWH/PWL, or Session Extreme

   void Reset()
     {
      valid            = false;
      signalDir        = BIAS_NEUTRAL;
      poolType         = LIQ_POOL_NONE;
      poolId           = "";
      triggerTfIdx     = TF_IDX_M15;
      sweepBarTime     = 0;
      sweepClosedShift = 0;
      sweptLevelPrice  = 0.0;
      extremeWickPrice = 0.0;
      isMajorPool      = false;
     }
  };

struct SMSSResult
  {
   bool          confirmed;        // True if body close broke opposing swing after sweep
   ENUM_BIAS_DIR direction;        // BIAS_BULL or BIAS_BEAR
   int           tfIdx;            // Timeframe of MSS
   datetime      mssBarTime;       // Time of displacement candle that closed beyond opposing swing
   int           mssClosedShift;   // Closed shift of MSS candle
   double        brokenSwingPrice; // Price of the opposing swing that was broken
   datetime      brokenSwingTime;  // Time of the opposing swing

   void Reset()
     {
      confirmed        = false;
      direction        = BIAS_NEUTRAL;
      tfIdx            = TF_IDX_M15;
      mssBarTime       = 0;
      mssClosedShift   = 0;
      brokenSwingPrice = 0.0;
      brokenSwingTime  = 0;
     }
  };

struct SFVGZone
  {
   string          id;
   ENUM_BIAS_DIR   direction;        // BIAS_BULL (gap up) or BIAS_BEAR (gap down)
   ENUM_FVG_STATUS status;           // FVG_STATUS_OPEN, PARTIAL, FILLED
   int             tfIdx;            // TF_IDX_M5, TF_IDX_M15, TF_IDX_H1, TF_IDX_H4
   datetime        bar3Time;         // Open time of 3rd candle completing the FVG
   datetime        bar2Time;         // Open time of middle displacement candle
   int             bar3ClosedShift;  // Closed shift of 3rd candle (1 = latest closed bar)
   double          proximal;         // Edge closest to current price on pullback (entry edge)
   double          distal;           // Far edge of the gap
   double          ce;               // 50% Consequent Encroachment = (proximal + distal) * 0.5
   double          gapSize;          // |proximal - distal|
   double          highEdge;         // max(proximal, distal)
   double          lowEdge;          // min(proximal, distal)

   void Reset()
     {
      id              = "";
      direction       = BIAS_NEUTRAL;
      status          = FVG_STATUS_OPEN;
      tfIdx           = TF_IDX_M5;
      bar3Time        = 0;
      bar2Time        = 0;
      bar3ClosedShift = 0;
      proximal        = 0.0;
      distal          = 0.0;
      ce              = 0.0;
      gapSize         = 0.0;
      highEdge        = 0.0;
      lowEdge         = 0.0;
     }

   bool IsTradable() const
     {
      return (status == FVG_STATUS_OPEN || status == FVG_STATUS_PARTIAL);
     }
  };

string QTLiqPoolTypeToString(const ENUM_LIQ_POOL_TYPE t)
  {
   switch(t)
     {
      case LIQ_POOL_EQH:          return "EQH";
      case LIQ_POOL_EQL:          return "EQL";
      case LIQ_POOL_PDH:          return "PDH";
      case LIQ_POOL_PDL:          return "PDL";
      case LIQ_POOL_PWH:          return "PWH";
      case LIQ_POOL_PWL:          return "PWL";
      case LIQ_POOL_SESSION_HIGH: return "SES_H";
      case LIQ_POOL_SESSION_LOW:  return "SES_L";
      case LIQ_POOL_SWING_HIGH:   return "SWING_H";
      case LIQ_POOL_SWING_LOW:    return "SWING_L";
      default:                    return "NONE";
     }
  }

struct STFFVGStore
  {
   SFVGZone fvgs[];
   int      count;

   void Reset()
     {
      ArrayResize(fvgs, 0);
      count = 0;
     }
  };

//+------------------------------------------------------------------+
//| CICTEngine Class                                                 |
//+------------------------------------------------------------------+
class CICTEngine
  {
private:
   SICTConfig        m_cfg;
   SLiquidityPool    m_pools[];
   int               m_poolCount;
   STFFVGStore       m_fvgStore[QT_MTF_COUNT];

   static void       AddPool(SLiquidityPool &arr[], int &cnt, const SLiquidityPool &p)
     {
      ArrayResize(arr, cnt + 1, 64);
      arr[cnt] = p;
      cnt++;
     }

   //--- Update sweep/break status of a liquidity pool across closed M15 bars after pool.formedTime
   static void       EvaluatePoolSweepStatus(SLiquidityPool &pool,
                                             const MqlRates &rates[],
                                             const int count)
     {
      for(int i = count - 1; i >= 0; i--)
        {
         if(rates[i].time <= pool.formedTime)
            continue;

         if(pool.isBuySide)
           {
            if(rates[i].close > pool.price)
              {
               pool.isBroken = true;
               return;
              }
            if(rates[i].high > pool.price && rates[i].close < pool.price && !pool.isSwept)
              {
               pool.isSwept   = true;
               pool.sweptTime = rates[i].time;
              }
           }
         else
           {
            if(rates[i].close < pool.price)
              {
               pool.isBroken = true;
               return;
              }
            if(rates[i].low < pool.price && rates[i].close > pool.price && !pool.isSwept)
              {
               pool.isSwept   = true;
               pool.sweptTime = rates[i].time;
              }
           }
        }
     }

public:
                     CICTEngine()
     {
      m_cfg.SetDefaults();
      ArrayResize(m_pools, 0);
      m_poolCount = 0;
      for(int i = 0; i < QT_MTF_COUNT; i++)
         m_fvgStore[i].Reset();
     }

   void              Init(const SICTConfig &cfg)
     {
      m_cfg       = cfg;
      ArrayResize(m_pools, 0);
      m_poolCount = 0;
      for(int i = 0; i < QT_MTF_COUNT; i++)
         m_fvgStore[i].Reset();
     }

   SICTConfig        GetConfig() const { return m_cfg; }

   //+------------------------------------------------------------------+
   //| 1. Detect EQH / EQL Clusters from Wick Swings on a Timeframe     |
   //+------------------------------------------------------------------+
   static void       DetectEqualHighsLows(const SSwingPoint &wickSwings[],
                                          const int swingCount,
                                          const int tfIdx,
                                          const double atrValue,
                                          const double eqToleranceAtrMult,
                                          const int maxLookbackSwings,
                                          SLiquidityPool &outPools[],
                                          int &outCount)
     {
      double tol = MathMax(1e-5, eqToleranceAtrMult * atrValue);
      int limit  = MathMin(swingCount, MathMax(2, maxLookbackSwings));

      bool used[];
      ArrayResize(used, limit);
      ArrayInitialize(used, false);

      for(int i = 0; i < limit; i++)
        {
         if(used[i])
            continue;

         SSwingPoint base = wickSwings[i];
         int matches      = 1;
         double extremeP  = base.price;
         datetime newestT = base.confirmTime;

         for(int j = i + 1; j < limit; j++)
           {
            if(used[j] || wickSwings[j].type != base.type)
               continue;

            if(MathAbs(wickSwings[j].price - base.price) <= tol)
              {
               // Check that no intermediate swing between i and j already broke the level
               used[j] = true;
               matches++;
               if(base.type == SWING_HIGH && wickSwings[j].price > extremeP)
                  extremeP = wickSwings[j].price;
               if(base.type == SWING_LOW  && wickSwings[j].price < extremeP)
                  extremeP = wickSwings[j].price;
               if(wickSwings[j].confirmTime > newestT)
                  newestT = wickSwings[j].confirmTime;
              }
           }

         if(matches >= 2)
           {
            used[i] = true;
            SLiquidityPool p;
            p.Reset();
            p.type       = (base.type == SWING_HIGH ? LIQ_POOL_EQH : LIQ_POOL_EQL);
            p.isBuySide  = (base.type == SWING_HIGH);
            p.tfIdx      = tfIdx;
            p.price      = extremeP;
            p.formedTime = newestT;
            p.touchCount = matches;
            p.id         = StringFormat("%s_%s_%I64d",
                                        QTTfIndexToString(tfIdx),
                                        QTLiqPoolTypeToString(p.type),
                                        (long)newestT);
            AddPool(outPools, outCount, p);
           }
        }
     }

   //+------------------------------------------------------------------+
   //| 2. Detect 3-Candle Fair Value Gaps (FVG) on Closed Bars          |
   //+------------------------------------------------------------------+
   static void       ScanRatesForFVG(const MqlRates &rates[],
                                     const int ratesCount,
                                     const int tfIdx,
                                     const double atrValue,
                                     const double minFvgAtrMult,
                                     const int maxAgeBars,
                                     SFVGZone &outFvgs[],
                                     int &outCount,
                                     const int maxCap = 50)
     {
      ArrayResize(outFvgs, 0);
      outCount = 0;
      if(ratesCount < 3)
         return;

      double minGap = MathMax(0.0, minFvgAtrMult * atrValue);
      int maxC3     = MathMin(ratesCount - 3, MathMax(1, maxAgeBars));

      // Scan from newest closed 3-candle pattern (c3 = 0 => shift 1) to older
      for(int c3 = 0; c3 <= maxC3 && outCount < maxCap; c3++)
        {
         int c2 = c3 + 1; // Middle displacement candle
         int c1 = c3 + 2; // First candle

         double c1High = rates[c1].high;
         double c1Low  = rates[c1].low;
         double c3High = rates[c3].high;
         double c3Low  = rates[c3].low;

         // A) Bullish FVG: low of candle 3 > high of candle 1
         if(c3Low > c1High)
           {
            double gap = c3Low - c1High;
            if(gap >= minGap)
              {
               SFVGZone fvg;
               fvg.Reset();
               fvg.direction       = BIAS_BULL;
               fvg.status          = FVG_STATUS_OPEN;
               fvg.tfIdx           = tfIdx;
               fvg.bar3Time        = rates[c3].time;
               fvg.bar2Time        = rates[c2].time;
               fvg.bar3ClosedShift = c3 + 1;
               fvg.proximal        = c3Low;  // Upper boundary (touched first on pullback)
               fvg.distal          = c1High; // Lower boundary
               fvg.ce              = (fvg.proximal + fvg.distal) * 0.5;
               fvg.gapSize         = gap;
               fvg.highEdge        = c3Low;
               fvg.lowEdge         = c1High;
               fvg.id              = StringFormat("FVG_BULL_%s_%I64d",
                                                  QTTfIndexToString(tfIdx),
                                                  (long)rates[c3].time);

               // Check mitigation on bars after candle 3 (j = c3 - 1 down to 0)
               for(int j = c3 - 1; j >= 0; j--)
                 {
                  if(rates[j].low <= fvg.distal || rates[j].close < fvg.distal)
                    {
                     fvg.status = FVG_STATUS_FILLED;
                     break;
                    }
                  if(rates[j].low <= fvg.proximal)
                     fvg.status = FVG_STATUS_PARTIAL;
                 }

               ArrayResize(outFvgs, outCount + 1, 64);
               outFvgs[outCount] = fvg;
               outCount++;
              }
           }

         // B) Bearish FVG: high of candle 3 < low of candle 1
         if(c3High < c1Low && outCount < maxCap)
           {
            double gap = c1Low - c3High;
            if(gap >= minGap)
              {
               SFVGZone fvg;
               fvg.Reset();
               fvg.direction       = BIAS_BEAR;
               fvg.status          = FVG_STATUS_OPEN;
               fvg.tfIdx           = tfIdx;
               fvg.bar3Time        = rates[c3].time;
               fvg.bar2Time        = rates[c2].time;
               fvg.bar3ClosedShift = c3 + 1;
               fvg.proximal        = c3High; // Lower boundary (touched first on pullback)
               fvg.distal          = c1Low;  // Upper boundary
               fvg.ce              = (fvg.proximal + fvg.distal) * 0.5;
               fvg.gapSize         = gap;
               fvg.highEdge        = c1Low;
               fvg.lowEdge         = c3High;
               fvg.id              = StringFormat("FVG_BEAR_%s_%I64d",
                                                  QTTfIndexToString(tfIdx),
                                                  (long)rates[c3].time);

               for(int j = c3 - 1; j >= 0; j--)
                 {
                  if(rates[j].high >= fvg.distal || rates[j].close > fvg.distal)
                    {
                     fvg.status = FVG_STATUS_FILLED;
                     break;
                    }
                  if(rates[j].high >= fvg.proximal)
                     fvg.status = FVG_STATUS_PARTIAL;
                 }

               ArrayResize(outFvgs, outCount + 1, 64);
               outFvgs[outCount] = fvg;
               outCount++;
              }
           }
        }
     }

   //+------------------------------------------------------------------+
   //| 3. Evaluate Closed-Bar Liquidity Sweep against Liquidity Pools   |
   //+------------------------------------------------------------------+
   static bool       DetectSweepOnBar(const MqlRates &bar,
                                      const int barClosedShift,
                                      const int triggerTfIdx,
                                      const SLiquidityPool &pools[],
                                      const int poolCount,
                                      const ENUM_BIAS_DIR filterDir,
                                      SSweepEvent &outSweep)
     {
      outSweep.Reset();

      for(int i = 0; i < poolCount; i++)
        {
         SLiquidityPool p = pools[i];
         if(p.formedTime >= bar.time)
            continue;

         // Sell-Side Liquidity Sweep (Bullish Reversal Signal):
         // Bar low pierces below Sell-Side pool, and bar close finishes back above pool.price
         if(!p.isBuySide && (filterDir == BIAS_BULL || filterDir == BIAS_NEUTRAL))
           {
            if(bar.low < p.price && bar.close > p.price)
              {
               // Prefer Major Pools (EQH/EQL, PDH/PDL, Session Extreme) or deeper sweep
               if(!outSweep.valid || (p.IsMajorPool() && !outSweep.isMajorPool))
                 {
                  outSweep.valid            = true;
                  outSweep.signalDir        = BIAS_BULL;
                  outSweep.poolType         = p.type;
                  outSweep.poolId           = p.id;
                  outSweep.triggerTfIdx     = triggerTfIdx;
                  outSweep.sweepBarTime     = bar.time;
                  outSweep.sweepClosedShift = barClosedShift;
                  outSweep.sweptLevelPrice  = p.price;
                  outSweep.extremeWickPrice = bar.low;
                  outSweep.isMajorPool      = p.IsMajorPool();
                 }
              }
           }

         // Buy-Side Liquidity Sweep (Bearish Reversal Signal):
         // Bar high pierces above Buy-Side pool, and bar close finishes back below pool.price
         if(p.isBuySide && (filterDir == BIAS_BEAR || filterDir == BIAS_NEUTRAL))
           {
            if(bar.high > p.price && bar.close < p.price)
              {
               if(!outSweep.valid || (p.IsMajorPool() && !outSweep.isMajorPool))
                 {
                  outSweep.valid            = true;
                  outSweep.signalDir        = BIAS_BEAR;
                  outSweep.poolType         = p.type;
                  outSweep.poolId           = p.id;
                  outSweep.triggerTfIdx     = triggerTfIdx;
                  outSweep.sweepBarTime     = bar.time;
                  outSweep.sweepClosedShift = barClosedShift;
                  outSweep.sweptLevelPrice  = p.price;
                  outSweep.extremeWickPrice = bar.high;
                  outSweep.isMajorPool      = p.IsMajorPool();
                 }
              }
           }
        }

      return outSweep.valid;
     }

   //+------------------------------------------------------------------+
   //| 4. Check Market Structure Shift (MSS) after a Liquidity Sweep    |
   //|    Body close breaks the most recent opposing Wick Swing formed  |
   //|    at or before the sweep bar.                                   |
   //+------------------------------------------------------------------+
   static bool       CheckMSSAfterSweep(const MqlRates &rates[],
                                        const int ratesCount,
                                        const SSwingPoint &wickSwings[],
                                        const int swingCount,
                                        const SSweepEvent &sweep,
                                        const int tfIdx,
                                        SMSSResult &outMss)
     {
      outMss.Reset();
      if(!sweep.valid || ratesCount <= 0 || swingCount <= 0)
         return false;

      // 1. Find most recent opposing Wick Swing whose pivot formed at or before sweep.sweepBarTime
      ENUM_SWING_TYPE targetSwingType = (sweep.signalDir == BIAS_BULL ? SWING_HIGH : SWING_LOW);
      SSwingPoint oppSwing;
      oppSwing.Reset();
      bool foundSwing = false;

      for(int i = 0; i < swingCount; i++)
        {
         if(wickSwings[i].type == targetSwingType &&
            wickSwings[i].pivotTime <= sweep.sweepBarTime)
           {
            oppSwing   = wickSwings[i];
            foundSwing = true;
            break;
           }
        }

      if(!foundSwing)
         return false;

      // 2. Scan closed bars from the sweep bar forward to the newest closed bar (index 0)
      int startIdx = MathMin(ratesCount - 1, MathMax(0, sweep.sweepClosedShift - 1));
      for(int idx = startIdx; idx >= 0; idx--)
        {
         if(rates[idx].time < sweep.sweepBarTime)
            continue;

         if(sweep.signalDir == BIAS_BULL && rates[idx].close > oppSwing.price)
           {
            outMss.confirmed        = true;
            outMss.direction        = BIAS_BULL;
            outMss.tfIdx            = tfIdx;
            outMss.mssBarTime       = rates[idx].time;
            outMss.mssClosedShift   = idx + 1;
            outMss.brokenSwingPrice = oppSwing.price;
            outMss.brokenSwingTime  = oppSwing.pivotTime;
            return true;
           }

         if(sweep.signalDir == BIAS_BEAR && rates[idx].close < oppSwing.price)
           {
            outMss.confirmed        = true;
            outMss.direction        = BIAS_BEAR;
            outMss.tfIdx            = tfIdx;
            outMss.mssBarTime       = rates[idx].time;
            outMss.mssClosedShift   = idx + 1;
            outMss.brokenSwingPrice = oppSwing.price;
            outMss.brokenSwingTime  = oppSwing.pivotTime;
            return true;
           }
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| 5. Master Update: Rebuild Liquidity Pools & FVGs across TFs      |
   //+------------------------------------------------------------------+
   void              Update(CMTFDataManager &mtf,
                            CSwingEngine &swings,
                            CQTTimeEngine &timeEngine,
                            const QTState &qtState,
                            const bool forceAll = false)
     {
      // A) Update FVGs on H4, H1, M15, M5 when new bar closes
      int fvgTfs[4] = { TF_IDX_H4, TF_IDX_H1, TF_IDX_M15, TF_IDX_M5 };
      for(int k = 0; k < 4; k++)
        {
         int tfIdx = fvgTfs[k];
         if(!mtf.IsTFReady(tfIdx))
            continue;
         if(!forceAll && !mtf.IsNewBar(tfIdx) && m_fvgStore[tfIdx].count > 0)
            continue;

         MqlRates rates[];
         int cnt = mtf.GetClosedRatesArray(tfIdx, rates);
         ScanRatesForFVG(rates,
                         cnt,
                         tfIdx,
                         mtf.GetATR(tfIdx),
                         m_cfg.minFvgAtrMult,
                         m_cfg.maxFvgAgeBars,
                         m_fvgStore[tfIdx].fvgs,
                         m_fvgStore[tfIdx].count,
                         60);
        }

      // B) Rebuild Master Liquidity Pool List when M15 (or higher) closes a new bar
      if(!forceAll && !mtf.IsNewBar(TF_IDX_M15) && !mtf.IsNewBar(TF_IDX_M5) && m_poolCount > 0)
         return;

      ArrayResize(m_pools, 0);
      m_poolCount = 0;

      MqlRates m15Rates[];
      int m15Count = mtf.GetClosedRatesArray(TF_IDX_M15, m15Rates);

      // B1. Previous Week High / Low (PWH / PWL from W1 closed bar shift 1)
      MqlRates w1Bar;
      if(mtf.GetClosedBar(TF_IDX_W1, 1, w1Bar))
        {
         SLiquidityPool pwh, pwl;
         pwh.Reset();
         pwh.type       = LIQ_POOL_PWH;
         pwh.isBuySide  = true;
         pwh.tfIdx      = TF_IDX_W1;
         pwh.price      = w1Bar.high;
         pwh.formedTime = w1Bar.time;
         pwh.id         = StringFormat("PWH_%I64d", (long)w1Bar.time);
         AddPool(m_pools, m_poolCount, pwh);

         pwl.Reset();
         pwl.type       = LIQ_POOL_PWL;
         pwl.isBuySide  = false;
         pwl.tfIdx      = TF_IDX_W1;
         pwl.price      = w1Bar.low;
         pwl.formedTime = w1Bar.time;
         pwl.id         = StringFormat("PWL_%I64d", (long)w1Bar.time);
         AddPool(m_pools, m_poolCount, pwl);
        }

      // B2. Previous Day High / Low (PDH / PDL: Daye 18:00 NY boundary or Broker D1)
      if(m_cfg.pdhSource == PDH_SOURCE_BROKER_D1)
        {
         MqlRates d1Bar;
         if(mtf.GetClosedBar(TF_IDX_D1, 1, d1Bar))
           {
            SLiquidityPool pdh, pdl;
            pdh.Reset();
            pdh.type       = LIQ_POOL_PDH;
            pdh.isBuySide  = true;
            pdh.tfIdx      = TF_IDX_D1;
            pdh.price      = d1Bar.high;
            pdh.formedTime = d1Bar.time;
            pdh.id         = StringFormat("PDH_D1_%I64d", (long)d1Bar.time);
            AddPool(m_pools, m_poolCount, pdh);

            pdl.Reset();
            pdl.type       = LIQ_POOL_PDL;
            pdl.isBuySide  = false;
            pdl.tfIdx      = TF_IDX_D1;
            pdl.price      = d1Bar.low;
            pdl.formedTime = d1Bar.time;
            pdl.id         = StringFormat("PDL_D1_%I64d", (long)d1Bar.time);
            AddPool(m_pools, m_poolCount, pdl);
           }
        }
      else if(m15Count > 0 && qtState.dayeDayStartNY > 0)
        {
         // Daye Previous Trading Day [prevDayStartSrv, curDayStartSrv)
         datetime curDayStartSrv  = timeEngine.NYToServer(qtState.dayeDayStartNY);
         datetime prevDayStartNY  = (datetime)((long)qtState.dayeDayStartNY - 86400);
         // If today is Monday Daye day, step back to Thursday/Friday
         if(qtState.dayeDayOfWeek == 1)
            prevDayStartNY = (datetime)((long)qtState.dayeDayStartNY - 3 * 86400);
         datetime prevDayStartSrv = timeEngine.NYToServer(prevDayStartNY);

         double pdhVal = -DBL_MAX;
         double pdlVal =  DBL_MAX;
         for(int i = 0; i < m15Count; i++)
           {
            if(m15Rates[i].time >= prevDayStartSrv && m15Rates[i].time < curDayStartSrv)
              {
               if(m15Rates[i].high > pdhVal) pdhVal = m15Rates[i].high;
               if(m15Rates[i].low  < pdlVal) pdlVal = m15Rates[i].low;
              }
           }
         if(pdhVal >= pdlVal)
           {
            SLiquidityPool pdh, pdl;
            pdh.Reset();
            pdh.type       = LIQ_POOL_PDH;
            pdh.isBuySide  = true;
            pdh.tfIdx      = TF_IDX_D1;
            pdh.price      = pdhVal;
            pdh.formedTime = curDayStartSrv;
            pdh.id         = StringFormat("PDH_DAYE_%I64d", (long)curDayStartSrv);
            AddPool(m_pools, m_poolCount, pdh);

            pdl.Reset();
            pdl.type       = LIQ_POOL_PDL;
            pdl.isBuySide  = false;
            pdl.tfIdx      = TF_IDX_D1;
            pdl.price      = pdlVal;
            pdl.formedTime = curDayStartSrv;
            pdl.id         = StringFormat("PDL_DAYE_%I64d", (long)curDayStartSrv);
            AddPool(m_pools, m_poolCount, pdl);
           }
        }

      // B3. Completed QT Session Highs & Lows of Current Daye Day (Asia Q1, London Q2, NY AM Q3)
      if(m15Count > 0 && qtState.dayeDayStartNY > 0)
        {
         for(int s = 0; s < 3; s++) // 0=Asia, 1=London, 2=NY_AM
           {
            datetime sesStartNY = (datetime)((long)qtState.dayeDayStartNY + (long)s * 6 * 3600);
            datetime sesEndNY   = (datetime)((long)sesStartNY + 6 * 3600);
            if(qtState.nyTime < sesEndNY)
               continue; // Only add completed sessions (or prior session extremes)

            datetime sesStartSrv = timeEngine.NYToServer(sesStartNY);
            datetime sesEndSrv   = timeEngine.NYToServer(sesEndNY);
            double sHi = -DBL_MAX;
            double sLo =  DBL_MAX;

            for(int i = 0; i < m15Count; i++)
              {
               if(m15Rates[i].time >= sesStartSrv && m15Rates[i].time < sesEndSrv)
                 {
                  if(m15Rates[i].high > sHi) sHi = m15Rates[i].high;
                  if(m15Rates[i].low  < sLo) sLo = m15Rates[i].low;
                 }
              }

            if(sHi >= sLo)
              {
               string sName = QTSessionToString((ENUM_QT_SESSION)(s + 1));
               SLiquidityPool sh, sl;
               sh.Reset();
               sh.type       = LIQ_POOL_SESSION_HIGH;
               sh.isBuySide  = true;
               sh.tfIdx      = TF_IDX_M15;
               sh.price      = sHi;
               sh.formedTime = sesEndSrv;
               sh.id         = StringFormat("SESH_%s_%I64d", sName, (long)sesEndSrv);
               AddPool(m_pools, m_poolCount, sh);

               sl.Reset();
               sl.type       = LIQ_POOL_SESSION_LOW;
               sl.isBuySide  = false;
               sl.tfIdx      = TF_IDX_M15;
               sl.price      = sLo;
               sl.formedTime = sesEndSrv;
               sl.id         = StringFormat("SESL_%s_%I64d", sName, (long)sesEndSrv);
               AddPool(m_pools, m_poolCount, sl);
              }
           }
        }

      // B4. EQH / EQL Clusters on H4, H1, M15
      int eqTfs[3] = { TF_IDX_H4, TF_IDX_H1, TF_IDX_M15 };
      for(int k = 0; k < 3; k++)
        {
         int tfIdx = eqTfs[k];
         int wCnt  = swings.GetWickSwingCount(tfIdx);
         if(wCnt < 2)
            continue;
         SSwingPoint wArr[];
         ArrayResize(wArr, wCnt);
         for(int i = 0; i < wCnt; i++)
            swings.GetWickSwing(tfIdx, i, wArr[i]);

         DetectEqualHighsLows(wArr,
                              wCnt,
                              tfIdx,
                              mtf.GetATR(tfIdx),
                              m_cfg.eqToleranceAtrMult,
                              m_cfg.eqLookbackSwings,
                              m_pools,
                              m_poolCount);
        }

      // B5. Key Wick Swings on W1, D1, H4, H1, M15
      int swTfs[5] = { TF_IDX_W1, TF_IDX_D1, TF_IDX_H4, TF_IDX_H1, TF_IDX_M15 };
      for(int k = 0; k < 5; k++)
        {
         int tfIdx = swTfs[k];
         int wCnt  = MathMin(12, swings.GetWickSwingCount(tfIdx));
         for(int i = 0; i < wCnt; i++)
           {
            SSwingPoint sp;
            if(!swings.GetWickSwing(tfIdx, i, sp))
               continue;
            SLiquidityPool p;
            p.Reset();
            p.type       = (sp.type == SWING_HIGH ? LIQ_POOL_SWING_HIGH : LIQ_POOL_SWING_LOW);
            p.isBuySide  = (sp.type == SWING_HIGH);
            p.tfIdx      = tfIdx;
            p.price      = sp.price;
            p.formedTime = sp.confirmTime;
            p.id         = StringFormat("SW_%s_%s_%I64d",
                                        QTTfIndexToString(tfIdx),
                                        (p.isBuySide ? "H" : "L"),
                                        (long)sp.pivotTime);
            AddPool(m_pools, m_poolCount, p);
           }
        }

      // Evaluate sweep/break status on all collected pools using M15 closed bars
      if(m15Count > 0)
        {
         for(int i = 0; i < m_poolCount; i++)
            EvaluatePoolSweepStatus(m_pools[i], m15Rates, m15Count);
        }
     }

   //--- Accessors for Liquidity Pools
   int               GetPoolCount() const { return m_poolCount; }
   bool              GetPool(const int idx, SLiquidityPool &outPool) const
     {
      if(idx < 0 || idx >= m_poolCount) return false;
      outPool = m_pools[idx];
      return true;
     }

   void              GetPoolsArray(SLiquidityPool &outArr[], int &outCount) const
     {
      outCount = m_poolCount;
      ArrayResize(outArr, outCount);
      for(int i = 0; i < outCount; i++)
         outArr[i] = m_pools[i];
     }

   //--- Accessors for FVGs
   int               GetFVGCount(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return 0;
      return m_fvgStore[tfIdx].count;
     }

   bool              GetFVG(const int tfIdx, const int idx, SFVGZone &outFvg) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      if(idx < 0 || idx >= m_fvgStore[tfIdx].count) return false;
      outFvg = m_fvgStore[tfIdx].fvgs[idx];
      return true;
     }

   //--- Find most recent tradable (OPEN or PARTIAL) FVG in direction formed at or after minBarTime
   bool              FindRecentTradableFVG(const int tfIdx,
                                           const ENUM_BIAS_DIR dir,
                                           const datetime minBarTime,
                                           SFVGZone &outFvg) const
     {
      outFvg.Reset();
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;

      for(int i = 0; i < m_fvgStore[tfIdx].count; i++)
        {
         SFVGZone f = m_fvgStore[tfIdx].fvgs[i];
         if(f.direction == dir && f.IsTradable() && f.bar3Time >= minBarTime)
           {
            outFvg = f;
            return true;
           }
        }
      return false;
     }
  };

#endif // QT_ICT_ENGINE_MQH
//+------------------------------------------------------------------+
