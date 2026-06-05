"""
XAUUSD Sniper EA — Claude AI Bridge
====================================
Connects MetaTrader 5 EA to Claude AI for real-time signal validation.

How it works:
  1. EA writes a signal file when a trade setup is detected
  2. This script reads the signal and sends it to Claude API
  3. Claude analyzes the SMC confluence and returns a verdict
  4. Script writes the verdict back to a response file
  5. EA reads the verdict and executes or skips the trade
  6. EA writes trade results so Claude can track performance

Setup:
  pip install anthropic
  Set your API key below or in environment variable ANTHROPIC_API_KEY
  Set MT5_FILES_PATH to your MT5 Common Files folder
  Run: python claude_bridge.py

Cost: ~$0.005 per signal (~$0.45/month at 3 trades/day)
"""

import os
import time
import anthropic
from datetime import datetime
from pathlib import Path

# ── CONFIGURATION ──────────────────────────────────────────────────
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "your-api-key-here")

# MT5 Common Files folder — change to match your system
# Windows default: C:/Users/YOUR_NAME/AppData/Roaming/MetaQuotes/Terminal/Common/Files/
MT5_FILES_PATH = Path(os.environ.get(
    "MT5_FILES_PATH",
    r"C:/Users/" + os.environ.get("USERNAME", "User") +
    r"/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
))

SIGNAL_FILE   = MT5_FILES_PATH / "SNP_Signal.txt"
RESPONSE_FILE = MT5_FILES_PATH / "SNP_Response.txt"
RESULT_FILE   = MT5_FILES_PATH / "SNP_Result.txt"
LOG_FILE       = Path("claude_bridge_log.txt")

POLL_INTERVAL = 1.0   # seconds between file checks
MODEL         = "claude-opus-4-8"

# ── CLAUDE CLIENT ──────────────────────────────────────────────────
client = anthropic.Anthropic(api_key=API_KEY)

# Track performance for context
trade_history = []   # list of dicts: {result, profit, strategy, score, session}


def log(msg: str):
    """Write timestamped message to log and console."""
    ts  = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def parse_file(path: Path) -> dict:
    """Parse key=value file into dict."""
    data = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if "=" in line:
                    k, v = line.split("=", 1)
                    data[k.strip()] = v.strip()
    except Exception as e:
        log(f"Parse error {path}: {e}")
    return data


def write_response(verdict: str, reason: str, adjust_sl: str = ""):
    """Write Claude verdict back to MT5."""
    with open(RESPONSE_FILE, "w", encoding="utf-8") as f:
        f.write(f"VERDICT={verdict}\n")
        f.write(f"REASON={reason}\n")
        if adjust_sl:
            f.write(f"ADJUST_SL={adjust_sl}\n")
    log(f"Response written: {verdict} — {reason}")


