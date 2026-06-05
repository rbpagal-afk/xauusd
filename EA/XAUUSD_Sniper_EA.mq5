//+------------------------------------------------------------------+
//|  XAUUSD Sniper Entry EA                                          |
//|  Multi-Timeframe Confluence Dashboard                            |
//|  Timeframes: H4 > H1 > M15 (Primary) | H1 > M15 > M5 (Fallback)|
//|  Attach to ANY timeframe — dashboard always works                |
//+------------------------------------------------------------------+
#property copyright   "XAUUSD Sniper Strategy"
#property version     "1.00"
#property description "Multi-TF Sniper Dashboard for XAUUSD"
#property strict

//--- Inputs
input group            "=== STRATEGY SETTINGS ==="
input int              BOS_Lookback      = 50;     // BOS lookback bars
input int              OB_Lookback       = 10;     // Order Block lookback bars
input int              FVG_Lookback      = 5;      // FVG lookback bars
input int              Sweep_Lookback    = 5;      // Liquidity Sweep lookback bars
input int              MinPrimaryScore   = 7;      // Min score for primary trade
input int              MinFallbackScore  = 9;      // Min score for fallback trade

input group            "=== RISK MANAGEMENT ==="
input double           PrimaryRisk       = 2.0;    // Primary risk % per trade
input double           FallbackRisk      = 1.0;    // Fallback risk % per trade
input double           MinRR             = 2.0;    // Minimum Risk:Reward

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

//+------------------------------------------------------------------+
//| Structure to hold analysis for one timeframe                     |
//+------------------------------------------------------------------+
struct TFAnalysis {
   string   name;
   bool     bullish;
   bool     hasBOS;
   bool     hasCHoCH;
   bool     hasOB;
   bool     hasFVG;
   bool     hasLiqSweep;
   bool     inDiscount;
   bool     inPremium;
   double   obHigh;
   double   obLow;
   string   narrative;
};

//--- Global state
TFAnalysis g_H4, g_H1, g_M15, g_M5;
int        g_PrimaryScore   = 0;
int        g_FallbackScore  = 0;
string     g_Session        = "";
string     g_Recommendation = "";
bool       g_UseFallback    = false;
datetime   g_LastUpdate     = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetTimer(5); // Update every 5 seconds
   CreateDashboard();
   AnalyzeAllTimeframes();
   UpdateDashboard();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   EventKillTimer();
   DeleteDashboard();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   AnalyzeAllTimeframes();
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Timer — keeps dashboard alive on any TF                         |
//+------------------------------------------------------------------+
void OnTimer() {
   AnalyzeAllTimeframes();
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Chart event — redraw if chart changes                           |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam) {
   if(id == CHARTEVENT_CHART_CHANGE) {
      DeleteDashboard();
      CreateDashboard();
      UpdateDashboard();
   }
}

//+------------------------------------------------------------------+
//| Analyze all timeframes                                           |
//+------------------------------------------------------------------+
void AnalyzeAllTimeframes() {
   g_H4  = AnalyzeTF(TF_H4,  "H4");
   g_H1  = AnalyzeTF(TF_H1,  "H1");
   g_M15 = AnalyzeTF(TF_M15, "M15");
   g_M5  = AnalyzeTF(TF_M5,  "M5");

   g_PrimaryScore  = ScorePrimary();
   g_FallbackScore = ScoreFallback();
   g_Session       = GetSession();
   g_UseFallback   = (g_PrimaryScore < MinPrimaryScore);
   g_Recommendation = GetRecommendation();
}

