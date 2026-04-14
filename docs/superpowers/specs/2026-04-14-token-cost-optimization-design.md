# Token Cost Optimization Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce per-run API token cost and fix a correctness bug where JPEG images are mislabeled as PNG in Anthropic requests.

**Architecture:** Three targeted changes in well-isolated spots — fix the media type in `AnthropicChatClient`, memoize the system prompt in `VisionPrompt`, replace a linear duplicate-observation scan with a `HashSet`, and log Anthropic cache hit metrics.

**Tech Stack:** Kotlin Multiplatform (commonMain), Ktor HTTP, kotlinx.serialization

---

## Context

Every analysis step makes one AI call. With 40 max steps per run:

- The system prompt (~800 tokens) is sent 40 times. Anthropic's prompt caching (`cache_control: ephemeral` + beta header) is already wired in `AnthropicChatClient` and should cache after the first call — but only if the text is identical. Memoizing the string in `VisionPrompt` guarantees it.
- `AnthropicChatClient` hardcodes `mediaType = "image/png"` but `AnalystDriverIOS` sends JPEG bytes. The AI is decoding JPEG data as PNG on every call — a correctness issue that could hurt analysis quality and wastes any image-processing optimisation the model does based on declared type.
- `Analyst` uses `steps.none { it.observation == obs }` — an O(n) linear scan to detect duplicate observations. With a `HashSet<String>` this becomes O(1).
- Anthropic's response includes `cache_read_input_tokens` and `cache_creation_input_tokens` fields. Logging these lets us verify caching is working.

---

## Files

| File | Change |
|------|--------|
| `commonMain/.../ai/AnthropicChatClient.kt` | Fix hardcoded `"image/png"` → detect actual media type from bytes; parse and log cache metrics from response |
| `commonMain/.../ai/VisionPrompt.kt` | Memoize system prompt string as a `val` computed at construction time |
| `commonMain/.../analyst/Analyst.kt` | Replace `steps.none { it.observation == obs }` with a `HashSet<String>` maintained alongside `steps` |

---

## Design

### 1. Media type fix — `AnthropicChatClient`

`AnalystDriverIOS.screenshotPng()` returns JPEG bytes (PNG converted to JPEG at 0.7 quality). The client must detect the actual format from the magic bytes rather than hardcode PNG.

JPEG magic bytes: `0xFF 0xD8` at offset 0.
PNG magic bytes: `0x89 0x50` at offset 0.

Add a private helper `ByteArray.imageMimeType(): String` (same logic already in `HtmlReportWriter`) and use it when building `AnthropicImageSource`. Same fix applies to `mediaType` label — `"image/jpeg"` vs `"image/png"`.

### 2. Cache hit logging — `AnthropicChatClient`

Anthropic responses include usage fields:
```json
{
  "usage": {
    "input_tokens": 100,
    "cache_read_input_tokens": 820,
    "cache_creation_input_tokens": 0,
    "output_tokens": 45
  }
}
```

Add `usage` to `AnthropicResponse` deserialization and log it with `Logging.info`. A non-zero `cache_read_input_tokens` confirms the system prompt cache is hitting.

### 3. System prompt memoization — `VisionPrompt`

`VisionPrompt` is instantiated once per run (in `Analyst.run()`). The system prompt string depends only on `config` (immutable) — language, persona. It never changes during a run.

Move system prompt construction from `invoke()` into a `private val systemPrompt: String` computed at construction. `invoke()` uses `systemPrompt` directly.

This guarantees the same `String` object (same content) is sent on every call, which is the precondition for Anthropic's cache to hit consistently.

### 4. O(1) duplicate detection — `Analyst`

Replace:
```kotlin
if (obs != null && steps.none { it.observation == obs }) {
```
With a `HashSet<String>` maintained in parallel with `steps`:
```kotlin
val seenObservations = mutableSetOf<String>()
// ...
if (obs != null && seenObservations.add(obs)) {
    steps.add(...)
}
```

`MutableSet.add()` returns `false` if the element was already present — one operation, O(1).

---

## Error Handling

- Media type detection: if `imageBytes` is null or fewer than 2 bytes, default to `"image/jpeg"` (matches the driver's primary output path).
- Cache metrics logging: the `usage` field is optional in deserialization — if absent (OpenAI/Gemini paths that reuse the same response shape), it's silently ignored.

---

## Expected Impact

| Change | Impact |
|--------|--------|
| Media type fix | Correct AI image interpretation — qualitative improvement |
| Cache hit logging | Visibility into whether Anthropic caching is working |
| System prompt memoization | Guarantees Anthropic cache hits after step 1; ~820 cached tokens × 39 steps = ~32k tokens at cached rate (~10× cheaper) |
| HashSet dedup | O(n²) → O(n) across a 40-step run; negligible wall-clock impact but cleaner |
