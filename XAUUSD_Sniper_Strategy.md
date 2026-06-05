# XAUUSD Sniper Entry Strategy
## Multi-Timeframe Confluence System (H4 → H1 → M15)

---

## Overview

This strategy uses 3 timeframes to identify high-probability sniper entries on XAUUSD (Gold).
It combines Smart Money Concepts (SMC) with ICT methodology for maximum confluence.

---

## Timeframe Roles

| Timeframe | Role | Purpose |
|---|---|---|
| H4 | Higher Timeframe (HTF) | Trend direction & major zones |
| H1 | Middle Timeframe (MTF) | Key levels, OB, FVG |
| M15 | Lower Timeframe (LTF) | Sniper entry trigger |

---

## Step 1 — H4 Analysis (Bias & Direction)

### What to look for:
- **BOS (Break of Structure)** — confirms trend direction
  - Bullish BOS = price breaks above last Higher High → ONLY look for BUYS
  - Bearish BOS = price breaks below last Lower Low → ONLY look for SELLS
- **Major Order Blocks** — mark the last bearish candle before a big move up (bullish OB) or last bullish candle before a big move down (bearish OB)
- **Premium & Discount Zones**
  - Below 50% of H4 range = Discount = look for BUYS
  - Above 50% of H4 range = Premium = look for SELLS

### H4 Checklist:
```
□ BOS direction identified (bullish or bearish)
□ Major Order Block marked
□ Price in Premium or Discount zone confirmed
□ Draw on Liquidity identified (where is price heading?)
```

---

## Step 2 — H1 Analysis (Zone Identification)

### What to look for:
- **CHoCH (Change of Character)** — early reversal signal
  - In downtrend: price breaks above last Lower High = CHoCH = potential buy
  - In uptrend: price breaks below last Higher Low = CHoCH = potential sell
- **Order Blocks (OB)** — refined from H4, more precise on H1
- **Fair Value Gaps (FVG)** — 3-candle pattern where middle candle leaves a gap
  - Bullish FVG: gap between candle 1 high and candle 3 low
  - Bearish FVG: gap between candle 1 low and candle 3 high
- **Mitigation Blocks** — broken OBs that price returns to

### H1 Checklist:
```
□ CHoCH confirmed in direction of H4 bias
□ H1 Order Block identified and marked
□ FVG present within or near the Order Block
□ Zone aligns with H4 OB or key level
```

---

## Step 3 — M15 Entry (Sniper Trigger)

### What to look for:
- **Liquidity Sweep** — price wicks below a low (for buys) or above a high (for sells) then reverses
- **M15 CHoCH** — structural shift after the sweep
- **Confirmation Candle** — bullish or bearish engulfing at the zone
- **M15 FVG** — small gap created after the sweep, enter at 50% of this FVG

### M15 Entry Checklist:
```
□ Price has reached the H1 Order Block zone
□ Liquidity sweep occurred (wick grabs stops)
□ M15 CHoCH confirmed after sweep
□ Confirmation candle (engulfing or strong close)
□ M15 FVG present above/below entry
```

---

## The Sniper Entry Model

```
H4 → Bullish BOS confirmed
     Price in Discount zone
     H4 Bullish Order Block at 2295-2300
          │
H1 → CHoCH bullish confirmed
     H1 FVG present at 2296-2298
     Aligns perfectly with H4 OB
          │
M15 → Price sweeps liquidity LOW at 2294
      M15 CHoCH forms immediately after
      Bullish engulfing candle closes at 2297
      M15 FVG between 2296-2298
          │
          ▼
ENTER BUY at 2297 (50% of M15 FVG)
SL at 2292 (below sweep wick, 5 pip buffer)
TP1 at 2310 (H1 swing high) — partial close 50%
TP2 at 2325 (H4 draw on liquidity) — full close
RR = 1:3 minimum ✅
```

---

## Confluence Scoring System

