//+------------------------------------------------------------------+
//|  SMC_Engine.mqh                                                  |
//|  Advanced Smart Money Concepts Analysis Engine                   |
//|  Covers: S&R, Internal/External BOS, MSS, Fresh OB,             |
//|  Open FVG, Equal H/L, Breaker, Displacement, OTE, Asian Range   |
//+------------------------------------------------------------------+
#ifndef SMC_ENGINE_MQH
#define SMC_ENGINE_MQH

//+------------------------------------------------------------------+
//| Extended TF Analysis Structure                                   |
//+------------------------------------------------------------------+
struct SMCAnalysis {
   string   name;

   //--- Basic direction
   bool     bullish;

   //--- Market Structure
   bool     hasExternalBOS;     // Breaks major swing high/low (HTF structure)
   bool     hasInternalBOS;     // Breaks minor swing inside range (LTF structure)
   bool     hasCHoCH;           // Change of Character (first sign of reversal)
   bool     hasMSS;             // Market Structure Shift (stronger than CHoCH)
   bool     hasDisplacement;    // Strong impulsive candle confirming direction
   bool     hasInducement;      // Fake CHoCH before real move (trap)

   //--- Order Blocks
   bool     hasFreshOB;         // OB not yet touched by price (valid)
   bool     hasMitigatedOB;     // OB already touched (weakened)
   bool     hasBreakerBlock;    // Old OB broken — now acts as opposite zone
   bool     hasRejectionBlock;  // Series of wicks at same level
   bool     hasPropulsionOB;    // Continuation OB inside trend
   double   obHigh;
   double   obLow;
   double   breakerHigh;
   double   breakerLow;
   string   obStatus;           // "Fresh" / "Mitigated" / "Broken"

   //--- Fair Value Gaps
   bool     hasFVGOpen;         // FVG not yet filled (valid trade zone)
   bool     hasFVGClosed;       // FVG fully filled (invalid)
   bool     hasInverseFVG;      // Violated FVG — now acts as opposite zone
   bool     hasVolumeImbalance; // Single candle, no wicks, large body
   double   fvgHigh;
   double   fvgLow;
   double   fvgMid;             // 50% of FVG — optimal entry

   //--- Liquidity
   bool     hasEqualHighs;      // Double/triple top = buy-side liquidity
   bool     hasEqualLows;       // Double/triple bottom = sell-side liquidity
   bool     hasLiqSweep;        // Price took liquidity then reversed
   bool     hasLiquidityVoid;   // Area with no price action (fast move)
   double   equalHighLevel;
   double   equalLowLevel;
   double   sweepLevel;

   //--- Support & Resistance
   double   weeklyHigh;
   double   weeklyLow;
   double   dailyHigh;
   double   dailyLow;
   double   prevDayHigh;
   double   prevDayLow;
   double   asianHigh;          // Asian session high
   double   asianLow;           // Asian session low
   double   nearestSR;          // Closest key S/R level to price
   bool     atKeySR;            // Price is AT a key S/R level

   //--- ICT / Advanced
   bool     inOTE;              // Price in Optimal Trade Entry zone (61.8-79%)
   double   oteHigh;
   double   oteLow;
   bool     isJudasSwing;       // False move at session open
   bool     inAsianRange;       // Price still inside Asian session range
   bool     aboveAsianHigh;     // Price broke above Asian range
   bool     belowAsianLow;      // Price broke below Asian range
   bool     inSilverBullet;     // Within ICT Silver Bullet time window

   //--- ICT Killzones (UTC-based)
   bool     inLondonKZ;         // 07:00-09:00 UTC (3PM-5PM PHT)
   bool     inNYAmKZ;           // 12:00-15:00 UTC (8PM-11PM PHT)
   bool     inNYPMKZ;           // 15:00-17:00 UTC (11PM-1AM PHT)
   bool     inAsianKZ;          // 21:00-23:00 UTC (5AM-7AM PHT)
   string   killzoneName;       // Active killzone label

   //--- Midnight Open & Opening Gaps
   double   midnightOpen;       // NY midnight price (05:00 UTC)
   bool     nearMidnightOpen;   // Price within range of midnight open
   bool     hasNDOG;            // New Day Opening Gap (today's open ≠ yesterday's close)
   double   ndogHigh;
   double   ndogLow;
   bool     hasNWOG;            // New Week Opening Gap (week open ≠ prev week close)
   double   nwogHigh;
   double   nwogLow;

   //--- Power of 3 (Accumulation → Manipulation → Distribution)
   bool     po3Accumulation;    // Tight Asian consolidation
   bool     po3Manipulation;    // Judas sweep occurred
   bool     po3Distribution;    // Real trend direction after manipulation
   string   po3Phase;

   //--- ICT Macros (ultra-precise high-probability windows)
   bool     inICTMacro;
   string   macroName;

   //--- Consequent Encroachment (CE = 50% of FVG — ideal entry)
   bool     atCE;
   double   ceLevel;

   //--- IPDA — Interbank Price Delivery Algorithm (20/40/60 day ranges)
   double   ipda20High;
   double   ipda20Low;
   double   ipda40High;
   double   ipda40Low;
   double   ipda60High;
   double   ipda60Low;
   bool     atIPDALevel;        // Price near an IPDA boundary

   //--- Balanced Price Range (overlapping bull + bear FVG — strongest zone)
   bool     hasBPR;
   double   bprHigh;
   double   bprLow;

   //--- Strong vs Weak Highs/Lows (ICT sweep targeting)
   bool     hasWeakHigh;        // High without BOS confirmation = sweep target
   double   weakHigh;
   bool     hasWeakLow;         // Low without BOS confirmation = sweep target
   double   weakLow;
   double   strongHigh;         // High confirmed by BOS
   double   strongLow;          // Low confirmed by BOS

   //--- Premium / Discount
   bool     inDiscount;
   bool     inPremium;
   bool     atEquilibrium;
   double   rangeHigh;
   double   rangeLow;
   double   rangeMid;

