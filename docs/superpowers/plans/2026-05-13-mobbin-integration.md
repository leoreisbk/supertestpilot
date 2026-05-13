# TestPilot Mobbin Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `./testpilot mobbin --query "..." --objective "..."` that searches Mobbin, analyzes each screen with AI, and generates an HTML report — no JVM, no Xcode, no `claude` CLI required.

**Architecture:** `scripts/mobbin_fetch.py` (pure Python stdlib, no external deps) called from the bash CLI. Reads session cookies from `~/.testpilot/sessions/mobbin.com.json`, POSTs to `https://mobbin.com/api/content/search-screens`, downloads screen images, calls AI API per screen, writes HTML report. The bash CLI adds a `mobbin` command that invokes the Python script.

**Tech Stack:** Python 3 stdlib (urllib, json, base64, html, argparse, re, os), Anthropic/OpenAI/Gemini HTTP APIs.

**Key API facts (discovered via MCP):**
- Search endpoint: `POST https://mobbin.com/api/content/search-screens`
- Auth: Supabase session cookies from `~/.testpilot/sessions/mobbin.com.json` (Playwright storageState format)
- Response top-level key: `screens` (array)
- Each screen: `id`, `image_url` (short redirect URL), `mobbin_url`, `app_name`, `platform`
- Images are downloaded via `image_url` with session cookie auth

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `scripts/mobbin_fetch.py` | All Python logic: search, download, AI analysis, HTML report |
| Modify | `testpilot` (bash) | Add `mobbin` command, parse `--query`/`--limit` flags |

---

### Task 1: Probe raw Mobbin API

**Files:** None changed — discovery only

- [ ] **Step 1: Check session cookies**

```bash
python3 -c "
import json, os
s = json.load(open(os.path.expanduser('~/.testpilot/sessions/mobbin.com.json')))
cookies = s.get('cookies', [])
mobbin_cookies = [c for c in cookies if 'mobbin.com' in c.get('domain', '')]
print('Mobbin cookie count:', len(mobbin_cookies))
print('Names:', [c['name'] for c in mobbin_cookies])
"
```

Expected: count > 0, names include `sb-ujasntkfphywizsdaapi-auth-token.0` and `.1`

- [ ] **Step 2: Call search endpoint and inspect response**

```bash
python3 -c "
import json, os, urllib.request
s = json.load(open(os.path.expanduser('~/.testpilot/sessions/mobbin.com.json')))
cookie_str = '; '.join(f\"{c['name']}={c['value']}\" for c in s.get('cookies',[]) if 'mobbin.com' in c.get('domain',''))
body = json.dumps({'query': 'onboarding', 'platform': 'ios', 'limit': 2}).encode()
req = urllib.request.Request('https://mobbin.com/api/content/search-screens', data=body,
    headers={'Cookie': cookie_str, 'Content-Type': 'application/json', 'Accept': 'application/json'})
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())
    top = list(data.keys()) if isinstance(data, dict) else 'array'
    items = data.get('screens', data.get('data', data)) if isinstance(data, dict) else data
    print('Top-level keys:', top)
    if items:
        print('First item keys:', list(items[0].keys()))
        for k, v in items[0].items():
            print(f'  {k}:', str(v)[:100])
except Exception as e:
    print('Error:', type(e).__name__, e)
"
```

Expected: top-level key is `screens`, each item has `image_url` and `mobbin_url`.

- [ ] **Step 3: Try downloading an image with session cookie**

Replace `IMAGE_URL` with the `image_url` value from step 2.

```bash
python3 -c "
import json, os, urllib.request
s = json.load(open(os.path.expanduser('~/.testpilot/sessions/mobbin.com.json')))
cookie_str = '; '.join(f\"{c['name']}={c['value']}\" for c in s.get('cookies',[]) if 'mobbin.com' in c.get('domain',''))
IMAGE_URL = 'REPLACE_WITH_image_url_FROM_STEP_2'
req = urllib.request.Request(IMAGE_URL, headers={'Cookie': cookie_str})
try:
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = resp.read()
        print('Content-Type:', resp.headers.get('Content-Type'))
        print('Size:', len(data), 'bytes — SUCCESS')
except Exception as e:
    print('Failed:', e)
"
```

Expected: `Content-Type: image/jpeg`, `Size > 50000 bytes — SUCCESS`

If download fails (403/redirect loop): the `image_url` needs cookie on the final CDN domain too — note this for Task 3 adjustments.

---

### Task 2: Python skeleton + arg parsing + session loading

**Files:**
- Create: `scripts/mobbin_fetch.py`

