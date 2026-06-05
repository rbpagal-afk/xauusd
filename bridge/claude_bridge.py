"""
XAUUSD Sniper EA — Claude AI Bridge + Telegram Bot
====================================================
Connects MetaTrader 5 EA to Claude AI and your Telegram phone.

Features:
  - Claude AI validates every trade signal (TAKE/SKIP/ADJUST_SL)
  - Telegram sends you alerts for signals, entries, TP/SL hits
  - Control your EA from your phone with simple commands
  - /status  — see balance, P&L, open trades
  - /pause   — stop new entries remotely
  - /resume  — resume trading
  - /close   — close all open trades
  - /score 35 — change minimum score threshold
  - /risk 1.5 — change risk percentage
  - /report  — get today's performance summary
  - /help    — list all commands

Setup:
  1. pip install anthropic requests
  2. Create Telegram bot via @BotFather — get token
  3. Set ANTHROPIC_API_KEY and TELEGRAM_TOKEN below
  4. Run: python claude_bridge.py
  5. Send any message to your bot to register your chat ID
  6. In MT5 EA settings: set UseBridge=true
"""

import os
import time
import json
import requests
import anthropic
from datetime import datetime
from pathlib import Path

# ══════════════════════════════════════════════════════════════════
# CONFIGURATION — edit these before running
# ══════════════════════════════════════════════════════════════════

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "your-anthropic-key-here")
TELEGRAM_TOKEN    = os.environ.get("TELEGRAM_TOKEN",    "your-telegram-bot-token-here")

# Your Telegram chat ID — leave 0 to auto-detect on first message
CHAT_ID = int(os.environ.get("TELEGRAM_CHAT_ID", "0"))

# MT5 Common Files folder — update to match your Windows username
MT5_FILES_PATH = Path(os.environ.get(
    "MT5_FILES_PATH",
    r"C:/Users/" + os.environ.get("USERNAME", "User") +
    r"/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
))

# File names (must match EA settings)
SIGNAL_FILE   = MT5_FILES_PATH / "SNP_Signal.txt"
RESPONSE_FILE = MT5_FILES_PATH / "SNP_Response.txt"
RESULT_FILE   = MT5_FILES_PATH / "SNP_Result.txt"
STATUS_FILE   = MT5_FILES_PATH / "SNP_Status.txt"
COMMAND_FILE  = MT5_FILES_PATH / "SNP_Command.txt"
SETTINGS_FILE = MT5_FILES_PATH / "SNP_Settings.txt"
ACK_FILE      = MT5_FILES_PATH / "SNP_CmdAck.txt"

LOG_FILE      = Path("claude_bridge_log.txt")
STATE_FILE    = Path("bridge_state.json")  # Persists chat ID etc.

MODEL         = "claude-opus-4-8"
POLL_INTERVAL = 1.0   # seconds between file and Telegram checks

# ══════════════════════════════════════════════════════════════════
# STATE
# ══════════════════════════════════════════════════════════════════

state = {
    "chat_id":        CHAT_ID,
    "tg_offset":      0,
    "trade_history":  [],
    "last_briefing":  -1,
    "paused":         False,
}

def load_state():
    global state
    if STATE_FILE.exists():
        try:
            saved = json.loads(STATE_FILE.read_text())
            state.update(saved)
        except Exception:
            pass
    if CHAT_ID != 0:
        state["chat_id"] = CHAT_ID

def save_state():
    STATE_FILE.write_text(json.dumps(state, indent=2))


# ══════════════════════════════════════════════════════════════════
# LOGGING
# ══════════════════════════════════════════════════════════════════

def log(msg: str):
    ts   = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")


# ══════════════════════════════════════════════════════════════════
# TELEGRAM FUNCTIONS
# ══════════════════════════════════════════════════════════════════

TG_BASE = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}"

