//+------------------------------------------------------------------+
//|  XAUUSD Sniper Entry EA                                          |
//|  Multi-Timeframe Confluence Dashboard                            |
//|  Timeframes: H4 > H1 > M15 (Primary) | H1 > M15 > M5 (Fallback)|
//|  Attach to ANY timeframe — dashboard always works                |
//|  Capital Protection: Full suite including daily limits & news    |
//+------------------------------------------------------------------+
#property copyright   "XAUUSD Sniper Strategy"
#property version     "13.17"
#property description "XAUUSD Sniper EA — Telegram Remote Control v13.17"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- SMC Engine (inlined)
//+------------------------------------------------------------------+
//|  SMC_Engine.mqh                                                  |
//|  Advanced Smart Money Concepts Analysis Engine                   |
//|  Covers: S&R, Internal/External BOS, MSS, Fresh OB,             |
//|  Open FVG, Equal H/L, Breaker, Displacement, OTE, Asian Range   |
//+------------------------------------------------------------------+
#ifndef SMC_ENGINE_MQH
#define SMC_ENGINE_MQH

//+------------------------------------------------------------------+
//| DST-aware session open helpers                                   |
//| Philippines (PHT = UTC+8) never observes DST.                   |
//| London and NY shift ±1h twice a year — computed here in UTC.    |
//+------------------------------------------------------------------+
int SMC_DaysInMonth(int year, int month) {
   if(month == 2) return (year%4==0 && (year%100!=0 || year%400==0)) ? 29 : 28;
   if(month==4 || month==6 || month==9 || month==11) return 30;
   return 31;
}

// Day-of-month for the Nth Sunday in year/month.  nth=1 → first, nth=-1 → last.
int SMC_NthSundayDay(int year, int month, int nth) {
   MqlDateTime d;
   d.year = year; d.mon = month; d.day = 1;
   d.hour = 0;   d.min = 0;    d.sec = 0;
   TimeToStruct(StructToTime(d), d);
   int firstSun = (d.day_of_week == 0) ? 1 : 8 - d.day_of_week;
   if(nth > 0) return firstSun + (nth - 1) * 7;
   int dim = SMC_DaysInMonth(year, month);
   int s   = firstSun;
   while(s + 7 <= dim) s += 7;
   return s;
}

// UK BST: last Sunday March 01:00 UTC  →  last Sunday October 01:00 UTC
bool IsLondonDST(datetime utcTime) {
   MqlDateTime dt; TimeToStruct(utcTime, dt);
   int y = dt.year;
   datetime bstOn  = StringToTime(StringFormat("%04d.03.%02d 01:00", y, SMC_NthSundayDay(y,  3, -1)));
   datetime bstOff = StringToTime(StringFormat("%04d.10.%02d 01:00", y, SMC_NthSundayDay(y, 10, -1)));
   return (utcTime >= bstOn && utcTime < bstOff);
}

// US EDT: 2nd Sunday March 07:00 UTC  →  1st Sunday November 06:00 UTC
bool IsNYDST(datetime utcTime) {
   MqlDateTime dt; TimeToStruct(utcTime, dt);
   int y = dt.year;
   datetime edtOn  = StringToTime(StringFormat("%04d.03.%02d 07:00", y, SMC_NthSundayDay(y,  3, 2)));
   datetime edtOff = StringToTime(StringFormat("%04d.11.%02d 06:00", y, SMC_NthSundayDay(y, 11, 1)));
   return (utcTime >= edtOn && utcTime < edtOff);
}

// London open in UTC: 07:00 when BST active, 08:00 when GMT (winter)
int GetLondonOpenUTC(datetime utcTime = 0) {
   if(utcTime == 0) utcTime = TimeGMT();
   return IsLondonDST(utcTime) ? 7 : 8;
}

// NY open in UTC: 12:00 when EDT active, 13:00 when EST (winter)
int GetNYOpenUTC(datetime utcTime = 0) {
   if(utcTime == 0) utcTime = TimeGMT();
   return IsNYDST(utcTime) ? 12 : 13;
}

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
   bool     isJudasSwing;       // False move at session open (sweep + CHoCH)
   bool     judasSwingBull;     // Swept ABOVE Asian high → SELL reversal setup
   bool     judasSwingBear;     // Swept BELOW Asian low  → BUY  reversal setup
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

   //--- PDH / PDL / PWH / PWL — Previous Day & Week High/Low
   // These are the #1 institutional liquidity targets every day.
   // Price sweeps them to grab stop orders, then reverses hard.
   bool     atPDH;           // Price at Previous Day High (±20 pips)
   bool     atPDL;           // Price at Previous Day Low  (±20 pips)
   bool     atPWH;           // Price at Previous Week High (±30 pips)
   bool     atPWL;           // Price at Previous Week Low  (±30 pips)
   bool     sweepPDH;        // PDH swept: wick above PDH then close below = SELL setup
   bool     sweepPDL;        // PDL swept: wick below PDL then close above = BUY setup
   bool     sweepPWH;        // PWH swept = major SELL reversal signal
   bool     sweepPWL;        // PWL swept = major BUY reversal signal
   bool     runningToPDH;    // Bullish move approaching PDH — block further BUY entries
   bool     runningToPDL;    // Bearish move approaching PDL — block further SELL entries
   double   prevWeekHigh;    // Previous week's high (= weeklyHigh, aliased for clarity)
   double   prevWeekLow;     // Previous week's low  (= weeklyLow,  aliased for clarity)

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

   // Alias weekly high/low as prev week for code clarity
   a.prevWeekHigh = a.weeklyHigh;
   a.prevWeekLow  = a.weeklyLow;

   //================================================================
   // PDH / PDL / PWH / PWL — Proximity, Sweep & Approach Detection
   // These are the primary daily and weekly liquidity targets ICT uses.
   //================================================================
   double pdProx = pip * 20;   // Within 20 pips = AT the daily level
   double pwProx = pip * 30;   // Within 30 pips = AT the weekly level

   // Proximity flags — is price at the level right now?
   a.atPDH = (a.prevDayHigh > 0 && MathAbs(price - a.prevDayHigh) < pdProx);
   a.atPDL = (a.prevDayLow  > 0 && MathAbs(price - a.prevDayLow)  < pdProx);
   a.atPWH = (a.prevWeekHigh > 0 && MathAbs(price - a.prevWeekHigh) < pwProx);
   a.atPWL = (a.prevWeekLow  > 0 && MathAbs(price - a.prevWeekLow)  < pwProx);

   // Sweep flags — wick pierced the level but candle closed back the other side
   // Check last 5 bars (sweep may have happened a few bars ago)
   a.sweepPDH = false; a.sweepPDL = false;
   a.sweepPWH = false; a.sweepPWL = false;
   int swLB = MathMin(6, lookback);
   for(int sw = 1; sw < swLB; sw++) {
      if(!a.sweepPDH && a.prevDayHigh > 0 && high[sw] > a.prevDayHigh && close[sw] < a.prevDayHigh)
         a.sweepPDH = true;
      if(!a.sweepPDL && a.prevDayLow  > 0 && low[sw]  < a.prevDayLow  && close[sw] > a.prevDayLow)
         a.sweepPDL = true;
      if(!a.sweepPWH && a.prevWeekHigh > 0 && high[sw] > a.prevWeekHigh && close[sw] < a.prevWeekHigh)
         a.sweepPWH = true;
      if(!a.sweepPWL && a.prevWeekLow  > 0 && low[sw]  < a.prevWeekLow  && close[sw] > a.prevWeekLow)
         a.sweepPWL = true;
   }

   // Approach flags — price is heading TOWARD a level from the near side (within 50 pips)
   // Buying into PDH overhead = bad entry (resistance above). Selling into PDL below = bad.
   a.runningToPDH = (a.bullish && a.prevDayHigh > 0 && price < a.prevDayHigh &&
                     (a.prevDayHigh - price) < pip * 50);
   a.runningToPDL = (!a.bullish && a.prevDayLow > 0 && price > a.prevDayLow &&
                     (price - a.prevDayLow) < pip * 50);

   // Nearest key S/R to current price — include PDH/PDL/PWH/PWL
   double srLevels[8];
   srLevels[0] = a.prevWeekHigh; srLevels[1] = a.prevWeekLow;
   srLevels[2] = a.prevDayHigh;  srLevels[3] = a.prevDayLow;
   srLevels[4] = a.dailyHigh;    srLevels[5] = a.dailyLow;
   srLevels[6] = a.asianHigh;    srLevels[7] = a.asianLow;

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
   // ICT: London sweeps Asian high or low, then reverses hard.
   // judasSwingBull = sweep above Asian high + CHoCH down → SELL setup (reverse of sweep)
   // judasSwingBear = sweep below Asian low  + CHoCH up   → BUY  setup (reverse of sweep)
   //================================================================
   //================================================================
   // DST-AWARE SESSION OPENS — computed first; used by all below
   //================================================================
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   datetime nowUTC   = TimeGMT();
   int londonOpenUTC = GetLondonOpenUTC(nowUTC);  // 7 (summer) or 8 (winter)
   int nyOpenUTC     = GetNYOpenUTC(nowUTC);       // 12 (summer) or 13 (winter)
   int londonOpenPHT = (londonOpenUTC + 8) % 24;  // 15 or 16
   int nyOpenPHT     = (nyOpenUTC     + 8) % 24;  // 20 or 21
   int utcH          = dt.hour;
   int utcM          = dt.min;
   int utcMins       = utcH * 60 + utcM;
   int phtHour       = (utcH + 8) % 24;

   //================================================================
   // JUDAS SWING — false move at London/NY open then reversal
   // Includes pre-session spike windows (price sweeps BEFORE session opens).
   // judasSwingBull = sweep above Asian high + CHoCH down → SELL setup
   // judasSwingBear = sweep below Asian low  + CHoCH up   → BUY  setup
   // atSessionOpen window is DST-aware: covers pre-session + open windows
   //================================================================
   a.isJudasSwing     = false;
   a.judasSwingBull   = false;
   a.judasSwingBear   = false;
   {
      // Window: 90 min before London open through end of London open (+2h)
      // Window: 30 min before NY open through end of NY AM session (+3h)
      // All expressed in UTC for DST correctness
      int loUtcMins = londonOpenUTC * 60;
      int nyUtcMins = nyOpenUTC     * 60;
      bool atLondonWindow = (utcMins >= loUtcMins - 90 && utcMins < (loUtcMins + 120));
      bool atNYWindow     = (utcMins >= nyUtcMins - 30 && utcMins < (nyUtcMins + 180));
      bool atSessionOpen  = atLondonWindow || atNYWindow;
      if(atSessionOpen && a.hasLiqSweep && a.hasCHoCH) {
         a.isJudasSwing   = true;
         a.judasSwingBull = a.aboveAsianHigh && !a.bullish; // Swept up, now bearish
         a.judasSwingBear = a.belowAsianLow  && a.bullish;  // Swept down, now bullish
      }
   }

   //================================================================
   // SILVER BULLET: 10:00-11:00 AM NY time = nyOpenUTC + 2h
   //   Summer: 14:00-15:00 UTC = 22:00-23:00 PHT (10PM-11PM)
   //   Winter: 15:00-16:00 UTC = 23:00-00:00 PHT (11PM-midnight)
   //================================================================
   a.inSilverBullet = (utcH == nyOpenUTC + 2); // always NY+2h, DST-correct

   //================================================================
   // REJECTION BLOCK / PROPULSION BLOCK
   //================================================================
   a.hasPropulsionOB = DetectPropulsionBlock(high, low, close, open,
                                              a.bullish, lookback);

   //================================================================
   // ICT KILLZONES — DST-aware UTC anchoring
   //================================================================
   // For legacy HHMM comparisons still used below
   int utcT = utcH * 100 + utcM;
   a.inAsianKZ  = (utcT >= 2100 && utcT < 2300);   // always 21-23 UTC (5-7AM PHT)
   a.inLondonKZ = (utcH >= londonOpenUTC && utcH < londonOpenUTC + 2);
   a.inNYAmKZ   = (utcH >= nyOpenUTC     && utcH < nyOpenUTC + 3);
   a.inNYPMKZ   = (utcH >= nyOpenUTC + 3 && utcH < nyOpenUTC + 5);
   a.killzoneName = a.inLondonKZ ? StringFormat("London KZ (%dPM-%dPM PHT)", londonOpenPHT, londonOpenPHT+2) :
                    a.inNYAmKZ   ? StringFormat("NY AM KZ (%dPM-%dPM PHT)",   nyOpenPHT,     nyOpenPHT+3)    :
                    a.inNYPMKZ   ? StringFormat("NY PM KZ (%dPM-%dAM PHT)",   nyOpenPHT+3,  (nyOpenPHT+5)%24) :
                    a.inAsianKZ  ? "Asian KZ (5AM-7AM PHT)" : "No Active KZ";

   //================================================================
   // ICT MACROS — offsets in minutes from London/NY open (DST-safe)
   // London Open Macro: L+0:33 – L+1:00
   // London AM Macro:   L+2:03 – L+2:30
   // NY Lunch Macro:    NY+1:50 – NY+2:10
   // NY AM Macro:       NY+3:10 – NY+3:40
   // NY PM Macro:       NY+4:50 – NY+5:10
   //================================================================
   int londonOpenMin = londonOpenUTC * 60;
   int nyOpenMin     = nyOpenUTC * 60;
   int macroStartMin[5] = { londonOpenMin + 33,  londonOpenMin + 123,
                             nyOpenMin    + 110,  nyOpenMin    + 190,  nyOpenMin + 290 };
   int macroEndMin[5]   = { londonOpenMin + 60,  londonOpenMin + 150,
                             nyOpenMin    + 130,  nyOpenMin    + 220,  nyOpenMin + 310 };
   string macroLabels[5] = {
      StringFormat("London Open Macro (%d:33-%d:00 PHT)", londonOpenPHT, londonOpenPHT+1),
      StringFormat("London AM Macro (%d:03-%d:30 PHT)",   londonOpenPHT+2, londonOpenPHT+2),
      StringFormat("NY Lunch Macro (%d:50-%d:10 PHT)",    nyOpenPHT+1, nyOpenPHT+2),
      StringFormat("NY AM Macro (%d:10-%d:40 PHT)",       nyOpenPHT+3, nyOpenPHT+3),
      StringFormat("NY PM Macro (%d:50-%d:10 PHT)",       nyOpenPHT+4, nyOpenPHT+5)
   };
   a.inICTMacro = false;
   a.macroName  = "";
   for(int mi = 0; mi < 5; mi++) {
      if(utcMins >= macroStartMin[mi] && utcMins < macroEndMin[mi]) {
         a.inICTMacro = true;
         a.macroName  = macroLabels[mi];
         break;
      }
   }

   //================================================================
   // MIDNIGHT OPEN — NY midnight in UTC: nyOpenUTC - 8h
   //   Summer (EDT, nyOpen=12): midnight = 04:00 UTC
   //   Winter (EST, nyOpen=13): midnight = 05:00 UTC
   //================================================================
   a.midnightOpen    = 0;
   a.nearMidnightOpen = false;
   {
      int midnightHour = nyOpenUTC - 8; // 4 (summer) or 5 (winter)
      datetime midnightUTC = StringToTime(StringFormat("%04d.%02d.%02d %02d:00",
                                                        dt.year, dt.mon, dt.day, midnightHour));
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

   string pdStr = StringFormat("PDH:%.2f%s PDL:%.2f%s | PWH:%.2f%s PWL:%.2f%s",
      a.prevDayHigh,  a.sweepPDH ? "(SWEPT)" : (a.atPDH ? "(AT)" : ""),
      a.prevDayLow,   a.sweepPDL ? "(SWEPT)" : (a.atPDL ? "(AT)" : ""),
      a.prevWeekHigh, a.sweepPWH ? "(SWEPT)" : (a.atPWH ? "(AT)" : ""),
      a.prevWeekLow,  a.sweepPWL ? "(SWEPT)" : (a.atPWL ? "(AT)" : ""));

   a.srNarrative = StringFormat(
      "KZ:%s | %s | MidOpen:%.2f | IPDA20:%.2f-%.2f | %s",
      a.killzoneName,
      a.inICTMacro    ? StringFormat("MACRO:%s", a.macroName) : "No Macro",
      a.midnightOpen,
      a.ipda20Low, a.ipda20High,
      pdStr);

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
   // --- PDH / PDL / PWH / PWL (max +8) ---
   // AT the level with sweep = highest-probability ICT reversal
   if(a.sweepPDH && !a.bullish)           a.score += 4; // PDH swept → SELL reversal
   if(a.sweepPDL &&  a.bullish)           a.score += 4; // PDL swept → BUY  reversal
   if(a.sweepPWH && !a.bullish)           a.score += 5; // PWH swept → major SELL signal
   if(a.sweepPWL &&  a.bullish)           a.score += 5; // PWL swept → major BUY  signal
   // AT the level without confirmed sweep = potential reaction
   if(a.atPDH && !a.bullish && !a.sweepPDH) a.score += 2;
   if(a.atPDL &&  a.bullish && !a.sweepPDL) a.score += 2;
   if(a.atPWH && !a.bullish && !a.sweepPWH) a.score += 3;
   if(a.atPWL &&  a.bullish && !a.sweepPWL) a.score += 3;
   // Penalty: buying toward PDH overhead or selling toward PDL below = fighting levels
   if(a.runningToPDH &&  a.bullish)       a.score -= 2;
   if(a.runningToPDL && !a.bullish)       a.score -= 2;
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

   // PDH / PDL / PWH / PWL — Daily & Weekly liquidity levels (max +8)
   if(h4.sweepPWH && !h4.bullish)                 score += 5; // PWH swept → major SELL
   if(h4.sweepPWL &&  h4.bullish)                 score += 5; // PWL swept → major BUY
   if(h1.sweepPDH && !h4.bullish)                 score += 4; // PDH swept → SELL reversal
   if(h1.sweepPDL &&  h4.bullish)                 score += 4; // PDL swept → BUY  reversal
   if(h1.atPDH    && !h4.bullish && !h1.sweepPDH) score += 2; // At PDH, no sweep yet
   if(h1.atPDL    &&  h4.bullish && !h1.sweepPDL) score += 2; // At PDL, no sweep yet
   if(h4.atPWH    && !h4.bullish && !h4.sweepPWH) score += 3; // At PWH, no sweep yet
   if(h4.atPWL    &&  h4.bullish && !h4.sweepPWL) score += 3; // At PWL, no sweep yet
   if(h1.runningToPDH &&  h4.bullish)             score -= 2; // Buying into PDH overhead
   if(h1.runningToPDL && !h4.bullish)             score -= 2; // Selling into PDL below

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

   // PDH / PDL / PWH / PWL — Fallback tier uses H1 for PDH/PDL, M15 for proximity
   if(h1.sweepPWH && !h1.bullish)                 score += 5;
   if(h1.sweepPWL &&  h1.bullish)                 score += 5;
   if(m15.sweepPDH && !h1.bullish)                score += 4;
   if(m15.sweepPDL &&  h1.bullish)                score += 4;
   if(m15.atPDH    && !h1.bullish)                score += 2;
   if(m15.atPDL    &&  h1.bullish)                score += 2;
   if(h1.atPWH     && !h1.bullish)                score += 3;
   if(h1.atPWL     &&  h1.bullish)                score += 3;
   if(m15.runningToPDH &&  h1.bullish)            score -= 2;
   if(m15.runningToPDL && !h1.bullish)            score -= 2;

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

   // PDH / PDL / PWH / PWL — Tertiary uses M15/M5 for level detection
   if(m15.sweepPWH && !m15.bullish)               score += 5;
   if(m15.sweepPWL &&  m15.bullish)               score += 5;
   if(m5.sweepPDH  && !m15.bullish)               score += 4;
   if(m5.sweepPDL  &&  m15.bullish)               score += 4;
   if(m5.atPDH     && !m15.bullish)               score += 2;
   if(m5.atPDL     &&  m15.bullish)               score += 2;
   if(m15.atPWH    && !m15.bullish)               score += 3;
   if(m15.atPWL    &&  m15.bullish)               score += 3;
   if(m5.runningToPDH &&  m15.bullish)            score -= 2;
   if(m5.runningToPDL && !m15.bullish)            score -= 2;

   // Penalties
   if(m15.hasMitigatedOB && !m15.hasFreshOB)             score -= 3;
   if(m5.hasFVGClosed    && !m5.hasFVGOpen)              score -= 2;
   if(m15.bullish != m5.bullish)                          score -= 4; // Conflicting bias

   return MathMax(0, score);
}

#endif // SMC_ENGINE_MQH


CTrade         Trade;
CPositionInfo  PositionInfo;

//--- Inputs
input group            "=== STRATEGY SETTINGS ==="
input int              BOS_Lookback      = 50;     // BOS lookback bars
input int              OB_Lookback       = 10;     // Order Block lookback bars
input int              FVG_Lookback      = 5;      // FVG lookback bars
input int              Sweep_Lookback    = 5;      // Liquidity Sweep lookback bars
input int              MinPrimaryScore   = 7;      // Min score for primary trade (H4→H1→M15)
input int              MinFallbackScore  = 9;      // Min score for fallback trade (H1→M15→M5)
input int              MinTertiaryScore  = 11;     // Min score for tertiary scalp (M15→M5→M1)

input group            "=== RISK PER TRADE ==="
input double           PrimaryRisk       = 2.0;    // Primary risk % (H4→H1→M15)
input double           FallbackRisk      = 1.0;    // Fallback risk % (H1→M15→M5)
input double           TertiaryRisk      = 0.5;    // Tertiary risk % (M15→M5→M1 scalp)
input double           MinRR             = 2.0;    // Minimum Risk:Reward

input group            "=== DAILY PROFIT & LOSS LIMITS ==="
input double           DailyProfitTarget = 5.0;    // Daily profit target % (e.g. 5 = stop at +5%)
input double           DailyLossLimit    = 2.0;    // Daily max loss % (e.g. 2 = stop at -2%)
input int              MaxDailyTrades    = 3;       // Max total trades per day
input int              MaxConsecLosses   = 2;       // Max consecutive losses before stopping

input group            "=== TRADE PROTECTION ==="
input bool             UseBreakeven      = true;   // Move SL to entry when profitable
input double           BreakevenTrigger  = 1.0;    // Profit (x SL distance) to activate BE
input double           BreakevenBuffer   = 2.0;    // Extra pips above entry for BE
input bool             UseTrailingStop   = true;   // Trail SL as price moves in favor
input double           TrailStart        = 1.5;    // Profit (x SL distance) to start trailing
input double           TrailStep         = 5.0;    // Trail step in pips
input double           TrailDistance     = 15.0;   // Trail distance behind price in pips
input bool             UsePartialTP      = true;   // Close partial position at TP1
input double           PartialTPPercent  = 50.0;   // % of position to close at TP1
input double           TP1_RR            = 1.0;    // TP1 Risk:Reward ratio (1:1)
input double           TP2_RR            = 3.0;    // TP2 Risk:Reward ratio (1:3)

input group            "=== DXY CORRELATION FILTER ==="
input bool             UseDXYFilter      = true;   // Block trades conflicting with DXY direction
input string           DXY_Symbol        = "USDX"; // DXY symbol on your broker (try USDX, DXY, DX)
input int              DXY_Lookback      = 20;     // Bars to determine DXY trend
input double           DXY_MinMove       = 0.10;   // Min DXY move (price units) to confirm trend

input group            "=== CANDLE CONFIRMATION FILTER ==="
input bool             UseCandleConfirm  = true;   // Require confirmation candle before entry
input double           EngulfMinRatio    = 1.2;    // Engulfing body must be X times previous body
input double           PinBarWickRatio   = 2.0;    // Wick must be X times body for pin bar
input double           MinBodyPips       = 3.0;    // Minimum body size in pips to count as valid

input group            "=== SPREAD & SLIPPAGE FILTER ==="
input double           MaxSpreadPips     = 30.0;   // Max allowed spread in pips
input int              MaxSlippagePips   = 3;       // Max slippage in pips

input group            "=== HIGH IMPACT NEWS FILTER ==="
input bool             UseNewsFilter     = true;   // Block trades near high impact news
input bool             BlockHighOnly     = true;   // true=High only | false=High+Medium
input int              NewsMinutesBefore = 30;     // Minutes before news to block entry
input int              NewsMinutesAfter  = 30;     // Minutes after news to resume
input bool             BlockUSD          = true;   // Block on USD high impact news
input bool             BlockXAU          = true;   // Block on Gold-specific news
input bool             BlockEUR          = false;  // Block on EUR news (affects DXY)
input bool             CloseOnHighImpact = false;  // Close open trades before high impact news

input group            "=== ACCOUNT FLOOR ==="
input bool             UseBalanceFloor   = true;   // Stop trading below minimum balance
input double           MinBalanceUSD     = 100.0;  // Minimum account balance in USD

input group            "=== DRAWDOWN PROTECTION ==="
input bool             UseMaxDrawdown    = true;   // Stop trading if drawdown exceeds limit
input double           MaxDrawdownPct    = 10.0;   // Max drawdown % from account peak
input bool             UseWeeklyLimit    = true;   // Enable weekly loss limit
input double           WeeklyLossLimit   = 6.0;    // Max weekly loss % before stopping
input double           WeeklyProfitTarget= 15.0;   // Weekly profit target % — stop and rest
input bool             UseMonthlyLimit   = true;   // Enable monthly loss limit
input double           MonthlyLossLimit  = 15.0;   // Max monthly loss % before stopping
input double           MonthlyProfitTarget=30.0;   // Monthly profit target % — stop and rest

input group            "=== SESSION CLOSE ==="
input bool             CloseAtSessionEnd = true;   // Close all trades at end of NY session
input int              SessionCloseHour  = 22;     // PHT hour to close trades (default 10PM)
input bool             CloseOnFriday     = true;   // Close all trades before weekend
input int              FridayCloseHour   = 21;     // PHT hour on Friday to close (default 9PM)
input bool             TightenSLIdle     = true;   // Tighten SL if trade stalls too long
input int              IdleBarLimit      = 20;     // Bars with no progress before tightening SL
input double           IdleSLTightenPips = 5.0;    // Move SL closer by this many pips when idle

input group            "=== CLAUDE AI BRIDGE ==="
input bool             UseBridge         = false;  // Connect EA to Claude AI for signal validation
input bool             BridgeMustApprove = true;   // true=skip trade if no Claude response in time
input int              BridgeTimeoutSec  = 30;     // Seconds to wait for Claude response
input string           BridgeSignalFile  = "SNP_Signal.txt";   // EA writes signal here
input string           BridgeRespFile    = "SNP_Response.txt"; // Claude writes verdict here
input string           BridgeResultFile  = "SNP_Result.txt";   // EA writes closed trade here

input group            "=== AUTO TRADE ENTRY ==="
input bool             AutoTrade         = false;  // Enable auto trade execution (false = alerts only)
input bool             AlertOnSignal     = true;   // Send alert when signal is ready
input int              MagicNumber       = 202401; // EA magic number
input double           SL_BufferPips     = 5.0;    // Extra pips beyond sweep for SL
input int              CooldownBars      = 3;      // Bars to wait after last trade before new entry
input bool             OneTradeAtATime   = true;   // Allow only 1 open trade at a time (overridden by scaled entries)

input group            "=== SESSION-SPECIFIC SETTINGS ==="
// ── Pre-London Spike Window (1:30PM-3PM PHT) — Asian range sweep, Judas Swing setups ──
input bool             TradePreLondon       = true;   // Trade pre-London spike window (1:30-3PM PHT)
input double           PreLondonRisk        = 1.0;    // Pre-London risk % (reduced — spike volatility)
input int              PreLondonMinScore    = 10;     // Min score (high bar — Judas confirmation required)
input int              PreLondonBlackoutMins = 90;    // Window size in minutes before London open (3PM PHT)
// ── Pre-NY Spike Window (7:30PM-8PM PHT) — London range sweep, Judas Swing setups ──
input bool             TradePreNY           = true;   // Trade pre-NY spike window (7:30-8PM PHT)
input double           PreNYRisk            = 1.0;    // Pre-NY risk % (reduced — spike volatility)
input int              PreNYMinScore        = 10;     // Min score (high bar — Judas + DXY confirmation)
input int              PreNYBlackoutMins    = 30;     // Window size in minutes before NY open (8PM PHT)
// ── DEPRECATED: hard blackout toggle (kept for compatibility — use risk/score controls above) ──
input bool             UsePreSessionBlackout = false; // Hard-block all entries in pre-session windows
// ── London Open (3PM-5PM PHT) — Judas Sweep reversal + trending ──
input double           LondonRisk         = 2.0;    // London Open risk % (full — best trending window)
input int              LondonMinScore     = 7;      // Min score for London Open w/ Judas Swing (no-Judas = +2)
input double           LondonTP2_RR       = 3.0;    // London TP2 RR (wider — trending moves)
// ── London Session (5PM-8PM PHT) — selective, continuation only ──
input double           LondonMidRisk      = 1.5;    // London Mid risk % (reduced — selective trades only)
input int              LondonMidMinScore  = 9;      // Min score for London Mid (higher bar)
input int              LondonMidMaxTrades = 1;      // Max simultaneous trades during London Mid
// ── NY Open (8PM-11PM PHT) — best window, full power ──
input double           NYOpenRisk         = 2.0;    // NY Open risk % (full — highest-probability window)
input int              NYOpenMinScore     = 7;      // Min score for NY Open (Judas Swing = same +2 rule)
input double           NYOpenTP2_RR       = 3.5;    // NY Open TP2 RR (slightly wider — strong momentum)
// ── NY PM / Silver Bullet (11PM-1AM PHT) — wind down, SB only ──
input double           NYPMRisk           = 1.0;    // NY PM risk % (reduced — wind-down, SB setups only)
input int              NYPMMinScore       = 9;      // Min score for NY PM entries
input double           NYPMMaxTrades_New  = 1;      // No new trades if already 1 open during NY PM
input double           NYPMTP2_RR         = 2.0;    // NY PM TP2 RR (tighter — less time left in session)

input group            "=== ASIAN SESSION (5AM-7AM PHT) ==="
input bool             TradePremarket     = true;   // Allow trades during Pre-Market 7AM-3PM PHT (Asian extension rules)
input bool             TradeAsianSession  = true;   // Allow trades during Asian KZ (5AM-7AM PHT)
input double           AsianRisk          = 0.5;    // Risk % during Asian session (smaller — range market)
input int              AsianMinScore      = 9;      // Minimum score to trade Asian session (higher bar)
input double           AsianTP1_RR        = 0.8;    // TP1 RR for Asian (tighter — range fading)
input double           AsianTP2_RR        = 1.5;    // TP2 RR for Asian (target opposite range wall)
input double           AsianMaxSpread     = 20.0;   // Block Asian trade if spread > this (pips)
input bool             AsianRangeOnly     = true;   // Asian: only trade at range extremes (OB + sweep)

input group            "=== FVG PENDING ORDERS ==="
input bool             UsePendingOrders     = true;   // Place BUY/SELL LIMIT at FVG CE instead of market order
input int              PendingExpiryBars    = 8;      // Cancel pending if unfilled after this many M15 bars
input double           PendingFVGBuffer     = 2.0;    // Extra pips inside FVG edge for limit price
input bool             PendingMarketFallback = true;  // Fall back to market order if price already inside FVG

input group            "=== SCALED ENTRIES (SCORE-BASED) ==="
input bool             UseScaledEntries  = true;   // Scale max simultaneous trades by confluence score
input int              ScaledScore1      = 8;      // Score threshold for 1 entry
input int              ScaledScore2      = 9;      // Score threshold for 2 simultaneous entries
input int              ScaledScore3      = 10;     // Score threshold for 3 simultaneous entries

input group            "=== ATR VOLATILITY FILTER ==="
input bool             UseATRFilter       = true;    // Block entries when market is too choppy or spiking
input int              ATR_Period         = 14;       // ATR period (H1 bars)
input double           ATR_ChopThreshold  = 8.0;     // Block if H1 ATR < this many pips (dead chop)
input double           ATR_SpikeThreshold = 60.0;    // Block if H1 ATR > this many pips (news spike)
input bool             UseATRStop         = false;   // Use ATR for SL sizing (overrides sweep SL)
input double           ATR_SLMultiplier   = 1.5;     // SL = ATR * this multiplier (when UseATRStop=true)
input double           ATR_TPMultiplier   = 3.0;     // TP2 = ATR * this multiplier (when UseATRStop=true)

