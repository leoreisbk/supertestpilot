package co.work.testpilot.extensions

import platform.XCTest.XCUIElement
import platform.XCTest.XCUIElementSnapshotProtocol
import platform.XCTest.XCUIElementType

fun XCUIElementSnapshotProtocol.findIn(parent: XCUIElement) = parent.firstMatch(elementType, label)
fun XCUIElement.waitForExistenceIfNecessary(timeoutSeconds: Double): Boolean {
    return if (exists) true else {
        return waitForExistenceWithTimeout(timeoutSeconds)
    }
}
fun XCUIElement.firstMatch(type: XCUIElementType, label: String) = descendantsMatchingType(type).matchingIdentifier(label).firstMatch