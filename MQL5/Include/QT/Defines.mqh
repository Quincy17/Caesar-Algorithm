//+------------------------------------------------------------------+
//| Defines.mqh                                                      |
//| Shared Constants, Enums, and Data Structures (QT-MSNR-ICT EA)    |
//| Place in: MQL5/Include/QT/Defines.mqh                            |
//+------------------------------------------------------------------+
#ifndef QT_DEFINES_MQH
#define QT_DEFINES_MQH

#define QT_EA_VERSION         "1.21"
#define QT_TARGET_SYMBOL      "XAUUSD"
#define QT_MTF_COUNT          6

//+------------------------------------------------------------------+
//| Time Engine Enums (M1)                                           |
//+------------------------------------------------------------------+
enum ENUM_TIME_CONV_MODE
  {
   TIME_MODE_A_SERVER_MINUS_7 = 0, // Mode A: NY = Server - 7h (Broker follows US DST GMT+2/+3)
   TIME_MODE_B_GMT_PLUS_USDST = 1  // Mode B: Broker GMT Offset + US DST Rules (Mar 2nd Sun - Nov 1st Sun)
  };

enum ENUM_QT_QUARTER
  {
   QT_Q0 = 0, // Q0: Out of cycle (e.g., Friday in weekly cycle, 5th week in monthly cycle)
   QT_Q1 = 1, // Q1: Accumulation (1st quarter)
   QT_Q2 = 2, // Q2: Manipulation / Judas Swing (2nd quarter)
   QT_Q3 = 3, // Q3: Distribution / Expansion (3rd quarter)
   QT_Q4 = 4  // Q4: Continuation / Reversal / X (4th quarter)
  };

enum ENUM_QT_SESSION
  {
   QT_SESSION_ASIA   = 1, // 18:00 - 00:00 NY (Daily Q1)
   QT_SESSION_LONDON = 2, // 00:00 - 06:00 NY (Daily Q2)
   QT_SESSION_NY_AM  = 3, // 06:00 - 12:00 NY (Daily Q3)
   QT_SESSION_NY_PM  = 4  // 12:00 - 18:00 NY (Daily Q4)
  };

//+------------------------------------------------------------------+
//| Trade Profile & Bias Enums (M6, M10)                             |
//+------------------------------------------------------------------+
enum ENUM_TRADE_PROFILE
  {
   PROFILE_SCALPING = 0, // Scalping (Gate: H4 | Score: D1,W1 | POI: H1,M15,M5 | Entry: M5 | RR>=1.5)
   PROFILE_INTRADAY = 1, // Intraday (Gate: D1,H4 | Score: W1 | POI: H4,H1,M15,M5 | Entry: M5 | RR>=2.0)
   PROFILE_SWING    = 2  // Swing (Gate: W1,D1 | Score: H4 | POI: W1,D1,H4 | Entry: M15 | RR>=3.0)
  };

enum ENUM_BIAS_DIR
  {
   BIAS_BEAR    = -1, // Bearish (-1)
   BIAS_NEUTRAL =  0, // Neutral / Conflicting (0 - No trade)
   BIAS_BULL    =  1  // Bullish (+1)
  };

enum ENUM_BIAS_GATE_MODE
  {
   BIAS_GATE_STRICT   = 0, // All required Gate TFs must align with trade direction
   BIAS_GATE_MAJORITY = 1  // Majority of Gate TFs must align, none opposing if 1 gate
  };

//+------------------------------------------------------------------+
//| MSNR & ICT Enums (M4, M5, M7)                                    |
//+------------------------------------------------------------------+
enum ENUM_POI_TYPE
  {
   POI_NONE      = 0,
   POI_CLASSIC_A = 1, // Resistance at body/close peak
   POI_CLASSIC_V = 2, // Support at body/close valley
   POI_RBS       = 3, // Resistance Become Support (Broken Classic A)
   POI_SBR       = 4, // Support Become Resistance (Broken Classic V)
   POI_QM_BULL   = 5, // Bullish Quasimodo (Left Shoulder body level)
   POI_QM_BEAR   = 6  // Bearish Quasimodo (Left Shoulder body level)
  };

enum ENUM_POI_STATUS
  {
   POI_STATUS_FRESH   = 0, // Untouched since creation/break (Valid for entry)
   POI_STATUS_TOUCHED = 1, // Wick touched without body break (Removed from active POI pool)
   POI_STATUS_BROKEN  = 2, // Body closed beyond level (Flipped to RBS/SBR)
   POI_STATUS_USED    = 3  // First touch / trade already occurred
  };

