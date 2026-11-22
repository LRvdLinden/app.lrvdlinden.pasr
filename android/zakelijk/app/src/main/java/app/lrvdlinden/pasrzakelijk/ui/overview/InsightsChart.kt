package app.lrvdlinden.pasrzakelijk.ui.overview

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.lrvdlinden.pasrzakelijk.ui.LocalDark
import app.lrvdlinden.pasrzakelijk.ui.Pz
import java.util.Date
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

data class MetricPoint(val date: Date, val value: Double)

/**
 * Grafiek in de stijl van Homey Insights: vloeiende lijn met verloopvlak, gestippeld raster, eenheid bovenaan de
 * Y-as, dunne asslijnen en selectie met een ring-punt (tik of veeg). Zelfde opzet als InsightsChart.swift.
 */
@Composable
fun InsightsChart(
    points: List<MetricPoint>,
    unit: String,
    color: Color,
    xLabel: (Date) -> String,
    selected: MetricPoint?,
    onSelect: (MetricPoint?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val grid = Pz.insightsGrid
    val muted = Pz.muted
    val ringFill = if (LocalDark.current) Color.Black else Color.White
    val maxValue = max(4.0, (points.maxOfOrNull { it.value } ?: 0.0) * 1.15)
    val step = niceStep(maxValue / 4)
    val top = ceil(maxValue / step) * step

    fun indexAt(x: Float, left: Float, width: Float): Int {
        if (points.size < 2) return 0
        return (((x - left) / width) * (points.size - 1)).roundToInt().coerceIn(0, points.size - 1)
    }

    Canvas(
        modifier
            .fillMaxWidth()
            .height(220.dp)
            .semantics { contentDescription = unit }
            .pointerInput(points) {
                val left = 34.dp.toPx()
                detectTapGestures { o -> if (points.isNotEmpty()) onSelect(points[indexAt(o.x, left, size.width - left - 6.dp.toPx())]) }
            }
            .pointerInput(points) {
                val left = 34.dp.toPx()
                detectDragGestures(onDragEnd = { }, onDragCancel = { }) { change, _ ->
                    if (points.isNotEmpty()) onSelect(points[indexAt(change.position.x, left, size.width - left - 6.dp.toPx())])
                }
            },
    ) {
        val left = 34.dp.toPx()
        val right = size.width - 6.dp.toPx()
        val topY = 26.dp.toPx()
        val bottom = size.height - 22.dp.toPx()
        val w = right - left
        val h = bottom - topY
        val labelPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            this.color = muted.toArgb(); textSize = 11.sp.toPx()
        }
        // eenheid bovenaan de Y-as, zoals Homey
        drawContext.canvas.nativeCanvas.drawText(unit, 0f, 11.sp.toPx(), labelPaint.apply { isFakeBoldText = true })
        labelPaint.isFakeBoldText = false
        // gestippelde rasterlijnen met waarden
        var v = 0.0
        while (v <= top + 0.0001) {
            val y = bottom - (v / top * h).toFloat()
            if (v > 0) drawLine(grid, Offset(left, y), Offset(right, y), 0.5.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx())))
            val label = if (step >= 1) v.roundToInt().toString() else String.format("%.1f", v)
            drawContext.canvas.nativeCanvas.drawText(label, 0f, y + 4.sp.toPx(), labelPaint)
            v += step
        }
        // dunne lijn langs de Y-as en de X-as
        drawLine(grid, Offset(left, topY), Offset(left, bottom), 1.dp.toPx())
        drawLine(grid, Offset(left, bottom), Offset(right, bottom), 1.dp.toPx())
        if (points.isEmpty()) return@Canvas

        fun px(i: Int) = if (points.size == 1) left + w / 2 else left + w * i / (points.size - 1)
        fun py(value: Double) = bottom - (value / top * h).toFloat()
        val xy = points.mapIndexed { i, p -> Offset(px(i), py(p.value)) }

        // vloeiende lijn (Catmull-Rom als Bézier)
        val line = Path().apply {
            moveTo(xy[0].x, xy[0].y)
            for (i in 0 until xy.size - 1) {
                val p0 = xy[max(0, i - 1)]
                val p1 = xy[i]
                val p2 = xy[i + 1]
                val p3 = xy[minOf(xy.size - 1, i + 2)]
                val c1 = Offset(p1.x + (p2.x - p0.x) / 6f, (p1.y + (p2.y - p0.y) / 6f).coerceIn(topY, bottom))
                val c2 = Offset(p2.x - (p3.x - p1.x) / 6f, (p2.y - (p3.y - p1.y) / 6f).coerceIn(topY, bottom))
                cubicTo(c1.x, c1.y, c2.x, c2.y, p2.x, p2.y)
            }
        }
        val area = Path().apply {
            addPath(line)
            lineTo(xy.last().x, bottom)
            lineTo(xy.first().x, bottom)
            close()
        }
        drawPath(area, Brush.verticalGradient(listOf(color.copy(alpha = 0.35f), color.copy(alpha = 0f)), startY = topY, endY = bottom))
        drawPath(line, color, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))

        // labels onder de X-as (ongeveer 5)
        val count = minOf(5, points.size)
        if (count > 0) {
            labelPaint.textAlign = android.graphics.Paint.Align.CENTER
            for (k in 0 until count) {
                val i = if (count == 1) 0 else (k * (points.size - 1)) / (count - 1)
                val x = px(i).coerceIn(left + 14.dp.toPx(), right - 14.dp.toPx())
                drawContext.canvas.nativeCanvas.drawText(xLabel(points[i].date), x, size.height - 4.dp.toPx(), labelPaint)
            }
        }

        // selectie: verticale lijn + ring-punt
        selected?.let { s ->
            val i = points.indexOfFirst { it.date == s.date }.takeIf { it >= 0 } ?: return@let
            val x = px(i)
            val y = py(points[i].value)
            drawLine(muted.copy(alpha = 0.5f), Offset(x, topY), Offset(x, bottom), 1.dp.toPx())
            drawCircle(ringFill, 5.dp.toPx(), Offset(x, y))
            drawCircle(color, 5.dp.toPx(), Offset(x, y), style = Stroke(2.dp.toPx()))
        }
    }
}

private fun niceStep(raw: Double): Double {
    if (raw <= 0) return 1.0
    val mag = Math.pow(10.0, Math.floor(Math.log10(raw)))
    val n = raw / mag
    val nice = when { n <= 1 -> 1.0; n <= 2 -> 2.0; n <= 2.5 -> 2.5; n <= 5 -> 5.0; else -> 10.0 }
    return max(1.0, nice * mag)
}