- [ ] **Step 1: Write skeleton**

```python
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
```

- [ ] **Step 2: Make executable and test**

```bash
chmod +x scripts/mobbin_fetch.py
python3 scripts/mobbin_fetch.py --query "test" --objective "test" --api-key "dummy"
```

Expected: `Searching Mobbin for "test"...`

- [ ] **Step 3: Commit**

```bash
git add scripts/mobbin_fetch.py
git commit -m "feat(mobbin): Python script skeleton with session loading"
```

---

### Task 3: Mobbin search + image download

**Files:**
- Modify: `scripts/mobbin_fetch.py`

- [ ] **Step 1: Add `mobbin_request` helper**

```python
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
```

- [ ] **Step 2: Add `search_screens`**

```python
def search_screens(query: str, platform: str, limit: int, cookie: str) -> list:
    result = mobbin_request("/api/content/search-screens", {
        "query": query,
        "platform": platform,
        "limit": limit,
    }, cookie)
    items = result.get("screens", result.get("data", result)) if isinstance(result, dict) else result
    if not items:
        print(f'Error: No screens found for query "{query}". Try a different query.', file=sys.stderr)
        sys.exit(1)
    return items
```

- [ ] **Step 3: Add `download_image`**

```python
def download_image(screen: dict, cookie: str) -> bytes:
    url = screen.get("image_url") or screen.get("screenshot_url") or screen.get("url", "")
    if not url:
        return b""
    req = urllib.request.Request(url, headers={"Cookie": cookie, "Accept": "image/*"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.read()
    except Exception as e:
        print(f"  Warning: image download failed for {screen.get('app_name', '?')}: {e}")
        return b""
```

- [ ] **Step 4: Wire into `main()` and test**

Replace the `main()` body with:

```python
def main():
    args = parse_args()
    cookie = load_cookie()
    print(f'Searching Mobbin for "{args.query}"...')
    screens = search_screens(args.query, args.platform, args.limit, cookie)
    print(f"Found {len(screens)} screens.")
    img = download_image(screens[0], cookie)
    print(f"First image: {len(img)} bytes ({'ok' if img else 'EMPTY — check Task 1 findings'})")
```

```bash
python3 scripts/mobbin_fetch.py \
  --query "onboarding" --objective "test" --api-key "dummy"
```

Expected:
```
Searching Mobbin for "onboarding"...
Found 20 screens.
First image: NNNNN bytes (ok)
```

- [ ] **Step 5: Commit**

```bash
git add scripts/mobbin_fetch.py
git commit -m "feat(mobbin): Mobbin search and image download"
```

---

### Task 4: AI analysis per screen

**Files:**
- Modify: `scripts/mobbin_fetch.py`

- [ ] **Step 1: Add system prompts and user prompt builder**

```python
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
```

- [ ] **Step 2: Add per-provider vision callers**

```python
def _call_anthropic(b64: str, system: str, prompt: str, api_key: str) -> str:
    body = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 512,
        "system": system,
        "messages": [{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": b64}},
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
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
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
        {"inline_data": {"mime_type": "image/jpeg", "data": b64}},
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
```

- [ ] **Step 3: Add text-only summary call**

```python
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
```

- [ ] **Step 4: Commit**

```bash
git add scripts/mobbin_fetch.py
git commit -m "feat(mobbin): add multi-provider AI screen analysis and summary"
```

---

### Task 5: Analysis loop

**Files:**
- Modify: `scripts/mobbin_fetch.py`

- [ ] **Step 1: Replace `main()` with full loop**

```python
def main():
    args = parse_args()
    cookie = load_cookie()
    print(f'Searching Mobbin for "{args.query}"...')
    screens = search_screens(args.query, args.platform, args.limit, cookie)
    print(f"Found {len(screens)} screens. Analyzing...")

    steps = []       # {"app_name", "mobbin_url", "image_b64", "observation"}
    observations = []  # running list for dedup context

    for i, screen in enumerate(screens):
        app_name = screen.get("app_name", f"App {i + 1}")
        mobbin_url = screen.get("mobbin_url", "")
        print(f"  [{i + 1}/{len(screens)}] {app_name}...", end=" ", flush=True)

        image_bytes = download_image(screen, cookie)
        if not image_bytes:
            print("skip (no image)")
            steps.append({"app_name": app_name, "mobbin_url": mobbin_url,
                           "image_b64": "", "observation": "Could not load image."})
            continue

        try:
            observation = analyze_screen(
                image_bytes, app_name, args.objective,
                observations, args.provider, args.api_key, args.lang, args.persona,
            )
            observations.append(f"{app_name}: {observation}")
            print("done")
        except Exception as e:
            observation = f"Analysis error: {e}"
            print(f"error: {e}")

        steps.append({
            "app_name": app_name,
            "mobbin_url": mobbin_url,
            "image_b64": base64.b64encode(image_bytes).decode(),
            "observation": observation,
        })

    if not observations:
        print("Error: no screens could be analyzed.", file=sys.stderr)
        sys.exit(1)

    print("Generating summary...")
    summary = generate_summary(observations, args.objective, args.provider, args.api_key, args.lang)

    # report written in Task 6
    print(f"Done. {len(steps)} screens analyzed.")
    print(f"Summary: {summary[:120]}...")
```