input group            "=== ICT ADVANCED CONCEPTS ==="
input bool             UseKillzones      = true;   // Score bonus for London/NY killzones
input bool             UseICTMacros      = true;   // Score bonus for ICT macro windows
input bool             UsePowerOf3       = true;   // Score bonus for PO3 distribution phase
input bool             UseIPDA           = true;   // Score bonus for IPDA price delivery levels
input bool             UseBPR            = true;   // Score bonus for Balanced Price Range
input bool             UseCE             = true;   // Score bonus for Consequent Encroachment
input bool             UseSMTDivergence  = true;   // Use SMT divergence (Gold vs DXY) as filter
input string           SMT_Symbol        = "USDX"; // DXY symbol for SMT divergence (same as DXY)
input bool             UseMidnightOpen   = true;   // Score bonus for NY midnight open proximity
input bool             UseGapDetection   = true;   // Score bonus for NDOG/NWOG gap detection

input group            "=== CHART VISUALS ==="
input bool             ShowOB            = true;   // Draw Order Block boxes on chart
input bool             ShowFVG           = true;   // Draw FVG zones on chart
input bool             ShowSweep         = true;   // Draw liquidity sweep lines
input bool             ShowBOSArrows     = true;   // Mark BOS with arrows
input bool             ShowCHoCHArrows   = true;   // Mark CHoCH with arrows
input bool             ShowTradeLevels   = true;   // Draw SL/TP1/TP2 lines on chart
input int              VisualMaxBars     = 100;    // How many bars back to draw visuals
input color            ColorOB_Bull      = C'0,80,0';     // Bullish OB box color
input color            ColorOB_Bear      = C'80,0,0';     // Bearish OB box color
input color            ColorFVG_Bull     = C'0,60,60';    // Bullish FVG color
input color            ColorFVG_Bear     = C'60,30,0';    // Bearish FVG color
input color            ColorSweep        = clrMagenta;    // Sweep line color
input color            ColorSL_Line      = clrRed;        // SL line color
input color            ColorTP1_Line     = clrDodgerBlue; // TP1 line color
input color            ColorTP2_Line     = clrLime;       // TP2 line color

input group            "=== TRADE JOURNAL ==="
input bool             UseJournal        = true;   // Save trades to CSV journal
input string           JournalFileName   = "XAUUSD_Sniper_Journal.csv"; // Journal file name

input group            "=== NOTIFICATIONS ==="
input bool             UsePushAlert      = true;   // Send push notification to phone
input bool             UseEmailAlert     = false;  // Send email on signal
input bool             UseSoundAlert     = true;   // Play sound on signal
input string           SoundBuy          = "news.wav";  // Sound for BUY signal
input string           SoundSell         = "news.wav";  // Sound for SELL signal
input string           SoundTP           = "ok.wav";    // Sound for TP hit
input string           SoundSL           = "stops.wav"; // Sound for SL hit

input group            "=== REPORT ==="
input bool             GenerateReport    = true;   // Generate HTML report on backtest end
input string           ReportFileName    = "XAUUSD_Sniper_Report.html"; // Report file name

input group            "=== ADAPTIVE LEARNING ==="
input bool             UseAdaptiveLearning = true;  // EA self-adjusts score thresholds from trade results
input int              LearningBatchSize   = 20;    // Trades per review cycle before adjusting thresholds
input int              MinTradesForAdjust  = 10;    // Minimum trades needed before any adjustment
input double           MinSessionWinRate   = 45.0;  // Suspend a session if win rate falls below this %
input bool             SuspendBadSessions  = true;  // Auto-suspend sessions with poor win rate
input string           LearningFileName    = "XAUUSD_Sniper_Learning.dat"; // Learning data save file

input group            "=== OPTIMIZATION TARGETS ==="
// These are the parameters the Strategy Tester will vary during optimization
// In MT5: right-click each input → check Optimize checkbox
// Recommended ranges shown in comments
input int              OPT_MinPrimary    = 7;      // Optimize: Min primary score (range 5-10)
input int              OPT_MinFallback   = 9;      // Optimize: Min fallback score (range 7-11)
input double           OPT_TP1_RR        = 1.0;    // Optimize: TP1 RR (range 0.5-2.0, step 0.5)
input double           OPT_TP2_RR        = 3.0;    // Optimize: TP2 RR (range 2.0-5.0, step 0.5)
input double           OPT_TrailDist     = 15.0;   // Optimize: Trail distance pips (range 10-30)
input double           OPT_BETrigger     = 1.0;    // Optimize: Breakeven trigger (range 0.5-2.0)
input double           OPT_SLBuffer      = 5.0;    // Optimize: SL buffer pips (range 3-10)

input group            "=== DASHBOARD ==="
input int              Dashboard_X       = 20;     // Dashboard X position
input int              Dashboard_Y       = 30;     // Dashboard Y position
input int              FontSize          = 9;      // Font size
input string           FontName          = "Consolas"; // Font name
input color            ColorBull         = clrLime;
input color            ColorBear         = clrRed;
input color            ColorNeutral      = C'180,180,180';
input color            ColorTitle        = clrGold;
input color            ColorHeader       = C'100,180,255';
input color            ColorBG           = C'15,15,25';
input color            ColorText         = clrWhite;
input color            ColorWarn         = clrOrange;

//--- Constants
#define PREFIX          "SNP_"
#define DASH_WIDTH      420
#define ROW_HEIGHT      16

//--- Timeframe definitions
ENUM_TIMEFRAMES TF_H4   = PERIOD_H4;
ENUM_TIMEFRAMES TF_H1   = PERIOD_H1;
ENUM_TIMEFRAMES TF_M15  = PERIOD_M15;
ENUM_TIMEFRAMES TF_M5   = PERIOD_M5;
ENUM_TIMEFRAMES TF_M1   = PERIOD_M1;

//--- Global state — uses advanced SMC engine (SMCAnalysis from SMC_Engine.mqh)
SMCAnalysis g_H4, g_H1, g_M15, g_M5, g_M1;
int        g_PrimaryScore   = 0;
int        g_FallbackScore  = 0;
int        g_TertiaryScore  = 0;
string     g_Session        = "";
string     g_Recommendation = "";
bool       g_UseFallback    = false;
bool       g_UseTertiary    = false;
datetime   g_LastUpdate     = 0;
bool       g_SMTDivergence  = false;  // SMT divergence detected (Gold vs DXY)
string     g_SMTType        = "";     // "BULL" = Gold weak/DXY strong, "BEAR" = Gold strong/DXY weak
// Daily bias lock — set after London confirms direction, used to filter NY Open trades
bool       g_DailyBiasLocked    = false;
bool       g_DailyBias          = false; // true=bullish, false=bearish
datetime   g_DailyBiasDate      = 0;
// London session range — tracked for NY Judas detection (NY sweeps LONDON range, not Asian)
double     g_LondonSessionHigh  = 0;    // High formed during London Open + Mid session
double     g_LondonSessionLow   = 0;    // Low formed during London Open + Mid session
datetime   g_LondonRangeDate    = 0;    // Date London range was last captured
// Open trade direction tracking — prevent stacking opposite directions across sessions
int        g_OpenBuys        = 0;     // Count of currently open BUY trades
int        g_OpenSells       = 0;     // Count of currently open SELL trades

//--- Capital protection state per ticket
struct TradeState {
   ulong    ticket;
   bool     breakEvenDone;
   bool     partialTPDone;
   double   entryPrice;
   double   initialSL;
   double   tp1Price;
   double   tp2Price;
   double   lotSize;
   bool     isBuy;
};

TradeState g_Trades[];            // Tracks all open positions
string     g_ProtectionStatus  = "No open trades";

//--- Daily tracking (resets each new day)
datetime   g_TradeDay          = 0;      // Current trading day
double     g_DayStartBalance   = 0;      // Balance at start of day
double     g_DailyPnL          = 0;      // Today's P&L in %
int        g_DailyTradeCount   = 0;      // Trades taken today
int        g_ConsecLosses      = 0;      // Consecutive losses
bool       g_DailyProfitHit    = false;  // Daily profit target reached
bool       g_DailyLossHit      = false;  // Daily loss limit hit
bool       g_MaxTradesHit      = false;  // Max daily trades hit
bool       g_ConsecLossHit     = false;  // Max consecutive losses hit

//--- MT5 Calendar — high impact news state
struct NewsEvent {
   string   name;       // Event name
   datetime time;       // Scheduled UTC time
   string   country;    // Country code (US, EU, etc.)
   int      importance; // 3=High, 2=Medium, 1=Low
};

NewsEvent  g_NewsEvents[];          // Upcoming high impact events
datetime   g_NextHighImpactTime = 0;// Next high impact event time
string     g_NextHighImpactName = "";// Next event name
string     g_NextHighImpactCountry="";
int        g_NextNewsMinutesAway = 9999;
bool       g_NewsBlocked        = false;
string     g_NewsStatus         = "Checking...";
datetime   g_LastCalendarUpdate = 0; // Throttle calendar queries

//--- DXY state
bool       g_DXY_Available     = false;  // True if DXY symbol found on broker
bool       g_DXY_Bullish       = false;  // DXY trending up (bad for gold BUY)
double     g_DXY_Price         = 0;      // Latest DXY price
double     g_DXY_Change        = 0;      // DXY change over lookback
string     g_DXY_Status        = "N/A";  // Human-readable DXY status

//--- Candle confirmation state
bool       g_CandleConfirmed   = false;  // Latest candle confirmation result
string     g_CandlePattern     = "None"; // Pattern detected: Engulf / PinBar / None

//+------------------------------------------------------------------+
//| Adaptive Learning — confluence snapshot at trade entry          |
//+------------------------------------------------------------------+
#define CONFLUENCE_COUNT 20
#define SESSION_COUNT     9

string g_ConfluenceNames[CONFLUENCE_COUNT] = {
   "H4 ExtBOS",  "H4 MSS",       "H4 FreshOB",  "H4 AtSR",
   "H4 EqualHL", "H1 CHoCH",     "H1 MSS",      "H1 OB+Sweep",
   "H1 OpenFVG", "H1 OTE",       "H1 Displace",  "M15 Sweep",
   "M15 CHoCH",  "M15 OpenFVG",  "M15 FreshOB", "M15 Judas",
   "SilverBull", "DXY Aligned",  "CandleConf",  "Key Session"
};

// Session index constants — must match g_SessionNames order
#define SESS_ASIAN        0
#define SESS_PREMARKET    1
#define SESS_PRELONDON    2   // Pre-London spike window — Judas Swing setups
#define SESS_LONDON_OPEN  3
#define SESS_LONDON_MID   4
#define SESS_PRENY        5   // Pre-NY spike window — Judas Swing setups
#define SESS_NY_OPEN      6
#define SESS_NY_PM        7
#define SESS_OTHER        8

string g_SessionNames[SESSION_COUNT] = {
   "Asian KZ", "Pre-Market", "Pre-London", "London Open", "London Mid",
   "Pre-NY", "NY Open", "NY PM/SB", "Other"
};

struct ConfluenceStats {
   int presentWins;   // Wins when this confluence WAS present
   int presentTotal;  // Total trades when this confluence WAS present
   int absentWins;    // Wins when this confluence was NOT present
   int absentTotal;   // Total trades when this confluence was NOT present
};

struct SessionStats {
   int  wins;
   int  total;
   bool suspended;    // Auto-suspended due to low win rate
};

struct TradeSnapshot {
   ulong  ticket;
   bool   confluences[CONFLUENCE_COUNT]; // Which confluences were active at entry
   int    sessionIdx;                    // Which session trade was taken in
   string strategy;                      // PRIMARY or FALLBACK
};

//--- Learning state
ConfluenceStats g_ConfStats[CONFLUENCE_COUNT];
SessionStats    g_SessStats[SESSION_COUNT];
TradeSnapshot   g_Snapshots[];           // Parallel array with g_Trades

//--- Dynamic thresholds (start at input values, self-adjust over time)
int    g_DynPrimaryScore   = 0;   // Initialized from MinPrimaryScore in OnInit
int    g_DynFallbackScore  = 0;   // Initialized from MinFallbackScore in OnInit
int    g_DynTertiaryScore  = 0;   // Initialized from MinTertiaryScore in OnInit
int    g_PrimaryWins       = 0;
int    g_FallbackWins      = 0;
int    g_TertiaryWins      = 0;
int    g_BatchTradeCount  = 0;   // Counts toward next adjustment cycle
string g_LearnStatus      = "Learning: accumulating trades...";

//--- Telegram / Remote control state
bool       g_TradingPaused     = false;  // Remote pause via Telegram command
string     g_LastTelegramMsg   = "";     // Last message sent to Telegram
datetime   g_LastStatusWrite   = 0;      // Throttle status file writes
string     g_RemoteChangeLog   = "";     // Log of remote parameter changes

//--- Claude AI Bridge state
enum BridgeState { BRIDGE_IDLE=0, BRIDGE_WAITING=1, BRIDGE_APPROVED=2, BRIDGE_REJECTED=3 };
BridgeState g_BridgeState     = BRIDGE_IDLE;
datetime    g_BridgeWriteTime = 0;       // When signal file was written
string      g_BridgeVerdict   = "";      // TAKE / SKIP / ADJUST_SL
string      g_BridgeReason    = "";      // Claude's reasoning text
string      g_BridgeSLStr     = "";      // Adjusted SL if ADJUST_SL verdict
string      g_BridgeStatus    = "Bridge: Standby";

// Pending trade parameters held while waiting for Claude
bool        g_PendingIsBuy    = false;
double      g_PendingEntry    = 0;
double      g_PendingSL       = 0;
double      g_PendingTP1      = 0;
double      g_PendingTP2      = 0;
double      g_PendingLots     = 0;
double      g_PendingRisk     = 0;
string      g_PendingStrategy = "";
int         g_PendingScore    = 0;

//--- FVG pending order tracking
struct FVGPending {
   ulong    ticket;          // MT5 order ticket
   bool     isBuy;           // Direction of the pending order
   datetime placedBar;       // M15 bar time when placed (for expiry)
   double   fvgHigh;         // FVG zone high (for invalidation check)
   double   fvgLow;          // FVG zone low
   string   strategy;        // Strategy tag for logging
};
FVGPending g_FVGPendings[];  // Active FVG pending orders placed by EA

//--- Lot size calculator state
double     g_LastLotSize       = 0;
string     g_BlockReason       = "";     // Why trading is blocked

//--- Auto entry state
datetime   g_LastEntryBar      = 0;
int        g_LastSignalScore   = 0;
bool       g_LastSignalIsBuy   = false; // Track last alerted direction (re-alert on flip)
double     g_LastTP1RR         = 1.0; // Effective TP1 RR used at entry (may differ in Asian session)
double     g_LastTP2RR         = 3.0; // Effective TP2 RR used at entry
bool       g_AlertSent         = false;
string     g_LastTradeResult   = "";
string     g_EntryLog          = "";

//--- Journal stats (all-time, loaded from file on init)
int        g_TotalTrades       = 0;
int        g_TotalWins         = 0;
int        g_TotalLosses       = 0;
double     g_TotalProfit       = 0;
double     g_TotalLoss         = 0;
string     g_JournalPath       = "";

//--- Extended metrics for Z Report
int        g_ATRBlockCount     = 0;   // Trades blocked by ATR chop/spike filter
int        g_NewsBlockCount    = 0;   // Trades blocked by news filter (incremented in TryAutoEntry)
int        g_SpreadBlockCount  = 0;   // Trades blocked by spread filter

// Per-session extended stats (parallel to g_SessStats[SESSION_COUNT])
double     g_SessProfit[SESSION_COUNT];    // Gross profit per session
double     g_SessLoss[SESSION_COUNT];      // Gross loss per session
double     g_SessPips[SESSION_COUNT];      // Net pips per session

// Monthly performance tracking
struct MonthlyPerf {
   int    year;
   int    month;
   int    wins;
   int    losses;
   double grossProfit;
   double grossLoss;
};
MonthlyPerf g_MonthlyPerf[];   // Dynamically grown as months pass

//--- Visual tracking — avoid redrawing every tick
datetime   g_LastVisualBar     = 0;

//--- Backtest / Tester state
bool       g_IsTesting         = false;  // True when running in Strategy Tester
double     g_MaxEquity         = 0;      // Peak equity during backtest
double     g_MinEquity         = 0;      // Lowest equity during backtest
double     g_StartBalance      = 0;      // Balance at EA start
int        g_WinStreak         = 0;      // Current win streak
int        g_LoseStreak        = 0;      // Current lose streak
int        g_MaxWinStreak      = 0;      // Best win streak
int        g_MaxLoseStreak     = 0;      // Worst lose streak
double     g_BestTrade         = 0;      // Best single trade profit
double     g_WorstTrade        = 0;      // Worst single trade loss
double     g_TotalPips         = 0;      // Total pips won/lost
int        g_PrimaryTrades     = 0;      // Trades taken by primary strategy
int        g_FallbackTrades    = 0;      // Trades taken by fallback strategy
int        g_TertiaryTrades    = 0;      // Trades taken by tertiary scalp strategy
datetime   g_EAStartTime       = 0;      // When EA started

//--- Drawdown tracking
double     g_PeakBalance       = 0;      // Highest balance ever reached
double     g_CurrentDrawdown   = 0;      // Current drawdown % from peak
bool       g_DrawdownHit       = false;  // Max drawdown triggered

//--- Weekly tracking
datetime   g_WeekStart         = 0;
double     g_WeekStartBalance  = 0;
double     g_WeeklyPnL         = 0;
bool       g_WeeklyLossHit     = false;
bool       g_WeeklyProfitHit   = false;

//--- Monthly tracking
datetime   g_MonthStart        = 0;
double     g_MonthStartBalance = 0;
double     g_MonthlyPnL        = 0;
bool       g_MonthlyLossHit    = false;
bool       g_MonthlyProfitHit  = false;

//--- Session close tracking
bool       g_SessionCloseDone  = false;  // Tracks if session close already fired today
bool       g_FridayCloseDone   = false;  // Tracks if Friday close already fired

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   g_IsTesting   = MQLInfoInteger(MQL_TESTER);
   g_EAStartTime = TimeCurrent();
   g_StartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_MaxEquity    = g_StartBalance;
   g_MinEquity    = g_StartBalance;

   EventSetTimer(g_IsTesting ? 1 : 5);
   Trade.SetDeviationInPoints(MaxSlippagePips * 10);
   Trade.SetExpertMagicNumber(MagicNumber);
   g_PeakBalance = g_StartBalance;

   ResetDailyTracking();
   ResetWeeklyTracking();
   ResetMonthlyTracking();

   // Initialize adaptive learning
   g_DynPrimaryScore   = MinPrimaryScore;
   g_DynFallbackScore  = MinFallbackScore;
   g_DynTertiaryScore  = MinTertiaryScore;
   ArrayResize(g_Snapshots, 0);
   if(!g_IsTesting) LoadLearningData();

   if(!g_IsTesting) InitJournal();

   if(!g_IsTesting) {
      CreateDashboard();
      AnalyzeAllTimeframes();
      DrawChartVisuals();
      UpdateDashboard();
   }
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Strategy Tester — return custom optimization metric             |
//+------------------------------------------------------------------+
double OnTester() {
   // Custom metric: Profit Factor weighted by win rate and low drawdown
   double profitFactor = GetProfitFactor();
   double winRate      = GetWinRate() / 100.0;
   double ddPenalty    = g_CurrentDrawdown > 0 ? 1.0 / (1.0 + g_CurrentDrawdown / 10.0) : 1.0;
   double metric       = profitFactor * winRate * ddPenalty;

   if(GenerateReport) GenerateHTMLReport();
   return metric;
}

//+------------------------------------------------------------------+
//| Tester pass completed (optimization only)                       |
//+------------------------------------------------------------------+
void OnTesterPass() {
   // Called after each optimization pass — nothing extra needed
}

//+------------------------------------------------------------------+
//| Reset daily tracking at start of new day                        |
//+------------------------------------------------------------------+
void ResetDailyTracking() {
   g_DayStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   g_DailyPnL         = 0;
   g_DailyTradeCount  = 0;
   g_ConsecLosses     = 0;
   g_DailyProfitHit   = false;
   g_DailyLossHit     = false;
   g_MaxTradesHit     = false;
   g_ConsecLossHit    = false;
   g_BlockReason      = "";
   // Reset daily bias lock — each new day starts fresh
   g_DailyBiasLocked  = false;
   g_DailyBias        = false;
   g_DailyBiasDate    = 0;
}

//+------------------------------------------------------------------+
//| Check if new trading day started                                |
//+------------------------------------------------------------------+
void CheckNewDay() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00",
                                              dt.year, dt.mon, dt.day));
   if(today != g_TradeDay) {
      g_TradeDay = today;
      ResetDailyTracking();
   }
}

//+------------------------------------------------------------------+
//| Calculate daily P&L as percentage of start balance             |
//+------------------------------------------------------------------+
void UpdateDailyPnL() {
   if(g_DayStartBalance <= 0) return;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_DailyPnL = ((currentEquity - g_DayStartBalance) / g_DayStartBalance) * 100.0;

   // Check profit target hit
   if(g_DailyPnL >= DailyProfitTarget) {
      g_DailyProfitHit = true;
      g_BlockReason    = StringFormat("Daily profit target reached: +%.2f%%", g_DailyPnL);
   }
   // Check loss limit hit
   if(g_DailyPnL <= -DailyLossLimit) {
      g_DailyLossHit = true;
      g_BlockReason  = StringFormat("Daily loss limit hit: %.2f%%", g_DailyPnL);
   }
}

//+------------------------------------------------------------------+
//| Check spread — returns true if spread is acceptable            |
//+------------------------------------------------------------------+
bool IsSpreadOK() {
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) *
                   SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double spreadPips = spread / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
   return spreadPips <= MaxSpreadPips;
}

//+------------------------------------------------------------------+
//| Update high impact news from MT5 built-in economic calendar    |
//| Queries next 24 hours for USD, XAU, EUR high impact events     |
//+------------------------------------------------------------------+
void UpdateNewsCalendar() {
   if(!UseNewsFilter) {
      g_NewsStatus  = "Filter OFF";
      g_NewsBlocked = false;
      return;
   }

   // Throttle — only query calendar every 5 minutes to save CPU
   if(TimeCurrent() - g_LastCalendarUpdate < 300) return;
   g_LastCalendarUpdate = TimeCurrent();

   ArrayResize(g_NewsEvents, 0);

   datetime fromTime = TimeCurrent() - NewsMinutesAfter  * 60;
   datetime toTime   = TimeCurrent() + NewsMinutesBefore * 60 + 86400; // next 24h

   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, fromTime, toTime);
   if(count <= 0) {
      g_NewsStatus = "Calendar: No data (check internet connection)";
      return;
   }

   // Build filtered list of relevant high impact events
   for(int i = 0; i < count; i++) {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;

      // Check importance level
      bool isHigh   = (event.importance == CALENDAR_IMPORTANCE_HIGH);
      bool isMedium = (event.importance == CALENDAR_IMPORTANCE_MODERATE);
      if(BlockHighOnly && !isHigh)            continue;
      if(!BlockHighOnly && !isHigh && !isMedium) continue;

      // Check country filter
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;

      bool isUSD = (country.currency == "USD");
      bool isXAU = (country.currency == "XAU");
      bool isEUR = (country.currency == "EUR");

      if(isUSD && !BlockUSD) continue;
      if(isXAU && !BlockXAU) continue;
      if(isEUR && !BlockEUR) continue;
      if(!isUSD && !isXAU && !isEUR) continue;

      // Add to list
      int idx = ArraySize(g_NewsEvents);
      ArrayResize(g_NewsEvents, idx + 1);
      g_NewsEvents[idx].name       = event.name;
      g_NewsEvents[idx].time       = values[i].time;
      g_NewsEvents[idx].country    = country.currency;
      g_NewsEvents[idx].importance = (int)event.importance;
   }

   // Find soonest upcoming event
   g_NextHighImpactTime    = 0;
   g_NextHighImpactName    = "";
   g_NextHighImpactCountry = "";
   g_NextNewsMinutesAway   = 9999;

   datetime now = TimeCurrent();
   for(int i = 0; i < ArraySize(g_NewsEvents); i++) {
      int minutesAway = (int)((g_NewsEvents[i].time - now) / 60);
      if(minutesAway < g_NextNewsMinutesAway && minutesAway > -NewsMinutesAfter) {
         g_NextNewsMinutesAway   = minutesAway;
         g_NextHighImpactTime    = g_NewsEvents[i].time;
         g_NextHighImpactName    = g_NewsEvents[i].name;
         g_NextHighImpactCountry = g_NewsEvents[i].country;
      }
   }

   // Determine if currently blocked
   g_NewsBlocked = false;
   if(g_NextHighImpactTime > 0) {
      int minsAway = g_NextNewsMinutesAway;
      if(minsAway <= NewsMinutesBefore && minsAway >= -NewsMinutesAfter) {
         g_NewsBlocked = true;
      }
   }

   // Build status string
   if(ArraySize(g_NewsEvents) == 0) {
      g_NewsStatus = "No high impact news in next 24h — Clear to trade";
   } else if(g_NewsBlocked) {
      string when = g_NextNewsMinutesAway >= 0 ?
                    StringFormat("in %d min", g_NextNewsMinutesAway) : "NOW — just released";
      g_NewsStatus = StringFormat("BLOCKED: %s (%s) %s",
                                  g_NextHighImpactName,
                                  g_NextHighImpactCountry, when);
   } else {
      // Convert event time to PHT for display
      MqlDateTime evtDt;
      TimeToStruct(g_NextHighImpactTime, evtDt);
      int phtH = (evtDt.hour + 8) % 24;
      g_NewsStatus = StringFormat("Next: %s (%s) at %02d:%02d PHT — %d min away",
                                  g_NextHighImpactName,
                                  g_NextHighImpactCountry,
                                  phtH, evtDt.min,
                                  g_NextNewsMinutesAway);
   }

   // Close open trades if configured and news is imminent
   if(CloseOnHighImpact && g_NewsBlocked && g_NextNewsMinutesAway >= 0 &&
      g_NextNewsMinutesAway <= 5)
      CloseAllTrades("High impact news in " +
                     IntegerToString(g_NextNewsMinutesAway) + " min");
}

//+------------------------------------------------------------------+
//| Check if near a high impact news event — uses calendar data     |
//+------------------------------------------------------------------+
bool IsNearNews() {
   if(!UseNewsFilter) return false;
   return g_NewsBlocked;
}

//+------------------------------------------------------------------+
//| DXY Correlation — reads DXY trend from broker                  |
//| Gold is inversely correlated: DXY up = gold down               |
//+------------------------------------------------------------------+
void UpdateDXY() {
   g_DXY_Available = false;
   g_DXY_Status    = "N/A";

   // Check if DXY symbol exists on this broker
   if(!SymbolSelect(DXY_Symbol, true)) {
      g_DXY_Status = "Symbol not found: " + DXY_Symbol;
      return;
   }

   double dxyClose[];
   ArraySetAsSeries(dxyClose, true);
   int copied = CopyClose(DXY_Symbol, PERIOD_H4, 0, DXY_Lookback + 1, dxyClose);
   if(copied < DXY_Lookback + 1) {
      g_DXY_Status = "Loading DXY data...";
      return;
   }

   g_DXY_Available = true;
   g_DXY_Price     = dxyClose[0];
   g_DXY_Change    = dxyClose[0] - dxyClose[DXY_Lookback];

   // DXY bullish = USD strengthening = headwind for gold BUY
   if(g_DXY_Change >= DXY_MinMove) {
      g_DXY_Bullish = true;
      g_DXY_Status  = StringFormat("BULLISH +%.3f | Gold headwind — avoid BUY", g_DXY_Change);
   } else if(g_DXY_Change <= -DXY_MinMove) {
      g_DXY_Bullish = false;
      g_DXY_Status  = StringFormat("BEARISH %.3f | Gold tailwind — favor BUY", g_DXY_Change);
   } else {
      // Ranging DXY — no strong signal, allow both directions
      g_DXY_Bullish = false;
      g_DXY_Status  = StringFormat("RANGING %.3f | Neutral for gold", g_DXY_Change);
   }
}

//+------------------------------------------------------------------+
//| SMT Divergence — Gold vs DXY on H1 (last 3 swings)            |
//| Divergence = Gold makes new high BUT DXY also makes new high   |
//|   → expect Gold reversal down (bearish SMT)                    |
//| Divergence = Gold makes new low BUT DXY also makes new low     |
//|   → expect Gold reversal up (bullish SMT)                      |
//+------------------------------------------------------------------+
void CheckSMTDivergence() {
   g_SMTDivergence = false;
   g_SMTType       = "";

   string dxySym = (StringLen(SMT_Symbol) > 0) ? SMT_Symbol : DXY_Symbol;
   if(!SymbolSelect(dxySym, true)) return;

   int lookback = 10;
   double xauH[], xauL[], dxyH[], dxyL[];
   ArraySetAsSeries(xauH, true); ArraySetAsSeries(xauL, true);
   ArraySetAsSeries(dxyH, true); ArraySetAsSeries(dxyL, true);

   if(CopyHigh(_Symbol, PERIOD_H1, 0, lookback, xauH) < lookback) return;
   if(CopyLow (_Symbol, PERIOD_H1, 0, lookback, xauL) < lookback) return;
   if(CopyHigh(dxySym,  PERIOD_H1, 0, lookback, dxyH) < lookback) return;
   if(CopyLow (dxySym,  PERIOD_H1, 0, lookback, dxyL) < lookback) return;

   // Compare recent 3-bar high vs prior 3-bar high
   double xauRecHigh = MathMax(xauH[0], MathMax(xauH[1], xauH[2]));
   double xauPriorHigh = MathMax(xauH[4], MathMax(xauH[5], xauH[6]));
   double dxyRecHigh = MathMax(dxyH[0], MathMax(dxyH[1], dxyH[2]));
   double dxyPriorHigh = MathMax(dxyH[4], MathMax(dxyH[5], dxyH[6]));

   double xauRecLow = MathMin(xauL[0], MathMin(xauL[1], xauL[2]));
   double xauPriorLow = MathMin(xauL[4], MathMin(xauL[5], xauL[6]));
   double dxyRecLow = MathMin(dxyL[0], MathMin(dxyL[1], dxyL[2]));
   double dxyPriorLow = MathMin(dxyL[4], MathMin(dxyL[5], dxyL[6]));

   // Bearish SMT: Gold higher high + DXY higher high → Gold is overextended, reversal down
   if(xauRecHigh > xauPriorHigh && dxyRecHigh > dxyPriorHigh) {
      g_SMTDivergence = true;
      g_SMTType = "BEAR"; // Both making higher highs — unusual, watch for Gold reversal
   }
   // Bullish SMT: Gold lower low + DXY lower low → watch for Gold reversal up
   else if(xauRecLow < xauPriorLow && dxyRecLow < dxyPriorLow) {
      g_SMTDivergence = true;
      g_SMTType = "BULL";
   }
   // Classic bearish divergence: Gold higher high + DXY lower high (DXY weakening)
   // → Gold well-supported — actually confirms BUY, not divergence in harmful sense
   // Classic bearish divergence: Gold lower low + DXY higher low → SELL confirmation
   else if(xauRecLow < xauPriorLow && dxyRecLow > dxyPriorLow) {
      g_SMTDivergence = true;
      g_SMTType = "BEAR_CONFIRM"; // DXY strengthening while gold falling = bearish
   }
   else if(xauRecHigh > xauPriorHigh && dxyRecHigh < dxyPriorHigh) {
      g_SMTDivergence = true;
      g_SMTType = "BULL_CONFIRM"; // DXY weakening while gold rising = bullish
   }
}

