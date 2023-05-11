package co.work.testpilot

import androidx.test.uiautomator.UiObject2
import co.work.testpilot.runtime.ElementType

fun List<UiObject2>.traverseFind(predicate: (UiObject2) -> Boolean): List<UiObject2> {
    return flatMap {
        listOfNotNull(it.takeIf(predicate)) + it.children.traverseFind(predicate)
    }
}

fun List<UiObject2>.traverse(): List<UiObject2> {
    return flatMap {
        listOf(it) + it.children.traverse()
    }
}

class AppUISnapshotAndroid(private val elements: List<UiObject2>) : AppUISnapshot {
    private val traverseElements = elements.traverse()

    private fun getMinifiedElementDescription(element: UiObject2, spaces: Int = 0): String {
        val indentationSpaces = " ".repeat(spaces)
        val resumedClass = element.className.substring(element.className.lastIndexOf('.') + 1)
        val writable = if (element.className.contains("EditText")) "writable" else ""
        val clickable = if (element.isClickable) " clickable" else ""
        val checkable = if (element.isCheckable) "checkable " else ""
        val checked = if (element.isChecked) " checked" else ""
        val scrollable = if (element.isScrollable) " scrollable" else ""
        val label = if (element.contentDescription != null) " label=\"${element.contentDescription}\"" else if (element.text != null) " label=\"${element.text}\"" else ""

        return "$indentationSpaces$resumedClass id=${getAndroidElementId(element)} $writable$clickable$checkable$checked$scrollable$label"
    }

    fun getAndroidElementId(element: UiObject2): Int = traverseElements.indexOf(element)
    fun getAndroidElementById(id: Int): UiObject2? = traverseElements.getOrNull(id)

    override fun toPromptString(): String {
        val result = StringBuilder()
        this.elements.traverse().forEach { element ->
            result.appendLine(getMinifiedElementDescription(element))
        }
        return result.toString()
    }

    override val allElements = this.elements.traverse().map { AppUIElementSnapshotAndroid(it) }
}

class AppUIElementSnapshotAndroid(element: UiObject2) : AppUIElementSnapshot {
    override val type: ElementType = when (element.className.split(".").last()) {
        "EditText" -> ElementType.TextField
        "Text", "Label" -> ElementType.TextView
        "Button" -> ElementType.Button
        "CheckBox" -> ElementType.CheckBox
        "View" -> ElementType.View
        "Spinner" -> ElementType.Picker
        "Image" -> ElementType.Image
        "ScrollView" -> ElementType.ScrollView
        "RadioButton" -> ElementType.RadioButton
        "RadioGroup" -> ElementType.RadioGroup
        else -> ElementType.Unknown
    }

    override val label: String = element.contentDescription
}