//+------------------------------------------------------------------+
//| Analyze a single timeframe                                       |
//+------------------------------------------------------------------+
TFAnalysis AnalyzeTF(ENUM_TIMEFRAMES tf, string name) {
   TFAnalysis a;
   a.name = name;

   // Get candle data — safely handles any timeframe
   int bars = iBars(_Symbol, tf);
   if(bars < BOS_Lookback + 10) {
      a.narrative = "Waiting for data...";
      return a;
   }

   double high[], low[], close[], open[];
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(open,  true);

   if(CopyHigh (_Symbol, tf, 0, BOS_Lookback, high)  < BOS_Lookback ||
      CopyLow  (_Symbol, tf, 0, BOS_Lookback, low)   < BOS_Lookback ||
      CopyClose(_Symbol, tf, 0, BOS_Lookback, close) < BOS_Lookback ||
      CopyOpen (_Symbol, tf, 0, BOS_Lookback, open)  < BOS_Lookback) {
      a.narrative = "Loading data...";
      return a;
   }

   // --- BOS Detection ---
   double swingHigh = high[ArrayMaximum(high, 1, BOS_Lookback - 1)];
   double swingLow  = low [ArrayMinimum(low,  1, BOS_Lookback - 1)];

   a.hasBOS   = false;
   a.bullish  = false;

   // Bullish BOS: current close breaks above recent swing high
   if(close[0] > swingHigh) {
      a.hasBOS  = true;
      a.bullish = true;
   }
   // Bearish BOS: current close breaks below recent swing low
   else if(close[0] < swingLow) {
      a.hasBOS  = true;
      a.bullish = false;
   }
   else {
      // No BOS — use trend of last few candles
      a.bullish = (close[0] > close[MathMin(5, BOS_Lookback-1)]);
   }

   // --- Premium / Discount ---
   double rangeHigh = high[ArrayMaximum(high, 0, BOS_Lookback)];
   double rangeLow  = low [ArrayMinimum(low,  0, BOS_Lookback)];
   double rangeMid  = (rangeHigh + rangeLow) / 2.0;
   a.inDiscount = (close[0] < rangeMid);
   a.inPremium  = (close[0] > rangeMid);

   // --- Order Block Detection ---
   a.hasOB   = false;
   a.obHigh  = 0;
   a.obLow   = 0;
   int obLookback = MathMin(OB_Lookback, BOS_Lookback - 2);
   for(int i = 1; i < obLookback; i++) {
      bool bigMoveUp   = (close[i-1] - open[i-1]) > 2 * (close[i] - open[i]) && close[i-1] > open[i-1];
      bool bigMoveDown = (open[i-1] - close[i-1]) > 2 * (open[i] - close[i]) && close[i-1] < open[i-1];
      if(a.bullish && bigMoveUp && open[i] > close[i]) {
         a.hasOB  = true;
         a.obHigh = high[i];
         a.obLow  = low[i];
         break;
      }
      if(!a.bullish && bigMoveDown && open[i] < close[i]) {
         a.hasOB  = true;
         a.obHigh = high[i];
         a.obLow  = low[i];
         break;
      }
   }

   // --- FVG Detection ---
   a.hasFVG = false;
   int fvgLookback = MathMin(FVG_Lookback + 2, BOS_Lookback - 2);
   for(int i = 1; i < fvgLookback; i++) {
      // Bullish FVG: gap between candle[i+1] high and candle[i-1] low
      if(a.bullish && low[i-1] > high[i+1]) {
         a.hasFVG = true;
         break;
      }
      // Bearish FVG: gap between candle[i+1] low and candle[i-1] high
      if(!a.bullish && high[i-1] < low[i+1]) {
         a.hasFVG = true;
         break;
      }
   }

   // --- CHoCH Detection ---
   a.hasCHoCH = false;
   // Look for a swing that breaks in the opposite direction then recovers
   if(BOS_Lookback >= 6) {
      double recentHigh = high[ArrayMaximum(high, 1, 5)];
      double recentLow  = low [ArrayMinimum(low,  1, 5)];
      double prevHigh   = high[ArrayMaximum(high, 6, MathMin(15, BOS_Lookback-6))];
      double prevLow    = low [ArrayMinimum(low,  6, MathMin(15, BOS_Lookback-6))];

      // Bullish CHoCH: was making lower highs, now breaks above previous high
      if(a.bullish && recentHigh > prevHigh && close[0] > recentHigh)
         a.hasCHoCH = true;
      // Bearish CHoCH: was making higher lows, now breaks below previous low
      if(!a.bullish && recentLow < prevLow && close[0] < recentLow)
         a.hasCHoCH = true;
   }

   // --- Liquidity Sweep Detection ---
   a.hasLiqSweep = false;
   int sweepLookback = MathMin(Sweep_Lookback + 1, BOS_Lookback - 1);
   for(int i = 1; i < sweepLookback; i++) {
      double prevSwingLow  = low [ArrayMinimum(low,  i+1, MathMin(10, BOS_Lookback-i-1))];
      double prevSwingHigh = high[ArrayMaximum(high, i+1, MathMin(10, BOS_Lookback-i-1))];
      // Bullish sweep: wick went below swing low but closed back above
      if(a.bullish && low[i] < prevSwingLow && close[i] > prevSwingLow) {
         a.hasLiqSweep = true;
         break;
      }
      // Bearish sweep: wick went above swing high but closed back below
      if(!a.bullish && high[i] > prevSwingHigh && close[i] < prevSwingHigh) {
         a.hasLiqSweep = true;
         break;
      }
   }

   // --- Build Narrative ---
   string dir    = a.bullish ? "BULLISH" : "BEARISH";
   string zone   = a.inDiscount ? "Discount" : (a.inPremium ? "Premium" : "Mid-Range");
   string bos    = a.hasBOS      ? "BOS ✓"       : "No BOS";
   string choch  = a.hasCHoCH    ? "CHoCH ✓"     : "No CHoCH";
   string ob     = a.hasOB       ? "OB ✓"        : "No OB";
   string fvg    = a.hasFVG      ? "FVG ✓"       : "No FVG";
   string sweep  = a.hasLiqSweep ? "Sweep ✓"     : "No Sweep";

   a.narrative = StringFormat("%s | %s | %s | %s | %s | %s | %s",
                              dir, zone, bos, choch, ob, fvg, sweep);
   return a;
}

