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

| Session | Time (UTC) | Quality |
|---|---|---|
| London Open | 07:00 - 09:00 | ⭐⭐⭐⭐⭐ Best |
| New York Open | 12:00 - 14:00 | ⭐⭐⭐⭐⭐ Best |
| London/NY Overlap | 12:00 - 16:00 | ⭐⭐⭐⭐⭐ Highest Volume |
| Asian Session | 00:00 - 07:00 | ⭐⭐ Avoid for entries |

> Only take sniper entries during London or New York sessions.

---

## Key Rules — Never Break These

1. **Never trade against H4 bias** — if H4 is bearish, only take sells
2. **Wait for the liquidity sweep** — if no sweep, no trade
3. **CHoCH must confirm** on M15 before entry
4. **Score must be 7 or higher** — below 7, skip the trade
5. **Only trade during London or NY session**
6. **Never risk more than 2% per trade**
7. **One valid setup is better than ten random trades**

---

## Daily Routine

```
Before London Open (06:30 UTC):
1. Open H4 → Identify trend, mark OBs, check Premium/Discount
2. Open H1 → Mark key zones, FVGs, previous CHoCH levels
3. Set alerts at key zone levels

During London Open (07:00-09:00 UTC):
4. Watch M15 closely
5. Wait for price to reach H1 zone
6. Look for liquidity sweep + CHoCH
7. Score the setup
8. If score 7+ → Enter sniper trade

After Trade:
9. Manage TP1 and TP2
10. Move SL to breakeven after TP1
11. Journal the trade (screenshot + notes)
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
