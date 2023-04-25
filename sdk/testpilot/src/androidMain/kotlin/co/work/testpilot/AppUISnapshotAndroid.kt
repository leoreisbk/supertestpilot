package co.work.testpilot

import androidx.test.uiautomator.UiObject2

fun List<UiObject2>.traverseFind(predicate: (UiObject2) -> Boolean): List<UiObject2> {
    return flatMap {
        listOfNotNull(it.takeIf(predicate)) + it.children.traverseFind(predicate)
    }
}

class AppUISnapshotAndroid(private val elements: MutableList<UiObject2>) : AppUISnapshot {
    private fun generateUiRepresentation(
        listOfElements: List<UiObject2>,
        result: StringBuilder,
        numberOfSpace: Int = 0,
    ) {
        for (element in listOfElements) {
            addAndroidElement(element)
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

        result.append("$indentationSpaces$resumedClass id=${getAndroidElementId(element)} $writable$clickable$checkable$checked$scrollable$label\n")
    }

    // TO-DO: ids should be pre-generated
    fun getAndroidElementId(element: UiObject2): Int = elements.indexOf(element)
    fun getAndroidElementById(id: Int): UiObject2? = elements.getOrNull(id)
    private fun addAndroidElement(element: UiObject2) {
        elements.add(element)
    }

    override fun toPromptString(): String {
        val result = StringBuilder()
        generateUiRepresentation(this.elements, result)
        return result.toString()
    }
}
