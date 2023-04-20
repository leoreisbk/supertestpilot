package co.work.testpilot

import androidx.test.uiautomator.UiObject
import androidx.test.uiautomator.UiObject2

class AppUISnapshotAndroid(val elements: List<UiObject2>) : AppUISnapshot {
    private fun generateUiRepresentation(
        listOfElements: List<UiObject2>,
        result: StringBuilder,
        numberOfSpace: Int = 0,
    ) {
        for (element in listOfElements) {
            if (element.children == null || element.children.isEmpty()) {
                addMinifiedElement(result, element, numberOfSpace)
            } else {
                addMinifiedElement(result, element, numberOfSpace)
                generateUiRepresentation(element.children, result, numberOfSpace + 1)
            }
        }
    }

    private fun addMinifiedElement(result: StringBuilder, element: UiObject2, spaces: Int) {
        val indentationSpaces = " ".repeat(spaces)
        val resumedClass = element.className.substring(element.className.lastIndexOf('.') + 1)
        val writable = if (element.className.contains("EditText")) "writable" else ""
        val clickable = if (element.isClickable) " clickable" else ""
        val checkable = if (element.isCheckable) "checkable " else ""
        val checked = if (element.isChecked) " checked" else ""
        val scrollable = if (element.isScrollable) " scrollable" else ""
        val label = if (element.contentDescription != null) " label=\"${element.contentDescription}\"" else if (element.text != null) " label=\"${element.text}\"" else ""

        result.append("$indentationSpaces$resumedClass id=${getElementId(element)} $writable$clickable$checkable$checked$scrollable$label\n")
    }

    // TO-DO: ids should be pre-generated
    fun getElementId(element: UiObject2): Int = elements.indexOf(element)
    fun getElementById(id: Int): UiObject2? = elements.getOrNull(id)

    override fun toPromptString(): String {
        val result = StringBuilder()
        generateUiRepresentation(this.elements, result)
        return result.toString()
    }
}
