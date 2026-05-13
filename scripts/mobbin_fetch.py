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
# CDN account ID discovered via API probing (Task 1). May need updating if Mobbin rotates CDN config.
BYTESCALE_CDN = "https://bytescale.mobbin.com/FW25bBB/image/mobbin.com/prod"
SUPABASE_PUBLIC = "/storage/v1/object/public/"


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


def _supabase_to_cdn(screen_url: str) -> str:
    """Convert Supabase storage URL to Bytescale CDN URL (no auth needed)."""
    idx = screen_url.find(SUPABASE_PUBLIC)
    if idx == -1:
        return screen_url
    path = screen_url[idx + len(SUPABASE_PUBLIC):]
    return f"{BYTESCALE_CDN}/{path}?f=webp&w=1920&q=85&fit=shrink-cover"


def mobbin_request(path: str, body: dict, cookie: str) -> object:
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{MOBBIN_BASE}{path}",
        data=data,
        headers={
            "Cookie": cookie,
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            print("Error: Mobbin session expired — run: testpilot mobbin-login", file=sys.stderr)
            sys.exit(1)
        raise
    except urllib.error.URLError as e:
        print(f"Error: Could not reach Mobbin — check your internet connection. ({e.reason})", file=sys.stderr)
        sys.exit(1)


def search_flows(query: str, platform: str, limit: int, cookie: str) -> list[dict]:
    """Search Mobbin flows. Returns a flat list of screen dicts with normalized keys."""
    # Note: /search-flows uses flowActions taxonomy, not free-text; searchQuery is a best-effort addition
    result = mobbin_request("/api/content/search-flows", {
        "searchRequestId": "",
        "searchQuery": query,
        "filterOptions": {
            "platform": platform,
            "flowActions": None,
            "appCategories": None,
        },
        "paginationOptions": {
            "pageSize": limit,
            "pageIndex": 0,
            "sortBy": "publishedAt",
        },
    }, cookie)
    flows = result.get("value", {}).get("data", []) if isinstance(result, dict) else []
    if not flows:
        print(f'Error: No flows found for query "{query}". Try a different query.', file=sys.stderr)
        sys.exit(1)
    screens = []
    for flow in flows:
        app_name = flow.get("appName", "")
        for screen in flow.get("screens", []):
            screens.append({
                "app_name": app_name,
                "screen_url": screen.get("screenUrl", ""),
                "mobbin_url": f"https://mobbin.com/screens/{screen.get('screenId', '')}",
            })
    return screens


def download_image(screen_url: str) -> bytes:
    """Download a screen image via Bytescale CDN (no auth required)."""
    cdn_url = _supabase_to_cdn(screen_url)
    req = urllib.request.Request(cdn_url, headers={"Accept": "image/*"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read()
    except Exception as e:
        print(f"  Warning: image download failed ({e})", file=sys.stderr)
        return b""


def main():
    args = parse_args()
    cookie = load_cookie()
    print(f'Searching Mobbin for "{args.query}"...')
    screens = search_flows(args.query, args.platform, args.limit, cookie)
    print(f"Found {len(screens)} screens across flows.")
    if screens:
        img = download_image(screens[0]["screen_url"])
        print(f"First image ({screens[0]['app_name']}): {len(img)} bytes ({'ok' if img else 'EMPTY'})")


if __name__ == "__main__":
    main()
