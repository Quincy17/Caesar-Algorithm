//+------------------------------------------------------------------+
//| Visual.mqh                                                       |
//| M9 - Complete Chart Object Renderer & Dashboard (QT-MSNR-ICT EA) |
//| Place in: MQL5/Include/QT/Visual.mqh                             |
//|                                                                  |
//| Responsibilities:                                                |
//|  - Draw QT Time Boxes, 90m Dividers, and True Open lines         |
//|  - Draw MSNR Levels (A, V, RBS, SBR, QM) color-coded by status   |
//|  - Draw ICT Objects (EQH/EQL, FVG rectangles, DOL objective)     |
//|  - Render comprehensive On-Chart Dashboard (NY Time, Quarters,   |
//|    Profile, News status, Multi-TF Bias, DOL, Setup State, Score) |
//+------------------------------------------------------------------+
#ifndef QT_VISUAL_MQH
#define QT_VISUAL_MQH

#include "QT_Visualizer.mqh"
#include "Setup.mqh"

#define QT_OBJ_PREFIX "QTEA_"

struct SEAVisualConfig
  {
   bool            enableVisuals;
   bool            showQTBoxesAndOpens;
   bool            showMSNRLevels;
   bool            showICTObjects;
   bool            showDashboard;
   SQTVisualConfig qtVisCfg;

   // MSNR Colors
   color           colMSNRFreshSupport;     // Classic V Fresh (Green)
   color           colMSNRFreshResistance;  // Classic A Fresh (Crimson)
   color           colMSNRFlipFresh;        // RBS / SBR Fresh (Aqua)
   color           colMSNRQmFresh;          // QM Bull / Bear Fresh (Gold)
   color           colMSNRTouchedUsed;      // Touched / Used (DimGray)

   // ICT Colors
   color           colFvgBull;              // Bullish FVG box
   color           colFvgBear;              // Bearish FVG box
   color           colEqPool;               // EQH / EQL line
   color           colDolLine;              // Draw on Liquidity target line

   void SetDefaults()
     {
      enableVisuals          = true;
      showQTBoxesAndOpens    = true;
      showMSNRLevels         = true;
      showICTObjects         = true;
      showDashboard          = true;
      qtVisCfg.SetDefaults();
      qtVisCfg.showDashboardComment = false; // Master EA renders full dashboard

      colMSNRFreshSupport    = clrMediumSeaGreen;
      colMSNRFreshResistance = clrIndianRed;
      colMSNRFlipFresh       = clrDeepSkyBlue;
      colMSNRQmFresh         = clrGold;
      colMSNRTouchedUsed     = clrDimGray;

      colFvgBull             = clrDarkGreen;
      colFvgBear             = clrDarkRed;
      colEqPool              = clrViolet;
      colDolLine             = clrYellow;
     }
  };

