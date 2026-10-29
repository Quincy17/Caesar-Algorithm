//+------------------------------------------------------------------+
//| Logger.mqh                                                       |
//| M9 - CSV Setup & Trade Journal Logger + Screenshot Engine        |
//| Place in: MQL5/Include/QT/Logger.mqh                             |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Write Setups_Log.csv (every evaluated setup, including        |
//|    rejected/cancelled setups with exact reason and score details)|
//|  - Write Trades_Log.csv (every executed trade event: ENTRY,      |
//|    BREAK_EVEN, PARTIAL_TP1, TIME_STOP, FRIDAY_FLAT, CLOSED,      |
//|    realized P/L and R-multiple)                                  |
//|  - Capture optional chart screenshot on S4_ARMED / ENTRY         |
//+------------------------------------------------------------------+
#ifndef QT_LOGGER_MQH
#define QT_LOGGER_MQH

#include "Setup.mqh"

struct SLoggerConfig
  {
   bool   enableCsvLog;
   string setupsCsvFile;
   string tradesCsvFile;
   string forwardJournalCsvFile;
   bool   takeScreenshotOnEntry;
   int    screenshotWidth;
   int    screenshotHeight;

   void SetDefaults()
     {
      enableCsvLog          = true;
      setupsCsvFile         = "QT_Setups_Log.csv";
      tradesCsvFile         = "QT_Trades_Log.csv";
      forwardJournalCsvFile = "QT_Forward_Journal.csv";
      takeScreenshotOnEntry = false;
      screenshotWidth       = 1600;
      screenshotHeight      = 900;
     }
  };

//+------------------------------------------------------------------+
//| Master Closed Trade Journal Record (1 Row = 1 Completed Trade)   |
//| Includes Full QT Context, Execution Quality, P/L, MFE/MAE & Score|
//+------------------------------------------------------------------+
struct SClosedTradeJournal
  {
   // 1. Identity & Timing
   ulong             positionId;
   string            setupId;
   string            symbol;
   ENUM_TRADE_PROFILE profile;
   ENUM_BIAS_DIR     direction;
   bool              wasMarketOrder;

   datetime          openServerTime;
   datetime          openNyTime;
   datetime          closeServerTime;
   datetime          closeNyTime;
   int               holdDurationMin;
   string            openDayeDate;
   string            openDayeDow;

   // 2. Quarterly Theory Context at Entry & Exit
   ENUM_QT_QUARTER   openYearQ;
   ENUM_QT_QUARTER   openMonthQ;
   ENUM_QT_QUARTER   openWeekQ;
   ENUM_QT_QUARTER   openDayQ;
   ENUM_QT_SESSION   openSession;
   ENUM_QT_QUARTER   openQ90;
   ENUM_QT_SESSION   closeSession;
   ENUM_QT_QUARTER   closeQ90;

   // 3. Execution Quality & Price Levels
   int               barsToFillM5;
   int               spreadAtEntryPts;
   double            slippagePts;
   double            initialLots;
   double            plannedEntryPrice;
   double            actualEntryPrice;
   double            initialSlPrice;
   double            finalSlPrice;
   double            tp1Price;
   double            finalTpPrice;
   double            exitPrice;
   double            plannedRR;

   // 4. Outcome & Financial Performance (USD & R)
   string            exitOutcome; // TP_FULL, TP1_THEN_TP, TP1_THEN_BE, BE_HIT, SL_HIT, TIME_STOP, FRIDAY_FLAT, MANUAL_CLOSE
   double            initialRiskUsd;
   double            grossProfitUsd;
   double            swapUsd;
   double            commissionUsd;
   double            netProfitUsd;
   double            realizedR;
   double            balanceAfter;

   // 5. Algorithm Evolution Telemetry (MFE / MAE / Volatility)
   double            mfePrice;
   double            mfeR;
   double            maePrice;
   double            maeR;
   bool              beTriggered;
   bool              partialTp1Triggered;
   double            atrM5AtEntry;
   double            atrH1AtEntry;

   // 6. Strategy Architecture & Confluence Breakdown
   ENUM_BIAS_DIR     biasW1;
   ENUM_BIAS_DIR     biasD1;
   ENUM_BIAS_DIR     biasH4;
   string            anchorPoiSummary;
   string            refinedPoiSummary;
   string            sweepPoolSummary;
   string            fvgTfSummary;
   string            dolLabel;
   SConfluenceBreakdown score;

   void Reset()
     {
      positionId          = 0;
      setupId             = "";
      symbol              = QT_TARGET_SYMBOL;
      profile             = PROFILE_INTRADAY;
      direction           = BIAS_NEUTRAL;
      wasMarketOrder      = false;
      openServerTime      = 0;
      openNyTime          = 0;
      closeServerTime     = 0;
      closeNyTime         = 0;
      holdDurationMin     = 0;
      openDayeDate        = "";
      openDayeDow         = "";
      openYearQ           = QT_Q1;
      openMonthQ          = QT_Q1;
      openWeekQ           = QT_Q1;
      openDayQ            = QT_Q1;
      openSession         = QT_SESSION_ASIA;
      openQ90             = QT_Q1;
      closeSession        = QT_SESSION_ASIA;
      closeQ90            = QT_Q1;
      barsToFillM5        = 0;
      spreadAtEntryPts    = 0;
      slippagePts         = 0.0;
      initialLots         = 0.0;
      plannedEntryPrice   = 0.0;
      actualEntryPrice    = 0.0;
      initialSlPrice      = 0.0;
      finalSlPrice        = 0.0;
      tp1Price            = 0.0;
      finalTpPrice        = 0.0;
      exitPrice           = 0.0;
      plannedRR           = 0.0;
      exitOutcome         = "CLOSED";
      initialRiskUsd      = 0.0;
      grossProfitUsd      = 0.0;
      swapUsd             = 0.0;
      commissionUsd       = 0.0;
      netProfitUsd        = 0.0;
      realizedR           = 0.0;
      balanceAfter        = 0.0;
      mfePrice            = 0.0;
      mfeR                = 0.0;
      maePrice            = 0.0;
      maeR                = 0.0;
      beTriggered         = false;
      partialTp1Triggered = false;
      atrM5AtEntry        = 0.0;
      atrH1AtEntry        = 0.0;
      biasW1              = BIAS_NEUTRAL;
      biasD1              = BIAS_NEUTRAL;
      biasH4              = BIAS_NEUTRAL;
      anchorPoiSummary    = "";
      refinedPoiSummary   = "NONE";
      sweepPoolSummary    = "";
      fvgTfSummary        = "NONE";
      dolLabel            = "";
      score.Reset();
     }
  };

