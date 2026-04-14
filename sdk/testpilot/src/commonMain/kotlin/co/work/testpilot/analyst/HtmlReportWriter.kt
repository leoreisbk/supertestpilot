package co.work.testpilot.analyst

import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

object HtmlReportWriter {

    private data class Labels(
        val htmlLang: String,
        val title: String,
        val summary: String,
        val stepByStep: String,
        val step: String,
        val steps: String,
        val evaluatedAs: String,
    )

    private fun labelsFor(language: String): Labels = when (language) {
        "pt-BR", "pt" -> Labels(
            htmlLang    = "pt-BR",
            title       = "Relatório de Análise TestPilot",
            summary     = "Resumo",
            stepByStep  = "Passo a passo",
            step        = "Passo",
            steps       = "passos",
            evaluatedAs = "Avaliado como",
        )
        else -> Labels(
            htmlLang    = "en",
            title       = "TestPilot Analysis Report",
            summary     = "Summary",
            stepByStep  = "Step-by-step",
            step        = "Step",
            steps       = "steps",
            evaluatedAs = "Evaluated as",
        )
    }

    @OptIn(ExperimentalEncodingApi::class)
    fun generate(report: AnalysisReport, language: String = "en"): String {
        val lbl = labelsFor(language)
        val stepsHtml = report.steps.mapIndexed { index, step ->
            val base64 = Base64.encode(step.screenshotData)
            val obsContent = step.observation
                ?.takeIf { it.isNotBlank() }
                ?.let { "<p>${renderObservation(it)}</p>" }
                ?: "<p class=\"step-obs-empty\">—</p>"
            val coordHtml = step.coordinates
                ?.let { (x, y) -> "<span class=\"coord\">(${fmtCoord(x)}, ${fmtCoord(y)})</span>" }
                ?: ""
            """
            <div class="step">
              <div class="step-header">
                <span class="step-num">${lbl.step} ${index + 1}</span>
                <span class="action">${step.action.htmlEscape()}</span>
                $coordHtml
              </div>
              <div class="step-body">
                <div class="step-img-col">
                  <img src="data:${step.screenshotData.imageMimeType()};base64,$base64" alt="${lbl.step} ${index + 1}" loading="lazy" />
                </div>
                <div class="step-obs-col">
                  $obsContent
                </div>
              </div>
            </div>
            """.trimIndent()
        }.joinToString("\n")

        val durationText = fmtDuration(report.durationMs)

        val personaCardHtml = report.persona
            ?.takeIf { it.isNotBlank() }
            ?.let { persona ->
                val firstLine = persona.lines()
                    .firstOrNull { it.isNotBlank() }
                    ?.trimStart('#', ' ')
                    ?.htmlEscape()
                    ?: ""
                val fullPersona = persona.htmlEscape()
                """
                <div class="persona-card">
                  <span class="persona-icon">👤</span>
                  <div class="persona-content">
                    <div class="persona-label">${lbl.evaluatedAs}</div>
                    <div class="persona-text">$firstLine</div>
                    <details>
                      <summary class="persona-show-more">Show full persona</summary>
                      <pre class="persona-full">$fullPersona</pre>
                    </details>
                  </div>
                </div>
                """.trimIndent()
            } ?: ""

        return """
        <!DOCTYPE html>
        <html lang="${lbl.htmlLang}">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${lbl.title}</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                 background: #f5f5f7; color: #1d1d1f; line-height: 1.5; }
          .header { background: #fff; padding: 32px 40px; border-bottom: 1px solid #e5e5ea; }
          .header h1 { font-size: 22px; font-weight: 600; margin-bottom: 8px; }
          .header .objective { color: #6e6e73; font-size: 15px; }
          .meta { margin-top: 12px; font-size: 13px; color: #8e8e93; }
          .persona-card { display: flex; gap: 10px; align-items: flex-start; margin-top: 14px;
                          background: #f2f2f7; border-radius: 8px; padding: 10px 14px; }
          .persona-icon { font-size: 20px; line-height: 1.3; }
          .persona-label { font-size: 11px; color: #8e8e93; text-transform: uppercase;
                           letter-spacing: .04em; }
          .persona-text  { font-size: 13px; font-weight: 500; margin-top: 2px; color: #1d1d1f; }
          .persona-show-more { font-size: 12px; color: #007aff; cursor: pointer; margin-top: 4px; list-style: none; }
          .persona-full  { font-size: 12px; color: #6e6e73; margin-top: 6px;
                           white-space: pre-wrap; line-height: 1.5; font-family: inherit; }
          .summary-box { margin: 24px 40px; background: #fff; border-radius: 12px;
                         padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .summary-box h2 { font-size: 15px; font-weight: 600; margin-bottom: 8px; }
          .summary-content { font-size: 14px; color: #3a3a3c; }
          .summary-content p { margin-bottom: 6px; }
          .summary-content ul { padding-left: 18px; margin: 4px 0 8px; }
          .summary-content li { margin-bottom: 3px; }
          .summary-content strong { font-weight: 600; }
          .steps { padding: 0 40px 40px; }
          .steps h2 { font-size: 15px; font-weight: 600; margin: 24px 0 12px; }
          .step { background: #fff; border-radius: 12px; margin-bottom: 16px;
                  box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .step-header { display: flex; align-items: center; gap: 10px;
                         padding: 12px 16px; background: #f2f2f7;
                         border-radius: 12px 12px 0 0; }
          .step-num { font-size: 12px; color: #8e8e93; }
          .action { font-size: 13px; font-weight: 600; background: #007aff;
                    color: #fff; padding: 2px 8px; border-radius: 4px; }
          .coord { font-size: 12px; color: #8e8e93; font-family: monospace; }
          .step-body { display: flex; flex-direction: row; align-items: flex-start; }
          .step-img-col { flex: 0 0 40%; padding: 12px; }
          .step-img-col img { display: block; width: 100%; height: auto; border-radius: 8px; }
          .step-obs-col { flex: 1; padding: 16px 16px 16px 8px;
                          font-size: 14px; line-height: 1.6; color: #3a3a3c; }
          .step-obs-empty { color: #aeaeb2; font-style: italic; }
          .badge { display: inline-block; font-size: 10px; font-weight: 700; letter-spacing: .06em;
                   padding: 1px 6px; border-radius: 3px; margin-right: 6px; vertical-align: middle; }
          .badge-critical { background: #ff3b30; color: #fff; }
          .badge-issue    { background: #ff9500; color: #fff; }
          .badge-positive { background: #34c759; color: #fff; }
          @media (max-width: 600px) {
            .step-body { flex-direction: column; }
            .step-img-col { flex: none; width: 100%; }
          }
          @media (prefers-color-scheme: dark) {
            body { background: #1c1c1e; color: #f5f5f7; }
            .header { background: #2c2c2e; border-bottom-color: #3a3a3c; }
            .header .objective { color: #aeaeb2; }
            .meta { color: #636366; }
            .persona-card  { background: #3a3a3c; }
            .persona-text  { color: #f5f5f7; }
            .persona-label { color: #636366; }
            .persona-full  { color: #aeaeb2; }
            .summary-box { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
            .summary-content { color: #ebebf0; }
            .step { background: #2c2c2e; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
            .step-header { background: #3a3a3c; }
            .step-num { color: #636366; }
            .coord { color: #636366; }
            .step-obs-col { color: #ebebf0; }
          }
        </style>
        </head>
        <body>
        <div class="header">
          <h1>${lbl.title}</h1>
          <div class="objective">${report.objective.htmlEscape()}</div>
          <div class="meta">${report.stepCount} ${lbl.steps} &middot; $durationText</div>
          $personaCardHtml
        </div>
        <div class="summary-box">
          <h2>${lbl.summary}</h2>
          <div class="summary-content">${report.summary.renderSummaryMarkdown()}</div>
        </div>
        <div class="steps">
          <h2>${lbl.stepByStep}</h2>
          $stepsHtml
        </div>
        </body>
        </html>
        """.trimIndent()
    }

