//+------------------------------------------------------------------+
//| Exec.mqh                                                         |
//| M8 & M12 - Order Execution, Trade Management & Friday Flat       |
//| Place in: MQL5/Include/QT/Exec.mqh                               |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Execute Limit / Market orders via native OrderSend wrapper    |
//|    with auto-detected filling mode (FOK / IOC / RETURN) & retry  |
//|  - Recover active positions & pending orders on OnInit restart   |
//|  - Manage open positions:                                        |
//|    * Real-time MFE (Max Favorable Excursion) & MAE tracking      |
//|    * Break-Even (BE) at +1R (optional)                           |
//|    * Partial Close (50%) at TP1 internal liquidity (optional)    |
//|    * Time Stop per Trade Profile (end of 90m block for Scalping; |
//|      end of NY PM / 17:55 NY for Intraday)                       |
//|  - Reconcile closed positions via HistorySelectByPosition &      |
//|    write full row to QT_Forward_Journal.csv                      |
//|  - M12 Friday Forced Flat:                                       |
//|    * Checked every second in OnTimer (and OnTick)                |
//|    * Effective cutoff = earlier of FridayCloseNY (default 15:00) |
//|      and 60 minutes before broker symbol session close           |
//|    * Closes all positions (profit or loss) & cancels pendings    |
//+------------------------------------------------------------------+
#ifndef QT_EXEC_MQH
#define QT_EXEC_MQH

#include "Risk.mqh"
#include "Setup.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Self-Contained Native MQL5 Order Executor                        |
//| Eliminates external <Trade/Trade.mqh> dependency while using     |
//| standard MQL5 MqlTradeRequest / MqlTradeResult / OrderSend       |
//+------------------------------------------------------------------+
class CQTTradeExecutor
  {
private:
   long                    m_magic;
   ulong                   m_deviationPts;
   ENUM_ORDER_TYPE_FILLING m_fillingMode;
   bool                    m_asyncMode;
   MqlTradeResult          m_lastResult;

public:
                     CQTTradeExecutor()
     {
      m_magic        = 20261001;
      m_deviationPts = 20;
      m_fillingMode  = ORDER_FILLING_FOK;
      m_asyncMode    = false;
      ZeroMemory(m_lastResult);
     }

   void              SetExpertMagicNumber(const long magic)                 { m_magic = magic; }
   void              SetDeviationInPoints(const ulong dev)                  { m_deviationPts = dev; }
   void              SetTypeFilling(const ENUM_ORDER_TYPE_FILLING filling)  { m_fillingMode = filling; }
   void              SetAsyncMode(const bool async)                         { m_asyncMode = async; }

   uint              ResultRetcode() const { return m_lastResult.retcode; }
   ulong             ResultOrder()   const { return m_lastResult.order; }
   ulong             ResultDeal()    const { return m_lastResult.deal; }
   double            ResultPrice()   const { return m_lastResult.price; }

   bool              Buy(const double volume,
                         const string symbol,
                         const double price,
                         const double sl,
                         const double tp,
                         const string comment = "")
     {
      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_BUY;
      req.price        = (price > 0.0 ? price : SymbolInfoDouble(symbol, SYMBOL_ASK));
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviationPts;
      req.magic        = m_magic;
      req.comment      = comment;
      req.type_filling = m_fillingMode;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && (m_lastResult.retcode == TRADE_RETCODE_DONE ||
                     m_lastResult.retcode == TRADE_RETCODE_DONE_PARTIAL ||
                     m_lastResult.retcode == TRADE_RETCODE_PLACED));
     }

   bool              Sell(const double volume,
                          const string symbol,
                          const double price,
                          const double sl,
                          const double tp,
                          const string comment = "")
     {
      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action       = TRADE_ACTION_DEAL;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_SELL;
      req.price        = (price > 0.0 ? price : SymbolInfoDouble(symbol, SYMBOL_BID));
      req.sl           = sl;
      req.tp           = tp;
      req.deviation    = m_deviationPts;
      req.magic        = m_magic;
      req.comment      = comment;
      req.type_filling = m_fillingMode;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && (m_lastResult.retcode == TRADE_RETCODE_DONE ||
                     m_lastResult.retcode == TRADE_RETCODE_DONE_PARTIAL ||
                     m_lastResult.retcode == TRADE_RETCODE_PLACED));
     }

   bool              BuyLimit(const double volume,
                              const double price,
                              const string symbol,
                              const double sl,
                              const double tp,
                              const ENUM_ORDER_TYPE_TIME typeTime = ORDER_TIME_GTC,
                              const datetime expiration = 0,
                              const string comment = "")
     {
      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_BUY_LIMIT;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.magic        = m_magic;
      req.comment      = comment;
      req.type_filling = m_fillingMode;
      req.type_time    = typeTime;
      req.expiration   = expiration;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && (m_lastResult.retcode == TRADE_RETCODE_DONE ||
                     m_lastResult.retcode == TRADE_RETCODE_PLACED));
     }

   bool              SellLimit(const double volume,
                               const double price,
                               const string symbol,
                               const double sl,
                               const double tp,
                               const ENUM_ORDER_TYPE_TIME typeTime = ORDER_TIME_GTC,
                               const datetime expiration = 0,
                               const string comment = "")
     {
      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = ORDER_TYPE_SELL_LIMIT;
      req.price        = price;
      req.sl           = sl;
      req.tp           = tp;
      req.magic        = m_magic;
      req.comment      = comment;
      req.type_filling = m_fillingMode;
      req.type_time    = typeTime;
      req.expiration   = expiration;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && (m_lastResult.retcode == TRADE_RETCODE_DONE ||
                     m_lastResult.retcode == TRADE_RETCODE_PLACED));
     }

   bool              OrderDelete(const ulong orderTicket)
     {
      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action = TRADE_ACTION_REMOVE;
      req.order  = orderTicket;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && m_lastResult.retcode == TRADE_RETCODE_DONE);
     }

   bool              PositionModify(const ulong posTicket, const double sl, const double tp)
     {
      if(!PositionSelectByTicket(posTicket))
         return false;

      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action   = TRADE_ACTION_SLTP;
      req.position = posTicket;
      req.symbol   = PositionGetString(POSITION_SYMBOL);
      req.sl       = sl;
      req.tp       = tp;
      req.magic    = m_magic;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && m_lastResult.retcode == TRADE_RETCODE_DONE);
     }

   bool              PositionClose(const ulong posTicket, const ulong deviationPts = 20)
     {
      if(!PositionSelectByTicket(posTicket))
         return false;

      string sym     = PositionGetString(POSITION_SYMBOL);
      double vol     = PositionGetDouble(POSITION_VOLUME);
      long   posType = PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action       = TRADE_ACTION_DEAL;
      req.position     = posTicket;
      req.symbol       = sym;
      req.volume       = vol;
      req.type         = (posType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      req.price        = (posType == POSITION_TYPE_BUY ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                       : SymbolInfoDouble(sym, SYMBOL_ASK));
      req.deviation    = deviationPts;
      req.magic        = m_magic;
      req.type_filling = m_fillingMode;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && (m_lastResult.retcode == TRADE_RETCODE_DONE ||
                     m_lastResult.retcode == TRADE_RETCODE_DONE_PARTIAL));
     }

   bool              PositionClosePartial(const ulong posTicket, const double volumeToClose, const ulong deviationPts = 20)
     {
      if(!PositionSelectByTicket(posTicket))
         return false;

      string sym     = PositionGetString(POSITION_SYMBOL);
      long   posType = PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest req;
      ZeroMemory(req);
      ZeroMemory(m_lastResult);

      req.action       = TRADE_ACTION_DEAL;
      req.position     = posTicket;
      req.symbol       = sym;
      req.volume       = volumeToClose;
      req.type         = (posType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      req.price        = (posType == POSITION_TYPE_BUY ? SymbolInfoDouble(sym, SYMBOL_BID)
                                                       : SymbolInfoDouble(sym, SYMBOL_ASK));
      req.deviation    = deviationPts;
      req.magic        = m_magic;
      req.type_filling = m_fillingMode;

      bool ok = OrderSend(req, m_lastResult);
      return (ok && (m_lastResult.retcode == TRADE_RETCODE_DONE ||
                     m_lastResult.retcode == TRADE_RETCODE_DONE_PARTIAL));
     }
  };