   //--- Narrative
   string   narrative;
   string   structureNarrative;
   string   liquidityNarrative;
   string   srNarrative;
   int      score;              // SMC confluence score for this TF
};

//+------------------------------------------------------------------+
//| Full SMC Analysis for one timeframe                             |
//+------------------------------------------------------------------+
SMCAnalysis AnalyzeSMC(string symbol, ENUM_TIMEFRAMES tf,
                       string tfName, int lookback) {
   SMCAnalysis a;
   a.name = tfName;

   int bars = iBars(symbol, tf);
   if(bars < lookback + 20) {
      a.narrative = "Waiting for bars...";
      return a;
   }

   double high[], low[], close[], open[];
   long   vol[];
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(vol,   true);

   int need = lookback + 5;
   if(CopyHigh (symbol, tf, 0, need, high)  < need ||
      CopyLow  (symbol, tf, 0, need, low)   < need ||
      CopyClose(symbol, tf, 0, need, close) < need ||
      CopyOpen (symbol, tf, 0, need, open)  < need) {
      a.narrative = "Loading...";
      return a;
   }
   CopyTickVolume(symbol, tf, 0, need, vol);

   double pip    = SymbolInfoDouble(symbol, SYMBOL_POINT) * 10;
   double price  = close[0];

   //================================================================
   // PREMIUM / DISCOUNT / EQUILIBRIUM
   //================================================================
   a.rangeHigh = high[ArrayMaximum(high, 0, lookback)];
   a.rangeLow  = low [ArrayMinimum(low,  0, lookback)];
   a.rangeMid  = (a.rangeHigh + a.rangeLow) / 2.0;
   a.inDiscount     = (price < a.rangeMid * 0.9995);
   a.inPremium      = (price > a.rangeMid * 1.0005);
   a.atEquilibrium  = (!a.inDiscount && !a.inPremium);

   //================================================================
   // WEEKLY / DAILY S&R LEVELS
   //================================================================
   // Weekly
   double whArr[], wlArr[];
   ArraySetAsSeries(whArr, true);
   ArraySetAsSeries(wlArr, true);
   if(CopyHigh(symbol, PERIOD_W1, 0, 3, whArr) >= 2)
      a.weeklyHigh = whArr[1];
   if(CopyLow(symbol, PERIOD_W1, 0, 3, wlArr) >= 2)
      a.weeklyLow  = wlArr[1];
   // Daily
   double dhArr[], dlArr[];
   ArraySetAsSeries(dhArr, true);
   ArraySetAsSeries(dlArr, true);
   if(CopyHigh(symbol, PERIOD_D1, 0, 3, dhArr) >= 2) {
      a.dailyHigh   = dhArr[0]; // Today high so far
      a.prevDayHigh = dhArr[1]; // Yesterday high
   }
   if(CopyLow(symbol, PERIOD_D1, 0, 3, dlArr) >= 2) {
      a.dailyLow   = dlArr[0];
      a.prevDayLow = dlArr[1];
   }

   // Asian session high/low (00:00-07:00 UTC)
   ComputeAsianRange(symbol, a);

   // Nearest key S/R to current price
   double srLevels[8];
   srLevels[0] = a.weeklyHigh; srLevels[1] = a.weeklyLow;
   srLevels[2] = a.dailyHigh;  srLevels[3] = a.dailyLow;
   srLevels[4] = a.prevDayHigh;srLevels[5] = a.prevDayLow;
   srLevels[6] = a.asianHigh;  srLevels[7] = a.asianLow;

   a.nearestSR = 0;
   double minDist = DBL_MAX;
   for(int k = 0; k < 8; k++) {
      if(srLevels[k] <= 0) continue;
      double dist = MathAbs(price - srLevels[k]);
      if(dist < minDist) { minDist = dist; a.nearestSR = srLevels[k]; }
   }
   a.atKeySR = (minDist < pip * 20);

   //================================================================
   // EXTERNAL BOS — breaks major swing (HTF structure)
   //================================================================
   int halfLB   = lookback / 2;
   double majorHigh = high[ArrayMaximum(high, halfLB, halfLB)]; // Older half
   double majorLow  = low [ArrayMinimum(low,  halfLB, halfLB)];

   a.hasExternalBOS = false;
   a.bullish        = false;
   if(close[0] > majorHigh) { a.hasExternalBOS = true; a.bullish = true; }
   else if(close[0] < majorLow) { a.hasExternalBOS = true; a.bullish = false; }
   else {
      // Fall back to recent trend
      a.bullish = (close[0] > close[MathMin(10, lookback-1)]);
   }

   //================================================================
   // INTERNAL BOS — breaks minor swing (inside the range)
   //================================================================
   int internalLB   = MathMin(15, lookback / 3);
   double minorHigh = high[ArrayMaximum(high, 1, internalLB)];
   double minorLow  = low [ArrayMinimum(low,  1, internalLB)];
   a.hasInternalBOS = false;
   if(a.bullish  && close[0] > minorHigh) a.hasInternalBOS = true;
   if(!a.bullish && close[0] < minorLow)  a.hasInternalBOS = true;

   //================================================================
   // CHOCH — first structural break opposite to recent swing
   //================================================================
   a.hasCHoCH = false;
   if(lookback >= 10) {
      double recentHigh = high[ArrayMaximum(high, 1, 5)];
      double recentLow  = low [ArrayMinimum(low,  1, 5)];
      double prevHigh   = high[ArrayMaximum(high, 6, MathMin(12, lookback-6))];
      double prevLow    = low [ArrayMinimum(low,  6, MathMin(12, lookback-6))];
      if(a.bullish  && recentHigh > prevHigh && close[0] > recentHigh) a.hasCHoCH = true;
      if(!a.bullish && recentLow  < prevLow  && close[0] < recentLow)  a.hasCHoCH = true;
   }

   //================================================================
   // LIQUIDITY SWEEP — must be computed before MSS (MSS requires it)
   //================================================================
   a.hasLiqSweep = false;
   a.sweepLevel  = 0;
   {
      int swLB = MathMin(15, lookback - 1);
      for(int i = 1; i < swLB; i++) {
         double psLow  = low [ArrayMinimum(low,  i+1, MathMin(10, lookback-i-1))];
         double psHigh = high[ArrayMaximum(high, i+1, MathMin(10, lookback-i-1))];
         if(a.bullish && low[i] < psLow && close[i] > psLow) {
            a.hasLiqSweep = true; a.sweepLevel = psLow; break;
         }
         if(!a.bullish && high[i] > psHigh && close[i] < psHigh) {
            a.hasLiqSweep = true; a.sweepLevel = psHigh; break;
         }
      }
   }

   //================================================================
   // MSS — Market Structure Shift (stronger than CHoCH)
   // Requires CHoCH + liquidity sweep + displacement candle
   //================================================================
   a.hasMSS = false;
   if(a.hasCHoCH && a.hasLiqSweep) {
      for(int i = 1; i <= 5; i++) {
         double body = MathAbs(close[i] - open[i]);
         double range= high[i] - low[i];
         if(range > 0 && body / range > 0.7 && body > pip * 3) {
            a.hasMSS = true;
            break;
         }
      }
   }

   //================================================================
   // DISPLACEMENT — strong impulsive candle
   //================================================================
   a.hasDisplacement = false;
   for(int i = 1; i <= 5; i++) {
      double body  = MathAbs(close[i] - open[i]);
      double range = high[i] - low[i];
      bool   bullCandle = close[i] > open[i];
      // Large body (>70% of range) AND bigger than average
      double avgBody = 0;
      for(int j = 6; j <= 15 && j < lookback; j++)
         avgBody += MathAbs(close[j] - open[j]);
      avgBody /= 10.0;
      if(body > avgBody * 2.0 && range > 0 && body / range > 0.65) {
         if(a.bullish == bullCandle) { a.hasDisplacement = true; break; }
      }
   }

   //================================================================
   // INDUCEMENT — fake CHoCH before real move
   // Pattern: CHoCH forms, then price sweeps the CHoCH level before
   // continuing in the original direction
   //================================================================
   a.hasInducement = false;
   if(a.hasCHoCH) {
      // Check if price quickly reversed after the CHoCH candle
      double chochCandle = a.bullish ? low[2] : high[2];
      if(a.bullish  && low[1] < chochCandle && close[0] > open[0]) a.hasInducement = true;
      if(!a.bullish && high[1] > chochCandle && close[0] < open[0]) a.hasInducement = true;
   }

   //================================================================
   // ORDER BLOCKS — Fresh, Mitigated, Breaker
   //================================================================
   a.hasFreshOB     = false;
   a.hasMitigatedOB = false;
   a.hasBreakerBlock= false;
   a.obHigh = a.obLow = a.breakerHigh = a.breakerLow = 0;
   a.obStatus = "None";

   int obLB = MathMin(20, lookback - 2);
   for(int i = 2; i < obLB; i++) {
      double body     = MathAbs(close[i] - open[i]);
      double nextBody = MathAbs(close[i-1] - open[i-1]);
      bool   bigMove  = (nextBody > body * 2.0);

      // Bullish OB: last bearish candle before big bullish move
      if(a.bullish && close[i] < open[i] && close[i-1] > open[i-1] && bigMove) {
         double obH = high[i], obL = low[i];
         // Check if price has returned to this OB (mitigated)
         bool mitigated = false;
         for(int m = 1; m < i; m++) {
            if(low[m] <= obH && high[m] >= obL) { mitigated = true; break; }
         }
         if(!mitigated) {
            a.hasFreshOB = true;
            a.obHigh = obH; a.obLow = obL;
            a.obStatus = "Fresh";

            // Check if price is currently IN the OB (optimal entry)
            if(price <= obH && price >= obL)
               a.obStatus = "In OB — Entry Zone";
         } else {
            a.hasMitigatedOB = true;
            a.obStatus = "Mitigated";

            // Breaker Block: OB was mitigated then broken
            if(price < obL) {
               a.hasBreakerBlock = true;
               a.breakerHigh = obH; a.breakerLow = obL;
               a.obStatus = "Breaker Block";
            }
         }
         break;
      }

      // Bearish OB: last bullish candle before big bearish move
      if(!a.bullish && close[i] > open[i] && close[i-1] < open[i-1] && bigMove) {
         double obH = high[i], obL = low[i];
         bool mitigated = false;
         for(int m = 1; m < i; m++) {
            if(low[m] <= obH && high[m] >= obL) { mitigated = true; break; }
         }
         if(!mitigated) {
            a.hasFreshOB = true;
            a.obHigh = obH; a.obLow = obL;
            a.obStatus = "Fresh";
            if(price <= obH && price >= obL)
               a.obStatus = "In OB — Entry Zone";
         } else {
            a.hasMitigatedOB = true;
            a.obStatus = "Mitigated";
            if(price > obH) {
               a.hasBreakerBlock = true;
               a.breakerHigh = obH; a.breakerLow = obL;
               a.obStatus = "Breaker Block";
            }
         }
         break;
      }
   }

   // Rejection Block: multiple wicks at same level
   a.hasRejectionBlock = DetectRejectionBlock(high, low, close, open,
                                               a.bullish, lookback);

   //================================================================
   // FVG — Open, Closed, Inverse, Volume Imbalance
   //================================================================
   a.hasFVGOpen    = false;
   a.hasFVGClosed  = false;
   a.hasInverseFVG = false;
   a.fvgHigh = a.fvgLow = a.fvgMid = 0;

   int fvgLB = MathMin(20, lookback - 2);
   for(int i = 1; i < fvgLB - 1; i++) {
      double gapHi = 0, gapLo = 0;
      bool   bullFVG = false;

      // Bullish FVG
      if(a.bullish && low[i-1] > high[i+1]) {
         gapHi = low[i-1]; gapLo = high[i+1]; bullFVG = true;
      }
      // Bearish FVG
      if(!a.bullish && high[i-1] < low[i+1]) {
         gapHi = low[i+1]; gapLo = high[i-1]; bullFVG = false;
      }

      if(gapHi > 0 && gapLo > 0) {
         // Check if FVG is still open (price has not entered the gap)
         bool filled = false;
         for(int m = 1; m <= i; m++) {
            if(bullFVG  && low[m]  < gapHi) { filled = true; break; }
            if(!bullFVG && high[m] > gapLo) { filled = true; break; }
         }
         if(!filled) {
            a.hasFVGOpen = true;
            a.fvgHigh    = gapHi;
            a.fvgLow     = gapLo;
            a.fvgMid     = (gapHi + gapLo) / 2.0;
         } else {
            a.hasFVGClosed = true;
            // Inverse FVG: filled FVG now acts as opposing zone
            if(bullFVG && price < gapLo) a.hasInverseFVG = true;
            if(!bullFVG && price > gapHi) a.hasInverseFVG = true;
         }
         break;
      }
   }

   // Volume Imbalance: candle with body > 90% of range
   a.hasVolumeImbalance = false;
   for(int i = 1; i <= 5; i++) {
      double body  = MathAbs(close[i] - open[i]);
      double range = high[i] - low[i];
      if(range > 0 && body / range > 0.90) {
         a.hasVolumeImbalance = true; break;
      }
   }

   //================================================================
   // EQUAL HIGHS / EQUAL LOWS (Liquidity Pools)
   //================================================================
   a.hasEqualHighs    = false;
   a.hasEqualLows     = false;
   a.equalHighLevel   = 0;
   a.equalLowLevel    = 0;
   double eqTolerance = pip * 3; // Within 3 pips = equal
   int eqLB = MathMin(30, lookback);

   for(int i = 2; i < eqLB - 1; i++) {
      for(int j = i + 2; j < eqLB; j++) {
         // Equal Highs
         if(MathAbs(high[i] - high[j]) <= eqTolerance &&
            high[i] > high[i-1] && high[i] > high[i+1] &&
            high[j] > high[j-1] && high[j] > high[j+1]) {
            a.hasEqualHighs  = true;
            a.equalHighLevel = (high[i] + high[j]) / 2.0;
         }
         // Equal Lows
         if(MathAbs(low[i] - low[j]) <= eqTolerance &&
            low[i] < low[i-1] && low[i] < low[i+1] &&
            low[j] < low[j-1] && low[j] < low[j+1]) {
            a.hasEqualLows  = true;
            a.equalLowLevel = (low[i] + low[j]) / 2.0;
         }
         if(a.hasEqualHighs && a.hasEqualLows) break;
      }
      if(a.hasEqualHighs && a.hasEqualLows) break;
   }

   //================================================================
   // LIQUIDITY VOID — fast move with no wicks (gaps in price)
   //================================================================
   a.hasLiquidityVoid = false;
   for(int i = 1; i <= 10 && i < lookback; i++) {
      // If next candle open is far from previous close = void
      double openGap = MathAbs(open[i] - close[i+1]);
      if(openGap > pip * 8) { a.hasLiquidityVoid = true; break; }
   }

   //================================================================
   // OTE — Optimal Trade Entry (Fibonacci 61.8% - 79%)
   //================================================================
   a.inOTE = false;
   a.oteHigh = a.oteLow = 0;
   if(a.hasLiqSweep && a.sweepLevel > 0) {
      double swing = a.bullish ?
                     high[ArrayMaximum(high, 1, MathMin(20, lookback-1))] :
                     low [ArrayMinimum(low,  1, MathMin(20, lookback-1))];
      double swingRange = MathAbs(swing - a.sweepLevel);
      if(swingRange > 0) {
         if(a.bullish) {
            a.oteHigh = swing - swingRange * 0.618;
            a.oteLow  = swing - swingRange * 0.79;
         } else {
            a.oteLow  = swing + swingRange * 0.618;
            a.oteHigh = swing + swingRange * 0.79;
         }
         // Check if current price is in OTE zone
         if(price >= MathMin(a.oteHigh, a.oteLow) &&
            price <= MathMax(a.oteHigh, a.oteLow))
            a.inOTE = true;
      }
   }

   //================================================================
   // ASIAN RANGE STATUS
   //================================================================
   a.inAsianRange    = (a.asianHigh > 0 && price <= a.asianHigh && price >= a.asianLow);
   a.aboveAsianHigh  = (a.asianHigh > 0 && price > a.asianHigh);
   a.belowAsianLow   = (a.asianLow  > 0 && price < a.asianLow);

   //================================================================
   // JUDAS SWING — false move at London/NY open then reversal
   //================================================================
   a.isJudasSwing = false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int phtHour = (dt.hour + 8) % 24;
   bool atSessionOpen = (phtHour >= 15 && phtHour < 17) || // London open window
                        (phtHour >= 20 && phtHour < 22);   // NY open window
   if(atSessionOpen && a.hasLiqSweep && a.hasCHoCH)
      a.isJudasSwing = true;

   //================================================================
   // SILVER BULLET WINDOWS — 3AM, 10AM, 2PM NY = 15UTC, 22UTC, 2UTC
   // In PHT (+8): 3AM NY=11PM PHT, 10AM NY=11PM PHT+1h, 2PM NY=3AM PHT
   // Most active: 10AM NY = 15:00 UTC = 23:00 PHT
   //================================================================
   a.inSilverBullet = (phtHour == 23 || phtHour == 3);

   //================================================================
   // REJECTION BLOCK / PROPULSION BLOCK
   //================================================================
   a.hasPropulsionOB = DetectPropulsionBlock(high, low, close, open,
                                              a.bullish, lookback);

   //================================================================
   // ICT KILLZONES (UTC hours)
   //================================================================
   int utcH = dt.hour;
   int utcM = dt.min;
   int utcT = utcH * 100 + utcM; // HHMM integer for range checks
   a.inAsianKZ   = (utcT >= 2100 && utcT <  2300);
   a.inLondonKZ  = (utcT >= 700  && utcT <   900);
   a.inNYAmKZ    = (utcT >= 1200 && utcT <  1500);
   a.inNYPMKZ    = (utcT >= 1500 && utcT <  1700);
   a.killzoneName = a.inLondonKZ ? "London KZ (3PM-5PM PHT)" :
                    a.inNYAmKZ   ? "NY AM KZ (8PM-11PM PHT)" :
                    a.inNYPMKZ   ? "NY PM/Close KZ (11PM-1AM PHT)" :
                    a.inAsianKZ  ? "Asian KZ (5AM-7AM PHT)" : "No Active KZ";

   //================================================================
   // ICT MACROS (UTC times — NY EST + 5 hours)
   // NY 02:33-03:00 | 04:03-04:30 | 08:50-09:10 | 10:10-10:40 | 11:50-12:10
   //================================================================
   int macroStart[5] = {733, 903, 1350, 1510, 1650};
   int macroEnd[5]   = {800, 930, 1410, 1540, 1710};
   string macroLabels[5] = {
      "London Open Macro (3:33-4:00 PM PHT)",
      "London AM Macro (5:03-5:30 PM PHT)",
      "NY Lunch Macro (9:50-10:10 PM PHT)",
      "NY AM Macro (11:10-11:40 PM PHT)",
      "NY PM Macro (12:50-1:10 AM PHT)"
   };
   a.inICTMacro = false;
   a.macroName  = "";
   for(int mi = 0; mi < 5; mi++) {
      if(utcT >= macroStart[mi] && utcT <= macroEnd[mi]) {
         a.inICTMacro = true;
         a.macroName  = macroLabels[mi];
         break;
      }
   }

   //================================================================
   // MIDNIGHT OPEN — NY midnight = 05:00 UTC (EST, approx)
   //================================================================
   a.midnightOpen    = 0;
   a.nearMidnightOpen = false;
   {
      datetime midnightUTC = StringToTime(StringFormat("%04d.%02d.%02d 05:00",
                                                        dt.year, dt.mon, dt.day));
      double moOpen[];
      ArraySetAsSeries(moOpen, false);
      if(CopyOpen(symbol, PERIOD_H1, midnightUTC, 1, moOpen) > 0) {
         a.midnightOpen     = moOpen[0];
         a.nearMidnightOpen = (a.midnightOpen > 0 &&
                               MathAbs(price - a.midnightOpen) < pip * 15);
      }
   }

   //================================================================
   // NEW DAY OPENING GAP (NDOG) & NEW WEEK OPENING GAP (NWOG)
   //================================================================
   a.hasNDOG = false; a.ndogHigh = 0; a.ndogLow = 0;
   a.hasNWOG = false; a.nwogHigh = 0; a.nwogLow = 0;
   {
      double d1O[], d1C[];
      ArraySetAsSeries(d1O, true); ArraySetAsSeries(d1C, true);
      if(CopyOpen (symbol, PERIOD_D1, 0, 3, d1O) >= 2 &&
         CopyClose(symbol, PERIOD_D1, 0, 3, d1C) >= 2) {
         double gap = d1O[0] - d1C[1];
         if(MathAbs(gap) > pip * 3) {
            a.hasNDOG = true;
            a.ndogHigh = MathMax(d1O[0], d1C[1]);
            a.ndogLow  = MathMin(d1O[0], d1C[1]);
         }
      }
      double w1O[], w1C[];
      ArraySetAsSeries(w1O, true); ArraySetAsSeries(w1C, true);
      if(CopyOpen (symbol, PERIOD_W1, 0, 3, w1O) >= 2 &&
         CopyClose(symbol, PERIOD_W1, 0, 3, w1C) >= 2) {
         double wgap = w1O[0] - w1C[1];
         if(MathAbs(wgap) > pip * 5) {
            a.hasNWOG = true;
            a.nwogHigh = MathMax(w1O[0], w1C[1]);
            a.nwogLow  = MathMin(w1O[0], w1C[1]);
         }
      }
   }

   //================================================================
   // POWER OF 3 — Accumulation → Manipulation → Distribution
   //================================================================
   {
      double asianRange = a.asianHigh - a.asianLow;
      a.po3Accumulation = (asianRange > 0 && asianRange < pip * 40 && a.inAsianRange);
      a.po3Manipulation = (a.hasLiqSweep &&
                           (a.aboveAsianHigh || a.belowAsianLow) && a.hasCHoCH);
      a.po3Distribution = (a.po3Manipulation && a.hasMSS && a.hasDisplacement);
      a.po3Phase = a.po3Distribution ? "3-Distribution (TRADE NOW)" :
                   a.po3Manipulation ? "2-Manipulation (Judas Active)" :
                   a.po3Accumulation ? "1-Accumulation (Wait)" : "No PO3 Signal";
   }

   //================================================================
   // CONSEQUENT ENCROACHMENT — 50% of FVG = CE level
   //================================================================
   a.atCE    = false;
   a.ceLevel = 0;
   if(a.hasFVGOpen && a.fvgMid > 0) {
      a.ceLevel = a.fvgMid;
      a.atCE    = (MathAbs(price - a.fvgMid) < pip * 5);
   }

   //================================================================
   // IPDA — 20 / 40 / 60 day range boundaries
   //================================================================
   a.atIPDALevel = false;
   a.ipda20High = a.ipda20Low = a.ipda40High = a.ipda40Low =
   a.ipda60High = a.ipda60Low = 0;
   {
      double dH[], dL[];
      ArraySetAsSeries(dH, true); ArraySetAsSeries(dL, true);
      if(CopyHigh(symbol, PERIOD_D1, 0, 65, dH) >= 62 &&
         CopyLow (symbol, PERIOD_D1, 0, 65, dL) >= 62) {
         a.ipda20High = dH[ArrayMaximum(dH, 0, 20)];
         a.ipda20Low  = dL[ArrayMinimum(dL, 0, 20)];
         a.ipda40High = dH[ArrayMaximum(dH, 0, 40)];
         a.ipda40Low  = dL[ArrayMinimum(dL, 0, 40)];
         a.ipda60High = dH[ArrayMaximum(dH, 0, 60)];
         a.ipda60Low  = dL[ArrayMinimum(dL, 0, 60)];
         double ipdaLvl[6] = {a.ipda20High, a.ipda20Low,
                               a.ipda40High, a.ipda40Low,
                               a.ipda60High, a.ipda60Low};
         for(int il = 0; il < 6; il++) {
            if(ipdaLvl[il] > 0 && MathAbs(price - ipdaLvl[il]) < pip * 25) {
               a.atIPDALevel = true; break;
            }
         }
      }
   }

   //================================================================
   // BALANCED PRICE RANGE — overlapping bull + bear FVG
   //================================================================
   a.hasBPR = false; a.bprHigh = 0; a.bprLow = 0;
   if(a.hasFVGOpen && a.fvgHigh > 0) {
      int bprLB = MathMin(30, lookback - 2);
      for(int i = 2; i < bprLB - 1; i++) {
         double oHi = 0, oLo = 0;
         if(a.bullish && high[i-1] < low[i+1]) {        // bearish FVG in area
            oHi = low[i+1]; oLo = high[i-1];
         } else if(!a.bullish && low[i-1] > high[i+1]) { // bullish FVG in area
            oHi = low[i-1]; oLo = high[i+1];
         }
         if(oHi > 0 && oLo < a.fvgHigh && oHi > a.fvgLow) {
            a.hasBPR  = true;
            a.bprHigh = MathMin(oHi, a.fvgHigh);
            a.bprLow  = MathMax(oLo, a.fvgLow);
            break;
         }
      }
   }

   //================================================================
   // STRONG vs WEAK HIGHS/LOWS
   // Strong = swing formed with a BOS confirmation (reliable level)
   // Weak   = swing with no BOS = price will likely return and sweep it
   //================================================================
   a.hasWeakHigh = false; a.weakHigh  = 0;
   a.hasWeakLow  = false; a.weakLow   = 0;
   a.strongHigh  = 0;     a.strongLow = 0;
   {
      int swHL = MathMin(lookback, 40);
      for(int i = 3; i < swHL - 3; i++) {
         // Swing high at bar i
         if(high[i] > high[i-1] && high[i] > high[i-2] &&
            high[i] > high[i+1] && high[i] > high[i+2]) {
            // BOS down from this high = strong (a lower low broke below a prior low)
            double refLow = low[ArrayMinimum(low, i+1, MathMin(10, swHL-i-1))];
            bool   bosDown = false;
            for(int j = 1; j < i; j++) {
               if(close[j] < refLow) { bosDown = true; break; }
            }
            if(bosDown) { if(high[i] > a.strongHigh) a.strongHigh = high[i]; }
            else {
               a.hasWeakHigh = true;
               if(high[i] > a.weakHigh) a.weakHigh = high[i];
            }
         }
         // Swing low at bar i
         if(low[i] < low[i-1] && low[i] < low[i-2] &&
            low[i] < low[i+1] && low[i] < low[i+2]) {
            double refHigh = high[ArrayMaximum(high, i+1, MathMin(10, swHL-i-1))];
            bool   bosUp   = false;
            for(int j = 1; j < i; j++) {
               if(close[j] > refHigh) { bosUp = true; break; }
            }
            if(bosUp) { if(a.strongLow == 0 || low[i] < a.strongLow) a.strongLow = low[i]; }
            else {
               a.hasWeakLow = true;
               if(a.weakLow == 0 || low[i] < a.weakLow) a.weakLow = low[i];
            }
         }
      }
   }

   //================================================================
   // BUILD NARRATIVES
   //================================================================
   string dir  = a.bullish ? "BULLISH" : "BEARISH";
   string zone = a.inDiscount ? "Discount" : (a.inPremium ? "Premium" : "Equilibrium");

   a.structureNarrative = StringFormat(
      "%s | %s | ExtBOS:%s | CHoCH:%s | MSS:%s | Disp:%s | PO3:%s",
      dir, zone,
      a.hasExternalBOS  ? "Y" : "N",
      a.hasCHoCH        ? "Y" : "N",
      a.hasMSS          ? "Y" : "N",
      a.hasDisplacement ? "Y" : "N",
      a.po3Phase);

   string obStr  = a.hasFreshOB      ? StringFormat("FreshOB(%.2f-%.2f)", a.obLow, a.obHigh) :
                   a.hasBreakerBlock  ? "BreakerBlk" :
                   a.hasMitigatedOB   ? "OB-Mitigated" : "NoOB";
   string fvgStr = a.hasBPR          ? StringFormat("BPR(%.2f-%.2f)", a.bprLow, a.bprHigh) :
                   a.hasFVGOpen       ? StringFormat("FVG(%.2f CE:%.2f)", a.fvgLow, a.ceLevel) :
                   a.hasInverseFVG    ? "InvFVG" :
                   a.hasFVGClosed     ? "FVG-Closed" : "NoFVG";

   a.liquidityNarrative = StringFormat(
      "%s | %s | Sweep:%s | OTE:%s | WkHi:%s | WkLo:%s",
      obStr, fvgStr,
      a.hasLiqSweep   ? "Y" : "N",
      a.inOTE         ? "IN" : "N",
      a.hasWeakHigh   ? StringFormat("Y@%.2f", a.weakHigh) : "N",
      a.hasWeakLow    ? StringFormat("Y@%.2f", a.weakLow)  : "N");

   a.srNarrative = StringFormat(
      "KZ:%s | %s | MidOpen:%.2f | IPDA20:%.2f-%.2f | W:%.2f/%.2f",
      a.killzoneName,
      a.inICTMacro    ? StringFormat("MACRO:%s", a.macroName) : "No Macro",
      a.midnightOpen,
      a.ipda20Low, a.ipda20High,
      a.weeklyHigh, a.weeklyLow);

   a.narrative = a.structureNarrative;

   //================================================================
   // SCORE THIS TIMEFRAME (max ~42 base + ~18 ICT = ~60 total)
   //================================================================
   a.score = 0;
   // --- Base SMC (max 30) ---
   if(a.hasExternalBOS)              a.score += 3;
   if(a.hasInternalBOS)              a.score += 1;
   if(a.hasCHoCH)                    a.score += 2;
   if(a.hasMSS)                      a.score += 3;
   if(a.hasDisplacement)             a.score += 2;
   if(a.hasFreshOB)                  a.score += 3;
   if(a.hasBreakerBlock)             a.score += 2;
   if(a.hasFVGOpen)                  a.score += 2;
   if(a.hasVolumeImbalance)          a.score += 1;
   if(a.hasLiqSweep)                 a.score += 3;
   if(a.hasEqualHighs || a.hasEqualLows) a.score += 2;
   if(a.inOTE)                       a.score += 2;
   if(a.atKeySR)                     a.score += 2;
   if(a.hasInducement)               a.score += 1;
   if(a.isJudasSwing)                a.score += 2;
   if(a.inSilverBullet)              a.score += 1;
   // --- ICT Advanced (max 18) ---
   if(a.inLondonKZ || a.inNYAmKZ)    a.score += 3;  // In major killzone
   if(a.inICTMacro)                   a.score += 3;  // In ICT macro window
   if(a.po3Distribution)              a.score += 3;  // PO3 distribution phase
   if(a.atCE)                         a.score += 2;  // At consequent encroachment
   if(a.hasBPR)                       a.score += 2;  // Balanced price range
   if(a.atIPDALevel)                  a.score += 2;  // At IPDA boundary
   if(a.nearMidnightOpen)             a.score += 2;  // Near NY midnight open
   if(a.hasNDOG || a.hasNWOG)        a.score += 1;  // Opening gap present
   if(a.hasWeakHigh && !a.bullish)    a.score += 1;  // Weak high = sweep target above
   if(a.hasWeakLow  &&  a.bullish)    a.score += 1;  // Weak low  = sweep target below
   // --- Penalties ---
   if(a.hasMitigatedOB && !a.hasFreshOB) a.score -= 2;
   if(a.hasFVGClosed   && !a.hasFVGOpen) a.score -= 1;

   return a;
}