- [ ] **Step 2: Smoke test without report**

```bash
python3 scripts/mobbin_fetch.py \
  --query "onboarding" --objective "identify friction points" \
  --limit 3 --provider anthropic --api-key "$TESTPILOT_API_KEY"
```

Expected: 3 screens analyzed, summary printed.

- [ ] **Step 3: Commit**

```bash
git add scripts/mobbin_fetch.py
git commit -m "feat(mobbin): add analysis loop"
```

---

### Task 6: HTML report generation

**Files:**
- Modify: `scripts/mobbin_fetch.py`

- [ ] **Step 1: Add `_badge`, `_render_obs`, and `generate_report`**

```python
def _badge(obs: str) -> str:
    u = obs.upper()
    if "[CRITICAL]" in u:
        return '<span class="badge badge-critical">CRITICAL</span>'
    if "[ISSUE]" in u:
        return '<span class="badge badge-issue">ISSUE</span>'
    if "[POSITIVE]" in u:
        return '<span class="badge badge-positive">POSITIVE</span>'
    return ""


def _render_obs(obs: str) -> str:
    badge = _badge(obs)
    clean = html_lib.escape(re.sub(r"\[(CRITICAL|ISSUE|POSITIVE)\]\s*", "", obs))
    return f"{badge} {clean}"


_CSS = """* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
       background: #f5f5f7; color: #1d1d1f; line-height: 1.5; }
.header { background: #fff; padding: 32px 40px; border-bottom: 1px solid #e5e5ea; }
.header h1 { font-size: 22px; font-weight: 600; margin-bottom: 8px; }
.header .objective { color: #6e6e73; font-size: 15px; }
.meta { margin-top: 12px; font-size: 13px; color: #8e8e93; }
.persona-card { display: flex; gap: 10px; align-items: flex-start; margin-top: 14px;
                background: #f2f2f7; border-radius: 8px; padding: 10px 14px; }
.persona-icon { font-size: 20px; }
.persona-label { font-size: 11px; color: #8e8e93; text-transform: uppercase; letter-spacing: .04em; }
.persona-text { font-size: 13px; font-weight: 500; }
.summary-box { margin: 24px 40px; background: #fff; border-radius: 12px;
               padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
.summary-box h2 { font-size: 15px; font-weight: 600; margin-bottom: 8px; }
.summary-content { font-size: 14px; color: #3a3a3c; }
.summary-content ul { padding-left: 18px; }
.summary-content li { margin-bottom: 3px; }
.steps { padding: 0 40px 40px; }
.steps h2 { font-size: 15px; font-weight: 600; margin: 24px 0 12px; }
.step { background: #fff; border-radius: 12px; margin-bottom: 16px;
        box-shadow: 0 1px 3px rgba(0,0,0,.08); }
.step-header { display: flex; align-items: center; gap: 10px; padding: 12px 16px;
               background: #f2f2f7; border-radius: 12px 12px 0 0; }
.step-num { font-size: 12px; color: #8e8e93; }
.action { font-size: 13px; font-weight: 600; }
.action a { color: #007aff; text-decoration: none; }
.step-body { display: flex; flex-direction: row; align-items: flex-start; }
.step-img-col { flex: 0 0 40%; padding: 12px; }
.step-img-col img { display: block; width: 100%; height: auto; border-radius: 8px; }
.step-obs-col { flex: 1; padding: 16px 16px 16px 8px; font-size: 14px; line-height: 1.6; color: #3a3a3c; }
.step-obs-empty { color: #aeaeb2; font-style: italic; }
.badge { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: .06em;
         padding: 1px 6px; border-radius: 3px; margin-right: 6px; }
.badge-critical { background: #ff3b30; color: #fff; }
.badge-issue { background: #ff9500; color: #fff; }
.badge-positive { background: #34c759; color: #fff; }
@media (max-width: 600px) { .step-body { flex-direction: column; } .step-img-col { width: 100%; flex: none; } }
@media (prefers-color-scheme: dark) {
  body { background: #1c1c1e; color: #f5f5f7; }
  .header { background: #2c2c2e; border-bottom-color: #3a3a3c; }
  .header .objective { color: #aeaeb2; }
  .summary-box, .step { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
  .step-header { background: #3a3a3c; }
  .step-num { color: #636366; }
  .summary-content { color: #ebebf0; }
  .step-obs-col { color: #ebebf0; }
}"""


def generate_report(steps: list, query: str, objective: str, summary: str,
                    lang: str, persona: str) -> str:
    ptbr = lang.startswith("pt")
    title = "Relatório de Pesquisa TestPilot" if ptbr else "TestPilot Research Report"
    sum_label = "Resumo" if ptbr else "Summary"
    screen_label = "Tela" if ptbr else "Screen"
    analyzed_label = "Telas analisadas" if ptbr else "Analyzed screens"
    eval_label = "Avaliado como" if ptbr else "Evaluated as"

    persona_card = ""
    if persona:
        first = html_lib.escape(next((l.lstrip("# ") for l in persona.splitlines() if l.strip()), "Persona"))
        persona_card = (
            f'<div class="persona-card"><span class="persona-icon">👤</span>'
            f'<div class="persona-content"><div class="persona-label">{eval_label}</div>'
            f'<div class="persona-text">{first}</div></div></div>'
        )

    steps_html = ""
    for i, step in enumerate(steps):
        img_tag = (
            f'<img src="data:image/jpeg;base64,{step["image_b64"]}" '
            f'alt="{screen_label} {i+1}" loading="lazy" />'
        ) if step["image_b64"] else ""
        app_link = (
            f'<a href="{html_lib.escape(step["mobbin_url"])}" target="_blank">'
            f'{html_lib.escape(step["app_name"])}</a>'
        ) if step["mobbin_url"] else html_lib.escape(step["app_name"])
        obs_html = (
            f'<p>{_render_obs(step["observation"])}</p>'
            if step["observation"] else '<p class="step-obs-empty">—</p>'
        )
        steps_html += (
            f'<div class="step"><div class="step-header">'
            f'<span class="step-num">{screen_label} {i+1}</span>'
            f'<span class="action">{app_link}</span></div>'
            f'<div class="step-body"><div class="step-img-col">{img_tag}</div>'
            f'<div class="step-obs-col">{obs_html}</div></div></div>'
        )

    return (
        f'<!DOCTYPE html><html lang="{"pt-BR" if ptbr else "en"}">\n'
        f'<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">\n'
        f'<title>{title}</title><style>{_CSS}</style></head>\n<body>\n'
        f'<div class="header"><h1>{title}</h1>'
        f'<div class="objective">{html_lib.escape(objective)}</div>'
        f'<div class="meta">Query: &ldquo;{html_lib.escape(query)}&rdquo; &middot; {len(steps)} screens</div>'
        f'{persona_card}</div>\n'
        f'<div class="summary-box"><h2>{sum_label}</h2>'
        f'<div class="summary-content">{summary}</div></div>\n'
        f'<div class="steps"><h2>{analyzed_label}</h2>{steps_html}</div>\n'
        f'</body></html>'
    )
```

