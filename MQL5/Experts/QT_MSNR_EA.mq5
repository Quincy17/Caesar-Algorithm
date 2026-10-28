//+------------------------------------------------------------------+
//| QT_MSNR_EA.mq5                                                   |
//| Main Expert Advisor: Quarterly Theory + MSNR + ICT (MQL5)        |
//| Place in: MQL5/Experts/QT_MSNR_EA.mq5                            |
//|                                                                  |
//| Architecture (M1..M12):                                          |
//|  - M1  QT_Time.mqh       : NY Time, DST, Quarterly Cycles, Opens |
//|  - M2  MTF_Data.mqh      : Closed-bar cache W1..M5 & ATR(14)     |
//|  - M3  Swings.mqh        : Fractal Wick & Body Swings (no repaint|
//|  - M4  MSNR_Levels.mqh   : Classic A/V, RBS/SBR, QM (W1..M5)     |
//|  - M5  ICT_Engine.mqh    : Pools, EQH/EQL, Sweep, MSS, FVG       |
//|  - M6  Bias.mqh          : Multi-TF Storyline, Bias & DOL        |
//|  - M7  Setup.mqh         : S0..S6 State Machine & Confluence     |
//|  - M8  Risk.mqh, Exec.mqh: Lot sizing, Circuit Breakers, CTrade  |
//|  - M9  Visual.mqh, Logger: Chart Objects, Dashboard & CSV Logs   |
//|  - M10 TradeProfile.mqh  : Scalping / Intraday / Swing Profiles  |
//|  - M11 News.mqh          : Forex Factory Live JSON / Tester CSV  |
//|  - M12 Friday Flat       : Mandatory Friday 15:00 NY Flat        |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.10"
#property strict

#include "../Include/QT/Defines.mqh"
#include "../Include/QT/QT_Time.mqh"
#include "../Include/QT/MTF_Data.mqh"
#include "../Include/QT/Swings.mqh"
#include "../Include/QT/MSNR_Levels.mqh"
#include "../Include/QT/ICT_Engine.mqh"
#include "../Include/QT/TradeProfile.mqh"
#include "../Include/QT/Bias.mqh"
#include "../Include/QT/Setup.mqh"
#include "../Include/QT/Risk.mqh"
#include "../Include/QT/Exec.mqh"
#include "../Include/QT/Logger.mqh"
#include "../Include/QT/Visual.mqh"
#include "../Include/QT/News.mqh"

//+------------------------------------------------------------------+
//| Input Parameters (PRD Section 7 + v1.1 Additions)                |
//+------------------------------------------------------------------+
input group "=== 1. Trade Profile & Execution Mode ==="
input ENUM_TRADE_PROFILE  InpTradeProfile       = PROFILE_INTRADAY;           // Trade Profile (Scalping / Intraday / Swing)
input bool                InpSignalOnlyMode     = false;                      // Signal-Only Mode (Fase 6: True = No Orders)
input ENUM_BIAS_GATE_MODE InpBiasGateMode       = BIAS_GATE_STRICT;           // Multi-TF Bias Gate Mode (STRICT / MAJORITY)
input bool                InpUseW1Bias          = true;                       // Enable Weekly (W1) Bias
input bool                InpUseD1Bias          = true;                       // Enable Daily (D1) Bias
input bool                InpUseH4Bias          = true;                       // Enable H4 Bias
input bool                InpStrictBiasConfirm  = false;                      // Strict Complementary Bias Confirmation

