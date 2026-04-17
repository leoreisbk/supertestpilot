package co.work.testpilot.analyst

import com.microsoft.playwright.Browser
import com.microsoft.playwright.BrowserType
import com.microsoft.playwright.Playwright
import org.json.JSONObject
import java.io.File
import java.net.URI
import java.net.URLDecoder
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.charset.StandardCharsets
import java.nio.file.Path

/**
 * Fetches Mobbin flow screens via Mobbin's internal API (no Playwright needed).
 * Auth uses the Supabase session cookies saved by the mobbin-login flow.
 *
 * API endpoints reverse-engineered from https://github.com/pdcolandrea/mobbin-mcp
 */
class MobbinFetcher {

    companion object {
        private const val MOBBIN_SESSION_PATH = ".testpilot/sessions/mobbin.com.json"
        private const val MOBBIN_BASE = "https://mobbin.com"
        private const val CDN_BASE = "https://bytescale.mobbin.com/FW25bBB/image/mobbin.com/prod"
        private const val SUPABASE_STORAGE_PREFIX = "/storage/v1/object/public/"

        fun sessionFile(): File =
            File(System.getProperty("user.home"), MOBBIN_SESSION_PATH)
    }

    fun hasSession(): Boolean = sessionFile().exists()

    // ── Cookie / auth extraction ─────────────────────────────────────────────

    /** Reads the Playwright session JSON and builds a cookie header string. */
    private fun cookieHeader(): String {
        val json = JSONObject(sessionFile().readText())
        val cookies = json.optJSONArray("cookies") ?: return ""
        return (0 until cookies.length()).joinToString("; ") { i ->
            val c = cookies.getJSONObject(i)
            "${c.getString("name")}=${c.getString("value")}"
        }
    }

    /**
     * Extracts the Supabase JWT access token from the sb-*-auth-token cookie.
     * The cookie value is URL-encoded JSON: {"access_token":"eyJ...","token_type":"bearer",...}
     */
    private fun bearerToken(): String? {
        val json = JSONObject(sessionFile().readText())
        val cookies = json.optJSONArray("cookies") ?: return null
        for (i in 0 until cookies.length()) {
            val c = cookies.getJSONObject(i)
            val name = c.optString("name")
            if (name.startsWith("sb-") && name.endsWith("-auth-token")) {
                val raw = c.optString("value").takeIf { it.isNotEmpty() } ?: continue
                val decoded = URLDecoder.decode(raw, StandardCharsets.UTF_8)
                return runCatching { JSONObject(decoded).optString("access_token") }
                    .getOrNull()?.takeIf { it.isNotEmpty() }
            }
        }
        return null
    }

    // ── HTTP client ──────────────────────────────────────────────────────────

    private val http = HttpClient.newBuilder()
        .followRedirects(HttpClient.Redirect.NORMAL)
        .build()

    private fun post(path: String, body: String): JSONObject {
        val token = bearerToken()
        val builder = HttpRequest.newBuilder()
            .uri(URI.create("$MOBBIN_BASE$path"))
            .header("Content-Type", "application/json")
            .header("Cookie", cookieHeader())
            .header("User-Agent", "Mozilla/5.0")
        if (token != null) builder.header("Authorization", "Bearer $token")
        val req = builder.POST(HttpRequest.BodyPublishers.ofString(body)).build()
        val resp = http.send(req, HttpResponse.BodyHandlers.ofString())
        val respObj = JSONObject(resp.body())
        // Surface auth errors as exceptions so callers get a clear message
        val errorMsg = respObj.optJSONObject("error")?.optString("message")
        if (errorMsg != null && errorMsg.contains("unauthenticated", ignoreCase = true)) {
            error("unauthenticated")
        }
        if (resp.statusCode() !in 200..299)
            error("Mobbin API error ${resp.statusCode()} for $path")
        return respObj
    }

    private fun getBytes(url: String): ByteArray {
        val req = HttpRequest.newBuilder()
            .uri(URI.create(url))
            .header("User-Agent", "Mozilla/5.0")
            .GET()
            .build()
        val resp = http.send(req, HttpResponse.BodyHandlers.ofByteArray())
        if (resp.statusCode() !in 200..299) error("Image fetch error ${resp.statusCode()} for $url")
        return resp.body()
    }

    // ── URL helpers ──────────────────────────────────────────────────────────