def build_signal_prompt(sig: dict) -> str:
    """Build the prompt sent to Claude for signal analysis."""

    # Build recent performance context
    perf_ctx = ""
    if trade_history:
        recent = trade_history[-10:]
        wins   = sum(1 for t in recent if t["result"] == "WIN")
        perf_ctx = (
            f"\nRECENT PERFORMANCE (last {len(recent)} trades): "
            f"{wins}/{len(recent)} wins ({wins/len(recent)*100:.0f}% win rate)\n"
        )
        if len(recent) >= 3:
            last3 = recent[-3:]
            perf_ctx += "Last 3: " + " | ".join(
                f"{t['result']} ${t['profit']}" for t in last3
            ) + "\n"

    return f"""You are an expert SMC/ICT gold trader reviewing a XAUUSD trade signal.

Analyze this setup and respond with TAKE, SKIP, or ADJUST_SL.

━━━ SIGNAL DETAILS ━━━
Time:      {sig.get('time', 'N/A')}
Strategy:  {sig.get('strategy', 'N/A')}
Direction: {sig.get('direction', 'N/A')}
Score:     {sig.get('score', 'N/A')}
Session:   {sig.get('session', 'N/A')}

━━━ H4 STRUCTURE (Bias) ━━━
Bias:          {sig.get('h4_bias', 'N/A')}
External BOS:  {sig.get('h4_extbos', 'N/A')}
MSS:           {sig.get('h4_mss', 'N/A')}
Fresh OB:      {sig.get('h4_freshob', 'N/A')} ({sig.get('h4_ob_status', '')})
At Key S/R:    {sig.get('h4_atsr', 'N/A')}
Zone:          {sig.get('h4_zone', 'N/A')}
Weekly H/L:    {sig.get('h4_weekly', 'N/A')}

━━━ H1 ZONE ━━━
Bias:          {sig.get('h1_bias', 'N/A')}
CHoCH:         {sig.get('h1_choch', 'N/A')}
MSS:           {sig.get('h1_mss', 'N/A')}
Fresh OB:      {sig.get('h1_freshob', 'N/A')}
Open FVG:      {sig.get('h1_fvgopen', 'N/A')}
OTE (61-79%):  {sig.get('h1_ote', 'N/A')}
Sweep:         {sig.get('h1_sweep', 'N/A')}
Displacement:  {sig.get('h1_displacement', 'N/A')}

━━━ M15 ENTRY TRIGGER ━━━
Bias:          {sig.get('m15_bias', 'N/A')}
Sweep:         {sig.get('m15_sweep', 'N/A')}
CHoCH:         {sig.get('m15_choch', 'N/A')}
MSS:           {sig.get('m15_mss', 'N/A')}
Fresh OB:      {sig.get('m15_freshob', 'N/A')}
Open FVG:      {sig.get('m15_fvgopen', 'N/A')}
Judas Swing:   {sig.get('m15_judas', 'N/A')}
Silver Bullet: {sig.get('m15_silver', 'N/A')}

━━━ FILTERS ━━━
DXY:           {sig.get('dxy_status', 'N/A')}
Candle:        {sig.get('candle', 'N/A')}
News:          {sig.get('news', 'N/A')}

━━━ TRADE LEVELS ━━━
Entry:   {sig.get('entry', 'N/A')}
SL:      {sig.get('sl', 'N/A')} ({sig.get('sl_pips', '?')} pips)
TP1:     {sig.get('tp1', 'N/A')}
TP2:     {sig.get('tp2', 'N/A')} (RR {sig.get('rr', '?')})
Lots:    {sig.get('lots', 'N/A')}
Risk:    {sig.get('risk_pct', 'N/A')}%

━━━ ACCOUNT ━━━
Balance:     ${sig.get('balance', 'N/A')}
Equity:      ${sig.get('equity', 'N/A')}
Daily P&L:   {sig.get('daily_pnl', 'N/A')}
Daily trades:{sig.get('daily_trades', 'N/A')}
Drawdown:    {sig.get('drawdown', 'N/A')}
{perf_ctx}
━━━ YOUR RESPONSE FORMAT (strict) ━━━
Reply with EXACTLY these lines — nothing else:

VERDICT=TAKE
REASON=One sentence explanation

or:

VERDICT=SKIP
REASON=One sentence explanation

or (if SL should be at a better level):

VERDICT=ADJUST_SL
ADJUST_SL=<price>
REASON=One sentence explanation

Rules:
- TAKE if HTF bias matches direction AND LTF has clear sweep+CHoCH trigger
- SKIP if H4/H1 bias conflict OR OB is mitigated OR score is marginal
- ADJUST_SL if a stronger structural level exists nearby for better RR
- Be decisive — one clear verdict, one short reason
"""


def analyze_signal(sig: dict):
    """Send signal to Claude and write response."""
    log(f"Analyzing {sig.get('direction','?')} signal — score {sig.get('score','?')}")

    prompt = build_signal_prompt(sig)

    try:
        message = client.messages.create(
            model=MODEL,
            max_tokens=150,
            messages=[{"role": "user", "content": prompt}]
        )
        response_text = message.content[0].text.strip()
        log(f"Claude raw response:\n{response_text}")

        # Parse response
        lines   = {k: v for k, v in
                   (line.split("=", 1) for line in response_text.splitlines()
                    if "=" in line)}
        verdict   = lines.get("VERDICT",    "SKIP")
        reason    = lines.get("REASON",     "No reason provided")
        adjust_sl = lines.get("ADJUST_SL",  "")

        # Validate verdict
        if verdict not in ("TAKE", "SKIP", "ADJUST_SL"):
            verdict = "SKIP"
            reason  = "Invalid Claude response — defaulting to SKIP"

        write_response(verdict, reason, adjust_sl)

    except Exception as e:
        log(f"Claude API error: {e}")
        write_response("SKIP", f"API error: {str(e)[:80]}")


