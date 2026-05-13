# Design: `./testpilot mobbin` — Mobbin MCP Integration

**Date:** 2026-05-13  
**Status:** Approved  
**Replaces:** `research` command (coexists for now; `research` deprecated after web JAR cleanup)

---

## Problem

The existing `research` command failed for two reasons:
1. **Wrong images returned** — browser automation matched incorrect screens from Mobbin flows
2. **CDN token expiration** — individual screenshot URLs expired before download completed

The Mobbin MCP (`pdcolandrea/mobbin-mcp`) solves both: natural language search returns the right screens, and images are returned as base64 (no CDN tokens).

---

## Solution

A new `./testpilot mobbin` subcommand backed by a standalone Python script (`scripts/mobbin_fetch.py`). No JVM, no Xcode, no `claude` CLI dependency.

Auth reuses the existing `mobbin-login` session cookie (`~/.testpilot/sessions/mobbin.com.json`).

---

## CLI Interface

```
./testpilot mobbin \
  --query "onboarding flow"          # natural language search (required)
  --objective "analyze UX clarity"   # what to analyze (required)
  [--platform ios|web]               # default: ios
  [--limit 20]                       # number of screens, default 20, max 30
  [--output report.html]
  [--provider anthropic|openai|gemini]
  [--api-key <key>]
  [--lang en|pt-BR]
  [--persona <file>]
```

The `mobbin-login` command is unchanged — the Python script reads the cookie it produces.

---

## Architecture

### Components

| Component | Location | Role |
|-----------|----------|------|
| CLI bash | `testpilot` | Parse flags, validate, invoke Python |
| Python fetcher+analyst | `scripts/mobbin_fetch.py` | Search → download → AI → HTML |
| Session cookie | `~/.testpilot/sessions/mobbin.com.json` | Mobbin auth |

### Data Flow

```
testpilot mobbin --query "..." --objective "..."
        │
        ▼
scripts/mobbin_fetch.py
        │
        ├─ read ~/.testpilot/sessions/mobbin.com.json (cookie auth)
        │
        ├─ POST Mobbin search API → list of screens
        │   (query, platform, limit)
        │
        └─ for each screen:
              download image bytes (with session cookie)
                      │
                      ▼
              AI call: image + objective → observation (text)
                      │
                      ▼
              collect observations
        │
        ▼
HtmlReportWriter (Python) → report.html
        │
        ▼
open report.html
```

### Analysis Loop

Unlike the live-app `Analyst` (which loops with Tap/Scroll/Done actions), the Mobbin loop is **linear**:

- Analyze each screen in order
- AI returns a text observation per screen (no navigation actions)
- All observations collected → single HTML report
- Mirrors what `research` was supposed to do

### HTML Report Format

Each step card in the report shows:
- Screen thumbnail (the Mobbin screenshot)
- App name + Mobbin link
- AI observation text

The summary section at the top consolidates cross-screen patterns (same format as the existing `analyze` report header). Default output path: `./report.html`.

### API Discovery

The Mobbin API endpoints are reverse-engineered from the open-source `pdcolandrea/mobbin-mcp` source. The session cookie from `mobbin-login` is used for all requests — same auth mechanism, no new login flow.

---

## Error Handling

| Condition | Behavior |
|-----------|----------|
| No session file | `Error: Mobbin session not found — run: testpilot mobbin-login` |
| Session expired (401) | `Error: Mobbin session expired — run: testpilot mobbin-login` |
| Zero search results | `Error: No screens found for query "...". Try a different query.` |
| AI failure on one screen | Log warning, continue with remaining screens |
| Partial failures | Report generated with error markers on failed screens |

---

## Migration

- `research` command **stays** in the CLI (no breaking change)
- `mobbin` command **added** alongside it
- When the web JAR is updated to remove its Mobbin browser automation code, `research` can be deprecated
- `mobbin-login` stays unchanged

---

## Files Changed

**Added:**
- `scripts/mobbin_fetch.py` (~130 lines)

**Modified:**
- `testpilot` (bash CLI) — add `mobbin` to command list + handler block (~30 lines)

**Not changed yet:**
- `testpilot-web.jar` — Mobbin code inside it removed in a separate JAR update
- `mobbin-login` command — unchanged

---

## Out of Scope

- Replacing `research` (done after web JAR update)
- Android/iOS platform targeting (Mobbin is platform-agnostic static analysis)
- Caching AI responses per screen (can be added later)
- `test` mode for Mobbin (pass/fail verdicts — no use case identified)
