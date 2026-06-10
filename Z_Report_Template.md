# Z REPORT — XAUUSD SNIPER EA BACKTEST ANALYSIS
> Fill in every `[ ]` field after running the backtest in MT5 Strategy Tester.
> Upload this completed file for parameter optimization recommendations.

---

## SECTION 0 — TEST CONFIGURATION

| Field | Value |
|---|---|
| EA Version | [ ] |
| Symbol | XAUUSD |
| Backtest Period | [ e.g. 2021.01.01 – 2025.06.01 ] |
| Starting Balance | $[ ] |
| Modelling Quality | [ Every tick / Every tick based on real ticks / 1-minute OHLC ] |
| Spread (fixed pips) | [ ] |
| Commission per lot | $[ ] |
| Primary Timeframe | H4 → H1 → M15 |
| Tested Timeframes | [ list all you ran, e.g. M15 chart / H1 chart ] |
| ATR Filter ON/OFF | [ ] |
| ATR Chop Threshold | [ ] pips |
| ATR Spike Threshold | [ ] pips |
| UseATRStop | [ true / false ] |
| News Filter ON/OFF | [ ] |
| Max Spread Pips | [ ] |
| Min Primary Score | [ ] |
| Min Fallback Score | [ ] |
| Primary Risk % | [ ]% |
| Fallback Risk % | [ ]% |
| TP1 R:R | 1:[ ] |
| TP2 R:R | 1:[ ] |
| Breakeven Trigger | [ ]× SL |
| Trail Distance | [ ] pips |
| One Trade At A Time | [ true / false ] |
| Use Pending Orders (FVG) | [ true / false ] |
| Daily Loss Limit | [ ]% |
| Daily Profit Target | [ ]% |
| Weekly Loss Limit | [ ]% |
| Monthly Loss Limit | [ ]% |

---

## SECTION 1 — STRATEGY PERFORMANCE OVERVIEW

### 1.1 Top-Level KPIs

| Metric | Result | Target | Pass/Fail |
|---|---|---|---|
| Net Return % | [ ]% | > 50% / yr | [ ] |
| CAGR (annualised) | [ ]% | > 30% | [ ] |
| Starting Balance | $[ ] | — | — |
| Ending Balance | $[ ] | — | — |
| Net P&L | $[ ] | Positive | [ ] |
| Win Rate | [ ]% | ≥ 50% | [ ] |
| Profit Factor | [ ] | ≥ 1.5 | [ ] |
| Expected Payoff | $[ ] / trade | > $0 | [ ] |
| Average R:R Achieved | 1:[ ] | ≥ 1:2 | [ ] |
| Total Trades | [ ] | — | — |
| Total Wins | [ ] | — | — |
| Total Losses | [ ] | — | — |
| Max Drawdown (Balance) | [ ]% | < 15% | [ ] |
| Max Drawdown (Equity) | [ ]% | < 20% | [ ] |
| Max Win Streak | [ ] trades | — | — |
| Max Lose Streak | [ ] trades | — | — |
| Best Single Trade | $[ ] | — | — |
| Worst Single Trade | $[ ] | — | — |
| Total Pips | [ ] | Positive | [ ] |
| Gross Profit | $[ ] | — | — |
| Gross Loss | $[ ] | — | — |

### 1.2 By Strategy Tier

| Tier | Trades | Wins | Win Rate | Net P&L | Avg R:R | Notes |
|---|---|---|---|---|---|---|
| PRIMARY (H4→H1→M15) | [ ] | [ ] | [ ]% | $[ ] | 1:[ ] | |
| FALLBACK (H1→M15→M5) | [ ] | [ ] | [ ]% | $[ ] | 1:[ ] | |
| TERTIARY (M15→M5→M1) | [ ] | [ ] | [ ]% | $[ ] | 1:[ ] | |
| FVG Pending Filled | [ ] | [ ] | [ ]% | $[ ] | 1:[ ] | |
| FVG Pending Expired | [ ] | — | — | — | — | |

---

## SECTION 2 — STATISTICAL BREAKDOWN

### 2.1 Per-Session Performance

| Session | PHT Window | Trades | Wins | Losses | Win Rate | Net P&L | Profit Factor | Notes |
|---|---|---|---|---|---|---|---|---|
| Asian KZ | 05:00–07:00 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| Pre-Market | 07:00–13:30 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| Pre-London Spike | 13:30–15:00 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| London Open | 15:00–17:00 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| London Mid | 17:00–19:30 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| Pre-NY Spike | 19:30–20:00 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| NY Open | 20:00–23:00 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| NY PM / Silver Bullet | 23:00–01:00 | [ ] | [ ] | [ ] | [ ]% | $[ ] | [ ] | |
| **BEST SESSION** | | | | | | | | |
| **WORST SESSION** | | | | | | | | |

*(PHT times shown for summer. Winter adds 1 hour to all except Asian KZ.)*

### 2.2 Monthly Performance Grid

| Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | Annual |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 2021 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| 2022 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| 2023 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| 2024 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] |
| 2025 | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | — | — | — | — | [ ] |

