TestPilot
===

AI-powered app testing using vision — exploratory analysis and deterministic pass/fail tests for iOS, Android, and web.

TestPilot is a Kotlin Multiplatform (KMM) SDK that drives iOS, Android, and web apps using screenshots and a multimodal AI loop. It supports two modes:

- **`./testpilot analyze`** — exploratory UX analysis: the AI navigates freely and generates an HTML report with screenshots and observations
- **`./testpilot test`** — deterministic pass/fail: the AI evaluates a specific assertion and exits with `0` (PASS) or `1` (FAIL), with response caching for fast reruns

# Installation

Refer to [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for build and installation instructions.

# Usage

## Exploratory analysis

Run `./testpilot analyze` with a free-form objective. The AI explores the app and generates an HTML report.

```bash
# iOS
./testpilot analyze \
  --platform ios \
  --app "My App" \
  --objective "how easy is it to find the search feature and complete a purchase"

# Web
./testpilot analyze \
  --platform web \
  --url https://your-app.com \
  --objective "how easy is it to find the checkout flow"
```

At the end, the report opens automatically in the browser.

## Deterministic test

Run `./testpilot test` with a specific assertion. The AI evaluates it and returns PASS or FAIL.

```bash
# iOS
./testpilot test \
  --platform ios \
  --app "My App" \
  --objective "Check if the Buy button is enabled on the product page"

# Web
./testpilot test \
  --platform web \
  --url https://your-app.com \
  --objective "Check if the Buy button is enabled on the product page"
```

Terminal output:

```
Running test...
  ✓ Opened the home screen
  ✓ Navigated to the product page
  ✗ "Buy" button was disabled

FAILED: "Buy" button was disabled
```

Exit code `0` = PASS, `1` = FAIL — suitable for CI pipelines.

Responses are cached in `~/.testpilot/cache/` so reruns of the same test skip API calls.

## Web session management

For apps that require login, TestPilot can authenticate before running:

**Automatic login** (username + password):

```bash
./testpilot test \
  --platform web \
  --url https://your-app.com \
  --objective "Check the dashboard loads correctly" \
  --username user@example.com \
  --password secret
```

The session is saved to `~/.testpilot/sessions/<hostname>.json` and reused on subsequent runs.

**Manual login** (SSO, OAuth, MFA):

```bash
./testpilot web-login --url https://your-app.com
```

Opens a browser window. Log in manually, then press Enter to save the session.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--platform` | — | `ios`, `android`, or `web` |
| `--app` | — | App name (`ios`/`android` only) |
| `--url` | — | URL to open (`web` only) |
| `--objective` | — | What to analyze or assert |
| `--username` | — | Username for automatic login pre-step (`web` only) |
| `--password` | — | Password for automatic login pre-step (`web` only) |
| `--max-steps` | `20` | Maximum AI actions before stopping |
| `--output` | `./report.html` | Report path (`analyze` only) |
| `--provider` | via `.env` | AI provider: `anthropic` or `openai` (web); `anthropic`, `openai`, or `gemini` (mobile) |
| `--api-key` | via `.env` | AI API key |
| `--device` | — | iOS device UDID for physical device |
| `--team-id` | — | Apple Developer Team ID (required with `--device`) |
| `--lang` | `en` | Report language: `en` or `pt-BR` |

## AI providers

TestPilot works with Anthropic Claude, OpenAI GPT-4o, and Google Gemini. Set the provider via `.env`:

```
TESTPILOT_API_KEY=your-key-here
TESTPILOT_PROVIDER=anthropic
```

Or pass `--provider` and `--api-key` directly on the command line.

# How it works

Each step of the loop:

1. Takes a screenshot of the app
2. Sends the screenshot + objective to the AI
3. AI returns the next action: tap, scroll, type, or a verdict (analyze: done / test: pass or fail)
4. The action is executed on the device
5. Repeat until the objective is complete or `maxSteps` is reached

In **analyze** mode, the AI acts as a UX analyst — it explores freely and accumulates observations. At the end, a second AI call generates a written summary. Output is an HTML report with all screenshots inline.

In **test** mode, the AI acts as a deterministic test evaluator — it terminates as soon as it has enough evidence to issue a verdict. No report is generated.

# Data and Privacy

TestPilot sends screenshots of your app to the AI provider you configure. Screenshots may contain sensitive information visible on screen during the test run. Use ephemeral test credentials with limited scope when testing authenticated flows.

# License
Copyright 2023 Work&Co

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
