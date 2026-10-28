//+------------------------------------------------------------------+
//| Risk.mqh                                                         |
//| M8 - Risk Calculation, Lot Sizing & Circuit Breakers             |
//| Place in: MQL5/Include/QT/Risk.mqh                               |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Risk-based lot calculation (default 0.5% balance) using       |
//|    OrderCalcProfit & OrderCalcMargin, normalized to symbol step  |
//|  - Circuit Breakers per Daye Day / Week:                         |
//|    * Max Daily Loss % (default 2.0%)                             |
//|    * Max Weekly Loss % (default 5.0%)                            |
//|    * Max Trades per Daye Day (default 2)                         |
//|    * Max Consecutive Losses (default 3 -> pause until next day)  |
//|  - Spread filter & Broker StopsLevel / FreezeLevel validation    |
//+------------------------------------------------------------------+
#ifndef QT_RISK_MQH
#define QT_RISK_MQH

#include "Defines.mqh"
#include "QT_Time.mqh"

struct SRiskConfig
  {
   bool   useEquityStepLot;    // Default true: Fixed 0.05 lot per $5,000 USD equity tier
   double equityStepUsd;       // Default 5000.0 USD per step
   double lotPerEquityStep;    // Default 0.05 lot per step (e.g. $5k->0.05, $10k->0.10, $25k->0.25)
   double riskPercentPerTrade; // Fallback % risk if useEquityStepLot=false (default 0.5%)
   double maxDailyLossPercent; // Default 2.0% of start-of-day balance
   double maxWeeklyLossPercent;// Default 5.0% of start-of-week balance
   int    maxTradesPerDayeDay; // Default 2 trades per Daye day
   int    maxConsecutiveLosses;// Default 3 consecutive losses -> stop until next Daye day
   int    maxSpreadPoints;     // Max allowed spread in points (e.g. 50 points = 50 cents on XAUUSD)

   void SetDefaults()
     {
      useEquityStepLot     = true;
      equityStepUsd        = 5000.0;
      lotPerEquityStep     = 0.05;
      riskPercentPerTrade  = 0.50;
      maxDailyLossPercent  = 2.00;
      maxWeeklyLossPercent = 5.00;
      maxTradesPerDayeDay  = 2;
      maxConsecutiveLosses = 3;
      maxSpreadPoints      = 50;
     }
  };

struct SRiskStats
  {
   datetime currentDayeDayStartNY;
   datetime currentDayeWeekStartNY;
   double   dayStartBalance;
   double   weekStartBalance;
   double   realizedDailyPnL;
   double   realizedWeeklyPnL;
   int      tradesOpenedToday;
   int      consecutiveLosses;
   bool     isDailyLimitHit;
   bool     isWeeklyLimitHit;
   bool     isTradeCountLimitHit;
   bool     isConsecLossLimitHit;
   string   blockReason;

   void Reset()
     {
      currentDayeDayStartNY  = 0;
      currentDayeWeekStartNY = 0;
      dayStartBalance        = 0.0;
      weekStartBalance       = 0.0;
      realizedDailyPnL       = 0.0;
      realizedWeeklyPnL      = 0.0;
      tradesOpenedToday      = 0;
      consecutiveLosses      = 0;
      isDailyLimitHit        = false;
      isWeeklyLimitHit       = false;
      isTradeCountLimitHit   = false;
      isConsecLossLimitHit   = false;
      blockReason            = "OK";
     }
  };

