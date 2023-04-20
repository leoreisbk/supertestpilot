package co.work.testpilot.runtime

import co.work.testpilot.Environment
import co.work.testpilot.throwables.ConfigurationException
import kotlin.experimental.ExperimentalObjCName
import kotlin.native.ObjCName


data class Config(
    val apiKey: String,
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
    var apiKey: String? = null
    var maxTokens: Int = ConfigDefaults.maxTokens
    var temperature: Double = ConfigDefaults.temperature
    var maxSteps: Int = ConfigDefaults.maxSteps

    @ObjCName("apiKey")
    fun apiKey(key: String?): ConfigBuilder {
        this.apiKey = key
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

    fun build(): Config = Config(
        apiKey = apiKey ?: Environment.apiKey ?: throw ConfigurationException.ApiKeyRequired(),
        maxTokens = maxTokens,
        temperature = temperature,
        maxSteps = maxSteps
    )
}