def tg_send(text: str, parse_mode: str = "HTML") -> bool:
    """Send message to Telegram."""
    if not state["chat_id"]:
        log(f"No chat_id yet — message not sent: {text[:60]}")
        return False
    try:
        r = requests.post(
            f"{TG_BASE}/sendMessage",
            data={"chat_id": state["chat_id"],
                  "text": text,
                  "parse_mode": parse_mode},
            timeout=10
        )
        return r.status_code == 200
    except Exception as e:
        log(f"Telegram send error: {e}")
        return False


def tg_get_updates() -> list:
    """Poll Telegram for new messages."""
    try:
        r = requests.get(
            f"{TG_BASE}/getUpdates",
            params={"offset": state["tg_offset"], "timeout": 1},
            timeout=5
        )
        if r.status_code != 200:
            return []
        data = r.json()
        if not data.get("ok"):
            return []
        return data.get("result", [])
    except Exception:
        return []


def tg_process_updates():
    """Read and process all new Telegram messages."""
    updates = tg_get_updates()
    for upd in updates:
        state["tg_offset"] = upd["update_id"] + 1

        msg = upd.get("message") or upd.get("edited_message")
        if not msg:
            continue

        # Auto-register first user's chat ID
        chat_id = msg["chat"]["id"]
        if not state["chat_id"]:
            state["chat_id"] = chat_id
            save_state()
            log(f"Chat ID registered: {chat_id}")
            tg_send("✅ <b>Bridge connected!</b>\nSend /help to see all commands.")
            continue

        # Only accept messages from registered user
        if chat_id != state["chat_id"]:
            continue

        text = msg.get("text", "").strip().lower()
        handle_command(text)

    save_state()


def handle_command(text: str):
    """Process a command from Telegram."""
    log(f"Telegram command: {text}")

    # /help
    if text in ("/help", "help"):
        tg_send(
            "📋 <b>XAUUSD Sniper Commands</b>\n\n"
            "/status — Account balance, P&L, open trades\n"
            "/signal — Latest signal details\n"
            "/report — Today's performance summary\n"
            "/pause  — Stop new trade entries\n"
            "/resume — Resume trading\n"
            "/close  — Close all open trades\n"
            "/score 35 — Set min primary score (5-20)\n"
            "/risk 1.5 — Set primary risk % (0.5-5.0)\n"
            "/fscore 9 — Set min fallback score\n"
            "/help   — Show this list"
        )

    # /status
    elif text in ("/status", "status"):
        send_status()

    # /signal
    elif text in ("/signal", "signal"):
        send_latest_signal()

    # /report
    elif text in ("/report", "report"):
        send_report()

    # /pause
    elif text in ("/pause", "pause"):
        write_command("PAUSE", "")
        state["paused"] = True
        tg_send("⏸ <b>Trading PAUSED</b>\nNo new entries until you send /resume")

    # /resume
    elif text in ("/resume", "resume"):
        write_command("RESUME", "")
        state["paused"] = False
        tg_send("▶️ <b>Trading RESUMED</b>")

    # /close
    elif text in ("/close", "close all", "/close all"):
        write_command("CLOSE_ALL", "Manual close via Telegram")
        tg_send("🔴 <b>Closing all trades...</b>\nConfirmation will arrive shortly.")

    # /score N
    elif text.startswith("/score") or text.startswith("score "):
        parts = text.split()
        if len(parts) >= 2 and parts[-1].isdigit():
            val = int(parts[-1])
            if 5 <= val <= 20:
                write_command("SET_PRIMARY_SCORE", str(val))
                tg_send(f"✅ <b>Min primary score set to {val}</b>")
            else:
                tg_send("❌ Score must be between 5 and 20")
        else:
            tg_send("Usage: /score 35")

    # /fscore N
    elif text.startswith("/fscore") or text.startswith("fscore "):
        parts = text.split()
        if len(parts) >= 2 and parts[-1].isdigit():
            val = int(parts[-1])
            if 5 <= val <= 22:
                write_command("SET_FALLBACK_SCORE", str(val))
                tg_send(f"✅ <b>Min fallback score set to {val}</b>")
            else:
                tg_send("❌ Fallback score must be between 5 and 22")
        else:
            tg_send("Usage: /fscore 9")

    # /risk N
    elif text.startswith("/risk") or text.startswith("risk "):
        parts = text.split()
        if len(parts) >= 2:
            try:
                val = float(parts[-1])
                if 0.1 <= val <= 10.0:
                    write_settings({"PrimaryRisk": str(val)})
                    tg_send(f"✅ <b>Primary risk set to {val}%</b>")
                else:
                    tg_send("❌ Risk must be between 0.1 and 10.0")
            except ValueError:
                tg_send("Usage: /risk 1.5")
        else:
            tg_send("Usage: /risk 1.5")

    else:
        tg_send("❓ Unknown command. Send /help")