//+------------------------------------------------------------------+
//| DXY filter check — returns true if trade direction is OK        |
//+------------------------------------------------------------------+
bool IsDXYAligned(bool isBuyTrade) {
   if(!UseDXYFilter)      return true;
   if(!g_DXY_Available)   return true; // If DXY not available, don't block

   // DXY ranging = both directions allowed
   if(MathAbs(g_DXY_Change) < DXY_MinMove) return true;

   // BUY gold requires DXY bearish (USD weakening)
   if(isBuyTrade  &&  g_DXY_Bullish) return false;
   // SELL gold requires DXY bullish (USD strengthening)
   if(!isBuyTrade && !g_DXY_Bullish) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Candle Confirmation — checks for engulfing or pin bar           |
//| at the entry timeframe before allowing auto entry               |
//+------------------------------------------------------------------+
bool CheckCandleConfirmation(bool isBuy, ENUM_TIMEFRAMES tf) {
   if(!UseCandleConfirm) { g_CandlePattern = "Filter OFF"; return true; }

   double open[], high[], low[], close[];
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   if(CopyOpen (_Symbol, tf, 0, 3, open)  < 3 ||
      CopyHigh (_Symbol, tf, 0, 3, high)  < 3 ||
      CopyLow  (_Symbol, tf, 0, 3, low)   < 3 ||
      CopyClose(_Symbol, tf, 0, 3, close) < 3) {
      g_CandlePattern = "No data";
      return false;
   }

   double pip      = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   double minBody  = MinBodyPips * pip;

   // Current completed candle = index 1 (index 0 = still forming)
   double body1    = MathAbs(close[1] - open[1]);
   double body2    = MathAbs(close[2] - open[2]);
   double range1   = high[1] - low[1];
   bool   bull1    = close[1] > open[1];

   // ── BULLISH ENGULFING — for BUY confirmation ──
   if(isBuy && bull1 && body1 >= minBody) {
      // Body engulfs previous candle body
      bool engulfs = (open[1] <= close[2] && close[1] >= open[2]);
      // Body is larger than previous
      bool bigger  = (body2 > 0 && body1 >= body2 * EngulfMinRatio);
      if(engulfs || bigger) {
         g_CandlePattern = "Bullish Engulf";
         g_CandleConfirmed = true;
         return true;
      }
   }

   // ── BEARISH ENGULFING — for SELL confirmation ──
   if(!isBuy && !bull1 && body1 >= minBody) {
      bool engulfs = (open[1] >= close[2] && close[1] <= open[2]);
      bool bigger  = (body2 > 0 && body1 >= body2 * EngulfMinRatio);
      if(engulfs || bigger) {
         g_CandlePattern = "Bearish Engulf";
         g_CandleConfirmed = true;
         return true;
      }
   }

   // ── BULLISH PIN BAR — hammer, for BUY confirmation ──
   if(isBuy && range1 > 0 && body1 >= minBody) {
      double lowerWick = MathMin(open[1], close[1]) - low[1];
      double upperWick = high[1] - MathMax(open[1], close[1]);
      // Lower wick much longer than body, small upper wick
      bool isPinBar = (lowerWick >= body1 * PinBarWickRatio &&
                       upperWick <= body1 * 0.5);
      if(isPinBar) {
         g_CandlePattern = "Bullish Pin Bar";
         g_CandleConfirmed = true;
         return true;
      }
   }

   // ── BEARISH PIN BAR — shooting star, for SELL confirmation ──
   if(!isBuy && range1 > 0 && body1 >= minBody) {
      double upperWick = high[1] - MathMax(open[1], close[1]);
      double lowerWick = MathMin(open[1], close[1]) - low[1];
      bool isPinBar = (upperWick >= body1 * PinBarWickRatio &&
                       lowerWick <= body1 * 0.5);
      if(isPinBar) {
         g_CandlePattern = "Bearish Pin Bar";
         g_CandleConfirmed = true;
         return true;
      }
   }

   // ── STRONG MOMENTUM CANDLE — body > 70% of range ──
   if(body1 >= minBody && range1 > 0 && body1 / range1 >= 0.70) {
      bool dirMatch = isBuy ? bull1 : !bull1;
      if(dirMatch) {
         g_CandlePattern = "Strong Momentum";
         g_CandleConfirmed = true;
         return true;
      }
   }

   g_CandlePattern   = "No confirmation";
   g_CandleConfirmed = false;
   return false;
}

//+------------------------------------------------------------------+
//| Check account balance floor                                     |
//+------------------------------------------------------------------+
bool IsBalanceOK() {
   if(!UseBalanceFloor) return true;
   return AccountInfoDouble(ACCOUNT_BALANCE) >= MinBalanceUSD;
}

//+------------------------------------------------------------------+
//| Auto-calculate lot size based on risk % and SL distance        |
//+------------------------------------------------------------------+
double CalcLotSize(double riskPercent, double slPips) {
   if(slPips <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * riskPercent / 100.0;
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip        = point * 10;

   if(tickValue <= 0 || tickSize <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double pipValue   = (pip / tickSize) * tickValue;
   double lots       = riskAmount / (slPips * pipValue);

   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Master gate — is trading allowed right now?                    |
//+------------------------------------------------------------------+
bool IsTradingAllowed() {
   // Remote pause via Telegram
   if(g_TradingPaused) {
      g_BlockReason = "PAUSED remotely via Telegram — send /resume to restart";
      return false;
   }
   // Drawdown
   if(g_DrawdownHit) {
      g_BlockReason = StringFormat("Max drawdown hit: %.2f%% — Account protection active", g_CurrentDrawdown);
      return false;
   }
   // Monthly limits
   if(g_MonthlyLossHit) {
      g_BlockReason = StringFormat("Monthly loss limit hit: %.2f%% — Wait next month", g_MonthlyPnL);
      return false;
   }
   if(g_MonthlyProfitHit) {
      g_BlockReason = StringFormat("Monthly profit target hit: +%.2f%% — Enjoy your profits!", g_MonthlyPnL);
      return false;
   }
   // Weekly limits
   if(g_WeeklyLossHit) {
      g_BlockReason = StringFormat("Weekly loss limit hit: %.2f%% — Wait next week", g_WeeklyPnL);
      return false;
   }
   if(g_WeeklyProfitHit) {
      g_BlockReason = StringFormat("Weekly profit target hit: +%.2f%% — Well done, rest now", g_WeeklyPnL);
      return false;
   }
   // Balance floor
   if(!IsBalanceOK()) {
      g_BlockReason = StringFormat("Balance below floor ($%.2f)", MinBalanceUSD);
      return false;
   }
   // Daily profit target — high score (9 or 10) overrides and continues trading
   if(g_DailyProfitHit) {
      int curScore = g_UseFallback ? g_FallbackScore : g_PrimaryScore;
      if(UseScaledEntries && curScore >= ScaledScore2) {
         g_BlockReason = "";  // Score 9+ overrides daily profit cap — keep trading
      } else {
         g_BlockReason = StringFormat("Daily profit target hit: +%.2f%% — Score %d below %d, no new trades",
                                      g_DailyPnL, curScore, ScaledScore2);
         return false;
      }
   }
   if(g_DailyLossHit) {
      g_BlockReason = StringFormat("Daily loss limit hit: -%.2f%%  — Come back tomorrow", DailyLossLimit);
      return false;
   }
   if(g_MaxTradesHit) {
      g_BlockReason = StringFormat("Max daily trades reached (%d)", MaxDailyTrades);
      return false;
   }
   if(g_ConsecLossHit) {
      g_BlockReason = StringFormat("Max consecutive losses (%d) — Stop for today", MaxConsecLosses);
      return false;
   }
   // Friday / session close
   if(g_FridayCloseDone) {
      g_BlockReason = "Friday — market closing for weekend, no new trades";
      return false;
   }
   if(g_SessionCloseDone) {
      g_BlockReason = "Session ended — waiting for next trading window";
      return false;
   }
   // Spread and news
   if(!IsSpreadOK()) {
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) *
                      SymbolInfoDouble(_Symbol, SYMBOL_POINT) /
                      (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
      g_BlockReason = StringFormat("Spread too wide: %.1f pips (max %.0f)", spread, MaxSpreadPips);
      return false;
   }
   if(IsNearNews()) {
      g_BlockReason = "Near scheduled news event — waiting";
      return false;
   }
   g_BlockReason = "";
   return true;
}

//+------------------------------------------------------------------+
//| Call after each closed trade to update counters                |
//+------------------------------------------------------------------+
void OnTradeClose(bool wasWin) {
   g_DailyTradeCount++;
   if(g_DailyTradeCount >= MaxDailyTrades)
      g_MaxTradesHit = true;

   if(wasWin) {
      g_ConsecLosses = 0;
   } else {
      g_ConsecLosses++;
      if(g_ConsecLosses >= MaxConsecLosses)
         g_ConsecLossHit = true;
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   DeleteDashboard();
   ObjectsDeleteAll(0, "VIS_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Remote control — read Telegram commands and setting overrides
   if(!g_IsTesting) {
      ReadCommandFile();
      ReadSettingsOverride();
      WriteStatusFile();
   }

   CheckNewDay();
   CheckNewWeek();
   CheckNewMonth();
   UpdateDailyPnL();
   UpdateWeeklyPnL();
   UpdateMonthlyPnL();
   UpdateDrawdown();
   CheckSessionClose();
   ManageCapitalProtection();
   ManageIdleTrades();
   ManagePendingOrders();
   AnalyzeAllTimeframes();
   TryAutoEntry();

   // Skip heavy UI work in tester — keeps backtest fast
   if(!g_IsTesting) {
      datetime curBar = iTime(_Symbol, TF_M15, 0);
      if(curBar != g_LastVisualBar) {
         DrawChartVisuals();
         g_LastVisualBar = curBar;
      }
      UpdateDashboard();
   }

   // Track equity high/low for report
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_MaxEquity) g_MaxEquity = eq;
   if(eq < g_MinEquity) g_MinEquity = eq;
}

//+------------------------------------------------------------------+
//| Track trade results via transaction events                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   // Only care about deal additions (trade closed)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal_type != DEAL_TYPE_BUY &&
      trans.deal_type != DEAL_TYPE_SELL) return;

   // Find if this is a closing deal (entry = OUT)
   if(HistoryDealSelect(trans.deal)) {
      // Only process deals opened by this EA
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;

      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT) {
         double profit  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         bool   wasWin  = (profit > 0);
         ulong  dealTicket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         OnTradeClose(wasWin);
         g_LastTradeResult = StringFormat("%s  $%.2f  (%s)",
                             TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
                             profit, wasWin ? "WIN" : "LOSS");

         // Find trade state for journal and stats
         int idx = FindTradeState(dealTicket);
         if(idx >= 0) {
            TradeState ts       = g_Trades[idx];
            double exitPrice    = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            // Extract strategy from deal comment (set at entry time) for accuracy
            string dealComment  = HistoryDealGetString(trans.deal, DEAL_COMMENT);
            string strat        = (StringFind(dealComment, "FALLBACK") >= 0) ? "FALLBACK" : "PRIMARY";
            double slPips       = MathAbs(ts.entryPrice - ts.initialSL) /
                                  (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
            double tradePips    = MathAbs(exitPrice - ts.entryPrice) /
                                  (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);

            // Track pips
            g_TotalPips += wasWin ? tradePips : -tradePips;

            // Track best/worst trade
            if(profit > g_BestTrade)  g_BestTrade  = profit;
            if(profit < g_WorstTrade) g_WorstTrade = profit;

            // Track streaks
            if(wasWin) {
               g_WinStreak++;
               g_LoseStreak = 0;
               if(g_WinStreak > g_MaxWinStreak) g_MaxWinStreak = g_WinStreak;
            } else {
               g_LoseStreak++;
               g_WinStreak = 0;
               if(g_LoseStreak > g_MaxLoseStreak) g_MaxLoseStreak = g_LoseStreak;
            }

            // Track per-strategy counts
            if(strat == "PRIMARY")   g_PrimaryTrades++;
            else if(strat == "FALLBACK") g_FallbackTrades++;
            else                     g_TertiaryTrades++;

            // Update adaptive learning stats
            UpdateLearningStats(dealTicket, wasWin, strat);

            // Notify Claude bridge of trade result
            WriteBridgeResult(dealTicket, wasWin, profit, strat, g_LastSignalScore);

            if(!g_IsTesting) {
               JournalWriteTrade(dealTicket, strat, g_LastSignalScore,
                                 ts.entryPrice, ts.initialSL, ts.tp1Price, ts.tp2Price,
                                 ts.lotSize,
                                 strat == "PRIMARY"   ? PrimaryRisk  :
                                 strat == "FALLBACK"  ? FallbackRisk : TertiaryRisk,
                                 slPips, exitPrice, profit, ts.isBuy,
                                 ts.breakEvenDone, ts.partialTPDone, UseTrailingStop);
               SendTradeResultNotification(wasWin, profit, dealTicket, strat);
            }
         }

         // Notify if daily limit was just triggered
         if(g_DailyLossHit || g_DailyProfitHit || g_ConsecLossHit)
            SendDailyLimitNotification(g_BlockReason);

         g_AlertSent = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Score-based entry scaling — returns max open trades allowed     |
//| Score >= ScaledScore3 → 3 trades                                |
//| Score >= ScaledScore2 → 2 trades                                |
//| Score >= ScaledScore1 → 1 trade                                 |
//| Score <  ScaledScore1 → 0 trades (signal too weak)             |
//+------------------------------------------------------------------+
int GetMaxEntriesForScore(int score) {
   if(!UseScaledEntries) return (OneTradeAtATime ? 1 : 99);
   if(score >= ScaledScore3) return 3;
   if(score >= ScaledScore2) return 2;
   if(score >= ScaledScore1) return 1;
   return 0;
}

//+------------------------------------------------------------------+
//| Session index from current session string                       |
//+------------------------------------------------------------------+
int GetSessionIndex() {
   // All session strings now contain dynamic PHT times — use StringFind (partial match)
   if(StringFind(g_Session, "Pre-London Spike")       >= 0) return SESS_PRELONDON;
   if(StringFind(g_Session, "Pre-NY Spike")           >= 0) return SESS_PRENY;
   if(StringFind(g_Session, "Asian KZ")               >= 0) return SESS_ASIAN;
   if(StringFind(g_Session, "Pre-Market")             >= 0) return SESS_PREMARKET;
   if(StringFind(g_Session, "London Open")            >= 0) return SESS_LONDON_OPEN;
   if(StringFind(g_Session, "London Session")         >= 0) return SESS_LONDON_MID;
   if(StringFind(g_Session, "New York Open")          >= 0) return SESS_NY_OPEN;
   if(StringFind(g_Session, "NY PM / Silver Bullet")  >= 0) return SESS_NY_PM;
   if(StringFind(g_Session, "NY Closed")              >= 0) return SESS_OTHER;
   return SESS_OTHER;
}

//+------------------------------------------------------------------+
//| Per-session parameters: risk, min score, max trades, TP2 RR     |
//+------------------------------------------------------------------+
struct SessionParams {
   double risk;
   int    minScore;
   int    maxNewTrades;  // Max NEW trades allowed (0 = session blocked)
   double tp1RR;
   double tp2RR;
   string tag;
};

SessionParams GetSessionParams() {
   SessionParams p;
   int si = GetSessionIndex();

   switch(si) {
      case SESS_ASIAN:
         p.risk         = AsianRisk;
         p.minScore     = AsianMinScore;
         p.maxNewTrades = 1;
         p.tp1RR        = AsianTP1_RR;
         p.tp2RR        = AsianTP2_RR;
         p.tag          = "[ASIAN-RANGE]";
         break;
      case SESS_PREMARKET:
         // Same conservative rules as Asian — range market, low liquidity
         p.risk         = AsianRisk;
         p.minScore     = AsianMinScore;
         p.maxNewTrades = TradePremarket ? 1 : 0;
         p.tp1RR        = AsianTP1_RR;
         p.tp2RR        = AsianTP2_RR;
         p.tag          = "[PRE-MKT]";
         break;
      case SESS_PRELONDON: {
         // Pre-London spike window — Asian range being swept, Judas Swing loading
         // Big spikes happen here. Trade WITH Judas (reversal) at high confluence only.
         // Judas required → tight score bar; without Judas → very high bar (avoid fakes)
         bool hasJudas = g_M15.isJudasSwing || g_M5.isJudasSwing || g_H1.isJudasSwing;
         p.risk         = PreLondonRisk;
         p.minScore     = hasJudas ? PreLondonMinScore : PreLondonMinScore + 3;
         p.maxNewTrades = TradePreLondon ? 1 : 0;
         p.tp1RR        = TP1_RR;
         p.tp2RR        = LondonTP2_RR;   // Same target as London — delivering into London session
         p.tag          = hasJudas ? "[PRE-LDN-JUDAS]" : "[PRE-LDN]";
         break;
      }
      case SESS_PRENY: {
         // Pre-NY spike window — London range sweep, Judas Swing loading
         // Sharp moves before NY open. Trade reversal at very high confluence only.
         bool hasJudas = g_M15.isJudasSwing || g_M5.isJudasSwing || g_H1.isJudasSwing;
         p.risk         = PreNYRisk;
         p.minScore     = hasJudas ? PreNYMinScore : PreNYMinScore + 3;
         p.maxNewTrades = TradePreNY ? 1 : 0;
         p.tp1RR        = TP1_RR;
         p.tp2RR        = NYOpenTP2_RR;   // Same target as NY — delivering into NY open
         p.tag          = hasJudas ? "[PRE-NY-JUDAS]" : "[PRE-NY]";
         break;
      }
      case SESS_LONDON_OPEN: {
         bool hasJudas = g_M15.isJudasSwing || g_M5.isJudasSwing || g_H1.isJudasSwing;
         p.risk         = LondonRisk;
         // Judas Swing detected → low score OK (it's the holy grail setup)
         // No Judas Swing → require higher confluence before trading London trend
         p.minScore     = hasJudas ? LondonMinScore : LondonMinScore + 2;
         p.maxNewTrades = 99;
         p.tp1RR        = TP1_RR;
         p.tp2RR        = LondonTP2_RR;
         p.tag          = hasJudas ? "[LONDON-JUDAS]" : "[LONDON-OPEN]";
         break;
      }
      case SESS_LONDON_MID:
         p.risk         = LondonMidRisk;
         p.minScore     = LondonMidMinScore;
         p.maxNewTrades = LondonMidMaxTrades;
         p.tp1RR        = TP1_RR;
         p.tp2RR        = TP2_RR;
         p.tag          = "[LONDON-MID]";
         break;
      case SESS_NY_OPEN:
         p.risk         = NYOpenRisk;
         p.minScore     = NYOpenMinScore;
         p.maxNewTrades = 99; // scaled entries decide
         p.tp1RR        = TP1_RR;
         p.tp2RR        = NYOpenTP2_RR;
         p.tag          = "[NY-OPEN]";
         break;
      case SESS_NY_PM:
         p.risk         = NYPMRisk;
         p.minScore     = NYPMMinScore;
         p.maxNewTrades = (int)NYPMMaxTrades_New;
         p.tp1RR        = TP1_RR;
         p.tp2RR        = NYPMTP2_RR;
         p.tag          = "[NY-PM/SB]";
         break;
      default: // SESS_OTHER / blocked
         p.risk         = TertiaryRisk;
         p.minScore     = 999; // effectively blocked
         p.maxNewTrades = 0;
         p.tp1RR        = TP1_RR;
         p.tp2RR        = TP2_RR;
         p.tag          = "";
         break;
   }
   return p;
}

//+------------------------------------------------------------------+
//| Auto Entry — fires when confluence score meets threshold         |
//+------------------------------------------------------------------+
void TryAutoEntry() {
   if(!IsTradingAllowed()) return;
   double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0; // declared once for entire function

   // Pre-session blackout — danger zone before London/NY open.
   if(IsInPreSessionBlackout()) {
      g_EntryLog = "Blackout: " + g_Session + " — no new entries, managing existing";
      return;
   }

   // Universal spread check — all sessions (Asian has its own tighter check below)
   {
      double curSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) *
                         SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
      if(curSpread > MaxSpreadPips) {
         g_EntryLog = StringFormat("SPREAD: %.1f pips > max %.1f — waiting for spread to tighten",
                                   curSpread, MaxSpreadPips);
         return;
      }
   }

   // ATR volatility filter — block entries during dead chop and news spike blow-offs
   if(UseATRFilter) {
      int atrHnd  = iATR(_Symbol, TF_H1, ATR_Period);
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(atrHnd != INVALID_HANDLE && CopyBuffer(atrHnd, 0, 1, 1, atrBuf) == 1) {
         double atrPips = atrBuf[0] / pip;
         if(atrPips < ATR_ChopThreshold) {
            g_EntryLog = StringFormat("ATR CHOP FILTER: H1 ATR=%.1f pips < %.1f minimum — market too quiet, skip",
                                      atrPips, ATR_ChopThreshold);
            g_ATRBlockCount++;
            return;
         }
         if(atrPips > ATR_SpikeThreshold) {
            g_EntryLog = StringFormat("ATR SPIKE FILTER: H1 ATR=%.1f pips > %.1f maximum — news spike, skip",
                                      atrPips, ATR_SpikeThreshold);
            g_ATRBlockCount++;
            return;
         }
      }
   }

   // Load per-session parameters
   SessionParams sp = GetSessionParams();
   int curSessIdx   = GetSessionIndex();

   // Block sessions that are not in a trade window
   bool isAsian     = (curSessIdx == SESS_ASIAN);
   bool isPremarket = (curSessIdx == SESS_PREMARKET);
   bool isPreLondon = (curSessIdx == SESS_PRELONDON);
   bool isPreNY     = (curSessIdx == SESS_PRENY);
   bool inSession   = (curSessIdx != SESS_OTHER) &&
                      !(isAsian     && !TradeAsianSession) &&
                      !(isPremarket && !TradePremarket) &&
                      !(isPreLondon && !TradePreLondon) &&
                      !(isPreNY     && !TradePreNY);
   if(!inSession || sp.maxNewTrades == 0) { g_AlertSent = false; return; }

   // NY PM: block new trades if already at limit
   if(curSessIdx == SESS_NY_PM && CountOpenTrades() >= sp.maxNewTrades) {
      g_EntryLog = "NY PM: Max trades open — manage existing position, no new entries";
      return;
   }

   // London Mid: max trades cap
   if(curSessIdx == SESS_LONDON_MID && CountOpenTrades() >= sp.maxNewTrades) {
      g_EntryLog = "London Mid (Selective): Already 1 trade open — waiting for close";
      return;
   }

   // Asian / Pre-market: spread and range-extreme filters
   if(isAsian || isPremarket) {
      double curSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) *
                         SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
      if(curSpread > AsianMaxSpread) {
         g_EntryLog = StringFormat("Asian KZ: Spread %.1f pips > max %.1f — waiting", curSpread, AsianMaxSpread);
         return;
      }
      if(AsianRangeOnly && !(g_M15.hasLiqSweep && g_M15.hasFreshOB)) {
         g_EntryLog = "Asian KZ (Range Mode): Need sweep + fresh OB at range extreme — waiting";
         return;
      }
   }

   // NY PM / Silver Bullet: require Silver Bullet window or high score
   if(curSessIdx == SESS_NY_PM) {
      bool inSB = g_M15.inSilverBullet || g_M5.inSilverBullet || g_M1.inSilverBullet;
      if(!inSB && g_PrimaryScore < sp.minScore + 2) {
         g_EntryLog = "NY PM: Outside Silver Bullet window — need score " +
                      IntegerToString(sp.minScore + 2) + "+ to trade";
         return;
      }
   }

   // Check cooldown — wait for new bar between entries
   datetime currentBar = iTime(_Symbol, TF_M15, 0);
   if(currentBar == g_LastEntryBar) return;

   // Determine which strategy triggered
   // Use dynamic thresholds (self-adjusted by learning system)
   int    effectivePrimScore  = UseAdaptiveLearning ? g_DynPrimaryScore  : MinPrimaryScore;
   int    effectiveFallScore  = UseAdaptiveLearning ? g_DynFallbackScore : MinFallbackScore;
   int    effectiveTertScore  = UseAdaptiveLearning ? g_DynTertiaryScore : MinTertiaryScore;

   // Apply per-session score floor
   effectivePrimScore = MathMax(effectivePrimScore, sp.minScore);
   effectiveFallScore = MathMax(effectiveFallScore, sp.minScore);
   effectiveTertScore = MathMax(effectiveTertScore, sp.minScore);

   // Check session suspension
   if(IsSessionSuspended()) {
      g_EntryLog = StringFormat("SESSION SUSPENDED: %s has low win rate — learning system paused trading",
                                g_Session);
      return;
   }

   // ── 3-TIER CASCADE: Primary → Fallback → Tertiary ──
   // Tier 1: H4 → H1 → M15
   bool primaryReady  = (g_PrimaryScore  >= effectivePrimScore);
   // Tier 2: H1 → M15 → M5 (only when primary not ready)
   bool fallbackReady = !primaryReady && (g_FallbackScore >= effectiveFallScore);
   // Tier 3: M15 → M5 → M1 (only when both primary and fallback not ready)
   bool tertiaryReady = !primaryReady && !fallbackReady && (g_TertiaryScore >= effectiveTertScore);

   if(!primaryReady && !fallbackReady && !tertiaryReady) { g_AlertSent = false; return; }

   // Pick the active tier
   bool   isBuy;
   int    score;
   double riskPct;
   string strategy;
   ENUM_TIMEFRAMES entryTF;

   if(primaryReady) {
      isBuy    = g_H4.bullish;
      score    = g_PrimaryScore;
      riskPct  = PrimaryRisk;
      strategy = "PRIMARY";
      entryTF  = TF_M15;
   } else if(fallbackReady) {
      isBuy    = g_H1.bullish;
      score    = g_FallbackScore;
      riskPct  = FallbackRisk;
      strategy = "FALLBACK";
      entryTF  = TF_M5;
   } else {
      isBuy    = g_M15.bullish;
      score    = g_TertiaryScore;
      riskPct  = TertiaryRisk;
      strategy = "TERTIARY";
      entryTF  = TF_M1;
   }

   // ── SESSION-SPECIFIC TIER RULES ──
   // Asian KZ: H4 trend is irrelevant during range consolidation — PRIMARY tier blocked.
   // Asian/Premarket must be at Asian range extreme (within 20 pips of High/Low), not mid-range.
   if(isAsian) {
      if(primaryReady) {
         primaryReady  = false;
         fallbackReady = (g_FallbackScore >= effectiveFallScore);
         tertiaryReady = !fallbackReady && (g_TertiaryScore >= effectiveTertScore);
         if(fallbackReady) {
            isBuy    = g_H1.bullish;
            score    = g_FallbackScore;
            riskPct  = FallbackRisk;
            strategy = "FALLBACK";
            entryTF  = TF_M5;
         } else if(tertiaryReady) {
            isBuy    = g_M15.bullish;
            score    = g_TertiaryScore;
            riskPct  = TertiaryRisk;
            strategy = "TERTIARY";
            entryTF  = TF_M1;
         } else {
            g_EntryLog = "ASIAN: PRIMARY blocked (range session — H4 bias irrelevant), no fallback tier";
            return;
         }
      }
      // Must be at Asian range extreme — no mid-range entries
      bool atAsianExtreme = false;
      double asianEdge = 0;
      string asianEdgeName = "";
      if(isBuy) {
         asianEdge     = g_M15.asianLow;
         asianEdgeName = "Low";
         if(asianEdge > 0 && MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_BID) - asianEdge) < pip * 20)
            atAsianExtreme = true;
      } else {
         asianEdge     = g_M15.asianHigh;
         asianEdgeName = "High";
         if(asianEdge > 0 && MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_ASK) - asianEdge) < pip * 20)
            atAsianExtreme = true;
      }
      if(!atAsianExtreme) {
         g_EntryLog = StringFormat("ASIAN: Mid-range — price must reach Asian %s (%.2f) within 20 pips",
                                   asianEdgeName, asianEdge);
         return;
      }
   }

   // NY PM: wind-down session — PRIMARY tier blocked entirely (only scalp tiers allowed).
   // Silver Bullet window is already gated above; this enforces the tier cap.
   if(curSessIdx == SESS_NY_PM && primaryReady) {
      primaryReady  = false;
      fallbackReady = (g_FallbackScore >= effectiveFallScore);
      tertiaryReady = !fallbackReady && (g_TertiaryScore >= effectiveTertScore);
      if(fallbackReady) {
         isBuy    = g_H1.bullish;
         score    = g_FallbackScore;
         riskPct  = FallbackRisk;
         strategy = "FALLBACK";
         entryTF  = TF_M5;
      } else if(tertiaryReady) {
         isBuy    = g_M15.bullish;
         score    = g_TertiaryScore;
         riskPct  = TertiaryRisk;
         strategy = "TERTIARY";
         entryTF  = TF_M1;
      } else {
         g_EntryLog = "NY PM: PRIMARY blocked (wind-down — scalp tiers only outside SB window), no fallback tier";
         return;
      }
   }

   // ── JUDAS SWING DIRECTION OVERRIDE ──
   // Pre-session / London Open / NY Open: if Judas Sweep detected, the REAL trade is the REVERSAL.
   // London sessions: judasSwingBull/Bear uses Asian range (correct — London sweeps Asia).
   // NY sessions: check LONDON session range instead — NY sweeps the London range.
   bool judasActive = g_M15.isJudasSwing || g_M5.isJudasSwing;
   bool judasSession = (curSessIdx == SESS_PRELONDON  || curSessIdx == SESS_LONDON_OPEN ||
                        curSessIdx == SESS_PRENY      || curSessIdx == SESS_NY_OPEN);

   // NY-specific: override Judas direction using London session range (not Asian range)
   bool nyLondonJudasBull = false; // swept above London high → SELL
   bool nyLondonJudasBear = false; // swept below London low  → BUY
   if((curSessIdx == SESS_PRENY || curSessIdx == SESS_NY_OPEN) &&
       g_LondonSessionHigh > 0 && g_LondonSessionLow > 0) {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // Swept above London high: wick above + close (bid) back below = NY sells the false break
      nyLondonJudasBull = (ask > g_LondonSessionHigh && bid < g_LondonSessionHigh && g_M15.hasCHoCH);
      // Swept below London low: wick below + close (ask) back above = NY buys the false break
      nyLondonJudasBear = (bid < g_LondonSessionLow  && ask > g_LondonSessionLow  && g_M15.hasCHoCH);
      if(nyLondonJudasBull || nyLondonJudasBear) {
         judasActive = true; // treat as Judas for downstream gates
         if(nyLondonJudasBull) {
            isBuy  = false;
            score += 4; // NY London Judas = very high probability (full day manipulation)
            strategy += "_JUDAS_LDN";
         } else {
            isBuy  = true;
            score += 4;
            strategy += "_JUDAS_LDN";
         }
      }
   }

   if(judasActive && judasSession && !nyLondonJudasBull && !nyLondonJudasBear) {
      if(g_M15.judasSwingBull || g_M5.judasSwingBull) {
         isBuy  = false;  // Swept above → sell the reversal
         score += 3;
         strategy += "_JUDAS";
      } else if(g_M15.judasSwingBear || g_M5.judasSwingBear) {
         isBuy  = true;   // Swept below → buy the reversal
         score += 3;
         strategy += "_JUDAS";
      }
   }

   // ── PRE-LONDON / PRE-NY SWEEP GATE ──
   // These windows exist purely for Judas Swing setups and key liquidity sweep reversals.
   // Any random spike without sweep confirmation = not tradeable.
   if(isPreLondon || isPreNY) {
      bool hasSweepSetup = judasActive ||
                           g_H1.sweepPDH || g_H1.sweepPDL ||
                           g_H4.sweepPWH || g_H4.sweepPWL ||
                           g_M15.sweepPDH || g_M15.sweepPDL;
      if(!hasSweepSetup) {
         g_EntryLog = StringFormat("%s: No Judas Swing or PDH/PDL sweep — random spike, not tradeable",
                                   sp.tag);
         return;
      }
      // Without Judas: also require MSS for structure confirmation (sweep alone = not enough)
      if(!judasActive && !g_M15.hasMSS && !g_M5.hasMSS) {
         g_EntryLog = StringFormat("%s PDH/PDL-only: MSS required on M15/M5 — sweep not yet confirmed",
                                   sp.tag);
         return;
      }
   }

   // ── PDH/PDL/PWH/PWL RUNNING-INTO BLOCK ──
   // Don't buy when price is charging toward PDH overhead (resistance 50 pips away).
   // Don't sell when price is charging toward PDL below (support 50 pips away).
   // Exception: if the level is being SWEPT (Judas into the level) allow the trade.
   bool pdSweepActive = isBuy  ? (g_H1.sweepPDL || g_H1.sweepPWL || g_M15.sweepPDL) :
                                  (g_H1.sweepPDH || g_H1.sweepPWH || g_M15.sweepPDH);
   if(!pdSweepActive) {
      if(isBuy  && (g_H1.runningToPDH || g_H4.runningToPDH)) {
         g_EntryLog = StringFormat("PDH BLOCK: BUY blocked — PDH at %.2f is %.1f pips overhead (resistance)",
                                   g_H1.prevDayHigh,
                                   (g_H1.prevDayHigh - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) /
                                   (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10));
         return;
      }
      if(!isBuy && (g_H1.runningToPDL || g_H4.runningToPDL)) {
         g_EntryLog = StringFormat("PDL BLOCK: SELL blocked — PDL at %.2f is %.1f pips below (support)",
                                   g_H1.prevDayLow,
                                   (SymbolInfoDouble(_Symbol, SYMBOL_BID) - g_H1.prevDayLow) /
                                   (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10));
         return;
      }
   }

   // ── DAILY BIAS LOCK — set after London Open / Pre-London confirms direction ──
   // Pre-London spike often reveals the day's real direction before London even opens.
   bool isLondonBiasSession = (curSessIdx == SESS_PRELONDON || curSessIdx == SESS_LONDON_OPEN);
   if(isLondonBiasSession && !g_DailyBiasLocked) {
      // Lock only when H1 + M15 agree (not just M15 noise)
      if(g_H1.bullish == g_M15.bullish) {
         g_DailyBias       = isBuy;
         g_DailyBiasLocked = true;
         g_DailyBiasDate   = TimeCurrent();
      }
   }
   // NY Open: if daily bias is locked, only trade in bias direction
   if(curSessIdx == SESS_NY_OPEN && g_DailyBiasLocked) {
      if(isBuy != g_DailyBias) {
         g_EntryLog = StringFormat("NY BIAS FILTER: %s trade blocked — London set %s bias today",
                                   isBuy ? "BUY" : "SELL",
                                   g_DailyBias ? "BULLISH" : "BEARISH");
         return;
      }
   }

   // London Mid: continuation of London Open move only — counter-trend always blocked.
   // London Mid is distribution/extension phase; reversal entries here are low-probability traps.
   if(curSessIdx == SESS_LONDON_MID) {
      if(g_DailyBiasLocked && isBuy != g_DailyBias) {
         g_EntryLog = StringFormat("LONDON MID: Counter-trend %s blocked — London Open set %s bias (continuation only)",
                                   isBuy ? "BUY" : "SELL",
                                   g_DailyBias ? "BULLISH" : "BEARISH");
         return;
      }
      // Even without bias lock, require H4+H1 agreement — no lone M15 signals in London Mid
      if(!g_DailyBiasLocked && g_H4.bullish != g_H1.bullish) {
         g_EntryLog = "LONDON MID: H4/H1 conflict — need higher-TF alignment for continuation entry";
         return;
      }
   }

   // ── CROSS-SESSION DIRECTION CONFLICT PREVENTION ──
   // Don't stack opposite directions: if SELL trades are open, block BUY (and vice versa)
   // Exception: allow if current session is high-confidence (score >= ScaledScore2)
   if(isBuy && g_OpenSells > 0 && score < ScaledScore2) {
      g_EntryLog = StringFormat("DIRECTION CONFLICT: %d SELL(s) open — need score≥%d to add BUY",
                                g_OpenSells, ScaledScore2);
      return;
   }
   if(!isBuy && g_OpenBuys > 0 && score < ScaledScore2) {
      g_EntryLog = StringFormat("DIRECTION CONFLICT: %d BUY(s) open — need score≥%d to add SELL",
                                g_OpenBuys, ScaledScore2);
      return;
   }

   // ── PO3 PHASE SESSION GATE ──
   // Accumulation phase → only Asian/Pre-market/Pre-London range setups
   // Manipulation phase → Judas reversal sessions (Pre-London, London Open, Pre-NY, NY Open)
   // Distribution phase → all sessions (trend follow)
   {
      bool inAccumSession = (curSessIdx == SESS_ASIAN     || curSessIdx == SESS_PREMARKET ||
                             curSessIdx == SESS_PRELONDON || curSessIdx == SESS_PRENY);
      if(g_M15.po3Accumulation && !inAccumSession) {
         g_EntryLog = "PO3 GATE: Accumulation phase — range/Judas setups only, no trend entries";
         return;
      }
   }

   // ── PRICE-AT-ZONE CHECK (Sniper Gate) ──
   // For a true sniper entry, price must be AT a valid SMC entry zone, not just near one.
   // At minimum: price in OTE zone, or at CE (FVG midpoint), or currently inside OB, or at IPDA level.
   // Bypass in Asian/Pre-market (range fade at extremes already checked above).
   if(curSessIdx != SESS_ASIAN && curSessIdx != SESS_PREMARKET) {
      bool atZone = false;
      SMCAnalysis ref;
      if(primaryReady)       ref = g_H1;
      else if(fallbackReady) ref = g_M15;
      else                   ref = g_M5;
      atZone = atZone || ref.inOTE;           // Price in 61.8-79% retracement
      atZone = atZone || ref.atCE;            // At FVG midpoint (CE)
      atZone = atZone || (ref.hasFreshOB &&
                          StringFind(ref.obStatus, "In OB") >= 0); // Inside OB
      atZone = atZone || ref.atIPDALevel;     // At IPDA 20/40/60 day boundary
      atZone = atZone || g_M15.inOTE || g_M15.atCE;
      if(!atZone) {
         g_EntryLog = StringFormat("ZONE CHECK: Not at OTE/CE/OB/IPDA — waiting for pullback to entry zone (%s)",
                                   strategy);
         g_AlertSent = false;
         return;
      }
   }

   // ── CANDLE CONFIRMATION CHECK — before expensive checks ──
   if(!CheckCandleConfirmation(isBuy, entryTF)) {
      g_EntryLog = StringFormat("CANDLE: Waiting for %s confirmation on %s",
                                isBuy ? "bullish" : "bearish", TFToString(entryTF));
      g_AlertSent = false;
      return;
   }

   // ── SMT DIVERGENCE CHECK ──
   // BULL_CONFIRM = DXY weakening + Gold rising → confirms BUY, overrides DXY block
   // BEAR_CONFIRM = DXY strengthening + Gold falling → confirms SELL, overrides DXY block
   bool smtConfirmedDir = false;
   if(UseSMTDivergence && g_SMTDivergence) {
      bool smtContradict = (isBuy  && g_SMTType == "BEAR_CONFIRM") ||
                           (!isBuy && g_SMTType == "BULL_CONFIRM");
      bool smtConfirm    = (isBuy  && g_SMTType == "BULL_CONFIRM") ||
                           (!isBuy && g_SMTType == "BEAR_CONFIRM");
      if(smtContradict) {
         g_EntryLog = StringFormat("SMT BLOCKED: %s trade contradicted by SMT (%s)",
                                   isBuy ? "BUY" : "SELL", g_SMTType);
         return;
      }
      if(smtConfirm) {
         score += 2;
         smtConfirmedDir = true; // SMT confirming = override DXY block below
      }
   }

   // ── DXY CORRELATION CHECK ──
   // If SMT already confirmed the direction (Gold vs DXY divergence), DXY trend block is bypassed —
   // the divergence itself IS the SMT setup. Otherwise DXY must align.
   if(!smtConfirmedDir && !IsDXYAligned(isBuy)) {
      g_EntryLog = StringFormat("DXY BLOCKED: %s trade conflicts with DXY trend — %s",
                                isBuy ? "BUY" : "SELL", g_DXY_Status);
      g_AlertSent = false;
      return;
   }

   // ── PER-SESSION RISK & TP OVERRIDES ──
   // Cap tier risk at session's maximum — never exceed session limit
   double effectiveTP1_RR = sp.tp1RR;
   double effectiveTP2_RR = sp.tp2RR;
   riskPct = MathMin(riskPct, sp.risk);
   if(StringLen(sp.tag) > 0) strategy += "_" + StringSubstr(sp.tag, 1, StringLen(sp.tag)-2);

   // ── SCALED ENTRY GATE ──
   int openNow    = CountOpenTrades();
   // OneTradeAtATime overrides scaled entries — hard cap at 1 regardless of score
   int maxAllowed = OneTradeAtATime ? 1 : GetMaxEntriesForScore(score);
   // Also cap at session's maxNewTrades
   maxAllowed = MathMin(maxAllowed, sp.maxNewTrades >= 99 ? maxAllowed : sp.maxNewTrades);
   if(maxAllowed == 0) {
      g_EntryLog = StringFormat("SCALED: Score %d below threshold (need %d for 1 entry)",
                                score, ScaledScore1);
      g_AlertSent = false;
      return;
   }
   if(openNow >= maxAllowed) {
      g_EntryLog = StringFormat("SCALED: %d/%d trades open — waiting for close or higher score",
                                openNow, maxAllowed);
      return;
   }

   // ── BRIDGE STATE MACHINE ──
   if(UseBridge) {
      if(g_BridgeState == BRIDGE_WAITING) {
         CheckBridgeTimeout();
         if(!ReadBridgeResponse()) return;
      }
      if(g_BridgeState == BRIDGE_REJECTED) {
         g_BridgeState = BRIDGE_IDLE;
         g_EntryLog    = StringFormat("Claude SKIPPED: %s", g_BridgeReason);
         return;
      }
   }

   // Avoid re-alerting same signal — but DO re-alert if direction flipped
   if(g_AlertSent && score == g_LastSignalScore && isBuy == g_LastSignalIsBuy) return;

   // Calculate SL — either ATR-based or sweep-wick based
   double slPips;
   if(UseATRStop) {
      int atrHnd2 = iATR(_Symbol, TF_H1, ATR_Period);
      double atrBuf2[];
      ArraySetAsSeries(atrBuf2, true);
      double atrPips2 = 30.0; // safe fallback
      if(atrHnd2 != INVALID_HANDLE && CopyBuffer(atrHnd2, 0, 1, 1, atrBuf2) == 1)
         atrPips2 = atrBuf2[0] / pip;
      slPips = MathMax(atrPips2 * ATR_SLMultiplier, 25.0);
      // Override TP2 with ATR multiple when ATR stop mode active
      effectiveTP2_RR = ATR_TPMultiplier / ATR_SLMultiplier; // express as RR ratio
   } else {
      double slRef  = GetSweepLevel(isBuy, entryTF);
      slPips = MathAbs((isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(_Symbol, SYMBOL_BID)) - slRef)
                / pip + SL_BufferPips;
      slPips = MathMax(slPips, 25.0); // Gold minimum SL: 25 pips ($2.50)
   }

   // Check minimum RR — sessions with tight custom TP targets bypass the global MinRR
   double tp2Pips = slPips * effectiveTP2_RR;
   bool customTP = (curSessIdx == SESS_ASIAN    || curSessIdx == SESS_NY_PM ||
                    curSessIdx == SESS_PRELONDON || curSessIdx == SESS_PRENY);
   if(!customTP && tp2Pips / slPips < MinRR) return;

   // Calculate lot size using exact SL
   double lots = CalcLotSize(riskPct, slPips);
   g_LastLotSize = lots;

   // Build prices
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry  = isBuy ? ask : bid;
   double sl     = isBuy ? entry - slPips * pip : entry + slPips * pip;
   double tp1    = isBuy ? entry + slPips * effectiveTP1_RR * pip : entry - slPips * effectiveTP1_RR * pip;
   double tp2    = isBuy ? entry + slPips * effectiveTP2_RR * pip : entry - slPips * effectiveTP2_RR * pip;

   sl  = NormalizeDouble(sl,  _Digits);
   tp1 = NormalizeDouble(tp1, _Digits);
   tp2 = NormalizeDouble(tp2, _Digits);

   string comment = StringFormat("Sniper %s %s Sc:%d", strategy, isBuy?"BUY":"SELL", score);

   // ── BRIDGE — write signal and wait for Claude approval ──
   if(UseBridge && g_BridgeState == BRIDGE_IDLE) {
      // Store pending trade parameters
      g_PendingIsBuy    = isBuy;
      g_PendingEntry    = entry;
      g_PendingSL       = sl;
      g_PendingTP1      = tp1;
      g_PendingTP2      = tp2;
      g_PendingLots     = lots;
      g_PendingRisk     = riskPct;
      g_PendingStrategy = strategy;
      g_PendingScore    = score;
      WriteBridgeSignal(isBuy, score, strategy, entry, sl, tp1, tp2, lots, riskPct);
      return; // Come back next tick with response
   }

   // If bridge approved with SL adjustment — apply Claude's suggested SL
   if(UseBridge && g_BridgeState == BRIDGE_APPROVED && StringLen(g_BridgeSLStr) > 0) {
      double claudeSL = StringToDouble(g_BridgeSLStr);
      if(claudeSL > 0) {
         sl  = claudeSL;
         // Recalculate SL pips and lots with new SL
         double newSlPips = MathAbs(entry - sl) / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10);
         lots = CalcLotSize(riskPct, newSlPips);
         g_EntryLog = StringFormat("Claude adjusted SL to %.2f", sl);
      }
   }

   // Reset bridge state for next trade
   if(UseBridge) g_BridgeState = BRIDGE_IDLE;

   // Alert regardless of AutoTrade setting
   if(!g_AlertSent) {
      SendSignalNotification(strategy, isBuy, score, entry, sl, tp1, tp2, riskPct, lots);
      g_AlertSent        = true;
      g_LastSignalScore  = score;
      g_LastSignalIsBuy  = isBuy;
      g_EntryLog = StringFormat("SIGNAL: %s %s | Score:%d | Entry:%.2f SL:%.2f TP1:%.2f TP2:%.2f | Lots:%.2f",
                                strategy, isBuy?"BUY":"SELL", score, entry, sl, tp1, tp2, lots);
   }

   // Auto execute if enabled
   if(!AutoTrade) return;

   g_LastTP1RR = effectiveTP1_RR;
   g_LastTP2RR = effectiveTP2_RR;

   // ── FVG PENDING ORDER MODE ──
   // If enabled: price approaching FVG but not yet inside → place BUY/SELL LIMIT at CE.
   // If price is already inside FVG → fall back to market order (immediate execution).
   if(UsePendingOrders) {
      SMCAnalysis fvgRef;
      if(primaryReady)       fvgRef = g_H1;
      else if(fallbackReady) fvgRef = g_M15;
      else                   fvgRef = g_M5;
      bool hasFVG      = fvgRef.hasFVGOpen && fvgRef.fvgHigh > 0 && fvgRef.fvgLow > 0;
      bool insideFVG   = hasFVG && ask >= fvgRef.fvgLow && bid <= fvgRef.fvgHigh;
      bool approachFVG = hasFVG && !insideFVG &&
                         (isBuy  ? (ask > fvgRef.fvgHigh && (ask - fvgRef.fvgHigh) < pip * 30) :
                                   (bid < fvgRef.fvgLow  && (fvgRef.fvgLow - bid)  < pip * 30));

      if(approachFVG) {
         // Only one FVG pending per direction at a time
         bool alreadyPending = false;
         for(int pi = 0; pi < ArraySize(g_FVGPendings); pi++) {
            if(g_FVGPendings[pi].isBuy == isBuy) { alreadyPending = true; break; }
         }
         if(!alreadyPending) {
            PlaceFVGPendingOrder(isBuy, fvgRef.fvgHigh, fvgRef.fvgLow, fvgRef.fvgMid,
                                 sl, tp1, tp2, lots, strategy, score);
            g_LastEntryBar = currentBar;
         } else {
            g_EntryLog = StringFormat("FVG LIMIT: Already have %s limit pending — waiting for fill or expiry",
                                      isBuy ? "BUY" : "SELL");
         }
         return;
      }

      // Price inside FVG: market order if fallback enabled, otherwise wait for pullback
      if(hasFVG && insideFVG && !PendingMarketFallback) {
         g_EntryLog = StringFormat("FVG MODE: Price inside FVG (%.2f-%.2f) — waiting for CE pullback entry",
                                   fvgRef.fvgLow, fvgRef.fvgHigh);
         return;
      }
      // No FVG detected or price already inside with fallback enabled → fall through to market order
   }

   // ── SCALED MARKET ENTRIES — execute up to maxAllowed trades ──
   // Each entry staggers its TP2 slightly to avoid all closing at the same tick
   int toPlace  = MathMax(1, MathMin(maxAllowed - openNow,
                              UseScaledEntries ? maxAllowed - openNow : 1));
   int placed   = 0;
   int failed   = 0;
   string ticketList = "";

   for(int ei = 0; ei < toPlace; ei++) {
      // Stagger TP2 on 2nd and 3rd entries (+0.2 RR each) for independent targets
      double entryTP2 = isBuy ? entry + slPips * (effectiveTP2_RR + ei * 0.2) * pip
                               : entry - slPips * (effectiveTP2_RR + ei * 0.2) * pip;
      entryTP2 = NormalizeDouble(entryTP2, _Digits);

      string entryComment = StringFormat("Sniper %s %s Sc:%d E%d/%d",
                                         strategy, isBuy?"BUY":"SELL", score,
                                         ei + 1, toPlace);
      bool ok = false;
      if(isBuy)
         ok = Trade.Buy(lots, _Symbol, ask, sl, entryTP2, entryComment);
      else
         ok = Trade.Sell(lots, _Symbol, bid, sl, entryTP2, entryComment);

      if(ok) {
         placed++;
         ulong newTicket = Trade.ResultOrder();
         ticketList += "#" + IntegerToString(newTicket) + " ";
         if(UseAdaptiveLearning) RegisterSnapshot(newTicket, strategy);
      } else {
         failed++;
      }
   }

   if(placed > 0) {
      g_LastEntryBar = currentBar;
      g_EntryLog = StringFormat("ENTERED %d/%d: %s %s | Score:%d | Entry:%.2f SL:%.2f TP2:%.2f | Lots:%.2f | %s",
                                placed, toPlace, strategy, isBuy?"BUY":"SELL", score,
                                entry, sl, tp2, lots, ticketList);
   }
   if(failed > 0) {
      g_EntryLog += StringFormat(" | %d FAILED (Error %d: %s)",
                                 failed, Trade.ResultRetcode(),
                                 Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| FVG Pending Orders — place limit at CE, manage expiry/cancel   |
//+------------------------------------------------------------------+
bool PlaceFVGPendingOrder(bool isBuy, double fvgHigh, double fvgLow, double fvgMid,
                          double sl, double tp1, double tp2, double lots,
                          string strategy, int score) {
   double pip    = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
   double buf    = PendingFVGBuffer * pip;

   // Limit price: CE (midpoint) shifted slightly inside FVG for better fill
   double limitPrice = isBuy  ? fvgMid + buf   // BUY LIMIT: just above CE into the gap
                               : fvgMid - buf;  // SELL LIMIT: just below CE into the gap
   limitPrice = NormalizeDouble(limitPrice, _Digits);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = _Symbol;
   req.volume       = lots;
   req.type         = isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   req.price        = limitPrice;
   req.sl           = NormalizeDouble(sl,  _Digits);
   req.tp           = NormalizeDouble(tp2, _Digits);
   req.magic        = MagicNumber;
   req.deviation    = MaxSlippagePips;
   req.type_time    = ORDER_TIME_SPECIFIED;
   req.expiration   = iTime(_Symbol, TF_M15, 0) + PendingExpiryBars * PeriodSeconds(TF_M15);
   req.comment      = StringFormat("Sniper FVG %s %s Sc:%d", strategy, isBuy?"BUY":"SELL", score);

   bool ok = OrderSend(req, res);
   if(ok && res.order > 0) {
      int n = ArraySize(g_FVGPendings);
      ArrayResize(g_FVGPendings, n + 1);
      g_FVGPendings[n].ticket    = res.order;
      g_FVGPendings[n].isBuy     = isBuy;
      g_FVGPendings[n].placedBar = iTime(_Symbol, TF_M15, 0);
      g_FVGPendings[n].fvgHigh   = fvgHigh;
      g_FVGPendings[n].fvgLow    = fvgLow;
      g_FVGPendings[n].strategy  = strategy;
      g_EntryLog = StringFormat("FVG LIMIT PLACED: %s %s @ %.2f | FVG %.2f-%.2f CE:%.2f | SL:%.2f TP:%.2f | Ticket:#%d",
                                strategy, isBuy?"BUY":"SELL", limitPrice,
                                fvgLow, fvgHigh, fvgMid, sl, tp2, (long)res.order);
      return true;
   }
   g_EntryLog = StringFormat("FVG LIMIT FAILED: %s %s @ %.2f | Error %d: %s",
                             strategy, isBuy?"BUY":"SELL", limitPrice,
                             res.retcode, Trade.ResultRetcodeDescription());
   return false;
}

void ManagePendingOrders() {
   if(ArraySize(g_FVGPendings) == 0) return;

   double pip        = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0;
   datetime nowBar   = iTime(_Symbol, TF_M15, 0);
   int      sessIdx  = GetSessionIndex();
   int      toRemove[];

   for(int i = 0; i < ArraySize(g_FVGPendings); i++) {
      ulong ticket = g_FVGPendings[i].ticket;

      // Check if order still exists
      if(!OrderSelect(ticket)) {
         // Already filled or externally cancelled — remove tracking entry
         ArrayResize(toRemove, ArraySize(toRemove) + 1);
         toRemove[ArraySize(toRemove)-1] = i;
         continue;
      }

      bool shouldCancel = false;
      string cancelReason = "";

      // 1. Expiry: PendingExpiryBars M15 bars passed since placement
      datetime placedBar = g_FVGPendings[i].placedBar;
      int barsElapsed = (int)((nowBar - placedBar) / PeriodSeconds(TF_M15));
      if(barsElapsed >= PendingExpiryBars) {
         shouldCancel  = true;
         cancelReason  = StringFormat("FVG LIMIT EXPIRED: %d bars elapsed (max %d)", barsElapsed, PendingExpiryBars);
      }

      // 2. Session changed to non-trading session — no point waiting
      if(!shouldCancel && sessIdx == SESS_OTHER) {
         shouldCancel = true;
         cancelReason = "FVG LIMIT CANCELLED: Session ended";
      }

      // 3. FVG invalidated: price traded THROUGH the zone (FVG filled from wrong side)
      if(!shouldCancel) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         bool fvgBroken = g_FVGPendings[i].isBuy  ? (bid < g_FVGPendings[i].fvgLow  - pip * 3) :
                                                     (ask > g_FVGPendings[i].fvgHigh + pip * 3);
         if(fvgBroken) {
            shouldCancel = true;
            cancelReason = StringFormat("FVG INVALIDATED: Price broke through FVG zone (%.2f-%.2f)",
                                        g_FVGPendings[i].fvgLow, g_FVGPendings[i].fvgHigh);
         }
      }

      if(shouldCancel) {
         Trade.OrderDelete(ticket);
         g_EntryLog = cancelReason;
         ArrayResize(toRemove, ArraySize(toRemove) + 1);
         toRemove[ArraySize(toRemove)-1] = i;
      }
   }

   // Remove cancelled/filled entries (reverse order to preserve indices)
   for(int r = ArraySize(toRemove) - 1; r >= 0; r--) {
      int idx = toRemove[r];
      int n   = ArraySize(g_FVGPendings);
      for(int j = idx; j < n - 1; j++)
         g_FVGPendings[j] = g_FVGPendings[j+1];
      ArrayResize(g_FVGPendings, n - 1);
   }
}

//+------------------------------------------------------------------+
//| Get sweep level (lowest wick for buy, highest wick for sell)    |
//+------------------------------------------------------------------+
double GetSweepLevel(bool isBuy, ENUM_TIMEFRAMES tf) {
   double arr[];
   ArraySetAsSeries(arr, true);
   if(isBuy) {
      CopyLow(_Symbol, tf, 1, Sweep_Lookback, arr);
      return arr[ArrayMinimum(arr, 0, Sweep_Lookback)];
   } else {
      CopyHigh(_Symbol, tf, 1, Sweep_Lookback, arr);
      return arr[ArrayMaximum(arr, 0, Sweep_Lookback)];
   }
}

//+------------------------------------------------------------------+
//| Count EA's open trades on this symbol                           |
//+------------------------------------------------------------------+
int CountOpenTrades() {
   int count = 0;
   g_OpenBuys  = 0;
   g_OpenSells = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionInfo.SelectByIndex(i) &&
         PositionInfo.Symbol() == _Symbol &&
         PositionInfo.Magic()  == MagicNumber) {
         count++;
         if(PositionInfo.PositionType() == POSITION_TYPE_BUY)  g_OpenBuys++;
         else                                                    g_OpenSells++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Capital Protection — Breakeven, Trail SL, Partial TP           |
//+------------------------------------------------------------------+
void ManageCapitalProtection() {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double pip   = point * 10; // 1 pip for 5-digit broker

   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!PositionInfo.SelectByIndex(i)) continue;
      if(PositionInfo.Symbol() != _Symbol)   continue;
      if(PositionInfo.Magic()  != MagicNumber) continue;

      ulong  ticket     = PositionInfo.Ticket();
      bool   isBuy      = (PositionInfo.PositionType() == POSITION_TYPE_BUY);
      double entry      = PositionInfo.PriceOpen();
      double currentSL  = PositionInfo.StopLoss();
      double currentTP  = PositionInfo.TakeProfit();
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price      = isBuy ? currentBid : currentAsk;
      double lots       = PositionInfo.Volume();

      // Calculate SL distance
      double slDistance = MathAbs(entry - currentSL);
      if(slDistance <= 0) continue;

      // Current profit in price terms
      double profit = isBuy ? (price - entry) : (entry - price);

      // ── Find or create trade state ──
      int idx = FindTradeState(ticket);
      if(idx < 0) {
         idx = RegisterTrade(ticket, entry, currentSL, isBuy, lots, g_LastTP1RR, g_LastTP2RR);
         if(idx < 0) continue;
      }

      // ── PARTIAL TP — Close 50% at TP1 (1:1 RR) ──
      if(UsePartialTP && !g_Trades[idx].partialTPDone) {
         double tp1Distance = slDistance * TP1_RR;
         if(profit >= tp1Distance) {
            double lotStep_     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            int    lotDigits_   = (lotStep_ >= 0.1) ? 1 : 2;
            double closeVolume  = NormalizeDouble(lots * PartialTPPercent / 100.0, lotDigits_);
            closeVolume = MathMax(closeVolume, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

            if(closeVolume < lots) {
               if(isBuy)
                  Trade.Sell(closeVolume, _Symbol, currentBid, 0, 0,
                             StringFormat("Partial TP1 #%d", ticket));
               else
                  Trade.Buy(closeVolume, _Symbol, currentAsk, 0, 0,
                            StringFormat("Partial TP1 #%d", ticket));

               g_Trades[idx].partialTPDone = true;
               g_ProtectionStatus = StringFormat("Partial TP hit — closed %.0f%% at #%d",
                                                  PartialTPPercent, ticket);
            }
         }
      }

      // ── BREAKEVEN — Move SL to entry when profit >= trigger ──
      if(UseBreakeven && !g_Trades[idx].breakEvenDone) {
         double beTriggerDist = slDistance * BreakevenTrigger;
         if(profit >= beTriggerDist) {
            double newSL = isBuy  ? entry + BreakevenBuffer * pip
                                  : entry - BreakevenBuffer * pip;
            newSL = NormalizeDouble(newSL, _Digits);

            // Only move SL if it improves (never widen it)
            bool shouldMove = isBuy  ? (newSL > currentSL)
                                     : (newSL < currentSL || currentSL == 0);
            if(shouldMove) {
               Trade.PositionModify(ticket, newSL, currentTP);
               g_Trades[idx].breakEvenDone = true;
               g_ProtectionStatus = StringFormat("Breakeven set at %.5f for #%d", newSL, ticket);
            }
         }
      }

      // ── TRAILING STOP — Follow price once trail starts ──
      if(UseTrailingStop) {
         double trailTriggerDist = slDistance * TrailStart;
         if(profit >= trailTriggerDist) {
            double trailDist = TrailDistance * pip;
            double trailSL   = isBuy  ? price - trailDist
                                       : price + trailDist;
            trailSL = NormalizeDouble(trailSL, _Digits);

            // Only move SL if it improves position
            bool shouldTrail = isBuy  ? (trailSL > currentSL + TrailStep * pip)
                                      : (trailSL < currentSL - TrailStep * pip ||
                                         currentSL == 0);
            if(shouldTrail) {
               Trade.PositionModify(ticket, trailSL, currentTP);
               g_ProtectionStatus = StringFormat("Trailing SL moved to %.5f for #%d",
                                                  trailSL, ticket);
            }
         }
      }
   }

   // Clean up closed trades from state array
   CleanupClosedTrades();
}

//+------------------------------------------------------------------+
//| Find trade state index by ticket                                |
//+------------------------------------------------------------------+
int FindTradeState(ulong ticket) {
   for(int i = 0; i < ArraySize(g_Trades); i++)
      if(g_Trades[i].ticket == ticket)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Register a new trade in state array                             |
//+------------------------------------------------------------------+
int RegisterTrade(ulong ticket, double entry, double sl,
                  bool isBuy, double lots,
                  double tp1RR = -1.0, double tp2RR = -1.0) {
   double slDist = MathAbs(entry - sl);
   double r1     = (tp1RR > 0) ? tp1RR : TP1_RR;
   double r2     = (tp2RR > 0) ? tp2RR : TP2_RR;

   int idx = ArraySize(g_Trades);
   ArrayResize(g_Trades, idx + 1);

   g_Trades[idx].ticket        = ticket;
   g_Trades[idx].breakEvenDone = false;
   g_Trades[idx].partialTPDone = false;
   g_Trades[idx].entryPrice    = entry;
   g_Trades[idx].initialSL     = sl;
   g_Trades[idx].isBuy         = isBuy;
   g_Trades[idx].lotSize       = lots;
   g_Trades[idx].tp1Price      = isBuy ? entry + slDist * r1 : entry - slDist * r1;
   g_Trades[idx].tp2Price      = isBuy ? entry + slDist * r2 : entry - slDist * r2;
   return idx;
}

//+------------------------------------------------------------------+
//| Remove closed trades from state array                           |
//+------------------------------------------------------------------+
void CleanupClosedTrades() {
   for(int i = ArraySize(g_Trades) - 1; i >= 0; i--) {
      if(!PositionSelectByTicket(g_Trades[i].ticket)) {
         // Shift array left
         for(int j = i; j < ArraySize(g_Trades) - 1; j++)
            g_Trades[j] = g_Trades[j + 1];
         ArrayResize(g_Trades, ArraySize(g_Trades) - 1);
      }
   }
   if(ArraySize(g_Trades) == 0)
      g_ProtectionStatus = "No open trades";
}

//+------------------------------------------------------------------+
//| Timer — keeps dashboard alive on any TF                         |
//+------------------------------------------------------------------+
void OnTimer() {
   AnalyzeAllTimeframes();
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Chart event — redraw everything when user switches timeframe    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_CHART_CHANGE) {
      // Force full redraw of visuals on next tick
      g_LastVisualBar = 0;

      // Rebuild dashboard for new TF
      DeleteDashboard();
      CreateDashboard();
      UpdateDashboard();

      // Redraw chart objects immediately
      ObjectsDeleteAll(0, "VIS_");
      if(!g_IsTesting) DrawChartVisuals();

      ChartRedraw(0);
   }
}

//+------------------------------------------------------------------+
//| Analyze all timeframes using advanced SMC engine                |
//+------------------------------------------------------------------+
void AnalyzeAllTimeframes() {
   g_H4  = AnalyzeSMC(_Symbol, TF_H4,  "H4",  BOS_Lookback);
   g_H1  = AnalyzeSMC(_Symbol, TF_H1,  "H1",  BOS_Lookback);
   g_M15 = AnalyzeSMC(_Symbol, TF_M15, "M15", BOS_Lookback);
   g_M5  = AnalyzeSMC(_Symbol, TF_M5,  "M5",  BOS_Lookback);
   g_M1  = AnalyzeSMC(_Symbol, TF_M1,  "M1",  BOS_Lookback);

   UpdateDXY();
   UpdateNewsCalendar();

   g_PrimaryScore   = ScorePrimaryAdvanced(g_H4, g_H1, g_M15);
   g_FallbackScore  = ScoreFallbackAdvanced(g_H1, g_M15, g_M5);
   g_TertiaryScore  = ScoreTertiaryAdvanced(g_M15, g_M5, g_M1);

   // ICT filter overrides: disable bonuses if their input toggle is off
   if(!UseKillzones) {
      g_H4.inLondonKZ=false; g_H4.inNYAmKZ=false;
      g_H1.inLondonKZ=false; g_H1.inNYAmKZ=false;
      g_M15.inLondonKZ=false; g_M15.inNYAmKZ=false;
      g_M5.inLondonKZ=false; g_M5.inNYAmKZ=false;
      g_M1.inLondonKZ=false; g_M1.inNYAmKZ=false;
   }
   if(!UseICTMacros) {
      g_H4.inICTMacro=false; g_H1.inICTMacro=false;
      g_M15.inICTMacro=false; g_M5.inICTMacro=false; g_M1.inICTMacro=false;
   }
   if(!UsePowerOf3) {
      g_H4.po3Distribution=false; g_H1.po3Distribution=false;
      g_M15.po3Distribution=false; g_M5.po3Distribution=false; g_M1.po3Distribution=false;
   }
   if(!UseIPDA) {
      g_H4.atIPDALevel=false; g_H1.atIPDALevel=false;
      g_M15.atIPDALevel=false; g_M5.atIPDALevel=false; g_M1.atIPDALevel=false;
   }
   if(!UseBPR) {
      g_H4.hasBPR=false; g_H1.hasBPR=false;
      g_M15.hasBPR=false; g_M5.hasBPR=false; g_M1.hasBPR=false;
   }
   if(!UseCE) {
      g_H4.atCE=false; g_H1.atCE=false;
      g_M15.atCE=false; g_M5.atCE=false; g_M1.atCE=false;
   }
   if(!UseMidnightOpen) {
      g_H4.nearMidnightOpen=false; g_H1.nearMidnightOpen=false;
      g_M15.nearMidnightOpen=false; g_M5.nearMidnightOpen=false; g_M1.nearMidnightOpen=false;
   }
   if(!UseGapDetection) {
      g_H4.hasNDOG=false; g_H4.hasNWOG=false;
      g_H1.hasNDOG=false; g_H1.hasNWOG=false;
      g_M15.hasNDOG=false; g_M5.hasNDOG=false; g_M1.hasNDOG=false;
   }

   // SMT Divergence check (Gold vs DXY)
   if(UseSMTDivergence) CheckSMTDivergence();
   else { g_SMTDivergence = false; g_SMTType = ""; }

   g_Session = GetSession();

   // Track London session range — used for NY Judas detection.
   // NY Judas sweeps the LONDON range (not Asian), so we need London H/L.
   // Capture and extend during London Open + London Mid, freeze once NY opens.
   {
      int curIdx = GetSessionIndex();
      bool inLondon = (curIdx == SESS_LONDON_OPEN || curIdx == SESS_LONDON_MID);
      MqlDateTime nowDt; TimeToStruct(TimeGMT(), nowDt);
      datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00",
                                                  nowDt.year, nowDt.mon, nowDt.day));
      if(g_LondonRangeDate != today) {
         // New day — reset London range
         g_LondonSessionHigh = 0;
         g_LondonSessionLow  = 0;
         g_LondonRangeDate   = today;
      }
      if(inLondon) {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double mid = (ask + bid) / 2.0;
         if(g_LondonSessionHigh == 0 || mid > g_LondonSessionHigh) g_LondonSessionHigh = mid;
         if(g_LondonSessionLow  == 0 || mid < g_LondonSessionLow)  g_LondonSessionLow  = mid;
      }
   }

   int effPrim = UseAdaptiveLearning ? g_DynPrimaryScore  : MinPrimaryScore;
   int effFall = UseAdaptiveLearning ? g_DynFallbackScore : MinFallbackScore;
   int effTert = UseAdaptiveLearning ? g_DynTertiaryScore : MinTertiaryScore;

   g_UseFallback  = (g_PrimaryScore  < effPrim);
   g_UseTertiary  = (g_PrimaryScore  < effPrim) && (g_FallbackScore < effFall);
   g_Recommendation = GetRecommendation();
}

