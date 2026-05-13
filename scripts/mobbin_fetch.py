#!/usr/bin/env python3
"""TestPilot Mobbin: analyze Mobbin screens with AI."""

import argparse
import base64
import html as html_lib
import json
import os
import re
import sys
import urllib.error
import urllib.request

SESSION_PATH = os.path.expanduser("~/.testpilot/sessions/mobbin.com.json")
MOBBIN_BASE = "https://mobbin.com"


def parse_args():
    p = argparse.ArgumentParser(description="Analyze Mobbin screens with AI.")
    p.add_argument("--query", required=True)
    p.add_argument("--objective", required=True)
    p.add_argument("--platform", default="ios", choices=["ios", "web"])
    p.add_argument("--limit", type=int, default=20)
    p.add_argument("--output", default="./report.html")
    p.add_argument("--provider", default="anthropic", choices=["anthropic", "openai", "gemini"])
    p.add_argument("--api-key", required=True, dest="api_key")
    p.add_argument("--lang", default="en")
    p.add_argument("--persona", default="")
    return p.parse_args()


def load_cookie() -> str:
    if not os.path.exists(SESSION_PATH):
        print("Error: Mobbin session not found — run: testpilot mobbin-login", file=sys.stderr)
        sys.exit(1)
    with open(SESSION_PATH) as f:
        state = json.load(f)
    cookies = [c for c in state.get("cookies", []) if "mobbin.com" in c.get("domain", "")]
    if not cookies:
        print("Error: Mobbin session expired — run: testpilot mobbin-login", file=sys.stderr)
        sys.exit(1)
    return "; ".join(f"{c['name']}={c['value']}" for c in cookies)


def main():
    args = parse_args()
    cookie = load_cookie()
    print(f'Searching Mobbin for "{args.query}"...')


if __name__ == "__main__":
    main()
