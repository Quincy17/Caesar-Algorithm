//+------------------------------------------------------------------+
//| TestSwings.mq5                                                   |
//| Fase 2 - Unit Tests for MTF_Data.mqh & Swings.mqh                |
//| Place in: MQL5/Scripts/TestSwings.mq5                            |
//+------------------------------------------------------------------+
#property copyright "Caesar Algorithm - QT-MSNR-ICT"
#property version   "1.10"
#property strict

#include "../Include/QT/Swings.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const bool cond, const string msg)
  {
   if(cond)
     {
      g_pass++;
      Print("PASS: ", msg);
     }
   else
     {
      g_fail++;
      Print("FAIL: ", msg);
     }
  }

void SetBar(MqlRates &r, const datetime t, const double o, const double h, const double l, const double c)
  {
   ZeroMemory(r);
   r.time  = t;
   r.open  = o;
   r.high  = h;
   r.low   = l;
   r.close = c;
  }

void OnStart()
  {
   Print("=== Starting Fase 2 Unit Tests: Swings.mqh ===");

   // Create 9 closed bars (series-indexed: 0 = newest closed bar, 8 = oldest closed bar)
   // With strength N = 2, valid pivot indices p are 2..6.
   MqlRates rates[];
   ArrayResize(rates, 9);
   ArraySetAsSeries(rates, true);

   datetime baseT = D'2026.10.27 12:00:00';
   // Index 6 (older): Wick Low = 2690, Body Close = 2695 (Classic V valley)
   // Index 3 (newer): Wick High = 2750, Body Close = 2742 (Classic A peak)
   SetBar(rates[8], baseT - 8 * 300, 2710, 2715, 2705, 2708);
   SetBar(rates[7], baseT - 7 * 300, 2708, 2710, 2698, 2700);
   SetBar(rates[6], baseT - 6 * 300, 2700, 2702, 2690, 2695); // <-- Swing Low at p=6
   SetBar(rates[5], baseT - 5 * 300, 2695, 2712, 2694, 2710);
   SetBar(rates[4], baseT - 4 * 300, 2710, 2730, 2708, 2725);
   SetBar(rates[3], baseT - 3 * 300, 2725, 2750, 2722, 2742); // <-- Swing High at p=3
   SetBar(rates[2], baseT - 2 * 300, 2742, 2740, 2728, 2730);
   SetBar(rates[1], baseT - 1 * 300, 2730, 2732, 2718, 2720);
   SetBar(rates[0], baseT - 0 * 300, 2720, 2725, 2715, 2718);

   SSwingPoint wickSwings[];
   int wickCnt = 0;
   SSwingPoint bodySwings[];
   int bodyCnt = 0;

   CSwingEngine::ScanRatesForSwings(rates, 9, TF_IDX_M5, 2, 50,
                                    wickSwings, wickCnt,
                                    bodySwings, bodyCnt);

   Check(wickCnt == 2, "Detected 2 Wick Swings (1 High, 1 Low)");
   Check(bodyCnt == 2, "Detected 2 Body Swings (1 High, 1 Low)");

   if(wickCnt == 2)
     {
      Check(wickSwings[0].type == SWING_HIGH && MathAbs(wickSwings[0].price - 2750.0) < 1e-5,
            "Newest Wick Swing is SWING_HIGH at 2750.0 (wick high)");
      Check(wickSwings[1].type == SWING_LOW  && MathAbs(wickSwings[1].price - 2690.0) < 1e-5,
            "Older Wick Swing is SWING_LOW at 2690.0 (wick low)");
     }

   if(bodyCnt == 2)
     {
      Check(bodySwings[0].type == SWING_HIGH && MathAbs(bodySwings[0].price - 2742.0) < 1e-5,
            "Newest Body Swing is SWING_HIGH at 2742.0 (close price, not wick)");
      Check(bodySwings[1].type == SWING_LOW  && MathAbs(bodySwings[1].price - 2695.0) < 1e-5,
            "Older Body Swing is SWING_LOW at 2695.0 (close price, not wick)");
     }

   // Zero-Repaint verification: append a new closed bar at index 0 (shifting existing bars by +1)
   MqlRates ratesNext[];
   ArrayResize(ratesNext, 10);
   ArraySetAsSeries(ratesNext, true);
   SetBar(ratesNext[0], baseT + 300, 2718, 2760, 2710, 2755); // Huge new bar after confirmation
   for(int i = 0; i < 9; i++)
      ratesNext[i + 1] = rates[i];

   SSwingPoint wickNext[];
   int wickNextCnt = 0;
   SSwingPoint bodyNext[];
   int bodyNextCnt = 0;

   CSwingEngine::ScanRatesForSwings(ratesNext, 10, TF_IDX_M5, 2, 50,
                                    wickNext, wickNextCnt,
                                    bodyNext, bodyNextCnt);

   Check(wickNextCnt == 2 &&
         wickNext[0].pivotTime == wickSwings[0].pivotTime &&
         MathAbs(wickNext[0].price - wickSwings[0].price) < 1e-5 &&
         wickNext[1].pivotTime == wickSwings[1].pivotTime &&
         MathAbs(wickNext[1].price - wickSwings[1].price) < 1e-5,
         "Zero-Repaint: Confirmed swings remain 100% identical in timestamp & price after new bar closes");

   PrintFormat("=== TestSwings finished: %d PASSED, %d FAILED ===", g_pass, g_fail);
  }
//+------------------------------------------------------------------+
