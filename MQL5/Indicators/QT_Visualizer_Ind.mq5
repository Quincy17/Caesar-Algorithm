//+------------------------------------------------------------------+
//| QT_Visualizer_Ind.mq5                                            |
//| Fase 1 - Standalone Indicator for QT Time Engine & True Opens    |
//| Place in: MQL5/Indicators/QT_Visualizer_Ind.mq5                  |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.10"
#property strict
#property indicator_chart_window
#property indicator_plots 0

#include "../Include/QT/QT_Time.mqh"
#include "../Include/QT/QT_Visualizer.mqh"

//--- Input Parameters: Time Engine
input group "=== M1: QT Time Engine Settings ==="
input ENUM_TIME_CONV_MODE InpConvMode          = TIME_MODE_A_SERVER_MINUS_7; // Conversion Mode (A=-7h, B=GMT+DST)
input int                 InpModeAServerToNY   = -7;                         // Mode A: NY = Server + X hours
input int                 InpModeBServerGMT    = 0;                          // Mode B: Broker Standard GMT Offset
input ENUM_TRADE_PROFILE  InpProfilePreset     = PROFILE_INTRADAY;           // Time Gate Preset Profile
input int                 InpFridayCloseHourNY = 15;                         // Friday Flat Cutoff Hour (NY)
input int                 InpFridayCloseMinNY  = 0;                          // Friday Flat Cutoff Minute (NY)

//--- Input Parameters: Visualizer
input group "=== Fase 1: QT Visualizer Settings ==="
input int                 InpLookbackDays      = 7;                          // Days of History to Draw
input bool                InpShowDayBoundaries = true;                       // Show 18:00 NY Daye Day Boundaries
input bool                InpShowSessionBoxes  = true;                       // Show Session Boxes (Asia/Lon/NY)
input bool                InpShow90mDividers   = true;                       // Show 90-Minute Cycle Dividers
input bool                InpShowTrueYearOpen  = true;                       // Show True Year Open (1st Mon Apr)
input bool                InpShowTrueMonthOpen = true;                       // Show True Month Open (2nd Mon)
input bool                InpShowTrueWeekOpen  = true;                       // Show True Week Open (Mon 18:00 NY)
input bool                InpShowTrueDayOpen   = true;                       // Show True Day Open (00:00 NY)
input bool                InpShowTrueSessOpen  = true;                       // Show True Session Opens
input bool                InpShowDashboard     = true;                       // Show Top-Left QT Status Dashboard

CQTTimeEngine g_timeEngine;
CQTVisualizer g_visualizer;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   SQTTimeConfig tcfg;
   tcfg.SetDefaults();
   tcfg.convMode             = InpConvMode;
   tcfg.modeAServerToNYHours = InpModeAServerToNY;
   tcfg.modeBServerGmtHours  = InpModeBServerGMT;
   tcfg.ApplyProfilePreset(InpProfilePreset);
   tcfg.fridayCloseHourNY    = InpFridayCloseHourNY;
   tcfg.fridayCloseMinNY     = InpFridayCloseMinNY;

   g_timeEngine.Init(_Symbol, tcfg);

   SQTVisualConfig vcfg;
   vcfg.SetDefaults();
   vcfg.lookbackDays         = InpLookbackDays;
   vcfg.showDayBoundaries    = InpShowDayBoundaries;
   vcfg.showSessionBoxes     = InpShowSessionBoxes;
   vcfg.show90mDividers      = InpShow90mDividers;
   vcfg.showTrueYearOpen     = InpShowTrueYearOpen;
   vcfg.showTrueMonthOpen    = InpShowTrueMonthOpen;
   vcfg.showTrueWeekOpen     = InpShowTrueWeekOpen;
   vcfg.showTrueDayOpen      = InpShowTrueDayOpen;
   vcfg.showTrueSessionOpen  = InpShowTrueSessOpen;
   vcfg.showDashboardComment = InpShowDashboard;

   g_visualizer.Init(ChartID(), _Symbol, vcfg);

   string d1Report = "";
   g_timeEngine.VerifyBrokerD1OpenIs17NY(d1Report);
   Print("[QT_Visualizer_Ind] ", d1Report);

   EventSetTimer(1);
   g_visualizer.Render(g_timeEngine, TimeCurrent(), true);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_visualizer.ClearAll();
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   bool forceRedraw = (prev_calculated == 0);
   g_visualizer.Render(g_timeEngine, TimeCurrent(), forceRedraw);
   return(rates_total);
  }

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   g_visualizer.Render(g_timeEngine, TimeCurrent(), false);
  }
//+------------------------------------------------------------------+
