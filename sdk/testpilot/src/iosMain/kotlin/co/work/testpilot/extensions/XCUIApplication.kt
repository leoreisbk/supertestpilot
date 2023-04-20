package co.work.testpilot.extensions

import co.work.testpilot.runtime.Element
import co.work.testpilot.runtime.ElementType
import platform.XCTest.XCUIApplication
import platform.XCTest.XCUIElementSnapshotProtocol
import platform.XCTest.XCUIElementSnapshotProvidingProtocol

private fun makeElement(id: Int, snapshot: XCUIElementSnapshotProtocol): Element? {
    val elementType = snapshot.elementType.toTestPilotElementType()
    (elementType != ElementType.Unknown && snapshot.label.isNotEmpty()) || return null
    return Element(elementType, id, snapshot.label, snapshot.value as? String, if (snapshot.selected) true else null)
}

private val XCUIElementSnapshotProtocol.all: List<XCUIElementSnapshotProtocol>
    get() = listOf(this) + children.flatMap { (it as XCUIElementSnapshotProtocol).all }

val XCUIApplication.elements: Map<Int, Pair<XCUIElementSnapshotProtocol, Element>>
    get() {
        val snapshot = (this as XCUIElementSnapshotProvidingProtocol).snapshotWithError(null) ?: return emptyMap()
        return snapshot.all.mapIndexedNotNull { i, e -> makeElement(i, e)?.let { Pair(e, it) } }
            .associateBy({ it.second.id }, { it })
    }