//+------------------------------------------------------------------+
//| Score primary strategy H4/H1/M15                                |
//+------------------------------------------------------------------+
int ScorePrimary() {
   int score = 0;
   if(g_H4.hasBOS && g_H4.bullish == g_H1.bullish)  score += 2; // H4 BOS aligned
   if((g_H4.bullish && g_H4.inDiscount) ||
      (!g_H4.bullish && g_H4.inPremium))              score += 1; // Correct zone
   if(g_H4.hasOB)                                     score += 2; // H4 OB
   if(g_H1.hasCHoCH && g_H1.bullish == g_H4.bullish) score += 2; // H1 CHoCH
   if(g_H1.hasFVG && g_H1.hasOB)                     score += 1; // H1 FVG+OB
   if(g_M15.hasLiqSweep)                              score += 2; // M15 Sweep
   if(g_M15.hasCHoCH)                                 score += 1; // M15 CHoCH
   if(g_M15.hasFVG)                                   score += 1; // M15 FVG
   if(g_M15.hasOB)                                    score += 1; // M15 confirmation
   return score;
}

//+------------------------------------------------------------------+
//| Score fallback strategy H1/M15/M5                               |
//+------------------------------------------------------------------+
int ScoreFallback() {
   int score = 0;
   if(g_H1.hasBOS && g_H1.bullish == g_M15.bullish)  score += 2;
   if((g_H1.bullish && g_H1.inDiscount) ||
      (!g_H1.bullish && g_H1.inPremium))              score += 1;
   if(g_H1.hasOB)                                     score += 2;
   if(g_M15.hasCHoCH && g_M15.bullish == g_H1.bullish) score += 2;
   if(g_M15.hasFVG && g_M15.hasOB)                   score += 1;
   if(g_M5.hasLiqSweep)                               score += 2;
   if(g_M5.hasCHoCH)                                  score += 1;
   if(g_M5.hasFVG)                                    score += 1;
   if(g_M5.hasOB)                                     score += 1;
   return score;
}