enum ENUM_FVG_STATUS
  {
   FVG_STATUS_OPEN    = 0, // Untouched
   FVG_STATUS_PARTIAL = 1, // Touched / partially mitigated
   FVG_STATUS_FILLED  = 2  // Completely filled
  };

enum ENUM_SETUP_STATE
  {
   SETUP_S0_IDLE      = 0, // Waiting for bias + allowed Daye day & time window
   SETUP_S1_POI_TOUCH = 1, // Price touched a fresh POI aligned with bias
   SETUP_S2_SWEEP     = 2, // Liquidity sweep confirmed inside/near POI
   SETUP_S3_MSS       = 3, // Market Structure Shift (body close displacement)
   SETUP_S4_ARMED     = 4, // FVG / LTF POI formed; limit/market order prepared
   SETUP_S5_IN_TRADE  = 5, // Order filled and position active
   SETUP_S6_DONE      = 6  // Completed (TP/SL) or cancelled/expired
  };

enum ENUM_ENTRY_TYPE
  {
   ENTRY_FVG_CE       = 0, // Limit at 50% Consequent Encroachment of FVG (Default)
   ENTRY_FVG_PROXIMAL = 1, // Limit at proximal edge of FVG
   ENTRY_MARKET_MSS   = 2  // Market execution on MSS candle close
  };

//+------------------------------------------------------------------+
//| Daily AMDX / XAMD Cycle & ERL <-> IRL Liquidity Narrative Enums  |
//+------------------------------------------------------------------+
enum ENUM_DAILY_CYCLE_TYPE
  {
   CYCLE_UNKNOWN = 0,
   CYCLE_AMDX    = 1, // Standard: Q1(Asia)=A, Q2(London)=M, Q3(NY_AM)=D, Q4(NY_PM)=X
   CYCLE_XAMD    = 2  // Shifted : Q1(Asia)=X, Q2(London)=A, Q3(NY_AM)=M, Q4(NY_PM)=D
  };

enum ENUM_AMDX_PHASE
  {
   PHASE_NONE = 0,
   PHASE_A    = 1, // Accumulation (Builds Phase A Swing High & Swing Low)
   PHASE_M    = 2, // Manipulation (Sweep of Phase A High/Low -> Extreme Top/Bottom Entry)
   PHASE_D    = 3, // Distribution (Real Expansion after Phase M Sweep -> Low-Risk Entry)
   PHASE_X    = 4  // Continuation / Reversal
  };

enum ENUM_LIQ_NARRATIVE
  {
   NARRATIVE_NONE       = 0,
   NARRATIVE_ERL_TO_IRL = 1, // Swept External Range Liquidity -> targeting Internal Range Liquidity
   NARRATIVE_IRL_TO_ERL = 2, // Rebalanced Internal Range Liquidity -> targeting External Range Liquidity
   NARRATIVE_ERL_TO_ERL = 3  // Swept Phase A Low/High (ERL) -> targeting opposing Phase A High/Low (ERL)
  };

//+------------------------------------------------------------------+
//| True Open Record & Collection (M1)                               |
//+------------------------------------------------------------------+
struct STrueOpenLevel
  {
   bool     valid;        // True if M5 bar open price was successfully resolved
   datetime time_ny;      // Anchor timestamp in New York time
   datetime time_server;  // Anchor timestamp in Broker Server time
   double   price;        // Open price of the M5 bar at anchor timestamp

   void Reset()
     {
      valid       = false;
      time_ny     = 0;
      time_server = 0;
      price       = 0.0;
     }
  };

struct QTTrueOpens
  {
   STrueOpenLevel yearOpen;        // True Year Open: 1st Monday of April (Daye daily open = Sun 18:00 NY)
   STrueOpenLevel monthOpen;       // True Month Open: 2nd Monday of Month (Daye daily open = Sun 18:00 NY)
   STrueOpenLevel weekOpen;        // True Week Open: Monday 18:00 NY (Tuesday Daye daily open)
   STrueOpenLevel dayOpen;         // True Day Open: 00:00 NY
   STrueOpenLevel sessionOpen;     // Active Session True Open (19:30, 01:30, 07:30, or 13:30 NY)
   STrueOpenLevel asiaOpen;        // Today's Asia True Session Open (19:30 NY)
   STrueOpenLevel londonOpen;      // Today's London True Session Open (01:30 NY)
   STrueOpenLevel nyAmOpen;        // Today's NY AM True Session Open (07:30 NY)
   STrueOpenLevel nyPmOpen;        // Today's NY PM True Session Open (13:30 NY)

   void Reset()
     {
      yearOpen.Reset();
      monthOpen.Reset();
      weekOpen.Reset();
      dayOpen.Reset();
      sessionOpen.Reset();
      asiaOpen.Reset();
      londonOpen.Reset();
      nyAmOpen.Reset();
      nyPmOpen.Reset();
     }
  };

