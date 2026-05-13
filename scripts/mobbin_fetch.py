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


# ---------------------------------------------------------------------------
# AI analysis helpers
# ---------------------------------------------------------------------------

_SYSTEM_ANALYST = (
    "You are a senior UX researcher conducting competitive analysis. "
    "Examine the screenshot and identify ONE specific finding relevant to the objective. "
    'Respond ONLY with valid JSON: {"observation": "[CRITICAL/ISSUE/POSITIVE] specific finding"}'
)

_SYSTEM_PERSONA_TMPL = (
    "You are the following person using a mobile app:\n\n<persona>\n{persona}\n</persona>\n\n"
    "You are NOT a researcher — you ARE this person. "
    'Respond ONLY with valid JSON: {"observation": "[CRITICAL/ISSUE/POSITIVE] first-person experience"}'
)


def _user_prompt(app_name: str, objective: str, observations: list, lang: str) -> str:
    prev = "\n".join(f"{i+1}. {o}" for i, o in enumerate(observations[-10:])) or "None yet."
    lang_note = f"\nWrite your observation in {lang}." if lang != "en" else ""
    return (
        f"App: {app_name}\nObjective: {objective}\n"
        f"Previous observations (do NOT repeat):\n{prev}\n"
        f"Examine this screenshot and provide ONE UX observation.{lang_note}"
    )


def _parse_obs(raw: str) -> str:
    try:
        return json.loads(raw).get("observation", raw)
    except Exception:
        return raw.strip()


def _call_anthropic(b64: str, system: str, prompt: str, api_key: str) -> str:
    body = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 512,
        "system": system,
        "messages": [{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/webp", "data": b64}},
            {"type": "text", "text": prompt},
        ]}],
    }
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(body).encode(),
        headers={"x-api-key": api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return _parse_obs(json.loads(resp.read())["content"][0]["text"])


def _call_openai(b64: str, system: str, prompt: str, api_key: str) -> str:
    body = {
        "model": "gpt-4o",
        "max_tokens": 512,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:image/webp;base64,{b64}"}},
                {"type": "text", "text": prompt},
            ]},
        ],
    }
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return _parse_obs(json.loads(resp.read())["choices"][0]["message"]["content"])


def _call_gemini(b64: str, prompt: str, api_key: str) -> str:
    body = {"contents": [{"parts": [
        {"inline_data": {"mime_type": "image/webp", "data": b64}},
        {"text": prompt},
    ]}]}
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"gemini-2.5-flash:generateContent?key={api_key}"
    )
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                  headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return _parse_obs(json.loads(resp.read())["candidates"][0]["content"]["parts"][0]["text"])


def analyze_screen(image_bytes: bytes, app_name: str, objective: str,
                   observations: list, provider: str, api_key: str,
                   lang: str, persona: str) -> str:
    b64 = base64.b64encode(image_bytes).decode()
    system = _SYSTEM_PERSONA_TMPL.format(persona=persona.strip()) if persona else _SYSTEM_ANALYST
    prompt = _user_prompt(app_name, objective, observations, lang)
    if provider == "anthropic":
        return _call_anthropic(b64, system, prompt, api_key)
    if provider == "openai":
        return _call_openai(b64, system, prompt, api_key)
    return _call_gemini(b64, prompt, api_key)


def generate_summary(observations: list, objective: str, provider: str, api_key: str, lang: str) -> str:
    lang_note = f"Write in {lang}." if lang != "en" else ""
    obs_text = "\n".join(f"{i+1}. {o}" for i, o in enumerate(observations))
    prompt = (
        f"Objective: {objective}\n\nObservations from {len(observations)} screens:\n{obs_text}\n\n"
        "Synthesize a concise competitive analysis (3-5 bullet points as HTML <ul><li>). "
        "Focus on cross-app patterns: what works, what doesn't, standout design decisions. "
        f"{lang_note}\n"
        'Respond with JSON: {"summary": "<ul><li>point 1</li>...</ul>"}'
    )
    system = "You are a senior UX researcher synthesizing competitive findings."

    if provider == "anthropic":
        body = {"model": "claude-sonnet-4-6", "max_tokens": 1024, "system": system,
                "messages": [{"role": "user", "content": prompt}]}
        req = urllib.request.Request("https://api.anthropic.com/v1/messages",
            data=json.dumps(body).encode(),
            headers={"x-api-key": api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return _parse_obs(json.loads(resp.read())["content"][0]["text"])

    if provider == "openai":
        body = {"model": "gpt-4o", "max_tokens": 1024,
                "messages": [{"role": "system", "content": system}, {"role": "user", "content": prompt}]}
        req = urllib.request.Request("https://api.openai.com/v1/chat/completions",
            data=json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            return _parse_obs(json.loads(resp.read())["choices"][0]["message"]["content"])

    body = {"contents": [{"parts": [{"text": prompt}]}]}
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return _parse_obs(json.loads(resp.read())["candidates"][0]["content"]["parts"][0]["text"])


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