# ══════════════════════════════════════════════════════════════════
# STATUS & REPORT MESSAGES
# ══════════════════════════════════════════════════════════════════

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


def send_status():
    """Read SNP_Status.txt and send formatted status to Telegram."""
    if not STATUS_FILE.exists():
        tg_send("❌ No status file yet — is the EA running?")
        return

    s = parse_file(STATUS_FILE)
    balance  = s.get("balance",      "?")
    equity   = s.get("equity",       "?")
    dpnl     = s.get("daily_pnl",    "?")
    wpnl     = s.get("weekly_pnl",   "?")
    dd       = s.get("drawdown",     "?")
    trades   = s.get("open_trades",  "?")
    session  = s.get("session",      "?")
    gate     = s.get("gate",         "?")
    paused   = s.get("paused",       "false")
    pscore   = s.get("primary_score","?")
    fscore   = s.get("fallback_score","?")
    pthr     = s.get("prim_threshold","?")
    fthr     = s.get("fall_threshold","?")
    news     = s.get("news",         "?")
    dxy      = s.get("dxy",          "?")
    wr       = s.get("win_rate",     "?")
    pf       = s.get("profit_factor","?")
    rec      = s.get("recommendation","?")
    t_time   = s.get("time",         "?")

    gate_icon = "🟢" if gate == "OPEN"  else "🔴"
    paus_icon = "⏸" if paused == "true" else ""
    dpnl_icon = "📈" if dpnl.startswith("+") else "📉"

    msg = (
        f"📊 <b>XAUUSD Sniper Status</b>  {t_time}\n"
        f"{'─'*30}\n"
        f"💰 Balance:  <b>${balance}</b>   Equity: ${equity}\n"
        f"{dpnl_icon} Daily P&L: <b>{dpnl}%</b>   Weekly: {wpnl}%\n"
        f"📉 Drawdown: {dd}%\n"
        f"{'─'*30}\n"
        f"{gate_icon} Gate: <b>{gate}</b> {paus_icon}\n"
        f"📰 News: {news}   DXY: {dxy[:30]}\n"
        f"{'─'*30}\n"
        f"🎯 Primary Score: {pscore}/42 (need {pthr})\n"
        f"🎯 Fallback Score:{fscore}/42 (need {fthr})\n"
        f"📂 Open trades: {trades}\n"
        f"{'─'*30}\n"
        f"📈 Win Rate: {wr}%   PF: {pf}\n"
        f"💡 {rec[:80]}\n"
    )

    # Add open trade details
    for i in range(3):
        td = s.get(f"trade_{i}", "")
        if td:
            msg += f"\n🔷 {td}"

    tg_send(msg)


def send_latest_signal():
    """Send the last known signal from trade history."""
    if not state["trade_history"]:
        tg_send("No signals recorded yet this session.")
        return
    last = state["trade_history"][-1]
    tg_send(
        f"📡 <b>Last Signal</b>\n"
        f"Result: {last.get('result','?')}  ${last.get('profit','?')}\n"
        f"Strategy: {last.get('strategy','?')}  Score: {last.get('score','?')}\n"
        f"Session: {last.get('session','?')}\n"
        f"Time: {last.get('time','?')}"
    )