| Factor | Points |
|---|---|
| H4 BOS in trade direction | +2 |
| Price in correct Premium/Discount | +1 |
| H4 Order Block present | +2 |
| H1 CHoCH confirmed | +2 |
| H1 FVG aligns with H4 OB | +1 |
| M15 Liquidity Sweep occurred | +2 |
| M15 CHoCH after sweep | +1 |
| M15 Confirmation candle | +1 |
| M15 FVG entry | +1 |
| **Total Possible** | **13** |

### Score Interpretation:
- **10-13 = SNIPER ENTRY — High confidence, take the trade**
- **7-9  = VALID SETUP — Take with smaller position size**
- **4-6  = WAIT — Missing key confluence factors**
- **0-3  = NO TRADE — Skip completely**

---

## Trade Management Rules

### Entry:
- Enter at **50% of the M15 FVG** after confirmation candle closes
- Never enter before the M15 candle fully closes

### Stop Loss:
- Place SL **below the liquidity sweep wick** (for buys)
- Add **5-10 pip buffer** beyond the wick
- Never move SL to a worse position

### Take Profit:
- **TP1** = Next H1 swing high/low (close 50% of position)
- **TP2** = H4 draw on liquidity / major level (close remaining 50%)
- Move SL to breakeven after TP1 is hit

### Risk Management:
- Risk **maximum 1-2% per trade**
- Minimum RR = **1:2** (preferred 1:3)
- Maximum **2 trades per day**
- **Stop trading** after 2 consecutive losses

---

## Session Timing for XAUUSD

| Session | UTC Time | Philippines Time (PHT) | Quality |
|---|---|---|---|
| Asian Session | 00:00 - 07:00 | 08:00 AM - 03:00 PM | ⭐⭐ Prepare only |
| London Open | 07:00 - 09:00 | 03:00 PM - 05:00 PM | ⭐⭐⭐⭐⭐ Best |
| London Session | 07:00 - 16:00 | 03:00 PM - 12:00 AM | ⭐⭐⭐⭐ Good |
| New York Open | 12:00 - 14:00 | 08:00 PM - 10:00 PM | ⭐⭐⭐⭐⭐ Best |
| London/NY Overlap | 12:00 - 16:00 | 08:00 PM - 12:00 AM | ⭐⭐⭐⭐⭐ Highest Volume |

> Only take sniper entries during London or New York sessions.

---

## Trading Windows — Philippines Time (PHT)

```
❌ 8:00 AM  - 3:00 PM  ──► NO TRADING (Asian Session)
                            PREPARATION ONLY

✅ 3:00 PM  - 5:00 PM  ──► TRADE (London Open)
                            Best London setups form here
                            London sweeps Asian session liquidity

⚠️ 5:00 PM  - 8:00 PM  ──► SELECTIVE (London Session)
                            Still valid but require score 9+

✅ 8:00 PM  - 10:00 PM ──► TRADE (New York Open) ← BEST WINDOW
                            Highest volume of the day
                            London/NY overlap = most reliable setups

❌ After 10:00 PM       ──► STOP TRADING
                            Rest and review
```

---

## Asian Session Strategy (8:00 AM - 3:00 PM PHT)

> Do NOT trade — use this time to PREPARE

```
8:00 AM  ──► Open H4 chart
             Identify trend direction (bullish or bearish)
             Mark Order Blocks and major swing highs/lows

9:00 AM  ──► Drop to H1
             Mark FVGs and CHoCH levels
             Draw key zones where price might react

10:00 AM ──► Set price alerts at your zones
             Asian session builds liquidity (tight range)
             London will sweep this range later — mark it!

12:00 PM ──► Mid-day review
             Update zones if price moved
             Prepare trade plan for London open

2:30 PM  ──► Final preparation
             Confirm H4 bias is still valid
             Have your zones ready
             Get ready for 3:00 PM London open
```

**Why Asian session builds setups for London:**
- Price moves in a tight range during Asia
- This creates liquidity pools above and below
- London institutions sweep these pools first
- That sweep = your sniper entry trigger at 3:00 PM

---

## London Session Strategy (3:00 PM - 8:00 PM PHT)