//+------------------------------------------------------------------+
//| Execution Configuration                                          |
//+------------------------------------------------------------------+
struct SExecConfig
  {
   long   magicNumber;
   int    slippagePoints;
   int    maxRetries;
   bool   useBreakEvenAt1R;
   double breakEvenPips;          // Default 65.0 pips ($6.50 on XAUUSD) for Stage-1 Break-Even protection
   double breakEvenBufferPoints;
   bool   usePartialCloseTP1;
   double partialCloseRatio;      // Default 0.50 (50%)
   double partialTp1Pips;         // Default 100.0 pips ($10.00 on XAUUSD) for Stage-2 50% Partial Close (TP1)
   bool   useTimeStop;            // Enforce profile duration limit
   bool   closeOrBeBeforeNews;    // Optional: move to BE before news window (default false)

   void SetDefaults()
     {
      magicNumber           = 20261001;
      slippagePoints        = 20;
      maxRetries            = 3;
      useBreakEvenAt1R      = true;
      breakEvenPips         = 65.0;
      breakEvenBufferPoints = 5.0;
      usePartialCloseTP1    = true;
      partialCloseRatio     = 0.50;
      partialTp1Pips        = 100.0;
      useTimeStop           = true;
      closeOrBeBeforeNews   = false;
     }
  };

//+------------------------------------------------------------------+
//| Active Position Tracker with Full Forward-Test Telemetry         |
//+------------------------------------------------------------------+
struct SManagedTrade
  {
   bool                 active;
   ulong                positionTicket;
   ulong                positionId;
   string               setupId;
   ENUM_BIAS_DIR        direction;
   bool                 wasMarketOrder;

   datetime             openServerTime;
   datetime             openNyTime;
   string               openDayeDate;
   string               openDayeDow;
   ENUM_QT_QUARTER      openYearQ;
   ENUM_QT_QUARTER      openMonthQ;
   ENUM_QT_QUARTER      openWeekQ;
   ENUM_QT_QUARTER      openDayQ;
   ENUM_QT_SESSION      openSession;
   ENUM_QT_QUARTER      openQ90;

   datetime             openedTimeNY;
   datetime             openedBlock90EndNY;
   datetime             openedDayeEndNY;

   int                  barsToFillM5;
   int                  spreadAtEntryPts;
   double               slippagePts;
   double               initialLots;
   double               plannedEntryPrice;
   double               entryPrice;
   double               initialSL;
   double               currentSL;
   double               tp1Price;
   double               finalTP;
   double               plannedRR;
   double               initialRiskUsd;

   double               mfePrice;
   double               mfeR;
   double               maePrice;
   double               maeR;
   bool                 beApplied;
   bool                 partialDone;
   double               atrM5AtEntry;
   double               atrH1AtEntry;

   ENUM_BIAS_DIR        biasW1;
   ENUM_BIAS_DIR        biasD1;
   ENUM_BIAS_DIR        biasH4;
   string               poiSummary;
   string               refinedPoiSummary;
   string               sweepPoolSummary;
   string               fvgTfSummary;
   string               dolLabel;
   int                  confluenceScore;
   SConfluenceBreakdown score;
   string               lastCloseReason;

   void Reset()
     {
      active             = false;
      positionTicket     = 0;
      positionId         = 0;
      setupId            = "";
      direction          = BIAS_NEUTRAL;
      wasMarketOrder     = false;
      openServerTime     = 0;
      openNyTime         = 0;
      openDayeDate       = "";
      openDayeDow        = "";
      openYearQ          = QT_Q1;
      openMonthQ         = QT_Q1;
      openWeekQ          = QT_Q1;
      openDayQ           = QT_Q1;
      openSession        = QT_SESSION_ASIA;
      openQ90            = QT_Q1;
      openedTimeNY       = 0;
      openedBlock90EndNY = 0;
      openedDayeEndNY    = 0;
      barsToFillM5       = 0;
      spreadAtEntryPts   = 0;
      slippagePts        = 0.0;
      initialLots        = 0.0;
      plannedEntryPrice  = 0.0;
      entryPrice         = 0.0;
      initialSL          = 0.0;
      currentSL          = 0.0;
      tp1Price           = 0.0;
      finalTP            = 0.0;
      plannedRR          = 0.0;
      initialRiskUsd     = 0.0;
      mfePrice           = 0.0;
      mfeR               = 0.0;
      maePrice           = 0.0;
      maeR               = 0.0;
      beApplied          = false;
      partialDone        = false;
      atrM5AtEntry       = 0.0;
      atrH1AtEntry       = 0.0;
      biasW1             = BIAS_NEUTRAL;
      biasD1             = BIAS_NEUTRAL;
      biasH4             = BIAS_NEUTRAL;
      poiSummary         = "";
      refinedPoiSummary  = "NONE";
      sweepPoolSummary   = "";
      fvgTfSummary       = "NONE";
      dolLabel           = "";
      confluenceScore    = 0;
      score.Reset();
      lastCloseReason    = "";
     }
  };

