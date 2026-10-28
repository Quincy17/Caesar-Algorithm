//+------------------------------------------------------------------+
//| Swings.mqh                                                       |
//| M3 - Multi-Timeframe Fractal Swing Engine (Wick & Body Variants) |
//| Place in: MQL5/Include/QT/Swings.mqh                             |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Detect fractal Swing Highs & Swing Lows per timeframe         |
//|  - Default strength N per TF: W1=2, D1=2, H4=2, H1=3, M15=2, M5=2|
//|  - Confirmed strictly after N closed bars to the right           |
//|    (Zero repaint guarantee)                                      |
//|  - Two variants per TF:                                          |
//|    1. Wick Swings (high/low) -> used by ICT & Structure          |
//|    2. Body Swings (close/line chart) -> used by MSNR (A/V/QM)    |
//+------------------------------------------------------------------+
#ifndef QT_SWINGS_MQH
#define QT_SWINGS_MQH

#include "MTF_Data.mqh"

enum ENUM_SWING_TYPE
  {
   SWING_HIGH =  1, // Peak (Resistance / Buy-side liquidity)
   SWING_LOW  = -1  // Valley (Support / Sell-side liquidity)
  };

enum ENUM_SWING_SOURCE
  {
   SWING_SOURCE_WICK = 0, // Based on candle High / Low (ICT & Structure)
   SWING_SOURCE_BODY = 1  // Based on candle Close / Line Chart (MSNR A, V, QM)
  };

struct SSwingPoint
  {
   ENUM_SWING_TYPE   type;           // SWING_HIGH (+1) or SWING_LOW (-1)
   ENUM_SWING_SOURCE source;         // SWING_SOURCE_WICK or SWING_SOURCE_BODY
   int               tfIdx;          // Timeframe index (TF_IDX_W1 .. TF_IDX_M5)
   datetime          pivotTime;      // Open time of the pivot bar
   datetime          confirmTime;    // Open time of the N-th closed bar to the right
   int               pivotClosedShift;   // Closed shift (1 = latest closed bar)
   int               confirmClosedShift; // Closed shift where N-th right bar closed
   double            price;          // Swing level price (High/Low for Wick; Close for Body)
   double            candleHigh;     // Full candle High at pivot bar
   double            candleLow;      // Full candle Low at pivot bar
   double            candleClose;    // Full candle Close at pivot bar

   void Reset()
     {
      type               = SWING_HIGH;
      source             = SWING_SOURCE_WICK;
      tfIdx              = TF_IDX_M5;
      pivotTime          = 0;
      confirmTime        = 0;
      pivotClosedShift   = 0;
      confirmClosedShift = 0;
      price              = 0.0;
      candleHigh         = 0.0;
      candleLow          = 0.0;
      candleClose        = 0.0;
     }
  };

struct SSwingConfig
  {
   int strength[QT_MTF_COUNT]; // Fractal N left & right bars per TF
   int maxSwingsPerTF;         // Maximum swings stored per TF (default 100)

   void SetDefaults()
     {
      strength[TF_IDX_W1]  = 2;
      strength[TF_IDX_D1]  = 2;
      strength[TF_IDX_H4]  = 2;
      strength[TF_IDX_H1]  = 3;
      strength[TF_IDX_M15] = 2;
      strength[TF_IDX_M5]  = 2;
      maxSwingsPerTF       = 100;
     }
  };

struct STFSwingStore
  {
   SSwingPoint wickSwings[]; // Ordered newest-first (index 0 = most recent confirmed swing)
   int         wickCount;
   SSwingPoint bodySwings[]; // Ordered newest-first (index 0 = most recent confirmed body swing)
   int         bodyCount;

   void Reset()
     {
      ArrayResize(wickSwings, 0);
      wickCount = 0;
      ArrayResize(bodySwings, 0);
      bodyCount = 0;
     }
  };

