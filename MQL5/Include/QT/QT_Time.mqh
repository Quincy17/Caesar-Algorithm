//+------------------------------------------------------------------+
//| QT_Time.mqh                                                      |
//| M1 - Quarterly Theory Time Engine (TraderDaye Original Rules)    |
//| Place in: MQL5/Include/QT/QT_Time.mqh                            |
//|                                                                  |
//| Responsibilities:                                                |
//|  1. Broker Server <-> New York (NY) time conversion:             |
//|     - Mode A (Default): NY = Server - 7 hours                    |
//|     - Mode B: Server GMT Offset + US DST rules                   |
//|       (Starts 2nd Sunday of March 02:00 EST / 07:00 UTC,         |
//|        Ends 1st Sunday of November 02:00 EDT / 06:00 UTC)        |
//|  2. Daye trading day boundary: 18:00 NY to 18:00 NY              |
//|     computed via shifted = NY + 6 hours.                         |
//|  3. Quarterly Cycles:                                            |
//|     - Yearly   : Calendar Q1..Q4                                 |
//|     - Monthly  : Q1..Q4 = 1st..4th Monday of month; 5th = Q0     |
//|     - Weekly   : Mon=Q1, Tue=Q2, Wed=Q3, Thu=Q4, Fri=Q0          |
//|     - Daily    : 18-24 Asia Q1, 00-06 London Q2,                 |
//|                  06-12 NY AM Q3, 12-18 NY PM Q4                  |
//|     - 90-Min   : 4 blocks of 90m per 6h session (Q1..Q4)         |
//|  4. True Opens (from M5 open price, no look-ahead):              |
//|     - True Year Open    : 1st Monday of April (Sun 18:00 NY)     |
//|     - True Month Open   : 2nd Monday of Month (Sun 18:00 NY)     |
//|     - True Week Open    : Monday 18:00 NY (Tue Daye candle open) |
//|     - True Day Open     : 00:00 NY                               |
//|     - True Session Open : 19:30, 01:30, 07:30, 13:30 NY          |
//+------------------------------------------------------------------+
#ifndef QT_TIME_MQH
#define QT_TIME_MQH

#include "Defines.mqh"