//+------------------------------------------------------------------+
//| Get current session in PHT (UTC+8)                              |
//+------------------------------------------------------------------+
string GetSession() {
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hour = dt.hour;

   // Convert UTC to PHT (+8)
   int pht = (hour + 8) % 24;

   if(pht >= 8  && pht < 15)  return "Asian Session (Prepare Only)";
   if(pht >= 15 && pht < 17)  return "London Open — TRADE WINDOW 1";
   if(pht >= 17 && pht < 20)  return "London Session (Selective)";
   if(pht >= 20 && pht < 22)  return "New York Open — TRADE WINDOW 2 (BEST)";
   if(pht >= 22)               return "After Hours — Close Charts & Rest";
   return "Pre-Market — Prepare Charts";
}

//+------------------------------------------------------------------+
//| Build trade recommendation                                       |
//+------------------------------------------------------------------+
string GetRecommendation() {
   bool inTradeSession = (g_Session == "London Open — TRADE WINDOW 1" ||
                          g_Session == "New York Open — TRADE WINDOW 2 (BEST)" ||
                          g_Session == "London Session (Selective)");

   if(!inTradeSession)
      return "NOT IN TRADING SESSION — PREPARE ONLY";

   // Primary strategy
   if(g_PrimaryScore >= MinPrimaryScore) {
      string dir = g_H4.bullish ? "BUY" : "SELL";
      return StringFormat("PRIMARY TRADE: %s | Score %d/13 | Risk %.1f%%",
                          dir, g_PrimaryScore, PrimaryRisk);
   }

   // Fallback strategy
   if(g_FallbackScore >= MinFallbackScore) {
      string dir = g_H1.bullish ? "BUY" : "SELL";
      return StringFormat("FALLBACK TRADE: %s | Score %d/13 | Risk %.1f%%",
                          dir, g_FallbackScore, FallbackRisk);
   }

   return StringFormat("NO TRADE — Primary: %d/13 | Fallback: %d/13 | Wait",
                       g_PrimaryScore, g_FallbackScore);
}

