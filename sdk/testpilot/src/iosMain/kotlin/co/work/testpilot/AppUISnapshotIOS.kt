package co.work.testpilot

import co.work.testpilot.extensions.all
import co.work.testpilot.extensions.makeElement
import co.work.testpilot.extensions.toTestPilotElementType
import co.work.testpilot.runtime.ElementType
import platform.XCTest.XCUIElementSnapshotProtocol
import platform.XCTest.XCUIElementType

class AppUISnapshotIOS(snapshot: XCUIElementSnapshotProtocol) : AppUISnapshot {
    private val traverseElements = snapshot.all
    override val allElements = traverseElements.map { AppUIElementSnapshotIOS(it) }

    override fun toPromptString(): String {
        return traverseElements.mapIndexedNotNull { i, element -> makeElement(i, element) }
            .joinToString("\n")
    }

    fun getXcElementById(id: Int): XCUIElementSnapshotProtocol? {
        return traverseElements.getOrNull(id)
    }

    fun firstXcElementOrNull(type: XCUIElementType, label: String): XCUIElementSnapshotProtocol? {
        return traverseElements.firstOrNull { it.elementType == type && it.label == label }
    }
}

class AppUIElementSnapshotIOS(xcElement: XCUIElementSnapshotProtocol) : AppUIElementSnapshot {
    override val label: String = xcElement.label
    override val type: ElementType = xcElement.elementType.toTestPilotElementType()
}