//+------------------------------------------------------------------+
//| Compute Asian Session Range (00:00-07:00 UTC)                   |
//+------------------------------------------------------------------+
void ComputeAsianRange(string symbol, SMCAnalysis &a) {
   a.asianHigh = 0;
   a.asianLow  = DBL_MAX;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   // Find start of today's Asian session (00:00 UTC)
   datetime asianStart = StringToTime(StringFormat("%04d.%02d.%02d 00:00",
                                                   now.year, now.mon, now.day));
   datetime asianEnd   = asianStart + 7 * 3600; // 07:00 UTC

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(symbol, PERIOD_M15, asianStart, asianEnd, rates);
   if(copied <= 0) { a.asianHigh = 0; a.asianLow = 0; return; }

   a.asianHigh = rates[0].high;
   a.asianLow  = rates[0].low;
   for(int i = 1; i < copied; i++) {
      if(rates[i].high > a.asianHigh) a.asianHigh = rates[i].high;
      if(rates[i].low  < a.asianLow)  a.asianLow  = rates[i].low;
   }
}

//+------------------------------------------------------------------+
//| Detect Rejection Block (multiple wicks at same level)           |
//+------------------------------------------------------------------+
bool DetectRejectionBlock(const double &high[], const double &low[],
                          const double &close[], const double &open[],
                          bool bullish, int lookback) {
   double pip   = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   int    count = 0;
   double refLevel = bullish ? low[1] : high[1];

   int rb = MathMin(lookback, 20);
   for(int i = 1; i < rb; i++) {
      double wick = bullish ? MathAbs(low[i]  - refLevel)
                            : MathAbs(high[i] - refLevel);
      if(wick < pip * 3) count++;
   }
   return (count >= 3);
}