input group "=== 2. M1: Quarterly Theory Time Engine ==="
input ENUM_TIME_CONV_MODE InpTimeConvMode       = TIME_MODE_A_SERVER_MINUS_7; // Server->NY Mode (A: -7h, B: GMT+DST)
input int                 InpModeAServerToNY    = -7;                         // Mode A: NY = Server + X hours (default -7)
input int                 InpModeBServerGMT     = 0;                          // Mode B: Broker Standard GMT Offset
input bool                InpOverrideProfileTime= false;                      // Override Profile Time Filter with Manual Toggles
input bool                InpAllowMonday        = false;                      // Manual: Allow Monday (Q1 Accumulation)
input bool                InpAllowTuesday       = true;                       // Manual: Allow Tuesday (Q2)
input bool                InpAllowWednesday     = true;                       // Manual: Allow Wednesday (Q3)
input bool                InpAllowThursday      = true;                       // Manual: Allow Thursday (Q4)
input bool                InpAllowFriday        = false;                      // Manual: Allow Friday (Q0 Out of Cycle)
input bool                InpAllowAsia          = false;                      // Manual: Allow Asia Session (18-24 NY Q1)
input bool                InpAllowLondon        = true;                       // Manual: Allow London Session (00-06 NY Q2)
input bool                InpAllowNyAm          = true;                       // Manual: Allow NY AM Session (06-12 NY Q3)
input bool                InpAllowNyPm          = false;                      // Manual: Allow NY PM Session (12-18 NY Q4)
input bool                InpAllow90mQ1         = false;                      // Manual: Allow 90m Block Q1
input bool                InpAllow90mQ2         = true;                       // Manual: Allow 90m Block Q2 (Sweep/Judas)
input bool                InpAllow90mQ3         = true;                       // Manual: Allow 90m Block Q3 (Distribution)
input bool                InpAllow90mQ4         = false;                      // Manual: Allow 90m Block Q4

input group "=== 3. M3 & M4: Swing & MSNR POI Settings ==="
input int                 InpSwingStrengthW1    = 2;                          // Fractal Strength N: W1
input int                 InpSwingStrengthD1    = 2;                          // Fractal Strength N: D1
input int                 InpSwingStrengthH4    = 2;                          // Fractal Strength N: H4
input int                 InpSwingStrengthH1    = 3;                          // Fractal Strength N: H1
input int                 InpSwingStrengthM15   = 2;                          // Fractal Strength N: M15
input int                 InpSwingStrengthM5    = 2;                          // Fractal Strength N: M5
input double              InpMSNRTouchAtrMult   = 0.05;                       // Touch Tolerance = max(spread, mult * ATR14)
input int                 InpMSNRMaxLevelsPerTF = 20;                         // Max Active Levels Kept per TF
input int                 InpMSNRMaxAgeBars     = 250;                        // Max Level Age in Bars per TF
input int                 InpMaxQMBodyBreak     = 2;                          // Max Body Breaks in QM Pattern
input bool                InpUseM15M5Refinement = true;                       // Enable M15/M5 POI Refinement for Precision Entry

input group "=== 4. M5: ICT Liquidity, Sweep, MSS & FVG ==="
input double              InpEqToleranceAtrMult = 0.10;                       // EQH/EQL Max Diff = mult * ATR(14)
input double              InpMinFvgAtrMult      = 0.15;                       // Min FVG Size = mult * ATR(14)
input bool                InpUseMSS             = true;                       // Require Market Structure Shift (MSS) after Sweep
input ENUM_PDH_SOURCE     InpPdhSource          = PDH_SOURCE_DAYE_18NY;       // PDH/PDL Boundary (Daye 18:00 NY / Broker D1)

input group "=== 5. M7: Setup, Entry & Confluence Score ==="
input int                 InpMinConfluenceScore = 6;                          // Minimum Confluence Score to Enter
input double              InpCustomMinRR        = 0.0;                        // Custom Min RR (0 = Use Profile Default)
input int                 InpMaxSetupBarsM5     = 36;                         // Max Setup Lifespan in M5 Bars (36 = 3h)
input ENUM_ENTRY_TYPE     InpEntryType          = ENTRY_FVG_CE;               // Entry Mode (FVG CE 50% / Proximal / Market MSS)
input double              InpSlBufferAtrM5      = 0.20;                       // SL Buffer = mult * ATR(M5) + Spread
input double              InpMaxSlAtrH1         = 2.50;                       // Skip Setup if SL > mult * ATR(H1)

