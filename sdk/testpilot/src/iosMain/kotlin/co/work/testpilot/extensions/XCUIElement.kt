package co.work.testpilot.extensions

import platform.XCTest.XCUIElement
import platform.XCTest.XCUIElementType

fun XCUIElement.waitForExistenceIfNecessary(timeoutSeconds: Double): Boolean {
    return if (exists) true else {
        return waitForExistenceWithTimeout(timeoutSeconds)
    }
}

fun XCUIElement.firstMatch(type: XCUIElementType, label: String): XCUIElement {
    return descendantsMatchingType(type).matchingIdentifier(label).firstMatch
}