// NOTE: AnalyzeTF, ScorePrimary, ScoreFallback replaced by SMC_Engine.mqh

//+------------------------------------------------------------------+
//| Get current session in PHT (UTC+8)                              |
//+------------------------------------------------------------------+
string GetSession() {
   datetime nowUTC = TimeGMT();
   MqlDateTime dt; TimeToStruct(nowUTC, dt);

   // DST-aware session opens — Philippines (UTC+8) never observes DST
   int loUTC  = GetLondonOpenUTC(nowUTC);   // 7 (summer/BST) or 8 (winter/GMT)
   int nyUTC  = GetNYOpenUTC(nowUTC);        // 12 (summer/EDT) or 13 (winter/EST)
   int loPHT  = (loUTC + 8) % 24;           // 15 (3PM) or 16 (4PM)
   int nyPHT  = (nyUTC + 8) % 24;           // 20 (8PM) or 21 (9PM)

   // Work in UTC minutes for sub-hour accuracy
   int utcMins = dt.hour * 60 + dt.min;

   // Pre-London spike window: [loUTC - PreLondonBlackoutMins, loUTC)
   // Asian range being swept → prime Judas Swing loading zone
   {
      int loMins    = loUTC * 60;
      int preLoMins = loMins - PreLondonBlackoutMins;
      if(utcMins >= preLoMins && utcMins < loMins) {
         int minsLeft = loMins - utcMins;
         return StringFormat("Pre-London Spike — Judas Loading (%d min to %dPM PHT)", minsLeft, loPHT);
      }
   }

   // Pre-NY spike window: [nyUTC - PreNYBlackoutMins, nyUTC)
   // London range sweep → Judas Swing into NY direction
   {
      int nyMins    = nyUTC * 60;
      int preNyMins = nyMins - PreNYBlackoutMins;
      if(utcMins >= preNyMins && utcMins < nyMins) {
         int minsLeft = nyMins - utcMins;
         return StringFormat("Pre-NY Spike — Judas Loading (%d min to %dPM PHT)", minsLeft, nyPHT);
      }
   }

   // Main session windows anchored to dynamic UTC opens:
   // Asian KZ:    21:00-23:00 UTC — fixed (Tokyo/Sydney don't shift PHT)
   // Pre-Market:  23:00 UTC → pre-London start (spans UTC midnight)
   // London Open: loUTC → loUTC+2
   // London Mid:  loUTC+2 → nyUTC (minus pre-NY window, handled above)
   // NY Open:     nyUTC → nyUTC+3
   // NY PM/SB:    nyUTC+3 → nyUTC+5
   // NY Closed:   nyUTC+5 → 21:00 UTC
   int utcH = dt.hour;
   if(utcH >= 21 && utcH < 23)
      return "Asian KZ — Watch for Judas Sweep (5AM-7AM PHT)";
   if(utcH >= loUTC && utcH < loUTC + 2)
      return StringFormat("London Open — TRADE WINDOW 1 (%dPM-%dPM PHT)", loPHT, loPHT+2);
   if(utcH >= loUTC + 2 && utcH < nyUTC)
      return StringFormat("London Session — Selective Trades (%dPM-%dPM PHT)", loPHT+2, nyPHT);
   if(utcH >= nyUTC && utcH < nyUTC + 3)
      return StringFormat("New York Open — BEST WINDOW (%dPM-%dPM PHT)", nyPHT, nyPHT+3);
   if(utcH >= nyUTC + 3 && utcH < nyUTC + 5)
      return StringFormat("NY PM / Silver Bullet — Wind Down (%dPM-%dAM PHT)", nyPHT+3, (nyPHT+5)%24);
   if(utcH >= nyUTC + 5 && utcH < 21)
      return "NY Closed — Sleep (1AM-5AM PHT)";
   // Everything else: pre-market (23:00 UTC → pre-London; spans midnight)
   return StringFormat("Pre-Market — Asian Extension (7AM-%dPM PHT)", loPHT);
}