//+------------------------------------------------------------------+
//| Time Engine Configuration Parameters                             |
//+------------------------------------------------------------------+
struct SQTTimeConfig
  {
   ENUM_TIME_CONV_MODE convMode;            // Mode A (-7h) or Mode B (GMT + US DST)
   int                 modeAServerToNYHours;// Default -7 (NY = Server - 7h)
   int                 modeBServerGmtHours; // Broker standard GMT offset in hours for Mode B (e.g. 2 or 0)

   // Day permissions (Daye day: Mon=Q1, Tue=Q2, Wed=Q3, Thu=Q4, Fri=Q0)
   bool                allowMonday;         // Default false (Mon Q1 accumulation)
   bool                allowTuesday;        // Default true  (Tue Q2)
   bool                allowWednesday;      // Default true  (Wed Q3)
   bool                allowThursday;       // Default true  (Thu Q4)
   bool                allowFriday;         // Default false (Fri Q0 out of cycle)
   bool                allowMondayCycleD;   // v1.21: Allow Monday for Daily Cycle Phase D entries only (Default true)
   bool                allowFridayCycleD;   // v1.21: Allow Friday for Daily Cycle Phase D entries only (Default true)

   // Session permissions (Daily cycle)
   bool                allowAsia;           // 18:00-00:00 NY (Q1) - Default false (true for Swing)
   bool                allowLondon;         // 00:00-06:00 NY (Q2) - Default true
   bool                allowNyAm;           // 06:00-12:00 NY (Q3) - Default true
   bool                allowNyPm;           // 12:00-18:00 NY (Q4) - Default false (true for Swing)

   // 90-minute block permissions inside allowed sessions
   bool                allow90mQ1;          // 00..89m  - Default false for Scalp, true for Intraday/Swing
   bool                allow90mQ2;          // 90..179m - Default true (Sweep/Judas)
   bool                allow90mQ3;          // 180..269m- Default true (Distribution)
   bool                allow90mQ4;          // 270..359m- Default false for Scalp, true for Intraday/Swing

   // Friday flat cutoff in NY time (default 15:00 NY)
   int                 fridayCloseHourNY;   // Default 15
   int                 fridayCloseMinNY;    // Default 0

   void SetDefaults()
     {
      convMode             = TIME_MODE_A_SERVER_MINUS_7;
      modeAServerToNYHours = -7;
      modeBServerGmtHours  = 0;

      allowMonday          = false;
      allowTuesday         = true;
      allowWednesday       = true;
      allowThursday        = true;
      allowFriday          = false;
      allowMondayCycleD    = true;
      allowFridayCycleD    = true;

      allowAsia            = false;
      allowLondon          = true;
      allowNyAm            = true;
      allowNyPm            = false;

      allow90mQ1           = false;
      allow90mQ2           = true;
      allow90mQ3           = true;
      allow90mQ4           = false;

      fridayCloseHourNY    = 15;
      fridayCloseMinNY     = 0;
     }

   //--- Apply profile-specific time filter presets (PRD 4.10)
   void ApplyProfilePreset(const ENUM_TRADE_PROFILE profile)
     {
      allowMonday    = false;
      allowTuesday   = true;
      allowWednesday = true;
      allowThursday  = true;
      allowFriday    = false;

      if(profile == PROFILE_SCALPING)
        {
         // Scalping: only Q2-Q3 90m blocks in London and NY AM
         allowAsia   = false;
         allowLondon = true;
         allowNyAm   = true;
         allowNyPm   = false;

         allow90mQ1  = false;
         allow90mQ2  = true;
         allow90mQ3  = true;
         allow90mQ4  = false;
        }
      else if(profile == PROFILE_INTRADAY)
        {
         // Intraday: London and NY AM sessions (Q2 & Q3 90m default trigger)
         allowAsia   = false;
         allowLondon = true;
         allowNyAm   = true;
         allowNyPm   = false;

         allow90mQ1  = false;
         allow90mQ2  = true;
         allow90mQ3  = true;
         allow90mQ4  = false;
        }
      else if(profile == PROFILE_SWING)
        {
         // Swing: any session on Tuesday-Thursday
         allowAsia   = true;
         allowLondon = true;
         allowNyAm   = true;
         allowNyPm   = true;

         allow90mQ1  = true;
         allow90mQ2  = true;
         allow90mQ3  = true;
         allow90mQ4  = true;
        }
     }
  };

