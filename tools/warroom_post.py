#!/usr/bin/env python3
"""Post a build-status update into the AI War Room under a chosen bot's token.
Usage: warroom_post.py <profile> "<message>"
Profiles: chief(scout|writer|desk|forge). Chief token lives in ~/.hermes/.env."""
import sys, os, urllib.parse, urllib.request

CHAT = "-5443630507"
profile = sys.argv[1]
message = sys.argv[2]

if profile == "chief":
    env = os.path.expanduser("~/.hermes/.env")
else:
    env = os.path.expanduser(f"~/.hermes/profiles/{profile}/.env")

tok = ""
with open(env) as fh:
    for line in fh:
        if line.startswith("TELEGRAM_BOT_TOKEN="):
            tok = line.split("=", 1)[1].strip()
if not tok:
    print(f"ERROR: no TELEGRAM_BOT_TOKEN in {env}")
    sys.exit(1)

data = urllib.parse.urlencode({"chat_id": CHAT, "text": message.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"), "parse_mode": "HTML"}).encode()
req = urllib.request.Request(f"https://api.telegram.org/bot{tok}/sendMessage", data=data)
try:
    resp = urllib.request.urlopen(req)
    print(f"{profile} ok= True")
except Exception as e:
    print(f"{profile} ok= False error= {e}")
