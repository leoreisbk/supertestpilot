package co.work.testpilot

import co.work.testpilot.throwables.TestAutomationException
import kotlinx.serialization.*
import kotlinx.serialization.json.*

object InstructionSerializer : JsonContentPolymorphicSerializer<Instruction>(Instruction::class) {
    override fun selectDeserializer(element: JsonElement): DeserializationStrategy<out Instruction> {
        val commandString = element.jsonObject["cmd"]?.jsonPrimitive?.contentOrNull
        val command = TestCommand.values().firstOrNull { it.name.lowercase() == commandString?.lowercase() }
        return when (command) {
            TestCommand.Tap -> Instruction.Tap.serializer()
            TestCommand.Type -> Instruction.Type.serializer()
            TestCommand.Assert -> Instruction.Assert.serializer()
            TestCommand.ScrollDown -> Instruction.ScrollDown.serializer()
            TestCommand.ScrollUp -> Instruction.ScrollUp.serializer()
            TestCommand.GoBack -> Instruction.GoBack.serializer()
            TestCommand.Wait -> Instruction.Wait.serializer()
            TestCommand.Done -> Instruction.Done.serializer()

            else -> throw TestAutomationException.InvalidCommand(commandString)
        }
    }
}

@Serializable(with = InstructionSerializer::class)
sealed class Instruction {
    @Serializable
    data class Tap(val type: ElementType, val label: String, val reason: String) : Instruction()

    @Serializable
    data class Type(val type: ElementType, val label: String, val text: String, val reason: String) : Instruction()

    @Serializable
    data class Assert(val answer: String?, val expected: String, val reason: String) : Instruction()

    @Serializable
    data class ScrollDown(val reason: String) : Instruction()

    @Serializable
    data class ScrollUp(val reason: String) : Instruction()

    @Serializable
    data class GoBack(val reason: String) : Instruction()

    @Serializable
    data class Wait(val seconds: Float, val reason: String) : Instruction()

    @Serializable
    data class Done(val reason: String) : Instruction()

    override fun toString() = description
    val description get() = when (this) {
        is Assert -> "$reason - Asserting expected value ($expected) equals to discovered value (${answer ?: "N/A"})"
        is Tap -> "$reason - Tapping '$label' $type"
        is Wait -> "$reason - Waiting for $seconds seconds"
        is Type -> "$reason - Typing '$text' into '$label' $type"
        is Done -> reason
        is GoBack -> reason
        is ScrollDown -> reason
        is ScrollUp -> reason
    }
}