//+------------------------------------------------------------------+
//| CSwingEngine Class                                               |
//+------------------------------------------------------------------+
class CSwingEngine
  {
private:
   SSwingConfig      m_cfg;
   STFSwingStore     m_store[QT_MTF_COUNT];

   static void       AppendSwing(SSwingPoint &arr[], int &count, const SSwingPoint &pt, const int maxCap)
     {
      if(count >= maxCap)
         return;
      ArrayResize(arr, count + 1, 64);
      arr[count] = pt;
      count++;
     }

public:
                     CSwingEngine()
     {
      m_cfg.SetDefaults();
      for(int i = 0; i < QT_MTF_COUNT; i++)
         m_store[i].Reset();
     }

   void              Init(const SSwingConfig &cfg)
     {
      m_cfg = cfg;
      for(int i = 0; i < QT_MTF_COUNT; i++)
         m_store[i].Reset();
     }

   SSwingConfig      GetConfig() const { return m_cfg; }
   int               GetStrength(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return 2;
      return MathMax(1, m_cfg.strength[tfIdx]);
     }

   //+------------------------------------------------------------------+
   //| Scan a series-indexed closed-bar MqlRates array (index 0=shift 1)|
   //| and populate Wick Swings and Body Swings (newest-first).         |
   //+------------------------------------------------------------------+
   static void       ScanRatesForSwings(const MqlRates &rates[],
                                        const int count,
                                        const int tfIdx,
                                        const int strengthN,
                                        const int maxCap,
                                        SSwingPoint &outWick[],
                                        int &outWickCount,
                                        SSwingPoint &outBody[],
                                        int &outBodyCount)
     {
      ArrayResize(outWick, 0);
      outWickCount = 0;
      ArrayResize(outBody, 0);
      outBodyCount = 0;

      int N = MathMax(1, strengthN);
      if(count < 2 * N + 1)
         return;

      // p is index in series-ordered rates[] (0 = closed shift 1).
      // Minimum p is N so that p - N >= 0 (all N right-side bars are closed).
      for(int p = N; p < count - N; p++)
        {
         //--------------------------------------------------------------
         // 1. Wick Swing High & Low (High / Low prices)
         //--------------------------------------------------------------
         double candHigh = rates[p].high;
         double candLow  = rates[p].low;
         bool isWickHigh = true;
         bool isWickLow  = true;

         for(int k = 1; k <= N; k++)
           {
            // Right side (newer closed bars: p - k) -> strict inequality prevents duplicate plateau triggers
            if(rates[p - k].high >= candHigh) isWickHigh = false;
            if(rates[p - k].low  <= candLow)  isWickLow  = false;

            // Left side (older closed bars: p + k) -> non-strict allows first bar of plateau
            if(rates[p + k].high > candHigh)  isWickHigh = false;
            if(rates[p + k].low  < candLow)   isWickLow  = false;

            if(!isWickHigh && !isWickLow)
               break;
           }

         if(isWickHigh && outWickCount < maxCap)
           {
            SSwingPoint pt;
            pt.type               = SWING_HIGH;
            pt.source             = SWING_SOURCE_WICK;
            pt.tfIdx              = tfIdx;
            pt.pivotTime          = rates[p].time;
            pt.confirmTime        = rates[p - N].time;
            pt.pivotClosedShift   = p + 1;
            pt.confirmClosedShift = (p - N) + 1;
            pt.price              = candHigh;
            pt.candleHigh         = rates[p].high;
            pt.candleLow          = rates[p].low;
            pt.candleClose        = rates[p].close;
            AppendSwing(outWick, outWickCount, pt, maxCap);
           }

         if(isWickLow && outWickCount < maxCap)
           {
            SSwingPoint pt;
            pt.type               = SWING_LOW;
            pt.source             = SWING_SOURCE_WICK;
            pt.tfIdx              = tfIdx;
            pt.pivotTime          = rates[p].time;
            pt.confirmTime        = rates[p - N].time;
            pt.pivotClosedShift   = p + 1;
            pt.confirmClosedShift = (p - N) + 1;
            pt.price              = candLow;
            pt.candleHigh         = rates[p].high;
            pt.candleLow          = rates[p].low;
            pt.candleClose        = rates[p].close;
            AppendSwing(outWick, outWickCount, pt, maxCap);
           }

         //--------------------------------------------------------------
         // 2. Body Swing High & Low (Close / Line Chart prices for MSNR)
         //--------------------------------------------------------------
         double candClose = rates[p].close;
         bool isBodyHigh  = true;
         bool isBodyLow   = true;

         for(int k = 1; k <= N; k++)
           {
            if(rates[p - k].close >= candClose) isBodyHigh = false;
            if(rates[p - k].close <= candClose) isBodyLow  = false;

            if(rates[p + k].close > candClose)  isBodyHigh = false;
            if(rates[p + k].close < candClose)  isBodyLow  = false;

            if(!isBodyHigh && !isBodyLow)
               break;
           }

         if(isBodyHigh && outBodyCount < maxCap)
           {
            SSwingPoint pt;
            pt.type               = SWING_HIGH;
            pt.source             = SWING_SOURCE_BODY;
            pt.tfIdx              = tfIdx;
            pt.pivotTime          = rates[p].time;
            pt.confirmTime        = rates[p - N].time;
            pt.pivotClosedShift   = p + 1;
            pt.confirmClosedShift = (p - N) + 1;
            pt.price              = candClose;
            pt.candleHigh         = rates[p].high;
            pt.candleLow          = rates[p].low;
            pt.candleClose        = candClose;
            AppendSwing(outBody, outBodyCount, pt, maxCap);
           }

         if(isBodyLow && outBodyCount < maxCap)
           {
            SSwingPoint pt;
            pt.type               = SWING_LOW;
            pt.source             = SWING_SOURCE_BODY;
            pt.tfIdx              = tfIdx;
            pt.pivotTime          = rates[p].time;
            pt.confirmTime        = rates[p - N].time;
            pt.pivotClosedShift   = p + 1;
            pt.confirmClosedShift = (p - N) + 1;
            pt.price              = candClose;
            pt.candleHigh         = rates[p].high;
            pt.candleLow          = rates[p].low;
            pt.candleClose        = candClose;
            AppendSwing(outBody, outBodyCount, pt, maxCap);
           }
        }
     }

   //+------------------------------------------------------------------+
   //| Update Swings for TFs that closed a new bar                      |
   //+------------------------------------------------------------------+
   void              Update(CMTFDataManager &mtf, const bool forceAll = false)
     {
      for(int tfIdx = 0; tfIdx < QT_MTF_COUNT; tfIdx++)
        {
         if(!mtf.IsTFReady(tfIdx))
            continue;
         if(!forceAll && !mtf.IsNewBar(tfIdx) && m_store[tfIdx].wickCount > 0)
            continue;

         MqlRates rates[];
         int cnt = mtf.GetClosedRatesArray(tfIdx, rates);
         ScanRatesForSwings(rates,
                            cnt,
                            tfIdx,
                            m_cfg.strength[tfIdx],
                            m_cfg.maxSwingsPerTF,
                            m_store[tfIdx].wickSwings,
                            m_store[tfIdx].wickCount,
                            m_store[tfIdx].bodySwings,
                            m_store[tfIdx].bodyCount);
        }
     }

   //--- Accessors for Wick Swings (newest-first: index 0 = most recent)
   int               GetWickSwingCount(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return 0;
      return m_store[tfIdx].wickCount;
     }

   bool              GetWickSwing(const int tfIdx, const int idx, SSwingPoint &outPt) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      if(idx < 0 || idx >= m_store[tfIdx].wickCount) return false;
      outPt = m_store[tfIdx].wickSwings[idx];
      return true;
     }

   //--- Accessors for Body Swings (newest-first: index 0 = most recent)
   int               GetBodySwingCount(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return 0;
      return m_store[tfIdx].bodyCount;
     }

   bool              GetBodySwing(const int tfIdx, const int idx, SSwingPoint &outPt) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      if(idx < 0 || idx >= m_store[tfIdx].bodyCount) return false;
      outPt = m_store[tfIdx].bodySwings[idx];
      return true;
     }

   //--- Find most recent Wick Swing of given type (SWING_HIGH or SWING_LOW)
   bool              GetLatestWickSwingByType(const int tfIdx,
                                              const ENUM_SWING_TYPE type,
                                              SSwingPoint &outPt,
                                              const int minClosedShift = 1) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      for(int i = 0; i < m_store[tfIdx].wickCount; i++)
        {
         if(m_store[tfIdx].wickSwings[i].type == type &&
            m_store[tfIdx].wickSwings[i].pivotClosedShift >= minClosedShift)
           {
            outPt = m_store[tfIdx].wickSwings[i];
            return true;
           }
        }
      return false;
     }
  };

#endif // QT_SWINGS_MQH
//+------------------------------------------------------------------+
