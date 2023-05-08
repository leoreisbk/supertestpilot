package co.work.testpilot.openai

internal enum class OpenAIModel(val idString: String) {
    GPT3_TextEmbeddingAda002("text-embedding-ada-002"),
    GPT3_TextDavinci003("text-davinci-003"),
    GPT3_5_Turbo(idString = "gpt-3.5-turbo"),
    GPT3_5_Turbo_0301(idString = "gpt-3.5-turbo-0301"),
    GPT4("gpt-4"),
    GPT4_0314("gpt-4-0314"),
}
