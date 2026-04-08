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
    )

    private fun labelsFor(language: String): Labels = when (language) {
        "pt-BR", "pt" -> Labels(
            htmlLang = "pt-BR",
            title = "Relatório de Análise TestPilot",
            summary = "Resumo",
            stepByStep = "Passo a passo",
            step = "Passo",
            steps = "passos",
        )
        else -> Labels(
            htmlLang = "en",
            title = "TestPilot Analysis Report",
            summary = "Summary",
            stepByStep = "Step-by-step",
            step = "Step",
            steps = "steps",
        )
    }

    @OptIn(ExperimentalEncodingApi::class)
    fun generate(report: AnalysisReport, language: String = "en"): String {
        val lbl = labelsFor(language)
        val stepsHtml = report.steps.mapIndexed { index, step ->
            val base64 = Base64.encode(step.screenshotData)
            val obsHtml = step.observation
                ?.let { "<p class=\"obs\">${it.htmlEscape()}</p>" }
                ?: ""
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
              <img src="data:image/png;base64,$base64" alt="${lbl.step} ${index + 1}" />
              $obsHtml
            </div>
            """.trimIndent()
        }.joinToString("\n")

        val durationText = fmtDuration(report.durationMs)

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
          .summary-box { margin: 24px 40px; background: #fff; border-radius: 12px;
                         padding: 20px 24px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .summary-box h2 { font-size: 15px; font-weight: 600; margin-bottom: 8px; }
          .summary-box p { font-size: 14px; color: #3a3a3c; }
          .steps { padding: 0 40px 40px; }
          .steps h2 { font-size: 15px; font-weight: 600; margin: 24px 0 12px; }
          .step { background: #fff; border-radius: 12px; margin-bottom: 16px;
                  overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
          .step-header { display: flex; align-items: center; gap: 10px;
                         padding: 12px 16px; background: #f2f2f7; }
          .step-num { font-size: 12px; color: #8e8e93; }
          .action { font-size: 13px; font-weight: 600; background: #007aff;
                    color: #fff; padding: 2px 8px; border-radius: 4px; }
          .coord { font-size: 12px; color: #8e8e93; font-family: monospace; }
          .step img { display: block; width: 100%; max-width: 390px;
                      height: auto; margin: 0 auto; }
          .obs { padding: 12px 16px; font-size: 14px; color: #3a3a3c;
                 border-top: 1px solid #f2f2f7; }
        </style>
        </head>
        <body>
        <div class="header">
          <h1>${lbl.title}</h1>
          <div class="objective">${report.objective.htmlEscape()}</div>
          <div class="meta">${report.stepCount} ${lbl.steps} &middot; $durationText</div>
        </div>
        <div class="summary-box">
          <h2>${lbl.summary}</h2>
          <p>${report.summary.htmlEscape()}</p>
        </div>
        <div class="steps">
          <h2>${lbl.stepByStep}</h2>
          $stepsHtml
        </div>
        </body>
        </html>
        """.trimIndent()
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