input group "=== 6. M8 & M12: Risk, Management & Friday Flat ==="
input double              InpRiskPercent        = 0.50;                       // Risk % of Balance per Trade
input double              InpMaxDailyLossPct    = 2.00;                       // Max Daily Loss % Circuit Breaker
input double              InpMaxWeeklyLossPct   = 5.00;                       // Max Weekly Loss % Circuit Breaker
input int                 InpMaxTradesPerDay    = 2;                          // Max Trades per Daye Trading Day
input int                 InpMaxConsecLosses    = 3;                          // Pause Until Next Day after N Consecutive Losses
input int                 InpMaxSpreadPoints    = 50;                         // Max Allowed Spread (Points)
input bool                InpUseBreakEven1R     = true;                       // Move SL to Break-Even at +1R
input double              InpBeBufferPoints     = 5.0;                        // Break-Even Buffer (Points)
input bool                InpUsePartialTP1      = true;                       // Close 50% at Internal Liquidity TP1
input bool                InpUseTimeStop        = true;                       // Enforce Profile Duration Time Stop
input bool                InpFridayNoNewEntry   = true;                       // Block New Entries on Friday (Q0)
input int                 InpFridayCloseHourNY  = 15;                         // Friday Forced Flat Hour (NY Time, default 15)
input int                 InpFridayCloseMinNY   = 0;                          // Friday Forced Flat Minute (NY Time, default 0)

input group "=== 7. M11: Forex Factory / MT5 News Filter ==="
input bool                InpNewsEnabled        = true;                       // Enable High-Impact News Filter
input ENUM_NEWS_SOURCE    InpNewsLiveSource     = NEWS_LIVE_FF_JSON;          // Live Source (Forex Factory JSON / MT5 Calendar)
input int                 InpNewsPreHours       = 5;                          // Block Window Before News (Hours, default 5)
input int                 InpNewsPostHours      = 1;                          // Block Window After News (Hours, default 1)
input string              InpNewsCurrencies     = "USD";                      // Additional Currencies to Monitor
input int                 InpNewsRefreshMin     = 60;                         // Refresh Interval in Live Mode (Minutes)
input bool                InpNewsFailSafe       = true;                       // Block Entries if News Data Unavailable/Stale
input string              InpNewsCsvFile        = "news_high_impact.csv";     // Historical News CSV File (Common/Files)

input group "=== 8. M9: System, Magic Number, Visuals & CSV Logs ==="
input long                InpMagicNumber        = 20261001;                   // Base Magic Number (auto-offset per Profile)
input bool                InpEnableVisuals      = true;                       // Draw Chart Objects & Dashboard
input int                 InpVisualLookbackDays = 5;                          // Days of QT Boxes/Opens to Draw
input bool                InpEnableCsvLog       = true;                       // Write CSV Setup & Trade Journals
input string              InpForwardJournalCSV  = "QT_Forward_Journal.csv";   // Master Closed-Trade Forward Journal CSV
input bool                InpScreenshotOnEntry  = false;                      // Save Chart Screenshot on Entry

//+------------------------------------------------------------------+
//| Global Module Instances                                          |
//+------------------------------------------------------------------+
CQTTimeEngine     g_timeEngine;
CMTFDataManager   g_mtf;
CSwingEngine      g_swings;
CMSNREngine       g_msnr;
CICTEngine        g_ict;
STradeProfileSpec g_profileSpec;
CBiasEngine       g_bias;
CSetupEngine      g_setup;
CRiskManager      g_risk;
CExecutionEngine  g_exec;
CQTLogger         g_logger;
CEAChartVisual    g_visual;
CNewsFilter       g_news;

