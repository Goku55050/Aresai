import time
import aiohttp
import re as _r
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    ApplicationBuilder,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    ContextTypes,
    filters,
)

# ======================
# CONFIG
# ======================
BOT_TOKEN = "8573740591:AAE8o0EvjuQ94TpnjTHvaB4sayFqh_DLYcs"
ADMIN_ID = 6430768414
ADMINS = {ADMIN_ID}

RATE_LIMIT = {}

FORCE_CHANNELS = [
    {"chat_id": "@ares_anime", "name": "Ares Anime", "invite": "https://t.me/ares_anime"},
    {"chat_id": "@ares_info_channel", "name": "Ares Info", "invite": "https://t.me/ares_info_channel"},
]

# ======================
# ADVANCED AUTO NUMBER NORMALIZER
# ======================
def nornum(raw: str):
    ζ = _r.sub(r"\D", "", raw)   # digits only
    ℓ = len(ζ)

    _rules = (
        (lambda s, n: n == 10, lambda s: s),                              # already 10 digits
        (lambda s, n: n == 11 and s[0] == "0", lambda s: s[1:]),          # 0xxxxxxxxxx
        (lambda s, n: n == 12 and s.startswith("91"), lambda s: s[2:]),   # 91xxxxxxxxxx
        (lambda s, n: n == 14 and s.startswith("0091"), lambda s: s[4:]), # 0091xxxxxxxxxx
        (lambda s, n: n > 10 and s[-10] in "6789", lambda s: s[-10:]),    # extract last valid 10
    )

    q = next((t(ζ) for p, t in _rules if p(ζ, ℓ)), None)
    return q if q and _r.match(r"^[6-9]\d{9}$", q) else None


# ======================
# FORCE JOIN CHECK
# ======================
async def check_force_join(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if user_id in ADMINS:
        return True

    missing = []
    for ch in FORCE_CHANNELS:
        try:
            m = await context.bot.get_chat_member(ch["chat_id"], user_id)
            if m.status in ("left", "kicked"):
                missing.append(ch)
        except:
            missing.append(ch)

    if not missing:
        return True

    kb = [[InlineKeyboardButton(f"Join {c['name']}", url=c["invite"])] for c in FORCE_CHANNELS]
    kb.append([InlineKeyboardButton("✅ I Joined", callback_data="fj_refresh")])

    txt = (
        "🔒 <b>Ares Security Check</b>\n"
        "━━━━━━━━━━━━━━━━━━\n"
        "Please join the required channels:\n\n"
        + "\n".join(f"• {c['name']}" for c in FORCE_CHANNELS) +
        "\n━━━━━━━━━━━━━━━━━━\n🔥 Powered by <b>Ares</b>"
    )

    await update.effective_message.reply_text(
        txt, parse_mode="HTML", reply_markup=InlineKeyboardMarkup(kb)
    )
    return False


# ======================
# START COMMAND
# ======================
async def start(update, context):
    if not await check_force_join(update, context):
        return

    await update.message.reply_text(
        "🎩 <b>Ares Premium Lookup Bot</b>\n"
        "━━━━━━━━━━━━━━━━━━\n"
        "📱 Send ANY Indian mobile number in ANY format.\n"
        "🤖 Bot will auto-detect it.\n"
        "━━━━━━━━━━━━━━━━━━\n🔥 Powered by <b>Ares</b>",
        parse_mode="HTML",
    )


# ======================
# BROADCAST
# ======================
async def broadcast(update, context):
    if update.effective_user.id not in ADMINS:
        return
    context.user_data["broadcast_mode"] = True
    await update.message.reply_text("📢 Send broadcast message.\n🔥 Powered by <b>Ares</b>", parse_mode="HTML")


# ======================
# BUTTON HANDLER (FOR FORCE JOIN)
# ======================
async def button_handler(update, context):
    q = update.callback_query
    await q.answer()

    if q.data == "fj_refresh":
        if await check_force_join(update, context):
            return await q.edit_message_text(
                "✅ Verified! You may continue.\n🔥 Powered by <b>Ares</b>",
                parse_mode="HTML",
            )


# ======================
# MAIN AUTO-DETECT TEXT HANDLER
# ======================
async def text_handler(update, context):
    msg = update.message
    user_id = msg.from_user.id
    raw_text = msg.text.strip()

    # Track Users
    if "users" not in context.bot_data:
        context.bot_data["users"] = set()
    context.bot_data["users"].add(user_id)

    # Broadcast Mode
    if user_id in ADMINS and context.user_data.get("broadcast_mode"):
        context.user_data["broadcast_mode"] = False
        sent = 0
        for uid in context.bot_data["users"]:
            try: await msg.copy(uid); sent += 1
            except: pass
        return await msg.reply_text(
            f"📢 Broadcast sent to {sent} users.\n🔥 Powered by <b>Ares</b>", parse_mode="HTML"
        )

    # Force Join
    if not await check_force_join(update, context):
        return

    # AUTO EXTRACT NUMBER
    number = nornum(raw_text)

    if not number:
        return  # SILENT MODE: ignore non-number msgs

    # RATE LIMIT
    now = time.time()
    if user_id in RATE_LIMIT and now - RATE_LIMIT[user_id] < 2:
        return
    RATE_LIMIT[user_id] = now

    # API REQUEST
    url = f"https://x2-proxy.vercel.app/api?num={number}"

    await msg.reply_text("⏳ Fetching premium details…\n🔥 Powered by <b>Ares</b>", parse_mode="HTML")

    try:
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=5)) as s:
            async with s.get(url) as r:
                data = await r.json()
    except:
        return await msg.reply_text("❌ No data found.\n🔥 Powered by <b>Ares</b>", parse_mode="HTML")

    results = data.get("result", [])
    final = (
        "🎩 <b>Ares Premium Lookup</b>\n"
        f"📞 Number: <code>{number}</code>\n"
        "━━━━━━━━━━━━━━━━━━\n\n"
    )

    # SAFE PARSING
    count = 0
    for r in results:
        if not isinstance(r, dict):
            continue

        count += 1
        final += (
            f"📦 <b>Record {count}</b>\n"
            f"👤 Name: {r.get('name','N/A')}\n"
            f"🧔 Father: {r.get('father_name','N/A')}\n"
            f"📍 Address:\n<code>{(r.get('address','N/A')).replace('!','\\n')}</code>\n"
            f"📡 Operator: {r.get('circle','N/A')}\n"
            f"📞 Alt: {r.get('alt_mobile','N/A')}\n"
            f"🆔 ID: {r.get('id_number','N/A')}\n"
            f"📧 Email: {r.get('email','N/A')}\n"
            "━━━━━━━━━━━━━━━━━━\n\n"
        )

    if count == 0:
        return await msg.reply_text("❌ No data found.\n🔥 Powered by <b>Ares</b>", parse_mode="HTML")

    final += "✨ <i>Result processed by Ares Premium Lookup</i>\n🔥 Powered by <b>Ares</b>"
    await msg.reply_text(final, parse_mode="HTML")


# ======================
# MAIN
# ======================
def main():
    app = ApplicationBuilder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("broadcast", broadcast))
    app.add_handler(CallbackQueryHandler(button_handler))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, text_handler))

    print("🔥 Ares Auto-Detect Bot Running — Smart, Silent, Premium…")
    app.run_polling()


if __name__ == "__main__":
    main()