//+------------------------------------------------------------------+
//| Complete Time Engine State Output (M1)                           |
//+------------------------------------------------------------------+
struct QTState
  {
   datetime        serverTime;          // Current broker server time evaluated
   datetime        nyTime;              // Converted New York time
   datetime        shiftedTime;         // Daye shifted time (nyTime + 6 hours)
   bool            isUsDst;             // True if US Daylight Saving Time (EDT, UTC-4) is active
   int             nyOffsetFromServer;  // Seconds added to serverTime to get nyTime (e.g. -7*3600)

   // Daye trading day calendar fields (derived from shiftedTime = NY + 6h)
   int             dayeYear;            // Trading year
   int             dayeMonth;           // Trading month (1..12)
   int             dayeDay;             // Trading day of month (1..31)
   int             dayeDayOfWeek;       // Trading day of week (0=Sun, 1=Mon, ..., 5=Fri, 6=Sat)
   datetime        dayeDayStartNY;      // Start of current Daye trading day in NY time (18:00 NY)
   datetime        dayeWeekStartNY;     // Start of current Daye trading week in NY time (Sun 18:00 NY)

   // Quarterly Theory Cycles
   ENUM_QT_QUARTER yearQ;               // Yearly quarter (Q1..Q4 calendar)
   ENUM_QT_QUARTER monthQ;              // Monthly quarter (Q1..Q4 = 1st..4th Monday week; Q0 = 5th week/before 1st Mon)
   ENUM_QT_QUARTER weekQ;               // Weekly quarter (Mon=Q1, Tue=Q2, Wed=Q3, Thu=Q4, Fri/Weekend=Q0)
   ENUM_QT_QUARTER dayQ;                // Daily quarter (Asia=Q1, London=Q2, NY_AM=Q3, NY_PM=Q4)
   ENUM_QT_SESSION session;             // Active session enum (Asia, London, NY_AM, NY_PM)
   ENUM_QT_QUARTER q90;                 // 90-minute cycle quarter inside current session (Q1..Q4)
   int             minuteInSession;     // Minutes elapsed since start of current 6h session (0..359)
   int             minuteIn90mBlock;    // Minutes elapsed inside current 90m block (0..89)
   datetime        sessionStartNY;      // Start of current 6-hour session in NY time
   datetime        sessionEndNY;        // End of current 6-hour session in NY time
   datetime        block90StartNY;      // Start of current 90-minute block in NY time
   datetime        block90EndNY;        // End of current 90-minute block in NY time

   // True Opens
   QTTrueOpens     trueOpens;           // All True Open anchor timestamps & prices

   // Permission flags
   bool            isDayAllowed;        // True if current Daye day of week is enabled
   bool            isSessionAllowed;    // True if current 6h session is enabled
   bool            isQ90Allowed;        // True if current 90m quarter is enabled
   bool            isFridayCutoffPassed;// True if Friday >= FridayCloseNY (15:00 NY)
   bool            isTimeAllowed;       // Master time filter flag (Day && Session && Q90 && !FridayCutoff)
   bool            isCycleOnlyDay;      // v1.21: Mon/Fri enabled only for Daily Cycle Phase D entries
   bool            isCycleTimeAllowed;  // v1.21: Time filter for Daily Cycle tracker ((Day || CycleOnlyDay) && Session && Q90 && !FridayCutoff)

   void Reset()
     {
      serverTime           = 0;
      nyTime               = 0;
      shiftedTime          = 0;
      isUsDst              = false;
      nyOffsetFromServer   = -7 * 3600;
      dayeYear             = 0;
      dayeMonth            = 0;
      dayeDay              = 0;
      dayeDayOfWeek        = 0;
      dayeDayStartNY       = 0;
      dayeWeekStartNY      = 0;
      yearQ                = QT_Q0;
      monthQ               = QT_Q0;
      weekQ                = QT_Q0;
      dayQ                 = QT_Q0;
      session              = QT_SESSION_ASIA;
      q90                  = QT_Q0;
      minuteInSession      = 0;
      minuteIn90mBlock     = 0;
      sessionStartNY       = 0;
      sessionEndNY         = 0;
      block90StartNY       = 0;
      block90EndNY         = 0;
      trueOpens.Reset();
      isDayAllowed         = false;
      isSessionAllowed     = false;
      isQ90Allowed         = false;
      isFridayCutoffPassed = false;
      isTimeAllowed        = false;
      isCycleOnlyDay       = false;
      isCycleTimeAllowed   = false;
     }
  };

