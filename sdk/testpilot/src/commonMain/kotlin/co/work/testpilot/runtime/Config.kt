package co.work.testpilot.runtime

import co.work.testpilot.throwables.ConfigurationException
import kotlin.experimental.ExperimentalObjCName
import kotlin.native.ObjCName

enum class AIProvider {
    OpenAI,
    Anthropic,
}

object AIProviderDefaults {
    const val openAIModel = "gpt-4o"
    const val anthropicModel = "claude-sonnet-4-6"
}

data class Config(
    val provider: AIProvider,
    val apiKey: String,
    val modelId: String?,
    var apiHost: String?,
    var apiOrg: String?,
    var apiHeaders: Map<String, String>,
    val maxTokens: Int,
    val temperature: Double,
    val maxSteps: Int,
)

object ConfigDefaults {
    const val maxTokens = 200
    const val temperature = 0.0
    const val maxSteps = 10
}

@OptIn(ExperimentalObjCName::class)
class ConfigBuilder {
    var provider: AIProvider = AIProvider.OpenAI
    var apiKey: String? = null
    var modelId: String? = null
    var apiHost: String? = null
    var apiOrg: String? = null
    val apiHeaders: MutableMap<String, String> = mutableMapOf()
    var maxTokens: Int = ConfigDefaults.maxTokens
    var temperature: Double = ConfigDefaults.temperature
    var maxSteps: Int = ConfigDefaults.maxSteps

    fun provider(provider: AIProvider): ConfigBuilder {
        this.provider = provider
        return this
    }

    @ObjCName("apiKey")
    fun apiKey(key: String?): ConfigBuilder {
        this.apiKey = key
        return this
    }

    fun modelId(modelId: String?): ConfigBuilder {
        this.modelId = modelId
        return this
    }

    @ObjCName("maxTokens")
    fun maxTokens(tokens: Int): ConfigBuilder {
        this.maxTokens = tokens
        return this
    }

    fun temperature(temperature: Double): ConfigBuilder {
        this.temperature = temperature
        return this
    }

    @ObjCName("maxSteps")
    fun maxSteps(steps: Int): ConfigBuilder {
        this.maxSteps = steps
        return this
    }

    fun apiHost(host: String?): ConfigBuilder {
        this.apiHost = host
        return this
    }

    fun apiOrganization(org: String?): ConfigBuilder {
        this.apiOrg = org
        return this
    }

    fun apiHeader(key: String, value: String): ConfigBuilder {
        this.apiHeaders[key] = value
        return this
    }

    fun build(): Config = Config(
        provider = provider,
        apiKey = apiKey ?: throw ConfigurationException.ApiKeyRequired(),
        modelId = modelId,
        apiHost = apiHost,
        apiOrg = apiOrg,
        apiHeaders = apiHeaders,
        maxTokens = maxTokens,
        temperature = temperature,
        maxSteps = maxSteps,
    )
}
