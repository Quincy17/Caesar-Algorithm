//+------------------------------------------------------------------+
//| QT_Visualizer.mqh                                                |
//| Fase 1 - Quarterly Theory Chart Visualizer (Boxes & True Opens)  |
//| Place in: MQL5/Include/QT/QT_Visualizer.mqh                      |
//+------------------------------------------------------------------+
#ifndef QT_VISUALIZER_MQH
#define QT_VISUALIZER_MQH

#include "QT_Time.mqh"

#define QT_VIS_PREFIX "QTVIS_"

struct SQTVisualConfig
  {
   bool  showDayBoundaries;     // Vertical line at 18:00 NY (Daye day rollover)
   bool  showSessionBoxes;      // Shaded rectangle for Asia Q1, London Q2, NY AM Q3, NY PM Q4
   bool  show90mDividers;       // Dotted vertical lines for Q1..Q4 90-minute blocks
   bool  showTrueYearOpen;      // Horizontal ray/segment for True Year Open
   bool  showTrueMonthOpen;     // Horizontal ray/segment for True Month Open
   bool  showTrueWeekOpen;      // Horizontal segment for True Week Open (Mon 18:00 NY)
   bool  showTrueDayOpen;       // Horizontal segment for True Day Open (00:00 NY)
   bool  showTrueSessionOpen;   // Horizontal segment for True Session Opens (19:30, 01:30, 07:30, 13:30 NY)
   bool  showDashboardComment;  // Display live QTState summary in top-left chart comment
   int   lookbackDays;          // Number of historical Daye days to draw (default 7)

   // Colors
   color colAsiaBox;
   color colLondonBox;
   color colNyAmBox;
   color colNyPmBox;
   color colDayBoundary;
   color col90mDivider;
   color colTrueYearOpen;
   color colTrueMonthOpen;
   color colTrueWeekOpen;
   color colTrueDayOpen;
   color colTrueSessionOpen;

   void SetDefaults()
     {
      showDayBoundaries    = true;
      showSessionBoxes     = true;
      show90mDividers      = true;
      showTrueYearOpen     = true;
      showTrueMonthOpen    = true;
      showTrueWeekOpen     = true;
      showTrueDayOpen      = true;
      showTrueSessionOpen  = true;
      showDashboardComment = true;
      lookbackDays         = 7;

      colAsiaBox           = clrDarkSlateGray;
      colLondonBox         = clrMidnightBlue;
      colNyAmBox           = clrIndigo;
      colNyPmBox           = clrMaroon;
      colDayBoundary       = clrSilver;
      col90mDivider        = clrDimGray;
      colTrueYearOpen      = clrGold;
      colTrueMonthOpen     = clrMagenta;
      colTrueWeekOpen      = clrDodgerBlue;
      colTrueDayOpen       = clrLime;
      colTrueSessionOpen   = clrOrange;
     }
  };

