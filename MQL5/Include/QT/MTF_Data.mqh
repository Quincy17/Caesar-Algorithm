//+------------------------------------------------------------------+
//| MTF_Data.mqh                                                     |
//| M2 - Multi-Timeframe Closed-Bar Cache & New Bar Detector         |
//| Place in: MQL5/Include/QT/MTF_Data.mqh                           |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Maintain closed-bar MqlRates cache for W1, D1, H4, H1, M15, M5|
//|  - Strictly copy from shift 1 (closed bars only; zero repaint)   |
//|  - Detect new closed bar events independently per timeframe      |
//|  - Maintain ATR(14) indicator handles & closed-bar ATR values    |
//|  - Safely pause/wait if history or indicator data is incomplete  |
//+------------------------------------------------------------------+
#ifndef QT_MTF_DATA_MQH
#define QT_MTF_DATA_MQH

#include "Defines.mqh"

enum ENUM_QT_TF_INDEX
  {
   TF_IDX_W1  = 0,
   TF_IDX_D1  = 1,
   TF_IDX_H4  = 2,
   TF_IDX_H1  = 3,
   TF_IDX_M15 = 4,
   TF_IDX_M5  = 5
  };

//+------------------------------------------------------------------+
//| Helper to map ENUM_QT_TF_INDEX <-> ENUM_TIMEFRAMES               |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES QTTfIndexToPeriod(const int idx)
  {
   switch(idx)
     {
      case TF_IDX_W1:  return PERIOD_W1;
      case TF_IDX_D1:  return PERIOD_D1;
      case TF_IDX_H4:  return PERIOD_H4;
      case TF_IDX_H1:  return PERIOD_H1;
      case TF_IDX_M15: return PERIOD_M15;
      case TF_IDX_M5:  return PERIOD_M5;
      default:         return PERIOD_M5;
     }
  }

int QTPeriodToTfIndex(const ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_W1:  return TF_IDX_W1;
      case PERIOD_D1:  return TF_IDX_D1;
      case PERIOD_H4:  return TF_IDX_H4;
      case PERIOD_H1:  return TF_IDX_H1;
      case PERIOD_M15: return TF_IDX_M15;
      case PERIOD_M5:  return TF_IDX_M5;
      default:         return -1;
     }
  }

string QTTfIndexToString(const int idx)
  {
   switch(idx)
     {
      case TF_IDX_W1:  return "W1";
      case TF_IDX_D1:  return "D1";
      case TF_IDX_H4:  return "H4";
      case TF_IDX_H1:  return "H1";
      case TF_IDX_M15: return "M15";
      case TF_IDX_M5:  return "M5";
      default:         return "UNK";
     }
  }

//+------------------------------------------------------------------+
//| Per-Timeframe Closed Bar Cache Slot                              |
//+------------------------------------------------------------------+
struct STFCacheSlot
  {
   ENUM_TIMEFRAMES tf;
   int             maxBars;          // Number of closed bars to cache
   MqlRates        rates[];          // Indexed as series: rates[0] = shift 1 (latest closed bar), rates[k] = shift (k+1)
   int             count;            // Number of valid closed bars currently in rates[]
   datetime        lastClosedBarTime;// Open time of shift 1 bar (rates[0].time)
   bool            isNewBar;         // True on the tick where a new closed bar appeared on this TF
   bool            isReady;          // True if minimum history and ATR are loaded
   int             atrHandle;        // Handle to iATR(symbol, tf, 14)
   double          atrValue;         // Closed-bar ATR(14) at shift 1

   void Reset()
     {
      tf                = PERIOD_M5;
      maxBars           = 300;
      ArrayResize(rates, 0);
      ArraySetAsSeries(rates, true);
      count             = 0;
      lastClosedBarTime = 0;
      isNewBar          = false;
      isReady           = false;
      atrHandle         = INVALID_HANDLE;
      atrValue          = 0.0;
     }
  };