def process_result(res: dict):
    """Process trade result — store for context and log."""
    entry = {
        "result":   res.get("result",   "?"),
        "profit":   res.get("profit",   "?"),
        "strategy": res.get("strategy", "?"),
        "score":    res.get("score",    "?"),
        "session":  res.get("session",  "?"),
        "time":     res.get("time",     "?"),
    }
    trade_history.append(entry)
    # Keep last 50
    if len(trade_history) > 50:
        trade_history.pop(0)

    icon = "✓" if entry["result"] == "WIN" else "✗"
    log(f"Trade result: {icon} {entry['result']} ${entry['profit']} "
        f"| {entry['strategy']} score:{entry['score']} | {entry['session']}")


def daily_briefing():
    """Generate a morning briefing — call once per day if desired."""
    if not trade_history:
        return
    wins   = sum(1 for t in trade_history if t["result"] == "WIN")
    total  = len(trade_history)
    profit = sum(float(t["profit"]) for t in trade_history
                 if t["profit"] not in ("?", ""))

    try:
        message = client.messages.create(
            model=MODEL,
            max_tokens=300,
            messages=[{"role": "user", "content":
                f"""You are an XAUUSD SMC trading coach.

Give a 3-sentence daily briefing based on these stats:
Total trades: {total}
Win rate: {wins/total*100:.1f}% ({wins}/{total})
Net profit: ${profit:.2f}
Recent 5: {[t['result'] for t in trade_history[-5:]]}

Focus on: what is working, what to watch for, one adjustment suggestion.
Keep it under 3 sentences."""
            }]
        )
        briefing = message.content[0].text.strip()
        log(f"\n{'='*60}\nDAILY BRIEFING:\n{briefing}\n{'='*60}")
    except Exception as e:
        log(f"Briefing error: {e}")


def main():
    log("=" * 60)
    log("XAUUSD Sniper — Claude AI Bridge STARTED")
    log(f"Watching: {MT5_FILES_PATH}")
    log(f"Signal:   {SIGNAL_FILE.name}")
    log(f"Response: {RESPONSE_FILE.name}")
    log(f"Model:    {MODEL}")
    log("=" * 60)

    # Verify API key
    if API_KEY == "your-api-key-here":
        log("ERROR: Set your Anthropic API key in API_KEY or ANTHROPIC_API_KEY env var")
        return

    # Verify MT5 files path exists
    if not MT5_FILES_PATH.exists():
        log(f"WARNING: MT5 files path not found: {MT5_FILES_PATH}")
        log("Create the directory or update MT5_FILES_PATH in this script")

    last_briefing_day = -1

    while True:
        try:
            now = datetime.now()

            # Daily briefing at 8:00 AM (before London open)
            if now.hour == 8 and now.day != last_briefing_day:
                last_briefing_day = now.day
                daily_briefing()

            # Check for new signal
            if SIGNAL_FILE.exists():
                sig = parse_file(SIGNAL_FILE)
                if sig.get("time") and "END_SIGNAL" not in sig:
                    # File still being written — wait
                    time.sleep(0.2)
                    sig = parse_file(SIGNAL_FILE)

                if sig:
                    try:
                        SIGNAL_FILE.unlink()  # Delete signal file
                    except Exception:
                        pass
                    analyze_signal(sig)

            # Check for trade result
            if RESULT_FILE.exists():
                res = parse_file(RESULT_FILE)
                if res:
                    try:
                        RESULT_FILE.unlink()
                    except Exception:
                        pass
                    process_result(res)

        except KeyboardInterrupt:
            log("Bridge stopped by user")
            break
        except Exception as e:
            log(f"Unexpected error: {e}")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
