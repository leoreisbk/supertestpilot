#!/usr/bin/env python3
"""TestPilot Mobbin: analyze Mobbin screens with AI."""

import argparse
import base64
import html as html_lib
import json
import os
import re
import subprocess
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
    args = p.parse_args()
    if args.limit < 1:
        p.error("--limit must be at least 1")
    return args


def load_cookie() -> str:
    if not os.path.exists(SESSION_PATH):
        print("Error: Mobbin session not found — run: testpilot mobbin-login", file=sys.stderr)
        sys.exit(1)
    if os.stat(SESSION_PATH).st_mode & 0o077:
        print("Warning: session file is world-readable. Run: chmod 600 ~/.testpilot/sessions/mobbin.com.json", file=sys.stderr)
    with open(SESSION_PATH) as f:
        try:
            state = json.load(f)
        except json.JSONDecodeError:
            print("Error: Mobbin session file is corrupt — run: testpilot mobbin-login", file=sys.stderr)
            sys.exit(1)
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
                "mobbin_url": f"https://mobbin.com/screens/{screen.get('screenId') or ''}",
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


def _strip_fences(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r'^```(?:json)?\s*\n?', '', text)
        text = re.sub(r'\n?```\s*$', '', text)
    return text.strip()


def _parse_obs(raw: str) -> str:
    try:
        return json.loads(_strip_fences(raw)).get("observation", raw)
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
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return _parse_obs(json.loads(resp.read())["content"][0]["text"])
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Anthropic API error {e.code}: {e.read().decode(errors='replace')[:200]}") from e


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
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return _parse_obs(json.loads(resp.read())["choices"][0]["message"]["content"])
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"OpenAI API error {e.code}: {e.read().decode(errors='replace')[:200]}") from e


def _call_gemini(b64: str, system: str, prompt: str, api_key: str) -> str:
    body = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [{"parts": [
            {"inline_data": {"mime_type": "image/webp", "data": b64}},
            {"text": prompt},
        ]}],
    }
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"gemini-2.5-flash:generateContent?key={api_key}"
    )
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                  headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return _parse_obs(json.loads(resp.read())["candidates"][0]["content"]["parts"][0]["text"])
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Gemini API error {e.code}: {e.read().decode(errors='replace')[:200]}") from e


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
    return _call_gemini(b64, system, prompt, api_key)


def _call_text(system: str, prompt: str, provider: str, api_key: str) -> str:
    """Text-only (no image) AI call shared by generate_summary."""
    if provider == "anthropic":
        body = {"model": "claude-sonnet-4-6", "max_tokens": 1024, "system": system,
                "messages": [{"role": "user", "content": prompt}]}
        req = urllib.request.Request("https://api.anthropic.com/v1/messages",
            data=json.dumps(body).encode(),
            headers={"x-api-key": api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return _strip_fences(json.loads(resp.read())["content"][0]["text"])
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"Anthropic API error {e.code}: {e.read().decode(errors='replace')[:200]}") from e

    if provider == "openai":
        body = {"model": "gpt-4o", "max_tokens": 1024,
                "messages": [{"role": "system", "content": system}, {"role": "user", "content": prompt}]}
        req = urllib.request.Request("https://api.openai.com/v1/chat/completions",
            data=json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return _strip_fences(json.loads(resp.read())["choices"][0]["message"]["content"])
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"OpenAI API error {e.code}: {e.read().decode(errors='replace')[:200]}") from e

    body = {
        "system_instruction": {"parts": [{"text": system}]},
        "contents": [{"parts": [{"text": prompt}]}],
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={api_key}"
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return _strip_fences(json.loads(resp.read())["candidates"][0]["content"]["parts"][0]["text"])
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Gemini API error {e.code}: {e.read().decode(errors='replace')[:200]}") from e


def generate_summary(observations: list, objective: str, provider: str, api_key: str, lang: str) -> str:
    lang_note = f"Write in {lang}." if lang != "en" else ""
    obs_text = "\n".join(f"{i+1}. {o}" for i, o in enumerate(observations))
    system = "You are a senior UX researcher synthesizing competitive findings."
    prompt = (
        f"Objective: {objective}\n\nObservations from {len(observations)} screens:\n{obs_text}\n\n"
        "Synthesize 3-5 key findings as a JSON array of plain text strings — no HTML, no markdown. "
        f"Focus on cross-app patterns: what works, what doesn't, standout design decisions. {lang_note}\n"
        'Respond with JSON: {"items": ["Finding 1", "Finding 2", ...]}'
    )
    raw = _call_text(system, prompt, provider, api_key)
    try:
        items = json.loads(raw).get("items", [])
        if isinstance(items, list) and items:
            return "<ul>" + "".join(f"<li>{html_lib.escape(str(item))}</li>" for item in items) + "</ul>"
    except Exception:
        pass
    return f"<p>{html_lib.escape(raw)}</p>"


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
            f'<img src="data:image/webp;base64,{step["image_b64"]}" '
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


def main():
    args = parse_args()
    cookie = load_cookie()
    print(f'Searching Mobbin for "{args.query}"...')
    # pageSize is number of flows; slice to args.limit to enforce screen count
    screens = search_flows(args.query, args.platform, args.limit, cookie)[:args.limit]
    print(f"Found {len(screens)} screens. Analyzing...")

    steps = []          # {"app_name", "mobbin_url", "image_b64", "observation"}
    observations = []   # running list for dedup context

    for i, screen in enumerate(screens):
        app_name = screen["app_name"]
        mobbin_url = screen["mobbin_url"]
        print(f"  [{i + 1}/{len(screens)}] {app_name}...", end=" ", flush=True)

        image_bytes = download_image(screen["screen_url"])
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
            print(f"error: {e}", file=sys.stderr)

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
    try:
        summary = generate_summary(observations, args.objective, args.provider, args.api_key, args.lang)
    except Exception as e:
        print(f"Warning: summary generation failed ({e}). Using placeholder.", file=sys.stderr)
        summary = "<ul><li>Summary unavailable — see per-screen observations above.</li></ul>"

    report_html = generate_report(steps, args.query, args.objective, summary, args.lang, args.persona)
    output_path = os.path.abspath(args.output)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(report_html)
    print(f"Report written to: {output_path}")
    subprocess.run(["open", output_path], check=False)


if __name__ == "__main__":
    main()