//+------------------------------------------------------------------+
//| Helper String Formatters                                         |
//+------------------------------------------------------------------+
string QTQuarterToString(const ENUM_QT_QUARTER q)
  {
   switch(q)
     {
      case QT_Q1: return "Q1";
      case QT_Q2: return "Q2";
      case QT_Q3: return "Q3";
      case QT_Q4: return "Q4";
      default:    return "Q0";
     }
  }

string QTSessionToString(const ENUM_QT_SESSION s)
  {
   switch(s)
     {
      case QT_SESSION_ASIA:   return "Asia";
      case QT_SESSION_LONDON: return "London";
      case QT_SESSION_NY_AM:  return "NY_AM";
      case QT_SESSION_NY_PM:  return "NY_PM";
      default:                return "Unknown";
     }
  }

string QTDayOfWeekToString(const int dow)
  {
   switch(dow)
     {
      case 0: return "Sun";
      case 1: return "Mon";
      case 2: return "Tue";
      case 3: return "Wed";
      case 4: return "Thu";
      case 5: return "Fri";
      case 6: return "Sat";
      default: return "N/A";
     }
  }

string QTProfileToString(const ENUM_TRADE_PROFILE p)
  {
   switch(p)
     {
      case PROFILE_SCALPING: return "Scalping";
      case PROFILE_INTRADAY: return "Intraday";
      case PROFILE_SWING:    return "Swing";
      default:               return "Unknown";
     }
  }

string QTBiasToString(const ENUM_BIAS_DIR b)
  {
   if(b > 0) return "BULL";
   if(b < 0) return "BEAR";
   return "NEUTRAL";
  }

string QTDailyCycleToString(const ENUM_DAILY_CYCLE_TYPE c)
  {
   switch(c)
     {
      case CYCLE_AMDX: return "AMDX";
      case CYCLE_XAMD: return "XAMD";
      default:         return "UNKNOWN";
     }
  }

string QTAmdxPhaseToString(const ENUM_AMDX_PHASE p)
  {
   switch(p)
     {
      case PHASE_A: return "PHASE_A";
      case PHASE_M: return "PHASE_M";
      case PHASE_D: return "PHASE_D";
      case PHASE_X: return "PHASE_X";
      default:      return "NONE";
     }
  }

string QTNarrativeToString(const ENUM_LIQ_NARRATIVE n)
  {
   switch(n)
     {
      case NARRATIVE_ERL_TO_IRL: return "ERL_TO_IRL";
      case NARRATIVE_IRL_TO_ERL: return "IRL_TO_ERL";
      case NARRATIVE_ERL_TO_ERL: return "ERL_TO_ERL";
      default:                   return "NONE";
     }
  }

//+------------------------------------------------------------------+
//| Pip <-> Price Conversion Helpers                                 |
//| On XAUUSD / GOLD: 1 pip = $0.10 (60 pips = $6, 100 pips = $10,   |
//|                   300 pips = $30, e.g. 4100 -> 4110 = 100 pips)  |
//| On Forex pairs  : 1 pip = 10 points (5/3-digit) or 1 point       |
//+------------------------------------------------------------------+
double QTPipsToPrice(const string symbol, const double pips)
  {
   string symUpper = (StringLen(symbol) > 0 ? symbol : _Symbol);
   StringToUpper(symUpper);
   if(StringFind(symUpper, "XAU") >= 0 || StringFind(symUpper, "GOLD") >= 0)
      return pips * 0.10;

   double pt  = SymbolInfoDouble(symUpper, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symUpper, SYMBOL_DIGITS);
   if(pt <= 0.0)
      pt = 0.0001;
   double pipSize = ((digits == 3 || digits == 5) ? pt * 10.0 : pt);
   return pips * pipSize;
  }

double QTPriceToPips(const string symbol, const double priceDist)
  {
   double onePip = QTPipsToPrice(symbol, 1.0);
   if(onePip <= 1e-9)
      return 0.0;
   return priceDist / onePip;
  }

#endif // QT_DEFINES_MQH
//+------------------------------------------------------------------+