//+------------------------------------------------------------------+
//| CEAChartVisual Class                                             |
//+------------------------------------------------------------------+
class CEAChartVisual
  {
private:
   long              m_chartId;
   string            m_symbol;
   SEAVisualConfig   m_cfg;
   CQTVisualizer     m_qtVis;
   datetime          m_lastObjUpdateM5;

   void              DrawLevelLine(const string name,
                                   const datetime t1,
                                   const datetime t2,
                                   const double price,
                                   const color clr,
                                   const ENUM_LINE_STYLE style,
                                   const int width,
                                   const string labelText) const
     {
      if(price <= 0.0 || t1 <= 0 || t2 <= t1)
         return;

      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_TREND, 0, t1, price, t2, price);
      else
        {
         ObjectMove(m_chartId, name, 0, t1, price);
         ObjectMove(m_chartId, name, 1, t2, price);
        }

      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, style);
      ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(m_chartId, name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(m_chartId,  name, OBJPROP_TOOLTIP, labelText);
     }

   void              DrawRectZone(const string name,
                                  const datetime t1,
                                  const datetime t2,
                                  const double highP,
                                  const double lowP,
                                  const color clr,
                                  const string tooltip) const
     {
      if(t1 <= 0 || t2 <= t1 || highP <= lowP)
         return;

      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, t1, highP, t2, lowP);
      else
        {
         ObjectMove(m_chartId, name, 0, t1, highP);
         ObjectMove(m_chartId, name, 1, t2, lowP);
        }

      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);
      ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
      ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(m_chartId,  name, OBJPROP_TOOLTIP, tooltip);
     }

   void              RenderMSNRLevels(CMSNREngine &msnr,
                                      const STradeProfileSpec &prof,
                                      const datetime nowServer) const
     {
      ObjectsDeleteAll(m_chartId, QT_OBJ_PREFIX + "MSNR_");

      for(int tf = TF_IDX_W1; tf < QT_MTF_COUNT; tf++)
        {
         if(!prof.allowPOITF[tf])
            continue;

         int cnt = MathMin(8, msnr.GetLevelCount(tf)); // Top 8 nearest per allowed TF for visual clarity
         for(int i = 0; i < cnt; i++)
           {
            SMSNRLevel lvl;
            if(!msnr.GetLevel(tf, i, lvl))
               continue;

            color clr = m_cfg.colMSNRTouchedUsed;
            ENUM_LINE_STYLE st = STYLE_DOT;
            int width = 1;

            if(lvl.IsFreshForEntry(2))
              {
               width = (tf <= TF_IDX_H4 ? 2 : 1);
               st    = (tf <= TF_IDX_H1 ? STYLE_SOLID : STYLE_DASH);
               if(lvl.type == POI_QM_BULL || lvl.type == POI_QM_BEAR)
                  clr = m_cfg.colMSNRQmFresh;
               else if(lvl.type == POI_RBS || lvl.type == POI_SBR)
                  clr = m_cfg.colMSNRFlipFresh;
               else if(lvl.direction == BIAS_BULL)
                  clr = m_cfg.colMSNRFreshSupport;
               else
                  clr = m_cfg.colMSNRFreshResistance;
              }

            string objName = QT_OBJ_PREFIX + "MSNR_" + lvl.id;
            string lbl     = StringFormat("[%s] %s (%s) %.2f",
                                          QTTfIndexToString(tf),
                                          QTPOITypeToString(lvl.type),
                                          QTPOIStatusToString(lvl.status),
                                          lvl.price);
            DrawLevelLine(objName, lvl.activeFromTime, nowServer, lvl.price, clr, st, width, lbl);
           }
        }
     }

   void              RenderICTObjects(CICTEngine &ict,
                                      const SBiasState &biasState,
                                      const STradeProfileSpec &prof,
                                      const datetime nowServer) const
     {
      ObjectsDeleteAll(m_chartId, QT_OBJ_PREFIX + "ICT_");

      // 1. Draw Active EQH / EQL & Major Unswept Pools
      int pCnt = MathMin(15, ict.GetPoolCount());
      for(int i = 0; i < pCnt; i++)
        {
         SLiquidityPool p;
         if(!ict.GetPool(i, p))
            continue;
         if(p.isBroken)
            continue;
         if(p.type != LIQ_POOL_EQH && p.type != LIQ_POOL_EQL &&
            p.type != LIQ_POOL_PDH && p.type != LIQ_POOL_PDL)
            continue;

         string name = QT_OBJ_PREFIX + "ICT_POOL_" + p.id;
         string tip  = StringFormat("%s (%s) %.2f [%s]",
                                    QTLiqPoolTypeToString(p.type),
                                    QTTfIndexToString(p.tfIdx),
                                    p.price,
                                    (p.isSwept ? "SWEPT" : "UNSWEPT"));
         DrawLevelLine(name,
                       p.formedTime,
                       nowServer,
                       p.price,
                       m_cfg.colEqPool,
                       (p.isSwept ? STYLE_DOT : STYLE_DASHDOT),
                       1,
                       tip);
        }

      // 2. Draw Recent Tradable FVGs on Entry & Trigger TFs
      int fvgTfs[2] = { prof.triggerTfIdx, prof.entryTfIdx };
      for(int k = 0; k < 2; k++)
        {
         int tf = fvgTfs[k];
         if(k == 1 && fvgTfs[1] == fvgTfs[0])
            continue;
         int fCnt = MathMin(5, ict.GetFVGCount(tf));
         for(int i = 0; i < fCnt; i++)
           {
            SFVGZone f;
            if(!ict.GetFVG(tf, i, f) || !f.IsTradable())
               continue;

            string fName = QT_OBJ_PREFIX + "ICT_FVG_" + f.id;
            string fTip  = StringFormat("%s FVG (%s) [%.2f - %.2f] CE:%.2f",
                                        QTBiasToString(f.direction),
                                        QTTfIndexToString(tf),
                                        f.lowEdge,
                                        f.highEdge,
                                        f.ce);
            DrawRectZone(fName,
                         f.bar2Time,
                         nowServer,
                         f.highEdge,
                         f.lowEdge,
                         (f.direction == BIAS_BULL ? m_cfg.colFvgBull : m_cfg.colFvgBear),
                         fTip);
           }
        }

      // 3. Draw Primary DOL Objective Line
      if(biasState.bullDOL.valid && biasState.allowBuy)
        {
         DrawLevelLine(QT_OBJ_PREFIX + "ICT_DOL_BULL",
                       nowServer - 12 * 3600,
                       nowServer,
                       biasState.bullDOL.price,
                       m_cfg.colDolLine,
                       STYLE_SOLID,
                       2,
                       "BUY DOL: " + biasState.bullDOL.label);
        }
      if(biasState.bearDOL.valid && biasState.allowSell)
        {
         DrawLevelLine(QT_OBJ_PREFIX + "ICT_DOL_BEAR",
                       nowServer - 12 * 3600,
                       nowServer,
                       biasState.bearDOL.price,
                       m_cfg.colDolLine,
                       STYLE_SOLID,
                       2,
                       "SELL DOL: " + biasState.bearDOL.label);
        }
     }