    /** Converts a Supabase storage URL to its Bytescale CDN equivalent. */
    private fun toCdnUrl(supabaseUrl: String): String {
        val path = URI.create(supabaseUrl).path
        val idx = path.indexOf(SUPABASE_STORAGE_PREFIX)
        if (idx == -1) return supabaseUrl   // already a CDN or unknown URL
        val storagePath = path.substring(idx + SUPABASE_STORAGE_PREFIX.length)
        return "$CDN_BASE/$storagePath?f=webp&w=1920&q=85&fit=shrink-cover"
    }

    /** Extracts the app UUID from a Mobbin app slug (e.g. tesla-ios-<uuid>). */
    private fun extractAppId(slug: String): String? =
        Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
            .findAll(slug).lastOrNull()?.value

    /** Parses flowId and appId from a Mobbin flow URL. */
    private fun parseFlowUrl(url: String): Pair<String?, String?> {
        // URL: https://mobbin.com/apps/{app-slug}/{flow-id}/flows
        val normalized = normalizeUrl(url)
        val segments = normalized.trimEnd('/').split("/")
        val flowsIdx = segments.lastIndexOf("flows")
        val flowId = if (flowsIdx > 0) segments[flowsIdx - 1].takeIf { it.contains('-') } else null
        val appSlug = if (flowsIdx > 1) segments[flowsIdx - 2] else null
        val appId = appSlug?.let { extractAppId(it) }
        return flowId to appId
    }

    private fun normalizeUrl(url: String): String {
        val t = url.trim()
        return when {
            t.startsWith("http://") || t.startsWith("https://") -> t
            t.startsWith("mobbin.com") -> "https://$t"
            t.startsWith("/apps/") -> "https://mobbin.com$t"
            t.startsWith("/") -> "https://mobbin.com/apps$t"
            else -> "https://mobbin.com/apps/$t"
        }
    }

    // ── Public API ───────────────────────────────────────────────────────────

