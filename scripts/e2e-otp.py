#!/usr/bin/env python3
"""Hands one-time codes from the local API (scripts/e2e-api.sh) to the UI tests.

The API keeps only HMAC(otp key, "email:code") in Redis, under a hash of the email, so a test asks
for an email by creating `<email>.want` in DIR, and this writes the code to `<email>.txt`, trying
every 6-digit code against the hash. Runs until stopped.

Usage: e2e-otp.py DIR
"""
import hashlib
import hmac
import json
import pathlib
import subprocess
import sys
import time

APP_KEY = b"local-ios-dev-app-key-0123456789abcdef0123456789"
OTP_KEY = hmac.new(APP_KEY, b"otp", hashlib.sha256).digest()


def stored_hash(email):
    key = "otp:email:" + hashlib.sha256(email.encode()).hexdigest()
    raw = subprocess.run(["docker", "exec", "vomatt-ios-redis", "redis-cli", "GET", key], capture_output=True, text=True).stdout
    return json.loads(raw)["codeHash"] if raw.strip() else None


def code(email, target):
    for n in range(1_000_000):
        guess = f"{n:06d}"
        if hmac.new(OTP_KEY, f"{email}:{guess}".encode(), hashlib.sha256).hexdigest() == target:
            return guess
    return None


def main(folder):
    folder.mkdir(parents=True, exist_ok=True)
    solved = {}
    while True:
        for want in folder.glob("*.want"):
            email = want.name.removesuffix(".want")
            target = stored_hash(email)
            # A resend stores a new hash; solve each one once
            if target and solved.get(email) != target and (found := code(email, target)):
                (folder / f"{email}.txt").write_text(found)
                solved[email] = target
        time.sleep(0.3)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(pathlib.Path(sys.argv[1]))