QTState           g_qtState;
SBiasState        g_biasState;
long              g_effectiveMagic = 20261001;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Unique magic number per profile instance (PRD 4.10)
   g_effectiveMagic = InpMagicNumber + (long)InpTradeProfile;

   // 1. Configure M10 Trade Profile
   g_profileSpec.Configure(InpTradeProfile,
                           InpBiasGateMode,
                           InpUseW1Bias,
                           InpUseD1Bias,
                           InpUseH4Bias,
                           InpCustomMinRR);

   // 2. Configure M1 Time Engine
   SQTTimeConfig tcfg;
   tcfg.SetDefaults();
   tcfg.convMode             = InpTimeConvMode;
   tcfg.modeAServerToNYHours = InpModeAServerToNY;
   tcfg.modeBServerGmtHours  = InpModeBServerGMT;
   tcfg.ApplyProfilePreset(InpTradeProfile);

   if(InpOverrideProfileTime)
     {
      tcfg.allowMonday    = InpAllowMonday;
      tcfg.allowTuesday   = InpAllowTuesday;
      tcfg.allowWednesday = InpAllowWednesday;
      tcfg.allowThursday  = InpAllowThursday;
      tcfg.allowFriday    = InpAllowFriday;
      tcfg.allowAsia      = InpAllowAsia;
      tcfg.allowLondon    = InpAllowLondon;
      tcfg.allowNyAm      = InpAllowNyAm;
      tcfg.allowNyPm      = InpAllowNyPm;
      tcfg.allow90mQ1     = InpAllow90mQ1;
      tcfg.allow90mQ2     = InpAllow90mQ2;
      tcfg.allow90mQ3     = InpAllow90mQ3;
      tcfg.allow90mQ4     = InpAllow90mQ4;
     }
   if(InpFridayNoNewEntry)
      tcfg.allowFriday = false;

   tcfg.fridayCloseHourNY = InpFridayCloseHourNY;
   tcfg.fridayCloseMinNY  = InpFridayCloseMinNY;
   g_timeEngine.Init(_Symbol, tcfg);

   // Verify Broker D1 Open = 17:00 NY
   string d1Verify = "";
   g_timeEngine.VerifyBrokerD1OpenIs17NY(d1Verify);
   Print("[QT_MSNR_EA] ", d1Verify);

   // 3. Configure M2 MTF Data Manager
   g_mtf.Init(_Symbol, 14);

   // 4. Configure M3 Swing Engine
   SSwingConfig scfg;
   scfg.SetDefaults();
   scfg.strength[TF_IDX_W1]  = InpSwingStrengthW1;
   scfg.strength[TF_IDX_D1]  = InpSwingStrengthD1;
   scfg.strength[TF_IDX_H4]  = InpSwingStrengthH4;
   scfg.strength[TF_IDX_H1]  = InpSwingStrengthH1;
   scfg.strength[TF_IDX_M15] = InpSwingStrengthM15;
   scfg.strength[TF_IDX_M5]  = InpSwingStrengthM5;
   g_swings.Init(scfg);

   // 5. Configure M4 MSNR Engine (including M15 & M5 for Intraday/Scalping)
   SMSNRConfig mcfg;
   mcfg.SetDefaults();
   mcfg.touchAtrMult         = InpMSNRTouchAtrMult;
   mcfg.maxActiveLevelsPerTF = InpMSNRMaxLevelsPerTF;
   mcfg.maxLevelAgeBars      = InpMSNRMaxAgeBars;
   mcfg.maxQMBodyBreak       = InpMaxQMBodyBreak;
   for(int i = 0; i < QT_MTF_COUNT; i++)
      mcfg.enableTF[i] = g_profileSpec.allowPOITF[i];
   // Ensure W1/D1/H4 are always enabled for HTF Bias & Roadblock detection
   mcfg.enableTF[TF_IDX_W1] = true;
   mcfg.enableTF[TF_IDX_D1] = true;
   mcfg.enableTF[TF_IDX_H4] = true;
   g_msnr.Init(mcfg);

   // 6. Configure M5 ICT Engine
   SICTConfig icfg;
   icfg.SetDefaults();
   icfg.eqToleranceAtrMult = InpEqToleranceAtrMult;
   icfg.minFvgAtrMult      = InpMinFvgAtrMult;
   icfg.useMSS             = InpUseMSS;
   icfg.pdhSource          = InpPdhSource;
   g_ict.Init(icfg);

   // 7. Configure M6 Bias Engine & M7 Setup Engine
   g_bias.Init(InpStrictBiasConfirm);

   SSetupConfig setCfg;
   setCfg.SetDefaults();
   setCfg.minConfluenceScore = InpMinConfluenceScore;
   setCfg.customMinRR        = InpCustomMinRR;
   setCfg.maxSetupBarsM5     = InpMaxSetupBarsM5;
   setCfg.entryType          = InpEntryType;
   setCfg.slBufferAtrMultM5  = InpSlBufferAtrM5;
   setCfg.maxSlAtrMultH1     = InpMaxSlAtrH1;
   setCfg.useM15M5Refinement = InpUseM15M5Refinement;
   g_setup.Init(setCfg);

   // 8. Configure M8 Risk & Execution Engines
   SRiskConfig rcfg;
   rcfg.SetDefaults();
   rcfg.riskPercentPerTrade  = InpRiskPercent;
   rcfg.maxDailyLossPercent  = InpMaxDailyLossPct;
   rcfg.maxWeeklyLossPercent = InpMaxWeeklyLossPct;
   rcfg.maxTradesPerDayeDay  = InpMaxTradesPerDay;
   rcfg.maxConsecutiveLosses = InpMaxConsecLosses;
   rcfg.maxSpreadPoints      = InpMaxSpreadPoints;
   g_risk.Init(_Symbol, g_effectiveMagic, rcfg);

   SExecConfig ecfg;
   ecfg.SetDefaults();
   ecfg.magicNumber           = g_effectiveMagic;
   ecfg.useBreakEvenAt1R      = InpUseBreakEven1R;
   ecfg.breakEvenBufferPoints = InpBeBufferPoints;
   ecfg.usePartialCloseTP1    = InpUsePartialTP1;
   ecfg.useTimeStop           = InpUseTimeStop;
   g_exec.Init(_Symbol, ecfg);

   // 9. Configure M9 Logger & Visuals
   SLoggerConfig lcfg;
   lcfg.SetDefaults();
   lcfg.enableCsvLog          = InpEnableCsvLog;
   lcfg.forwardJournalCsvFile = InpForwardJournalCSV;
   lcfg.takeScreenshotOnEntry = InpScreenshotOnEntry;
   g_logger.Init(_Symbol, lcfg);

   SEAVisualConfig vcfg;
   vcfg.SetDefaults();
   vcfg.enableVisuals         = InpEnableVisuals;
   vcfg.qtVisCfg.lookbackDays = InpVisualLookbackDays;
   g_visual.Init(ChartID(), _Symbol, vcfg);

   // 10. Configure M11 News Filter
   if(InpNewsEnabled)
     {
      g_news.Init(_Symbol,
                  InpNewsCsvFile,
                  InpNewsLiveSource,
                  InpNewsPreHours,
                  InpNewsPostHours,
                  InpNewsCurrencies,
                  InpNewsFailSafe,
                  InpNewsRefreshMin);
      g_news.Update(TimeCurrent());
     }

   // 11. Initial State Evaluation & Restart Recovery
   g_qtState = g_timeEngine.Update(TimeCurrent(), true);
   g_exec.RecoverStateOnInit(g_qtState, g_biasState, g_risk, g_setup, g_msnr, 0.0, 0.0);

   // If started after Friday Flat cutoff and positions exist, close immediately (PRD 4.12)
   g_exec.CheckAndExecuteFridayFlat(g_timeEngine, g_qtState, g_logger, g_profileSpec.profile);

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_mtf.Deinit();
   g_visual.ClearAll();
  }

