package co.work.testpilot.extensions

import co.work.testpilot.runtime.ElementType
import co.work.testpilot.runtime.Runner
import platform.XCTest.XCTestCase
import platform.XCTest.XCUIElement

suspend fun XCTestCase.getElement(
    runner: Runner,
    app: XCUIElement,
    type: ElementType,
    label: String
): XCUIElement {
    return app
//    val match = app.firstMatch(type.toXCUIElementType(), label)
//    if (match.exists) {
//        return match
//    }
//    val uiDump = app.debugDescription?.simplifyUI() ?: ""
//    val ui = Regex("^(?!${type.name}).*\\n").replace(uiDump, "")
//    val line = suspendTryOrNull {
//        runner.searchEmbeddings(
//            input = ui,
//            query = label,
//            n = 1,
//        ).firstOrNull()
//    } ?: ""
//    val labelMatch = Regex("label: '(?<label>.*?)'(\$|,)").matchAt(line, 0)
//
//    return app.firstMatch(type = type.toXCUIElementType(), label = labelMatch!!.groups["label"]!!.value)
}