//+------------------------------------------------------------------+
//| CQTTimeEngine Class                                              |
//+------------------------------------------------------------------+
class CQTTimeEngine
  {
private:
   string            m_symbol;
   SQTTimeConfig     m_cfg;
   QTState           m_state;

   // Cache for True Open price lookups so M5 CopyRates isn't spammed every tick
   STrueOpenLevel    m_cacheYear;
   STrueOpenLevel    m_cacheMonth;
   STrueOpenLevel    m_cacheWeek;
   STrueOpenLevel    m_cacheDay;
   STrueOpenLevel    m_cacheAsia;
   STrueOpenLevel    m_cacheLondon;
   STrueOpenLevel    m_cacheNyAm;
   STrueOpenLevel    m_cacheNyPm;

   //--- Build a datetime from calendar components
   static datetime   MakeDateTime(const int year, const int mon, const int day,
                                  const int hour = 0, const int min = 0, const int sec = 0)
     {
      MqlDateTime dt;
      ZeroMemory(dt);
      dt.year = year;
      dt.mon  = mon;
      dt.day  = day;
      dt.hour = hour;
      dt.min  = min;
      dt.sec  = sec;
      return StructToTime(dt);
     }

   //--- Find day-of-month (1..31) for the N-th occurrence (1..5) of targetDow (0=Sun..6=Sat)
   static int        GetNthWeekdayOfMonth(const int year, const int mon,
                                          const int targetDow, const int nth)
     {
      datetime firstOfMonth = MakeDateTime(year, mon, 1, 0, 0, 0);
      MqlDateTime dt;
      TimeToStruct(firstOfMonth, dt);
      int offset = (targetDow - dt.day_of_week + 7) % 7;
      return 1 + offset + (nth - 1) * 7;
     }

   //--- Resolve M5 open price at or immediately after anchorNY (no future leak)
   void              ResolveTrueOpenPrice(const datetime anchorNY,
                                          const datetime currentNY,
                                          STrueOpenLevel &cacheSlot,
                                          STrueOpenLevel &outLevel)
     {
      outLevel.Reset();
      outLevel.time_ny     = anchorNY;
      outLevel.time_server = NYToServer(anchorNY);

      // Do not resolve if anchor time is in the future relative to evaluated time
      if(anchorNY <= 0 || currentNY < anchorNY)
         return;

      // Return cached value if already resolved for this exact anchor timestamp
      if(cacheSlot.valid && cacheSlot.time_ny == anchorNY && cacheSlot.price > 0.0)
        {
         outLevel = cacheSlot;
         return;
        }

      if(StringLen(m_symbol) == 0)
         return;

      datetime currentServer = NYToServer(currentNY);
      datetime anchorServer  = outLevel.time_server;

      // Locate M5 bar at anchorServer (or first bar opening after anchorServer within 6h for maintenance break)
      int shift = iBarShift(m_symbol, PERIOD_M5, anchorServer, false);
      if(shift < 0)
         return;

      datetime barTime = iTime(m_symbol, PERIOD_M5, shift);
      if(barTime <= 0)
         return;

      // iBarShift(..., false) returns bar with time <= anchorServer.
      // If barTime < anchorServer (e.g., 17:00-18:00 NY XAUUSD break), step to shift - 1 (first bar after anchor).
      if(barTime < anchorServer)
        {
         if(shift - 1 >= 0)
           {
            shift--;
            barTime = iTime(m_symbol, PERIOD_M5, shift);
           }
         else
            return; // First bar at/after anchor hasn't formed yet
        }

      // Ensure the bar is within [anchorServer, anchorServer + 6h] and not in the future of currentServer
      if(barTime < anchorServer || barTime > anchorServer + 6 * 3600 || barTime > currentServer)
         return;

      double openPrice = iOpen(m_symbol, PERIOD_M5, shift);
      if(openPrice <= 0.0)
         return;

      outLevel.valid = true;
      outLevel.price = openPrice;
      cacheSlot      = outLevel;
     }

public:
                     CQTTimeEngine()
     {
      m_symbol = QT_TARGET_SYMBOL;
      m_cfg.SetDefaults();
      m_state.Reset();
      ResetCache();
     }

   void              ResetCache()
     {
      m_cacheYear.Reset();
      m_cacheMonth.Reset();
      m_cacheWeek.Reset();
      m_cacheDay.Reset();
      m_cacheAsia.Reset();
      m_cacheLondon.Reset();
      m_cacheNyAm.Reset();
      m_cacheNyPm.Reset();
     }

   void              Init(const string symbol, const SQTTimeConfig &cfg)
     {
      m_symbol = (StringLen(symbol) > 0 ? symbol : QT_TARGET_SYMBOL);
      m_cfg    = cfg;
      m_state.Reset();
      ResetCache();
     }

   void              SetConfig(const SQTTimeConfig &cfg)
     {
      m_cfg = cfg;
     }

   SQTTimeConfig     GetConfig() const { return m_cfg; }
   QTState           GetState()  const { return m_state; }

   //+------------------------------------------------------------------+
   //| US Daylight Saving Time (DST) Rules                              |
   //| Starts: 2nd Sunday of March at 02:00 EST (07:00 UTC)             |
   //| Ends  : 1st Sunday of November at 02:00 EDT (06:00 UTC)          |
   //+------------------------------------------------------------------+
   static bool       IsUsDstFromUTC(const datetime utcTime)
     {
      MqlDateTime dt;
      TimeToStruct(utcTime, dt);

      if(dt.mon < 3 || dt.mon > 11)
         return false;
      if(dt.mon > 3 && dt.mon < 11)
         return true;

      if(dt.mon == 3)
        {
         int secondSun = GetNthWeekdayOfMonth(dt.year, 3, 0, 2);
         datetime dstStartUTC = MakeDateTime(dt.year, 3, secondSun, 7, 0, 0); // 02:00 EST = 07:00 UTC
         return (utcTime >= dstStartUTC);
        }

      // dt.mon == 11
      int firstSun = GetNthWeekdayOfMonth(dt.year, 11, 0, 1);
      datetime dstEndUTC = MakeDateTime(dt.year, 11, firstSun, 6, 0, 0);     // 02:00 EDT = 06:00 UTC
      return (utcTime < dstEndUTC);
     }

   static bool       IsUsDstFromNY(const datetime nyTime)
     {
      MqlDateTime dt;
      TimeToStruct(nyTime, dt);

      if(dt.mon < 3 || dt.mon > 11)
         return false;
      if(dt.mon > 3 && dt.mon < 11)
         return true;

      if(dt.mon == 3)
        {
         int secondSun = GetNthWeekdayOfMonth(dt.year, 3, 0, 2);
         datetime dstStartNY = MakeDateTime(dt.year, 3, secondSun, 2, 0, 0);
         return (nyTime >= dstStartNY);
        }

      // dt.mon == 11
      int firstSun = GetNthWeekdayOfMonth(dt.year, 11, 0, 1);
      datetime dstEndNY = MakeDateTime(dt.year, 11, firstSun, 2, 0, 0);
      return (nyTime < dstEndNY);
     }

   //+------------------------------------------------------------------+
   //| Convert Broker Server Time <-> New York Time                     |
   //+------------------------------------------------------------------+
   datetime          ServerToNY(const datetime serverTime, bool &outIsDst, int &outOffsetSec) const
     {
      if(m_cfg.convMode == TIME_MODE_A_SERVER_MINUS_7)
        {
         outOffsetSec = m_cfg.modeAServerToNYHours * 3600; // Default -7 * 3600
         datetime ny  = (datetime)((long)serverTime + outOffsetSec);
         outIsDst     = IsUsDstFromNY(ny);
         return ny;
        }
      else
        {
         // Mode B: Server -> UTC -> NY (with US DST)
         datetime utc     = (datetime)((long)serverTime - (long)m_cfg.modeBServerGmtHours * 3600);
         outIsDst         = IsUsDstFromUTC(utc);
         int nyUtcOffset  = (outIsDst ? -4 * 3600 : -5 * 3600);
         datetime ny      = (datetime)((long)utc + nyUtcOffset);
         outOffsetSec     = (int)((long)ny - (long)serverTime);
         return ny;
        }
     }

   datetime          ServerToNY(const datetime serverTime) const
     {
      bool isDst = false;
      int  off   = 0;
      return ServerToNY(serverTime, isDst, off);
     }

   datetime          NYToServer(const datetime nyTime) const
     {
      if(m_cfg.convMode == TIME_MODE_A_SERVER_MINUS_7)
        {
         return (datetime)((long)nyTime - (long)m_cfg.modeAServerToNYHours * 3600);
        }
      else
        {
         bool isDst      = IsUsDstFromNY(nyTime);
         int nyUtcOffset = (isDst ? -4 * 3600 : -5 * 3600);
         datetime utc    = (datetime)((long)nyTime - nyUtcOffset);
         return (datetime)((long)utc + (long)m_cfg.modeBServerGmtHours * 3600);
        }
     }

   //+------------------------------------------------------------------+
   //| Broker Verification: D1 candle open must equal 17:00 NY          |
   //+------------------------------------------------------------------+
   bool              VerifyBrokerD1OpenIs17NY(string &outReport) const
     {
      datetime d1OpenServer = iTime(m_symbol, PERIOD_D1, 1);
      if(d1OpenServer <= 0)
        {
         outReport = "D1 history not yet available for verification.";
         return false;
        }
      datetime d1OpenNY = ServerToNY(d1OpenServer);
      MqlDateTime dt;
      TimeToStruct(d1OpenNY, dt);
      bool ok = (dt.hour == 17 && dt.min == 0);
      outReport = StringFormat("D1 Bar[1] Server=%s -> NY=%s (Expected 17:00 NY) [%s]",
                               TimeToString(d1OpenServer, TIME_DATE | TIME_MINUTES),
                               TimeToString(d1OpenNY, TIME_DATE | TIME_MINUTES),
                               (ok ? "PASS" : "MISMATCH"));
      return ok;
     }

   //+------------------------------------------------------------------+
   //| Compute Daye Daily Open (Sun 18:00 NY) of N-th Monday of Month   |
   //| Used for True Month Open (2nd Monday) & True Year Open (1st Mon  |
   //| of April), as well as Monthly Q1..Q4 boundaries.                 |
   //+------------------------------------------------------------------+
   static datetime   GetNthMondayDayeOpenNY(const int year, const int mon, const int nthMonday)
     {
      int monDay = GetNthWeekdayOfMonth(year, mon, 1, nthMonday); // 1 = Monday
      // Check if nthMonday actually exists in this month
      MqlDateTime dtCheck;
      datetime mondayShifted00 = MakeDateTime(year, mon, monDay, 0, 0, 0);
      TimeToStruct(mondayShifted00, dtCheck);
      if(dtCheck.mon != mon)
         return 0; // e.g., 5th Monday does not exist in this month

      // Daye day for Monday starts at Monday 00:00 shifted = Sunday 18:00 NY
      return (datetime)((long)mondayShifted00 - 6 * 3600);
     }

   //--- Active True Month Open anchor in NY time (2nd Monday's Daye open = Sun 18:00 NY)
   static datetime   GetActiveTrueMonthOpenNY(const datetime nyTime)
     {
      datetime shifted = (datetime)((long)nyTime + 6 * 3600);
      MqlDateTime dtS;
      TimeToStruct(shifted, dtS);

      datetime curMonthOpenNY = GetNthMondayDayeOpenNY(dtS.year, dtS.mon, 2);
      if(nyTime >= curMonthOpenNY)
         return curMonthOpenNY;

      // Before 2nd Monday of current month -> use previous month's 2nd Monday Daye open
      int prevYear = dtS.year;
      int prevMon  = dtS.mon - 1;
      if(prevMon < 1)
        {
         prevMon = 12;
         prevYear--;
        }
      return GetNthMondayDayeOpenNY(prevYear, prevMon, 2);
     }

   //--- Active True Year Open anchor in NY time (1st Monday of April's Daye open = Sun 18:00 NY)
   static datetime   GetActiveTrueYearOpenNY(const datetime nyTime)
     {
      datetime shifted = (datetime)((long)nyTime + 6 * 3600);
      MqlDateTime dtS;
      TimeToStruct(shifted, dtS);

      datetime curYearOpenNY = GetNthMondayDayeOpenNY(dtS.year, 4, 1);
      if(nyTime >= curYearOpenNY)
         return curYearOpenNY;

      return GetNthMondayDayeOpenNY(dtS.year - 1, 4, 1);
     }

   //+------------------------------------------------------------------+
   //| Evaluate All Quarterly Theory Cycles & True Opens at serverTime  |
   //+------------------------------------------------------------------+
   void              Evaluate(const datetime serverTime, QTState &outState, const bool resolvePrices = true)
     {
      outState.Reset();
      outState.serverTime = serverTime;
      outState.nyTime     = ServerToNY(serverTime, outState.isUsDst, outState.nyOffsetFromServer);

      // 1. Shifted time = NY + 6 hours (Daye day runs 18:00 NY -> 18:00 NY)
      outState.shiftedTime = (datetime)((long)outState.nyTime + 6 * 3600);

      MqlDateTime dtShifted;
      TimeToStruct(outState.shiftedTime, dtShifted);

      outState.dayeYear      = dtShifted.year;
      outState.dayeMonth     = dtShifted.mon;
      outState.dayeDay       = dtShifted.day;
      outState.dayeDayOfWeek = dtShifted.day_of_week; // 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat

      // Start of current Daye trading day (00:00 shifted = 18:00 NY previous evening)
      long secSinceDayeStart   = (long)dtShifted.hour * 3600 + (long)dtShifted.min * 60 + (long)dtShifted.sec;
      datetime dayStartShifted = (datetime)((long)outState.shiftedTime - secSinceDayeStart);
      outState.dayeDayStartNY  = (datetime)((long)dayStartShifted - 6 * 3600);

      // Start of current Daye trading week (Monday 00:00 shifted = Sunday 18:00 NY)
      int daysSinceMonday       = (dtShifted.day_of_week == 0 ? 6 : dtShifted.day_of_week - 1);
      datetime weekStartShifted = (datetime)((long)dayStartShifted - (long)daysSinceMonday * 86400);
      outState.dayeWeekStartNY  = (datetime)((long)weekStartShifted - 6 * 3600);

      // 2. Yearly Cycle (Calendar Quarter Q1..Q4)
      if(outState.dayeMonth <= 3)
         outState.yearQ = QT_Q1;
      else if(outState.dayeMonth <= 6)
         outState.yearQ = QT_Q2;
      else if(outState.dayeMonth <= 9)
         outState.yearQ = QT_Q3;
      else
         outState.yearQ = QT_Q4;

      // 3. Monthly Cycle: Q1..Q4 = 1st..4th Monday of month; 5th Monday = Q0; days before 1st Monday = Q0
      int firstMondayDay = GetNthWeekdayOfMonth(dtShifted.year, dtShifted.mon, 1, 1);
      if(dtShifted.day < firstMondayDay)
        {
         outState.monthQ = QT_Q0;
        }
      else
        {
         int weekIdx = ((dtShifted.day - firstMondayDay) / 7) + 1;
         switch(weekIdx)
           {
            case 1:  outState.monthQ = QT_Q1; break;
            case 2:  outState.monthQ = QT_Q2; break;
            case 3:  outState.monthQ = QT_Q3; break;
            case 4:  outState.monthQ = QT_Q4; break;
            default: outState.monthQ = QT_Q0; break; // 5th week of the month = Q0
           }
        }

      // 4. Weekly Cycle: Mon=Q1, Tue=Q2, Wed=Q3, Thu=Q4, Fri/Sat/Sun=Q0
      switch(outState.dayeDayOfWeek)
        {
         case 1:  outState.weekQ = QT_Q1; break; // Monday
         case 2:  outState.weekQ = QT_Q2; break; // Tuesday
         case 3:  outState.weekQ = QT_Q3; break; // Wednesday
         case 4:  outState.weekQ = QT_Q4; break; // Thursday
         default: outState.weekQ = QT_Q0; break; // Friday (5), Saturday (6), Sunday (0)
        }

      // 5. Daily Session Cycle (6-hour quarters starting at 18:00 NY = 00:00 shifted)
      //    shifted 00-06 = NY 18-24 Asia (Q1)
      //    shifted 06-12 = NY 00-06 London (Q2)
      //    shifted 12-18 = NY 06-12 NY AM (Q3)
      //    shifted 18-24 = NY 12-18 NY PM (Q4)
      int sessionIdx = dtShifted.hour / 6; // 0..3
      switch(sessionIdx)
        {
         case 0:
            outState.dayQ    = QT_Q1;
            outState.session = QT_SESSION_ASIA;
            break;
         case 1:
            outState.dayQ    = QT_Q2;
            outState.session = QT_SESSION_LONDON;
            break;
         case 2:
            outState.dayQ    = QT_Q3;
            outState.session = QT_SESSION_NY_AM;
            break;
         default:
            outState.dayQ    = QT_Q4;
            outState.session = QT_SESSION_NY_PM;
            break;
        }
      outState.sessionStartNY = (datetime)((long)outState.dayeDayStartNY + (long)sessionIdx * 6 * 3600);
      outState.sessionEndNY   = (datetime)((long)outState.sessionStartNY + 6 * 3600);

      // 6. 90-Minute Cycle inside the 6-hour session: floor(minutes_since_session_start / 90) -> Q1..Q4
      int secInSession          = (int)((long)outState.nyTime - (long)outState.sessionStartNY);
      outState.minuteInSession  = secInSession / 60;
      int block90Idx            = outState.minuteInSession / 90; // 0..3
      if(block90Idx < 0) block90Idx = 0;
      if(block90Idx > 3) block90Idx = 3;

      outState.q90              = (ENUM_QT_QUARTER)(block90Idx + 1);
      outState.minuteIn90mBlock = outState.minuteInSession % 90;
      outState.block90StartNY   = (datetime)((long)outState.sessionStartNY + (long)block90Idx * 90 * 60);
      outState.block90EndNY     = (datetime)((long)outState.block90StartNY + 90 * 60);

      // 7. True Open Anchor Timestamps (in NY time)
      //    - True Year Open   : 1st Monday of April (Sun 18:00 NY)
      //    - True Month Open  : 2nd Monday of Month (Sun 18:00 NY)
      //    - True Week Open   : Monday 18:00 NY (start of Tuesday Daye candle)
      //    - True Day Open    : 00:00 NY (dayeDayStartNY + 6 hours)
      //    - True Session Open: 19:30, 01:30, 07:30, 13:30 NY (each = sessionStartNY + 90m)
      datetime anchorYearNY   = GetActiveTrueYearOpenNY(outState.nyTime);
      datetime anchorMonthNY  = GetActiveTrueMonthOpenNY(outState.nyTime);
      datetime anchorWeekNY   = (datetime)((long)outState.dayeWeekStartNY + 24 * 3600); // Mon 18:00 NY
      datetime anchorDayNY    = (datetime)((long)outState.dayeDayStartNY  +  6 * 3600); // 00:00 NY
      datetime anchorAsiaNY   = (datetime)((long)outState.dayeDayStartNY  + 90 * 60);   // 19:30 NY
      datetime anchorLondonNY = (datetime)((long)outState.dayeDayStartNY  +  6 * 3600 + 90 * 60); // 01:30 NY
      datetime anchorNyAmNY   = (datetime)((long)outState.dayeDayStartNY  + 12 * 3600 + 90 * 60); // 07:30 NY
      datetime anchorNyPmNY   = (datetime)((long)outState.dayeDayStartNY  + 18 * 3600 + 90 * 60); // 13:30 NY

      if(resolvePrices)
        {
         ResolveTrueOpenPrice(anchorYearNY,   outState.nyTime, m_cacheYear,   outState.trueOpens.yearOpen);
         ResolveTrueOpenPrice(anchorMonthNY,  outState.nyTime, m_cacheMonth,  outState.trueOpens.monthOpen);
         ResolveTrueOpenPrice(anchorWeekNY,   outState.nyTime, m_cacheWeek,   outState.trueOpens.weekOpen);
         ResolveTrueOpenPrice(anchorDayNY,    outState.nyTime, m_cacheDay,    outState.trueOpens.dayOpen);
         ResolveTrueOpenPrice(anchorAsiaNY,   outState.nyTime, m_cacheAsia,   outState.trueOpens.asiaOpen);
         ResolveTrueOpenPrice(anchorLondonNY, outState.nyTime, m_cacheLondon, outState.trueOpens.londonOpen);
         ResolveTrueOpenPrice(anchorNyAmNY,   outState.nyTime, m_cacheNyAm,   outState.trueOpens.nyAmOpen);
         ResolveTrueOpenPrice(anchorNyPmNY,   outState.nyTime, m_cacheNyPm,   outState.trueOpens.nyPmOpen);
        }
      else
        {
         outState.trueOpens.yearOpen.time_ny     = anchorYearNY;
         outState.trueOpens.yearOpen.time_server = NYToServer(anchorYearNY);
         outState.trueOpens.monthOpen.time_ny    = anchorMonthNY;
         outState.trueOpens.monthOpen.time_server= NYToServer(anchorMonthNY);
         outState.trueOpens.weekOpen.time_ny     = anchorWeekNY;
         outState.trueOpens.weekOpen.time_server = NYToServer(anchorWeekNY);
         outState.trueOpens.dayOpen.time_ny      = anchorDayNY;
         outState.trueOpens.dayOpen.time_server  = NYToServer(anchorDayNY);
         outState.trueOpens.asiaOpen.time_ny     = anchorAsiaNY;
         outState.trueOpens.asiaOpen.time_server = NYToServer(anchorAsiaNY);
         outState.trueOpens.londonOpen.time_ny   = anchorLondonNY;
         outState.trueOpens.londonOpen.time_server = NYToServer(anchorLondonNY);
         outState.trueOpens.nyAmOpen.time_ny     = anchorNyAmNY;
         outState.trueOpens.nyAmOpen.time_server = NYToServer(anchorNyAmNY);
         outState.trueOpens.nyPmOpen.time_ny     = anchorNyPmNY;
         outState.trueOpens.nyPmOpen.time_server = NYToServer(anchorNyPmNY);
        }

      // Active session's True Session Open
      switch(outState.session)
        {
         case QT_SESSION_ASIA:   outState.trueOpens.sessionOpen = outState.trueOpens.asiaOpen;   break;
         case QT_SESSION_LONDON: outState.trueOpens.sessionOpen = outState.trueOpens.londonOpen; break;
         case QT_SESSION_NY_AM:  outState.trueOpens.sessionOpen = outState.trueOpens.nyAmOpen;   break;
         default:                outState.trueOpens.sessionOpen = outState.trueOpens.nyPmOpen;   break;
        }

      // 8. Permission & Friday Cutoff Evaluation
      switch(outState.dayeDayOfWeek)
        {
         case 1:  outState.isDayAllowed = m_cfg.allowMonday;    break;
         case 2:  outState.isDayAllowed = m_cfg.allowTuesday;   break;
         case 3:  outState.isDayAllowed = m_cfg.allowWednesday; break;
         case 4:  outState.isDayAllowed = m_cfg.allowThursday;  break;
         case 5:  outState.isDayAllowed = m_cfg.allowFriday;    break;
         default: outState.isDayAllowed = false;                break;
        }

      switch(outState.session)
        {
         case QT_SESSION_ASIA:   outState.isSessionAllowed = m_cfg.allowAsia;   break;
         case QT_SESSION_LONDON: outState.isSessionAllowed = m_cfg.allowLondon; break;
         case QT_SESSION_NY_AM:  outState.isSessionAllowed = m_cfg.allowNyAm;   break;
         case QT_SESSION_NY_PM:  outState.isSessionAllowed = m_cfg.allowNyPm;   break;
         default:                outState.isSessionAllowed = false;             break;
        }

      switch(outState.q90)
        {
         case QT_Q1: outState.isQ90Allowed = m_cfg.allow90mQ1; break;
         case QT_Q2: outState.isQ90Allowed = m_cfg.allow90mQ2; break;
         case QT_Q3: outState.isQ90Allowed = m_cfg.allow90mQ3; break;
         case QT_Q4: outState.isQ90Allowed = m_cfg.allow90mQ4; break;
         default:    outState.isQ90Allowed = false;            break;
        }

      // Check Friday Flat cutoff in NY time (e.g. Friday >= 15:00 NY, or Saturday)
      MqlDateTime dtNY;
      TimeToStruct(outState.nyTime, dtNY);
      if(dtNY.day_of_week == 5)
        {
         int curMinOfDay    = dtNY.hour * 60 + dtNY.min;
         int cutoffMinOfDay = m_cfg.fridayCloseHourNY * 60 + m_cfg.fridayCloseMinNY;
         outState.isFridayCutoffPassed = (curMinOfDay >= cutoffMinOfDay);
        }
      else if(dtNY.day_of_week == 6)
        {
         outState.isFridayCutoffPassed = true;
        }
      else
        {
         outState.isFridayCutoffPassed = false;
        }

      outState.isTimeAllowed = (outState.isDayAllowed &&
                                outState.isSessionAllowed &&
                                outState.isQ90Allowed &&
                                !outState.isFridayCutoffPassed);

      // v1.21: Mon / Fri open for Daily Cycle Phase D entries only (HTF tracker still uses isTimeAllowed)
      outState.isCycleOnlyDay = (!outState.isDayAllowed &&
                                 ((outState.dayeDayOfWeek == 1 && m_cfg.allowMondayCycleD) ||
                                  (outState.dayeDayOfWeek == 5 && m_cfg.allowFridayCycleD)));
      outState.isCycleTimeAllowed = ((outState.isDayAllowed || outState.isCycleOnlyDay) &&
                                     outState.isSessionAllowed &&
                                     outState.isQ90Allowed &&
                                     !outState.isFridayCutoffPassed);
     }

   //--- Update internal state for serverTime and return copy
   QTState           Update(const datetime serverTime, const bool resolvePrices = true)
     {
      Evaluate(serverTime, m_state, resolvePrices);
      return m_state;
     }
  };

#endif // QT_TIME_MQH
//+------------------------------------------------------------------+