- [ ] **Step 2: Wire into `main()` — write file and open**

After `summary = generate_summary(...)` in `main()`, replace the debug prints:

```python
    report_html = generate_report(steps, args.query, args.objective, summary, args.lang, args.persona)
    output_path = os.path.abspath(args.output)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(report_html)
    print(f"Report written to: {output_path}")
    os.system(f'open "{output_path}"')
```

- [ ] **Step 3: Commit**

```bash
git add scripts/mobbin_fetch.py
git commit -m "feat(mobbin): add HTML report generation"
```

---

### Task 7: CLI integration

**Files:**
- Modify: `testpilot` (bash)

- [ ] **Step 1: Add `mobbin` to command validation (line 23)**

Find:
```bash
if [[ "$COMMAND" != "analyze" && "$COMMAND" != "test" && "$COMMAND" != "web-login" && "$COMMAND" != "mobbin-login" && "$COMMAND" != "research" ]]; then
```

Replace with:
```bash
if [[ "$COMMAND" != "analyze" && "$COMMAND" != "test" && "$COMMAND" != "web-login" && "$COMMAND" != "mobbin-login" && "$COMMAND" != "research" && "$COMMAND" != "mobbin" ]]; then
```

- [ ] **Step 2: Add `mobbin` to the usage message**