//+------------------------------------------------------------------+
//| Returns true for hard blackout (UsePreSessionBlackout override)  |
//+------------------------------------------------------------------+
bool IsInPreSessionBlackout() {
   if(!UsePreSessionBlackout) return false;
   if(StringFind(g_Session, "Pre-London Spike") >= 0) return true;
   if(StringFind(g_Session, "Pre-NY Spike")     >= 0) return true;
   return false;
}

//+------------------------------------------------------------------+
//| TELEGRAM REMOTE CONTROL FUNCTIONS                               |
//+------------------------------------------------------------------+

//--- Read command file — Telegram bot writes commands here
void ReadCommandFile() {
   string cmdFile = "SNP_Command.txt";
   if(!FileIsExist(cmdFile, FILE_COMMON)) return;

   int fh = FileOpen(cmdFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return;

   string cmd = "";
   string arg = "";
   while(!FileIsEnding(fh)) {
      string line = FileReadString(fh);
      if(StringFind(line, "CMD=")    == 0) cmd = StringSubstr(line, 4);
      if(StringFind(line, "ARG=")    == 0) arg = StringSubstr(line, 4);
   }
   FileClose(fh);
   FileDelete(cmdFile, FILE_COMMON);

   if(cmd == "") return;

   // Execute command
   if(cmd == "CLOSE_ALL") {
      CloseAllTrades("Telegram command: " + arg);
      g_RemoteChangeLog = "Closed all trades via Telegram";
   }
   else if(cmd == "PAUSE") {
      g_TradingPaused   = true;
      g_RemoteChangeLog = "Trading PAUSED via Telegram";
   }
   else if(cmd == "RESUME") {
      g_TradingPaused   = false;
      g_RemoteChangeLog = "Trading RESUMED via Telegram";
   }
   else if(cmd == "SET_PRIMARY_SCORE") {
      int val = (int)StringToInteger(arg);
      if(val >= 5 && val <= 20) {
         g_DynPrimaryScore = val;
         g_RemoteChangeLog = StringFormat("MinPrimaryScore set to %d via Telegram", val);
      }
   }
   else if(cmd == "SET_FALLBACK_SCORE") {
      int val = (int)StringToInteger(arg);
      if(val >= 5 && val <= 22) {
         g_DynFallbackScore = val;
         g_RemoteChangeLog = StringFormat("MinFallbackScore set to %d via Telegram", val);
      }
   }
   else if(cmd == "SAVE_LEARNING") {
      SaveLearningData();
      g_RemoteChangeLog = "Learning data saved via Telegram";
   }

   // Write acknowledgement file for Telegram bot to confirm
   int af = FileOpen("SNP_CmdAck.txt", FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(af != INVALID_HANDLE) {
      FileWriteString(af, StringFormat("ACK=%s\nRESULT=%s\n", cmd, g_RemoteChangeLog));
      FileClose(af);
   }
}

//--- Read settings override file — Telegram bot writes parameter changes
void ReadSettingsOverride() {
   string setFile = "SNP_Settings.txt";
   if(!FileIsExist(setFile, FILE_COMMON)) return;

   int fh = FileOpen(setFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return;

   string changes = "";
   while(!FileIsEnding(fh)) {
      string line = FileReadString(fh);
      string parts[];
      if(StringSplit(line, '=', parts) < 2) continue;
      string key = parts[0];
      string val = parts[1];

      if(key == "MinPrimaryScore")  { g_DynPrimaryScore  = (int)StringToInteger(val); changes += "PrimaryScore=" + val + " "; }
      if(key == "MinFallbackScore") { g_DynFallbackScore = (int)StringToInteger(val); changes += "FallbackScore=" + val + " "; }
      if(key == "TradingPaused")    { g_TradingPaused    = (val == "true");            changes += "Paused=" + val + " "; }
   }
   FileClose(fh);
   FileDelete(setFile, FILE_COMMON);

   if(changes != "")
      g_RemoteChangeLog = "Settings updated: " + changes;
}

//--- Write status file every 30 seconds — Telegram bot reads this for /status
void WriteStatusFile() {
   if(TimeCurrent() - g_LastStatusWrite < 30) return;
   g_LastStatusWrite = TimeCurrent();

   int fh = FileOpen("SNP_Status.txt", FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int phtH = (dt.hour + 8) % 24;

   FileWriteString(fh, StringFormat("time=%02d:%02d PHT\n", phtH, dt.min));
   FileWriteString(fh, StringFormat("balance=%.2f\n",    AccountInfoDouble(ACCOUNT_BALANCE)));
   FileWriteString(fh, StringFormat("equity=%.2f\n",     AccountInfoDouble(ACCOUNT_EQUITY)));
   FileWriteString(fh, StringFormat("daily_pnl=%+.2f\n", g_DailyPnL));
   FileWriteString(fh, StringFormat("weekly_pnl=%+.2f\n",g_WeeklyPnL));
   FileWriteString(fh, StringFormat("drawdown=%.2f\n",   g_CurrentDrawdown));
   int openNowSt  = CountOpenTrades();
   int curScoreSt = g_UseFallback ? g_FallbackScore : g_PrimaryScore;
   int maxEntSt   = GetMaxEntriesForScore(curScoreSt);
   FileWriteString(fh, StringFormat("open_trades=%d\n",     openNowSt));
   FileWriteString(fh, StringFormat("max_entries=%d\n",     maxEntSt));
   FileWriteString(fh, StringFormat("scaled_score=%d\n",    curScoreSt));
   FileWriteString(fh, StringFormat("daily_trades=%d/%d\n", g_DailyTradeCount, MaxDailyTrades));
   FileWriteString(fh, StringFormat("session=%s\n",      g_Session));
   FileWriteString(fh, StringFormat("primary_score=%d\n",   g_PrimaryScore));
   FileWriteString(fh, StringFormat("fallback_score=%d\n",  g_FallbackScore));
   FileWriteString(fh, StringFormat("tertiary_score=%d\n",  g_TertiaryScore));
   FileWriteString(fh, StringFormat("paused=%s\n",       g_TradingPaused ? "true" : "false"));
   FileWriteString(fh, StringFormat("gate=%s\n",         IsTradingAllowed() ? "OPEN" : "CLOSED"));
   FileWriteString(fh, StringFormat("block_reason=%s\n", g_BlockReason));
   FileWriteString(fh, StringFormat("news=%s\n",         g_NewsBlocked ? "BLOCKED" : "Clear"));
   FileWriteString(fh, StringFormat("dxy=%s\n",          g_DXY_Status));
   FileWriteString(fh, StringFormat("killzone=%s\n",     g_M15.killzoneName != "" ? g_M15.killzoneName : "Outside KZ"));
   FileWriteString(fh, StringFormat("po3=%s\n",          g_M15.po3Phase));
   FileWriteString(fh, StringFormat("smt=%s\n",          g_SMTDivergence ? g_SMTType : "None"));
   FileWriteString(fh, StringFormat("ict_macro=%s\n",    g_M15.inICTMacro ? g_M15.macroName : "No"));
   FileWriteString(fh, StringFormat("recommendation=%s\n", g_Recommendation));
   FileWriteString(fh, StringFormat("total_trades=%d\n", g_TotalTrades));
   FileWriteString(fh, StringFormat("win_rate=%.1f\n",   GetWinRate()));
   FileWriteString(fh, StringFormat("profit_factor=%.2f\n", GetProfitFactor()));
   FileWriteString(fh, StringFormat("last_result=%s\n",  g_LastTradeResult));
   FileWriteString(fh, StringFormat("prim_threshold=%d\n", g_DynPrimaryScore));
   FileWriteString(fh, StringFormat("fall_threshold=%d\n", g_DynFallbackScore));
   FileWriteString(fh, StringFormat("remote_change=%s\n", g_RemoteChangeLog));

   // Open trade details
   for(int t = 0; t < ArraySize(g_Trades) && t < 3; t++) {
      string dir = g_Trades[t].isBuy ? "BUY" : "SELL";
      double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
      double currentPrice = g_Trades[t].isBuy ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double floatPnL = g_Trades[t].isBuy ?
                        (currentPrice - g_Trades[t].entryPrice) / pip :
                        (g_Trades[t].entryPrice - currentPrice) / pip;
      FileWriteString(fh, StringFormat("trade_%d=#%d %s Entry:%.2f SL:%.2f FloatPips:%.1f BE:%s\n",
         t, g_Trades[t].ticket, dir,
         g_Trades[t].entryPrice, g_Trades[t].initialSL,
         floatPnL,
         g_Trades[t].breakEvenDone ? "Done" : "Wait"));
   }

   FileClose(fh);
}

//+------------------------------------------------------------------+
//| CLAUDE AI BRIDGE FUNCTIONS                                      |
//+------------------------------------------------------------------+

//--- Write signal file for Claude to read
void WriteBridgeSignal(bool isBuy, int score, string strategy,
                       double entry, double sl, double tp1, double tp2,
                       double lots, double riskPct) {
   int fh = FileOpen(BridgeSignalFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) {
      g_BridgeStatus = "Bridge ERROR: Cannot write signal file";
      return;
   }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int phtH = (dt.hour + 8) % 24;

   FileWriteString(fh, "XAUUSD_SNIPER_SIGNAL\n");
   FileWriteString(fh, StringFormat("time=%s PHT %02d:%02d\n",
      TimeToString(TimeCurrent(), TIME_DATE), phtH, dt.min));
   FileWriteString(fh, StringFormat("strategy=%s\n",    strategy));
   FileWriteString(fh, StringFormat("direction=%s\n",   isBuy ? "BUY" : "SELL"));
   FileWriteString(fh, StringFormat("score=%d/60\n",    score));
   FileWriteString(fh, StringFormat("session=%s\n",     g_Session));

   // H4 context
   FileWriteString(fh, StringFormat("h4_bias=%s\n",     g_H4.bullish ? "BULLISH" : "BEARISH"));
   FileWriteString(fh, StringFormat("h4_extbos=%s\n",   g_H4.hasExternalBOS  ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h4_mss=%s\n",      g_H4.hasMSS          ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h4_freshob=%s\n",  g_H4.hasFreshOB      ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h4_ob_status=%s\n",g_H4.obStatus));
   FileWriteString(fh, StringFormat("h4_atsr=%s\n",     g_H4.atKeySR         ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h4_zone=%s\n",     g_H4.inDiscount ? "Discount" :
                                                         g_H4.inPremium  ? "Premium"  : "Equilibrium"));
   FileWriteString(fh, StringFormat("h4_weekly=%.2f/%.2f\n", g_H4.weeklyHigh, g_H4.weeklyLow));

   // H1 context
   FileWriteString(fh, StringFormat("h1_bias=%s\n",     g_H1.bullish ? "BULLISH" : "BEARISH"));
   FileWriteString(fh, StringFormat("h1_choch=%s\n",    g_H1.hasCHoCH        ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h1_mss=%s\n",      g_H1.hasMSS          ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h1_freshob=%s\n",  g_H1.hasFreshOB      ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h1_fvgopen=%s\n",  g_H1.hasFVGOpen      ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h1_ote=%s\n",      g_H1.inOTE           ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h1_sweep=%s\n",    g_H1.hasLiqSweep     ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("h1_displacement=%s\n", g_H1.hasDisplacement ? "YES" : "NO"));

   // M15 context
   FileWriteString(fh, StringFormat("m15_bias=%s\n",    g_M15.bullish ? "BULLISH" : "BEARISH"));
   FileWriteString(fh, StringFormat("m15_sweep=%s\n",   g_M15.hasLiqSweep    ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("m15_choch=%s\n",   g_M15.hasCHoCH       ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("m15_mss=%s\n",     g_M15.hasMSS         ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("m15_freshob=%s\n", g_M15.hasFreshOB     ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("m15_fvgopen=%s\n", g_M15.hasFVGOpen     ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("m15_judas=%s\n",   g_M15.isJudasSwing   ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("m15_silver=%s\n",  g_M15.inSilverBullet ? "YES" : "NO"));

   // ICT Advanced
   FileWriteString(fh, StringFormat("killzone=%s\n",    g_M15.killzoneName != "" ? g_M15.killzoneName : "Outside KZ"));
   FileWriteString(fh, StringFormat("ict_macro=%s\n",   g_M15.inICTMacro ? g_M15.macroName : "No"));
   FileWriteString(fh, StringFormat("po3_phase=%s\n",   g_M15.po3Phase));
   FileWriteString(fh, StringFormat("midnight_open=%.2f|near:%s\n", g_M15.midnightOpen,
                                    g_M15.nearMidnightOpen ? "YES" : "NO"));
   FileWriteString(fh, StringFormat("ndog=%s\n",        g_H1.hasNDOG ? StringFormat("YES [%.2f-%.2f]",
                                    g_H1.ndogLow, g_H1.ndogHigh) : "No"));
   FileWriteString(fh, StringFormat("nwog=%s\n",        g_H4.hasNWOG ? StringFormat("YES [%.2f-%.2f]",
                                    g_H4.nwogLow, g_H4.nwogHigh) : "No"));
   FileWriteString(fh, StringFormat("ipda_level=%s\n",  g_H4.atIPDALevel ? "YES" : "No"));
   FileWriteString(fh, StringFormat("bpr=%s\n",         g_H1.hasBPR ? StringFormat("YES [%.2f-%.2f]",
                                    g_H1.bprLow, g_H1.bprHigh) : "No"));
   FileWriteString(fh, StringFormat("ce_level=%s\n",    g_M15.atCE ? StringFormat("YES (%.2f)", g_M15.ceLevel) : "No"));
   FileWriteString(fh, StringFormat("smt=%s\n",         g_SMTDivergence ? g_SMTType : "None"));

   // Filters
   FileWriteString(fh, StringFormat("dxy_status=%s\n",  g_DXY_Status));
   FileWriteString(fh, StringFormat("candle=%s\n",      g_CandlePattern));
   FileWriteString(fh, StringFormat("news=%s\n",        g_NewsBlocked ? "BLOCKED" : "Clear"));

   // Trade levels
   FileWriteString(fh, StringFormat("entry=%.2f\n",     entry));
   FileWriteString(fh, StringFormat("sl=%.2f\n",        sl));
   FileWriteString(fh, StringFormat("tp1=%.2f\n",       tp1));
   FileWriteString(fh, StringFormat("tp2=%.2f\n",       tp2));
   FileWriteString(fh, StringFormat("sl_pips=%.1f\n",
      MathAbs(entry - sl) / (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10)));
   FileWriteString(fh, StringFormat("rr=1:%.1f\n",      TP2_RR));
   FileWriteString(fh, StringFormat("lots=%.2f\n",      lots));
   FileWriteString(fh, StringFormat("risk_pct=%.1f\n",  riskPct));

   // Account context
   FileWriteString(fh, StringFormat("balance=%.2f\n",   AccountInfoDouble(ACCOUNT_BALANCE)));
   FileWriteString(fh, StringFormat("equity=%.2f\n",    AccountInfoDouble(ACCOUNT_EQUITY)));
   FileWriteString(fh, StringFormat("daily_pnl=%+.2f%%\n", g_DailyPnL));
   FileWriteString(fh, StringFormat("daily_trades=%d/%d\n", g_DailyTradeCount, MaxDailyTrades));
   FileWriteString(fh, StringFormat("drawdown=%.2f%%\n", g_CurrentDrawdown));

   // Learning context
   if(UseAdaptiveLearning && g_PrimaryTrades + g_FallbackTrades >= MinTradesForAdjust) {
      double primWR = g_PrimaryTrades  > 0 ? (double)g_PrimaryWins  / g_PrimaryTrades  * 100.0 : 0;
      double fallWR = g_FallbackTrades > 0 ? (double)g_FallbackWins / g_FallbackTrades * 100.0 : 0;
      FileWriteString(fh, StringFormat("primary_winrate=%.1f%%\n", primWR));
      FileWriteString(fh, StringFormat("fallback_winrate=%.1f%%\n", fallWR));
   }

   FileWriteString(fh, "END_SIGNAL\n");
   FileClose(fh);

   g_BridgeWriteTime = TimeCurrent();
   g_BridgeState     = BRIDGE_WAITING;
   g_BridgeStatus    = StringFormat("Bridge: Signal sent — waiting for Claude (%ds timeout)...",
                                    BridgeTimeoutSec);
}

//--- Read and parse Claude's response file
bool ReadBridgeResponse() {
   if(!FileIsExist(BridgeRespFile, FILE_COMMON)) return false;

   int fh = FileOpen(BridgeRespFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return false;

   g_BridgeVerdict = "";
   g_BridgeReason  = "";
   g_BridgeSLStr   = "";

   while(!FileIsEnding(fh)) {
      string line = FileReadString(fh);
      if(StringFind(line, "VERDICT=")   == 0) g_BridgeVerdict = StringSubstr(line, 8);
      if(StringFind(line, "REASON=")    == 0) g_BridgeReason  = StringSubstr(line, 7);
      if(StringFind(line, "ADJUST_SL=") == 0) g_BridgeSLStr   = StringSubstr(line, 10);
   }
   FileClose(fh);

   // Delete response file so it does not trigger again
   FileDelete(BridgeRespFile, FILE_COMMON);

   if(g_BridgeVerdict == "TAKE" || g_BridgeVerdict == "ADJUST_SL") {
      g_BridgeState  = BRIDGE_APPROVED;
      g_BridgeStatus = StringFormat("Claude: APPROVED — %s", g_BridgeReason);
   } else {
      g_BridgeState  = BRIDGE_REJECTED;
      g_BridgeStatus = StringFormat("Claude: SKIP — %s", g_BridgeReason);
   }
   return true;
}

//--- Write trade result file so Claude can learn
void WriteBridgeResult(ulong ticket, bool wasWin, double profit,
                       string strategy, int score) {
   if(!UseBridge) return;
   int fh = FileOpen(BridgeResultFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return;

   FileWriteString(fh, "XAUUSD_SNIPER_RESULT\n");
   FileWriteString(fh, StringFormat("ticket=%d\n",     ticket));
   FileWriteString(fh, StringFormat("result=%s\n",     wasWin ? "WIN" : "LOSS"));
   FileWriteString(fh, StringFormat("profit=%.2f\n",   profit));
   FileWriteString(fh, StringFormat("strategy=%s\n",   strategy));
   FileWriteString(fh, StringFormat("score=%d\n",      score));
   FileWriteString(fh, StringFormat("session=%s\n",    g_Session));
   FileWriteString(fh, StringFormat("balance=%.2f\n",  AccountInfoDouble(ACCOUNT_BALANCE)));
   FileWriteString(fh, StringFormat("time=%s\n",       TimeToString(TimeCurrent())));
   FileWriteString(fh, "END_RESULT\n");
   FileClose(fh);
}

//--- Check bridge timeout — proceed or abort based on settings
void CheckBridgeTimeout() {
   if(g_BridgeState != BRIDGE_WAITING) return;
   int elapsed = (int)(TimeCurrent() - g_BridgeWriteTime);
   if(elapsed < BridgeTimeoutSec) return;

   // Timed out
   FileDelete(BridgeSignalFile, FILE_COMMON);
   if(BridgeMustApprove) {
      g_BridgeState  = BRIDGE_REJECTED;
      g_BridgeStatus = StringFormat("Bridge: Timeout after %ds — trade SKIPPED (BridgeMustApprove=true)",
                                    BridgeTimeoutSec);
   } else {
      g_BridgeState  = BRIDGE_APPROVED;
      g_BridgeStatus = StringFormat("Bridge: Timeout after %ds — proceeding without Claude",
                                    BridgeTimeoutSec);
   }
}

//+------------------------------------------------------------------+
//| ADAPTIVE LEARNING FUNCTIONS                                     |
//+------------------------------------------------------------------+

//--- Capture confluence state at the moment a trade is entered
TradeSnapshot CaptureSnapshot(ulong ticket, string strategy) {
   TradeSnapshot snap;
   snap.ticket   = ticket;
   snap.strategy = strategy;

   // Capture all 20 confluence flags
   snap.confluences[0]  = g_H4.hasExternalBOS;
   snap.confluences[1]  = g_H4.hasMSS;
   snap.confluences[2]  = g_H4.hasFreshOB;
   snap.confluences[3]  = g_H4.atKeySR;
   snap.confluences[4]  = (g_H4.hasEqualHighs || g_H4.hasEqualLows);
   snap.confluences[5]  = g_H1.hasCHoCH;
   snap.confluences[6]  = g_H1.hasMSS;
   snap.confluences[7]  = (g_H1.hasFreshOB && g_H1.hasLiqSweep);
   snap.confluences[8]  = g_H1.hasFVGOpen;
   snap.confluences[9]  = g_H1.inOTE;
   snap.confluences[10] = g_H1.hasDisplacement;
   snap.confluences[11] = g_M15.hasLiqSweep;
   snap.confluences[12] = (g_M15.hasCHoCH || g_M15.hasMSS);
   snap.confluences[13] = g_M15.hasFVGOpen;
   snap.confluences[14] = g_M15.hasFreshOB;
   snap.confluences[15] = g_M15.isJudasSwing;
   snap.confluences[16] = g_M15.inSilverBullet;
   snap.confluences[17] = g_DXY_Available ? !g_DXY_Bullish : false;
   snap.confluences[18] = g_CandleConfirmed;
   snap.confluences[19] = (GetSessionIndex() == SESS_LONDON_OPEN ||
                           GetSessionIndex() == SESS_NY_OPEN);

   snap.sessionIdx = GetSessionIndex();

   return snap;
}

//--- Store snapshot alongside trade
void RegisterSnapshot(ulong ticket, string strategy) {
   int idx = ArraySize(g_Snapshots);
   ArrayResize(g_Snapshots, idx + 1);
   g_Snapshots[idx] = CaptureSnapshot(ticket, strategy);
}

//--- Find snapshot by ticket
int FindSnapshot(ulong ticket) {
   for(int i = 0; i < ArraySize(g_Snapshots); i++)
      if(g_Snapshots[i].ticket == ticket) return i;
   return -1;
}

//--- Remove snapshot by index
void RemoveSnapshot(int idx) {
   int n = ArraySize(g_Snapshots);
   for(int i = idx; i < n - 1; i++)
      g_Snapshots[i] = g_Snapshots[i + 1];
   ArrayResize(g_Snapshots, n - 1);
}

//--- Update confluence and session stats after a trade closes
void UpdateLearningStats(ulong ticket, bool wasWin, string strategy) {
   if(!UseAdaptiveLearning) return;

   int snapIdx = FindSnapshot(ticket);
   if(snapIdx < 0) return;

   TradeSnapshot snap = g_Snapshots[snapIdx];

   // Update confluence stats
   for(int i = 0; i < CONFLUENCE_COUNT; i++) {
      if(snap.confluences[i]) {
         g_ConfStats[i].presentTotal++;
         if(wasWin) g_ConfStats[i].presentWins++;
      } else {
         g_ConfStats[i].absentTotal++;
         if(wasWin) g_ConfStats[i].absentWins++;
      }
   }

   // Update session stats
   int si = snap.sessionIdx;
   g_SessStats[si].total++;
   if(wasWin) g_SessStats[si].wins++;

   // Check session suspension
   if(SuspendBadSessions && g_SessStats[si].total >= MinTradesForAdjust) {
      double wr = (double)g_SessStats[si].wins / g_SessStats[si].total * 100.0;
      g_SessStats[si].suspended = (wr < MinSessionWinRate);
   }

   // Update per-strategy win counters
   if(strategy == "PRIMARY") {
      if(wasWin) g_PrimaryWins++;
   } else if(strategy == "FALLBACK") {
      if(wasWin) g_FallbackWins++;
   } else {
      if(wasWin) g_TertiaryWins++;
   }

   g_BatchTradeCount++;

   // Threshold adjustment after each batch
   if(g_BatchTradeCount >= LearningBatchSize)
      AdjustThresholds();

   // Save updated data
   RemoveSnapshot(snapIdx);
   if(!g_IsTesting) SaveLearningData();
}

//--- Self-adjust score thresholds based on recent performance
void AdjustThresholds() {
   g_BatchTradeCount = 0;

   // Primary threshold adjustment
   if(g_PrimaryTrades >= MinTradesForAdjust) {
      double primWR = (double)g_PrimaryWins / g_PrimaryTrades * 100.0;
      if(primWR < 40.0 && g_DynPrimaryScore < MinPrimaryScore + 5)
         g_DynPrimaryScore++;   // Losing too much — raise the bar
      else if(primWR > 70.0 && g_DynPrimaryScore > MinPrimaryScore - 2)
         g_DynPrimaryScore--;   // Winning well — can afford slightly lower bar
   }

   // Fallback threshold adjustment
   if(g_FallbackTrades >= MinTradesForAdjust) {
      double fallWR = (double)g_FallbackWins / g_FallbackTrades * 100.0;
      if(fallWR < 40.0 && g_DynFallbackScore < MinFallbackScore + 5)
         g_DynFallbackScore++;
      else if(fallWR > 70.0 && g_DynFallbackScore > MinFallbackScore - 2)
         g_DynFallbackScore--;
   }

   // Tertiary threshold adjustment
   if(g_TertiaryTrades >= MinTradesForAdjust) {
      double tertWR = (double)g_TertiaryWins / g_TertiaryTrades * 100.0;
      if(tertWR < 40.0 && g_DynTertiaryScore < MinTertiaryScore + 5)
         g_DynTertiaryScore++;
      else if(tertWR > 70.0 && g_DynTertiaryScore > MinTertiaryScore - 2)
         g_DynTertiaryScore--;
   }

   // Clamp to safe bounds
   g_DynPrimaryScore  = MathMax(5,  MathMin(20, g_DynPrimaryScore));
   g_DynFallbackScore = MathMax(7,  MathMin(22, g_DynFallbackScore));
   g_DynTertiaryScore = MathMax(9,  MathMin(25, g_DynTertiaryScore));

   // Build status string
   double primWR  = g_PrimaryTrades  > 0 ? (double)g_PrimaryWins  / g_PrimaryTrades  * 100.0 : 0;
   double fallWR  = g_FallbackTrades > 0 ? (double)g_FallbackWins / g_FallbackTrades * 100.0 : 0;
   g_LearnStatus = StringFormat(
      "Primary WR: %.1f%%  Score→%d  |  Fallback WR: %.1f%%  Score→%d  |  Trades reviewed: %d",
      primWR, g_DynPrimaryScore, fallWR, g_DynFallbackScore,
      g_PrimaryTrades + g_FallbackTrades);
}

//--- Get confluence win rate when present (returns -1 if no data)
double ConfluenceWinRate(int idx) {
   if(g_ConfStats[idx].presentTotal < 3) return -1;
   return (double)g_ConfStats[idx].presentWins / g_ConfStats[idx].presentTotal * 100.0;
}

//--- Get confluence value score (win rate present minus win rate absent)
double ConfluenceValue(int idx) {
   double wrPresent = g_ConfStats[idx].presentTotal >= 3 ?
                      (double)g_ConfStats[idx].presentWins / g_ConfStats[idx].presentTotal * 100.0 : 50.0;
   double wrAbsent  = g_ConfStats[idx].absentTotal  >= 3 ?
                      (double)g_ConfStats[idx].absentWins  / g_ConfStats[idx].absentTotal  * 100.0 : 50.0;
   return wrPresent - wrAbsent;
}

//--- Check if current session is suspended by learning system
bool IsSessionSuspended() {
   if(!UseAdaptiveLearning || !SuspendBadSessions) return false;
   int si = GetSessionIndex();
   return g_SessStats[si].suspended;
}

//--- Save all learning data to file
void SaveLearningData() {
   int fh = FileOpen(LearningFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return;

   // Header
   FileWriteString(fh, "XAUUSD_SNIPER_LEARNING_V1\n");

   // Dynamic thresholds
   FileWriteString(fh, StringFormat("THRESH,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
      g_DynPrimaryScore, g_DynFallbackScore, g_DynTertiaryScore,
      g_PrimaryTrades,   g_PrimaryWins,
      g_FallbackTrades,  g_FallbackWins,
      g_TertiaryTrades,  g_TertiaryWins));

   // Confluence stats
   for(int i = 0; i < CONFLUENCE_COUNT; i++) {
      FileWriteString(fh, StringFormat("CONF,%d,%d,%d,%d,%d\n",
         i,
         g_ConfStats[i].presentWins,  g_ConfStats[i].presentTotal,
         g_ConfStats[i].absentWins,   g_ConfStats[i].absentTotal));
   }

   // Session stats
   for(int i = 0; i < SESSION_COUNT; i++) {
      FileWriteString(fh, StringFormat("SESS,%d,%d,%d,%d\n",
         i, g_SessStats[i].wins, g_SessStats[i].total,
         g_SessStats[i].suspended ? 1 : 0));
   }

   FileClose(fh);
}

//--- Load learning data from file
void LoadLearningData() {
   if(!FileIsExist(LearningFileName, FILE_COMMON)) return;

   int fh = FileOpen(LearningFileName, FILE_READ|FILE_TXT|FILE_COMMON);
   if(fh == INVALID_HANDLE) return;

   // Check header
   string header = FileReadString(fh);
   if(StringFind(header, "XAUUSD_SNIPER_LEARNING") < 0) { FileClose(fh); return; }

   while(!FileIsEnding(fh)) {
      string line = FileReadString(fh);
      if(StringLen(line) == 0) continue;

      string parts[];
      int n = StringSplit(line, ',', parts);
      if(n < 2) continue;

      string tag = parts[0];

      if(tag == "THRESH" && n >= 7) {
         g_DynPrimaryScore   = (int)StringToInteger(parts[1]);
         g_DynFallbackScore  = (int)StringToInteger(parts[2]);
         if(n >= 10) g_DynTertiaryScore = (int)StringToInteger(parts[3]);
         g_PrimaryTrades     = (int)StringToInteger(n >= 10 ? parts[4] : parts[3]);
         g_PrimaryWins       = (int)StringToInteger(n >= 10 ? parts[5] : parts[4]);
         g_FallbackTrades    = (int)StringToInteger(n >= 10 ? parts[6] : parts[5]);
         g_FallbackWins      = (int)StringToInteger(n >= 10 ? parts[7] : parts[6]);
         if(n >= 10) { g_TertiaryTrades = (int)StringToInteger(parts[8]);
                       g_TertiaryWins   = (int)StringToInteger(parts[9]); }
      }
      else if(tag == "CONF" && n >= 6) {
         int idx = (int)StringToInteger(parts[1]);
         if(idx >= 0 && idx < CONFLUENCE_COUNT) {
            g_ConfStats[idx].presentWins  = (int)StringToInteger(parts[2]);
            g_ConfStats[idx].presentTotal = (int)StringToInteger(parts[3]);
            g_ConfStats[idx].absentWins   = (int)StringToInteger(parts[4]);
            g_ConfStats[idx].absentTotal  = (int)StringToInteger(parts[5]);
         }
      }
      else if(tag == "SESS" && n >= 5) {
         int idx = (int)StringToInteger(parts[1]);
         if(idx >= 0 && idx < SESSION_COUNT) {
            g_SessStats[idx].wins      = (int)StringToInteger(parts[2]);
            g_SessStats[idx].total     = (int)StringToInteger(parts[3]);
            g_SessStats[idx].suspended = (StringToInteger(parts[4]) == 1);
         }
      }
   }

   FileClose(fh);
   g_LearnStatus = StringFormat("Learning data loaded — %d primary, %d fallback trades",
                                g_PrimaryTrades, g_FallbackTrades);
}

//+------------------------------------------------------------------+
//| Build trade recommendation                                       |
//+------------------------------------------------------------------+
string GetRecommendation() {
   // Check master gate first
   if(!IsTradingAllowed())
      return StringFormat("BLOCKED: %s", g_BlockReason);

   SessionParams rsp    = GetSessionParams();
   int           rsi    = GetSessionIndex();
   bool isAsianRec      = (rsi == SESS_ASIAN);
   bool isPremarketRec  = (rsi == SESS_PREMARKET);
   bool inTradeSession  = (rsi != SESS_OTHER) &&
                          !(isAsianRec    && !TradeAsianSession) &&
                          !(isPremarketRec && !TradePremarket)   &&
                          (rsp.maxNewTrades > 0);

   if(!inTradeSession)
      return "NOT IN TRADING SESSION — PREPARE ONLY";

   int effPrim = MathMax(UseAdaptiveLearning ? g_DynPrimaryScore  : MinPrimaryScore,  rsp.minScore);
   int effFall = MathMax(UseAdaptiveLearning ? g_DynFallbackScore : MinFallbackScore, rsp.minScore);
   int effTert = MathMax(UseAdaptiveLearning ? g_DynTertiaryScore : MinTertiaryScore, rsp.minScore);

   // Check session suspension
   if(IsSessionSuspended())
      return StringFormat("SESSION SUSPENDED by learning system — %s below %.0f%% win rate",
                          g_Session, MinSessionWinRate);

   int openNow = CountOpenTrades();

   string asianTag    = " " + rsp.tag;
   double actPrimRisk = rsp.risk;
   double actFallRisk = rsp.risk;
   double actTertRisk = rsp.risk;

   // Tier 1 — Primary: H4 → H1 → M15
   if(g_PrimaryScore >= effPrim) {
      string dir    = g_H4.bullish ? "BUY" : "SELL";
      double lots   = CalcLotSize(actPrimRisk, 15.0);
      g_LastLotSize = lots;
      int    maxEnt = GetMaxEntriesForScore(g_PrimaryScore);
      return StringFormat("▶ PRIMARY  (H4→H1→M15)%s: %s | Score %d/60 | Risk %.1f%% | Lots %.2f | %d/%d trades",
                          asianTag, dir, g_PrimaryScore, actPrimRisk, lots, openNow, maxEnt);
   }

   // Tier 2 — Fallback: H1 → M15 → M5
   if(g_FallbackScore >= effFall) {
      string dir    = g_H1.bullish ? "BUY" : "SELL";
      double lots   = CalcLotSize(actFallRisk, 10.0);
      g_LastLotSize = lots;
      int    maxEnt = GetMaxEntriesForScore(g_FallbackScore);
      return StringFormat("▶ FALLBACK (H1→M15→M5)%s: %s | Score %d/60 | Risk %.1f%% | Lots %.2f | %d/%d trades",
                          asianTag, dir, g_FallbackScore, actFallRisk, lots, openNow, maxEnt);
   }

   // Tier 3 — Tertiary scalp: M15 → M5 → M1
   if(g_TertiaryScore >= effTert) {
      string dir    = g_M15.bullish ? "BUY" : "SELL";
      double lots   = CalcLotSize(actTertRisk, 7.0);
      g_LastLotSize = lots;
      int    maxEnt = GetMaxEntriesForScore(g_TertiaryScore);
      return StringFormat("▶ SCALP    (M15→M5→M1)%s: %s | Score %d/60 | Risk %.1f%% | Lots %.2f | %d/%d trades",
                          asianTag, dir, g_TertiaryScore, actTertRisk, lots, openNow, maxEnt);
   }

   // No tier ready
   string scaleHint = UseScaledEntries ?
      StringFormat("  [Entries: score %d=1, %d=2, %d=3]", ScaledScore1, ScaledScore2, ScaledScore3) : "";
   return StringFormat("NO TRADE — P:%d/60(≥%d) | F:%d/60(≥%d) | T:%d/60(≥%d)%s",
                       g_PrimaryScore, effPrim,
                       g_FallbackScore, effFall,
                       g_TertiaryScore, effTert, scaleHint);
}

//+------------------------------------------------------------------+
//|  WEEKLY & MONTHLY TRACKING                                      |
//+------------------------------------------------------------------+

void ResetWeeklyTracking() {
   g_WeekStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   g_WeeklyPnL         = 0;
   g_WeeklyLossHit     = false;
   g_WeeklyProfitHit   = false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   // Find Monday of current week
   int wday = dt.day_of_week == 0 ? 6 : dt.day_of_week - 1;
   // Snap to Monday midnight PHT (UTC+8) = Sunday 16:00 UTC
   datetime nowUTC  = TimeCurrent();
   g_WeekStart = nowUTC - wday * 86400 -
                 (dt.hour * 3600 + dt.min * 60 + dt.sec) + 8 * 3600;
   // If offset pushed past today, go back one day
   if(g_WeekStart > nowUTC) g_WeekStart -= 86400;
}

void ResetMonthlyTracking() {
   g_MonthStartBalance  = AccountInfoDouble(ACCOUNT_BALANCE);
   g_MonthlyPnL         = 0;
   g_MonthlyLossHit     = false;
   g_MonthlyProfitHit   = false;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_MonthStart = StringToTime(StringFormat("%04d.%02d.01 00:00",
                                            dt.year, dt.mon));
}

void CheckNewWeek() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int wday    = dt.day_of_week == 0 ? 6 : dt.day_of_week - 1;
   datetime nowUTC2 = TimeCurrent();
   datetime monDay = nowUTC2 - wday * 86400 -
                     (dt.hour * 3600 + dt.min * 60 + dt.sec) + 8 * 3600;
   if(monDay > nowUTC2) monDay -= 86400;
   if(monDay != g_WeekStart) {
      g_WeekStart       = monDay;
      g_SessionCloseDone = false;
      g_FridayCloseDone  = false;
      ResetWeeklyTracking();
   }
}

void CheckNewMonth() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime monthStart = StringToTime(StringFormat("%04d.%02d.01 00:00",
                                                   dt.year, dt.mon));
   if(monthStart != g_MonthStart)
      ResetMonthlyTracking();
}

void UpdateWeeklyPnL() {
   if(g_WeekStartBalance <= 0) return;
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   g_WeeklyPnL    = ((equity - g_WeekStartBalance) / g_WeekStartBalance) * 100.0;

   if(!g_WeeklyLossHit && g_WeeklyPnL <= -WeeklyLossLimit) {
      g_WeeklyLossHit = true;
      string msg = StringFormat("Weekly loss limit hit: %.2f%% — Stopping for the week", g_WeeklyPnL);
      SendDailyLimitNotification(msg);
      CloseAllTrades("Weekly loss limit hit");
   }
   if(!g_WeeklyProfitHit && g_WeeklyPnL >= WeeklyProfitTarget) {
      g_WeeklyProfitHit = true;
      string msg = StringFormat("Weekly profit target hit: +%.2f%% — Well done! Rest now.", g_WeeklyPnL);
      SendDailyLimitNotification(msg);
   }
}

void UpdateMonthlyPnL() {
   if(g_MonthStartBalance <= 0) return;
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   g_MonthlyPnL    = ((equity - g_MonthStartBalance) / g_MonthStartBalance) * 100.0;

   if(!g_MonthlyLossHit && g_MonthlyPnL <= -MonthlyLossLimit) {
      g_MonthlyLossHit = true;
      string msg = StringFormat("Monthly loss limit hit: %.2f%% — Stopping for the month", g_MonthlyPnL);
      SendDailyLimitNotification(msg);
      CloseAllTrades("Monthly loss limit hit");
   }
   if(!g_MonthlyProfitHit && g_MonthlyPnL >= MonthlyProfitTarget) {
      g_MonthlyProfitHit = true;
      string msg = StringFormat("Monthly profit target hit: +%.2f%% — Excellent! Take a break.", g_MonthlyPnL);
      SendDailyLimitNotification(msg);
   }
}

//+------------------------------------------------------------------+
//|  DRAWDOWN PROTECTION                                             |
//+------------------------------------------------------------------+

void UpdateDrawdown() {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

   // Update peak balance
   if(balance > g_PeakBalance) g_PeakBalance = balance;

   // Calculate drawdown from peak
   g_CurrentDrawdown = g_PeakBalance > 0 ?
                       ((g_PeakBalance - equity) / g_PeakBalance) * 100.0 : 0;

   if(!g_DrawdownHit && UseMaxDrawdown && g_CurrentDrawdown >= MaxDrawdownPct) {
      g_DrawdownHit = true;
      string msg = StringFormat("MAX DRAWDOWN HIT: %.2f%% — All trades closed. Stop trading.",
                                g_CurrentDrawdown);
      SendDailyLimitNotification(msg);
      CloseAllTrades("Max drawdown exceeded");
   }
}

//+------------------------------------------------------------------+
//|  SESSION CLOSE & FRIDAY CLOSE                                   |
//+------------------------------------------------------------------+

void CheckSessionClose() {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int phtHour = (dt.hour + 8) % 24;
   bool isFriday = (dt.day_of_week == 5);

   // Friday close
   if(CloseOnFriday && isFriday && phtHour >= FridayCloseHour && !g_FridayCloseDone) {
      CloseAllTrades("Friday close — weekend protection");
      g_FridayCloseDone = true;
      string msg = "Friday close triggered — all trades closed for weekend safety.";
      SendDailyLimitNotification(msg);
   }

   // Session end close (daily at PHT SessionCloseHour)
   if(CloseAtSessionEnd && phtHour >= SessionCloseHour && !g_SessionCloseDone) {
      CloseAllTrades("End of NY session close");
      g_SessionCloseDone = true;
      // Reset flag at start of new trading window
   }
   // Reset session close flag when new session opens (3PM PHT = London open)
   if(phtHour == 15) g_SessionCloseDone = false;
}

//+------------------------------------------------------------------+
//|  CLOSE ALL EA TRADES                                             |
//+------------------------------------------------------------------+

void CloseAllTrades(string reason) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!PositionInfo.SelectByIndex(i)) continue;
      if(PositionInfo.Symbol() != _Symbol)  continue;
      if(PositionInfo.Magic()  != MagicNumber) continue;
      Trade.PositionClose(PositionInfo.Ticket());
   }
   // Also cancel all FVG pending orders — no point leaving limits open after session ends
   for(int i = ArraySize(g_FVGPendings) - 1; i >= 0; i--) {
      if(OrderSelect(g_FVGPendings[i].ticket))
         Trade.OrderDelete(g_FVGPendings[i].ticket);
   }
   ArrayResize(g_FVGPendings, 0);
   g_EntryLog = StringFormat("ALL TRADES CLOSED: %s", reason);
}

//+------------------------------------------------------------------+
//|  IDLE TRADE SL TIGHTENING                                       |
//+------------------------------------------------------------------+

void ManageIdleTrades() {
   if(!TightenSLIdle) return;
   double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;

   for(int i = 0; i < PositionsTotal(); i++) {
      if(!PositionInfo.SelectByIndex(i))       continue;
      if(PositionInfo.Symbol() != _Symbol)      continue;
      if(PositionInfo.Magic()  != MagicNumber)  continue;

      ulong  ticket    = PositionInfo.Ticket();
      bool   isBuy     = (PositionInfo.PositionType() == POSITION_TYPE_BUY);
      double entry     = PositionInfo.PriceOpen();
      double currentSL = PositionInfo.StopLoss();
      double currentTP = PositionInfo.TakeProfit();
      double price     = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profit    = isBuy ? (price - entry) : (entry - price);

      // Only tighten if trade has not moved significantly (near breakeven)
      if(MathAbs(profit) > IdleSLTightenPips * pip * 2) continue;

      // Check how long trade has been open using bar count
      datetime openTime = PositionInfo.Time();
      int barsSinceOpen = Bars(_Symbol, TF_M15, openTime, TimeCurrent());
      if(barsSinceOpen < IdleBarLimit) continue;

      // Tighten SL toward price
      double newSL = isBuy  ? currentSL + IdleSLTightenPips * pip
                            : currentSL - IdleSLTightenPips * pip;
      newSL = NormalizeDouble(newSL, _Digits);

      // Never move SL past entry
      if(isBuy  && newSL >= entry) newSL = entry - 2 * pip;
      if(!isBuy && newSL <= entry) newSL = entry + 2 * pip;

      bool improves = isBuy ? (newSL > currentSL) : (newSL < currentSL);
      if(improves)
         Trade.PositionModify(ticket, newSL, currentTP);
   }
}

//+------------------------------------------------------------------+
//|  MASTER GATE — updated to include all new limits                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|  TRADE JOURNAL                                                   |
//+------------------------------------------------------------------+

string GetDailyJournalName() {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return StringFormat("XAUUSD_Sniper_Journal_%04d.%02d.%02d.csv",
                       dt.year, dt.mon, dt.day);
}

void InitJournal() {
   if(!UseJournal) return;
   string todayFile = GetDailyJournalName();
   g_JournalPath = TerminalInfoString(TERMINAL_DATA_PATH) +
                   "\\MQL5\\Files\\" + todayFile;

   // Create today's file with header if it does not exist yet
   if(!FileIsExist(todayFile, FILE_COMMON)) {
      int fh = FileOpen(todayFile, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(fh != INVALID_HANDLE) {
         FileWrite(fh,
            "Date", "Time(PHT)", "Symbol", "Direction", "Strategy",
            "Score", "Entry", "SL", "TP1", "TP2",
            "Lots", "Risk%", "SL_Pips", "Exit", "Profit_USD",
            "Profit%", "RR_Achieved", "Result", "Session",
            "BE_Used", "TP1_Hit", "Trail_Used");
         FileClose(fh);
      }
   }
   // Load stats from existing journal
   LoadJournalStats();
}

void LoadJournalStats() {
   int fh = FileOpen(JournalFileName, FILE_READ|FILE_CSV|FILE_COMMON, ',');
   if(fh == INVALID_HANDLE) return;
   FileReadString(fh); // Skip header line
   while(!FileIsEnding(fh)) {
      string line[22];
      bool valid = true;
      for(int i = 0; i < 22 && !FileIsEnding(fh); i++)
         line[i] = FileReadString(fh);
      if(line[0] == "") continue;
      double profit = StringToDouble(line[14]);
      g_TotalTrades++;
      if(profit >= 0) { g_TotalWins++;   g_TotalProfit += profit; }
      else            { g_TotalLosses++; g_TotalLoss   += MathAbs(profit); }
   }
   FileClose(fh);
}

void JournalWriteTrade(ulong ticket, string strategy, int score,
                       double entry, double sl, double tp1, double tp2,
                       double lots, double riskPct, double slPips,
                       double exitPrice, double profitUSD,
                       bool isBuy, bool beUsed, bool tp1Hit, bool trailUsed) {
   if(!UseJournal) return;
   // Use today's dated file — creates new file automatically each day
   string todayFile = GetDailyJournalName();
   if(!FileIsExist(todayFile, FILE_COMMON)) {
      int fhNew = FileOpen(todayFile, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
      if(fhNew != INVALID_HANDLE) {
         FileWrite(fhNew,
            "Date", "Time(PHT)", "Symbol", "Direction", "Strategy",
            "Score", "Entry", "SL", "TP1", "TP2",
            "Lots", "Risk%", "SL_Pips", "Exit", "Profit_USD",
            "Profit%", "RR_Achieved", "Result", "Session",
            "BE_Used", "TP1_Hit", "Trail_Used");
         FileClose(fhNew);
      }
   }
   int fh = FileOpen(todayFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
   if(fh == INVALID_HANDLE) return;
   FileSeek(fh, 0, SEEK_END);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int phtHour = (dt.hour + 8) % 24;

   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double profitPct = balance > 0 ? (profitUSD / (balance - profitUSD)) * 100.0 : 0;
   double rrAchieved = slPips > 0 ? MathAbs(exitPrice - entry) /
                                    (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10 * slPips) : 0;
   string result   = profitUSD >= 0 ? "WIN" : "LOSS";
   string dir      = isBuy ? "BUY" : "SELL";

   FileWrite(fh,
      TimeToString(TimeCurrent(), TIME_DATE),
      StringFormat("%02d:%02d PHT", phtHour, dt.min),
      _Symbol, dir, strategy,
      IntegerToString(score),
      DoubleToString(entry,  _Digits),
      DoubleToString(sl,     _Digits),
      DoubleToString(tp1,    _Digits),
      DoubleToString(tp2,    _Digits),
      DoubleToString(lots,   2),
      DoubleToString(riskPct, 1),
      DoubleToString(slPips, 1),
      DoubleToString(exitPrice, _Digits),
      DoubleToString(profitUSD, 2),
      DoubleToString(profitPct, 2),
      DoubleToString(rrAchieved, 2),
      result,
      g_Session,
      beUsed    ? "Yes" : "No",
      tp1Hit    ? "Yes" : "No",
      trailUsed ? "Yes" : "No");

   FileClose(fh);

   // Update in-memory stats
   g_TotalTrades++;
   if(profitUSD >= 0) { g_TotalWins++;   g_TotalProfit += profitUSD; }
   else               { g_TotalLosses++; g_TotalLoss   += MathAbs(profitUSD); }

   // Per-session extended stats
   int si = GetSessionIndex();
   if(si >= 0 && si < SESSION_COUNT) {
      if(profitUSD >= 0) g_SessProfit[si] += profitUSD;
      else               g_SessLoss[si]   += MathAbs(profitUSD);
      g_SessPips[si] += profitUSD >= 0 ? rrAchieved * slPips : -(rrAchieved * slPips);
   }

   // Monthly performance tracking
   {
      int n = ArraySize(g_MonthlyPerf);
      int found = -1;
      for(int mi = 0; mi < n; mi++) {
         if(g_MonthlyPerf[mi].year == dt.year && g_MonthlyPerf[mi].month == dt.mon) {
            found = mi; break;
         }
      }
      if(found < 0) {
         ArrayResize(g_MonthlyPerf, n + 1);
         g_MonthlyPerf[n].year  = dt.year;
         g_MonthlyPerf[n].month = dt.mon;
         g_MonthlyPerf[n].wins = g_MonthlyPerf[n].losses = 0;
         g_MonthlyPerf[n].grossProfit = g_MonthlyPerf[n].grossLoss = 0;
         found = n;
      }
      if(profitUSD >= 0) {
         g_MonthlyPerf[found].wins++;
         g_MonthlyPerf[found].grossProfit += profitUSD;
      } else {
         g_MonthlyPerf[found].losses++;
         g_MonthlyPerf[found].grossLoss += MathAbs(profitUSD);
      }
   }
}

double GetProfitFactor() {
   return g_TotalLoss > 0 ? g_TotalProfit / g_TotalLoss : 0;
}

double GetWinRate() {
   return g_TotalTrades > 0 ? (double)g_TotalWins / g_TotalTrades * 100.0 : 0;
}

double GetExpectedPayoff() {
   if(g_TotalTrades == 0) return 0;
   double avgWin  = g_TotalWins   > 0 ? g_TotalProfit / g_TotalWins   : 0;
   double avgLoss = g_TotalLosses > 0 ? g_TotalLoss   / g_TotalLosses : 0;
   double wr      = (double)g_TotalWins / g_TotalTrades;
   return wr * avgWin - (1.0 - wr) * avgLoss;
}

//+------------------------------------------------------------------+
//|  CHART VISUALS                                                   |
//+------------------------------------------------------------------+

void DrawChartVisuals() {
   // Skip if analysis data not ready (e.g. immediately after TF switch)
   if(g_H4.narrative == "" || StringFind(g_H4.narrative, "Loading") >= 0 ||
      StringFind(g_H4.narrative, "Waiting") >= 0) return;

   ObjectsDeleteAll(0, "VIS_");

   if(ShowOB)      DrawOrderBlocks();
   if(ShowFVG)     DrawFVGZones();
   if(ShowSweep)   DrawSweepLines();
   if(ShowBOSArrows || ShowCHoCHArrows) DrawStructureArrows();
   DrawTradeLevelLines();
}

void DrawOrderBlocks() {
   // Draw H4 OB
   if(g_H4.hasFreshOB && g_H4.obHigh > 0)
      DrawBox("VIS_OB_H4", TF_H4, g_H4.obHigh, g_H4.obLow,
              g_H4.bullish ? ColorOB_Bull : ColorOB_Bear, "H4 FreshOB");
   // Draw H1 OB
   if(g_H1.hasFreshOB && g_H1.obHigh > 0)
      DrawBox("VIS_OB_H1", TF_H1, g_H1.obHigh, g_H1.obLow,
              g_H1.bullish ? ColorOB_Bull : ColorOB_Bear, "H1 FreshOB");
   // Draw M15 OB
   if(g_M15.hasFreshOB && g_M15.obHigh > 0)
      DrawBox("VIS_OB_M15", TF_M15, g_M15.obHigh, g_M15.obLow,
              g_M15.bullish ? ColorOB_Bull : ColorOB_Bear, "M15 FreshOB");
   // Draw H4 Breaker Block if present
   if(g_H4.hasBreakerBlock && g_H4.breakerHigh > 0)
      DrawBox("VIS_BB_H4", TF_H4, g_H4.breakerHigh, g_H4.breakerLow,
              g_H4.bullish ? ColorOB_Bear : ColorOB_Bull, "H4 Breaker");
}

void DrawBox(string name, ENUM_TIMEFRAMES tf, double hi, double lo,
             color clr, string label) {
   if(hi <= 0 || lo <= 0 || hi <= lo) return;

   int      lb = MathMin(OB_Lookback, iBars(_Symbol, tf) - 2);
   if(lb    < 1) return;
   datetime t1 = iTime(_Symbol, tf, lb);
   datetime t2 = iTime(_Symbol, tf, 0);
   if(t1    <= 0 || t2 <= 0) return;
   t2 += (datetime)PeriodSeconds(tf) * 20;

   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   ObjectSetInteger(0, name, OBJPROP_COLOR,   clr);
   ObjectSetInteger(0, name, OBJPROP_FILL,    true);
   ObjectSetInteger(0, name, OBJPROP_BACK,    true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,   1);
   ObjectSetInteger(0, name, OBJPROP_STYLE,   STYLE_SOLID);
   ObjectSetString (0, name, OBJPROP_TEXT,    label);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

void DrawFVGZones() {
   DrawFVGForTF(TF_H4,  "VIS_FVG_H4",  g_H4,  "H4 FVG");
   DrawFVGForTF(TF_H1,  "VIS_FVG_H1",  g_H1,  "H1 FVG");
   DrawFVGForTF(TF_M15, "VIS_FVG_M15", g_M15, "M15 FVG");
   DrawFVGForTF(TF_M5,  "VIS_FVG_M5",  g_M5,  "M5 FVG");
}

void DrawFVGForTF(ENUM_TIMEFRAMES tf, string name,
                  SMCAnalysis &a, string label) {
   if(!a.hasFVGOpen) return;
   if(a.fvgHigh <= 0 || a.fvgLow <= 0) return;
   if(iBars(_Symbol, tf) < 10) return;

   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low,  true);
   int lookback = MathMin(FVG_Lookback + 3, 20);
   if(CopyHigh(_Symbol, tf, 0, lookback, high) < lookback) return;
   if(CopyLow (_Symbol, tf, 0, lookback, low)  < lookback) return;

   // Find FVG zone boundaries
   for(int i = 1; i < lookback - 1; i++) {
      double fvgHi = 0, fvgLo = 0;
      if(a.bullish && low[i-1] > high[i+1]) {
         fvgHi = low[i-1];
         fvgLo = high[i+1];
      } else if(!a.bullish && high[i-1] < low[i+1]) {
         fvgHi = low[i+1];
         fvgLo = high[i-1];
      }
      if(fvgHi > 0 && fvgLo > 0 && fvgHi > fvgLo) {
         datetime t1 = iTime(_Symbol, tf, i + 1);
         datetime t2 = iTime(_Symbol, tf, 0);
         if(t1 <= 0 || t2 <= 0) break;
         t2 += (datetime)PeriodSeconds(tf) * 15;
         if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, fvgHi, t2, fvgLo);
         color clr = a.bullish ? ColorFVG_Bull : ColorFVG_Bear;
         ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
         ObjectSetInteger(0, name, OBJPROP_FILL,       true);
         ObjectSetInteger(0, name, OBJPROP_BACK,       true);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetString (0, name, OBJPROP_TEXT,       label);
         break;
      }
   }
}

void DrawSweepLines() {
   DrawSweepForTF(TF_H1,  "VIS_SW_H1",  g_H1,  "H1 Sweep");
   DrawSweepForTF(TF_M15, "VIS_SW_M15", g_M15, "M15 Sweep");
   DrawSweepForTF(TF_M5,  "VIS_SW_M5",  g_M5,  "M5 Sweep");
}

void DrawSweepForTF(ENUM_TIMEFRAMES tf, string name,
                    SMCAnalysis &a, string label) {
   if(!a.hasLiqSweep) return;
   if(a.sweepLevel <= 0) return;
   if(iBars(_Symbol, tf) < 10) return;

   double arr[];
   ArraySetAsSeries(arr, true);
   int lookback = MathMin(Sweep_Lookback + 2, 20);
   double level = a.sweepLevel;  // Use pre-computed sweep level from SMC engine

   datetime t1 = iTime(_Symbol, tf, lookback);
   datetime t2 = iTime(_Symbol, tf, 0);
   if(t1 <= 0 || t2 <= 0) return;
   t2 += (datetime)PeriodSeconds(tf) * 10;
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_TREND, 0, t1, level, t2, level);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      ColorSweep);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      STYLE_DOT);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       1);
   ObjectSetString (0, name, OBJPROP_TEXT,        label);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT,   false);
}

void DrawStructureArrows() {
   // BOS arrows on H4
   if(ShowBOSArrows && g_H4.hasExternalBOS && iBars(_Symbol, TF_H4) > 2) {
      datetime  t  = iTime(_Symbol, TF_H4, 1);
      double    lv = g_H4.bullish ? iLow (_Symbol, TF_H4, 1) - 200 * _Point
                                  : iHigh(_Symbol, TF_H4, 1) + 200 * _Point;
      if(t > 0 && lv > 0) {
         string name = "VIS_BOS_H4";
         if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
         ObjectCreate(0, name, OBJ_ARROW, 0, t, lv);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, g_H4.bullish ? 233 : 234);
         ObjectSetInteger(0, name, OBJPROP_COLOR,     g_H4.bullish ? ColorBull : ColorBear);
         ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
         ObjectSetString (0, name, OBJPROP_TEXT,       "BOS H4");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
   }
   // CHoCH arrows on H1
   if(ShowCHoCHArrows && g_H1.hasCHoCH && iBars(_Symbol, TF_H1) > 2) {
      datetime  t  = iTime(_Symbol, TF_H1, 1);
      double    lv = g_H1.bullish ? iLow (_Symbol, TF_H1, 1) - 150 * _Point
                                  : iHigh(_Symbol, TF_H1, 1) + 150 * _Point;
      if(t > 0 && lv > 0) {
         string name = "VIS_CHOCH_H1";
         if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
         ObjectCreate(0, name, OBJ_ARROW, 0, t, lv);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, g_H1.bullish ? 233 : 234);
         ObjectSetInteger(0, name, OBJPROP_COLOR,     clrAqua);
         ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
         ObjectSetString (0, name, OBJPROP_TEXT,       "CHoCH H1");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
   }
   // CHoCH on M15
   if(ShowCHoCHArrows && g_M15.hasCHoCH && iBars(_Symbol, TF_M15) > 2) {
      datetime  t  = iTime(_Symbol, TF_M15, 1);
      double    lv = g_M15.bullish ? iLow (_Symbol, TF_M15, 1) - 100 * _Point
                                   : iHigh(_Symbol, TF_M15, 1) + 100 * _Point;
      if(t > 0 && lv > 0) {
         string name = "VIS_CHOCH_M15";
         if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
         ObjectCreate(0, name, OBJ_ARROW, 0, t, lv);
         ObjectSetInteger(0, name, OBJPROP_ARROWCODE, g_M15.bullish ? 233 : 234);
         ObjectSetInteger(0, name, OBJPROP_COLOR,     clrYellow);
         ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
         ObjectSetString (0, name, OBJPROP_TEXT,       "CHoCH M15");
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
   }
}

void DrawTradeLevelLines() {
   if(!ShowTradeLevels) return;
   ObjectsDeleteAll(0, "VIS_TL_");
   for(int t = 0; t < ArraySize(g_Trades); t++) {
      TradeState ts  = g_Trades[t];
      if(ts.ticket  == 0) continue;
      string     pfx = "VIS_TL_" + IntegerToString(ts.ticket);
      DrawHLine(pfx + "_SL",  ts.initialSL,  ColorSL_Line,  STYLE_SOLID, 2, "SL");
      DrawHLine(pfx + "_TP1", ts.tp1Price,   ColorTP1_Line, STYLE_DASH,  1, "TP1");
      DrawHLine(pfx + "_TP2", ts.tp2Price,   ColorTP2_Line, STYLE_SOLID, 1, "TP2");
      DrawHLine(pfx + "_EN",  ts.entryPrice, clrWhite,      STYLE_DOT,   1, "Entry");
   }
}

void DrawHLine(string name, double price, color clr,
               ENUM_LINE_STYLE style, int width, string label) {
   if(price <= 0) return;
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,      style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,       width);
   ObjectSetString (0, name, OBJPROP_TEXT,        label);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, name, OBJPROP_BACK,        true);
}

//+------------------------------------------------------------------+
//|  NOTIFICATIONS                                                   |
//+------------------------------------------------------------------+

void SendSignalNotification(string strategy, bool isBuy, int score,
                            double entry, double sl, double tp1,
                            double tp2, double lots, double riskPct) {
   string dir  = isBuy ? "BUY" : "SELL";
   string msg  = StringFormat(
      "XAUUSD SNIPER | %s %s\nScore: %d/60 | %s\nEntry: %.2f\nSL: %.2f | TP1: %.2f | TP2: %.2f\nRisk: %.1f%% | Lots: %.2f",
      strategy, dir, score, g_Session,
      entry, sl, tp1, tp2, riskPct, lots);

   if(AlertOnSignal)  Alert(msg);
   if(UsePushAlert)   SendNotification(msg);
   if(UseEmailAlert)  SendMail("XAUUSD Sniper Signal: " + strategy + " " + dir, msg);
   if(UseSoundAlert)  PlaySound(isBuy ? SoundBuy : SoundSell);
}

void SendTradeResultNotification(bool isWin, double profitUSD,
                                 ulong ticket, string strategy) {
   string msg = StringFormat(
      "XAUUSD SNIPER | Trade %s\n#%d %s\nProfit: %s$%.2f\nWin Rate: %.1f%% | Profit Factor: %.2f",
      isWin ? "WIN" : "LOSS", ticket, strategy,
      profitUSD >= 0 ? "+" : "", profitUSD,
      GetWinRate(), GetProfitFactor());

   if(UsePushAlert)  SendNotification(msg);
   if(UseSoundAlert) PlaySound(isWin ? SoundTP : SoundSL);
}

void SendDailyLimitNotification(string reason) {
   string msg = StringFormat(
      "XAUUSD SNIPER | Trading Stopped\n%s\nDaily P&L: %+.2f%%\nWins: %d | Losses: %d",
      reason, g_DailyPnL, g_TotalWins, g_TotalLosses);
   if(UsePushAlert)  SendNotification(msg);
   if(AlertOnSignal) Alert(msg);
}

//+------------------------------------------------------------------+
//|  HTML PERFORMANCE REPORT                                        |
//+------------------------------------------------------------------+

void GenerateHTMLReport() {
   int fh = FileOpen(ReportFileName, FILE_WRITE|FILE_COMMON|FILE_TXT);
   if(fh == INVALID_HANDLE) return;

   double netPnL      = g_TotalProfit - g_TotalLoss;
   double winRate     = GetWinRate();
   double pf          = GetProfitFactor();
   double returnPct   = g_StartBalance > 0 ?
                        (AccountInfoDouble(ACCOUNT_BALANCE) - g_StartBalance)
                        / g_StartBalance * 100.0 : 0;
   double avgWin      = g_TotalWins  > 0 ? g_TotalProfit / g_TotalWins  : 0;
   double avgLoss     = g_TotalLosses> 0 ? g_TotalLoss   / g_TotalLosses: 0;
   double avgRR       = avgLoss > 0 ? avgWin / avgLoss : 0;
   double maxDD       = g_PeakBalance > 0 ?
                        (g_PeakBalance - g_MinEquity) / g_PeakBalance * 100.0 : 0;

   string html = "";
   html += "<!DOCTYPE html><html><head><meta charset='UTF-8'>";
   html += "<title>XAUUSD Sniper EA — Performance Report</title>";
   html += "<style>";
   html += "body{background:#0d0d1a;color:#e0e0e0;font-family:Consolas,monospace;padding:20px;}";
   html += "h1{color:gold;} h2{color:#64b4ff;border-bottom:1px solid #333;padding-bottom:5px;}";
   html += "table{width:100%;border-collapse:collapse;margin-bottom:20px;}";
   html += "th{background:#1a1a2e;color:#64b4ff;padding:8px;text-align:left;}";
   html += "td{padding:7px 8px;border-bottom:1px solid #1e1e2e;}";
   html += "tr:hover{background:#1a1a2e;}";
   html += ".win{color:#00ff88;} .loss{color:#ff4444;} .warn{color:orange;}";
   html += ".card{background:#12121f;border:1px solid #2a2a3e;border-radius:6px;";
   html += "padding:15px;margin:10px 0;display:inline-block;min-width:180px;margin-right:10px;}";
   html += ".card-val{font-size:1.6em;font-weight:bold;} .card-lbl{color:#888;font-size:0.8em;}";
   html += "</style></head><body>";

   // Header
   html += "<h1>XAUUSD Sniper EA — Performance Report</h1>";
   html += StringFormat("<p>Generated: %s &nbsp;|&nbsp; Symbol: %s &nbsp;|&nbsp; Magic: %d</p>",
                        TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), _Symbol, MagicNumber);
   html += StringFormat("<p>Period: %s → %s</p>",
                        TimeToString(g_EAStartTime, TIME_DATE),
                        TimeToString(TimeCurrent(), TIME_DATE));

   // KPI Cards
   string rrClass  = avgRR  >= 2.0  ? "win" : (avgRR  >= 1.0 ? "warn" : "loss");
   string pfClass  = pf     >= 1.5  ? "win" : (pf     >= 1.0 ? "warn" : "loss");
   string wrClass  = winRate>= 60.0 ? "win" : (winRate>= 45.0? "warn" : "loss");
   string retClass = returnPct >= 0  ? "win" : "loss";

   html += "<div>";
   html += KPICard("Net Return",    StringFormat("%+.2f%%", returnPct),   retClass);
   html += KPICard("Win Rate",      StringFormat("%.1f%%",  winRate),     wrClass);
   html += KPICard("Profit Factor", StringFormat("%.2f",    pf),          pfClass);
   html += KPICard("Avg R:R",       StringFormat("1:%.2f",  avgRR),       rrClass);
   html += KPICard("Total Trades",  IntegerToString(g_TotalTrades),       "");
   html += KPICard("Max Drawdown",  StringFormat("%.2f%%",  maxDD),       maxDD > 10 ? "loss" : "win");
   html += KPICard("Total Pips",    StringFormat("%.1f",    g_TotalPips), g_TotalPips >= 0 ? "win" : "loss");
   html += KPICard("Net P&L",       StringFormat("$%.2f",   netPnL),      netPnL >= 0 ? "win" : "loss");
   html += "</div><br/>";

   // Summary table
   html += "<h2>Summary Statistics</h2>";
   html += "<table><tr><th>Metric</th><th>Value</th></tr>";
   html += TR("Starting Balance",   StringFormat("$%.2f", g_StartBalance));
   html += TR("Ending Balance",     StringFormat("$%.2f", AccountInfoDouble(ACCOUNT_BALANCE)));
   html += TR("Peak Equity",        StringFormat("$%.2f", g_MaxEquity));
   html += TR("Lowest Equity",      StringFormat("$%.2f", g_MinEquity));
   html += TR("Total Trades",       IntegerToString(g_TotalTrades));
   html += TR("Wins",               IntegerToString(g_TotalWins));
   html += TR("Losses",             IntegerToString(g_TotalLosses));
   html += TR("Win Rate",           StringFormat("%.2f%%", winRate));
   html += TR("Profit Factor",      StringFormat("%.2f",   pf));
   html += TR("Gross Profit",       StringFormat("$%.2f",  g_TotalProfit));
   html += TR("Gross Loss",         StringFormat("$%.2f",  g_TotalLoss));
   html += TR("Net P&L",            StringFormat("$%.2f",  netPnL));
   html += TR("Avg Win",            StringFormat("$%.2f",  avgWin));
   html += TR("Avg Loss",           StringFormat("$%.2f",  avgLoss));
   html += TR("Avg R:R Achieved",   StringFormat("1:%.2f", avgRR));
   html += TR("Best Trade",         StringFormat("$%.2f",  g_BestTrade));
   html += TR("Worst Trade",        StringFormat("$%.2f",  g_WorstTrade));
   html += TR("Total Pips",         StringFormat("%.1f",   g_TotalPips));
   html += TR("Max Win Streak",     IntegerToString(g_MaxWinStreak));
   html += TR("Max Lose Streak",    IntegerToString(g_MaxLoseStreak));
   html += TR("Max Drawdown",       StringFormat("%.2f%%", maxDD));
   html += TR("Primary Trades",     IntegerToString(g_PrimaryTrades));
   html += TR("Fallback Trades",    IntegerToString(g_FallbackTrades));
   html += TR("Tertiary Trades",    IntegerToString(g_TertiaryTrades));
   html += TR("Expected Payoff",    StringFormat("$%.2f / trade", GetExpectedPayoff()));
   html += TR("ATR Blocks",         IntegerToString(g_ATRBlockCount));
   html += TR("Spread Blocks",      IntegerToString(g_SpreadBlockCount));
   html += TR("News Blocks",        IntegerToString(g_NewsBlockCount));
   html += "</table>";

   // Per-session breakdown
   html += "<h2>Per-Session Performance</h2>";
   html += "<table><tr><th>Session</th><th>Trades</th><th>Wins</th><th>Losses</th>";
   html += "<th>Win Rate</th><th>Gross Profit</th><th>Gross Loss</th><th>Net P&L</th><th>Pips</th><th>Status</th></tr>";
   for(int si = 0; si < SESSION_COUNT; si++) {
      int strades = g_SessStats[si].wins + (g_SessStats[si].total - g_SessStats[si].wins);
      int swins   = g_SessStats[si].wins;
      int stotal  = g_SessStats[si].total;
      int slosses = stotal - swins;
      double swr  = stotal > 0 ? (double)swins / stotal * 100.0 : 0;
      double snet = g_SessProfit[si] - g_SessLoss[si];
      string sc   = swr >= 55.0 ? "win" : (swr >= 40.0 ? "warn" : (stotal > 0 ? "loss" : ""));
      string susp = g_SessStats[si].suspended ? "<span class='loss'>SUSPENDED</span>" : "<span class='win'>Active</span>";
      html += StringFormat(
         "<tr><td>%s</td><td>%d</td><td class='win'>%d</td><td class='loss'>%d</td>"
         "<td class='%s'>%.1f%%</td><td class='win'>$%.2f</td><td class='loss'>$%.2f</td>"
         "<td class='%s'>$%.2f</td><td>%.1f</td><td>%s</td></tr>",
         g_SessionNames[si], stotal, swins, slosses,
         sc, swr, g_SessProfit[si], g_SessLoss[si],
         snet >= 0 ? "win" : "loss", snet, g_SessPips[si], susp);
   }
   html += "</table>";

   // Monthly performance calendar
   html += "<h2>Monthly Performance</h2>";
   html += "<table><tr><th>Year</th><th>Month</th><th>Trades</th><th>Wins</th><th>Losses</th>";
   html += "<th>Win Rate</th><th>Gross Profit</th><th>Gross Loss</th><th>Net P&L</th><th>Profit Factor</th></tr>";
   double cumPnL = 0;
   for(int mi = 0; mi < ArraySize(g_MonthlyPerf); mi++) {
      MonthlyPerf mp = g_MonthlyPerf[mi];
      int mTrades    = mp.wins + mp.losses;
      double mWR     = mTrades > 0 ? (double)mp.wins / mTrades * 100.0 : 0;
      double mNet    = mp.grossProfit - mp.grossLoss;
      double mPF     = mp.grossLoss > 0 ? mp.grossProfit / mp.grossLoss : (mp.grossProfit > 0 ? 99.0 : 0);
      cumPnL        += mNet;
      string mClass  = mNet >= 0 ? "win" : "loss";
      string mNames[] = {"","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"};
      string monName  = (mp.month >= 1 && mp.month <= 12) ? mNames[mp.month] : IntegerToString(mp.month);
      html += StringFormat(
         "<tr><td>%d</td><td>%s</td><td>%d</td><td class='win'>%d</td><td class='loss'>%d</td>"
         "<td class='%s'>%.1f%%</td><td class='win'>$%.2f</td><td class='loss'>$%.2f</td>"
         "<td class='%s'>$%.2f</td><td class='%s'>%.2f</td></tr>",
         mp.year, monName, mTrades, mp.wins, mp.losses,
         mNet >= 0 ? "win" : "loss", mWR,
         mp.grossProfit, mp.grossLoss,
         mClass, mNet, mPF >= 1.0 ? "win" : "loss", mPF);
   }
   html += StringFormat("<tr style='font-weight:bold'><td colspan='8'>Cumulative Net P&L</td>"
                        "<td class='%s'>$%.2f</td><td></td></tr>",
                        cumPnL >= 0 ? "win" : "loss", cumPnL);
   html += "</table>";

   // Settings used
   html += "<h2>EA Settings Used</h2>";
   html += "<table><tr><th>Parameter</th><th>Value</th></tr>";
   html += TR("Min Primary Score",    IntegerToString(MinPrimaryScore));
   html += TR("Min Fallback Score",   IntegerToString(MinFallbackScore));
   html += TR("Primary Risk %",       StringFormat("%.1f%%", PrimaryRisk));
   html += TR("Fallback Risk %",      StringFormat("%.1f%%", FallbackRisk));
   html += TR("TP1 R:R",              StringFormat("1:%.1f", TP1_RR));
   html += TR("TP2 R:R",              StringFormat("1:%.1f", TP2_RR));
   html += TR("Breakeven Trigger",    StringFormat("%.1fx SL", BreakevenTrigger));
   html += TR("Trail Distance",       StringFormat("%.1f pips", TrailDistance));
   html += TR("Daily Loss Limit",     StringFormat("%.1f%%", DailyLossLimit));
   html += TR("Daily Profit Target",  StringFormat("%.1f%%", DailyProfitTarget));
   html += TR("Weekly Loss Limit",    StringFormat("%.1f%%", WeeklyLossLimit));
   html += TR("Monthly Loss Limit",   StringFormat("%.1f%%", MonthlyLossLimit));
   html += TR("Max Drawdown %",       StringFormat("%.1f%%", MaxDrawdownPct));
   html += TR("Max Spread Pips",      StringFormat("%.1f",   MaxSpreadPips));
   html += "</table>";

   html += "<br/><p style='color:#555;font-size:0.8em'>XAUUSD Sniper EA v13.17 — Advanced SMC Engine — Philippines Sniper Strategy</p>";
   html += "</body></html>";

   FileWriteString(fh, html);
   FileClose(fh);
}

string KPICard(string label, string value, string cls) {
   return StringFormat(
      "<div class='card'><div class='card-val %s'>%s</div><div class='card-lbl'>%s</div></div>",
      cls, value, label);
}

string TR(string label, string value) {
   return StringFormat("<tr><td>%s</td><td><b>%s</b></td></tr>", label, value);
}

//+------------------------------------------------------------------+
//| Dashboard creation — all labels                                 |
//+------------------------------------------------------------------+
void CreateDashboard() {
   // Background rectangle — height calculated to cover all rows including tertiary tier
   // ROW_HEIGHT * 170 covers all current dashboard sections with room to spare
   CreateRect(PREFIX+"BG", Dashboard_X - 5, Dashboard_Y - 5,
              DASH_WIDTH, ROW_HEIGHT * 170 + 10, ColorBG);
}

//+------------------------------------------------------------------+
//| Update all dashboard labels                                      |
//+------------------------------------------------------------------+
void UpdateDashboard() {
   int x  = Dashboard_X;
   int y  = Dashboard_Y;
   int dy = ROW_HEIGHT;

   // Title
   SetLabel(PREFIX+"T0", x, y,
            "══════════ XAUUSD SNIPER DASHBOARD ══════════",
            ColorTitle, FontSize + 1);
   y += dy + 2;

   // Current time PHT + DST status
   MqlDateTime dt;
   datetime nowUTC = TimeGMT();
   TimeToStruct(nowUTC, dt);
   int pht       = (dt.hour + 8) % 24;
   int loUTC_d   = GetLondonOpenUTC(nowUTC);
   int nyUTC_d   = GetNYOpenUTC(nowUTC);
   int loPHT_d   = (loUTC_d + 8) % 24;
   int nyPHT_d   = (nyUTC_d + 8) % 24;
   bool lonDST   = IsLondonDST(nowUTC);
   bool nyDST    = IsNYDST(nowUTC);
   string dstStr = (lonDST && nyDST) ? "Summer (BST+EDT)" :
                   (!lonDST && !nyDST) ? "Winter (GMT+EST)" :
                   lonDST ? "Trans: UK-DST, US-STD" : "Trans: US-DST, UK-STD";
   SetLabel(PREFIX+"T1", x, y,
            StringFormat("PHT Time: %02d:%02d  |  %s  |  London %dPM | NY %dPM PHT",
                         pht, dt.min, dstStr, loPHT_d, nyPHT_d),
            ColorNeutral, FontSize);
   y += dy;

   // Session + active parameters
   int    dsi = GetSessionIndex();
   SessionParams dsp = GetSessionParams();
   bool   inBlackout  = IsInPreSessionBlackout();
   bool   isPreSess   = (dsi == SESS_PRELONDON || dsi == SESS_PRENY);
   color sessionColor = inBlackout                                                                   ? clrOrangeRed :
                        isPreSess                                                                   ? clrGold :
                        (dsi == SESS_LONDON_OPEN || dsi == SESS_NY_OPEN)                           ? ColorBull :
                        (dsi == SESS_ASIAN || dsi == SESS_PREMARKET ||
                         dsi == SESS_LONDON_MID || dsi == SESS_NY_PM)                             ? ColorWarn :
                        ColorNeutral;
   string sessionDisplay = inBlackout  ? StringFormat("⚠ BLOCKED: %s", g_Session) :
                           isPreSess   ? StringFormat("⚡ %s", g_Session) :
                                         StringFormat("Session: %s", g_Session);
   SetLabel(PREFIX+"T2", x, y, sessionDisplay, sessionColor, FontSize);
   y += dy;
   string sessParamStr = StringFormat("Risk: %.1f%%  |  Min Score: %d  |  TP2 RR: 1:%.1f  |  Max Entries: %s  |  %s",
      dsp.risk, dsp.minScore, dsp.tp2RR,
      dsp.maxNewTrades >= 99 ? "Scaled" : IntegerToString(dsp.maxNewTrades),
      dsp.tag);
   SetLabel(PREFIX+"T2b", x, y, sessParamStr, sessionColor, FontSize);
   y += dy;

   // Daily bias lock + open positions direction
   bool judasNow = g_M15.isJudasSwing || g_M5.isJudasSwing;
   string biasStr = g_DailyBiasLocked
      ? StringFormat("Daily Bias: %s (locked by London)  |  Open: %d BUY / %d SELL",
                     g_DailyBias ? "BULLISH" : "BEARISH", g_OpenBuys, g_OpenSells)
      : StringFormat("Daily Bias: Not locked yet  |  Open: %d BUY / %d SELL",
                     g_OpenBuys, g_OpenSells);
   string judasStr = judasNow ? "  |  JUDAS SWING ACTIVE" : "";
   color biasClr = g_DailyBiasLocked ? (g_DailyBias ? ColorBull : ColorBear) : ColorNeutral;
   SetLabel(PREFIX+"T2c", x, y, biasStr + judasStr, biasClr, FontSize);
   y += dy;

   // PDH / PDL / PWH / PWL — key daily & weekly liquidity levels
   {
      string pdh = StringFormat("PDH:%.2f%s", g_H1.prevDayHigh,
                     g_H1.sweepPDH ? " SWEPT!" : (g_H1.atPDH ? " AT" : ""));
      string pdl = StringFormat("PDL:%.2f%s", g_H1.prevDayLow,
                     g_H1.sweepPDL ? " SWEPT!" : (g_H1.atPDL ? " AT" : ""));
      string pwh = StringFormat("PWH:%.2f%s", g_H4.prevWeekHigh,
                     g_H4.sweepPWH ? " SWEPT!" : (g_H4.atPWH ? " AT" : ""));
      string pwl = StringFormat("PWL:%.2f%s", g_H4.prevWeekLow,
                     g_H4.sweepPWL ? " SWEPT!" : (g_H4.atPWL ? " AT" : ""));
      bool anySwept = g_H1.sweepPDH || g_H1.sweepPDL || g_H4.sweepPWH || g_H4.sweepPWL;
      bool anyAt    = g_H1.atPDH || g_H1.atPDL || g_H4.atPWH || g_H4.atPWL;
      color pdColor = anySwept ? clrOrangeRed : anyAt ? clrGold : ColorNeutral;
      SetLabel(PREFIX+"T2d", x, y,
               StringFormat("Levels: %s  |  %s  |  %s  |  %s", pdh, pdl, pwh, pwl),
               pdColor, FontSize);
   }
   y += dy + 4;

   // ── PRIMARY STRATEGY H4 / H1 / M15 ──
   SetLabel(PREFIX+"PH", x, y, "── PRIMARY STRATEGY: H4 → H1 → M15 ──", ColorHeader, FontSize);
   y += dy;

   color h4c  = g_H4.bullish  ? ColorBull : ColorBear;
   color h1c  = g_H1.bullish  ? ColorBull : ColorBear;
   color m15c = g_M15.bullish ? ColorBull : ColorBear;
   color m5c  = g_M5.bullish  ? ColorBull : ColorBear;

   // H4 Structure
   SetLabel(PREFIX+"H4L",  x, y, "H4  STRUCT│", ColorHeader, FontSize);
   SetLabel(PREFIX+"H4V",  x+95, y, g_H4.structureNarrative, h4c, FontSize);
   y += dy;
   SetLabel(PREFIX+"H4L2", x, y, "H4  LIQ   │", ColorHeader, FontSize);
   SetLabel(PREFIX+"H4V2", x+95, y, g_H4.liquidityNarrative, h4c, FontSize);
   y += dy;
   SetLabel(PREFIX+"H4L3", x, y, "H4  S/R   │", ColorHeader, FontSize);
   SetLabel(PREFIX+"H4V3", x+95, y, g_H4.srNarrative, ColorNeutral, FontSize);
   y += dy;

   // H1
   SetLabel(PREFIX+"H1L",  x, y, "H1  STRUCT│", ColorHeader, FontSize);
   SetLabel(PREFIX+"H1V",  x+95, y, g_H1.structureNarrative, h1c, FontSize);
   y += dy;
   SetLabel(PREFIX+"H1L2", x, y, "H1  LIQ   │", ColorHeader, FontSize);
   SetLabel(PREFIX+"H1V2", x+95, y, g_H1.liquidityNarrative, h1c, FontSize);
   y += dy;
   SetLabel(PREFIX+"H1L3", x, y, "H1  S/R   │", ColorHeader, FontSize);
   SetLabel(PREFIX+"H1V3", x+95, y, g_H1.srNarrative, ColorNeutral, FontSize);
   y += dy;

   // M15
   SetLabel(PREFIX+"M15A", x, y, "M15 STRUCT│", ColorHeader, FontSize);
   SetLabel(PREFIX+"M15B", x+95, y, g_M15.structureNarrative, m15c, FontSize);
   y += dy;
   SetLabel(PREFIX+"M15C", x, y, "M15 LIQ   │", ColorHeader, FontSize);
   SetLabel(PREFIX+"M15D", x+95, y, g_M15.liquidityNarrative, m15c, FontSize);
   y += dy;

   color psColor = (g_PrimaryScore >= MinPrimaryScore) ? ColorBull :
                   (g_PrimaryScore >= 15) ? ColorWarn : ColorBear;
   SetLabel(PREFIX+"PS", x, y,
            StringFormat("Primary Score: %d / 42   (Need %d to trade)",
                         g_PrimaryScore, MinPrimaryScore), psColor, FontSize);
   y += dy + 4;

   // ── FALLBACK STRATEGY H1 / M15 / M5 ──
   SetLabel(PREFIX+"FH", x, y, "── FALLBACK STRATEGY: H1 → M15 → M5 ──", ColorHeader, FontSize);
   y += dy;

   SetLabel(PREFIX+"FM5A", x, y, "M5  STRUCT│", ColorHeader, FontSize);
   SetLabel(PREFIX+"FM5B", x+95, y, g_M5.structureNarrative, m5c, FontSize);
   y += dy;
   SetLabel(PREFIX+"FM5C", x, y, "M5  LIQ   │", ColorHeader, FontSize);
   SetLabel(PREFIX+"FM5D", x+95, y, g_M5.liquidityNarrative, m5c, FontSize);
   y += dy;

   color fsColor = (g_FallbackScore >= MinFallbackScore) ? ColorBull :
                   (g_FallbackScore >= 15) ? ColorWarn : ColorBear;
   SetLabel(PREFIX+"FS", x, y,
            StringFormat("Fallback Score: %d / 42  (Need %d to trade)",
                         g_FallbackScore, MinFallbackScore), fsColor, FontSize);
   y += dy + 4;

   // ── TERTIARY STRATEGY M15 / M5 / M1 ──
   SetLabel(PREFIX+"TH", x, y, "── TERTIARY STRATEGY: M15 → M5 → M1  (Scalp — fires when P & F have no signal) ──",
            ColorHeader, FontSize);
   y += dy;

   color m1c = g_M1.bullish ? ColorBull : ColorBear;
   SetLabel(PREFIX+"TM1A", x, y, "M1  STRUCT│", ColorHeader, FontSize);
   SetLabel(PREFIX+"TM1B", x+95, y, g_M1.structureNarrative, m1c, FontSize);
   y += dy;
   SetLabel(PREFIX+"TM1C", x, y, "M1  LIQ   │", ColorHeader, FontSize);
   SetLabel(PREFIX+"TM1D", x+95, y, g_M1.liquidityNarrative,  m1c, FontSize);
   y += dy;

   int effTert2 = UseAdaptiveLearning ? g_DynTertiaryScore : MinTertiaryScore;
   color tsColor = (g_TertiaryScore >= effTert2) ? ColorBull :
                   (g_TertiaryScore >= 8) ? ColorWarn : ColorBear;
   SetLabel(PREFIX+"TS", x, y,
            StringFormat("Tertiary Score: %d / 42  (Need %d to trade)  |  Risk: %.1f%%  |  Entry TF: M1",
                         g_TertiaryScore, effTert2, TertiaryRisk), tsColor, FontSize);
   y += dy + 4;

   // ── ADVANCED SMC CHECKLIST ──
   SetLabel(PREFIX+"CH", x, y, "── ADVANCED SMC CHECKLIST ──", ColorHeader, FontSize);
   y += dy;

   // Structure row
   SetLabel(PREFIX+"C1", x, y,
            CheckMark(g_H4.hasExternalBOS) + " H4 ExtBOS  " +
            CheckMark(g_H4.hasMSS)         + " H4 MSS     " +
            CheckMark(g_H4.hasFreshOB)     + " H4 FreshOB",
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"C2", x, y,
            CheckMark(g_H1.hasCHoCH)       + " H1 CHoCH   " +
            CheckMark(g_H1.hasMSS)         + " H1 MSS     " +
            CheckMark(g_H1.hasFVGOpen)     + " H1 OpenFVG",
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"C3", x, y,
            CheckMark(g_M15.hasLiqSweep)   + " M15 Sweep  " +
            CheckMark(g_M15.hasFreshOB)    + " M15 FreshOB" +
            CheckMark(g_M15.hasFVGOpen)    + " M15 OpenFVG",
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"C4", x, y,
            CheckMark(g_H4.hasEqualHighs || g_H4.hasEqualLows) + " EqH/L " +
            CheckMark(g_H1.inOTE)          + " H1 OTE     " +
            CheckMark(g_M15.isJudasSwing)  + " Judas Swing",
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"C5", x, y,
            CheckMark(g_H4.atKeySR)        + " H4 At S/R  " +
            CheckMark(g_H1.hasDisplacement)+ " H1 Displace" +
            CheckMark(g_M15.hasBreakerBlock)+" M15 Breaker",
            ColorText, FontSize);
   y += dy;

   // Asian range
   string asianStr = StringFormat("Asia Range: %.2f — %.2f  |  Price: %s",
                                  g_H1.asianLow, g_H1.asianHigh,
                                  g_H1.aboveAsianHigh ? "ABOVE (broke out)" :
                                  g_H1.belowAsianLow  ? "BELOW (broke out)" : "Inside range");
   color asianClr  = (g_H1.aboveAsianHigh || g_H1.belowAsianLow) ? ColorBull : ColorWarn;
   SetLabel(PREFIX+"C6", x, y, asianStr, asianClr, FontSize);
   y += dy;

   // Silver Bullet window
   color sbClr = g_M15.inSilverBullet ? ColorBull : ColorNeutral;
   SetLabel(PREFIX+"C7", x, y,
            StringFormat("Silver Bullet Window: %s  |  Weekly H/L: %.2f / %.2f",
                         g_M15.inSilverBullet ? "ACTIVE (22:00-23:00 PHT)" : "Not active",
                         g_H4.weeklyHigh, g_H4.weeklyLow),
            sbClr, FontSize);
   y += dy + 4;

   // ── DXY CORRELATION ──
   SetLabel(PREFIX+"DH", x, y, "── DXY CORRELATION ──", ColorHeader, FontSize);
   y += dy;

   color dxyClr = !UseDXYFilter         ? ColorNeutral :
                  !g_DXY_Available      ? ColorWarn    :
                  g_DXY_Bullish         ? ColorBear    : ColorBull;
   string dxyLabel = UseDXYFilter ? "" : "Filter OFF  |  ";
   SetLabel(PREFIX+"DX1", x, y,
            StringFormat("%sDXY (%s): %s  |  Price: %.3f  |  Change: %+.3f",
                         dxyLabel, DXY_Symbol,
                         g_DXY_Status, g_DXY_Price, g_DXY_Change),
            dxyClr, FontSize);
   y += dy;

   // DXY vs Gold logic explainer
   string dxyLogic = !g_DXY_Available ? "Check DXY symbol name in settings" :
                     g_DXY_Bullish    ? "USD Strengthening — Favor SELL gold, block BUY" :
                                        "USD Weakening — Favor BUY gold, block SELL";
   SetLabel(PREFIX+"DX2", x, y, dxyLogic,
            g_DXY_Available ? (g_DXY_Bullish ? ColorBear : ColorBull) : ColorWarn,
            FontSize);
   y += dy + 4;

   // ── CANDLE CONFIRMATION ──
   SetLabel(PREFIX+"CCH", x, y, "── CANDLE CONFIRMATION ──", ColorHeader, FontSize);
   y += dy;

   color ccClr = !UseCandleConfirm  ? ColorNeutral :
                 g_CandleConfirmed  ? ColorBull    : ColorWarn;
   string ccStatus = !UseCandleConfirm ? "Filter OFF" :
                     g_CandleConfirmed ? "CONFIRMED" : "WAITING";
   SetLabel(PREFIX+"CC1", x, y,
            StringFormat("Status: %s  |  Pattern: %s  |  Required on M15 (Primary) / M5 (Fallback)",
                         ccStatus, g_CandlePattern),
            ccClr, FontSize);
   y += dy;

   SetLabel(PREFIX+"CC2", x, y,
            StringFormat("Patterns accepted: Bullish/Bearish Engulf | Pin Bar (wick %.1fx body) | Strong Momentum (body >70%% range)",
                         PinBarWickRatio),
            ColorNeutral, FontSize);
   y += dy + 4;

   // ── ADAPTIVE LEARNING ──
   SetLabel(PREFIX+"ALH", x, y, "── ADAPTIVE LEARNING ──", ColorHeader, FontSize);
   y += dy;

   color learnClr = UseAdaptiveLearning ? ColorBull : ColorNeutral;
   SetLabel(PREFIX+"AL1", x, y,
            UseAdaptiveLearning ? g_LearnStatus : "Adaptive Learning: OFF",
            learnClr, FontSize);
   y += dy;

   // Dynamic thresholds
   int ep = UseAdaptiveLearning ? g_DynPrimaryScore  : MinPrimaryScore;
   int ef = UseAdaptiveLearning ? g_DynFallbackScore : MinFallbackScore;
   color thr1c = (ep > MinPrimaryScore)  ? ColorBear : (ep < MinPrimaryScore)  ? ColorBull : ColorText;
   color thr2c = (ef > MinFallbackScore) ? ColorBear : (ef < MinFallbackScore) ? ColorBull : ColorText;
   SetLabel(PREFIX+"AL2", x, y,
            StringFormat("Primary score threshold: %d  (base: %d)   Fallback: %d  (base: %d)   Batch: %d/%d",
                         ep, MinPrimaryScore, ef, MinFallbackScore,
                         g_BatchTradeCount, LearningBatchSize),
            ColorText, FontSize);
   y += dy;

   // Session performance table
   SetLabel(PREFIX+"AL3", x, y, "  Session Performance:", ColorHeader, FontSize);
   y += dy;
   for(int si = 0; si < SESSION_COUNT; si++) {
      double swr = g_SessStats[si].total > 0 ?
                   (double)g_SessStats[si].wins / g_SessStats[si].total * 100.0 : -1;
      string swrStr = swr >= 0 ? StringFormat("%.1f%%", swr) : "No data";
      string suspStr = g_SessStats[si].suspended ? " [SUSPENDED]" : "";
      color  swrClr  = g_SessStats[si].suspended ? ColorBear :
                       swr >= 60 ? ColorBull : swr >= 45 ? ColorWarn : ColorBear;
      SetLabel(PREFIX+"ALS"+IntegerToString(si), x, y,
               StringFormat("  %-14s  WR: %6s  (%d/%d trades)%s",
                            g_SessionNames[si], swrStr,
                            g_SessStats[si].wins, g_SessStats[si].total, suspStr),
               swrClr, FontSize);
      y += dy;
   }

   // Top 5 best confluences
   SetLabel(PREFIX+"AL4", x, y, "  Confluence Win Rates (top performing):", ColorHeader, FontSize);
   y += dy;

   // Sort by confluence value descending — simple bubble pass for display
   int   rankIdx[CONFLUENCE_COUNT];
   for(int i = 0; i < CONFLUENCE_COUNT; i++) rankIdx[i] = i;
   for(int i = 0; i < CONFLUENCE_COUNT - 1; i++)
      for(int j = i + 1; j < CONFLUENCE_COUNT; j++)
         if(ConfluenceValue(rankIdx[i]) < ConfluenceValue(rankIdx[j])) {
            int tmp = rankIdx[i]; rankIdx[i] = rankIdx[j]; rankIdx[j] = tmp;
         }

   // Show top 5
   int shown2 = 0;
   for(int i = 0; i < CONFLUENCE_COUNT && shown2 < 5; i++) {
      int   ci  = rankIdx[i];
      double wr = ConfluenceWinRate(ci);
      if(wr < 0) continue; // Not enough data
      double cv = ConfluenceValue(ci);
      color  wrc = wr >= 65 ? ColorBull : wr >= 50 ? ColorWarn : ColorBear;
      SetLabel(PREFIX+"ALC"+IntegerToString(shown2), x, y,
               StringFormat("  %-16s  WR: %.1f%%  Value: %+.1f  (%d trades)",
                            g_ConfluenceNames[ci], wr, cv,
                            g_ConfStats[ci].presentTotal),
               wrc, FontSize);
      y += dy;
      shown2++;
   }
   if(shown2 == 0) {
      SetLabel(PREFIX+"ALC0", x, y,
               StringFormat("  Accumulating data... need %d trades per confluence",
                            MinTradesForAdjust),
               ColorNeutral, FontSize);
      y += dy;
   }
   y += 4;

   // ── ICT ADVANCED CONCEPTS ──
   SetLabel(PREFIX+"ICTH", x, y, "── ICT ADVANCED CONCEPTS ──", ColorHeader, FontSize);
   y += dy;

   // Current TF data depending on which tier is active
   SMCAnalysis ict_ref, ict_mid, ict_htf;
   if(g_UseTertiary)      { ict_ref = g_M1;  ict_mid = g_M5;  ict_htf = g_M15; }
   else if(g_UseFallback) { ict_ref = g_M5;  ict_mid = g_M15; ict_htf = g_H1;  }
   else                   { ict_ref = g_M15; ict_mid = g_H1;  ict_htf = g_H4;  }

   // Killzone & Macro
   string kzStr = (ict_ref.killzoneName != "") ? ict_ref.killzoneName : "Outside Killzone";
   string macroStr = ict_ref.inICTMacro ? ict_ref.macroName : "No Macro";
   color kzClr = (ict_ref.inLondonKZ || ict_ref.inNYAmKZ) ? ColorBull :
                 (ict_ref.inNYPMKZ || ict_ref.inAsianKZ)   ? ColorWarn : ColorNeutral;
   SetLabel(PREFIX+"ICT1", x, y,
            StringFormat("Killzone: %-22s  |  Macro: %s",
                         (UseKillzones ? kzStr : "OFF"), (UseICTMacros ? macroStr : "OFF")),
            kzClr, FontSize);
   y += dy;

   // Power of 3
   string po3Str = g_M15.po3Phase != "" ? g_M15.po3Phase : "Undetermined";
   color po3Clr = g_M15.po3Distribution ? ColorBull :
                  g_M15.po3Manipulation ? ColorWarn : ColorNeutral;
   SetLabel(PREFIX+"ICT2", x, y,
            StringFormat("PO3 Phase: %-20s  |  CE: %s  |  Near MN Open: %s",
                         (UsePowerOf3 ? po3Str : "OFF"),
                         (UseCE ? (ict_ref.atCE ? StringFormat("YES (%.2f)", ict_ref.ceLevel) : "No") : "OFF"),
                         (UseMidnightOpen ? (ict_ref.nearMidnightOpen ? StringFormat("YES (%.2f)", ict_ref.midnightOpen) : "No") : "OFF")),
            po3Clr, FontSize);
   y += dy;

   // IPDA & BPR
   string ipdaStr = ict_htf.atIPDALevel ? StringFormat("YES (20:%d 40:%d 60:%d)",
                       (int)ict_htf.ipda20High, (int)ict_htf.ipda40High, (int)ict_htf.ipda60High) : "Not at level";
   string bprStr  = ict_mid.hasBPR ? StringFormat("YES [%.2f–%.2f]", ict_mid.bprLow, ict_mid.bprHigh) : "No";
   SetLabel(PREFIX+"ICT3", x, y,
            StringFormat("IPDA: %-30s  |  BPR: %s",
                         (UseIPDA ? ipdaStr : "OFF"), (UseBPR ? bprStr : "OFF")),
            (ict_htf.atIPDALevel ? ColorBull : ColorNeutral), FontSize);
   y += dy;

   // NDOG / NWOG
   string ndogStr = g_H1.hasNDOG ? StringFormat("YES [%.2f–%.2f]", g_H1.ndogLow, g_H1.ndogHigh) : "No gap";
   string nwogStr = g_H4.hasNWOG ? StringFormat("YES [%.2f–%.2f]", g_H4.nwogLow, g_H4.nwogHigh) : "No gap";
   SetLabel(PREFIX+"ICT4", x, y,
            StringFormat("NDOG: %-30s  |  NWOG: %s",
                         (UseGapDetection ? ndogStr : "OFF"), (UseGapDetection ? nwogStr : "OFF")),
            ((g_H1.hasNDOG || g_H4.hasNWOG) ? ColorWarn : ColorNeutral), FontSize);
   y += dy;

   // Strong / Weak H/L
   string swStr = "";
   if(ict_ref.hasWeakHigh)  swStr += StringFormat("Weak H:%.2f  ", ict_ref.weakHigh);
   if(ict_ref.hasWeakLow)   swStr += StringFormat("Weak L:%.2f  ", ict_ref.weakLow);
   if(StringLen(swStr) == 0) swStr = "No weak structures";
   SetLabel(PREFIX+"ICT5", x, y,
            StringFormat("Strong/Weak H/L: %-40s", swStr),
            (ict_ref.hasWeakHigh || ict_ref.hasWeakLow) ? ColorWarn : ColorNeutral, FontSize);
   y += dy;

   // SMT Divergence
   string smtStr = !UseSMTDivergence ? "OFF" :
                   !g_SMTDivergence  ? StringFormat("None detected (%s vs %s)", _Symbol, SMT_Symbol) :
                   StringFormat("DETECTED: %s — %s vs %s", g_SMTType, _Symbol, SMT_Symbol);
   color smtClr = !UseSMTDivergence ? ColorNeutral :
                  !g_SMTDivergence  ? ColorText :
                  (g_SMTType == "BULL_CONFIRM") ? ColorBull :
                  (g_SMTType == "BEAR_CONFIRM") ? ColorBear : ColorWarn;
   SetLabel(PREFIX+"ICT6", x, y, StringFormat("SMT Divergence: %s", smtStr), smtClr, FontSize);
   y += dy + 4;

   // ── CLAUDE AI BRIDGE ──
   SetLabel(PREFIX+"BRH", x, y, "── CLAUDE AI BRIDGE ──", ColorHeader, FontSize);
   y += dy;

   if(!UseBridge) {
      SetLabel(PREFIX+"BR1", x, y, "Bridge: OFF — enable UseBridge in settings to connect Claude AI",
               ColorNeutral, FontSize);
      y += dy + 4;
   } else {
      color brClr = g_BridgeState == BRIDGE_WAITING  ? ColorWarn  :
                    g_BridgeState == BRIDGE_APPROVED  ? ColorBull  :
                    g_BridgeState == BRIDGE_REJECTED  ? ColorBear  : ColorNeutral;
      SetLabel(PREFIX+"BR1", x, y, g_BridgeStatus, brClr, FontSize);
      y += dy;

      // Show last verdict details
      if(StringLen(g_BridgeReason) > 0) {
         SetLabel(PREFIX+"BR2", x, y,
                  StringFormat("Last verdict: %s — %s", g_BridgeVerdict, g_BridgeReason),
                  g_BridgeState == BRIDGE_APPROVED ? ColorBull : ColorBear, FontSize);
         y += dy;
      }

      // Timeout countdown if waiting
      if(g_BridgeState == BRIDGE_WAITING) {
         int elapsed  = (int)(TimeCurrent() - g_BridgeWriteTime);
         int remaining = BridgeTimeoutSec - elapsed;
         SetLabel(PREFIX+"BR3", x, y,
                  StringFormat("Waiting for Claude response... %ds remaining  (Files: %s / %s)",
                               MathMax(0, remaining), BridgeSignalFile, BridgeRespFile),
                  ColorWarn, FontSize);
         y += dy;
      }

      SetLabel(PREFIX+"BR4", x, y,
               StringFormat("Signal file: %s   Response file: %s   Timeout: %ds  MustApprove: %s",
                            BridgeSignalFile, BridgeRespFile, BridgeTimeoutSec,
                            BridgeMustApprove ? "YES" : "NO"),
               ColorNeutral, FontSize);
      y += dy + 4;
   }

   // ── RECOMMENDATION ──
   SetLabel(PREFIX+"RH", x, y, "── TRADE RECOMMENDATION ──", ColorHeader, FontSize);
   y += dy;

   color recColor = (StringFind(g_Recommendation, "PRIMARY TRADE") >= 0)  ? ColorBull  :
                    (StringFind(g_Recommendation, "FALLBACK TRADE") >= 0) ? ColorWarn  :
                    (StringFind(g_Recommendation, "NO TRADE") >= 0)       ? ColorBear  : ColorNeutral;
   SetLabel(PREFIX+"REC", x, y, g_Recommendation, recColor, FontSize);
   y += dy;

   // ── DAILY STATS & LIMITS ──
   y += dy;
   SetLabel(PREFIX+"DSH", x, y, "── DAILY STATS & LIMITS ──", ColorHeader, FontSize);
   y += dy;

   // Balance and equity
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   SetLabel(PREFIX+"DS1", x, y,
            StringFormat("Balance: $%.2f   Equity: $%.2f   Day Start: $%.2f",
                         balance, equity, g_DayStartBalance),
            ColorText, FontSize);
   y += dy;

   // Daily P&L bar
   color pnlColor = (g_DailyPnL >= 0) ? ColorBull : ColorBear;
   string pnlBar  = "";
   int    bars2   = (int)MathMin(MathAbs(g_DailyPnL) * 4, 20);
   for(int b = 0; b < bars2; b++) pnlBar += "|";
   int  curScorePnL = g_UseFallback ? g_FallbackScore : g_PrimaryScore;
   bool profitOverride = g_DailyProfitHit && UseScaledEntries && curScorePnL >= ScaledScore2;
   string profitNote = profitOverride ?
      StringFormat("  !! Target hit but OVERRIDDEN — Score %d >= %d", curScorePnL, ScaledScore2) :
      StringFormat("  Target: +%.1f%%  Limit: -%.1f%%", DailyProfitTarget, DailyLossLimit);
   SetLabel(PREFIX+"DS2", x, y,
            StringFormat("Daily P&L: %+.2f%%  [%s]%s", g_DailyPnL, pnlBar, profitNote),
            profitOverride ? ColorWarn : pnlColor, FontSize);
   y += dy;

   // Trade counters
   color tradeCountColor = (g_DailyTradeCount >= MaxDailyTrades) ? ColorBear : ColorText;
   SetLabel(PREFIX+"DS3", x, y,
            StringFormat("Trades Today: %d / %d   Consec Losses: %d / %d   Spread: %.1f pips",
                         g_DailyTradeCount, MaxDailyTrades,
                         g_ConsecLosses, MaxConsecLosses,
                         (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) *
                         SymbolInfoDouble(_Symbol, SYMBOL_POINT) /
                         (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10)),
            tradeCountColor, FontSize);
   y += dy;

   // Filters status row
   string spreadOK = IsSpreadOK()   ? "Spread:OK" : "Spread:HIGH";
   string newsOK   = !IsNearNews()  ? "News:Clear" : "News:BLOCKED";
   string balOK    = IsBalanceOK()  ? "Balance:OK" : "Balance:LOW";
   string gateOK   = IsTradingAllowed() ? "GATE: OPEN" : "GATE: CLOSED";
   color  gateClr  = IsTradingAllowed() ? ColorBull : ColorBear;
   color  spreadClr = IsSpreadOK()  ? ColorBull : ColorBear;
   color  newsClr   = !IsNearNews() ? ColorBull : ColorBear;
   color  balClr    = IsBalanceOK() ? ColorBull : ColorBear;

   SetLabel(PREFIX+"DS4a", x,       y, gateOK,    gateClr,   FontSize);
   SetLabel(PREFIX+"DS4b", x + 110, y, spreadOK,  spreadClr, FontSize);
   SetLabel(PREFIX+"DS4c", x + 210, y, newsOK,    newsClr,   FontSize);
   SetLabel(PREFIX+"DS4d", x + 310, y, balOK,     balClr,    FontSize);
   y += dy;

   // ── HIGH IMPACT NEWS CALENDAR ──
   y += 4;
   SetLabel(PREFIX+"NWH", x, y, "── HIGH IMPACT NEWS CALENDAR ──", ColorHeader, FontSize);
   y += dy;

   // News status line
   color nwClr = !UseNewsFilter    ? ColorNeutral :
                 g_NewsBlocked     ? ColorBear    :
                 ArraySize(g_NewsEvents) == 0 ? ColorBull : ColorWarn;
   SetLabel(PREFIX+"NW1", x, y, g_NewsStatus, nwClr, FontSize);
   y += dy;

   // Show upcoming events list (up to 4)
   int shown = 0;
   datetime now = TimeCurrent();
   for(int n = 0; n < ArraySize(g_NewsEvents) && shown < 4; n++) {
      int minsAway = (int)((g_NewsEvents[n].time - now) / 60);
      if(minsAway < -NewsMinutesAfter) continue; // already passed

      MqlDateTime evtDt;
      TimeToStruct(g_NewsEvents[n].time, evtDt);
      int phtH = (evtDt.hour + 8) % 24;

      string impact = g_NewsEvents[n].importance == 3 ? "HIGH  " : "MED   ";
      string when   = minsAway >= 0 ?
                      StringFormat("in %3d min", minsAway) : "ACTIVE";
      string evtLine = StringFormat("  [%s] %s  %s (%s)  @%02d:%02d PHT",
                                    impact,
                                    when,
                                    g_NewsEvents[n].name,
                                    g_NewsEvents[n].country,
                                    phtH, evtDt.min);
      color evtClr = (minsAway >= 0 && minsAway <= NewsMinutesBefore) ? ColorBear :
                     (minsAway < 0) ? ColorWarn : ColorText;
      SetLabel(PREFIX+"NWE"+IntegerToString(shown), x, y, evtLine, evtClr, FontSize);
      y += dy;
      shown++;
   }
   if(shown == 0 && UseNewsFilter) {
      SetLabel(PREFIX+"NWE0", x, y, "  No upcoming high impact events in next 24h", ColorBull, FontSize);
      y += dy;
   }

   // Settings summary
   string impactLevel = BlockHighOnly ? "HIGH only" : "HIGH + MEDIUM";
   string countries   = "";
   if(BlockUSD) countries += "USD ";
   if(BlockXAU) countries += "XAU ";
   if(BlockEUR) countries += "EUR ";
   SetLabel(PREFIX+"NW2", x, y,
            StringFormat("Filter: %s  |  Countries: %s  |  Block: %dmin before / %dmin after  |  Close on news: %s",
                         impactLevel, countries,
                         NewsMinutesBefore, NewsMinutesAfter,
                         CloseOnHighImpact ? "YES" : "NO"),
            ColorNeutral, FontSize);
   y += dy + 4;

   // Block reason if any
   if(g_BlockReason != "") {
      SetLabel(PREFIX+"DS5", x, y,
               StringFormat("! %s", g_BlockReason), ColorBear, FontSize);
      y += dy;
   }

   // ── CAPITAL PROTECTION STATUS ──
   y += dy;
   SetLabel(PREFIX+"CPH", x, y, "── TRADE PROTECTION ──", ColorHeader, FontSize);
   y += dy;

   // Settings summary
   SetLabel(PREFIX+"CP1", x, y,
            StringFormat("Breakeven: %s (trigger: %.1fx SL)   Trail SL: %s (start: %.1fx SL, dist: %.0f pips)",
                         UseBreakeven ? "ON" : "OFF", BreakevenTrigger,
                         UseTrailingStop ? "ON" : "OFF", TrailStart, TrailDistance),
            ColorNeutral, FontSize);
   y += dy;

   SetLabel(PREFIX+"CP2", x, y,
            StringFormat("Partial TP: %s (close %.0f%% at TP1 = 1:%.0f RR)   Full TP at 1:%.0f RR",
                         UsePartialTP ? "ON" : "OFF", PartialTPPercent, TP1_RR, TP2_RR),
            ColorNeutral, FontSize);
   y += dy;

   // Open trades protection status
   int openTrades = ArraySize(g_Trades);
   color cpColor  = openTrades > 0 ? ColorBull : ColorNeutral;
   SetLabel(PREFIX+"CP3", x, y,
            StringFormat("Open Trades: %d  |  %s", openTrades, g_ProtectionStatus),
            cpColor, FontSize);
   y += dy;

   // Show each open trade details
   for(int t = 0; t < openTrades && t < 3; t++) {
      string dir     = g_Trades[t].isBuy ? "BUY " : "SELL";
      string be      = g_Trades[t].breakEvenDone  ? "BE:Done" : "BE:Wait";
      string partial = g_Trades[t].partialTPDone  ? "TP1:Done" : "TP1:Wait";
      SetLabel(PREFIX+"CPT"+IntegerToString(t), x, y,
               StringFormat("  #%d %s | Entry:%.2f | SL:%.2f | TP1:%.2f | TP2:%.2f | %s | %s",
                            g_Trades[t].ticket, dir,
                            g_Trades[t].entryPrice, g_Trades[t].initialSL,
                            g_Trades[t].tp1Price, g_Trades[t].tp2Price,
                            be, partial),
               g_Trades[t].isBuy ? ColorBull : ColorBear, FontSize);
      y += dy;
   }

   // ── AUTO ENTRY STATUS ──
   y += dy;
   SetLabel(PREFIX+"AEH", x, y, "── AUTO ENTRY STATUS ──", ColorHeader, FontSize);
   y += dy;

   string autoMode = AutoTrade ? "AUTO TRADE: ON (will execute automatically)" :
                                 "AUTO TRADE: OFF (alerts only — you click manually)";
   color autoColor = AutoTrade ? ColorBull : ColorWarn;
   SetLabel(PREFIX+"AE1", x, y, autoMode, autoColor, FontSize);
   y += dy;

   // Scaled entry status
   if(UseScaledEntries) {
      int    curScore  = g_UseFallback ? g_FallbackScore : g_PrimaryScore;
      int    maxEnt    = GetMaxEntriesForScore(curScore);
      int    openNow2  = CountOpenTrades();
      string scaleStr  = StringFormat(
         "Scaled Entries: Score %d → %s max  |  Open: %d/%d  |  "
         "Thresholds: %d→1entry  %d→2entries  %d→3entries",
         curScore,
         maxEnt == 0 ? "0 (below threshold)" :
         maxEnt == 1 ? "1" : maxEnt == 2 ? "2" : "3",
         openNow2, maxEnt > 0 ? maxEnt : 1,
         ScaledScore1, ScaledScore2, ScaledScore3);
      color scaleClr = (maxEnt >= 3) ? ColorBull :
                       (maxEnt == 2) ? ColorWarn :
                       (maxEnt == 1) ? ColorText : ColorBear;
      SetLabel(PREFIX+"AES", x, y, scaleStr, scaleClr, FontSize);
      y += dy;
   }

   if(g_EntryLog != "") {
      color logColor = (StringFind(g_EntryLog, "ENTERED") >= 0)  ? ColorBull  :
                       (StringFind(g_EntryLog, "SIGNAL")  >= 0)  ? ColorWarn  :
                       (StringFind(g_EntryLog, "FAILED")  >= 0)  ? ColorBear  : ColorNeutral;
      SetLabel(PREFIX+"AE2", x, y, g_EntryLog, logColor, FontSize);
      y += dy;
   }

   if(g_LastTradeResult != "") {
      color resColor = (StringFind(g_LastTradeResult, "WIN") >= 0) ? ColorBull : ColorBear;
      SetLabel(PREFIX+"AE3", x, y,
               StringFormat("Last Result: %s", g_LastTradeResult), resColor, FontSize);
      y += dy;
   }

   // ── DRAWDOWN & PERIOD LIMITS ──
   y += dy;
   SetLabel(PREFIX+"DDH", x, y, "── DRAWDOWN & PERIOD LIMITS ──", ColorHeader, FontSize);
   y += dy;

   // Drawdown bar
   color ddColor = (g_CurrentDrawdown >= MaxDrawdownPct * 0.8) ? ColorBear :
                   (g_CurrentDrawdown >= MaxDrawdownPct * 0.5) ? ColorWarn : ColorBull;
   string ddBar  = "";
   int ddBars    = (int)MathMin(g_CurrentDrawdown * 2, 20);
   for(int b = 0; b < ddBars; b++) ddBar += "|";
   SetLabel(PREFIX+"DD1", x, y,
            StringFormat("Drawdown: %.2f%% / %.1f%%  [%s]   Peak: $%.2f",
                         g_CurrentDrawdown, MaxDrawdownPct, ddBar, g_PeakBalance),
            ddColor, FontSize);
   y += dy;

   // Weekly P&L
   color wkColor = g_WeeklyPnL >= 0 ? ColorBull : ColorBear;
   color wkHit   = (g_WeeklyLossHit || g_WeeklyProfitHit) ? ColorBear : ColorText;
   SetLabel(PREFIX+"WK1", x, y,
            StringFormat("Weekly P&L: %+.2f%%  (Limit: -%.1f%%  Target: +%.1f%%)   %s",
                         g_WeeklyPnL, WeeklyLossLimit, WeeklyProfitTarget,
                         g_WeeklyLossHit   ? "WEEKLY LOSS HIT" :
                         g_WeeklyProfitHit ? "WEEKLY TARGET HIT" : "Week OK"),
            g_WeeklyLossHit || g_WeeklyProfitHit ? ColorWarn : wkColor, FontSize);
   y += dy;

   // Monthly P&L
   color mnColor = g_MonthlyPnL >= 0 ? ColorBull : ColorBear;
   SetLabel(PREFIX+"MN1", x, y,
            StringFormat("Monthly P&L: %+.2f%%  (Limit: -%.1f%%  Target: +%.1f%%)   %s",
                         g_MonthlyPnL, MonthlyLossLimit, MonthlyProfitTarget,
                         g_MonthlyLossHit   ? "MONTHLY LOSS HIT" :
                         g_MonthlyProfitHit ? "MONTHLY TARGET HIT" : "Month OK"),
            g_MonthlyLossHit || g_MonthlyProfitHit ? ColorWarn : mnColor, FontSize);
   y += dy;

   // Session close status
   MqlDateTime dtsc;
   TimeToStruct(TimeGMT(), dtsc);
   bool isFridayNow = (dtsc.day_of_week == 5);
   string sessionCloseStr = g_SessionCloseDone ? "Session Close: DONE" :
                            StringFormat("Session Close: At %d:00 PHT", SessionCloseHour);
   string fridayCloseStr  = isFridayNow ?
                            (g_FridayCloseDone ? "Friday Close: DONE" :
                             StringFormat("Friday Close: At %d:00 PHT", FridayCloseHour)) :
                            "Friday Close: Standby";
   SetLabel(PREFIX+"SC1", x,       y, sessionCloseStr,
            g_SessionCloseDone ? ColorWarn : ColorText, FontSize);
   SetLabel(PREFIX+"SC2", x + 220, y, fridayCloseStr,
            g_FridayCloseDone ? ColorWarn : ColorText, FontSize);
   y += dy;

   // Idle SL tightening status
   SetLabel(PREFIX+"ID1", x, y,
            StringFormat("Idle SL Tighten: %s  (after %d bars stalled, move SL %.1f pips)",
                         TightenSLIdle ? "ON" : "OFF", IdleBarLimit, IdleSLTightenPips),
            ColorNeutral, FontSize);
   y += dy;

   // ── PERFORMANCE STATS ──
   y += dy;
   SetLabel(PREFIX+"STH", x, y, "── PERFORMANCE STATS (All-Time) ──", ColorHeader, FontSize);
   y += dy;

   double winRate = GetWinRate();
   double pf      = GetProfitFactor();
   double netPnL  = g_TotalProfit - g_TotalLoss;
   color  statsClr = netPnL >= 0 ? ColorBull : ColorBear;

   SetLabel(PREFIX+"ST1", x, y,
            StringFormat("Trades: %d  |  Wins: %d  |  Losses: %d  |  Win Rate: %.1f%%",
                         g_TotalTrades, g_TotalWins, g_TotalLosses, winRate),
            statsClr, FontSize);
   y += dy;

   SetLabel(PREFIX+"ST2", x, y,
            StringFormat("Net P&L: $%.2f  |  Profit Factor: %.2f  |  Gross Win: $%.2f  |  Gross Loss: $%.2f",
                         netPnL, pf, g_TotalProfit, g_TotalLoss),
            statsClr, FontSize);
   y += dy;

   // Journal status
   string jStatus = UseJournal ? StringFormat("Journal: ON  (%s)", JournalFileName)
                               : "Journal: OFF";
   SetLabel(PREFIX+"ST3", x, y, jStatus, ColorNeutral, FontSize);
   y += dy;

   // ── NOTIFICATIONS ──
   y += dy;
   SetLabel(PREFIX+"NTH", x, y, "── NOTIFICATIONS ──", ColorHeader, FontSize);
   y += dy;

   string pushStr  = UsePushAlert    ? "Push:ON"   : "Push:OFF";
   string emailStr = UseEmailAlert   ? "Email:ON"  : "Email:OFF";
   string soundStr = UseSoundAlert   ? "Sound:ON"  : "Sound:OFF";
   string alertStr = AlertOnSignal   ? "Alert:ON"  : "Alert:OFF";

   SetLabel(PREFIX+"NT1a", x,       y, pushStr,  UsePushAlert   ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"NT1b", x + 90,  y, emailStr, UseEmailAlert  ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"NT1c", x + 180, y, soundStr, UseSoundAlert  ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"NT1d", x + 270, y, alertStr, AlertOnSignal  ? ColorBull : ColorNeutral, FontSize);
   y += dy;

   // ── CHART VISUALS ──
   y += dy;
   SetLabel(PREFIX+"CVH", x, y, "── CHART VISUALS ──", ColorHeader, FontSize);
   y += dy;

   string obStr    = ShowOB         ? "OB:ON"     : "OB:OFF";
   string fvgStr   = ShowFVG        ? "FVG:ON"    : "FVG:OFF";
   string cvSwStr  = ShowSweep      ? "Sweep:ON"  : "Sweep:OFF";
   string bosStr   = ShowBOSArrows  ? "BOS:ON"    : "BOS:OFF";
   string tlStr    = ShowTradeLevels ? "Levels:ON" : "Levels:OFF";

   SetLabel(PREFIX+"CV1a", x,       y, obStr,    ShowOB          ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1b", x + 75,  y, fvgStr,   ShowFVG         ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1c", x + 150, y, cvSwStr,  ShowSweep       ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1d", x + 235, y, bosStr, ShowBOSArrows   ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1e", x + 310, y, tlStr,  ShowTradeLevels ? ColorBull : ColorNeutral, FontSize);
   y += dy;

   y += 4;
   // ── BACKTEST & OPTIMIZATION ──
   y += dy;
   SetLabel(PREFIX+"BTH", x, y, "── BACKTEST & OPTIMIZATION ──", ColorHeader, FontSize);
   y += dy;

   double returnPct = g_StartBalance > 0 ?
                      (AccountInfoDouble(ACCOUNT_BALANCE) - g_StartBalance)
                      / g_StartBalance * 100.0 : 0;
   double avgWin    = g_TotalWins   > 0 ? g_TotalProfit / g_TotalWins   : 0;
   double avgLoss   = g_TotalLosses > 0 ? g_TotalLoss   / g_TotalLosses : 0;
   double avgRR     = avgLoss > 0 ? avgWin / avgLoss : 0;
   double maxDD     = g_PeakBalance > 0 ?
                      (g_PeakBalance - g_MinEquity) / g_PeakBalance * 100.0 : 0;

   color retColor   = returnPct >= 0 ? ColorBull : ColorBear;
   SetLabel(PREFIX+"BT1", x, y,
            StringFormat("Return: %+.2f%%   Win Rate: %.1f%%   PF: %.2f   Avg RR: 1:%.2f",
                         returnPct, GetWinRate(), GetProfitFactor(), avgRR),
            retColor, FontSize);
   y += dy;

   SetLabel(PREFIX+"BT2", x, y,
            StringFormat("Best: $%.2f   Worst: $%.2f   Pips: %.1f   MaxDD: %.2f%%",
                         g_BestTrade, g_WorstTrade, g_TotalPips, maxDD),
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"BT3", x, y,
            StringFormat("Win Streak: %d (best: %d)   Lose Streak: %d (worst: %d)   Primary: %d  Fallback: %d",
                         g_WinStreak, g_MaxWinStreak, g_LoseStreak, g_MaxLoseStreak,
                         g_PrimaryTrades, g_FallbackTrades),
            ColorNeutral, FontSize);
   y += dy;

   string rptStr = GenerateReport ? StringFormat("Report: ON (%s)", ReportFileName)
                                  : "Report: OFF";
   SetLabel(PREFIX+"BT4", x, y, rptStr, ColorNeutral, FontSize);
   y += dy;

   y += 4;
   SetLabel(PREFIX+"UPD", x, y,
            StringFormat("v13.6 | %s | Magic: %d | %s",
                         TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS),
                         MagicNumber,
                         g_IsTesting ? "STRATEGY TESTER MODE" : "LIVE MODE"),
            ColorNeutral, FontSize - 1);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Helper — checkmark string                                        |
//+------------------------------------------------------------------+
string CheckMark(bool condition) {
   return condition ? "[X]" : "[ ]";
}

//+------------------------------------------------------------------+
//| Helper — timeframe to string                                     |
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf) {
   switch(tf) {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "?";
   }
}

//+------------------------------------------------------------------+
//| Create or update a text label                                    |
//+------------------------------------------------------------------+
void SetLabel(string name, int x, int y, string text, color clr, int fontSize) {
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetString (0, name, OBJPROP_FONT,      FontName);
}

//+------------------------------------------------------------------+
//| Create a background rectangle                                    |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color clr) {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      C'40,40,60');
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
}

//+------------------------------------------------------------------+
//| Delete all dashboard objects                                     |
//+------------------------------------------------------------------+
void DeleteDashboard() {
   ObjectsDeleteAll(0, PREFIX);
}
//+------------------------------------------------------------------+