*(Enter net % return per month, e.g. +3.2% or -1.1%. Red = loss month.)*

### 2.3 Drawdown Analysis

| Metric | Value |
|---|---|
| Maximum Balance Drawdown % | [ ]% |
| Maximum Equity Drawdown % | [ ]% |
| Drawdown start date | [ ] |
| Drawdown end date (recovery) | [ ] |
| Duration of deepest drawdown | [ ] days |
| Number of drawdown periods > 5% | [ ] |
| Longest losing streak (trades) | [ ] |
| Longest losing streak (calendar days) | [ ] |

### 2.4 Filter Effectiveness

| Filter | Times Triggered | Trades Blocked | Estimated $ Saved (rough) |
|---|---|---|---|
| ATR Chop Filter | [ ] | [ ] | $[ ] |
| ATR Spike Filter | [ ] | [ ] | $[ ] |
| Spread Filter | [ ] | [ ] | $[ ] |
| News Filter | [ ] | [ ] | $[ ] |
| PDH/PDL Running Block | [ ] | [ ] | $[ ] |
| Pre-London/Pre-NY No-Sweep Block | [ ] | [ ] | $[ ] |
| Daily Loss Limit Hit | [ ] days | — | — |
| Weekly Loss Limit Hit | [ ] weeks | — | — |
| Session Suspended (Adaptive) | [ ] | — | — |

---

## SECTION 3 — IDENTIFIED WEAKNESSES

> Rank each weakness from the backtest data. Use the HTML report's trade log to find clusters of losses.

### 3.1 Loss Cluster Analysis

| # | Condition / Market State | Trades Lost | $ Lost | % of Total Loss | Root Cause |
|---|---|---|---|---|---|
| 1 | [ e.g. Choppy consolidation, ATR < 10 ] | [ ] | $[ ] | [ ]% | [ ] |
| 2 | [ e.g. Counter-trend in strong trend day ] | [ ] | $[ ] | [ ]% | [ ] |
| 3 | [ e.g. False Judas — no follow-through ] | [ ] | $[ ] | [ ]% | [ ] |
| 4 | [ e.g. Pre-London spike without sweep ] | [ ] | $[ ] | [ ]% | [ ] |
| 5 | [ e.g. Wide spread on Asian session ] | [ ] | $[ ] | [ ]% | [ ] |
| 6 | [ ] | [ ] | $[ ] | [ ]% | [ ] |

### 3.2 Session Where EA Lost Most

- **Session:** [ ]
- **Win rate in this session:** [ ]%
- **Net loss from this session:** $[ ]
- **Pattern observed:** [ describe common price behaviour that caused losses ]
- **Proposed fix:** [ ]

### 3.3 Time-of-Year Weakness

- **Worst month(s):** [ ]
- **Pattern:** [ e.g. August low volatility, December thin liquidity ]
- **Proposed fix:** [ e.g. raise ATR chop threshold in Aug/Dec ]

### 3.4 Strategy Tier Weakness

- **Weakest tier:** [ PRIMARY / FALLBACK / TERTIARY ]
- **Win rate:** [ ]%
- **Reason:** [ ]
- **Proposed fix:** [ ]

---

## SECTION 4 — PROPOSED PARAMETER ADJUSTMENTS

> Based on Sections 2 and 3, list every parameter change to test in the next optimization run.

### 4.1 Score Thresholds

| Parameter | Current | Proposed | Reason |
|---|---|---|---|
| MinPrimaryScore | [ ] | [ ] | [ ] |
| MinFallbackScore | [ ] | [ ] | [ ] |
| MinTertiaryScore | [ ] | [ ] | [ ] |
| LondonMinScore | [ ] | [ ] | [ ] |
| NYOpenMinScore | [ ] | [ ] | [ ] |
| PreLondonMinScore | [ ] | [ ] | [ ] |
| PreNYMinScore | [ ] | [ ] | [ ] |
| AsianMinScore | [ ] | [ ] | [ ] |

### 4.2 Risk & Reward

| Parameter | Current | Proposed | Reason |
|---|---|---|---|
| PrimaryRisk % | [ ]% | [ ]% | [ ] |
| FallbackRisk % | [ ]% | [ ]% | [ ] |
| TertiaryRisk % | [ ]% | [ ]% | [ ] |
| TP1 R:R | 1:[ ] | 1:[ ] | [ ] |
| TP2 R:R | 1:[ ] | 1:[ ] | [ ] |
| SL Buffer Pips | [ ] | [ ] | [ ] |

### 4.3 ATR Filter

| Parameter | Current | Proposed | Reason |
|---|---|---|---|
| ATR_ChopThreshold | [ ] pips | [ ] pips | [ ] |
| ATR_SpikeThreshold | [ ] pips | [ ] pips | [ ] |
| UseATRStop | [ ] | [ ] | [ ] |
| ATR_SLMultiplier | [ ] | [ ] | [ ] |
| ATR_TPMultiplier | [ ] | [ ] | [ ] |

