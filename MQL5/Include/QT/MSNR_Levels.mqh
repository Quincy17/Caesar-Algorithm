//+------------------------------------------------------------------+
//| MSNR_Levels.mqh                                                  |
//| M4 - Malaysian SNR (MSNR) Engine: Classic A, V, RBS, SBR & QM    |
//| Place in: MQL5/Include/QT/MSNR_Levels.mqh                        |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Detect Classic A (Resistance peak) & Classic V (Support       |
//|    valley) from Body/Close Swings across W1, D1, H4, H1, M15, M5 |
//|  - Detect Quasimodo (QM Bullish & Bearish) from 5 consecutive    |
//|    Body Swings at Left Shoulder body price on D1, H4, H1, M15, M5|
//|  - Track closed-bar lifecycle:                                   |
//|    Fresh -> Touched (wick touch, removed from active pool)       |
//|    Fresh -> Broken (body close break) -> Flips to RBS / SBR Fresh|
//|    RBS/SBR/QM Fresh -> First touch -> Used                       |
//|  - Touch tolerance zone = max(spread, touchAtrMult * ATR(14))    |
//|  - Cap active levels to max 20 nearest per TF & max age X bars   |
//+------------------------------------------------------------------+
#ifndef QT_MSNR_LEVELS_MQH
#define QT_MSNR_LEVELS_MQH

#include "Swings.mqh"

struct SMSNRConfig
  {
   double touchAtrMult;        // Zone tolerance = max(spread, touchAtrMult * ATR(14)), default 0.05
   int    maxActiveLevelsPerTF;// Max active levels kept nearest to price per TF (default 20)
   int    maxLevelAgeBars;     // Ignore levels older than X bars on that TF (default 250)
   int    maxQMBodyBreak;      // Max body breaks allowed within QM pattern (default 2)
   bool   enableTF[QT_MTF_COUNT]; // Enabled timeframes for MSNR detection

   void SetDefaults()
     {
      touchAtrMult         = 0.05;
      maxActiveLevelsPerTF = 20;
      maxLevelAgeBars      = 250;
      maxQMBodyBreak       = 2;
      for(int i = 0; i < QT_MTF_COUNT; i++)
         enableTF[i] = true; // W1, D1, H4, H1, M15, M5 all enabled by default
     }
  };

struct SMSNRLevel
  {
   string          id;               // Unique level identifier
   ENUM_POI_TYPE   type;             // POI_CLASSIC_A, POI_CLASSIC_V, POI_RBS, POI_SBR, POI_QM_BULL, POI_QM_BEAR
   ENUM_POI_STATUS status;           // POI_STATUS_FRESH, TOUCHED, BROKEN, USED
   int             tfIdx;            // Timeframe index (TF_IDX_W1 .. TF_IDX_M5)
   ENUM_BIAS_DIR   direction;        // BIAS_BULL (+1 Support: V, RBS, QM_BULL) or BIAS_BEAR (-1 Resistance: A, SBR, QM_BEAR)
   double          price;            // Exact body/close level price (Proximal MSNR line)
   double          wickExtreme;      // Distal pivot wick extreme (High for Resistance, Low for Support)
   double          tolerance;        // Calculated touch tolerance = max(spread, 0.05 * ATR14)
   double          zoneLow;          // Lower edge of Body-to-Wick zone
   double          zoneHigh;         // Upper edge of Body-to-Wick zone

   datetime        pivotTime;        // Bar time of original pivot (or Left Shoulder for QM)
   datetime        activeFromTime;   // Bar time when level became active (confirmTime for A/V; breakTime for RBS/SBR/QM)
   datetime        firstTouchTime;   // Bar time when first wick touched the active level (0 if never touched)
   int             pivotClosedShift; // Current closed shift of original pivot
   int             activeClosedShift;// Current closed shift when level became active
   int             touchClosedShift; // Closed shift of first wick touch (0 if never touched)
   bool            usedByTrade;      // True once a setup/trade has consumed this POI

   // QM specific metadata
   double          qmHeadPrice;      // Head body price (for QM validation & SL reference)
   datetime        qmHeadTime;       // Head bar time

   void Reset()
     {
      id                = "";
      type              = POI_NONE;
      status            = POI_STATUS_FRESH;
      tfIdx             = TF_IDX_H1;
      direction         = BIAS_NEUTRAL;
      price             = 0.0;
      wickExtreme       = 0.0;
      tolerance         = 0.0;
      zoneLow           = 0.0;
      zoneHigh          = 0.0;
      pivotTime         = 0;
      activeFromTime    = 0;
      firstTouchTime    = 0;
      pivotClosedShift  = 0;
      activeClosedShift = 0;
      touchClosedShift  = 0;
      usedByTrade       = false;
      qmHeadPrice       = 0.0;
      qmHeadTime        = 0;
     }

   //--- True if level is currently eligible for S1_POI_TOUCH
   //    (Either completely untouched FRESH, or touched for the very first time on the latest closed bar shift 1..3)
   bool IsFreshForEntry(const int maxRecentTouchShift = 2) const
     {
      if(usedByTrade)
         return false;
      if(status == POI_STATUS_FRESH)
         return true;
      if((status == POI_STATUS_TOUCHED || status == POI_STATUS_USED) &&
         touchClosedShift >= 1 && touchClosedShift <= maxRecentTouchShift)
         return true;
      return false;
     }
  };