In the usage block (before `exit 1`), after the last `echo ""` line, add:
```bash
  echo "       ./testpilot mobbin --query <text> --objective <text>"
  echo "       [--platform ios|web] [--limit <n>] [--output <path>]"
  echo "       [--provider anthropic|openai|gemini] [--api-key <key>]"
  echo "       [--lang en|pt-BR] [--persona <file>]"
  echo ""
```

- [ ] **Step 3: Add `MOBBIN_QUERY` and `MOBBIN_LIMIT` variables**

After line `MOBBIN_FLOW_NAME=""` (line 19), add:
```bash
MOBBIN_QUERY=""
MOBBIN_LIMIT=20
```

- [ ] **Step 4: Add `--query` and `--limit` to flag parser**

In the `while [[ $# -gt 0 ]]` loop, add before the `*) echo ...` catch-all:
```bash
    --query)    MOBBIN_QUERY="$2";  shift 2 ;;
    --limit)    MOBBIN_LIMIT="$2";  shift 2 ;;
```

- [ ] **Step 5: Add `mobbin` command handler block**

After the `research` block (after line 229), add:
```bash
# ── mobbin: AI analysis of Mobbin screens ─────────────────────────────────────
if [[ "$COMMAND" == "mobbin" ]]; then
  [[ -z "$MOBBIN_QUERY" ]] && { echo "Error: --query required for mobbin"; exit 1; }
  [[ -z "$OBJECTIVE" ]]    && { echo "Error: --objective required for mobbin"; exit 1; }
  [[ -z "$API_KEY" ]]      && { echo "Error: API key required (--api-key or TESTPILOT_API_KEY in .env)"; exit 1; }

  PERSONA_CONTENT=""
  if [[ -n "$PERSONA_FILE" ]]; then
    [[ ! -f "$PERSONA_FILE" ]] && { echo "Error: persona file not found: $PERSONA_FILE"; exit 1; }
    PERSONA_CONTENT="$(cat "$PERSONA_FILE")"
  fi

  python3 "$SCRIPT_DIR/scripts/mobbin_fetch.py" \
    --query "$MOBBIN_QUERY" \
    --objective "$OBJECTIVE" \
    --platform "${PLATFORM:-ios}" \
    --limit "$MOBBIN_LIMIT" \
    --output "$OUTPUT" \
    --provider "$PROVIDER" \
    --api-key "$API_KEY" \
    --lang "$LANG_CODE" \
    --persona "$PERSONA_CONTENT"
  exit $?
fi
```

- [ ] **Step 6: Commit**

```bash
git add testpilot
git commit -m "feat(mobbin): add mobbin subcommand to CLI"
```

---

### Task 8: End-to-end smoke test

**Files:** No changes expected

- [ ] **Step 1: Run with real session and API key**

```bash
./testpilot mobbin \
  --query "onboarding flow" \
  --objective "identify friction points and standout design patterns" \
  --platform ios \
  --limit 5 \
  --output /tmp/mobbin-test.html
```

Expected output:
```
Searching Mobbin for "onboarding flow"...
Found 5 screens. Analyzing...
  [1/5] <AppName>... done
  [2/5] <AppName>... done
  [3/5] <AppName>... done
  [4/5] <AppName>... done
  [5/5] <AppName>... done
Generating summary...
Report written to: /tmp/mobbin-test.html
```

- [ ] **Step 2: Verify the HTML report**

Open `/tmp/mobbin-test.html` and check:
- Title shows "TestPilot Research Report"
- Meta line shows query and screen count
- Summary section has bullet points synthesizing patterns
- Each screen card: thumbnail + clickable app name (links to mobbin.com/screens/...) + observation
- CRITICAL/ISSUE/POSITIVE badges appear on observations
- Dark mode renders correctly (open in Safari, toggle dark mode)

- [ ] **Step 3: Test error cases**

```bash
# Missing session
mv ~/.testpilot/sessions/mobbin.com.json /tmp/mobbin-backup.json
./testpilot mobbin --query "test" --objective "test"
# Expected: Error: Mobbin session not found — run: testpilot mobbin-login
mv /tmp/mobbin-backup.json ~/.testpilot/sessions/mobbin.com.json

# No results
./testpilot mobbin --query "xyzzy-gibberish-12345" --objective "test"
# Expected: Error: No screens found for query "xyzzy-gibberish-12345". Try a different query.
```

- [ ] **Step 4: Commit fixes if any**

```bash
git add scripts/mobbin_fetch.py testpilot
git commit -m "fix(mobbin): smoke test fixes"
```
