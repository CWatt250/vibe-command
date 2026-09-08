#!/usr/bin/env python3
"""Send a photo into the AI War Room under a chosen bot's token.
Usage: warroom_photo.py <profile> <image_path> <caption>"""
import sys, os, urllib.request, json
from urllib.parse import urlencode

CHAT = "-5443630507"
profile = sys.argv[1]
img_path = sys.argv[2]
caption = sys.argv[3]

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

# Multipart upload of the image (sendPhoto).
boundary = "----hermes_warroom_boundary"
parts = []
with open(img_path, "rb") as f:
    img = f.read()
parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n{CHAT}\r\n".encode())
parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n{caption}\r\n".encode())
parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"shot.png\"\r\nContent-Type: image/png\r\n\r\n".encode() + img + b"\r\n")
parts.append(f"--{boundary}--\r\n".encode())
body = b"".join(parts)

req = urllib.request.Request(
    f"https://api.telegram.org/bot{tok}/sendPhoto",
    data=body,
    headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
try:
    urllib.request.urlopen(req)
    print(f"{profile} photo ok= True")
except Exception as e:
    print(f"{profile} photo ok= False error= {e}")
