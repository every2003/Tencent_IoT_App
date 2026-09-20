package com.tencent.iot.txiotdemo.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.widget.HorizontalScrollView
import com.tencent.liteav.iot.TXIoTCloudStorage.TXIoTVideoFile
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class CloudStorageTimelineView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    var hourWidthDp: Float = 60f
        set(value) {
            field = value
            requestLayout()
        }

    var hasVideoColor: Int = Color.parseColor("#3D6EFF")

    var noVideoColor: Int = Color.parseColor("#E4E7ED")

    var tickColor: Int = Color.parseColor("#9DA3B0")

    var tickTextColor: Int = Color.parseColor("#6B7280")

    var indicatorColor: Int = Color.parseColor("#FF4D4F")

    var darkMode: Boolean = false
        set(value) {
            field = value
            invalidate()
        }

    var sidePaddingPx: Float = 0f
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
            invalidate()
        }

    private var selectedDate: String = ""

    private var timeZone: TimeZone = TimeZone.getDefault()

    private var dayStartMs: Long = 0L

    private var dayEndMs: Long = 0L

    private data class RenderSegment(
        val startMs: Long,
        val endMs: Long,
        val file: TXIoTVideoFile
    )

    private val videoFiles = mutableListOf<TXIoTVideoFile>()

    private val renderSegments = mutableListOf<RenderSegment>()

    var onSegmentClickListener: ((file: TXIoTVideoFile, tappedTimeMs: Long) -> Unit)? = null

    private val barPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val tickPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = tickColor
        strokeWidth = dp(0.5f)
    }
    private val tickTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = tickTextColor
        textSize = sp(10f)
        textAlign = Paint.Align.CENTER
    }
    private val indicatorPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = indicatorColor
        strokeWidth = dp(1.5f)
    }

    private val tmpRect = RectF()
    private val isoDateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA)

    private val topPadding: Float get() = dp(20f)

    private val barHeight: Float get() = dp(28f)

    private val barWidthPx: Float get() = 24 * hourWidthDp * resources.displayMetrics.density

    private val gestureDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                handleTap(e.x, e.y)
                return true
            }

            override fun onDown(e: MotionEvent): Boolean = true
        })

    fun setDate(date: String, timeZone: TimeZone = TimeZone.getDefault()) {
        this.selectedDate = date
        this.timeZone = timeZone
        val cal = Calendar.getInstance(timeZone)
        try {
            isoDateFormatter.timeZone = timeZone
            val d = isoDateFormatter.parse(date) ?: Date()
            cal.time = d
        } catch (_: Exception) {

        }
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        dayStartMs = cal.timeInMillis
        dayEndMs = dayStartMs + 24L * 60 * 60 * 1000
        rebuildRenderSegments()
        invalidate()
    }

    fun setVideoFiles(files: List<TXIoTVideoFile>) {
        videoFiles.clear()
        videoFiles.addAll(files.sortedBy { it.startTimeMs })
        rebuildRenderSegments()
        invalidate()
    }

    fun clear() {
        videoFiles.clear()
        renderSegments.clear()
        invalidate()
    }

    fun timeAtCenter(scrollX: Int, viewportWidth: Int): Long {
        val centerContentX = scrollX + viewportWidth / 2f
        val time = xToTime(centerContentX)
        return if (time >= dayEndMs) dayEndMs - 1000L else time
    }

    fun videoFileAt(timeMs: Long): TXIoTVideoFile? =
        videoFiles.firstOrNull { f ->
            val end = f.startTimeMs + f.durationMs
            timeMs >= f.startTimeMs && timeMs < end
        }

    fun nearestVideoFileNear(timeMs: Long, rangeMs: Long = 10_000L): Pair<TXIoTVideoFile, Long>? {
        var bestAfter: TXIoTVideoFile? = null
        var bestAfterDiff = Long.MAX_VALUE
        var bestBefore: TXIoTVideoFile? = null
        var bestBeforeDiff = Long.MAX_VALUE

        for (f in videoFiles) {
            val end = f.startTimeMs + f.durationMs
            if (timeMs in f.startTimeMs until end) {
                return f to timeMs
            }
            if (f.startTimeMs >= timeMs) {
                val diff = f.startTimeMs - timeMs
                if (diff in 0..rangeMs && diff < bestAfterDiff) {
                    bestAfterDiff = diff
                    bestAfter = f
                }
            } else if (end <= timeMs) {
                val diff = timeMs - end
                if (diff in 0..rangeMs && diff < bestBeforeDiff) {
                    bestBeforeDiff = diff
                    bestBefore = f
                }
            }
        }

        bestAfter?.let { return it to it.startTimeMs }
        bestBefore?.let {
            return it to timeMs.coerceIn(
                it.startTimeMs,
                it.startTimeMs + it.durationMs - 1
            )
        }
        return null
    }

    fun getXForTime(timeMs: Long): Int {
        if (width <= 0 || dayEndMs <= dayStartMs) return 0
        return timeToX(timeMs).toInt()
    }

    fun firstSegmentStartMs(): Long? = renderSegments.firstOrNull()?.startMs

    private fun rebuildRenderSegments() {
        renderSegments.clear()
        if (videoFiles.isEmpty() || dayEndMs <= dayStartMs) return

        for (cur in videoFiles) {
            val start = cur.startTimeMs
            val duration = cur.durationMs
            if (duration <= 0L) continue
            val end = start + duration
            val s = start.coerceAtLeast(dayStartMs)
            val e = end.coerceAtMost(dayEndMs)
            if (e <= s) continue
            renderSegments.add(RenderSegment(s, e, cur))
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val totalWidth = (barWidthPx + sidePaddingPx * 2).toInt()
        val totalHeight = (topPadding + barHeight + dp(8f)).toInt()
        setMeasuredDimension(
            resolveSize(totalWidth, widthMeasureSpec),
            resolveSize(totalHeight, heightMeasureSpec)
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width <= 0) return

        val barTop = topPadding
        val barBottom = barTop + barHeight
        val barLeft = sidePaddingPx
        val barRight = sidePaddingPx + barWidthPx

        barPaint.color = if (darkMode) Color.parseColor("#3A3A3A") else noVideoColor
        tmpRect.set(barLeft, barTop, barRight, barBottom)
        canvas.drawRoundRect(tmpRect, dp(2f), dp(2f), barPaint)

        if (dayEndMs > dayStartMs && renderSegments.isNotEmpty()) {
            barPaint.color = hasVideoColor
            for (seg in renderSegments) {
                val s = seg.startMs.coerceIn(dayStartMs, dayEndMs)
                val e = seg.endMs.coerceIn(dayStartMs, dayEndMs)
                if (e <= s) continue
                val left = timeToX(s)
                val right = timeToX(e).coerceAtLeast(left + dp(0.5f))
                tmpRect.set(left, barTop, right, barBottom)
                canvas.drawRect(tmpRect, barPaint)
            }
        }

        tickPaint.color = if (darkMode) Color.parseColor("#666666") else tickColor
        tickTextPaint.color = if (darkMode) Color.parseColor("#B0B0B0") else tickTextColor
        for (h in 0..24) {
            val x = barLeft + (h.toFloat() / 24f) * barWidthPx
            val isMajor = h % 6 == 0
            tickPaint.alpha = if (isMajor) 200 else 120
            canvas.drawLine(
                x,
                barTop - dp(if (isMajor) 6f else 3f),
                x,
                barTop,
                tickPaint
            )

            if (h < 24) {
                val label = String.format(Locale.CHINA, "%02d:00", h)
                canvas.drawText(label, x, barTop - dp(8f), tickTextPaint)
            } else {
                val oldAlign = tickTextPaint.textAlign
                tickTextPaint.textAlign = Paint.Align.RIGHT
                canvas.drawText("23:59:59", barRight, barTop - dp(8f), tickTextPaint)
                tickTextPaint.textAlign = oldAlign
            }
        }

        drawCurrentIndicatorIfNeeded(canvas, barTop, barBottom)
    }

    private fun drawCurrentIndicatorIfNeeded(canvas: Canvas, barTop: Float, barBottom: Float) {
        if (dayEndMs <= dayStartMs) return
        val now = System.currentTimeMillis()
        if (now < dayStartMs || now > dayEndMs) return
        val x = timeToX(now)
        canvas.drawLine(x, barTop - dp(4f), x, barBottom + dp(4f), indicatorPaint)
    }

    private fun timeToX(timeMs: Long): Float {
        val total = (dayEndMs - dayStartMs).toFloat()
        if (total <= 0f) return sidePaddingPx
        val ratio = ((timeMs - dayStartMs).toFloat() / total).coerceIn(0f, 1f)
        return sidePaddingPx + ratio * barWidthPx
    }

    private fun xToTime(x: Float): Long {
        val bar = barWidthPx
        if (bar <= 0f || dayEndMs <= dayStartMs) return dayStartMs
        val ratio = ((x - sidePaddingPx) / bar).coerceIn(0f, 1f)
        return dayStartMs + (ratio * (dayEndMs - dayStartMs)).toLong()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        gestureDetector.onTouchEvent(event)
        return true
    }

    private fun handleTap(x: Float, y: Float) {
        val barTop = topPadding
        val barBottom = barTop + barHeight
        if (y < barTop - dp(4f) || y > barBottom + dp(4f)) return
        val tappedTime = xToTime(x)
        val hit = renderSegments.firstOrNull { tappedTime in it.startMs..it.endMs }
        if (hit != null) {
            onSegmentClickListener?.invoke(hit.file, tappedTime)
        }
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density
    private fun sp(value: Float): Float = value * resources.displayMetrics.scaledDensity
}