def send_report():
    """Send today's performance summary."""
    history = state["trade_history"]
    if not history:
        tg_send("📋 No trades recorded yet.")
        return

    total   = len(history)
    wins    = sum(1 for t in history if t.get("result") == "WIN")
    profits = [float(t["profit"]) for t in history if t.get("profit","?") != "?"]
    net     = sum(profits)
    wr      = wins / total * 100 if total else 0

    msg = (
        f"📋 <b>Session Report</b>\n"
        f"{'─'*25}\n"
        f"Total trades: {total}\n"
        f"Wins: {wins}   Losses: {total-wins}\n"
        f"Win Rate: {wr:.1f}%\n"
        f"Net P&L: {'+'if net>=0 else ''}${net:.2f}\n"
    )

    if profits:
        msg += f"Best: +${max(profits):.2f}   Worst: ${min(profits):.2f}\n"

    recent = history[-5:]
    msg += f"\nLast {len(recent)} trades: "
    msg += " ".join("✓" if t.get("result")=="WIN" else "✗" for t in recent)

    tg_send(msg)


# ══════════════════════════════════════════════════════════════════
# FILE COMMUNICATION
# ══════════════════════════════════════════════════════════════════

def write_command(cmd: str, arg: str):
    """Write command file for EA to execute."""
    try:
        with open(COMMAND_FILE, "w", encoding="utf-8") as f:
            f.write(f"CMD={cmd}\nARG={arg}\n")
        log(f"Command written: {cmd} {arg}")
    except Exception as e:
        log(f"Error writing command: {e}")


def write_settings(settings: dict):
    """Write settings override file for EA to apply."""
    try:
        with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
            for k, v in settings.items():
                f.write(f"{k}={v}\n")
        log(f"Settings written: {settings}")
    except Exception as e:
        log(f"Error writing settings: {e}")


def check_ack():
    """Check if EA acknowledged a command and notify Telegram."""
    if not ACK_FILE.exists():
        return
    data = parse_file(ACK_FILE)
    try:
        ACK_FILE.unlink()
    except Exception:
        pass
    if data.get("RESULT"):
        tg_send(f"✅ EA confirmed: {data['RESULT']}")


# ══════════════════════════════════════════════════════════════════
# CLAUDE AI SIGNAL ANALYSIS
# ══════════════════════════════════════════════════════════════════

ai_client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)


def build_prompt(sig: dict) -> str:
    perf = ""
    h    = state["trade_history"]
    if h:
        recent = h[-10:]
        wins   = sum(1 for t in recent if t.get("result") == "WIN")
        perf   = (f"\nRECENT: {wins}/{len(recent)} wins "
                  f"({wins/len(recent)*100:.0f}%) — "
                  f"last 3: {[t.get('result','?') for t in recent[-3:]]}")

    return f"""You are an expert SMC/ICT gold trader reviewing a XAUUSD trade signal.
Analyze and respond with TAKE, SKIP, or ADJUST_SL.

SIGNAL: {sig.get('direction','?')} | Strategy: {sig.get('strategy','?')} | Score: {sig.get('score','?')} | Session: {sig.get('session','?')}

H4: Bias={sig.get('h4_bias','?')} ExtBOS={sig.get('h4_extbos','?')} MSS={sig.get('h4_mss','?')} FreshOB={sig.get('h4_freshob','?')} Zone={sig.get('h4_zone','?')} AtSR={sig.get('h4_atsr','?')}
H1: Bias={sig.get('h1_bias','?')} CHoCH={sig.get('h1_choch','?')} MSS={sig.get('h1_mss','?')} FreshOB={sig.get('h1_freshob','?')} FVG={sig.get('h1_fvgopen','?')} OTE={sig.get('h1_ote','?')} Sweep={sig.get('h1_sweep','?')}
M15: Bias={sig.get('m15_bias','?')} Sweep={sig.get('m15_sweep','?')} CHoCH={sig.get('m15_choch','?')} FreshOB={sig.get('m15_freshob','?')} Judas={sig.get('m15_judas','?')} Silver={sig.get('m15_silver','?')}
DXY: {sig.get('dxy_status','?')} | Candle: {sig.get('candle','?')} | News: {sig.get('news','?')}

Entry={sig.get('entry','?')} SL={sig.get('sl','?')} ({sig.get('sl_pips','?')}pips) TP2={sig.get('tp2','?')} RR={sig.get('rr','?')}
Balance=${sig.get('balance','?')} DailyPnL={sig.get('daily_pnl','?')} Drawdown={sig.get('drawdown','?')}
{perf}

Reply EXACTLY:
VERDICT=TAKE or SKIP or ADJUST_SL
REASON=one sentence
ADJUST_SL=price (only if ADJUST_SL verdict)"""