//+------------------------------------------------------------------+
//| Detect Propulsion Block (continuation OB inside trend)          |
//+------------------------------------------------------------------+
bool DetectPropulsionBlock(const double &high[], const double &low[],
                           const double &close[], const double &open[],
                           bool bullish, int lookback) {
   int pb = MathMin(lookback, 15);
   for(int i = 2; i < pb; i++) {
      bool inTrend    = bullish ? (close[i] > close[i+1]) : (close[i] < close[i+1]);
      bool correction = bullish ? (close[i-1] < close[i]) : (close[i-1] > close[i]);
      bool resume     = bullish ? (close[0]   > close[i]) : (close[0]   < close[i]);
      if(inTrend && correction && resume) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Advanced Confluence Score — Primary H4/H1/M15                  |
//+------------------------------------------------------------------+
int ScorePrimaryAdvanced(SMCAnalysis &h4, SMCAnalysis &h1, SMCAnalysis &m15) {
   int score = 0;

   // H4 — Direction & Structure (max 15)
   if(h4.hasExternalBOS && h4.bullish == h1.bullish) score += 3;
   if(h4.hasFreshOB)                                  score += 3;
   if((h4.bullish && h4.inDiscount) ||
      (!h4.bullish && h4.inPremium))                  score += 2;
   if(h4.atKeySR)                                     score += 2;
   if(h4.hasEqualHighs || h4.hasEqualLows)            score += 2;
   if(h4.hasMSS)                                      score += 3;

   // H1 — Zone & Confirmation (max 14)
   if(h1.hasCHoCH && h1.bullish == h4.bullish)        score += 2;
   if(h1.hasMSS)                                      score += 3;
   if(h1.hasFreshOB && h1.hasLiqSweep)               score += 3;
   if(h1.hasFVGOpen)                                  score += 2;
   if(h1.inOTE)                                       score += 2;
   if(h1.hasDisplacement)                             score += 2;

   // M15 — Entry Trigger (max 13)
   if(m15.hasLiqSweep)                                score += 3;
   if(m15.hasCHoCH || m15.hasMSS)                    score += 3;
   if(m15.hasFVGOpen)                                 score += 2;
   if(m15.hasFreshOB)                                 score += 2;
   if(m15.isJudasSwing)                               score += 2;
   if(m15.inSilverBullet)                             score += 1;

   // ICT Advanced Bonuses — Primary (max +18)
   if(m15.inLondonKZ || m15.inNYAmKZ)              score += 3; // Prime killzone
   if(m15.inICTMacro)                               score += 3; // ICT macro window
   if(m15.po3Distribution)                          score += 3; // PO3 distribution phase
   if(m15.atCE)                                     score += 2; // Consequent encroachment
   if(h1.hasBPR)                                    score += 2; // Balanced price range
   if(h4.atIPDALevel)                               score += 2; // IPDA price delivery level
   if(m15.nearMidnightOpen)                         score += 1; // Near NY midnight open
   if(h1.hasNDOG || h4.hasNWOG)                   score += 1; // Gap present (NDOG/NWOG)
   if(m15.hasWeakLow  &&  h4.bullish)              score += 1; // Weak low as bull target
   if(m15.hasWeakHigh && !h4.bullish)              score += 1; // Weak high as bear target

   // Penalties
   if(h4.hasMitigatedOB && !h4.hasFreshOB)            score -= 3;
   if(h1.hasFVGClosed    && !h1.hasFVGOpen)            score -= 2;
   if(h4.bullish != h1.bullish)                        score -= 4; // Conflicting bias

   return MathMax(0, score);
}

//+------------------------------------------------------------------+
//| Advanced Confluence Score — Fallback H1/M15/M5                 |
//+------------------------------------------------------------------+
int ScoreFallbackAdvanced(SMCAnalysis &h1, SMCAnalysis &m15, SMCAnalysis &m5) {
   int score = 0;

   if(h1.hasExternalBOS && h1.bullish == m15.bullish)  score += 3;
   if(h1.hasFreshOB)                                    score += 3;
   if((h1.bullish && h1.inDiscount) ||
      (!h1.bullish && h1.inPremium))                    score += 2;
   if(h1.atKeySR)                                       score += 2;
   if(h1.hasMSS)                                        score += 3;

   if(m15.hasCHoCH && m15.bullish == h1.bullish)        score += 2;
   if(m15.hasFreshOB && m15.hasLiqSweep)               score += 3;
   if(m15.hasFVGOpen)                                   score += 2;
   if(m15.inOTE)                                        score += 2;

   if(m5.hasLiqSweep)                                   score += 3;
   if(m5.hasCHoCH || m5.hasMSS)                        score += 3;
   if(m5.hasFVGOpen)                                    score += 2;
   if(m5.hasDisplacement)                               score += 2;

   // ICT Advanced Bonuses — Fallback (max +18)
   if(m5.inLondonKZ || m5.inNYAmKZ)                score += 3;
   if(m5.inICTMacro)                                score += 3;
   if(m5.po3Distribution)                           score += 3;
   if(m5.atCE)                                      score += 2;
   if(m15.hasBPR)                                   score += 2;
   if(h1.atIPDALevel)                               score += 2;
   if(m5.nearMidnightOpen)                          score += 1;
   if(m15.hasNDOG || h1.hasNWOG)                  score += 1;
   if(m5.hasWeakLow  &&  h1.bullish)               score += 1;
   if(m5.hasWeakHigh && !h1.bullish)               score += 1;

   if(h1.hasMitigatedOB && !h1.hasFreshOB)             score -= 3;
   if(m15.hasFVGClosed   && !m15.hasFVGOpen)           score -= 2;
   if(h1.bullish != m15.bullish)                        score -= 4;

   return MathMax(0, score);
}

//+------------------------------------------------------------------+
//| Advanced Confluence Score — Tertiary M15/M5/M1 (scalp tier)   |
//| Same SMC logic, lowest timeframes, smallest risk               |
//+------------------------------------------------------------------+
int ScoreTertiaryAdvanced(SMCAnalysis &m15, SMCAnalysis &m5, SMCAnalysis &m1) {
   int score = 0;

   // M15 acts as the "HTF anchor" (same role H4 plays in primary)
   if(m15.hasExternalBOS && m15.bullish == m5.bullish)  score += 3;
   if(m15.hasFreshOB)                                    score += 3;
   if((m15.bullish && m15.inDiscount) ||
      (!m15.bullish && m15.inPremium))                   score += 2;
   if(m15.atKeySR)                                       score += 2;
   if(m15.hasMSS)                                        score += 3;

   // M5 — zone confirmation (same role H1 plays in primary)
   if(m5.hasCHoCH && m5.bullish == m15.bullish)          score += 2;
   if(m5.hasFreshOB && m5.hasLiqSweep)                  score += 3;
   if(m5.hasFVGOpen)                                     score += 2;
   if(m5.inOTE)                                          score += 2;
   if(m5.hasDisplacement)                                score += 1;

   // M1 — entry trigger (same role M15 plays in primary)
   if(m1.hasLiqSweep)                                    score += 3;
   if(m1.hasCHoCH || m1.hasMSS)                         score += 3;
   if(m1.hasFVGOpen)                                     score += 2;
   if(m1.hasFreshOB)                                     score += 1;
   if(m1.inSilverBullet)                                 score += 1;

   // ICT Advanced Bonuses — Tertiary (max +18)
   if(m1.inLondonKZ || m1.inNYAmKZ)                score += 3;
   if(m1.inICTMacro)                                score += 3;
   if(m1.po3Distribution)                           score += 3;
   if(m1.atCE)                                      score += 2;
   if(m5.hasBPR)                                    score += 2;
   if(m15.atIPDALevel)                              score += 2;
   if(m1.nearMidnightOpen)                          score += 1;
   if(m5.hasNDOG)                                   score += 1;
   if(m1.hasWeakLow  &&  m15.bullish)              score += 1;
   if(m1.hasWeakHigh && !m15.bullish)              score += 1;

   // Penalties
   if(m15.hasMitigatedOB && !m15.hasFreshOB)             score -= 3;
   if(m5.hasFVGClosed    && !m5.hasFVGOpen)              score -= 2;
   if(m15.bullish != m5.bullish)                          score -= 4; // Conflicting bias

   return MathMax(0, score);
}

#endif // SMC_ENGINE_MQH