//+------------------------------------------------------------------+
//| CRiskManager Class                                               |
//+------------------------------------------------------------------+
class CRiskManager
  {
private:
   string            m_symbol;
   long              m_magic;
   SRiskConfig       m_cfg;
   SRiskStats        m_stats;

   //--- Scan closed deal history for magic number since given server timestamp
   void              ScanDealHistory(CQTTimeEngine &timeEngine,
                                     const QTState &qtState)
     {
      datetime dayStartSrv  = timeEngine.NYToServer(qtState.dayeDayStartNY);
      datetime weekStartSrv = timeEngine.NYToServer(qtState.dayeWeekStartNY);
      datetime fromSrv      = MathMin(dayStartSrv, weekStartSrv);

      if(!HistorySelect(fromSrv, qtState.serverTime + 60))
         return;

      double dailyPnl   = 0.0;
      double weeklyPnl  = 0.0;
      int    consecLoss = 0;
      int    entriesToday = 0;

      int totalDeals = HistoryDealsTotal();
      for(int i = 0; i < totalDeals; i++)
        {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0)
            continue;
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != m_magic)
            continue;
         if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != m_symbol)
            continue;

         datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
         long dealEntry    = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         double netProfit  = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                             HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                             HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

         if(dealEntry == DEAL_ENTRY_IN && dealTime >= dayStartSrv)
            entriesToday++;

         if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
           {
            if(dealTime >= weekStartSrv)
               weeklyPnl += netProfit;
            if(dealTime >= dayStartSrv)
              {
               dailyPnl += netProfit;
               if(netProfit < -1e-4)
                  consecLoss++;
               else if(netProfit > 1e-4)
                  consecLoss = 0;
              }
           }
        }

      m_stats.realizedDailyPnL  = dailyPnl;
      m_stats.realizedWeeklyPnL = weeklyPnl;
      m_stats.tradesOpenedToday = entriesToday;
      m_stats.consecutiveLosses = consecLoss;
     }