def analyze_signal(sig: dict):
    log(f"Sending to Claude: {sig.get('direction','?')} score {sig.get('score','?')}")
    try:
        msg = ai_client.messages.create(
            model=MODEL,
            max_tokens=120,
            messages=[{"role": "user", "content": build_prompt(sig)}]
        )
        raw = msg.content[0].text.strip()
        log(f"Claude: {raw}")

        lines     = {k: v for k, v in
                     (line.split("=", 1) for line in raw.splitlines() if "=" in line)}
        verdict   = lines.get("VERDICT",   "SKIP")
        reason    = lines.get("REASON",    "No reason")
        adjust_sl = lines.get("ADJUST_SL", "")

        if verdict not in ("TAKE", "SKIP", "ADJUST_SL"):
            verdict = "SKIP"
            reason  = "Invalid response — defaulting to SKIP"

        # Write verdict for EA
        with open(RESPONSE_FILE, "w", encoding="utf-8") as f:
            f.write(f"VERDICT={verdict}\nREASON={reason}\n")
            if adjust_sl:
                f.write(f"ADJUST_SL={adjust_sl}\n")

        # Notify Telegram
        icon   = "✅" if verdict == "TAKE" else "❌" if verdict == "SKIP" else "🔧"
        direct = sig.get("direction", "?")
        score  = sig.get("score",     "?")
        entry  = sig.get("entry",     "?")
        sl     = sig.get("sl",        "?")
        tp2    = sig.get("tp2",       "?")
        sess   = sig.get("session",   "?")

        tg_msg = (
            f"{icon} <b>Claude: {verdict}</b>\n"
            f"{'─'*25}\n"
            f"Signal: <b>{direct}</b> | Score: {score}\n"
            f"Session: {sess}\n"
            f"Entry: {entry}  SL: {sl}  TP2: {tp2}\n"
        )
        if adjust_sl:
            tg_msg += f"Adjusted SL: {adjust_sl}\n"
        tg_msg += f"\n💬 {reason}"
        tg_send(tg_msg)

    except Exception as e:
        log(f"Claude API error: {e}")
        with open(RESPONSE_FILE, "w", encoding="utf-8") as f:
            f.write(f"VERDICT=SKIP\nREASON=API error: {str(e)[:60]}\n")


# ══════════════════════════════════════════════════════════════════
# TRADE RESULT PROCESSING
# ══════════════════════════════════════════════════════════════════

def process_result(res: dict):
    result   = res.get("result",   "?")
    profit   = res.get("profit",   "?")
    strategy = res.get("strategy", "?")
    score    = res.get("score",    "?")
    session  = res.get("session",  "?")
    t_time   = res.get("time",     "?")

    state["trade_history"].append({
        "result": result, "profit": profit,
        "strategy": strategy, "score": score,
        "session": session, "time": t_time
    })
    if len(state["trade_history"]) > 50:
        state["trade_history"].pop(0)
    save_state()

    icon   = "🏆" if result == "WIN" else "💔"
    profit_str = f"+${profit}" if result == "WIN" else f"-${abs(float(profit)):.2f}" if profit != "?" else profit

    tg_send(
        f"{icon} <b>Trade {result}</b>\n"
        f"{'─'*25}\n"
        f"P&L: <b>{profit_str}</b>\n"
        f"Strategy: {strategy}  Score: {score}\n"
        f"Session: {session}"
    )
    log(f"Result: {result} ${profit} | {strategy} | {session}")