//+------------------------------------------------------------------+
//| CExecutionEngine Class                                           |
//+------------------------------------------------------------------+
class CExecutionEngine
  {
private:
   string            m_symbol;
   SExecConfig       m_cfg;
   CQTTradeExecutor  m_trade;
   SManagedTrade     m_managed[10];
   int               m_managedCount;
   SSetupTracker     m_lastArmedBuy;
   SSetupTracker     m_lastArmedSell;

   //--- Detect supported filling mode for symbol
   static ENUM_ORDER_TYPE_FILLING DetectFillingMode(const string symbol)
     {
      uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) != 0)
         return ORDER_FILLING_FOK;
      if((filling & SYMBOL_FILLING_IOC) != 0)
         return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
     }

   int               FindManagedIndex(const ulong posTicket) const
     {
      for(int i = 0; i < m_managedCount; i++)
         if(m_managed[i].active && m_managed[i].positionTicket == posTicket)
            return i;
      return -1;
     }

   void              RegisterManagedPosition(const ulong posTicket,
                                             const SSetupTracker &tr,
                                             const double lots,
                                             const double actualEntryPrice,
                                             const double initialRiskMoney,
                                             const QTState &qtState,
                                             const SBiasState &biasState,
                                             const double atrM5,
                                             const double atrH1)
     {
      int slot = FindManagedIndex(posTicket);
      if(slot < 0)
        {
         for(int i = 0; i < 10; i++)
           {
            if(!m_managed[i].active)
              {
               slot = i;
               if(slot >= m_managedCount)
                  m_managedCount = slot + 1;
               break;
              }
           }
        }
      if(slot < 0)
         slot = 0;

      ulong posId = posTicket;
      if(PositionSelectByTicket(posTicket))
        {
         ulong pid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(pid > 0)
            posId = pid;
        }

      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double plannedE = (tr.entryPrice > 0.0 ? tr.entryPrice : actualEntryPrice);
      double fillE    = (actualEntryPrice > 0.0 ? actualEntryPrice : plannedE);
      double slipPts  = 0.0;
      if(point > 0.0 && plannedE > 0.0 && fillE > 0.0)
        {
         slipPts = (tr.direction == BIAS_BULL ? (fillE - plannedE) / point
                                              : (plannedE - fillE) / point);
        }

      int barsWait = 0;
      if(tr.armedTime > 0 && qtState.serverTime > tr.armedTime)
         barsWait = (int)((qtState.serverTime - tr.armedTime) / 300);

      m_managed[slot].Reset();
      m_managed[slot].active             = true;
      m_managed[slot].positionTicket     = posTicket;
      m_managed[slot].positionId         = posId;
      m_managed[slot].setupId            = (StringLen(tr.setupId) > 0 ? tr.setupId : StringFormat("REC_%I64u", posTicket));
      m_managed[slot].direction          = tr.direction;
      m_managed[slot].wasMarketOrder     = tr.isMarketOrder;

      m_managed[slot].openServerTime     = qtState.serverTime;
      m_managed[slot].openNyTime         = qtState.nyTime;
      m_managed[slot].openDayeDate       = StringFormat("%04d-%02d-%02d", qtState.dayeYear, qtState.dayeMonth, qtState.dayeDay);
      m_managed[slot].openDayeDow        = QTDayOfWeekToString(qtState.dayeDayOfWeek);
      m_managed[slot].openYearQ          = qtState.yearQ;
      m_managed[slot].openMonthQ         = qtState.monthQ;
      m_managed[slot].openWeekQ          = qtState.weekQ;
      m_managed[slot].openDayQ           = qtState.dayQ;
      m_managed[slot].openSession        = qtState.session;
      m_managed[slot].openQ90            = qtState.q90;

      m_managed[slot].openedTimeNY       = qtState.nyTime;
      m_managed[slot].openedBlock90EndNY = qtState.block90EndNY;
      m_managed[slot].openedDayeEndNY    = (datetime)((long)qtState.dayeDayStartNY + 24 * 3600);

      m_managed[slot].barsToFillM5       = barsWait;
      m_managed[slot].spreadAtEntryPts   = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      m_managed[slot].slippagePts        = slipPts;
      m_managed[slot].initialLots        = lots;
      m_managed[slot].plannedEntryPrice  = plannedE;
      m_managed[slot].entryPrice         = fillE;
      m_managed[slot].initialSL          = tr.slPrice;
      m_managed[slot].currentSL          = tr.slPrice;

      // Anchor TP1 strictly at +100 pips (m_cfg.partialTp1Pips) from actual fill price
      double tp1DistPrice                = QTPipsToPrice(m_symbol, (m_cfg.partialTp1Pips > 0.0 ? m_cfg.partialTp1Pips : 100.0));
      m_managed[slot].tp1Price           = (tr.direction == BIAS_BULL ? fillE + tp1DistPrice : fillE - tp1DistPrice);
      m_managed[slot].finalTP            = tr.tpPrice;
      m_managed[slot].plannedRR          = tr.rrRatio;
      m_managed[slot].initialRiskUsd     = initialRiskMoney;

      m_managed[slot].mfePrice           = fillE;
      m_managed[slot].mfeR               = 0.0;
      m_managed[slot].maePrice           = fillE;
      m_managed[slot].maeR               = 0.0;
      m_managed[slot].atrM5AtEntry       = atrM5;
      m_managed[slot].atrH1AtEntry       = atrH1;

      m_managed[slot].biasW1             = biasState.biasW1;
      m_managed[slot].biasD1             = biasState.biasD1;
      m_managed[slot].biasH4             = biasState.biasH4;
      m_managed[slot].poiSummary         = QTTfIndexToString(tr.anchorPOI.tfIdx) + "_" + QTPOITypeToString(tr.anchorPOI.type);
      m_managed[slot].refinedPoiSummary  = (tr.hasRefinedPOI ? QTTfIndexToString(tr.refinedPOI.tfIdx) + "_" + QTPOITypeToString(tr.refinedPOI.type) : "NONE");
      m_managed[slot].sweepPoolSummary   = QTLiqPoolTypeToString(tr.sweep.poolType);
      m_managed[slot].fvgTfSummary       = (tr.hasFvg ? QTTfIndexToString(tr.fvg.tfIdx) : "NONE");
      m_managed[slot].dolLabel           = (StringLen(tr.dolLabel) > 0 ? tr.dolLabel : "DOL");
      m_managed[slot].confluenceScore    = tr.score.totalScore;
      m_managed[slot].score              = tr.score;
     }

   //+------------------------------------------------------------------+
   //| Reconcile Closed Position History & Write Master Journal Row     |
   //+------------------------------------------------------------------+
   void              FinalizeAndJournalClosedPosition(SManagedTrade &mt,
                                                      CQTTimeEngine &timeEngine,
                                                      const QTState &qtState,
                                                      const ENUM_TRADE_PROFILE profile,
                                                      const CQTLogger &logger)
     {
      if(!mt.active)
         return;

      ulong posId = (mt.positionId > 0 ? mt.positionId : mt.positionTicket);
      bool histOk = HistorySelectByPosition(posId);
      if(!histOk)
         histOk = HistorySelect(mt.openServerTime - 300, qtState.serverTime + 300);

      double totalGrossProfit = 0.0;
      double totalSwap        = 0.0;
      double totalCommission  = 0.0;
      double outVolSum        = 0.0;
      double outPriceWeighted = 0.0;
      datetime lastOutTimeSrv = qtState.serverTime;
      long lastDealReason     = -1;

      if(histOk)
        {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
           {
            ulong dTicket = HistoryDealGetTicket(i);
            if(dTicket == 0)
               continue;
            ulong dPosId = (ulong)HistoryDealGetInteger(dTicket, DEAL_POSITION_ID);
            if(dPosId != posId && dPosId != mt.positionTicket)
               continue;

            long dEntry      = HistoryDealGetInteger(dTicket, DEAL_ENTRY);
            double dProfit   = HistoryDealGetDouble(dTicket, DEAL_PROFIT);
            double dSwap     = HistoryDealGetDouble(dTicket, DEAL_SWAP);
            double dComm     = HistoryDealGetDouble(dTicket, DEAL_COMMISSION);
            double dVol      = HistoryDealGetDouble(dTicket, DEAL_VOLUME);
            double dPrice    = HistoryDealGetDouble(dTicket, DEAL_PRICE);
            datetime dTime   = (datetime)HistoryDealGetInteger(dTicket, DEAL_TIME);

            totalCommission += dComm;
            if(dEntry == DEAL_ENTRY_OUT || dEntry == DEAL_ENTRY_INOUT)
              {
               totalGrossProfit += dProfit;
               totalSwap        += dSwap;
               outVolSum        += dVol;
               outPriceWeighted += dPrice * dVol;
               if(dTime >= lastOutTimeSrv || lastOutTimeSrv == 0)
                  lastOutTimeSrv = dTime;
               lastDealReason = HistoryDealGetInteger(dTicket, DEAL_REASON);
              }
           }
        }

      double avgExitPrice = (outVolSum > 0.0 ? outPriceWeighted / outVolSum : mt.entryPrice);
      double netProfitUsd = totalGrossProfit + totalSwap + totalCommission;

      double riskDist = MathAbs(mt.entryPrice - mt.initialSL);
      double realizedR = 0.0;
      if(mt.initialRiskUsd > 1e-5)
         realizedR = netProfitUsd / mt.initialRiskUsd;
      else if(riskDist > 1e-5)
         realizedR = (mt.direction == BIAS_BULL ? (avgExitPrice - mt.entryPrice) / riskDist
                                                : (mt.entryPrice - avgExitPrice) / riskDist);

      // Classify exact exit outcome
      string outcome = "MANUAL_OR_OTHER";
      if(mt.lastCloseReason == "FRIDAY_FLAT")
         outcome = "FRIDAY_FLAT";
      else if(StringFind(mt.lastCloseReason, "TIME_STOP") == 0)
         outcome = "TIME_STOP";
      else if(lastDealReason == DEAL_REASON_TP ||
              (mt.finalTP > 0.0 && MathAbs(avgExitPrice - mt.finalTP) <= riskDist * 0.15))
        {
         outcome = (mt.partialDone ? "TP1_THEN_TP" : "TP_FULL");
        }
      else if(lastDealReason == DEAL_REASON_SL ||
              (mt.currentSL > 0.0 && MathAbs(avgExitPrice - mt.currentSL) <= riskDist * 0.20))
        {
         if(mt.beApplied)
            outcome = (mt.partialDone ? "TP1_THEN_BE" : "BE_HIT");
         else
            outcome = "SL_HIT";
        }
      else if(realizedR >= 0.8)
         outcome = (mt.partialDone ? "TP1_THEN_TP" : "TP_FULL");
      else if(realizedR <= -0.5)
         outcome = "SL_HIT";
      else if(mt.beApplied)
         outcome = (mt.partialDone ? "TP1_THEN_BE" : "BE_HIT");

      // Populate SClosedTradeJournal
      SClosedTradeJournal j;
      j.Reset();
      j.positionId          = posId;
      j.setupId             = mt.setupId;
      j.symbol              = m_symbol;
      j.profile             = profile;
      j.direction           = mt.direction;
      j.wasMarketOrder      = mt.wasMarketOrder;

      j.openServerTime      = mt.openServerTime;
      j.openNyTime          = mt.openNyTime;
      j.closeServerTime     = lastOutTimeSrv;
      j.closeNyTime         = timeEngine.ServerToNY(lastOutTimeSrv);
      j.holdDurationMin     = (int)MathMax(0, (long)(j.closeServerTime - j.openServerTime) / 60);
      j.openDayeDate        = mt.openDayeDate;
      j.openDayeDow         = mt.openDayeDow;

      j.openYearQ           = mt.openYearQ;
      j.openMonthQ          = mt.openMonthQ;
      j.openWeekQ           = mt.openWeekQ;
      j.openDayQ            = mt.openDayQ;
      j.openSession         = mt.openSession;
      j.openQ90             = mt.openQ90;
      j.closeSession        = qtState.session;
      j.closeQ90            = qtState.q90;

      j.barsToFillM5        = mt.barsToFillM5;
      j.spreadAtEntryPts    = mt.spreadAtEntryPts;
      j.slippagePts         = mt.slippagePts;
      j.initialLots         = mt.initialLots;
      j.plannedEntryPrice   = mt.plannedEntryPrice;
      j.actualEntryPrice    = mt.entryPrice;
      j.initialSlPrice      = mt.initialSL;
      j.finalSlPrice        = mt.currentSL;
      j.tp1Price            = mt.tp1Price;
      j.finalTpPrice        = mt.finalTP;
      j.exitPrice           = avgExitPrice;
      j.plannedRR           = mt.plannedRR;

      j.exitOutcome         = outcome;
      j.initialRiskUsd      = mt.initialRiskUsd;
      j.grossProfitUsd      = totalGrossProfit;
      j.swapUsd             = totalSwap;
      j.commissionUsd       = totalCommission;
      j.netProfitUsd        = netProfitUsd;
      j.realizedR           = realizedR;
      j.balanceAfter        = AccountInfoDouble(ACCOUNT_BALANCE);

      j.mfePrice            = mt.mfePrice;
      j.mfeR                = mt.mfeR;
      j.maePrice            = mt.maePrice;
      j.maeR                = mt.maeR;
      j.beTriggered         = mt.beApplied;
      j.partialTp1Triggered = mt.partialDone;
      j.atrM5AtEntry        = mt.atrM5AtEntry;
      j.atrH1AtEntry        = mt.atrH1AtEntry;

      j.biasW1              = mt.biasW1;
      j.biasD1              = mt.biasD1;
      j.biasH4              = mt.biasH4;
      j.anchorPoiSummary    = mt.poiSummary;
      j.refinedPoiSummary   = mt.refinedPoiSummary;
      j.sweepPoolSummary    = mt.sweepPoolSummary;
      j.fvgTfSummary        = mt.fvgTfSummary;
      j.dolLabel            = mt.dolLabel;
      j.score               = mt.score;

      logger.LogTradeEvent("POSITION_CLOSED", mt.setupId, posId, mt.direction, mt.initialLots,
                           mt.entryPrice, mt.currentSL, mt.finalTP, avgExitPrice,
                           netProfitUsd, realizedR, mt.confluenceScore, mt.poiSummary,
                           outcome, qtState, profile);
      logger.LogClosedTradeJournal(j);

      mt.Reset();
     }