//+------------------------------------------------------------------+
//| Dashboard creation — all labels                                 |
//+------------------------------------------------------------------+
void CreateDashboard() {
   // Background rectangle
   CreateRect(PREFIX+"BG", Dashboard_X - 5, Dashboard_Y - 5,
              DASH_WIDTH, ROW_HEIGHT * 26 + 10, ColorBG);
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

   // Current time PHT
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int pht = (dt.hour + 8) % 24;
   SetLabel(PREFIX+"T1", x, y,
            StringFormat("PHT Time: %02d:%02d  |  Chart TF: %s  |  Symbol: %s",
                         pht, dt.min, TFToString(Period()), _Symbol),
            ColorNeutral, FontSize);
   y += dy;

   // Session
   color sessionColor = (StringFind(g_Session, "TRADE") >= 0) ? ColorBull :
                        (StringFind(g_Session, "Prepare") >= 0 ||
                         StringFind(g_Session, "After") >= 0) ? ColorWarn : ColorNeutral;
   SetLabel(PREFIX+"T2", x, y,
            StringFormat("Session: %s", g_Session), sessionColor, FontSize);
   y += dy + 4;

   // ── PRIMARY STRATEGY ──
   SetLabel(PREFIX+"PH", x, y, "── PRIMARY STRATEGY: H4 → H1 → M15 ──",
            ColorHeader, FontSize);
   y += dy;

   // H4
   color h4c = g_H4.bullish ? ColorBull : ColorBear;
   SetLabel(PREFIX+"H4L", x, y, "H4  │", ColorHeader, FontSize);
   SetLabel(PREFIX+"H4V", x + 45, y, g_H4.narrative, h4c, FontSize);
   y += dy;

   // H1
   color h1c = g_H1.bullish ? ColorBull : ColorBear;
   SetLabel(PREFIX+"H1L", x, y, "H1  │", ColorHeader, FontSize);
   SetLabel(PREFIX+"H1V", x + 45, y, g_H1.narrative, h1c, FontSize);
   y += dy;

   // M15
   color m15c = g_M15.bullish ? ColorBull : ColorBear;
   SetLabel(PREFIX+"M15L", x, y, "M15 │", ColorHeader, FontSize);
   SetLabel(PREFIX+"M15V", x + 45, y, g_M15.narrative, m15c, FontSize);
   y += dy;

   // Primary Score
   color psColor = (g_PrimaryScore >= MinPrimaryScore) ? ColorBull :
                   (g_PrimaryScore >= 5) ? ColorWarn : ColorBear;
   SetLabel(PREFIX+"PS", x, y,
            StringFormat("Primary Score: %d / 13   (Need %d to trade)",
                         g_PrimaryScore, MinPrimaryScore),
            psColor, FontSize);
   y += dy + 4;

   // ── FALLBACK STRATEGY ──
   SetLabel(PREFIX+"FH", x, y, "── FALLBACK STRATEGY: H1 → M15 → M5 ──",
            ColorHeader, FontSize);
   y += dy;

   // H1 (reused)
   SetLabel(PREFIX+"FH1L", x, y, "H1  │", ColorHeader, FontSize);
   SetLabel(PREFIX+"FH1V", x + 45, y, g_H1.narrative, h1c, FontSize);
   y += dy;

   // M15 (reused)
   SetLabel(PREFIX+"FM15L", x, y, "M15 │", ColorHeader, FontSize);
   SetLabel(PREFIX+"FM15V", x + 45, y, g_M15.narrative, m15c, FontSize);
   y += dy;

   // M5
   color m5c = g_M5.bullish ? ColorBull : ColorBear;
   SetLabel(PREFIX+"M5L", x, y, "M5  │", ColorHeader, FontSize);
   SetLabel(PREFIX+"M5V", x + 45, y, g_M5.narrative, m5c, FontSize);
   y += dy;

   // Fallback Score
   color fsColor = (g_FallbackScore >= MinFallbackScore) ? ColorBull :
                   (g_FallbackScore >= 6) ? ColorWarn : ColorBear;
   SetLabel(PREFIX+"FS", x, y,
            StringFormat("Fallback Score: %d / 13  (Need %d to trade)",
                         g_FallbackScore, MinFallbackScore),
            fsColor, FontSize);
   y += dy + 4;

   // ── CONFLUENCE CHECKLIST ──
   SetLabel(PREFIX+"CH", x, y, "── CONFLUENCE CHECKLIST ──", ColorHeader, FontSize);
   y += dy;

   // Primary checklist
   SetLabel(PREFIX+"C1", x, y,
            CheckMark(g_H4.hasBOS)       + " H4 BOS   " +
            CheckMark(g_H4.hasOB)        + " H4 OB    " +
            CheckMark(g_H4.inDiscount || g_H4.inPremium) + " H4 Zone",
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"C2", x, y,
            CheckMark(g_H1.hasCHoCH)     + " H1 CHoCH " +
            CheckMark(g_H1.hasOB)        + " H1 OB    " +
            CheckMark(g_H1.hasFVG)       + " H1 FVG",
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"C3", x, y,
            CheckMark(g_M15.hasLiqSweep) + " M15 Sweep" +
            CheckMark(g_M15.hasCHoCH)    + " M15 CHoCH" +
            CheckMark(g_M15.hasFVG)      + " M15 FVG",
            ColorText, FontSize);
   y += dy;

   SetLabel(PREFIX+"C4", x, y,
            CheckMark(g_M5.hasLiqSweep)  + " M5 Sweep " +
            CheckMark(g_M5.hasCHoCH)     + " M5 CHoCH " +
            CheckMark(g_M5.hasFVG)       + " M5 FVG",
            ColorText, FontSize);
   y += dy + 4;

   // ── RECOMMENDATION ──
   SetLabel(PREFIX+"RH", x, y, "── TRADE RECOMMENDATION ──", ColorHeader, FontSize);
   y += dy;

   color recColor = (StringFind(g_Recommendation, "PRIMARY TRADE") >= 0)  ? ColorBull  :
                    (StringFind(g_Recommendation, "FALLBACK TRADE") >= 0) ? ColorWarn  :
                    (StringFind(g_Recommendation, "NO TRADE") >= 0)       ? ColorBear  : ColorNeutral;
   SetLabel(PREFIX+"REC", x, y, g_Recommendation, recColor, FontSize);
   y += dy;

   // Last updated
   SetLabel(PREFIX+"UPD", x, y,
            StringFormat("Last updated: %s", TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS)),
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
