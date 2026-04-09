package co.work.testpilot.extensions

import co.work.testpilot.utils.tryOrNull
import platform.XCTest.XCUIElement
import platform.XCTest.XCUIElementSnapshotProtocol
import platform.XCTest.XCUIElementType

fun XCUIElementSnapshotProtocol.findIn(parent: XCUIElement) = parent.firstMatchOrNull(elementType, label)

fun XCUIElement.waitForExistenceIfNecessary(timeoutSeconds: Double): Boolean {
    return if (exists) true else {
        return waitForExistenceWithTimeout(timeoutSeconds)
    }
}

fun XCUIElement.waitForElementToBecomeVisible(timeoutSeconds: Double): Boolean {
    return waitForExistenceWithTimeout(timeoutSeconds) && isHittable()
}

fun XCUIElement.firstMatchOrNull(type: XCUIElementType, label: String): XCUIElement? {
    return tryOrNull { descendantsMatchingType(type)!!.matchingIdentifier(label)!!.firstMatch }
}
