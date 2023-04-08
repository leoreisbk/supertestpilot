package co.work.testpilot.extensions

import co.work.testpilot.Runner
import co.work.testpilot.utils.suspendTryOrNull
import co.work.testpilot.utils.tryOrNull
import platform.XCTest.XCTestCase
import platform.XCTest.XCUIElement
import platform.XCTest.XCUIElementType

suspend fun XCTestCase.getElement(
    runner: Runner,
    app: XCUIElement,
    type: XCUIElementType,
    label: String
): XCUIElement {
    val match = app.firstMatch(type, label)
    if (match.exists) {
        return match
    }
    val uiDump = app.debugDescription?.simplifyUI() ?: ""
    val ui = Regex("^(?!${type.description}).*\\n").replace(uiDump, "")
    val line = suspendTryOrNull {
        runner.searchEmbeddings(
            input = ui,
            query = label,
            n = 1,
        ).firstOrNull()
    } ?: ""
    val labelMatch = Regex("label: '(?<label>.*?)'(\$|,)").matchAt(line, 0)

    return app.firstMatch(type = type, label = labelMatch!!.groups["label"]!!.value)
}