//+------------------------------------------------------------------+
//| CQTVisualizer Class                                              |
//+------------------------------------------------------------------+
class CQTVisualizer
  {
private:
   long              m_chartId;
   string            m_symbol;
   SQTVisualConfig   m_vcfg;
   datetime          m_lastDrawnM5Bar;

   //--- Compute high and low of M5 bars in [startServer, endServer)
   bool              GetRangeHighLow(const datetime startServer,
                                     const datetime endServer,
                                     double &outHigh,
                                     double &outLow) const
     {
      MqlRates rates[];
      int copied = CopyRates(m_symbol, PERIOD_M5, startServer, endServer, rates);
      if(copied <= 0)
         return false;

      outHigh = -DBL_MAX;
      outLow  =  DBL_MAX;
      int validCount = 0;

      for(int i = 0; i < copied; i++)
        {
         if(rates[i].time < startServer || rates[i].time >= endServer)
            continue;
         if(rates[i].high > outHigh) outHigh = rates[i].high;
         if(rates[i].low  < outLow)  outLow  = rates[i].low;
         validCount++;
        }
      return (validCount > 0 && outHigh >= outLow);
     }

   //--- Draw or update a trendline segment (used for True Open horizontal lines)
   void              DrawHLineSegment(const string name,
                                      const datetime t1,
                                      const datetime t2,
                                      const double price,
                                      const color clr,
                                      const ENUM_LINE_STYLE style,
                                      const int width,
                                      const string tooltipText) const
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
      ObjectSetString(m_chartId,  name, OBJPROP_TOOLTIP, tooltipText);

      // Right-edge text label
      string lblName = name + "_LBL";
      if(ObjectFind(m_chartId, lblName) < 0)
         ObjectCreate(m_chartId, lblName, OBJ_TEXT, 0, t2, price);
      else
         ObjectMove(m_chartId, lblName, 0, t2, price);

      ObjectSetString(m_chartId,  lblName, OBJPROP_TEXT, " " + tooltipText);
      ObjectSetString(m_chartId,  lblName, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(m_chartId, lblName, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(m_chartId, lblName, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, lblName, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(m_chartId, lblName, OBJPROP_SELECTABLE, false);
     }

   //--- Draw or update a vertical line
   void              DrawVLine(const string name,
                               const datetime tServer,
                               const color clr,
                               const ENUM_LINE_STYLE style,
                               const int width,
                               const string tooltipText) const
     {
      if(tServer <= 0)
         return;

      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_VLINE, 0, tServer, 0.0);
      else
         ObjectMove(m_chartId, name, 0, tServer, 0.0);

      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, style);
      ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, width);
      ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
      ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(m_chartId,  name, OBJPROP_TOOLTIP, tooltipText);
     }

   //--- Draw or update a filled session rectangle
   void              DrawBox(const string name,
                             const datetime t1,
                             const datetime t2,
                             const double highPrice,
                             const double lowPrice,
                             const color clr,
                             const string tooltipText) const
     {
      if(t1 <= 0 || t2 <= t1 || highPrice < lowPrice)
         return;

      if(ObjectFind(m_chartId, name) < 0)
         ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, t1, highPrice, t2, lowPrice);
      else
        {
         ObjectMove(m_chartId, name, 0, t1, highPrice);
         ObjectMove(m_chartId, name, 1, t2, lowPrice);
        }

      ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);
      ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
      ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(m_chartId,  name, OBJPROP_TOOLTIP, tooltipText);
     }

