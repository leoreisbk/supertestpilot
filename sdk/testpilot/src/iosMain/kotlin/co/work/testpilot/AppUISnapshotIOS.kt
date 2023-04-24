package co.work.testpilot

import co.work.testpilot.extensions.all
import co.work.testpilot.extensions.makeElement
import platform.XCTest.XCUIElementSnapshotProtocol

class AppUISnapshotIOS(snapshot: XCUIElementSnapshotProtocol) : AppUISnapshot {
    private val traverseElements = snapshot.all

    override fun toPromptString(): String {
        return traverseElements.mapIndexedNotNull { i, element -> makeElement(i, element) }
            .joinToString("\n")
    }

    fun getXcElementById(id: Int): XCUIElementSnapshotProtocol? {
        return traverseElements.getOrNull(id)
    }
}
