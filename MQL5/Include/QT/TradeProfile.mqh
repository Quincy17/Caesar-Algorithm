//+------------------------------------------------------------------+
//| TradeProfile.mqh                                                 |
//| M10 - Trade Profile Configuration & Multi-TF Bias Gate Logic     |
//| Place in: MQL5/Include/QT/TradeProfile.mqh                       |
//|                                                                  |
//| Profiles (PRD 4.10 + M15/M5 POI Refinement):                     |
//|  1. Scalping: Gate=H4    | Score=D1,W1 | POI=H1,M15,M5 | RR>=1.5 |
//|  2. Intraday: Gate=D1,H4 | Score=W1    | POI=H4,H1,M15,M5|RR>=2.0|
//|  3. Swing   : Gate=W1,D1 | Score=H4    | POI=W1,D1,H4,H1|RR>=3.0 |
//+------------------------------------------------------------------+
#ifndef QT_TRADE_PROFILE_MQH
#define QT_TRADE_PROFILE_MQH

#include "MTF_Data.mqh"

struct STradeProfileSpec
  {
   ENUM_TRADE_PROFILE  profile;
   ENUM_BIAS_GATE_MODE gateMode;

   // Individual bias TF toggles (allow user override if desired)
   bool                useW1Bias;
   bool                useD1Bias;
   bool                useH4Bias;

   // Gate TFs (true = mandatory gate for this profile)
   bool                isGateTF[3]; // Index: 0=W1, 1=D1, 2=H4
   // Score TFs (true = adds +1/-1 to confluence score)
   bool                isScoreTF[3];// Index: 0=W1, 1=D1, 2=H4

   // Allowed POI timeframes (W1..M5)
   bool                allowPOITF[QT_MTF_COUNT];

   // Primary Trigger TF (Sweep + MSS) and Entry TF (FVG / LTF POI)
   int                 triggerTfIdx;
   int                 secondaryTriggerTfIdx; // e.g., M5 inside M15/H1 POI for precision
   int                 entryTfIdx;

   // Minimum Risk-to-Reward ratio
   double              minRR;

   // Duration & Time Stop Rules
   bool                closeAt90mBlockEnd; // True for Scalping
   bool                closeAtDayeDayEnd;  // True for Intraday (before 18:00 NY)
   bool                closeOnFridayFlat;  // True for all profiles (mandatory for Swing)

   void Configure(const ENUM_TRADE_PROFILE prof,
                  const ENUM_BIAS_GATE_MODE mode = BIAS_GATE_STRICT,
                  const bool enableW1 = true,
                  const bool enableD1 = true,
                  const bool enableH4 = true,
                  const double customMinRR = 0.0)
     {
      profile   = prof;
      gateMode  = mode;
      useW1Bias = enableW1;
      useD1Bias = enableD1;
      useH4Bias = enableH4;

      ArrayInitialize(isGateTF,  false);
      ArrayInitialize(isScoreTF, false);
      ArrayInitialize(allowPOITF, false);

      closeOnFridayFlat = true;

      if(prof == PROFILE_SCALPING)
        {
         // Gate: H4 | Score: D1, W1 | POI: H1, M15, M5 | Trigger: M15/M5 | Entry: M5 | RR: 1.5
         isGateTF[TF_IDX_H4]  = enableH4;
         isScoreTF[TF_IDX_D1] = enableD1;
         isScoreTF[TF_IDX_W1] = enableW1;

         allowPOITF[TF_IDX_H1]  = true;
         allowPOITF[TF_IDX_M15] = true;
         allowPOITF[TF_IDX_M5]  = true;

         triggerTfIdx           = TF_IDX_M15;
         secondaryTriggerTfIdx  = TF_IDX_M5;
         entryTfIdx             = TF_IDX_M5;
         minRR                  = (customMinRR > 0.0 ? customMinRR : 1.5);

         closeAt90mBlockEnd     = true;
         closeAtDayeDayEnd      = true;
        }
      else if(prof == PROFILE_INTRADAY)
        {
         // Gate: D1 & H4 | Score: W1 | Anchor POI: D1, H4, H1 (Refined on M15/M5) | Trigger: M15/M5 | Entry: M5 | RR: 2.0
         isGateTF[TF_IDX_D1]  = enableD1;
         isGateTF[TF_IDX_H4]  = enableH4;
         isScoreTF[TF_IDX_W1] = enableW1;

         allowPOITF[TF_IDX_D1]  = true;
         allowPOITF[TF_IDX_H4]  = true;
         allowPOITF[TF_IDX_H1]  = true;
         allowPOITF[TF_IDX_M15] = false; // M15 & M5 used strictly for nested refinement inside HTF Anchor POIs
         allowPOITF[TF_IDX_M5]  = false;

         triggerTfIdx           = TF_IDX_M15;
         secondaryTriggerTfIdx  = TF_IDX_M5;
         entryTfIdx             = TF_IDX_M5;
         minRR                  = (customMinRR > 0.0 ? customMinRR : 2.0);

         closeAt90mBlockEnd     = false;
         closeAtDayeDayEnd      = true;
        }
      else // PROFILE_SWING
        {
         // Gate: W1 & D1 | Score: H4 | Anchor POI: W1, D1, H4, H1 | Trigger: H1 | Entry: M15 | RR: 3.0
         isGateTF[TF_IDX_W1]  = enableW1;
         isGateTF[TF_IDX_D1]  = enableD1;
         isScoreTF[TF_IDX_H4] = enableH4;

         allowPOITF[TF_IDX_W1]  = true;
         allowPOITF[TF_IDX_D1]  = true;
         allowPOITF[TF_IDX_H4]  = true;
         allowPOITF[TF_IDX_H1]  = true;
         allowPOITF[TF_IDX_M15] = false;

         triggerTfIdx           = TF_IDX_H1;
         secondaryTriggerTfIdx  = TF_IDX_M15;
         entryTfIdx             = TF_IDX_M15;
         minRR                  = (customMinRR > 0.0 ? customMinRR : 3.0);

         closeAt90mBlockEnd     = false;
         closeAtDayeDayEnd      = false;
        }
     }

   //--- Evaluate whether candidate trade direction (BIAS_BULL or BIAS_BEAR) passes Gate TFs
   bool CheckBiasGate(const ENUM_BIAS_DIR candidateDir,
                      const ENUM_BIAS_DIR biasW1,
                      const ENUM_BIAS_DIR biasD1,
                      const ENUM_BIAS_DIR biasH4) const
     {
      if(candidateDir == BIAS_NEUTRAL)
         return false;

      ENUM_BIAS_DIR oppDir = (candidateDir == BIAS_BULL ? BIAS_BEAR : BIAS_BULL);
      ENUM_BIAS_DIR tfBiases[3];
      tfBiases[0] = biasW1;
      tfBiases[1] = biasD1;
      tfBiases[2] = biasH4;

      int totalGates   = 0;
      int alignedGates = 0;
      int opposedGates = 0;

      for(int i = 0; i < 3; i++)
        {
         if(!isGateTF[i])
            continue;
         totalGates++;
         if(tfBiases[i] == candidateDir)
            alignedGates++;
         else if(tfBiases[i] == oppDir)
            opposedGates++;
        }

      if(totalGates == 0)
         return true;

      if(gateMode == BIAS_GATE_STRICT)
         return (alignedGates == totalGates);

      // BIAS_GATE_MAJORITY: no opposing gate TF, and at least 1 aligned gate TF
      return (alignedGates > 0 && opposedGates == 0 && alignedGates * 2 >= totalGates);
     }

   //--- Compute confluence score bonus from Score TFs (+1 aligned, 0 neutral, -1 opposing)
   int CalcBiasScoreBonus(const ENUM_BIAS_DIR candidateDir,
                          const ENUM_BIAS_DIR biasW1,
                          const ENUM_BIAS_DIR biasD1,
                          const ENUM_BIAS_DIR biasH4) const
     {
      if(candidateDir == BIAS_NEUTRAL)
         return 0;

      ENUM_BIAS_DIR oppDir = (candidateDir == BIAS_BULL ? BIAS_BEAR : BIAS_BULL);
      ENUM_BIAS_DIR tfBiases[3];
      tfBiases[0] = biasW1;
      tfBiases[1] = biasD1;
      tfBiases[2] = biasH4;

      int bonus = 0;
      for(int i = 0; i < 3; i++)
        {
         if(!isScoreTF[i])
            continue;
         if(tfBiases[i] == candidateDir)
            bonus += 1;
         else if(tfBiases[i] == oppDir)
            bonus -= 1;
        }
      return bonus;
     }
  };

#endif // QT_TRADE_PROFILE_MQH
//+------------------------------------------------------------------+