public:
                     CQTVisualizer()
     {
      m_chartId        = 0;
      m_symbol         = QT_TARGET_SYMBOL;
      m_lastDrawnM5Bar = 0;
      m_vcfg.SetDefaults();
     }

   void              Init(const long chartId, const string symbol, const SQTVisualConfig &vcfg)
     {
      m_chartId        = chartId;
      m_symbol         = (StringLen(symbol) > 0 ? symbol : _Symbol);
      m_vcfg           = vcfg;
      m_lastDrawnM5Bar = 0;
     }

   void              ClearAll() const
     {
      ObjectsDeleteAll(m_chartId, QT_VIS_PREFIX);
      if(m_vcfg.showDashboardComment)
         Comment("");
      ChartRedraw(m_chartId);
     }

   //+------------------------------------------------------------------+
   //| Render Historical & Active Daye Days, Sessions, 90m & True Opens |
   //+------------------------------------------------------------------+
   void              Render(CQTTimeEngine &engine, const datetime nowServer, const bool forceRedraw = false)
     {
      QTState stNow;
      engine.Evaluate(nowServer, stNow, true);

      if(m_vcfg.showDashboardComment)
         RenderDashboardComment(engine, stNow);

      datetime curM5Bar = iTime(m_symbol, PERIOD_M5, 0);
      if(!forceRedraw && curM5Bar > 0 && curM5Bar == m_lastDrawnM5Bar)
         return;
      m_lastDrawnM5Bar = curM5Bar;

      int days = MathMax(1, m_vcfg.lookbackDays);

      // Iterate over the last N Daye days up to today
      for(int d = days - 1; d >= 0; d--)
        {
         datetime dayStartNY = (datetime)((long)stNow.dayeDayStartNY - (long)d * 86400);
         datetime dayMidNY   = (datetime)((long)dayStartNY + 12 * 3600);
         datetime dayMidSrv  = engine.NYToServer(dayMidNY);

         QTState stDay;
         engine.Evaluate(dayMidSrv, stDay, false);

         // Skip weekends (Saturday/Sunday Daye day)
         if(stDay.dayeDayOfWeek == 0 || stDay.dayeDayOfWeek == 6)
            continue;

         string dayTag = StringFormat("%04d%02d%02d", stDay.dayeYear, stDay.dayeMonth, stDay.dayeDay);
         datetime dayStartSrv = engine.NYToServer(dayStartNY);
         datetime dayEndNY    = (datetime)((long)dayStartNY + 24 * 3600);
         datetime dayEndSrv   = engine.NYToServer(dayEndNY);
         datetime clampDayEnd = (dayEndSrv > nowServer ? nowServer : dayEndSrv);

         // 1. Daye Day Boundary (18:00 NY)
         if(m_vcfg.showDayBoundaries)
           {
            string vName = QT_VIS_PREFIX + "DAY_" + dayTag;
            string vTip  = StringFormat("Daye Day %s (%s %s) [18:00 NY]",
                                        dayTag,
                                        QTDayOfWeekToString(stDay.dayeDayOfWeek),
                                        QTQuarterToString(stDay.weekQ));
            DrawVLine(vName, dayStartSrv, m_vcfg.colDayBoundary, STYLE_DASH, 1, vTip);
           }

         // 2. True Day Open (00:00 NY -> 18:00 NY)
         if(m_vcfg.showTrueDayOpen)
           {
            datetime tdoNY  = (datetime)((long)dayStartNY + 6 * 3600); // 00:00 NY
            if(stNow.nyTime >= tdoNY)
              {
               datetime sampleSrv = engine.NYToServer((datetime)((long)tdoNY + 60));
               QTState stTdo;
               engine.Evaluate(sampleSrv, stTdo, true);
               if(stTdo.trueOpens.dayOpen.valid && clampDayEnd > stTdo.trueOpens.dayOpen.time_server)
                 {
                  string tdoName = QT_VIS_PREFIX + "TDO_" + dayTag;
                  string tdoLbl  = StringFormat("TDO %.2f", stTdo.trueOpens.dayOpen.price);
                  DrawHLineSegment(tdoName,
                                   stTdo.trueOpens.dayOpen.time_server,
                                   clampDayEnd,
                                   stTdo.trueOpens.dayOpen.price,
                                   m_vcfg.colTrueDayOpen,
                                   STYLE_SOLID,
                                   2,
                                   tdoLbl);
                 }
              }
           }

         // 3. Four 6-Hour Sessions (Asia Q1, London Q2, NY AM Q3, NY PM Q4)
         for(int s = 0; s < 4; s++)
           {
            datetime sesStartNY  = (datetime)((long)dayStartNY + (long)s * 6 * 3600);
            datetime sesEndNY    = (datetime)((long)sesStartNY + 6 * 3600);
            if(sesStartNY > stNow.nyTime)
               continue;

            datetime sesStartSrv = engine.NYToServer(sesStartNY);
            datetime sesEndSrv   = engine.NYToServer(sesEndNY);
            datetime clampSesEnd = (sesEndSrv > nowServer ? nowServer : sesEndSrv);

            ENUM_QT_SESSION sesEnum = (ENUM_QT_SESSION)(s + 1);
            ENUM_QT_QUARTER sesQ    = (ENUM_QT_QUARTER)(s + 1);
            string sesTag = StringFormat("%s_S%d", dayTag, s + 1);

            if(m_vcfg.showSessionBoxes)
              {
               double hi = 0.0, lo = 0.0;
               if(GetRangeHighLow(sesStartSrv, clampSesEnd, hi, lo))
                 {
                  color boxCol = m_vcfg.colAsiaBox;
                  if(sesEnum == QT_SESSION_LONDON) boxCol = m_vcfg.colLondonBox;
                  if(sesEnum == QT_SESSION_NY_AM)  boxCol = m_vcfg.colNyAmBox;
                  if(sesEnum == QT_SESSION_NY_PM)  boxCol = m_vcfg.colNyPmBox;

                  string boxName = QT_VIS_PREFIX + "BOX_" + sesTag;
                  string boxTip  = StringFormat("%s (%s) [%s - %s NY] H:%.2f L:%.2f",
                                                QTSessionToString(sesEnum),
                                                QTQuarterToString(sesQ),
                                                TimeToString(sesStartNY, TIME_MINUTES),
                                                TimeToString(sesEndNY, TIME_MINUTES),
                                                hi, lo);
                  DrawBox(boxName, sesStartSrv, clampSesEnd, hi, lo, boxCol, boxTip);
                 }
              }

            // 4. 90-Minute Dividers (Q2=+90m, Q3=+180m, Q4=+270m)
            if(m_vcfg.show90mDividers && Period() <= PERIOD_M15)
              {
               for(int b = 1; b < 4; b++)
                 {
                  datetime bStartNY  = (datetime)((long)sesStartNY + (long)b * 90 * 60);
                  if(bStartNY > stNow.nyTime)
                     continue;
                  datetime bStartSrv = engine.NYToServer(bStartNY);
                  string bName = QT_VIS_PREFIX + StringFormat("Q90_%s_B%d", sesTag, b + 1);
                  string bTip  = StringFormat("%s 90m Q%d (%s NY)",
                                              QTSessionToString(sesEnum),
                                              b + 1,
                                              TimeToString(bStartNY, TIME_MINUTES));
                  DrawVLine(bName, bStartSrv, m_vcfg.col90mDivider, STYLE_DOT, 1, bTip);
                 }
              }

            // 5. True Session Open (sesStartNY + 90m: 19:30, 01:30, 07:30, 13:30 NY)
            if(m_vcfg.showTrueSessionOpen)
              {
               datetime tsoNY = (datetime)((long)sesStartNY + 90 * 60);
               if(stNow.nyTime >= tsoNY)
                 {
                  datetime sampleSrv = engine.NYToServer((datetime)((long)tsoNY + 60));
                  QTState stTso;
                  engine.Evaluate(sampleSrv, stTso, true);
                  if(stTso.trueOpens.sessionOpen.valid && clampSesEnd > stTso.trueOpens.sessionOpen.time_server)
                    {
                     string tsoName = QT_VIS_PREFIX + "TSO_" + sesTag;
                     string tsoLbl  = StringFormat("TSO(%s) %.2f",
                                                   QTSessionToString(sesEnum),
                                                   stTso.trueOpens.sessionOpen.price);
                     DrawHLineSegment(tsoName,
                                      stTso.trueOpens.sessionOpen.time_server,
                                      clampSesEnd,
                                      stTso.trueOpens.sessionOpen.price,
                                      m_vcfg.colTrueSessionOpen,
                                      STYLE_DOT,
                                      1,
                                      tsoLbl);
                    }
                 }
              }
           }
        }

      // 6. Active True Week Open, True Month Open, True Year Open extending to nowServer
      if(m_vcfg.showTrueWeekOpen && stNow.trueOpens.weekOpen.valid)
        {
         DrawHLineSegment(QT_VIS_PREFIX + "TWO_ACTIVE",
                          stNow.trueOpens.weekOpen.time_server,
                          nowServer,
                          stNow.trueOpens.weekOpen.price,
                          m_vcfg.colTrueWeekOpen,
                          STYLE_SOLID,
                          2,
                          StringFormat("TWO %.2f", stNow.trueOpens.weekOpen.price));
        }

      if(m_vcfg.showTrueMonthOpen && stNow.trueOpens.monthOpen.valid)
        {
         DrawHLineSegment(QT_VIS_PREFIX + "TMO_ACTIVE",
                          stNow.trueOpens.monthOpen.time_server,
                          nowServer,
                          stNow.trueOpens.monthOpen.price,
                          m_vcfg.colTrueMonthOpen,
                          STYLE_DASH,
                          2,
                          StringFormat("TMO %.2f", stNow.trueOpens.monthOpen.price));
        }

      if(m_vcfg.showTrueYearOpen && stNow.trueOpens.yearOpen.valid)
        {
         DrawHLineSegment(QT_VIS_PREFIX + "TYO_ACTIVE",
                          stNow.trueOpens.yearOpen.time_server,
                          nowServer,
                          stNow.trueOpens.yearOpen.price,
                          m_vcfg.colTrueYearOpen,
                          STYLE_DASH,
                          2,
                          StringFormat("TYO %.2f", stNow.trueOpens.yearOpen.price));
        }

      ChartRedraw(m_chartId);
     }

   //+------------------------------------------------------------------+
   //| Render On-Chart Status Comment (Dashboard Preview for Fase 1)    |
   //+------------------------------------------------------------------+
   void              RenderDashboardComment(CQTTimeEngine &engine, const QTState &st) const
     {
      string d1Report = "";
      engine.VerifyBrokerD1OpenIs17NY(d1Report);

      string s = "";
      s += "========================================================\n";
      s += "   EA QT-MSNR-ICT (MQL5) | Fase 1: Time Engine & QT\n";
      s += "========================================================\n";
      s += StringFormat(" Symbol          : %s\n", m_symbol);
      s += StringFormat(" Server Time     : %s\n", TimeToString(st.serverTime, TIME_DATE | TIME_SECONDS));
      s += StringFormat(" New York Time   : %s (%s, Offset %+.1fh)\n",
                        TimeToString(st.nyTime, TIME_DATE | TIME_SECONDS),
                        (st.isUsDst ? "EDT/DST" : "EST/Std"),
                        (double)st.nyOffsetFromServer / 3600.0);
      s += StringFormat(" Daye Trading Day: %04d-%02d-%02d (%s)\n",
                        st.dayeYear, st.dayeMonth, st.dayeDay,
                        QTDayOfWeekToString(st.dayeDayOfWeek));
      s += StringFormat(" Broker D1 Check : %s\n", d1Report);
      s += "--------------------------------------------------------\n";
      s += StringFormat(" Quarterly Cycles: Year=%s | Month=%s | Week=%s | Day=%s (%s) | 90m=%s (%dm/90m)\n",
                        QTQuarterToString(st.yearQ),
                        QTQuarterToString(st.monthQ),
                        QTQuarterToString(st.weekQ),
                        QTQuarterToString(st.dayQ),
                        QTSessionToString(st.session),
                        QTQuarterToString(st.q90),
                        st.minuteIn90mBlock);
      s += "--------------------------------------------------------\n";
      s += StringFormat(" True Year Open  : %s @ %s NY\n",
                        (st.trueOpens.yearOpen.valid ? DoubleToString(st.trueOpens.yearOpen.price, 2) : "N/A"),
                        TimeToString(st.trueOpens.yearOpen.time_ny, TIME_DATE | TIME_MINUTES));
      s += StringFormat(" True Month Open : %s @ %s NY\n",
                        (st.trueOpens.monthOpen.valid ? DoubleToString(st.trueOpens.monthOpen.price, 2) : "N/A"),
                        TimeToString(st.trueOpens.monthOpen.time_ny, TIME_DATE | TIME_MINUTES));
      s += StringFormat(" True Week Open  : %s @ %s NY\n",
                        (st.trueOpens.weekOpen.valid ? DoubleToString(st.trueOpens.weekOpen.price, 2) : "Pending Mon 18:00"),
                        TimeToString(st.trueOpens.weekOpen.time_ny, TIME_DATE | TIME_MINUTES));
      s += StringFormat(" True Day Open   : %s @ %s NY\n",
                        (st.trueOpens.dayOpen.valid ? DoubleToString(st.trueOpens.dayOpen.price, 2) : "Pending 00:00 NY"),
                        TimeToString(st.trueOpens.dayOpen.time_ny, TIME_DATE | TIME_MINUTES));
      s += StringFormat(" True Sess Open  : %s @ %s NY\n",
                        (st.trueOpens.sessionOpen.valid ? DoubleToString(st.trueOpens.sessionOpen.price, 2) : "Pending Q2 90m"),
                        TimeToString(st.trueOpens.sessionOpen.time_ny, TIME_DATE | TIME_MINUTES));
      s += "--------------------------------------------------------\n";
      s += StringFormat(" Time Gate Allow : %s (Day:%s | Sess:%s | 90m:%s | FriCut:%s)\n",
                        (st.isTimeAllowed ? "ALLOWED" : "BLOCKED"),
                        (st.isDayAllowed ? "OK" : "NO"),
                        (st.isSessionAllowed ? "OK" : "NO"),
                        (st.isQ90Allowed ? "OK" : "NO"),
                        (st.isFridayCutoffPassed ? "YES-FLAT" : "NO"));
      s += "========================================================\n";

      Comment(s);
     }
  };

#endif // QT_VISUALIZER_MQH
//+------------------------------------------------------------------+
