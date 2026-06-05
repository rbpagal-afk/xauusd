//+------------------------------------------------------------------+
//|  XAUUSD Sniper Entry EA                                          |
//|  Multi-Timeframe Confluence Dashboard                            |
//|  Timeframes: H4 > H1 > M15 (Primary) | H1 > M15 > M5 (Fallback)|
//|  Attach to ANY timeframe — dashboard always works                |
//|  Capital Protection: Full suite including daily limits & news    |
//+------------------------------------------------------------------+
#property copyright   "XAUUSD Sniper Strategy"
#property version     "5.00"
#property description "XAUUSD Sniper EA — Chart Visuals + Journal + Notifications"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         Trade;
CPositionInfo  PositionInfo;

//--- Inputs
input group            "=== STRATEGY SETTINGS ==="
input int              BOS_Lookback      = 50;     // BOS lookback bars
input int              OB_Lookback       = 10;     // Order Block lookback bars
input int              FVG_Lookback      = 5;      // FVG lookback bars
input int              Sweep_Lookback    = 5;      // Liquidity Sweep lookback bars
input int              MinPrimaryScore   = 7;      // Min score for primary trade
input int              MinFallbackScore  = 9;      // Min score for fallback trade

input group            "=== RISK PER TRADE ==="
input double           PrimaryRisk       = 2.0;    // Primary risk % per trade
input double           FallbackRisk      = 1.0;    // Fallback risk % per trade
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

input group            "=== SPREAD & SLIPPAGE FILTER ==="
input double           MaxSpreadPips     = 30.0;   // Max allowed spread in pips
input int              MaxSlippagePips   = 3;       // Max slippage in pips

input group            "=== NEWS FILTER ==="
input bool             UseNewsFilter     = true;   // Block trades near news
input int              NewsMinutesBefore = 30;     // Minutes before news to block
input int              NewsMinutesAfter  = 30;     // Minutes after news to block

input group            "=== ACCOUNT FLOOR ==="
input bool             UseBalanceFloor   = true;   // Stop trading below minimum balance
input double           MinBalanceUSD     = 100.0;  // Minimum account balance in USD

input group            "=== AUTO TRADE ENTRY ==="
input bool             AutoTrade         = false;  // Enable auto trade execution (false = alerts only)
input bool             AlertOnSignal     = true;   // Send alert when signal is ready
input int              MagicNumber       = 202401; // EA magic number
input double           SL_BufferPips     = 5.0;    // Extra pips beyond sweep for SL
input int              CooldownBars      = 3;      // Bars to wait after last trade before new entry
input bool             OneTradeAtATime   = true;   // Allow only 1 open trade at a time

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

//--- News event times (UTC) — major events affecting XAUUSD
//    Format: hour * 100 + minute (e.g. 1330 = 13:30 UTC)
//    These are fixed weekly/monthly schedule times
int g_NewsEvents[] = {
   1330,   // US CPI / NFP / GDP (13:30 UTC = 21:30 PHT)
   1800,   // Fed Rate Decision (18:00 UTC = 02:00 PHT next day)
   1400,   // FOMC Minutes (14:00 UTC = 22:00 PHT)
   1500    // US Retail Sales (15:00 UTC = 23:00 PHT)
};

//--- Lot size calculator state
double     g_LastLotSize       = 0;
string     g_BlockReason       = "";     // Why trading is blocked

//--- Auto entry state
datetime   g_LastEntryBar      = 0;
int        g_LastSignalScore   = 0;
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