public:
                     CEAChartVisual()
     {
      m_chartId         = 0;
      m_symbol          = QT_TARGET_SYMBOL;
      m_lastObjUpdateM5 = 0;
      m_cfg.SetDefaults();
     }

   void              Init(const long chartId, const string symbol, const SEAVisualConfig &cfg)
     {
      m_chartId         = chartId;
      m_symbol          = (StringLen(symbol) > 0 ? symbol : _Symbol);
      m_cfg             = cfg;
      m_lastObjUpdateM5 = 0;
      m_qtVis.Init(chartId, m_symbol, m_cfg.qtVisCfg);
     }

   void              ClearAll() const
     {
      m_qtVis.ClearAll();
      ObjectsDeleteAll(m_chartId, QT_OBJ_PREFIX);
      Comment("");
      ChartRedraw(m_chartId);
     }

   //+------------------------------------------------------------------+
   //| Render All Chart Objects & On-Chart Dashboard                    |
   //+------------------------------------------------------------------+
   void              Render(CQTTimeEngine &timeEngine,
                            const QTState &qtState,
                            CMSNREngine &msnr,
                            CICTEngine &ict,
                            const SBiasState &biasState,
                            const STradeProfileSpec &prof,
                            CSetupEngine &setupEngine,
                            const bool isSignalOnlyMode,
                            const bool isNewsBlocked,
                            const string newsReason,
                            const string riskStatusText,
                            const bool forceRedraw = false)
     {
      if(!m_cfg.enableVisuals)
         return;

      if(m_cfg.showQTBoxesAndOpens)
         m_qtVis.Render(timeEngine, qtState.serverTime, forceRedraw);

      datetime curM5 = iTime(m_symbol, PERIOD_M5, 0);
      if(forceRedraw || curM5 != m_lastObjUpdateM5)
        {
         m_lastObjUpdateM5 = curM5;
         if(m_cfg.showMSNRLevels)
            RenderMSNRLevels(msnr, prof, qtState.serverTime);
         if(m_cfg.showICTObjects)
            RenderICTObjects(ict, biasState, prof, qtState.serverTime);
        }

      if(m_cfg.showDashboard)
        {
         SSetupTracker buyTr  = setupEngine.GetBuySetup();
         SSetupTracker sellTr = setupEngine.GetSellSetup();

         string d = "";
         d += "==================================================================\n";
         d += StringFormat("  EA QT-MSNR-ICT v%s | Symbol: %s | Mode: %s | Profile: %s\n",
                           QT_EA_VERSION,
                           m_symbol,
                           (isSignalOnlyMode ? "SIGNAL-ONLY (Fase 6)" : "LIVE/DEMO EXEC (Fase 7)"),
                           QTProfileToString(prof.profile));
         d += "==================================================================\n";
         d += StringFormat("  NY Time     : %s (%s) | Daye Date: %04d-%02d-%02d (%s)\n",
                           TimeToString(qtState.nyTime, TIME_DATE | TIME_SECONDS),
                           (qtState.isUsDst ? "EDT" : "EST"),
                           qtState.dayeYear, qtState.dayeMonth, qtState.dayeDay,
                           QTDayOfWeekToString(qtState.dayeDayOfWeek));
         d += StringFormat("  QT Cycles   : Year=%s | Month=%s | Week=%s | Day=%s (%s) | 90m=%s (%dm)\n",
                           QTQuarterToString(qtState.yearQ),
                           QTQuarterToString(qtState.monthQ),
                           QTQuarterToString(qtState.weekQ),
                           QTQuarterToString(qtState.dayQ),
                           QTSessionToString(qtState.session),
                           QTQuarterToString(qtState.q90),
                           qtState.minuteIn90mBlock);
         d += StringFormat("  True Opens  : TYO=%s | TMO=%s | TWO=%s | TDO=%s | TSO=%s\n",
                           (qtState.trueOpens.yearOpen.valid    ? DoubleToString(qtState.trueOpens.yearOpen.price, 2)    : "N/A"),
                           (qtState.trueOpens.monthOpen.valid   ? DoubleToString(qtState.trueOpens.monthOpen.price, 2)   : "N/A"),
                           (qtState.trueOpens.weekOpen.valid    ? DoubleToString(qtState.trueOpens.weekOpen.price, 2)    : "Wait"),
                           (qtState.trueOpens.dayOpen.valid     ? DoubleToString(qtState.trueOpens.dayOpen.price, 2)     : "Wait"),
                           (qtState.trueOpens.sessionOpen.valid ? DoubleToString(qtState.trueOpens.sessionOpen.price, 2) : "Wait"));
         d += "------------------------------------------------------------------\n";
         d += StringFormat("  Gates       : Time=%s | News=%s | Risk=%s\n",
                           (qtState.isTimeAllowed ? "ALLOWED" : "BLOCKED"),
                           (isNewsBlocked ? "BLOCKED (" + newsReason + ")" : "CLEAR"),
                           riskStatusText);
         d += StringFormat("  MTF Bias    : W1=%s | D1=%s | H4=%s -> BuyGate=%s | SellGate=%s\n",
                           QTBiasToString(biasState.biasW1),
                           QTBiasToString(biasState.biasD1),
                           QTBiasToString(biasState.biasH4),
                           (biasState.allowBuy  ? "OPEN" : "LOCKED"),
                           (biasState.allowSell ? "OPEN" : "LOCKED"));
         d += StringFormat("  DOL Targets : Bull DOL=%s (%.2f) | Bear DOL=%s (%.2f)\n",
                           (biasState.bullDOL.valid ? biasState.bullDOL.label : "None"),
                           biasState.bullDOL.price,
                           (biasState.bearDOL.valid ? biasState.bearDOL.label : "None"),
                           biasState.bearDOL.price);
         d += "------------------------------------------------------------------\n";
         d += StringFormat("  BUY Setup   : State=%s | POI=%s %s (%.2f) | Refined=%s | Score=%d\n",
                           QTSetupStateToString(buyTr.state),
                           QTTfIndexToString(buyTr.anchorPOI.tfIdx),
                           QTPOITypeToString(buyTr.anchorPOI.type),
                           buyTr.anchorPOI.price,
                           (buyTr.hasRefinedPOI ? QTTfIndexToString(buyTr.refinedPOI.tfIdx) + " " + DoubleToString(buyTr.refinedPOI.price, 2) : "No"),
                           buyTr.score.totalScore);
         d += StringFormat("  SELL Setup  : State=%s | POI=%s %s (%.2f) | Refined=%s | Score=%d\n",
                           QTSetupStateToString(sellTr.state),
                           QTTfIndexToString(sellTr.anchorPOI.tfIdx),
                           QTPOITypeToString(sellTr.anchorPOI.type),
                           sellTr.anchorPOI.price,
                           (sellTr.hasRefinedPOI ? QTTfIndexToString(sellTr.refinedPOI.tfIdx) + " " + DoubleToString(sellTr.refinedPOI.price, 2) : "No"),
                           sellTr.score.totalScore);
         d += "==================================================================\n";

         Comment(d);
        }

      ChartRedraw(m_chartId);
     }
  };

#endif // QT_VISUAL_MQH
//+------------------------------------------------------------------+
