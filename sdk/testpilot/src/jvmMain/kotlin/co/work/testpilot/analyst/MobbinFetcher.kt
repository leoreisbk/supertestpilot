package co.work.testpilot.analyst

import io.ktor.client.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MobbinFetcher(private val httpClient: HttpClient) {

    companion object {
        private const val MOBBIN_SESSION_PATH = ".testpilot/sessions/mobbin.com.json"
        private const val MOBBIN_API_BASE = "https://mobbin.com/api"

        fun sessionFile(): File =
            File(System.getProperty("user.home"), MOBBIN_SESSION_PATH)
    }

    /** Returns true if a Mobbin session file exists. */
    fun hasSession(): Boolean = sessionFile().exists()

    /**
     * Loads cookies from the saved Playwright session state (JSON) for mobbin.com.
     * Returns a Cookie header value string like "name=value; name2=value2".
     */
    private fun loadCookieHeader(): String {
        val json = JSONObject(sessionFile().readText())
        val cookies = json.optJSONArray("cookies") ?: JSONArray()
        return (0 until cookies.length())
            .map { cookies.getJSONObject(it) }
            .filter { it.optString("domain").contains("mobbin.com") }
            .joinToString("; ") { "${it.getString("name")}=${it.getString("value")}" }
    }

    /**
     * Fetches image bytes for all screens in a Mobbin flow.
     * @param flowId UUID extracted from the flow URL.
     *
     * Note: Mobbin API endpoints are unofficial/internal (reverse-engineered).
     * Verify endpoint shape against https://github.com/pdcolandrea/mobbin-mcp if broken.
     */
    suspend fun fetchFlowImages(flowId: String): List<ByteArray> {
        val cookieHeader = loadCookieHeader()

        val response = httpClient.get("$MOBBIN_API_BASE/content/flows/$flowId") {
            header("Cookie", cookieHeader)
            header("Accept", "application/json")
        }

        if (response.status.value == 401) {
            error("Mobbin session expired — run: testpilot mobbin-login")
        }
        if (response.status.value != 200) {
            error("Mobbin API error ${response.status.value} for flow $flowId")
        }

        val body = response.bodyAsText()
        val imageUrls = parseImageUrls(body)

        if (imageUrls.isEmpty()) {
            error("No screens found in Mobbin flow $flowId. Check the flow URL.")
        }

        return imageUrls.map { url ->
            withContext(Dispatchers.IO) {
                httpClient.get(url) {
                    header("Cookie", cookieHeader)
                }.readBytes()
            }
        }
    }

    /**
     * Searches for a flow by app name + flow name and returns its ID.
     */
    suspend fun searchFlowId(appName: String, flowName: String): String {
        val cookieHeader = loadCookieHeader()

        val appsResp = httpClient.get("$MOBBIN_API_BASE/content/search-apps") {
            header("Cookie", cookieHeader)
            header("Accept", "application/json")
            parameter("q", appName)
        }
        val appId = parseFirstId(appsResp.bodyAsText())
            ?: error("No app found matching '$appName' on Mobbin")

        val flowsResp = httpClient.get("$MOBBIN_API_BASE/content/search-flows") {
            header("Cookie", cookieHeader)
            header("Accept", "application/json")
            parameter("q", flowName)
            parameter("appId", appId)
        }
        return parseFirstId(flowsResp.bodyAsText())
            ?: error("No flow found matching '$flowName' for app '$appName' on Mobbin")
    }

    private fun parseImageUrls(json: String): List<String> {
        // Mobbin flow response: { "data": { "screens": [ { "imageUrl": "..." }, ... ] } }
        // Adjust field path if the API response shape differs — check mobbin-mcp for current shape.
        return try {
            val root = JSONObject(json)
            val screens = root.optJSONObject("data")
                ?.optJSONArray("screens")
                ?: root.optJSONArray("screens")
                ?: JSONArray()
            (0 until screens.length()).mapNotNull { i ->
                screens.getJSONObject(i).optString("imageUrl").takeIf { it.isNotBlank() }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun parseFirstId(json: String): String? {
        return try {
            val root = JSONObject(json)
            val arr = root.optJSONArray("data") ?: return null
            if (arr.length() == 0) return null
            arr.getJSONObject(0).optString("id").takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        }
    }
}

/** Extracts the UUID flow ID from a Mobbin flow URL. */
fun extractFlowId(url: String): String {
    // Handles: https://mobbin.com/flows/<uuid>
    //      and https://mobbin.com/explore/flows/<uuid>
    val regex = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
    return regex.find(url)?.value
        ?: error("Could not extract flow ID from URL: $url — expected a UUID in the path")
}