public:
                     CExecutionEngine()
     {
      m_symbol       = QT_TARGET_SYMBOL;
      m_managedCount = 0;
      m_cfg.SetDefaults();
      m_lastArmedBuy.Reset(BIAS_BULL);
      m_lastArmedSell.Reset(BIAS_BEAR);
      for(int i = 0; i < 10; i++)
         m_managed[i].Reset();
     }

   void              Init(const string symbol, const SExecConfig &cfg)
     {
      m_symbol = (StringLen(symbol) > 0 ? symbol : _Symbol);
      m_cfg    = cfg;

      m_trade.SetExpertMagicNumber(m_cfg.magicNumber);
      m_trade.SetDeviationInPoints((ulong)MathMax(0, m_cfg.slippagePoints));
      m_trade.SetTypeFilling(DetectFillingMode(m_symbol));
      m_trade.SetAsyncMode(false);

      m_managedCount = 0;
      m_lastArmedBuy.Reset(BIAS_BULL);
      m_lastArmedSell.Reset(BIAS_BEAR);
      for(int i = 0; i < 10; i++)
         m_managed[i].Reset();
     }

   SExecConfig       GetConfig() const { return m_cfg; }

   //+------------------------------------------------------------------+
   //| OnInit State Recovery: Rebuild state from existing positions     |
   //| and pending orders matching MagicNumber                          |
   //+------------------------------------------------------------------+
   void              RecoverStateOnInit(const QTState &qtState,
                                        const SBiasState &biasState,
                                        CRiskManager &riskMgr,
                                        CSetupEngine &setupEngine,
                                        CMSNREngine &msnr,
                                        const double atrM5 = 0.0,
                                        const double atrH1 = 0.0)
     {
      int posTotal = PositionsTotal();
      for(int i = 0; i < posTotal; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.magicNumber)
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;

         long posType      = PositionGetInteger(POSITION_TYPE);
         ENUM_BIAS_DIR dir = (posType == POSITION_TYPE_BUY ? BIAS_BULL : BIAS_BEAR);
         double lots       = PositionGetDouble(POSITION_VOLUME);
         double openP      = PositionGetDouble(POSITION_PRICE_OPEN);
         double slP        = PositionGetDouble(POSITION_SL);
         double tpP        = PositionGetDouble(POSITION_TP);
         string comment    = PositionGetString(POSITION_COMMENT);

         SSetupTracker dummy;
         dummy.Reset(dir);
         dummy.setupId    = (StringLen(comment) > 0 ? comment : StringFormat("REC_%I64u", ticket));
         dummy.entryPrice = openP;
         dummy.slPrice    = slP;
         dummy.tpPrice    = tpP;
         dummy.tp1Price   = (dir == BIAS_BULL ? openP + MathAbs(openP - slP) : openP - MathAbs(openP - slP));
         double slDist    = MathAbs(openP - slP);
         dummy.rrRatio    = (slDist > 1e-5 ? MathAbs(tpP - openP) / slDist : 0.0);

         double riskUsd = riskMgr.CalcRiskMoneyForVolume(dir, lots, openP, slP);
         RegisterManagedPosition(ticket, dummy, lots, openP, riskUsd, qtState, biasState, atrM5, atrH1);
         setupEngine.NotifyTradeFilled(dir, ticket, msnr);
         PrintFormat("[Exec] Recovered open position #%I64u (%s %.2f lots @ %.2f)",
                     ticket, QTBiasToString(dir), lots, openP);
        }

      int ordTotal = OrdersTotal();
      for(int i = 0; i < ordTotal; i++)
        {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0)
            continue;
         if(OrderGetInteger(ORDER_MAGIC) != m_cfg.magicNumber)
            continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;

         long ordType      = OrderGetInteger(ORDER_TYPE);
         ENUM_BIAS_DIR dir = ((ordType == ORDER_TYPE_BUY_LIMIT || ordType == ORDER_TYPE_BUY_STOP) ? BIAS_BULL : BIAS_BEAR);
         setupEngine.NotifyOrderPlaced(dir, ticket);
         PrintFormat("[Exec] Recovered pending order #%I64u (%s)", ticket, QTBiasToString(dir));
        }
     }

   //+------------------------------------------------------------------+
   //| Count Active Positions & Pending Orders for MagicNumber          |
   //+------------------------------------------------------------------+
   int               CountOpenPositions(const ENUM_BIAS_DIR filterDir = BIAS_NEUTRAL) const
     {
      int cnt = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.magicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;

         long pType = PositionGetInteger(POSITION_TYPE);
         if(filterDir == BIAS_BULL && pType != POSITION_TYPE_BUY)  continue;
         if(filterDir == BIAS_BEAR && pType != POSITION_TYPE_SELL) continue;
         cnt++;
        }
      return cnt;
     }

   int               CountPendingOrders(const ENUM_BIAS_DIR filterDir = BIAS_NEUTRAL) const
     {
      int cnt = 0;
      int total = OrdersTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != m_cfg.magicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol) continue;

         long oType = OrderGetInteger(ORDER_TYPE);
         bool isBuy = (oType == ORDER_TYPE_BUY_LIMIT || oType == ORDER_TYPE_BUY_STOP);
         if(filterDir == BIAS_BULL && !isBuy) continue;
         if(filterDir == BIAS_BEAR &&  isBuy) continue;
         cnt++;
        }
      return cnt;
     }

   //+------------------------------------------------------------------+
   //| Cancel All Pending Orders (or by Direction)                      |
   //+------------------------------------------------------------------+
   int               CancelPendingOrders(const ENUM_BIAS_DIR filterDir,
                                         const string reason,
                                         const CQTLogger &logger,
                                         const QTState &qtState,
                                         const ENUM_TRADE_PROFILE profile)
     {
      int cancelled = 0;
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0) continue;
         if(OrderGetInteger(ORDER_MAGIC) != m_cfg.magicNumber) continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol) continue;

         long oType = OrderGetInteger(ORDER_TYPE);
         bool isBuy = (oType == ORDER_TYPE_BUY_LIMIT || oType == ORDER_TYPE_BUY_STOP);
         ENUM_BIAS_DIR dir = (isBuy ? BIAS_BULL : BIAS_BEAR);
         if(filterDir != BIAS_NEUTRAL && dir != filterDir)
            continue;

         double lots   = OrderGetDouble(ORDER_VOLUME_CURRENT);
         double price  = OrderGetDouble(ORDER_PRICE_OPEN);
         double sl     = OrderGetDouble(ORDER_SL);
         double tp     = OrderGetDouble(ORDER_TP);
         string comm   = OrderGetString(ORDER_COMMENT);

         if(m_trade.OrderDelete(ticket))
           {
            cancelled++;
            logger.LogTradeEvent("ORDER_CANCELLED", comm, ticket, dir, lots,
                                 price, sl, tp, 0.0, 0.0, 0.0, 0, "", reason, qtState, profile);
           }
        }
      return cancelled;
     }

   //+------------------------------------------------------------------+
   //| Close All Open Positions Immediately (Used by Friday Flat &      |
   //| Profile Time Stop) with Bounded Retry & Journal Reconciliation   |
   //+------------------------------------------------------------------+
   int               CloseAllPositions(const string reason,
                                       CQTTimeEngine &timeEngine,
                                       const CQTLogger &logger,
                                       const QTState &qtState,
                                       const ENUM_TRADE_PROFILE profile)
     {
      int closedCount = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.magicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;

         long pType        = PositionGetInteger(POSITION_TYPE);
         ENUM_BIAS_DIR dir = (pType == POSITION_TYPE_BUY ? BIAS_BULL : BIAS_BEAR);
         double lots       = PositionGetDouble(POSITION_VOLUME);
         double openP      = PositionGetDouble(POSITION_PRICE_OPEN);
         double slP        = PositionGetDouble(POSITION_SL);
         double tpP        = PositionGetDouble(POSITION_TP);
         double curP       = PositionGetDouble(POSITION_PRICE_CURRENT);
         double profit     = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         string comm       = PositionGetString(POSITION_COMMENT);

         int mIdx = FindManagedIndex(ticket);
         double initRiskDist = (mIdx >= 0 ? MathAbs(m_managed[mIdx].entryPrice - m_managed[mIdx].initialSL)
                                          : MathAbs(openP - slP));
         double realizedR = 0.0;
         if(initRiskDist > 1e-5)
            realizedR = (dir == BIAS_BULL ? (curP - openP) / initRiskDist : (openP - curP) / initRiskDist);

         bool closed = false;
         for(int attempt = 0; attempt < MathMax(1, m_cfg.maxRetries); attempt++)
           {
            if(m_trade.PositionClose(ticket, (ulong)MathMax(0, m_cfg.slippagePoints)))
              {
               closed = true;
               break;
              }
            uint ret = m_trade.ResultRetcode();
            if(ret != TRADE_RETCODE_REQUOTE && ret != TRADE_RETCODE_PRICE_OFF)
               break;
            Sleep(100);
           }

         if(closed)
           {
            closedCount++;
            if(mIdx >= 0)
              {
               m_managed[mIdx].lastCloseReason = reason;
               FinalizeAndJournalClosedPosition(m_managed[mIdx], timeEngine, qtState, profile, logger);
              }
            else
              {
               logger.LogTradeEvent(reason, comm, ticket, dir, lots, openP, slP, tpP,
                                    curP, profit, realizedR, 0, "", reason, qtState, profile);
              }
           }
         else
           {
            Alert(StringFormat("[QT_EA] Failed to close position #%I64u on %s (retcode=%u)",
                               ticket, reason, m_trade.ResultRetcode()));
           }
        }
      return closedCount;
     }

   //+------------------------------------------------------------------+
   //| M12: Friday Forced Flat Check (Called every second in OnTimer)   |
   //| Also checks SymbolInfoSessionTrade for early holiday close!      |
   //+------------------------------------------------------------------+
   bool              CheckAndExecuteFridayFlat(CQTTimeEngine &timeEngine,
                                               const QTState &qtState,
                                               const CQTLogger &logger,
                                               const ENUM_TRADE_PROFILE profile)
     {
      bool shouldFlat = qtState.isFridayCutoffPassed;

      // Also check if today is Friday in NY time and broker session closes within 60 minutes (early holiday close)
      MqlDateTime dtNY;
      TimeToStruct(qtState.nyTime, dtNY);
      if(!shouldFlat && dtNY.day_of_week == 5)
        {
         MqlDateTime dtSrv;
         TimeToStruct(qtState.serverTime, dtSrv);
         datetime sesFrom = 0, sesTo = 0;
         for(uint sIdx = 0; sIdx < 5; sIdx++)
           {
            datetime f = 0, t = 0;
            if(SymbolInfoSessionTrade(m_symbol, FRIDAY, sIdx, f, t))
              {
               sesFrom = f;
               sesTo   = t;
              }
            else
               break;
           }

         if(sesTo > 0)
           {
            int curSecOfDay = dtSrv.hour * 3600 + dtSrv.min * 60 + dtSrv.sec;
            int endSecOfDay = (int)sesTo;
            if(endSecOfDay > 0 && curSecOfDay >= endSecOfDay - 3600)
               shouldFlat = true;
           }
        }

      if(!shouldFlat)
         return false;

      if(CountPendingOrders() > 0)
         CancelPendingOrders(BIAS_NEUTRAL, "FRIDAY_FLAT", logger, qtState, profile);

      if(CountOpenPositions() > 0)
         CloseAllPositions("FRIDAY_FLAT", timeEngine, logger, qtState, profile);

      return true;
     }

   //+------------------------------------------------------------------+
   //| Execute Armed Setup (S4_ARMED -> Order Placement)                |
   //+------------------------------------------------------------------+
   bool              ExecuteArmedSetup(SSetupTracker &tr,
                                       CRiskManager &riskMgr,
                                       CSetupEngine &setupEngine,
                                       CMSNREngine &msnr,
                                       const CQTLogger &logger,
                                       const QTState &qtState,
                                       const SBiasState &biasState,
                                       const STradeProfileSpec &prof,
                                       const bool isSignalOnlyMode,
                                       const double atrM5 = 0.0,
                                       const double atrH1 = 0.0)
     {
      if(tr.state != SETUP_S4_ARMED || tr.orderTicket != 0)
         return false;

      // Prevent duplicate orders in the same direction
      if(CountOpenPositions(tr.direction) > 0 || CountPendingOrders(tr.direction) > 0)
         return false;

      string poiSummary = QTTfIndexToString(tr.anchorPOI.tfIdx) + "_" + QTPOITypeToString(tr.anchorPOI.type);

      // Fase 6: Signal-Only Mode (Alert + CSV Log without placing broker order)
      if(isSignalOnlyMode)
        {
         Alert(StringFormat("[SIGNAL-ONLY] %s %s | Entry=%.2f SL=%.2f TP=%.2f RR=%.2f Score=%d",
                            m_symbol, QTBiasToString(tr.direction),
                            tr.entryPrice, tr.slPrice, tr.tpPrice,
                            tr.rrRatio, tr.score.totalScore));
         logger.LogTradeEvent("SIGNAL_ARMED", tr.setupId, 0, tr.direction, 0.0,
                              tr.entryPrice, tr.slPrice, tr.tpPrice, 0.0, 0.0, 0.0,
                              tr.score.totalScore, poiSummary, "SIGNAL_ONLY_MODE", qtState, prof.profile);
         setupEngine.NotifySetupCompleted(tr.direction, "SIGNAL_SENT");
         return true;
        }

      // Fase 7: Validate Broker Conditions & Calculate Lot Size
      string rejectWhy = "";
      if(!riskMgr.ValidateBrokerConditions(tr.entryPrice, tr.slPrice, tr.tpPrice, rejectWhy))
        {
         logger.LogTradeEvent("EXEC_REJECTED", tr.setupId, 0, tr.direction, 0.0,
                              tr.entryPrice, tr.slPrice, tr.tpPrice, 0.0, 0.0, 0.0,
                              tr.score.totalScore, poiSummary, rejectWhy, qtState, prof.profile);
         setupEngine.NotifySetupCompleted(tr.direction, rejectWhy);
         return false;
        }

      double lots = riskMgr.CalculateLotSize(tr.direction, tr.entryPrice, tr.slPrice, rejectWhy);
      if(lots <= 0.0)
        {
         logger.LogTradeEvent("EXEC_REJECTED", tr.setupId, 0, tr.direction, 0.0,
                              tr.entryPrice, tr.slPrice, tr.tpPrice, 0.0, 0.0, 0.0,
                              tr.score.totalScore, poiSummary, rejectWhy, qtState, prof.profile);
         setupEngine.NotifySetupCompleted(tr.direction, rejectWhy);
         return false;
        }

      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int stopsPts = (int)MathMax(SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                  SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL));
      double minStopDist = (stopsPts > 0 ? stopsPts * point : point * 2.0);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double entryNorm = NormalizeDouble(tr.entryPrice, digits);
      double slNorm    = NormalizeDouble(tr.slPrice,    digits);
      double tpNorm    = NormalizeDouble(tr.tpPrice,    digits);

      // Guard against invalid stops or price already past SL
      if(tr.direction == BIAS_BULL)
        {
         if(slNorm >= entryNorm - minStopDist || bid <= slNorm + minStopDist || ask >= tpNorm - minStopDist)
           {
            setupEngine.NotifySetupCompleted(tr.direction, "INVALID_OR_CROSSED_STOPS");
            return false;
           }
        }
      else
        {
         if(slNorm <= entryNorm + minStopDist || ask >= slNorm - minStopDist || bid <= tpNorm + minStopDist)
           {
            setupEngine.NotifySetupCompleted(tr.direction, "INVALID_OR_CROSSED_STOPS");
            return false;
           }
        }

      bool useMarket = tr.isMarketOrder;
      // If limit price was already crossed or within stopsLevel of current market price, execute Market (if SL is still safe)
      if(!useMarket)
        {
         if(tr.direction == BIAS_BULL && entryNorm >= ask - minStopDist)
            useMarket = true;
         if(tr.direction == BIAS_BEAR && entryNorm <= bid + minStopDist)
            useMarket = true;
        }

      bool sent = false;
      for(int attempt = 0; attempt < MathMax(2, m_cfg.maxRetries); attempt++)
        {
         ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

         if(useMarket)
           {
            if(tr.direction == BIAS_BULL)
               sent = m_trade.Buy(lots, m_symbol, 0.0, slNorm, tpNorm, tr.setupId);
            else
               sent = m_trade.Sell(lots, m_symbol, 0.0, slNorm, tpNorm, tr.setupId);
           }
         else
           {
            if(tr.direction == BIAS_BULL)
               sent = m_trade.BuyLimit(lots, entryNorm, m_symbol, slNorm, tpNorm, ORDER_TIME_GTC, 0, tr.setupId);
            else
               sent = m_trade.SellLimit(lots, entryNorm, m_symbol, slNorm, tpNorm, ORDER_TIME_GTC, 0, tr.setupId);
           }

         if(sent)
            break;

         uint ret = m_trade.ResultRetcode();
         // Fallback from Limit to Market if live price touched/crossed limit price (10015 Invalid Price / 10016 Invalid Stops)
         if(!useMarket && (ret == TRADE_RETCODE_INVALID_PRICE || ret == TRADE_RETCODE_INVALID_STOPS))
           {
            double maxSlipDist = QTPipsToPrice(m_symbol, 15.0);
            if(tr.direction == BIAS_BULL &&
               MathAbs(ask - entryNorm) <= maxSlipDist &&
               bid > slNorm + minStopDist && ask < tpNorm - minStopDist)
              {
               useMarket = true;
               continue;
              }
            if(tr.direction == BIAS_BEAR &&
               MathAbs(bid - entryNorm) <= maxSlipDist &&
               ask < slNorm - minStopDist && bid > tpNorm + minStopDist)
              {
               useMarket = true;
               continue;
              }
           }

         if(ret != TRADE_RETCODE_REQUOTE && ret != TRADE_RETCODE_PRICE_OFF)
            break;
         Sleep(100);
        }

      if(!sent)
        {
         string errWhy = StringFormat("TRADE_SEND_ERROR_%u", m_trade.ResultRetcode());
         logger.LogTradeEvent("EXEC_ERROR", tr.setupId, 0, tr.direction, lots,
                              entryNorm, slNorm, tpNorm, 0.0, 0.0, 0.0,
                              tr.score.totalScore, poiSummary, errWhy, qtState, prof.profile);
         setupEngine.NotifySetupCompleted(tr.direction, errWhy);
         return false;
        }

      ulong ticket = m_trade.ResultOrder();
      if(useMarket)
        {
         double actualFill = (m_trade.ResultPrice() > 0.0 ? m_trade.ResultPrice() : (tr.direction == BIAS_BULL ? ask : bid));
         double riskUsd    = riskMgr.CalcRiskMoneyForVolume(tr.direction, lots, actualFill, slNorm);
         tr.isMarketOrder  = true;
         RegisterManagedPosition(ticket, tr, lots, actualFill, riskUsd, qtState, biasState, atrM5, atrH1);
         setupEngine.NotifyTradeFilled(tr.direction, ticket, msnr);
         logger.LogTradeEvent("ENTRY_MARKET", tr.setupId, ticket, tr.direction, lots,
                              actualFill, slNorm, tpNorm, 0.0, 0.0, 0.0,
                              tr.score.totalScore, poiSummary, "MARKET_FILLED", qtState, prof.profile);
         setupEngine.NotifySetupCompleted(tr.direction, "IN_TRADE");
        }
      else
        {
         if(tr.direction == BIAS_BULL)
            m_lastArmedBuy = tr;
         else
            m_lastArmedSell = tr;
         setupEngine.NotifyOrderPlaced(tr.direction, ticket);
         logger.LogTradeEvent("ORDER_LIMIT_PLACED", tr.setupId, ticket, tr.direction, lots,
                              entryNorm, slNorm, tpNorm, 0.0, 0.0, 0.0,
                              tr.score.totalScore, poiSummary, "LIMIT_ARMED", qtState, prof.profile);
        }

      return true;
     }

   //+------------------------------------------------------------------+
   //| Manage Open Positions, Track MFE/MAE & Reconcile Closed Trades   |
   //| - Updates MFE & MAE on every tick                                |
   //| - Reconciles closed positions into QT_Forward_Journal.csv        |
   //| - Simultaneous 50% Partial Close + Break-Even at 100 Pips (TP1)  |
   //| - Time Stop (Scalping: end of 90m block; Intraday: 17:55 NY)     |
   //+------------------------------------------------------------------+
   void              ManageActiveTrades(CSetupEngine &setupEngine,
                                        CMSNREngine &msnr,
                                        CRiskManager &riskMgr,
                                        CQTTimeEngine &timeEngine,
                                        const CQTLogger &logger,
                                        const QTState &qtState,
                                        const SBiasState &biasState,
                                        const STradeProfileSpec &prof,
                                        const double atrM5 = 0.0,
                                        const double atrH1 = 0.0)
     {
      // 1. Check if any armed limit order has filled into an open position
      SSetupTracker buyTr  = setupEngine.GetBuySetup();
      SSetupTracker sellTr = setupEngine.GetSellSetup();

      int posTotal = PositionsTotal();
      for(int i = 0; i < posTotal; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_cfg.magicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;

         // Register if newly filled from a limit order
         if(FindManagedIndex(ticket) < 0)
           {
            long pType        = PositionGetInteger(POSITION_TYPE);
            ENUM_BIAS_DIR dir = (pType == POSITION_TYPE_BUY ? BIAS_BULL : BIAS_BEAR);
            double lots       = PositionGetDouble(POSITION_VOLUME);
            double openP      = PositionGetDouble(POSITION_PRICE_OPEN);
            double slP        = PositionGetDouble(POSITION_SL);
            double tpP        = PositionGetDouble(POSITION_TP);
            string comm       = PositionGetString(POSITION_COMMENT);

            SSetupTracker refTr = (dir == BIAS_BULL ? buyTr : sellTr);
            if(StringLen(refTr.setupId) == 0)
              {
               SSetupTracker savedTr = (dir == BIAS_BULL ? m_lastArmedBuy : m_lastArmedSell);
               if(StringLen(savedTr.setupId) > 0)
                  refTr = savedTr;
               else
                 {
                  refTr.Reset(dir);
                  refTr.setupId    = comm;
                  refTr.entryPrice = openP;
                  refTr.slPrice    = slP;
                  refTr.tpPrice    = tpP;
                  double tp1D      = QTPipsToPrice(m_symbol, (m_cfg.partialTp1Pips > 0.0 ? m_cfg.partialTp1Pips : 100.0));
                  refTr.tp1Price   = (dir == BIAS_BULL ? openP + tp1D : openP - tp1D);
                  double slD       = MathAbs(openP - slP);
                  refTr.rrRatio    = (slD > 1e-5 ? MathAbs(tpP - openP) / slD : 0.0);
                 }
              }

            double riskUsd = riskMgr.CalcRiskMoneyForVolume(dir, lots, openP, slP);
            RegisterManagedPosition(ticket, refTr, lots, openP, riskUsd, qtState, biasState, atrM5, atrH1);
            setupEngine.NotifyTradeFilled(dir, ticket, msnr);
            string poiStr = QTTfIndexToString(refTr.anchorPOI.tfIdx) + "_" + QTPOITypeToString(refTr.anchorPOI.type);
            logger.LogTradeEvent("ENTRY_LIMIT_FILLED", refTr.setupId, ticket, dir, lots,
                                 openP, slP, tpP, 0.0, 0.0, 0.0,
                                 refTr.score.totalScore, poiStr, "LIMIT_FILLED", qtState, prof.profile);
            setupEngine.NotifySetupCompleted(dir, "IN_TRADE");
           }
        }

      // 2. Manage each registered position & reconcile any position that closed
      double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double stepLot= SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      for(int m = 0; m < m_managedCount; m++)
        {
         if(!m_managed[m].active)
            continue;

         ulong ticket = m_managed[m].positionTicket;
         if(!PositionSelectByTicket(ticket))
           {
            // Position was closed by TP, SL, BE, or Manual action -> reconcile & write QT_Forward_Journal.csv!
            FinalizeAndJournalClosedPosition(m_managed[m], timeEngine, qtState, prof.profile, logger);
            continue;
           }

         ENUM_BIAS_DIR dir = m_managed[m].direction;
         double curPrice   = PositionGetDouble(POSITION_PRICE_CURRENT);
         double curSL      = PositionGetDouble(POSITION_SL);
         double curTP      = PositionGetDouble(POSITION_TP);
         double curLots    = PositionGetDouble(POSITION_VOLUME);
         double curProfit  = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

         m_managed[m].currentSL = curSL;

         double riskDist   = MathAbs(m_managed[m].entryPrice - m_managed[m].initialSL);
         double profitDist = (dir == BIAS_BULL ? (curPrice - m_managed[m].entryPrice)
                                               : (m_managed[m].entryPrice - curPrice));
         double curR       = (riskDist > 1e-5 ? profitDist / riskDist : 0.0);

         // Track MFE (Max Favorable Excursion) & MAE (Max Adverse Excursion)
         if(curR > m_managed[m].mfeR)
           {
            m_managed[m].mfeR     = curR;
            m_managed[m].mfePrice = curPrice;
           }
         double adverseR = (curR < 0.0 ? -curR : 0.0);
         if(adverseR > m_managed[m].maeR)
           {
            m_managed[m].maeR     = adverseR;
            m_managed[m].maePrice = curPrice;
           }

         // A) Profile Time Stop Check
         if(m_cfg.useTimeStop)
           {
            bool timeStopTriggered = false;
            string tsReason        = "";

            if(prof.closeAt90mBlockEnd && m_managed[m].openedBlock90EndNY > 0 &&
               qtState.nyTime >= m_managed[m].openedBlock90EndNY - 60)
              {
               timeStopTriggered = true;
               tsReason          = "TIME_STOP_90M_BLOCK_END";
              }
            else if(prof.closeAtDayeDayEnd && m_managed[m].openedDayeEndNY > 0 &&
                    qtState.nyTime >= m_managed[m].openedDayeEndNY - 300) // 17:55 NY (5m before 18:00 NY rollover)
              {
               timeStopTriggered = true;
               tsReason          = "TIME_STOP_INTRADAY_18NY";
              }

            if(timeStopTriggered)
              {
               if(m_trade.PositionClose(ticket, (ulong)MathMax(0, m_cfg.slippagePoints)))
                 {
                  m_managed[m].lastCloseReason = tsReason;
                  FinalizeAndJournalClosedPosition(m_managed[m], timeEngine, qtState, prof.profile, logger);
                  continue;
                 }
              }
           }

         // B) Stage-1 Trade Protection: Move SL to Break-Even at +65 Pips (1R protection before TP1)
         double beTargetPips = (m_cfg.breakEvenPips > 0.0 ? m_cfg.breakEvenPips : 65.0);
         double beTargetDist = QTPipsToPrice(m_symbol, beTargetPips);
         double tp1TargetDist = QTPipsToPrice(m_symbol, (m_cfg.partialTp1Pips > 0.0 ? m_cfg.partialTp1Pips : 100.0));
         bool tp1Reached = (profitDist >= tp1TargetDist - 1e-5) ||
                           (m_managed[m].tp1Price > 0.0 &&
                            (dir == BIAS_BULL ? (curPrice >= m_managed[m].tp1Price)
                                              : (curPrice <= m_managed[m].tp1Price)));
         bool beReached  = (profitDist >= beTargetDist - 1e-5) || tp1Reached;

         // C) Stage-2 Mandatory Partial Close (50%) when Running 100 Pips (TP1)!
         if(tp1Reached && m_cfg.usePartialCloseTP1 && !m_managed[m].partialDone)
           {
            if(curLots >= minLot * 2.0)
              {
               double closeVol = CRiskManager::NormalizeVolume(curLots * m_cfg.partialCloseRatio,
                                                               minLot, curLots - minLot, stepLot);
               if(closeVol >= minLot && (curLots - closeVol) >= minLot)
                 {
                  if(m_trade.PositionClosePartial(ticket, closeVol, (ulong)MathMax(0, m_cfg.slippagePoints)))
                    {
                     m_managed[m].partialDone = true;
                     curLots -= closeVol;
                     logger.LogTradeEvent("PARTIAL_TP1", m_managed[m].setupId, ticket, dir, closeVol,
                                          m_managed[m].entryPrice, curSL, curTP, curPrice,
                                          curProfit * m_cfg.partialCloseRatio, curR,
                                          m_managed[m].confluenceScore, m_managed[m].poiSummary,
                                          "PARTIAL_50_AT_100PIPS", qtState, prof.profile);
                    }
                 }
               else
                  m_managed[m].partialDone = true; // Cannot split minimum lot
              }
            else
               m_managed[m].partialDone = true;
           }

         // Execute Break-Even SL modification once Stage-1 (+65 Pips) or Stage-2 (+100 Pips) is reached
         if(beReached && m_cfg.useBreakEvenAt1R && !m_managed[m].beApplied)
           {
            double beBuffer = m_cfg.breakEvenBufferPoints * point;
            double newSL    = (dir == BIAS_BULL ? NormalizeDouble(m_managed[m].entryPrice + beBuffer, digits)
                                                : NormalizeDouble(m_managed[m].entryPrice - beBuffer, digits));

            bool slImproved = (dir == BIAS_BULL ? (newSL > curSL) : (curSL == 0.0 || newSL < curSL));
            if(slImproved && m_trade.PositionModify(ticket, newSL, curTP))
              {
               m_managed[m].beApplied = true;
               m_managed[m].currentSL = newSL;
               logger.LogTradeEvent("BREAK_EVEN_1R", m_managed[m].setupId, ticket, dir, curLots,
                                    m_managed[m].entryPrice, newSL, curTP, curPrice,
                                    curProfit, curR, m_managed[m].confluenceScore,
                                    m_managed[m].poiSummary, "SL_MOVED_TO_BE", qtState, prof.profile);
              }
           }
        }
     }
  };

#endif // QT_EXEC_MQH
//+------------------------------------------------------------------+