//+------------------------------------------------------------------+
//| CQTLogger Class                                                  |
//+------------------------------------------------------------------+
class CQTLogger
  {
private:
   SLoggerConfig     m_cfg;
   string            m_symbol;

   static string     CleanCsvField(string s)
     {
      StringReplace(s, ",", ";");
      StringReplace(s, "\"", "'");
      StringReplace(s, "\r", " ");
      StringReplace(s, "\n", " ");
      return s;
     }

   void              EnsureSetupHeader() const
     {
      if(!m_cfg.enableCsvLog)
         return;
      if(FileIsExist(m_cfg.setupsCsvFile, FILE_COMMON))
         return;

      int h = FileOpen(m_cfg.setupsCsvFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(h == INVALID_HANDLE)
         return;

      FileWrite(h,
                "server_time",
                "ny_time",
                "daye_date",
                "daye_dow",
                "profile",
                "setup_id",
                "direction",
                "state",
                "status_reason",
                "year_q",
                "month_q",
                "week_q",
                "day_q",
                "session",
                "q90",
                "bias_w1",
                "bias_d1",
                "bias_h4",
                "poi_tf",
                "poi_type",
                "poi_price",
                "refined_poi_tf",
                "refined_poi_price",
                "poi_overlaps",
                "sweep_pool",
                "sweep_price",
                "sweep_wick",
                "mss_broken_price",
                "fvg_tf",
                "fvg_ce",
                "entry_price",
                "sl_price",
                "tp_price",
                "tp1_price",
                "dol_label",
                "rr_ratio",
                "score_total",
                "pts_poi_tf",
                "pts_poi_type",
                "pts_overlap",
                "pts_q90",
                "pts_session",
                "pts_tdo",
                "pts_two",
                "pts_sweep",
                "pts_fvg",
                "pts_bias_score");
      FileClose(h);
     }

   void              EnsureTradeHeader() const
     {
      if(!m_cfg.enableCsvLog)
         return;
      if(FileIsExist(m_cfg.tradesCsvFile, FILE_COMMON))
         return;

      int h = FileOpen(m_cfg.tradesCsvFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(h == INVALID_HANDLE)
         return;

      FileWrite(h,
                "server_time",
                "ny_time",
                "daye_date",
                "daye_dow",
                "year_q",
                "month_q",
                "week_q",
                "day_q",
                "session",
                "q90",
                "profile",
                "event_type",
                "setup_id",
                "ticket",
                "direction",
                "lots",
                "entry_price",
                "sl_price",
                "tp_price",
                "close_price",
                "profit_usd",
                "realized_r",
                "score_total",
                "poi_summary",
                "reason");
      FileClose(h);
     }

   void              EnsureJournalHeader() const
     {
      if(!m_cfg.enableCsvLog)
         return;
      if(FileIsExist(m_cfg.forwardJournalCsvFile, FILE_COMMON))
         return;

      int h = FileOpen(m_cfg.forwardJournalCsvFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
      if(h == INVALID_HANDLE)
         return;

      string header =
         "position_id,setup_id,symbol,profile,direction,order_type,"
         "open_server_time,open_ny_time,close_server_time,close_ny_time,hold_duration_min,open_daye_date,open_daye_dow,"
         "open_year_q,open_month_q,open_week_q,open_day_q,open_session,open_q90,close_session,close_q90,"
         "bars_to_fill_m5,spread_at_entry_pts,slippage_pts,initial_lots,planned_entry,actual_entry,"
         "initial_sl,final_sl,tp1_price,final_tp,exit_price,planned_rr,"
         "exit_outcome,initial_risk_usd,gross_profit_usd,swap_usd,commission_usd,net_profit_usd,realized_r,balance_after,"
         "mfe_price,mfe_r,mae_price,mae_r,be_triggered,partial_tp1_triggered,atr_m5_entry,atr_h1_entry,"
         "bias_w1,bias_d1,bias_h4,anchor_poi,refined_poi,sweep_pool,fvg_tf,dol_label,"
         "score_total,pts_poi_tf,pts_poi_type,pts_overlap,pts_q90,pts_session,pts_tdo,pts_two,pts_sweep,pts_fvg,pts_bias_score\r\n";

      FileWriteString(h, header);
      FileClose(h);
     }

public:
                     CQTLogger()
     {
      m_symbol = QT_TARGET_SYMBOL;
      m_cfg.SetDefaults();
     }

   void              Init(const string symbol, const SLoggerConfig &cfg)
     {
      m_symbol = (StringLen(symbol) > 0 ? symbol : QT_TARGET_SYMBOL);
      m_cfg    = cfg;
      EnsureSetupHeader();
      EnsureTradeHeader();
      EnsureJournalHeader();
     }

   //+------------------------------------------------------------------+
   //| Log Evaluated Setup (Valid S4_ARMED or Rejected/Cancelled Setup) |
   //+------------------------------------------------------------------+
   void              LogSetup(const SSetupTracker &tr,
                              const QTState &qtState,
                              const SBiasState &biasState,
                              const STradeProfileSpec &prof) const
     {
      if(!m_cfg.enableCsvLog)
         return;

      EnsureSetupHeader();
      int h = FileOpen(m_cfg.setupsCsvFile,
                       FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ,
                       ',');
      if(h == INVALID_HANDLE)
         return;

      FileSeek(h, 0, SEEK_END);

      string dayeDate = StringFormat("%04d-%02d-%02d", qtState.dayeYear, qtState.dayeMonth, qtState.dayeDay);
      string refTfStr = (tr.hasRefinedPOI ? QTTfIndexToString(tr.refinedPOI.tfIdx) : "NONE");
      double refPrice = (tr.hasRefinedPOI ? tr.refinedPOI.price : 0.0);
      string fvgTfStr = (tr.hasFvg ? QTTfIndexToString(tr.fvg.tfIdx) : "NONE");
      double fvgCeVal = (tr.hasFvg ? tr.fvg.ce : 0.0);

      FileWrite(h,
                TimeToString(qtState.serverTime, TIME_DATE | TIME_SECONDS),
                TimeToString(qtState.nyTime, TIME_DATE | TIME_SECONDS),
                dayeDate,
                QTDayOfWeekToString(qtState.dayeDayOfWeek),
                QTProfileToString(tr.profile),
                CleanCsvField(tr.setupId),
                QTBiasToString(tr.direction),
                QTSetupStateToString(tr.state),
                CleanCsvField(tr.statusNote),
                QTQuarterToString(qtState.yearQ),
                QTQuarterToString(qtState.monthQ),
                QTQuarterToString(tr.weekQ),
                QTQuarterToString(tr.dayQ),
                QTSessionToString(tr.session),
                QTQuarterToString(tr.q90),
                QTBiasToString(biasState.biasW1),
                QTBiasToString(biasState.biasD1),
                QTBiasToString(biasState.biasH4),
                QTTfIndexToString(tr.anchorPOI.tfIdx),
                QTPOITypeToString(tr.anchorPOI.type),
                DoubleToString(tr.anchorPOI.price, 2),
                refTfStr,
                DoubleToString(refPrice, 2),
                IntegerToString(tr.poiOverlapCount),
                QTLiqPoolTypeToString(tr.sweep.poolType),
                DoubleToString(tr.sweep.sweptLevelPrice, 2),
                DoubleToString(tr.sweep.extremeWickPrice, 2),
                DoubleToString(tr.mss.brokenSwingPrice, 2),
                fvgTfStr,
                DoubleToString(fvgCeVal, 2),
                DoubleToString(tr.entryPrice, 2),
                DoubleToString(tr.slPrice, 2),
                DoubleToString(tr.tpPrice, 2),
                DoubleToString(tr.tp1Price, 2),
                CleanCsvField(tr.dolLabel),
                DoubleToString(tr.rrRatio, 2),
                IntegerToString(tr.score.totalScore),
                IntegerToString(tr.score.ptsPoiTF),
                IntegerToString(tr.score.ptsPoiType),
                IntegerToString(tr.score.ptsPoiOverlap),
                IntegerToString(tr.score.ptsQ90),
                IntegerToString(tr.score.ptsSession),
                IntegerToString(tr.score.ptsTrueDayOpen),
                IntegerToString(tr.score.ptsTrueWeekOpen),
                IntegerToString(tr.score.ptsSweep),
                IntegerToString(tr.score.ptsFvg),
                IntegerToString(tr.score.ptsBiasScoreTF));

      FileClose(h);
     }

   //+------------------------------------------------------------------+
   //| Log Trade Lifecycle Event (ENTRY, BE, PARTIAL, FRIDAY_FLAT, etc.)|
   //+------------------------------------------------------------------+
   void              LogTradeEvent(const string eventType,
                                   const string setupId,
                                   const ulong ticket,
                                   const ENUM_BIAS_DIR dir,
                                   const double lots,
                                   const double entryPrice,
                                   const double slPrice,
                                   const double tpPrice,
                                   const double closePrice,
                                   const double profitUsd,
                                   const double realizedR,
                                   const int scoreTotal,
                                   const string poiSummary,
                                   const string reason,
                                   const QTState &qtState,
                                   const ENUM_TRADE_PROFILE profile) const
     {
      if(!m_cfg.enableCsvLog)
         return;

      EnsureTradeHeader();
      int h = FileOpen(m_cfg.tradesCsvFile,
                       FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ,
                       ',');
      if(h == INVALID_HANDLE)
         return;

      FileSeek(h, 0, SEEK_END);

      string dayeDate = StringFormat("%04d-%02d-%02d", qtState.dayeYear, qtState.dayeMonth, qtState.dayeDay);

      FileWrite(h,
                TimeToString(qtState.serverTime, TIME_DATE | TIME_SECONDS),
                TimeToString(qtState.nyTime, TIME_DATE | TIME_SECONDS),
                dayeDate,
                QTDayOfWeekToString(qtState.dayeDayOfWeek),
                QTQuarterToString(qtState.yearQ),
                QTQuarterToString(qtState.monthQ),
                QTQuarterToString(qtState.weekQ),
                QTQuarterToString(qtState.dayQ),
                QTSessionToString(qtState.session),
                QTQuarterToString(qtState.q90),
                QTProfileToString(profile),
                CleanCsvField(eventType),
                CleanCsvField(setupId),
                IntegerToString((long)ticket),
                QTBiasToString(dir),
                DoubleToString(lots, 2),
                DoubleToString(entryPrice, 2),
                DoubleToString(slPrice, 2),
                DoubleToString(tpPrice, 2),
                DoubleToString(closePrice, 2),
                DoubleToString(profitUsd, 2),
                DoubleToString(realizedR, 2),
                IntegerToString(scoreTotal),
                CleanCsvField(poiSummary),
                CleanCsvField(reason));

      FileClose(h);

      if(m_cfg.takeScreenshotOnEntry && (eventType == "ENTRY" || eventType == "SIGNAL_ARMED"))
        {
         string shotFile = StringFormat("QT_Shots\\%s_%I64u.png", CleanCsvField(setupId), ticket);
         ChartScreenShot(0, shotFile, m_cfg.screenshotWidth, m_cfg.screenshotHeight, ALIGN_RIGHT);
        }
     }

   //+------------------------------------------------------------------+
   //| Log Completed Closed Trade to QT_Forward_Journal.csv             |
   //+------------------------------------------------------------------+
   void              LogClosedTradeJournal(const SClosedTradeJournal &j) const
     {
      if(!m_cfg.enableCsvLog)
         return;

      EnsureJournalHeader();
      int h = FileOpen(m_cfg.forwardJournalCsvFile,
                       FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ);
      if(h == INVALID_HANDLE)
         return;

      FileSeek(h, 0, SEEK_END);

      string part1 = StringFormat("%I64u,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%s,%s,",
                                  j.positionId,
                                  CleanCsvField(j.setupId),
                                  CleanCsvField(j.symbol),
                                  QTProfileToString(j.profile),
                                  QTBiasToString(j.direction),
                                  (j.wasMarketOrder ? "MARKET" : "LIMIT"),
                                  TimeToString(j.openServerTime, TIME_DATE | TIME_SECONDS),
                                  TimeToString(j.openNyTime, TIME_DATE | TIME_SECONDS),
                                  TimeToString(j.closeServerTime, TIME_DATE | TIME_SECONDS),
                                  TimeToString(j.closeNyTime, TIME_DATE | TIME_SECONDS),
                                  j.holdDurationMin,
                                  CleanCsvField(j.openDayeDate),
                                  CleanCsvField(j.openDayeDow));

      string part2 = StringFormat("%s,%s,%s,%s,%s,%s,%s,%s,",
                                  QTQuarterToString(j.openYearQ),
                                  QTQuarterToString(j.openMonthQ),
                                  QTQuarterToString(j.openWeekQ),
                                  QTQuarterToString(j.openDayQ),
                                  QTSessionToString(j.openSession),
                                  QTQuarterToString(j.openQ90),
                                  QTSessionToString(j.closeSession),
                                  QTQuarterToString(j.closeQ90));

      string part3 = StringFormat("%d,%d,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,",
                                  j.barsToFillM5,
                                  j.spreadAtEntryPts,
                                  j.slippagePts,
                                  j.initialLots,
                                  j.plannedEntryPrice,
                                  j.actualEntryPrice,
                                  j.initialSlPrice,
                                  j.finalSlPrice,
                                  j.tp1Price,
                                  j.finalTpPrice,
                                  j.exitPrice,
                                  j.plannedRR);

      string part4 = StringFormat("%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%.2f,%.2f,",
                                  CleanCsvField(j.exitOutcome),
                                  j.initialRiskUsd,
                                  j.grossProfitUsd,
                                  j.swapUsd,
                                  j.commissionUsd,
                                  j.netProfitUsd,
                                  j.realizedR,
                                  j.balanceAfter,
                                  j.mfePrice,
                                  j.mfeR,
                                  j.maePrice,
                                  j.maeR,
                                  (j.beTriggered ? 1 : 0),
                                  (j.partialTp1Triggered ? 1 : 0),
                                  j.atrM5AtEntry,
                                  j.atrH1AtEntry);

      string part5 = StringFormat("%s,%s,%s,%s,%s,%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\r\n",
                                  QTBiasToString(j.biasW1),
                                  QTBiasToString(j.biasD1),
                                  QTBiasToString(j.biasH4),
                                  CleanCsvField(j.anchorPoiSummary),
                                  CleanCsvField(j.refinedPoiSummary),
                                  CleanCsvField(j.sweepPoolSummary),
                                  CleanCsvField(j.fvgTfSummary),
                                  CleanCsvField(j.dolLabel),
                                  j.score.totalScore,
                                  j.score.ptsPoiTF,
                                  j.score.ptsPoiType,
                                  j.score.ptsPoiOverlap,
                                  j.score.ptsQ90,
                                  j.score.ptsSession,
                                  j.score.ptsTrueDayOpen,
                                  j.score.ptsTrueWeekOpen,
                                  j.score.ptsSweep,
                                  j.score.ptsFvg,
                                  j.score.ptsBiasScoreTF);

      FileWriteString(h, part1 + part2 + part3 + part4 + part5);
      FileClose(h);
     }
  };

#endif // QT_LOGGER_MQH
//+------------------------------------------------------------------+