# ══════════════════════════════════════════════════════════════════
# DAILY BRIEFING
# ══════════════════════════════════════════════════════════════════

def daily_briefing():
    h = state["trade_history"]
    if not h:
        tg_send("☀️ <b>Good morning!</b>\nNo trade history yet. Ready to trade.")
        return
    wins    = sum(1 for t in h if t.get("result") == "WIN")
    total   = len(h)
    profits = [float(t["profit"]) for t in h if t.get("profit", "?") != "?"]
    net     = sum(profits)

    try:
        msg = ai_client.messages.create(
            model=MODEL,
            max_tokens=200,
            messages=[{"role": "user", "content":
                f"""XAUUSD SMC trading coach. Give a 3-sentence morning briefing.
Stats: {total} trades, {wins/total*100:.0f}% win rate, net ${net:.2f}
Recent results: {[t.get('result') for t in h[-5:]]}
Sessions: {set(t.get('session','') for t in h[-10:])}
Focus on: what is working, what to watch, one improvement tip.
Keep it under 3 sentences. Be direct and practical."""
            }]
        )
        briefing = msg.content[0].text.strip()
    except Exception:
        briefing = f"Win rate: {wins/total*100:.0f}% over {total} trades. Net P&L: ${net:.2f}. Trade with discipline today."

    tg_send(
        f"☀️ <b>Good Morning — Daily Briefing</b>\n"
        f"{'─'*25}\n"
        f"{briefing}\n\n"
        f"Stats: {wins}/{total} wins ({wins/total*100:.0f}%)  Net: ${net:.2f}\n"
        f"Send /status for live account data."
    )
    log("Daily briefing sent")


# ══════════════════════════════════════════════════════════════════
# MAIN LOOP
# ══════════════════════════════════════════════════════════════════

def main():
    load_state()

    log("=" * 60)
    log("XAUUSD Sniper — Claude AI Bridge + Telegram Bot STARTED")
    log(f"MT5 Files: {MT5_FILES_PATH}")
    log(f"Model:     {MODEL}")
    log(f"Chat ID:   {state['chat_id'] or 'not set — send any message to bot'}")
    log("=" * 60)

    # Validate API keys
    if ANTHROPIC_API_KEY == "your-anthropic-key-here":
        log("ERROR: Set ANTHROPIC_API_KEY")
        return
    if TELEGRAM_TOKEN == "your-telegram-bot-token-here":
        log("ERROR: Set TELEGRAM_TOKEN")
        return

    if not MT5_FILES_PATH.exists():
        log(f"WARNING: MT5 path not found: {MT5_FILES_PATH}")

    # Startup message to Telegram
    if state["chat_id"]:
        tg_send(
            "🟢 <b>XAUUSD Sniper Bridge ONLINE</b>\n"
            "Claude AI + Telegram monitoring active.\n"
            "Send /help to see all commands."
        )

    last_briefing_day = state.get("last_briefing", -1)

    while True:
        try:
            now = datetime.now()

            # Daily briefing at 8:00 AM PHT (before London open 15:00 PHT)
            if now.hour == 8 and now.day != last_briefing_day:
                last_briefing_day      = now.day
                state["last_briefing"] = now.day
                daily_briefing()
                save_state()

            # Check for MT5 signal
            if SIGNAL_FILE.exists():
                sig = parse_file(SIGNAL_FILE)
                if sig and "END_SIGNAL" not in str(sig.get("time","")):
                    time.sleep(0.1)  # Let EA finish writing
                    sig = parse_file(SIGNAL_FILE)
                if sig:
                    try:
                        SIGNAL_FILE.unlink()
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

            # Check for EA command acknowledgement
            check_ack()

            # Poll Telegram for commands
            tg_process_updates()

        except KeyboardInterrupt:
            log("Bridge stopped")
            if state["chat_id"]:
                tg_send("🔴 <b>Bridge OFFLINE</b>\nRestart claude_bridge.py to reconnect.")
            break
        except Exception as e:
            log(f"Error: {e}")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()