public:
                     CRiskManager()
     {
      m_symbol = QT_TARGET_SYMBOL;
      m_magic  = 202610;
      m_cfg.SetDefaults();
      m_stats.Reset();
     }

   void              Init(const string symbol, const long magicNumber, const SRiskConfig &cfg)
     {
      m_symbol = (StringLen(symbol) > 0 ? symbol : _Symbol);
      m_magic  = magicNumber;
      m_cfg    = cfg;
      m_stats.Reset();
     }

   SRiskConfig       GetConfig() const { return m_cfg; }
   SRiskStats        GetStats()  const { return m_stats; }

   //+------------------------------------------------------------------+
   //| Pure Lot Normalization Helper (Testable Offline)                 |
   //+------------------------------------------------------------------+
   static double     NormalizeVolume(const double rawLot,
                                     const double minLot,
                                     const double maxLot,
                                     const double lotStep)
     {
      if(rawLot <= 0.0 || lotStep <= 0.0)
         return 0.0;
      double stepped = MathFloor((rawLot + 1e-9) / lotStep) * lotStep;
      if(stepped < minLot)
         return 0.0; // Below broker minimum lot -> do not force over-risk!
      if(stepped > maxLot)
         stepped = maxLot;

      int digits = 2;
      if(lotStep >= 1.0)        digits = 0;
      else if(lotStep >= 0.1)   digits = 1;
      else if(lotStep >= 0.01)  digits = 2;
      else if(lotStep >= 0.001) digits = 3;
      return NormalizeDouble(stepped, digits);
     }

   //+------------------------------------------------------------------+
   //| Patented Equity-Step Lot Calculator                              |
   //| 0.05 lot per $5,000 USD tier ($5k->0.05, $10k->0.10, $25k->0.25) |
   //+------------------------------------------------------------------+
   static double     CalcEquityStepLot(const double equity,
                                       const double stepUsd,
                                       const double lotPerStep,
                                       const double minLot,
                                       const double maxLot,
                                       const double lotStep)
     {
      if(equity <= 0.0 || stepUsd <= 0.0 || lotPerStep <= 0.0)
         return 0.0;
      double tiers  = MathMax(1.0, MathRound(equity / stepUsd));
      double rawLot = tiers * lotPerStep;
      return NormalizeVolume(rawLot, minLot, maxLot, lotStep);
     }

   //+------------------------------------------------------------------+
   //| Calculate Position Size (Lots) for Given Entry & Stop Loss       |
   //+------------------------------------------------------------------+
   double            CalculateLotSize(const ENUM_BIAS_DIR dir,
                                      const double entryPrice,
                                      const double slPrice,
                                      string &outReason) const
     {
      outReason = "";
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         equity = balance;
      if(balance <= 0.0 && equity <= 0.0)
        {
         outReason = "ZERO_ACCOUNT_BALANCE";
         return 0.0;
        }

      double slDist = MathAbs(entryPrice - slPrice);
      if(slDist <= 0.0)
        {
         outReason = "INVALID_SL_DISTANCE";
         return 0.0;
        }

      ENUM_ORDER_TYPE ordType = (dir == BIAS_BULL ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      double lot     = 0.0;

      if(m_cfg.useEquityStepLot && m_cfg.equityStepUsd > 0.0 && m_cfg.lotPerEquityStep > 0.0)
        {
         lot = CalcEquityStepLot(equity, m_cfg.equityStepUsd, m_cfg.lotPerEquityStep, minLot, maxLot, lotStep);
         if(lot < minLot)
           {
            outReason = StringFormat("LOT_BELOW_MIN (equity=%.2f < min=%.2f)", equity, minLot);
            return 0.0;
           }
        }
      else
        {
         double riskMoney = balance * (m_cfg.riskPercentPerTrade / 100.0);
         double lossPerOneLot = 0.0;
         if(!OrderCalcProfit(ordType, m_symbol, 1.0, entryPrice, slPrice, lossPerOneLot) ||
            MathAbs(lossPerOneLot) <= 1e-5)
           {
            double tickVal  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
            if(tickVal > 0.0 && tickSize > 0.0)
               lossPerOneLot = (slDist / tickSize) * tickVal;
           }
         lossPerOneLot = MathAbs(lossPerOneLot);
         if(lossPerOneLot <= 1e-5)
           {
            outReason = "ORDER_CALC_PROFIT_FAILED";
            return 0.0;
           }

         double rawLot = riskMoney / lossPerOneLot;
         lot = NormalizeVolume(rawLot, minLot, maxLot, lotStep);
         if(lot < minLot)
           {
            outReason = StringFormat("LOT_BELOW_MIN (raw=%.4f < min=%.2f)", rawLot, minLot);
            return 0.0;
           }
        }

      // Check free margin via OrderCalcMargin
      double reqMargin = 0.0;
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(OrderCalcMargin(ordType, m_symbol, lot, entryPrice, reqMargin))
        {
         if(reqMargin > freeMargin * 0.95)
           {
            outReason = StringFormat("INSUFFICIENT_MARGIN (req=%.2f > free=%.2f)", reqMargin, freeMargin);
            return 0.0;
           }
        }

      return lot;
     }

   //+------------------------------------------------------------------+
   //| Validate Spread, StopsLevel & FreezeLevel                        |
   //+------------------------------------------------------------------+
   bool              ValidateBrokerConditions(const double entryPrice,
                                              const double slPrice,
                                              const double tpPrice,
                                              string &outReason) const
     {
      outReason = "";
      int curSpreadPts = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(m_cfg.maxSpreadPoints > 0 && curSpreadPts > m_cfg.maxSpreadPoints)
        {
         outReason = StringFormat("SPREAD_TOO_HIGH (%d > %d pts)", curSpreadPts, m_cfg.maxSpreadPoints);
         return false;
        }

      double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int stopsLevelPts = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freezePts     = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      double minStopDist = MathMax(stopsLevelPts, freezePts) * point;

      if(minStopDist > 0.0)
        {
         if(MathAbs(entryPrice - slPrice) < minStopDist)
           {
            outReason = "SL_CLOSER_THAN_STOPS_LEVEL";
            return false;
           }
         if(MathAbs(tpPrice - entryPrice) < minStopDist)
           {
            outReason = "TP_CLOSER_THAN_STOPS_LEVEL";
            return false;
           }
        }

      return true;
     }

   //+------------------------------------------------------------------+
   //| Calculate Exact USD Risk for a Given Lot Size & Stop Loss        |
   //+------------------------------------------------------------------+
   double            CalcRiskMoneyForVolume(const ENUM_BIAS_DIR dir,
                                            const double volume,
                                            const double entryPrice,
                                            const double slPrice) const
     {
      if(volume <= 0.0)
         return 0.0;
      double slDist = MathAbs(entryPrice - slPrice);
      if(slDist <= 0.0)
         return 0.0;

      ENUM_ORDER_TYPE ordType = (dir == BIAS_BULL ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double lossMoney = 0.0;
      if(!OrderCalcProfit(ordType, m_symbol, volume, entryPrice, slPrice, lossMoney) ||
         MathAbs(lossMoney) <= 1e-5)
        {
         double tickVal  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickVal > 0.0 && tickSize > 0.0)
            lossMoney = (slDist / tickSize) * tickVal * volume;
        }
      return MathAbs(lossMoney);
     }

   //+------------------------------------------------------------------+
   //| Update Daily/Weekly Circuit Breakers & Return Permission         |
   //+------------------------------------------------------------------+
   bool              UpdateAndCheckCanTrade(CQTTimeEngine &timeEngine,
                                            const QTState &qtState,
                                            string &outBlockReason)
     {
      double curBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(curBalance <= 0.0)
         curBalance = 10000.0;

      // Reset daily baseline at start of a new Daye trading day (18:00 NY)
      if(qtState.dayeDayStartNY != m_stats.currentDayeDayStartNY)
        {
         m_stats.currentDayeDayStartNY = qtState.dayeDayStartNY;
         m_stats.dayStartBalance       = curBalance;
         m_stats.realizedDailyPnL      = 0.0;
         m_stats.tradesOpenedToday     = 0;
         m_stats.consecutiveLosses     = 0;
        }

      // Reset weekly baseline at start of a new Daye trading week (Sun 18:00 NY)
      if(qtState.dayeWeekStartNY != m_stats.currentDayeWeekStartNY)
        {
         m_stats.currentDayeWeekStartNY = qtState.dayeWeekStartNY;
         m_stats.weekStartBalance       = curBalance;
         m_stats.realizedWeeklyPnL      = 0.0;
        }

      ScanDealHistory(timeEngine, qtState);

      double maxDailyLossMoney  = m_stats.dayStartBalance  * (m_cfg.maxDailyLossPercent  / 100.0);
      double maxWeeklyLossMoney = m_stats.weekStartBalance * (m_cfg.maxWeeklyLossPercent / 100.0);

      m_stats.isDailyLimitHit      = (m_stats.realizedDailyPnL  <= -maxDailyLossMoney);
      m_stats.isWeeklyLimitHit     = (m_stats.realizedWeeklyPnL <= -maxWeeklyLossMoney);
      m_stats.isTradeCountLimitHit = (m_stats.tradesOpenedToday >= m_cfg.maxTradesPerDayeDay);
      m_stats.isConsecLossLimitHit = (m_stats.consecutiveLosses >= m_cfg.maxConsecutiveLosses);

      if(m_stats.isDailyLimitHit)
        {
         m_stats.blockReason = StringFormat("DAILY_LOSS_LIMIT (%.2f USD)", m_stats.realizedDailyPnL);
         outBlockReason      = m_stats.blockReason;
         return false;
        }
      if(m_stats.isWeeklyLimitHit)
        {
         m_stats.blockReason = StringFormat("WEEKLY_LOSS_LIMIT (%.2f USD)", m_stats.realizedWeeklyPnL);
         outBlockReason      = m_stats.blockReason;
         return false;
        }
      if(m_stats.isConsecLossLimitHit)
        {
         m_stats.blockReason = StringFormat("MAX_CONSEC_LOSSES (%d)", m_stats.consecutiveLosses);
         outBlockReason      = m_stats.blockReason;
         return false;
        }
      if(m_stats.isTradeCountLimitHit)
        {
         m_stats.blockReason = StringFormat("MAX_DAILY_TRADES (%d/%d)",
                                            m_stats.tradesOpenedToday, m_cfg.maxTradesPerDayeDay);
         outBlockReason      = m_stats.blockReason;
         return false;
        }

      m_stats.blockReason = "OK";
      outBlockReason      = "OK";
      return true;
     }
  };

#endif // QT_RISK_MQH
//+------------------------------------------------------------------+
