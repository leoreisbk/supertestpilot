package co.work.testpilot.extensions

fun String.simplifyUI(): String {
    var simplifiedUI = this
    // Removing all elements without relevant info; also removes all hex mem addresses and frames
    simplifiedUI = Regex("(\\n\\s*.*\\}\\}$|, 0x.*\\}\\})", RegexOption.MULTILINE).replace(simplifiedUI, "")
    simplifiedUI = Regex("^\\s\\s+", RegexOption.MULTILINE).replace(simplifiedUI, "")

    // Removing "header"
    val headerRange = Regex("→Application.*?$", RegexOption.MULTILINE).find(simplifiedUI)?.range
    if (headerRange != null) {
        simplifiedUI = simplifiedUI.substring(startIndex = headerRange.last + 1)
    }

    // Removing "footer"
    val footerIndex = simplifiedUI.indexOf("\nPath to element")
    if (footerIndex >= 0) {
        simplifiedUI = simplifiedUI.substring(startIndex = 0, endIndex = footerIndex)
    }
    return simplifiedUI
}
