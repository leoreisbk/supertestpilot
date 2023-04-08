package co.work.testpilot

import kotlinx.serialization.*
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import platform.XCTest.XCUIElementType

@Serializable
sealed class Instruction(val cmd: Command) {
    enum class Command {
        @SerialName("tap")
        Tap,
        @SerialName("type")
        Type,
        @SerialName("assert")
        Assert,
        @SerialName("scrollDown")
        ScrollDown,
        @SerialName("scrollUp")
        ScrollUp,
        @SerialName("goBack")
        GoBack,
        @SerialName("wait")
        Wait,
        @SerialName("done")
        Done,
    }

    data class Tap(val type: XCUIElementType, val label: String, val reason: String) : Instruction(Command.Tap)
    data class Type(val type: XCUIElementType, val label: String, val text: String, val reason: String) : Instruction(Command.Type)
    data class Assert(val answer: String?, val expected: String, val reason: String) : Instruction(Command.Assert)
    data class ScrollDown(val reason: String) : Instruction(Command.ScrollDown)
    data class ScrollUp(val reason: String) : Instruction(Command.ScrollUp)
    data class GoBack(val reason: String) : Instruction(Command.GoBack)
    data class Wait(val seconds: Float, val reason: String) : Instruction(Command.Wait)
    data class Done(val reason: String) : Instruction(Command.Done)

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