    // Parses [CRITICAL]/[ISSUE]/[POSITIVE] prefix into a colored badge.
    private fun renderObservation(obs: String): String {
        val (badge, text) = when {
            obs.startsWith("[CRITICAL]") ->
                """<span class="badge badge-critical">CRITICAL</span>""" to obs.removePrefix("[CRITICAL]").trim()
            obs.startsWith("[ISSUE]") ->
                """<span class="badge badge-issue">ISSUE</span>""" to obs.removePrefix("[ISSUE]").trim()
            obs.startsWith("[POSITIVE]") ->
                """<span class="badge badge-positive">POSITIVE</span>""" to obs.removePrefix("[POSITIVE]").trim()
            else -> "" to obs
        }
        return "$badge${text.htmlEscape()}"
    }

    // Converts **bold** and - bullets to HTML, line by line.
    private fun String.renderSummaryMarkdown(): String {
        val lines = this.split("\n")
        val out = StringBuilder()
        var inList = false
        for (line in lines) {
            when {
                line.startsWith("- ") -> {
                    if (!inList) { out.append("<ul>"); inList = true }
                    val content = line.removePrefix("- ").htmlEscape().renderBold()
                    out.append("<li>$content</li>")
                }
                line.isBlank() -> {
                    if (inList) { out.append("</ul>"); inList = false }
                }
                else -> {
                    if (inList) { out.append("</ul>"); inList = false }
                    out.append("<p>${line.htmlEscape().renderBold()}</p>")
                }
            }
        }
        if (inList) out.append("</ul>")
        return out.toString()
    }

    private fun String.renderBold(): String =
        replace(Regex("\\*\\*(.+?)\\*\\*"), "<strong>$1</strong>")

    private fun ByteArray.imageMimeType(): String = when {
        size >= 2 && this[0] == 0xFF.toByte() && this[1] == 0xD8.toByte() -> "image/jpeg"
        else -> "image/png"
    }

    private fun String.htmlEscape(): String = this
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")

    private fun fmtDuration(ms: Long): String {
        val sec = ms / 1000
        val dec = (ms % 1000) / 100
        return "${sec}.${dec}s"
    }

    private fun fmtCoord(v: Double): String {
        val rounded = kotlin.math.round(v * 100).toInt()
        val intPart = rounded / 100
        val decPart = rounded % 100
        return "$intPart.${decPart.toString().padStart(2, '0')}"
    }
}