```
3:00 PM  ──► London opens, volume spikes
             Watch M15 closely now
             Is price sweeping the Asian session high or low?

3:00 PM - 5:00 PM ──► PRIMARY LONDON WINDOW
             Entry Checklist:
             □ Price sweeps Asian session liquidity
             □ Price reaches your H1 zone
             □ CHoCH forms on M15
             □ Confirmation candle closes
             □ Score 7+ → ENTER TRADE

5:00 PM - 8:00 PM ──► SECONDARY LONDON WINDOW
             Be more selective here
             Require score 9+ before entering
             Avoid entering if NY open is less than 1 hour away
```

---

## New York Session Strategy (8:00 PM - 10:00 PM PHT)

```
8:00 PM  ──► New York opens ← YOUR BEST OPPORTUNITY
             If no trade from London, this is your chance
             Highest volume = most reliable moves

8:00 PM - 10:00 PM ──► PRIME SNIPER WINDOW
             Entry Checklist:
             □ Price sweeps London session high or low
             □ Price reaches your H1 zone
             □ CHoCH forms on M15 after sweep
             □ Strong confirmation candle closes
             □ Score 7+ → ENTER TRADE

10:00 PM ──► STOP — Close charts and review
```

---

## News Events — Philippines Time

| News Event | PHT Time | Impact |
|---|---|---|
| US CPI | 8:30 PM PHT | Very High |
| US NFP (1st Friday) | 8:30 PM PHT | Very High |
| US GDP | 8:30 PM PHT | High |
| FOMC Minutes | 2:00 AM PHT | Very High (after hours) |

> **Rule:** Do NOT enter a trade 30 minutes before major news.
> Wait for the spike, let price settle, then look for your sniper setup.

---

## Key Rules — Never Break These

1. **Never trade against H4 bias** — if H4 is bearish, only take sells
2. **Wait for the liquidity sweep** — if no sweep, no trade
3. **CHoCH must confirm** on M15 before entry
4. **Score must be 7 or higher** — below 7, skip the trade
5. **Only trade at 3:00 PM or 8:00 PM PHT windows**
6. **Never risk more than 2% per trade**
7. **Stop after 2 consecutive losses** — close charts and rest
8. **No trades during Asian session** — preparation only
9. **No trades 30 minutes before major news**
10. **One valid setup is better than ten random trades**

---

## Daily Routine — Philippines Time

```
6:00 AM  ──► Optional early review
             Check economic calendar for news today
             Note any major events at 8:30 PM

8:00 AM  ──► PREPARATION PHASE BEGINS
             Open H4 → identify trend, mark OBs
             Open H1 → mark zones, FVGs, CHoCH levels
             Set price alerts at key zones

12:00 PM ──► MID-DAY REVIEW
             Update analysis if price moved
             Refine your trade plan

2:30 PM  ──► GET READY FOR LONDON
             Review all marked zones
             Confirm H4 bias still valid
             Charts open and ready

3:00 PM  ──► LONDON OPEN — TRADING WINDOW 1 ✅
             Watch M15 actively
             Wait for Asian session liquidity sweep
             Score every setup — enter only if 7+

5:00 PM  ──► Review London trades
             If in trade → manage TP1 and TP2
             If no trade → watch selectively until 8 PM

8:00 PM  ──► NEW YORK OPEN — TRADING WINDOW 2 ✅
             Highest priority window
             Watch M15 very closely
             Wait for London high or low to be swept
             Enter on confirmation candle

10:00 PM ──► TRADING DAY ENDS
             Close all charts
             Screenshot all trades
             Write in trading journal
             Calculate daily P&L
             Rest
```

---

## Summary

> This strategy works because it follows what INSTITUTIONS do.
> They accumulate orders at key levels (Order Blocks),
> they hunt retail stop losses (Liquidity Sweeps),
> and they leave imbalances in the market (FVGs).
> 
> By reading these footprints across H4, H1, and M15,
> you enter AFTER the institutions have shown their hand —
> that is the sniper entry.