//--- Visual tracking — avoid redrawing every tick
datetime   g_LastVisualBar     = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit() {
   EventSetTimer(5);
   Trade.SetDeviationInPoints(MaxSlippagePips * 10);
   Trade.SetExpertMagicNumber(MagicNumber);
   ResetDailyTracking();
   InitJournal();
   CreateDashboard();
   AnalyzeAllTimeframes();
   DrawChartVisuals();
   UpdateDashboard();
   return INIT_SUCCEEDED;
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
//| Check if near a scheduled news event                           |
//+------------------------------------------------------------------+
bool IsNearNews() {
   if(!UseNewsFilter) return false;
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int nowHHMM = dt.hour * 100 + dt.min;

   for(int i = 0; i < ArraySize(g_NewsEvents); i++) {
      int newsHHMM  = g_NewsEvents[i];
      int newsTotal = (newsHHMM / 100) * 60 + (newsHHMM % 100);
      int nowTotal  = dt.hour * 60 + dt.min;
      int diff      = nowTotal - newsTotal;

      if(diff >= -NewsMinutesBefore && diff <= NewsMinutesAfter)
         return true;
   }
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
   if(!IsBalanceOK()) {
      g_BlockReason = StringFormat("Balance below floor ($%.2f)", MinBalanceUSD);
      return false;
   }
   if(g_DailyProfitHit) {
      g_BlockReason = StringFormat("Daily profit target hit: +%.2f%%  — Come back tomorrow",
                                    DailyProfitTarget);
      return false;
   }
   if(g_DailyLossHit) {
      g_BlockReason = StringFormat("Daily loss limit hit: -%.2f%%  — Come back tomorrow",
                                    DailyLossLimit);
      return false;
   }
   if(g_MaxTradesHit) {
      g_BlockReason = StringFormat("Max daily trades reached (%d)", MaxDailyTrades);
      return false;
   }
   if(g_ConsecLossHit) {
      g_BlockReason = StringFormat("Max consecutive losses (%d) — Stop for today",
                                    MaxConsecLosses);
      return false;
   }
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
   CheckNewDay();
   UpdateDailyPnL();
   ManageCapitalProtection();
   AnalyzeAllTimeframes();
   TryAutoEntry();
   // Redraw visuals only on new bar to save CPU
   datetime curBar = iTime(_Symbol, TF_M15, 0);
   if(curBar != g_LastVisualBar) {
      DrawChartVisuals();
      g_LastVisualBar = curBar;
   }
   UpdateDashboard();
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
      long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT) {
         double profit  = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
         bool   wasWin  = (profit > 0);
         ulong  dealTicket = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         OnTradeClose(wasWin);
         g_LastTradeResult = StringFormat("%s  $%.2f  (%s)",
                             TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
                             profit, wasWin ? "WIN" : "LOSS");

         // Find trade state for journal
         int idx = FindTradeState(dealTicket);
         if(idx >= 0) {
            TradeState ts = g_Trades[idx];
            double exitPrice = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            string strat = g_UseFallback ? "FALLBACK" : "PRIMARY";
            JournalWriteTrade(dealTicket, strat, g_LastSignalScore,
                              ts.entryPrice, ts.initialSL, ts.tp1Price, ts.tp2Price,
                              ts.lotSize, ts.isBuy ? PrimaryRisk : FallbackRisk,
                              MathAbs(ts.entryPrice - ts.initialSL) /
                              (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10),
                              exitPrice, profit, ts.isBuy,
                              ts.breakEvenDone, ts.partialTPDone, UseTrailingStop);
            SendTradeResultNotification(wasWin, profit, dealTicket, strat);
         }

         // Notify if daily limit was just triggered
         if(g_DailyLossHit || g_DailyProfitHit || g_ConsecLossHit)
            SendDailyLimitNotification(g_BlockReason);

         g_AlertSent = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Auto Entry — fires when confluence score meets threshold         |
//+------------------------------------------------------------------+
void TryAutoEntry() {
   if(!IsTradingAllowed()) return;

   // Only enter during valid sessions
   bool inSession = (g_Session == "London Open — TRADE WINDOW 1"      ||
                     g_Session == "New York Open — TRADE WINDOW 2 (BEST)" ||
                     g_Session == "London Session (Selective)");
   if(!inSession) { g_AlertSent = false; return; }

   // Check cooldown — wait CooldownBars after last trade
   datetime currentBar = iTime(_Symbol, TF_M15, 0);
   if(currentBar == g_LastEntryBar) return;

   // One trade at a time check
   if(OneTradeAtATime && CountOpenTrades() > 0) return;

   // Determine which strategy triggered
   bool   primaryReady  = (g_PrimaryScore  >= MinPrimaryScore);
   bool   fallbackReady = (g_FallbackScore >= MinFallbackScore) && !primaryReady;
   if(!primaryReady && !fallbackReady) { g_AlertSent = false; return; }

   bool   isBuy     = primaryReady ? g_H4.bullish : g_H1.bullish;
   int    score     = primaryReady ? g_PrimaryScore : g_FallbackScore;
   double riskPct   = primaryReady ? PrimaryRisk : FallbackRisk;
   string strategy  = primaryReady ? "PRIMARY" : "FALLBACK";

   // Avoid re-alerting same signal
   if(g_AlertSent && score == g_LastSignalScore) return;

   // Calculate SL from recent sweep wick
   double pip    = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   double slRef  = GetSweepLevel(isBuy, primaryReady ? TF_M15 : TF_M5);
   double slPips = MathAbs((isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                                  : SymbolInfoDouble(_Symbol, SYMBOL_BID)) - slRef)
                   / pip + SL_BufferPips;
   slPips = MathMax(slPips, 10.0); // Minimum 10 pip SL

   // Check minimum RR
   double tp2Pips = slPips * TP2_RR;
   if(tp2Pips / slPips < MinRR) return;

   // Calculate lot size using exact SL
   double lots = CalcLotSize(riskPct, slPips);
   g_LastLotSize = lots;

   // Build prices
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry  = isBuy ? ask : bid;
   double sl     = isBuy ? entry - slPips * pip : entry + slPips * pip;
   double tp1    = isBuy ? entry + slPips * TP1_RR * pip : entry - slPips * TP1_RR * pip;
   double tp2    = isBuy ? entry + slPips * TP2_RR * pip : entry - slPips * TP2_RR * pip;

   sl  = NormalizeDouble(sl,  _Digits);
   tp2 = NormalizeDouble(tp2, _Digits);

   string comment = StringFormat("Sniper %s %s Sc:%d", strategy, isBuy?"BUY":"SELL", score);

   // Alert regardless of AutoTrade setting
   if(!g_AlertSent) {
      SendSignalNotification(strategy, isBuy, score, entry, sl, tp1, tp2, riskPct, lots);
      g_AlertSent       = true;
      g_LastSignalScore = score;
      g_EntryLog = StringFormat("SIGNAL: %s %s | Score:%d | Entry:%.2f SL:%.2f TP1:%.2f TP2:%.2f | Lots:%.2f",
                                strategy, isBuy?"BUY":"SELL", score, entry, sl, tp1, tp2, lots);
   }

   // Auto execute if enabled
   if(!AutoTrade) return;

   bool ok = false;
   if(isBuy)
      ok = Trade.Buy(lots, _Symbol, ask, sl, tp2, comment);
   else
      ok = Trade.Sell(lots, _Symbol, bid, sl, tp2, comment);

   if(ok) {
      g_LastEntryBar = currentBar;
      g_EntryLog = StringFormat("ENTERED: %s %s | Score:%d | Entry:%.2f SL:%.2f TP2:%.2f | Lots:%.2f | #%d",
                                strategy, isBuy?"BUY":"SELL", score,
                                entry, sl, tp2, lots, Trade.ResultOrder());
   } else {
      g_EntryLog = StringFormat("ENTRY FAILED: Error %d — %s",
                                Trade.ResultRetcode(), Trade.ResultRetcodeDescription());
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
   for(int i = 0; i < PositionsTotal(); i++) {
      if(PositionInfo.SelectByIndex(i))
         if(PositionInfo.Symbol() == _Symbol &&
            PositionInfo.Magic()  == MagicNumber)
            count++;
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
      if(PositionInfo.Symbol() != _Symbol) continue;

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
         idx = RegisterTrade(ticket, entry, currentSL, isBuy, lots);
         if(idx < 0) continue;
      }

      // ── PARTIAL TP — Close 50% at TP1 (1:1 RR) ──
      if(UsePartialTP && !g_Trades[idx].partialTPDone) {
         double tp1Distance = slDistance * TP1_RR;
         if(profit >= tp1Distance) {
            double closeVolume = NormalizeDouble(lots * PartialTPPercent / 100.0,
                                                SymbolInfoInteger(_Symbol, SYMBOL_VOLUME_STEP) > 0 ? 2 : 2);
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
                  bool isBuy, double lots) {
   double pip       = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
   double slDist    = MathAbs(entry - sl);

   int idx = ArraySize(g_Trades);
   ArrayResize(g_Trades, idx + 1);

   g_Trades[idx].ticket        = ticket;
   g_Trades[idx].breakEvenDone = false;
   g_Trades[idx].partialTPDone = false;
   g_Trades[idx].entryPrice    = entry;
   g_Trades[idx].initialSL     = sl;
   g_Trades[idx].isBuy         = isBuy;
   g_Trades[idx].lotSize       = lots;
   g_Trades[idx].tp1Price      = isBuy ? entry + slDist * TP1_RR
                                        : entry - slDist * TP1_RR;
   g_Trades[idx].tp2Price      = isBuy ? entry + slDist * TP2_RR
                                        : entry - slDist * TP2_RR;
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
   // Check master gate first
   if(!IsTradingAllowed())
      return StringFormat("BLOCKED: %s", g_BlockReason);

   bool inTradeSession = (g_Session == "London Open — TRADE WINDOW 1" ||
                          g_Session == "New York Open — TRADE WINDOW 2 (BEST)" ||
                          g_Session == "London Session (Selective)");

   if(!inTradeSession)
      return "NOT IN TRADING SESSION — PREPARE ONLY";

   // Primary strategy
   if(g_PrimaryScore >= MinPrimaryScore) {
      string dir   = g_H4.bullish ? "BUY" : "SELL";
      double slPips = 15.0; // Estimated — replaced by actual SL on entry
      double lots   = CalcLotSize(PrimaryRisk, slPips);
      g_LastLotSize = lots;
      return StringFormat("PRIMARY TRADE: %s | Score %d/13 | Risk %.1f%% | Lots: %.2f",
                          dir, g_PrimaryScore, PrimaryRisk, lots);
   }

   // Fallback strategy
   if(g_FallbackScore >= MinFallbackScore) {
      string dir   = g_H1.bullish ? "BUY" : "SELL";
      double slPips = 10.0;
      double lots   = CalcLotSize(FallbackRisk, slPips);
      g_LastLotSize = lots;
      return StringFormat("FALLBACK TRADE: %s | Score %d/13 | Risk %.1f%% | Lots: %.2f",
                          dir, g_FallbackScore, FallbackRisk, lots);
   }

   return StringFormat("NO TRADE — Primary: %d/13 | Fallback: %d/13 | Wait for confluence",
                       g_PrimaryScore, g_FallbackScore);
}

//+------------------------------------------------------------------+
//|  TRADE JOURNAL                                                   |
//+------------------------------------------------------------------+

void InitJournal() {
   if(!UseJournal) return;
   g_JournalPath = TerminalInfoString(TERMINAL_DATA_PATH) +
                   "\\MQL5\\Files\\" + JournalFileName;

   // Create file with header if it does not exist
   if(!FileIsExist(JournalFileName, FILE_COMMON)) {
      int fh = FileOpen(JournalFileName, FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
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
   int fh = FileOpen(JournalFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON, ',');
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
}

double GetProfitFactor() {
   return g_TotalLoss > 0 ? g_TotalProfit / g_TotalLoss : 0;
}

double GetWinRate() {
   return g_TotalTrades > 0 ? (double)g_TotalWins / g_TotalTrades * 100.0 : 0;
}

//+------------------------------------------------------------------+
//|  CHART VISUALS                                                   |
//+------------------------------------------------------------------+

void DrawChartVisuals() {
   // Clear old visual objects
   ObjectsDeleteAll(0, "VIS_");

   if(ShowOB)      DrawOrderBlocks();
   if(ShowFVG)     DrawFVGZones();
   if(ShowSweep)   DrawSweepLines();
   if(ShowBOSArrows || ShowCHoCHArrows) DrawStructureArrows();
   DrawTradeLevelLines();
}

void DrawOrderBlocks() {
   // Draw H4 OB
   if(g_H4.hasOB && g_H4.obHigh > 0)
      DrawBox("VIS_OB_H4", TF_H4, g_H4.obHigh, g_H4.obLow,
              g_H4.bullish ? ColorOB_Bull : ColorOB_Bear, "H4 OB");
   // Draw H1 OB
   if(g_H1.hasOB && g_H1.obHigh > 0)
      DrawBox("VIS_OB_H1", TF_H1, g_H1.obHigh, g_H1.obLow,
              g_H1.bullish ? ColorOB_Bull : ColorOB_Bear, "H1 OB");
   // Draw M15 OB
   if(g_M15.hasOB && g_M15.obHigh > 0)
      DrawBox("VIS_OB_M15", TF_M15, g_M15.obHigh, g_M15.obLow,
              g_M15.bullish ? ColorOB_Bull : ColorOB_Bear, "M15 OB");
}

void DrawBox(string name, ENUM_TIMEFRAMES tf, double hi, double lo,
             color clr, string label) {
   datetime t1 = iTime(_Symbol, tf, OB_Lookback);
   datetime t2 = iTime(_Symbol, tf, 0) + PeriodSeconds(tf) * 20;

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
                  TFAnalysis &a, string label) {
   if(!a.hasFVG) return;

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
      if(fvgHi > 0 && fvgLo > 0) {
         datetime t1 = iTime(_Symbol, tf, i + 1);
         datetime t2 = iTime(_Symbol, tf, 0) + PeriodSeconds(tf) * 15;
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
                    TFAnalysis &a, string label) {
   if(!a.hasLiqSweep) return;
   double arr[];
   ArraySetAsSeries(arr, true);
   int lookback = MathMin(Sweep_Lookback + 2, 20);
   double level = 0;

   if(a.bullish) {
      if(CopyLow(_Symbol, tf, 1, lookback, arr) < lookback) return;
      level = arr[ArrayMinimum(arr, 0, lookback)];
   } else {
      if(CopyHigh(_Symbol, tf, 1, lookback, arr) < lookback) return;
      level = arr[ArrayMaximum(arr, 0, lookback)];
   }
   if(level <= 0) return;

   datetime t1 = iTime(_Symbol, tf, lookback);
   datetime t2 = iTime(_Symbol, tf, 0) + PeriodSeconds(tf) * 10;
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
   if(ShowBOSArrows && g_H4.hasBOS) {
      string name = "VIS_BOS_H4";
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_ARROW, 0, iTime(_Symbol, TF_H4, 1),
                   g_H4.bullish ? iLow(_Symbol, TF_H4, 1) - 200 * _Point
                                : iHigh(_Symbol, TF_H4, 1) + 200 * _Point);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, g_H4.bullish ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     g_H4.bullish ? ColorBull : ColorBear);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
      ObjectSetString (0, name, OBJPROP_TEXT,       "BOS H4");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   // CHoCH arrows on H1
   if(ShowCHoCHArrows && g_H1.hasCHoCH) {
      string name = "VIS_CHOCH_H1";
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_ARROW, 0, iTime(_Symbol, TF_H1, 1),
                   g_H1.bullish ? iLow(_Symbol, TF_H1, 1) - 150 * _Point
                                : iHigh(_Symbol, TF_H1, 1) + 150 * _Point);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, g_H1.bullish ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     clrAqua);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      2);
      ObjectSetString (0, name, OBJPROP_TEXT,       "CHoCH H1");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   // CHoCH on M15
   if(ShowCHoCHArrows && g_M15.hasCHoCH) {
      string name = "VIS_CHOCH_M15";
      if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_ARROW, 0, iTime(_Symbol, TF_M15, 1),
                   g_M15.bullish ? iLow(_Symbol, TF_M15, 1) - 100 * _Point
                                 : iHigh(_Symbol, TF_M15, 1) + 100 * _Point);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, g_M15.bullish ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     clrYellow);
      ObjectSetInteger(0, name, OBJPROP_WIDTH,      1);
      ObjectSetString (0, name, OBJPROP_TEXT,       "CHoCH M15");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void DrawTradeLevelLines() {
   if(!ShowTradeLevels) return;
   // Remove old trade lines first
   ObjectsDeleteAll(0, "VIS_TL_");
   // Draw lines for each open trade
   for(int t = 0; t < ArraySize(g_Trades); t++) {
      TradeState ts = g_Trades[t];
      datetime   t1 = TimeCurrent() - PeriodSeconds(PERIOD_H1) * 4;
      datetime   t2 = TimeCurrent() + PeriodSeconds(PERIOD_H1) * 8;
      string     pfx = "VIS_TL_" + IntegerToString(ts.ticket);

      DrawHLine(pfx + "_SL",  ts.initialSL, ColorSL_Line,  STYLE_SOLID, 2, "SL");
      DrawHLine(pfx + "_TP1", ts.tp1Price,  ColorTP1_Line, STYLE_DASH,  1, "TP1");
      DrawHLine(pfx + "_TP2", ts.tp2Price,  ColorTP2_Line, STYLE_SOLID, 1, "TP2");
      DrawHLine(pfx + "_EN",  ts.entryPrice, clrWhite,     STYLE_DOT,   1, "Entry");
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
      "XAUUSD SNIPER | %s %s\nScore: %d/13 | %s\nEntry: %.2f\nSL: %.2f | TP1: %.2f | TP2: %.2f\nRisk: %.1f%% | Lots: %.2f",
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
//| Dashboard creation — all labels                                 |
//+------------------------------------------------------------------+
void CreateDashboard() {
   // Background rectangle
   CreateRect(PREFIX+"BG", Dashboard_X - 5, Dashboard_Y - 5,
              DASH_WIDTH, ROW_HEIGHT * 64 + 10, ColorBG);
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
   SetLabel(PREFIX+"DS2", x, y,
            StringFormat("Daily P&L: %+.2f%%  [%s]   Target: +%.1f%%  Limit: -%.1f%%",
                         g_DailyPnL, pnlBar, DailyProfitTarget, DailyLossLimit),
            pnlColor, FontSize);
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
   string swStr    = ShowSweep      ? "Sweep:ON"  : "Sweep:OFF";
   string bosStr   = ShowBOSArrows  ? "BOS:ON"    : "BOS:OFF";
   string tlStr    = ShowTradeLevels ? "Levels:ON" : "Levels:OFF";

   SetLabel(PREFIX+"CV1a", x,       y, obStr,  ShowOB          ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1b", x + 75,  y, fvgStr, ShowFVG         ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1c", x + 150, y, swStr,  ShowSweep       ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1d", x + 235, y, bosStr, ShowBOSArrows   ? ColorBull : ColorNeutral, FontSize);
   SetLabel(PREFIX+"CV1e", x + 310, y, tlStr,  ShowTradeLevels ? ColorBull : ColorNeutral, FontSize);
   y += dy;

   y += 4;
   SetLabel(PREFIX+"UPD", x, y,
            StringFormat("v5.0 | %s | Magic: %d",
                         TimeToString(TimeCurrent(), TIME_MINUTES|TIME_SECONDS), MagicNumber),
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