//+------------------------------------------------------------------+
//| CMTFDataManager Class                                            |
//+------------------------------------------------------------------+
class CMTFDataManager
  {
private:
   string            m_symbol;
   int               m_atrPeriod;
   STFCacheSlot      m_slots[QT_MTF_COUNT];
   bool              m_allReady;

   bool              RefreshSlot(const int idx, const bool forceReload)
     {
      ENUM_TIMEFRAMES tf = m_slots[idx].tf;

      // Check open time of the latest closed bar (shift 1)
      datetime closedBarTime = iTime(m_symbol, tf, 1);
      if(closedBarTime <= 0)
        {
         m_slots[idx].isReady  = false;
         m_slots[idx].isNewBar = false;
         return false;
        }

      bool newBarDetected = (forceReload || m_slots[idx].lastClosedBarTime == 0 ||
                             closedBarTime > m_slots[idx].lastClosedBarTime);

      m_slots[idx].isNewBar = newBarDetected;
      if(!newBarDetected && m_slots[idx].isReady)
         return true;

      // Copy closed bars starting strictly at shift = 1
      ArraySetAsSeries(m_slots[idx].rates, true);
      int copied = CopyRates(m_symbol, tf, 1, m_slots[idx].maxBars, m_slots[idx].rates);
      if(copied < 20) // Require at least 20 closed bars for swing/ATR stability
        {
         m_slots[idx].count    = (copied > 0 ? copied : 0);
         m_slots[idx].isReady  = false;
         m_slots[idx].isNewBar = false;
         return false;
        }

      ArraySetAsSeries(m_slots[idx].rates, true);
      m_slots[idx].count             = copied;
      m_slots[idx].lastClosedBarTime = m_slots[idx].rates[0].time;

      // Refresh closed-bar ATR(14) at shift = 1
      double atrBuf[];
      ArrayResize(atrBuf, 1);
      if(m_slots[idx].atrHandle != INVALID_HANDLE &&
         CopyBuffer(m_slots[idx].atrHandle, 0, 1, 1, atrBuf) == 1 &&
         atrBuf[0] > 0.0)
        {
         m_slots[idx].atrValue = atrBuf[0];
        }
      else
        {
         // Fallback manual True Range average over last m_atrPeriod closed bars
         int n = MathMin(m_atrPeriod, copied - 1);
         if(n > 0)
           {
            double sumTR = 0.0;
            for(int i = 0; i < n; i++)
              {
               double hi = m_slots[idx].rates[i].high;
               double lo = m_slots[idx].rates[i].low;
               double pc = m_slots[idx].rates[i + 1].close;
               double tr = MathMax(hi - lo, MathMax(MathAbs(hi - pc), MathAbs(lo - pc)));
               sumTR += tr;
              }
            m_slots[idx].atrValue = sumTR / (double)n;
           }
        }

      m_slots[idx].isReady = (m_slots[idx].atrValue > 0.0);
      return m_slots[idx].isReady;
     }

public:
                     CMTFDataManager()
     {
      m_symbol    = QT_TARGET_SYMBOL;
      m_atrPeriod = 14;
      m_allReady  = false;
      for(int i = 0; i < QT_MTF_COUNT; i++)
         m_slots[i].Reset();
     }

                    ~CMTFDataManager()
     {
      Deinit();
     }

   bool              Init(const string symbol,
                          const int atrPeriod = 14,
                          const int barsW1  = 120,
                          const int barsD1  = 250,
                          const int barsH4  = 400,
                          const int barsH1  = 500,
                          const int barsM15 = 600,
                          const int barsM5  = 800)
     {
      Deinit();
      m_symbol    = (StringLen(symbol) > 0 ? symbol : _Symbol);
      m_atrPeriod = MathMax(1, atrPeriod);
      m_allReady  = false;

      int barCounts[QT_MTF_COUNT];
      barCounts[TF_IDX_W1]  = barsW1;
      barCounts[TF_IDX_D1]  = barsD1;
      barCounts[TF_IDX_H4]  = barsH4;
      barCounts[TF_IDX_H1]  = barsH1;
      barCounts[TF_IDX_M15] = barsM15;
      barCounts[TF_IDX_M5]  = barsM5;

      for(int i = 0; i < QT_MTF_COUNT; i++)
        {
         m_slots[i].Reset();
         m_slots[i].tf        = QTTfIndexToPeriod(i);
         m_slots[i].maxBars   = MathMax(30, barCounts[i]);
         m_slots[i].atrHandle = iATR(m_symbol, m_slots[i].tf, m_atrPeriod);
        }

      return Update(true);
     }

   void              Deinit()
     {
      for(int i = 0; i < QT_MTF_COUNT; i++)
        {
         if(m_slots[i].atrHandle != INVALID_HANDLE)
           {
            IndicatorRelease(m_slots[i].atrHandle);
            m_slots[i].atrHandle = INVALID_HANDLE;
           }
         m_slots[i].Reset();
        }
      m_allReady = false;
     }

   //--- Call on every OnTick(); updates only TFs with a newly closed bar
   bool              Update(const bool forceReload = false)
     {
      bool ready = true;
      for(int i = 0; i < QT_MTF_COUNT; i++)
        {
         if(!RefreshSlot(i, forceReload))
            ready = false;
        }
      m_allReady = ready;
      return m_allReady;
     }

   bool              IsAllReady() const { return m_allReady; }
   bool              IsTFReady(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      return m_slots[tfIdx].isReady;
     }

   bool              IsNewBar(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      return m_slots[tfIdx].isNewBar;
     }

   bool              AnyNewBar() const
     {
      for(int i = 0; i < QT_MTF_COUNT; i++)
         if(m_slots[i].isNewBar) return true;
      return false;
     }

   double            GetATR(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return 0.0;
      return m_slots[tfIdx].atrValue;
     }

   int               GetClosedBarCount(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return 0;
      return m_slots[tfIdx].count;
     }

   //--- Note on indexing:
   //    shift = 1 is the most recently closed bar (stored at rates[0])
   //    shift = k (k >= 1) is stored at rates[k - 1]
   bool              GetClosedBar(const int tfIdx, const int closedShift, MqlRates &outBar) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      int arrIdx = closedShift - 1;
      if(arrIdx < 0 || arrIdx >= m_slots[tfIdx].count) return false;
      outBar = m_slots[tfIdx].rates[arrIdx];
      return true;
     }

   //--- Copy closed bars array (series-indexed: index 0 = shift 1)
   int               GetClosedRatesArray(const int tfIdx, MqlRates &outRates[]) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT || m_slots[tfIdx].count <= 0)
        {
         ArrayResize(outRates, 0);
         return 0;
        }
      int cnt = m_slots[tfIdx].count;
      ArrayResize(outRates, cnt);
      ArraySetAsSeries(outRates, true);
      for(int i = 0; i < cnt; i++)
         outRates[i] = m_slots[tfIdx].rates[i];
      return cnt;
     }
  };

#endif // QT_MTF_DATA_MQH
//+------------------------------------------------------------------+
