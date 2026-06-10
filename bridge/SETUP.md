# Claude AI Bridge — Setup Guide

## What this does
Connects your XAUUSD Sniper EA in MetaTrader 5 to Claude AI.
Every time the EA detects a trade signal, Claude analyzes the full
SMC confluence and returns TAKE / SKIP / ADJUST_SL before the EA executes.

---

## Step 1 — Get Anthropic API Key
1. Go to https://console.anthropic.com
2. Create an account (free)
3. Go to API Keys → Create Key
4. Copy your key

Cost: ~$0.005 per signal analysis (~$0.45/month at 3 trades/day)

---

## Step 2 — Install Python
Download from https://python.org (version 3.9 or higher)

---

## Step 3 — Install dependencies
Open terminal/command prompt:
```
pip install anthropic
```

---

## Step 4 — Configure the bridge

Open `claude_bridge.py` and set:

```python
API_KEY = "your-actual-api-key-here"

MT5_FILES_PATH = Path(r"C:/Users/YOUR_NAME/AppData/Roaming/MetaQuotes/Terminal/Common/Files")
```

To find your MT5 Common Files folder:
- Open MetaTrader 5
- Click File → Open Data Folder
- Navigate to: MQL5 → Files
- Copy that path

Or set as environment variable:
```
set ANTHROPIC_API_KEY=your-key-here
set MT5_FILES_PATH=C:\path\to\mt5\files
```

---

## Step 5 — Configure the EA in MT5

In EA settings, find the CLAUDE AI BRIDGE section:
```
UseBridge         = true
BridgeMustApprove = true      (skip trade if no response)
BridgeTimeoutSec  = 30        (wait 30 seconds for Claude)
BridgeSignalFile  = SNP_Signal.txt
BridgeRespFile    = SNP_Response.txt
BridgeResultFile  = SNP_Result.txt
```

Make sure MT5 allows file access:
- Tools → Options → Expert Advisors
- Check "Allow DLL imports"
- Check "Allow WebRequest for listed URL"

---

## Step 6 — Run the bridge

```
python claude_bridge.py
```

Keep this terminal window open while trading.
The bridge runs in the background watching for signals.

---

## What you will see

When a signal fires:
```
[2026-06-05 20:35:12] Analyzing BUY signal — score 31/42
[2026-06-05 20:35:14] Claude raw response:
VERDICT=TAKE
REASON=H4 MSS + H1 CHoCH confirmed, M15 sweep at FreshOB in discount zone — high probability
[2026-06-05 20:35:14] Response written: TAKE — H4 MSS + H1 CHoCH confirmed...
```

When a trade closes:
```
[2026-06-05 21:42:18] Trade result: ✓ WIN $24.50 | PRIMARY score:31 | NY Open
```

Every morning at 8:00 AM:
```
Daily Briefing:
Your win rate of 71% shows the NY Open session is your strongest window.
Watch for fake Judas swings at London open before committing.
Consider raising your minimum score to 32 during low-volume Asian hours.
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "API key invalid" | Check key at console.anthropic.com |
| "MT5 files path not found" | Update MT5_FILES_PATH in script |
| EA shows "Signal sent" but no response | Check bridge is running |
| Bridge crashes | Check claude_bridge_log.txt for errors |
| Timeout after 30s | Increase BridgeTimeoutSec in EA settings |