struct STFMSNRStore
  {
   SMSNRLevel levels[];   // Filtered & sorted active/recent levels
   int        count;

   void Reset()
     {
      ArrayResize(levels, 0);
      count = 0;
     }
  };

//+------------------------------------------------------------------+
//| Helper Formatter for POI Type & Status                           |
//+------------------------------------------------------------------+
string QTPOITypeToString(const ENUM_POI_TYPE t)
  {
   switch(t)
     {
      case POI_CLASSIC_A: return "Classic_A";
      case POI_CLASSIC_V: return "Classic_V";
      case POI_RBS:       return "RBS";
      case POI_SBR:       return "SBR";
      case POI_QM_BULL:   return "QM_Bull";
      case POI_QM_BEAR:   return "QM_Bear";
      default:            return "None";
     }
  }

string QTPOIStatusToString(const ENUM_POI_STATUS s)
  {
   switch(s)
     {
      case POI_STATUS_FRESH:   return "FRESH";
      case POI_STATUS_TOUCHED: return "TOUCHED";
      case POI_STATUS_BROKEN:  return "BROKEN";
      case POI_STATUS_USED:    return "USED";
      default:                 return "UNK";
     }
  }

//+------------------------------------------------------------------+
//| CMSNREngine Class                                                |
//+------------------------------------------------------------------+
class CMSNREngine
  {
private:
   SMSNRConfig       m_cfg;
   STFMSNRStore      m_store[QT_MTF_COUNT];
   string            m_consumedIds[];
   int               m_consumedCount;

   bool              IsConsumedId(const string id) const
     {
      for(int i = 0; i < m_consumedCount; i++)
         if(m_consumedIds[i] == id)
            return true;
      return false;
     }

   static void       AddLevelToList(SMSNRLevel &arr[], int &cnt, const SMSNRLevel &lvl)
     {
      ArrayResize(arr, cnt + 1, 64);
      arr[cnt] = lvl;
      cnt++;
     }

   //--- Build chronological alternating sequence of Body Swings (oldest -> newest)
   static void       BuildAlternatingBodySwings(const SSwingPoint &bodySwingsNewestFirst[],
                                                const int bodyCount,
                                                const int maxAgeBars,
                                                SSwingPoint &outChrono[],
                                                int &outCount)
     {
      ArrayResize(outChrono, 0);
      outCount = 0;

      // Iterate from oldest to newest
      for(int i = bodyCount - 1; i >= 0; i--)
        {
         if(bodySwingsNewestFirst[i].pivotClosedShift > maxAgeBars)
            continue;

         if(outCount == 0)
           {
            ArrayResize(outChrono, 1, 64);
            outChrono[0] = bodySwingsNewestFirst[i];
            outCount     = 1;
            continue;
           }

         SSwingPoint last = outChrono[outCount - 1];
         if(bodySwingsNewestFirst[i].type != last.type)
           {
            ArrayResize(outChrono, outCount + 1, 64);
            outChrono[outCount] = bodySwingsNewestFirst[i];
            outCount++;
           }
         else
           {
            // Same swing type consecutively -> keep the more extreme body pivot
            if((last.type == SWING_HIGH && bodySwingsNewestFirst[i].price >= last.price) ||
               (last.type == SWING_LOW  && bodySwingsNewestFirst[i].price <= last.price))
              {
               outChrono[outCount - 1] = bodySwingsNewestFirst[i];
              }
           }
        }
     }

public:
                     CMSNREngine()
     {
      m_cfg.SetDefaults();
      m_consumedCount = 0;
      ArrayResize(m_consumedIds, 0);
      for(int i = 0; i < QT_MTF_COUNT; i++)
         m_store[i].Reset();
     }

   void              Init(const SMSNRConfig &cfg)
     {
      m_cfg = cfg;
      m_consumedCount = 0;
      ArrayResize(m_consumedIds, 0);
      for(int i = 0; i < QT_MTF_COUNT; i++)
         m_store[i].Reset();
     }

   SMSNRConfig       GetConfig() const { return m_cfg; }

   //--- Mark a POI level as consumed after a trade is taken on it
   void              MarkLevelUsed(const string id)
     {
      if(StringLen(id) == 0 || IsConsumedId(id))
         return;
      ArrayResize(m_consumedIds, m_consumedCount + 1, 32);
      m_consumedIds[m_consumedCount] = id;
      m_consumedCount++;

      for(int tf = 0; tf < QT_MTF_COUNT; tf++)
        {
         for(int i = 0; i < m_store[tf].count; i++)
           {
            if(m_store[tf].levels[i].id == id)
              {
               m_store[tf].levels[i].usedByTrade = true;
               m_store[tf].levels[i].status      = POI_STATUS_USED;
              }
           }
        }
     }

   //+------------------------------------------------------------------+
   //| Core Builder: Detect Classic A, V, RBS, SBR, and QM on a single  |
   //| timeframe from closed-bar rates[] and bodySwings[].              |
   //+------------------------------------------------------------------+
   static void       BuildLevelsForTF(const MqlRates &rates[],
                                      const int ratesCount,
                                      const SSwingPoint &bodySwings[],
                                      const int bodyCount,
                                      const int tfIdx,
                                      const double atrValue,
                                      const double currentSpreadPrice,
                                      const SMSNRConfig &cfg,
                                      SMSNRLevel &outLevels[],
                                      int &outCount)
     {
      ArrayResize(outLevels, 0);
      outCount = 0;
      if(ratesCount < 5 || bodyCount <= 0)
         return;

      double tol = MathMax(currentSpreadPrice, cfg.touchAtrMult * atrValue);
      if(tol < 0.0) tol = 0.0;

      SMSNRLevel rawList[];
      int rawCount = 0;

      //----------------------------------------------------------------
      // PART 1: Classic A, Classic V, and Flips to RBS / SBR
      //----------------------------------------------------------------
      for(int s = 0; s < bodyCount; s++)
        {
         SSwingPoint sw = bodySwings[s];
         if(sw.pivotClosedShift > cfg.maxLevelAgeBars)
            continue;

         int pivotArrIdx   = sw.pivotClosedShift - 1;
         int confirmArrIdx = sw.confirmClosedShift - 1;
         if(pivotArrIdx < 0 || pivotArrIdx >= ratesCount || confirmArrIdx < 0)
            continue;

         bool isResistanceA = (sw.type == SWING_HIGH);
         double lvlPrice    = sw.price;
         double pivHigh     = MathMax(sw.candleHigh, (pivotArrIdx > 0 ? rates[pivotArrIdx - 1].high : sw.candleHigh));
         double pivLow      = MathMin(sw.candleLow,  (pivotArrIdx > 0 ? rates[pivotArrIdx - 1].low  : sw.candleLow));

         SMSNRLevel baseLvl;
         baseLvl.Reset();
         baseLvl.tfIdx             = tfIdx;
         baseLvl.type              = (isResistanceA ? POI_CLASSIC_A : POI_CLASSIC_V);
         baseLvl.direction         = (isResistanceA ? BIAS_BEAR : BIAS_BULL);
         baseLvl.price             = lvlPrice;
         baseLvl.wickExtreme       = (isResistanceA ? MathMax(lvlPrice, pivHigh) : MathMin(lvlPrice, pivLow));
         baseLvl.tolerance         = tol;
         if(isResistanceA)
           {
            // MSNR Classic A Zone: from Body Close (proximal) up to Pivot Wick High (distal)
            baseLvl.zoneLow  = lvlPrice - tol;
            baseLvl.zoneHigh = MathMax(lvlPrice, baseLvl.wickExtreme) + tol;
           }
         else
           {
            // MSNR Classic V Zone: from Pivot Wick Low (distal) up to Body Close (proximal)
            baseLvl.zoneLow  = MathMin(lvlPrice, baseLvl.wickExtreme) - tol;
            baseLvl.zoneHigh = lvlPrice + tol;
           }
         baseLvl.pivotTime         = sw.pivotTime;
         baseLvl.activeFromTime    = sw.confirmTime;
         baseLvl.pivotClosedShift  = sw.pivotClosedShift;
         baseLvl.activeClosedShift = sw.confirmClosedShift;
         baseLvl.status            = POI_STATUS_FRESH;
         baseLvl.id                = StringFormat("%s_%s_%I64d",
                                                  QTTfIndexToString(tfIdx),
                                                  QTPOITypeToString(baseLvl.type),
                                                  (long)sw.pivotTime);

         // Scan closed bars chronologically AFTER pivot confirmation (from confirmArrIdx - 1 down to 0)
         int breakArrIdx = -1;
         for(int idx = confirmArrIdx - 1; idx >= 0; idx--)
           {
            double hi = rates[idx].high;
            double lo = rates[idx].low;
            double cl = rates[idx].close;

            if(isResistanceA)
              {
               // Classic A (Resistance): body close above level -> BROKEN -> flips to RBS
               if(cl > lvlPrice)
                 {
                  baseLvl.status = POI_STATUS_BROKEN;
                  breakArrIdx    = idx;
                  break;
                 }
               // Wick touch without body close break -> TOUCHED (unfresh)
               if(hi >= baseLvl.zoneLow && baseLvl.status == POI_STATUS_FRESH)
                 {
                  baseLvl.status           = POI_STATUS_TOUCHED;
                  baseLvl.firstTouchTime   = rates[idx].time;
                  baseLvl.touchClosedShift = idx + 1;
                 }
              }
            else
              {
               // Classic V (Support): body close below level -> BROKEN -> flips to SBR
               if(cl < lvlPrice)
                 {
                  baseLvl.status = POI_STATUS_BROKEN;
                  breakArrIdx    = idx;
                  break;
                 }
               // Wick touch without body close break -> TOUCHED (unfresh)
               if(lo <= baseLvl.zoneHigh && baseLvl.status == POI_STATUS_FRESH)
                 {
                  baseLvl.status           = POI_STATUS_TOUCHED;
                  baseLvl.firstTouchTime   = rates[idx].time;
                  baseLvl.touchClosedShift = idx + 1;
                 }
              }
           }

         // If Classic A/V was NOT broken, keep it in rawList (Fresh or recently Touched)
         if(baseLvl.status != POI_STATUS_BROKEN)
           {
            AddLevelToList(rawList, rawCount, baseLvl);
           }
         else if(breakArrIdx >= 0)
           {
            // Spawn flipped level: Resistance A broken up -> RBS (Support); Support V broken down -> SBR (Resistance)
            SMSNRLevel flipLvl;
            flipLvl.Reset();
            flipLvl.tfIdx             = tfIdx;
            flipLvl.type              = (isResistanceA ? POI_RBS : POI_SBR);
            flipLvl.direction         = (isResistanceA ? BIAS_BULL : BIAS_BEAR);
            flipLvl.price             = lvlPrice;
            flipLvl.wickExtreme       = lvlPrice;
            flipLvl.tolerance         = tol;
            // RBS / SBR (Flipped A/V): touch zone is strictly around the broken Body Close line [lvlPrice - tol, lvlPrice + tol]
            flipLvl.zoneLow           = lvlPrice - tol;
            flipLvl.zoneHigh          = lvlPrice + tol;
            flipLvl.pivotTime         = sw.pivotTime;
            flipLvl.activeFromTime    = rates[breakArrIdx].time;
            flipLvl.pivotClosedShift  = sw.pivotClosedShift;
            flipLvl.activeClosedShift = breakArrIdx + 1;
            flipLvl.status            = POI_STATUS_FRESH;
            flipLvl.id                = StringFormat("%s_%s_%I64d",
                                                     QTTfIndexToString(tfIdx),
                                                     QTPOITypeToString(flipLvl.type),
                                                     (long)sw.pivotTime);

            // Track RBS/SBR lifecycle from bar after breakout (breakArrIdx - 1 down to 0)
            bool invalidatedByRebreak = false;
            for(int j = breakArrIdx - 1; j >= 0; j--)
              {
               double hi = rates[j].high;
               double lo = rates[j].low;
               double cl = rates[j].close;

               if(flipLvl.type == POI_RBS)
                 {
                  // RBS is Support: if body closes back below zoneLow, RBS fails
                  if(cl < flipLvl.zoneLow)
                    {
                     invalidatedByRebreak = true;
                     break;
                    }
                  // First wick touch of RBS support from above
                  if(lo <= flipLvl.zoneHigh && flipLvl.status == POI_STATUS_FRESH)
                    {
                     flipLvl.status           = POI_STATUS_USED;
                     flipLvl.firstTouchTime   = rates[j].time;
                     flipLvl.touchClosedShift = j + 1;
                    }
                 }
               else // POI_SBR (Resistance)
                 {
                  // SBR is Resistance: if body closes back above zoneHigh, SBR fails
                  if(cl > flipLvl.zoneHigh)
                    {
                     invalidatedByRebreak = true;
                     break;
                    }
                  // First wick touch of SBR resistance from below
                  if(hi >= flipLvl.zoneLow && flipLvl.status == POI_STATUS_FRESH)
                    {
                     flipLvl.status           = POI_STATUS_USED;
                     flipLvl.firstTouchTime   = rates[j].time;
                     flipLvl.touchClosedShift = j + 1;
                    }
                 }
              }

            if(!invalidatedByRebreak)
               AddLevelToList(rawList, rawCount, flipLvl);
           }
        }

      //----------------------------------------------------------------
      // PART 2: Quasimodo (QM Bullish & Bearish) on D1, H4, H1, M15, M5
      //----------------------------------------------------------------
      if(tfIdx != TF_IDX_W1)
        {
         SSwingPoint altSwings[];
         int altCount = 0;
         BuildAlternatingBodySwings(bodySwings, bodyCount, cfg.maxLevelAgeBars, altSwings, altCount);

         // Need at least 4 alternating body swings (LS -> Inter -> Head -> Structure Break)
         // before price returns to Left Shoulder (the 5th leg).
         for(int i = 0; i + 3 < altCount; i++)
           {
            SSwingPoint s1_LS   = altSwings[i];     // Left Shoulder
            SSwingPoint s2_Int  = altSwings[i + 1]; // Intermediate High/Low
            SSwingPoint s3_Head = altSwings[i + 2]; // Head (LL for Bull QM, HH for Bear QM)
            SSwingPoint s4_Bos  = altSwings[i + 3]; // Structure Break leg

            // 2A. Bullish QM: Low(LS) -> High(Int) -> Lower Low(Head < LS) -> Higher High(Bos > Int)
            if(s1_LS.type   == SWING_LOW  &&
               s2_Int.type  == SWING_HIGH &&
               s3_Head.type == SWING_LOW  && s3_Head.price < s1_LS.price &&
               s4_Bos.type  == SWING_HIGH && s4_Bos.price  > s2_Int.price)
              {
               int headIdx = s3_Head.pivotClosedShift - 1;
               int bosIdx  = s4_Bos.pivotClosedShift - 1;
               int breakArrIdx = -1;
               int bodyBreaksCount = 0;

               for(int k = headIdx - 1; k >= bosIdx && k >= 0; k--)
                 {
                  if(rates[k].close > s2_Int.price)
                    {
                     if(breakArrIdx < 0)
                        breakArrIdx = k;
                     bodyBreaksCount++;
                    }
                 }

               if(breakArrIdx >= 0 && bodyBreaksCount <= MathMax(1, cfg.maxQMBodyBreak) * 5)
                 {
                  SMSNRLevel qm;
                  qm.Reset();
                  qm.tfIdx             = tfIdx;
                  qm.type              = POI_QM_BULL;
                  qm.direction         = BIAS_BULL;
                  qm.price             = s1_LS.price; // QM level = Left Shoulder body price!
                  qm.wickExtreme       = MathMin(s1_LS.price, s1_LS.candleLow);
                  qm.tolerance         = tol;
                  qm.zoneLow           = MathMin(qm.price, qm.wickExtreme) - tol;
                  qm.zoneHigh          = qm.price + tol;
                  qm.pivotTime         = s1_LS.pivotTime;
                  qm.activeFromTime    = rates[breakArrIdx].time;
                  qm.pivotClosedShift  = s1_LS.pivotClosedShift;
                  qm.activeClosedShift = breakArrIdx + 1;
                  qm.status            = POI_STATUS_FRESH;
                  qm.qmHeadPrice       = s3_Head.price;
                  qm.qmHeadTime        = s3_Head.pivotTime;
                  qm.id                = StringFormat("%s_QMBULL_%I64d",
                                                      QTTfIndexToString(tfIdx),
                                                      (long)s1_LS.pivotTime);

                  bool qmBroken = false;
                  for(int j = breakArrIdx - 1; j >= 0; j--)
                    {
                     if(rates[j].close < MathMin(s3_Head.price, s3_Head.candleLow) || rates[j].close < qm.zoneLow)
                       {
                        qmBroken = true;
                        break;
                       }
                     if(rates[j].low <= qm.zoneHigh && qm.status == POI_STATUS_FRESH)
                       {
                        qm.status           = POI_STATUS_USED;
                        qm.firstTouchTime   = rates[j].time;
                        qm.touchClosedShift = j + 1;
                       }
                    }

                  if(!qmBroken)
                     AddLevelToList(rawList, rawCount, qm);
                 }
              }

            // 2B. Bearish QM: High(LS) -> Low(Int) -> Higher High(Head > LS) -> Lower Low(Bos < Int)
            if(s1_LS.type   == SWING_HIGH &&
               s2_Int.type  == SWING_LOW  &&
               s3_Head.type == SWING_HIGH && s3_Head.price > s1_LS.price &&
               s4_Bos.type  == SWING_LOW  && s4_Bos.price  < s2_Int.price)
              {
               int headIdx = s3_Head.pivotClosedShift - 1;
               int bosIdx  = s4_Bos.pivotClosedShift - 1;
               int breakArrIdx = -1;
               int bodyBreaksCount = 0;

               for(int k = headIdx - 1; k >= bosIdx && k >= 0; k--)
                 {
                  if(rates[k].close < s2_Int.price)
                    {
                     if(breakArrIdx < 0)
                        breakArrIdx = k;
                     bodyBreaksCount++;
                    }
                 }

               if(breakArrIdx >= 0 && bodyBreaksCount <= MathMax(1, cfg.maxQMBodyBreak) * 5)
                 {
                  SMSNRLevel qm;
                  qm.Reset();
                  qm.tfIdx             = tfIdx;
                  qm.type              = POI_QM_BEAR;
                  qm.direction         = BIAS_BEAR;
                  qm.price             = s1_LS.price; // QM level = Left Shoulder body price!
                  qm.wickExtreme       = MathMax(s1_LS.price, s1_LS.candleHigh);
                  qm.tolerance         = tol;
                  qm.zoneLow           = qm.price - tol;
                  qm.zoneHigh          = MathMax(qm.price, qm.wickExtreme) + tol;
                  qm.pivotTime         = s1_LS.pivotTime;
                  qm.activeFromTime    = rates[breakArrIdx].time;
                  qm.pivotClosedShift  = s1_LS.pivotClosedShift;
                  qm.activeClosedShift = breakArrIdx + 1;
                  qm.status            = POI_STATUS_FRESH;
                  qm.qmHeadPrice       = s3_Head.price;
                  qm.qmHeadTime        = s3_Head.pivotTime;
                  qm.id                = StringFormat("%s_QMBEAR_%I64d",
                                                      QTTfIndexToString(tfIdx),
                                                      (long)s1_LS.pivotTime);

                  bool qmBroken = false;
                  for(int j = breakArrIdx - 1; j >= 0; j--)
                    {
                     if(rates[j].close > MathMax(s3_Head.price, s3_Head.candleHigh) || rates[j].close > qm.zoneHigh)
                       {
                        qmBroken = true;
                        break;
                       }
                     if(rates[j].high >= qm.zoneLow && qm.status == POI_STATUS_FRESH)
                       {
                        qm.status           = POI_STATUS_USED;
                        qm.firstTouchTime   = rates[j].time;
                        qm.touchClosedShift = j + 1;
                       }
                    }

                  if(!qmBroken)
                     AddLevelToList(rawList, rawCount, qm);
                 }
              }
           }
        }

      //----------------------------------------------------------------
      // PART 3: Filter & Cap to Max 20 Nearest Active Levels to Price
      //----------------------------------------------------------------
      double refPrice = rates[0].close;

      // Prioritize levels that are Fresh (or just touched on latest closed bars)
      // Sort by distance to current price (ascending)
      for(int a = 0; a < rawCount - 1; a++)
        {
         for(int b = a + 1; b < rawCount; b++)
           {
            bool aFresh = rawList[a].IsFreshForEntry(3);
            bool bFresh = rawList[b].IsFreshForEntry(3);
            double distA = MathAbs(rawList[a].price - refPrice);
            double distB = MathAbs(rawList[b].price - refPrice);

            if((!aFresh && bFresh) || (aFresh == bFresh && distB < distA))
              {
               SMSNRLevel tmp = rawList[a];
               rawList[a]     = rawList[b];
               rawList[b]     = tmp;
              }
           }
        }

      int cap = MathMin(rawCount, MathMax(1, cfg.maxActiveLevelsPerTF));
      ArrayResize(outLevels, cap);
      for(int i = 0; i < cap; i++)
         outLevels[i] = rawList[i];
      outCount = cap;
     }

   //+------------------------------------------------------------------+
   //| Update All Enabled Timeframes when a New Bar Closes              |
   //+------------------------------------------------------------------+
   void              Update(CMTFDataManager &mtf,
                            CSwingEngine &swings,
                            const double currentSpreadPrice,
                            const bool forceAll = false)
     {
      for(int tfIdx = 0; tfIdx < QT_MTF_COUNT; tfIdx++)
        {
         if(!m_cfg.enableTF[tfIdx] || !mtf.IsTFReady(tfIdx))
            continue;
         if(!forceAll && !mtf.IsNewBar(tfIdx) && m_store[tfIdx].count > 0)
            continue;

         MqlRates rates[];
         int rCount = mtf.GetClosedRatesArray(tfIdx, rates);

         int bCount = swings.GetBodySwingCount(tfIdx);
         SSwingPoint bSwings[];
         ArrayResize(bSwings, bCount);
         for(int i = 0; i < bCount; i++)
            swings.GetBodySwing(tfIdx, i, bSwings[i]);

         BuildLevelsForTF(rates,
                          rCount,
                          bSwings,
                          bCount,
                          tfIdx,
                          mtf.GetATR(tfIdx),
                          currentSpreadPrice,
                          m_cfg,
                          m_store[tfIdx].levels,
                          m_store[tfIdx].count);

         // Re-apply consumed trade flags
         for(int i = 0; i < m_store[tfIdx].count; i++)
           {
            if(IsConsumedId(m_store[tfIdx].levels[i].id))
              {
               m_store[tfIdx].levels[i].usedByTrade = true;
               m_store[tfIdx].levels[i].status      = POI_STATUS_USED;
              }
           }
        }
     }

   //--- Accessors
   int               GetLevelCount(const int tfIdx) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return 0;
      return m_store[tfIdx].count;
     }

   bool              GetLevel(const int tfIdx, const int idx, SMSNRLevel &outLvl) const
     {
      if(tfIdx < 0 || tfIdx >= QT_MTF_COUNT) return false;
      if(idx < 0 || idx >= m_store[tfIdx].count) return false;
      outLvl = m_store[tfIdx].levels[idx];
      return true;
     }

   //--- Count how many OTHER timeframes have a fresh POI overlapping [price - tol, price + tol]
   int               CountMultiTFOverlaps(const SMSNRLevel &targetLvl) const
     {
      int overlaps = 0;
      for(int tf = 0; tf < QT_MTF_COUNT; tf++)
        {
         if(tf == targetLvl.tfIdx)
            continue;
         for(int i = 0; i < m_store[tf].count; i++)
           {
            SMSNRLevel other = m_store[tf].levels[i];
            if(other.direction != targetLvl.direction || !other.IsFreshForEntry(2))
               continue;
            // Check if zones overlap
            if(targetLvl.zoneLow <= other.zoneHigh && targetLvl.zoneHigh >= other.zoneLow)
              {
               overlaps++;
               break; // Max +1 per TF
              }
           }
        }
      return overlaps;
     }
  };

#endif // QT_MSNR_LEVELS_MQH
//+------------------------------------------------------------------+