### 4.4 Capital Protection

| Parameter | Current | Proposed | Reason |
|---|---|---|---|
| DailyLossLimit % | [ ]% | [ ]% | [ ] |
| DailyProfitTarget % | [ ]% | [ ]% | [ ] |
| MaxDailyTrades | [ ] | [ ] | [ ] |
| MaxConsecLosses | [ ] | [ ] | [ ] |
| BreakevenTrigger | [ ]× | [ ]× | [ ] |
| TrailDistance pips | [ ] | [ ] | [ ] |
| WeeklyLossLimit % | [ ]% | [ ]% | [ ] |

### 4.5 Session Adjustments

| Session | Change Proposed | Parameter | From → To |
|---|---|---|---|
| [ ] | [ ] | [ ] | [ ] → [ ] |
| [ ] | [ ] | [ ] | [ ] → [ ] |
| [ ] | [ ] | [ ] | [ ] → [ ] |

### 4.6 New Filters / Features to Consider

| # | Feature | Priority | Expected Impact |
|---|---|---|---|
| 1 | [ e.g. Disable trading in August ] | [ High/Med/Low ] | [ ] |
| 2 | [ e.g. Raise ATR min to 15 pips in Asian ] | [ ] | [ ] |
| 3 | [ ] | [ ] | [ ] |

---

## SECTION 5 — OPTIMIZATION PLAN FOR NEXT RUN

> List the MT5 Optimizer input ranges to test on the next pass.

| Parameter | Min | Max | Step | Priority |
|---|---|---|---|---|
| MinPrimaryScore | 5 | 12 | 1 | High |
| MinFallbackScore | 7 | 14 | 1 | High |
| ATR_ChopThreshold | 5 | 20 | 1 | High |
| ATR_SpikeThreshold | 40 | 100 | 5 | Medium |
| TP2_RR | 2.0 | 5.0 | 0.5 | High |
| TP1_RR | 0.5 | 2.0 | 0.5 | Medium |
| SL_BufferPips | 3 | 10 | 1 | Medium |
| TrailDistance | 10 | 30 | 5 | Low |
| BreakevenTrigger | 0.5 | 2.0 | 0.5 | Low |
| [ ] | [ ] | [ ] | [ ] | [ ] |

**Optimization Criterion:** Custom metric = `Profit Factor × Win Rate × (1 / Drawdown Penalty)`
*(Already coded in OnTester())*

**Walk-Forward Plan:**
- In-Sample: 2021.01.01 – 2023.12.31 (3 years)
- Out-of-Sample: 2024.01.01 – 2025.06.01 (1.5 years validation)
- Re-run every 6 months with rolling window

---

## SECTION 6 — TESTER SETUP CHECKLIST

Before running the backtest, verify each item:

- [ ] XAUUSD tick data downloaded (Tools → History Center → XAUUSD, all timeframes)
- [ ] M1 data present for 2021–present (MT5 needs M1 for higher TF synthesis)
- [ ] H4, H1, M15, M5, M1 all pre-loaded in charts (open each TF in MT5 before test)
- [ ] Modelling: "Every tick based on real ticks" selected (not Open prices only)
- [ ] Spread: Set to fixed value matching your broker's typical gold spread (e.g. 20 pips)
- [ ] Commission: Set per-lot cost if your broker charges ($3–7/lot typical for ECN)
- [ ] Initial deposit matches live account size
- [ ] `GenerateReport = true` in EA inputs (produces HTML report automatically)
- [ ] `UseJournal = true` (produces CSV trade log)
- [ ] `AutoTrade = true` (required for tester to place trades)
- [ ] `UseBridge = false` (disable Claude bridge during backtest)
- [ ] Look-ahead bias: all indicator values read from bar index 1+ (not bar 0) ✅ confirmed
- [ ] No external DLL calls that fail in tester environment
- [ ] `g_IsTesting` flag checked — dashboard and Telegram skipped in tester for speed

### Data Quality Notes

| Requirement | Why |
|---|---|
| Tick data (real ticks) preferred | ICT entries are precision-based — M1 OHLC misses FVG fills |
| Spread ≥ broker live spread | Underestimating spread inflates results — use conservative 25–30 pips for gold |
| Swap rates set correctly | Overnight positions (Asian hold-through) incur gold swap charges |
| 2021 data critical | Covers 2021 Covid recovery bull run + 2022 USD surge bear — both regimes needed |
| DST transitions included | UK/US DST shifts in March/October — EA handles automatically via IsLondonDST/IsNYDST |

---

## SECTION 7 — ANALYST SIGN-OFF

| Field | Value |
|---|---|
| Date Completed | [ ] |
| Run By | [ ] |
| MT5 Build | [ ] |
| EA Version | 13.17 |
| Next Review Date | [ ] |
| Verdict | [ PASS for live / OPTIMIZE / FAIL — rebuild required ] |
| Notes | [ any free-form observations ] |

---
*Z Report v1.0 — XAUUSD Sniper EA Backtesting Framework*
*Generated template: 2026-06-07*