//+------------------------------------------------------------------+
//| Timer function (Called every 1 second for Friday Flat & News)    |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();
   g_qtState = g_timeEngine.Update(now, false);

   // 1. M12 Friday Forced Flat Check (independent of setup state)
   g_exec.CheckAndExecuteFridayFlat(g_timeEngine, g_qtState, g_logger, g_profileSpec.profile);

   // 2. M11 News Refresh
   if(InpNewsEnabled)
      g_news.Update(now);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//| Gate Sequence (PRD v1.1): News -> Friday Flat -> Bias/Profile    |
//|                           -> Setup -> Risk -> Exec               |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();

   // 1. Update Time Engine
   g_qtState = g_timeEngine.Update(now, true);

   // 2. Gate: M12 Friday Forced Flat
   if(g_exec.CheckAndExecuteFridayFlat(g_timeEngine, g_qtState, g_logger, g_profileSpec.profile))
      return;

   // 3. Gate: M11 News Filter
   string newsWhy = "";
   bool isNewsBlocked = false;
   if(InpNewsEnabled)
     {
      g_news.Update(now);
      isNewsBlocked = g_news.IsBlocked(now, newsWhy);
      if(isNewsBlocked && g_exec.CountPendingOrders() > 0)
        {
         g_exec.CancelPendingOrders(BIAS_NEUTRAL, "NEWS_WINDOW_START: " + newsWhy,
                                    g_logger, g_qtState, g_profileSpec.profile);
        }
     }

   // 4. Manage Open Positions on every tick (MFE/MAE, Closed-Trade Journal, BE at 1R, Partial TP1, Time Stop)
   g_exec.ManageActiveTrades(g_setup, g_msnr, g_risk, g_timeEngine, g_logger,
                             g_qtState, g_biasState, g_profileSpec,
                             g_mtf.GetATR(TF_IDX_M5), g_mtf.GetATR(TF_IDX_H1));

   // 5. Update M2 Closed-Bar Cache (wait if history/ATR not yet ready)
   if(!g_mtf.Update(false))
      return;

   double spreadPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(spreadPrice < 0.0) spreadPrice = 0.0;

   // 6. Recalculate Downstream Analytical Modules only when a New Closed Bar forms
   if(g_mtf.AnyNewBar())
     {
      g_swings.Update(g_mtf, false);
      g_msnr.Update(g_mtf, g_swings, spreadPrice, false);
      g_ict.Update(g_mtf, g_swings, g_timeEngine, g_qtState, false);
      g_biasState = g_bias.Update(g_mtf, g_swings, g_msnr, g_ict, g_qtState, g_profileSpec);

      // Cancel pending order if Gate TF Bias flipped against an armed setup (PRD 4.10)
      if(!g_biasState.allowBuy && g_exec.CountPendingOrders(BIAS_BULL) > 0)
         g_exec.CancelPendingOrders(BIAS_BULL, "BIAS_GATE_FLIPPED_AGAINST_BUY", g_logger, g_qtState, g_profileSpec.profile);
      if(!g_biasState.allowSell && g_exec.CountPendingOrders(BIAS_BEAR) > 0)
         g_exec.CancelPendingOrders(BIAS_BEAR, "BIAS_GATE_FLIPPED_AGAINST_SELL", g_logger, g_qtState, g_profileSpec.profile);

      // Step M7 Setup State Machine on new M5 closed bar
      if(g_mtf.IsNewBar(TF_IDX_M5))
        {
         g_setup.Update(g_mtf, g_swings, g_msnr, g_ict,
                        g_qtState, g_biasState, g_profileSpec,
                        spreadPrice, isNewsBlocked, newsWhy);

         // Flush any newly evaluated / rejected setup to CSV journal
         SSetupTracker evalSetup;
         if(g_setup.PopLastLogEvent(evalSetup))
            g_logger.LogSetup(evalSetup, g_qtState, g_biasState, g_profileSpec);
        }
     }

   // 7. Check Risk Circuit Breakers & Execute S4_ARMED Setups
   string riskBlockWhy = "OK";
   bool canOpenNewTrade = g_risk.UpdateAndCheckCanTrade(g_timeEngine, g_qtState, riskBlockWhy);

   if(canOpenNewTrade && !isNewsBlocked && g_qtState.isTimeAllowed)
     {
      double atrM5 = g_mtf.GetATR(TF_IDX_M5);
      double atrH1 = g_mtf.GetATR(TF_IDX_H1);

      SSetupTracker buyTr = g_setup.GetBuySetup();
      if(buyTr.state == SETUP_S4_ARMED && buyTr.orderTicket == 0)
         g_exec.ExecuteArmedSetup(buyTr, g_risk, g_setup, g_msnr, g_logger,
                                  g_qtState, g_biasState, g_profileSpec, InpSignalOnlyMode, atrM5, atrH1);

      SSetupTracker sellTr = g_setup.GetSellSetup();
      if(sellTr.state == SETUP_S4_ARMED && sellTr.orderTicket == 0)
         g_exec.ExecuteArmedSetup(sellTr, g_risk, g_setup, g_msnr, g_logger,
                                  g_qtState, g_biasState, g_profileSpec, InpSignalOnlyMode, atrM5, atrH1);
     }

   // 8. Render Chart Visuals & Dashboard
   if(InpEnableVisuals && g_mtf.AnyNewBar())
     {
      g_visual.Render(g_timeEngine, g_qtState, g_msnr, g_ict, g_biasState,
                      g_profileSpec, g_setup, InpSignalOnlyMode,
                      isNewsBlocked, newsWhy, riskBlockWhy, false);
     }
  }
//+------------------------------------------------------------------+