    /**
     * Fetch screens for a specific Mobbin flow URL via headless Playwright DOM extraction.
     * Mobbin uses React Server Components — the screen data is server-rendered and never
     * exposed through the search-flows API for arbitrary flow IDs. We navigate headlessly
     * with the saved session and extract <img> src URLs directly from the rendered DOM.
     */
    fun fetchFlowScreenshots(flowUrl: String): List<ByteArray> {
        val normalizedUrl = normalizeUrl(flowUrl)
        System.err.println("[MobbinFetcher] extracting screens via Playwright from $normalizedUrl")

        val screenUrls = extractScreenUrlsViaPlaywright(normalizedUrl)
        if (screenUrls.isEmpty()) error("No screens found for flow — check URL and Mobbin session.")

        System.err.println("[MobbinFetcher] downloading ${screenUrls.size} screen(s)")
        return screenUrls.mapNotNull { url ->
            runCatching { getBytes(url) }
                .onFailure { System.err.println("[MobbinFetcher] download failed: ${it.message}") }
                .getOrNull()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun extractScreenUrlsViaPlaywright(flowUrl: String): List<String> {
        val sessionPath = sessionFile().absolutePath
        if (!sessionFile().exists()) {
            error("Mobbin session not found — please connect: click 'Connect Mobbin…' in the Research section")
        }

        Playwright.create().use { playwright ->
            val browser = playwright.chromium().launch(
                BrowserType.LaunchOptions()
                    .setHeadless(true)
                    .setArgs(listOf("--password-store=basic", "--use-mock-keychain"))
            )
            val context = browser.newContext(
                Browser.NewContextOptions()
                    .setStorageStatePath(Path.of(sessionPath))
            )
            val page = context.newPage()
            System.err.println("[MobbinFetcher] navigating headlessly…")
            page.navigate(flowUrl)
            Thread.sleep(8000) // wait for RSC rendering

            val result = page.evaluate("""
                () => {
                    const imgs = Array.from(document.querySelectorAll('img'));
                    const urls = imgs
                        .map(img => img.src || img.dataset.src || '')
                        .filter(src => src.includes('app_screens'));
                    return [...new Set(urls)];
                }
            """.trimIndent()) as? List<String> ?: emptyList()

            System.err.println("[MobbinFetcher] found ${result.size} app_screens URL(s) in DOM")

            // If the page returned nothing, the session may be expired
            if (result.isEmpty()) {
                val title = runCatching { page.title() }.getOrDefault("")
                System.err.println("[MobbinFetcher] page title: $title")
            }

            return result.filter { it.isNotEmpty() }
        }
    }

    /**
     * Search for an app by name, pick its first matching flow, and fetch screens.
     */
    fun fetchByAppName(appName: String, flowName: String?): List<ByteArray> {
        System.err.println("[MobbinFetcher] searching for app: $appName")

        // Autocomplete search to find the app
        val searchResp = post("/api/search-bar/search", """
            {"query":"$appName","experience":"apps","platform":"ios"}
        """.trimIndent())

        val primary = searchResp.optJSONObject("value")?.optJSONArray("primary")
        val appId = primary?.optJSONObject(0)?.optString("id")
            ?: error("App '$appName' not found in Mobbin")

        System.err.println("[MobbinFetcher] found app id: $appId, fetching flows…")
        val screenUrls = fetchScreenUrls(flowId = null, appId = appId, flowName = flowName)
        if (screenUrls.isEmpty()) error("No screens found for '$appName' in Mobbin.")

        System.err.println("[MobbinFetcher] downloading ${screenUrls.size} screen(s)")
        return screenUrls.mapNotNull { url ->
            runCatching { getBytes(toCdnUrl(url)) }
                .onFailure { System.err.println("[MobbinFetcher] download failed: ${it.message}") }
                .getOrNull()
        }
    }

    // ── Core: fetch screen URLs from Mobbin API ──────────────────────────────

    private fun fetchScreenUrls(
        flowId: String?,
        appId: String?,
        flowName: String? = null
    ): List<String> {
        // When we have a specific flowId, fetch it directly — most reliable approach.
        // The appId in the URL slug may not match Mobbin's internal appId in the API.
        val flows: org.json.JSONArray = if (flowId != null) {
            val body = """
                {
                  "searchRequestId": "",
                  "filterOptions": {
                    "platform": "ios",
                    "flowIds": ["$flowId"],
                    "flowActions": null,
                    "appCategories": null
                  },
                  "paginationOptions": { "pageSize": 1, "pageIndex": 0, "sortBy": "publishedAt" }
                }
            """.trimIndent()
            val resp = try { post("/api/content/search-flows", body) } catch (e: Exception) {
                val msg = e.message ?: ""
                if (msg == "unauthenticated") {
                    sessionFile().delete()
                    error("Mobbin session expired — please reconnect: click 'Connect Mobbin…' in the Research section")
                }
                error("Failed to fetch flow: $msg")
            }
            resp.optJSONObject("value")?.optJSONArray("data") ?: org.json.JSONArray()
        } else {
            // No flowId — filter by appId or return top flows
            val filterJson = if (appId != null) "\"appIds\":[\"$appId\"]," else ""
            val body = """
                {
                  "searchRequestId": "",
                  "filterOptions": {
                    "platform": "ios",
                    $filterJson
                    "flowActions": null,
                    "appCategories": null
                  },
                  "paginationOptions": { "pageSize": 50, "pageIndex": 0, "sortBy": "publishedAt" }
                }
            """.trimIndent()
            val resp = try { post("/api/content/search-flows", body) } catch (e: Exception) {
                val msg = e.message ?: ""
                if (msg == "unauthenticated") {
                    sessionFile().delete()
                    error("Mobbin session expired — please reconnect: click 'Connect Mobbin…' in the Research section")
                }
                error("Failed to fetch flows: $msg")
            }
            resp.optJSONObject("value")?.optJSONArray("data") ?: org.json.JSONArray()
        }

        if (flows.length() == 0) return emptyList()

        // When fetched by flowId we get exactly 1 result; otherwise pick by name or first
        val targetFlow: org.json.JSONObject = if (flowName != null) {
            (0 until flows.length()).map { flows.getJSONObject(it) }
                .firstOrNull { it.optString("name").contains(flowName, ignoreCase = true) }
                ?: flows.getJSONObject(0)
        } else {
            flows.getJSONObject(0)
        }

        val screens = targetFlow.optJSONArray("screens") ?: return emptyList()
        System.err.println("[MobbinFetcher] flow '${targetFlow.optString("name")}' has ${screens.length()} screen(s)")

        return (0 until screens.length())
            .map { screens.getJSONObject(it).optString("screenUrl") }
            .filter { it.isNotEmpty() }
    }
}

fun extractFlowId(url: String): String = url
