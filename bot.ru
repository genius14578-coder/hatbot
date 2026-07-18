import json
import os
import time
import urllib.request
import urllib.parse
import ssl

# ========== НАСТРОЙКИ ==========
BOT_TOKEN = "8249451082:AAFYWt2GP14kkbAXqZZN8Isyv7L7BpF2SbI"
ADMIN_ID = 1763274069
# =================================================

DATA_FILE = "hats.json"
OFFSET_FILE = "offset.txt"
API_URL = f"https://api.telegram.org/bot{BOT_TOKEN}/"

ssl_ctx = ssl.create_default_context()
ssl_ctx.check_hostname = False
ssl_ctx.verify_mode = ssl.CERT_NONE

PROXY = "proxy.server:3128"
proxy_handler = urllib.request.ProxyHandler({"https": PROXY, "http": PROXY})
opener = urllib.request.build_opener(proxy_handler)

if os.path.exists(OFFSET_FILE):
    with open(OFFSET_FILE, "r") as f:
        OFFSET = int(f.read().strip())
else:
    OFFSET = 0

waiting_for_first_comment = False
awarded_post_ids = set()

WELCOME_TEXT = """Привет! 🎩💜 
Я – помощник Хатвала. Этот болван надышался и забыл считать... Поэтому я здесь. Соревнуйся с другими пони за первый комментарий, собирай шляпы. В конце месяца тот, у кого их больше всех, получит скин или арт. Шляпа следит. Я считаю. Удачи!
⟥─────────🎩─────────⟤
/моишляпы – посмотреть своё количество шляп.
/топ – список лидеров"""

def api(method, data=None):
    url = API_URL + method
    if data:
        url += "?" + urllib.parse.urlencode(data)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with opener.open(req, timeout=30) as r:
        return json.loads(r.read().decode())

def load_data():
    if os.path.exists(DATA_FILE):
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}

def save_data(data):
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def send_reply(chat_id, message_id, text):
    api("sendMessage", {
        "chat_id": chat_id,
        "text": text,
        "reply_to_message_id": message_id
    })

def send_message(chat_id, text):
    api("sendMessage", {"chat_id": chat_id, "text": text})

def get_display_name(user):
    username = user.get("username")
    if username:
        return f"@{username}"
    first = user.get("first_name", "")
    last = user.get("last_name", "")
    full = f"{first} {last}".strip()
    return full if full else f"id{user['id']}"

def get_key(user):
    username = user.get("username")
    return username if username else str(user["id"])

def handle_update(update):
    global OFFSET, waiting_for_first_comment
    OFFSET = update["update_id"] + 1

    # --- Новый пост в канале ---
    channel_post = update.get("channel_post")
    if channel_post:
        post_id = channel_post["message_id"]
        if post_id not in awarded_post_ids:
            waiting_for_first_comment = True
            print(f"Новый пост {post_id}! Жду первый комментарий.")
        return

    # --- Сообщение в чате ---
    message = update.get("message")
    if not message:
        return

    text = message.get("text", "")
    chat_id = message["chat"]["id"]
    message_id = message["message_id"]
    user = message["from"]
    user_id = user["id"]
    display_name = get_display_name(user)
    key = get_key(user)

    # --- /start ---
    if text.startswith("/start"):
        send_message(chat_id, WELCOME_TEXT)
        return

    # --- АВТО-ШЛЯПА ---
    if waiting_for_first_comment and not text.startswith("/"):
        reply = message.get("reply_to_message")
        if reply:
            replied_post_id = reply.get("message_id")
            if replied_post_id and replied_post_id not in awarded_post_ids:
                awarded_post_ids.add(replied_post_id)
                waiting_for_first_comment = False
                data = load_data()
                data[key] = data.get(key, 0) + 1
                save_data(data)
                send_reply(chat_id, message_id, f"🎩 Первый комментарий! Шляпа вручена {display_name}! Всего шляп: {data[key]}")
                return

    # --- /снятьшляпу ---
    if text.startswith("/снятьшляпу"):
        if user_id != ADMIN_ID:
            send_reply(chat_id, message_id, "⛔ Только админ может снимать шляпы.")
            return
        parts = text.split()
        if len(parts) < 2:
            send_reply(chat_id, message_id, "ℹ️ Использование: /снятьшляпу @username")
            return
        target = parts[1]
        target_user = target[1:] if target.startswith("@") else target
        data = load_data()
        current = data.get(target_user, 0)
        if current > 0:
            data[target_user] = current - 1
            save_data(data)
            send_reply(chat_id, message_id, f"🎩 Шляпа снята с @{target_user}. Всего шляп: {data[target_user]}")
        else:
            send_reply(chat_id, message_id, f"⚠️ У @{target_user} и так нет шляп.")
        return

    # --- /сброс ---
    if text.startswith("/сброс"):
        if user_id != ADMIN_ID:
            send_reply(chat_id, message_id, "⛔ Только админ может сбрасывать счёт.")
            return
        save_data({})
        awarded_post_ids.clear()
        waiting_for_first_comment = False
        send_reply(chat_id, message_id, "🔄 Все шляпы аннулированы. Новый сезон открыт!")
        return

    # --- /шляпа ---
    if text.startswith("/шляпа"):
        if user_id != ADMIN_ID:
            send_reply(chat_id, message_id, "⛔ Только админ может выдавать шляпы.")
            return
        parts = text.split()
        if len(parts) < 2:
            send_reply(chat_id, message_id, "ℹ️ Использование: /шляпа @username")
            return
        target = parts[1]
        target_user = target[1:] if target.startswith("@") else target
        data = load_data()
        data[target_user] = data.get(target_user, 0) + 1
        save_data(data)
        send_reply(chat_id, message_id, f"🎩 Шляпа вручена @{target_user}! Всего шляп: {data[target_user]}")
        return

    # --- /моишляпы ---
    if text.startswith("/моишляпы"):
        data = load_data()
        count = data.get(key, 0)
        send_reply(chat_id, message_id, f"🎩 У тебя {count} шляп(ы).")
        return

    # --- /топ ---
    if text.startswith("/топ"):
        data = load_data()
        if not data:
            send_reply(chat_id, message_id, "🏜 Пока никто не получил ни одной шляпы.")
            return
        sorted_players = sorted(data.items(), key=lambda x: x[1], reverse=True)[:10]
        text_lines = ["🏆 Топ-10 обладателей шляп:\n"]
        for i, (name, score) in enumerate(sorted_players, 1):
            display = f"@{name}" if not name.startswith("-") and not name.isdigit() else name
            text_lines.append(f"{i}. {display} — {score} шляп(ы)")
        send_reply(chat_id, message_id, "\n".join(text_lines))
        return

print("✅ Бот v.10 (с /start) запущен!")
while True:
    try:
        updates = api("getUpdates", {"offset": OFFSET, "timeout": 30})
        if updates.get("result"):
            for upd in updates["result"]:
                handle_update(upd)
            with open(OFFSET_FILE, "w") as f:
                f.write(str(OFFSET))
    except Exception as e:
        print(f"Ошибка: {e}")
        time.sleep(5)