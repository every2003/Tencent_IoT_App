package com.tencent.iot.txiotdemo.view

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.util.AttributeSet
import android.view.View
import me.dm7.barcodescanner.core.IViewFinder

class SquareViewFinderView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs), IViewFinder {

    private val framingRect = Rect()

    private val maskPaint = Paint().apply {
        color = 0x60000000.toInt()
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint().apply {
        color = 0xFFFFFFFF.toInt()
        style = Paint.Style.STROKE
        strokeWidth = dp(3).toFloat()
        isAntiAlias = true
    }
    private val laserPaint = Paint().apply {
        color = 0xFF19C5C6.toInt()
        style = Paint.Style.FILL
    }

    private val borderLineLength = dp(24)
    private var laserPosition = 0.5f

    private val laserAnimator by lazy {
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 2000
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE
            addUpdateListener { anim ->
                laserPosition = anim.animatedValue as Float
                invalidate()
            }
        }
    }

    override fun setupViewFinder() {
        invalidate()
    }

    override fun getFramingRect(): Rect = framingRect

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        updateFramingRect()
    }

    private fun updateFramingRect() {
        val size = (minOf(width, height) * 0.65f).toInt()
        val left = (width - size) / 2
        val top = (height - size) / 2
        framingRect.set(left, top, left + size, top + size)
        invalidate()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        laserAnimator.start()
    }

    override fun onDetachedFromWindow() {
        laserAnimator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        if (framingRect.width() == 0) return
        drawMask(canvas)
        drawBorder(canvas)
        drawLaser(canvas)
    }

    private fun drawMask(canvas: Canvas) {
        val r = framingRect
        canvas.drawRect(0f, 0f, width.toFloat(), r.top.toFloat(), maskPaint)
        canvas.drawRect(0f, r.bottom.toFloat(), width.toFloat(), height.toFloat(), maskPaint)
        canvas.drawRect(0f, r.top.toFloat(), r.left.toFloat(), r.bottom.toFloat(), maskPaint)
        canvas.drawRect(
            r.right.toFloat(),
            r.top.toFloat(),
            width.toFloat(),
            r.bottom.toFloat(),
            maskPaint
        )
    }

    private fun drawBorder(canvas: Canvas) {
        val r = framingRect
        val len = borderLineLength.toFloat()
        canvas.drawLine(
            r.left.toFloat(),
            r.top.toFloat(),
            r.left + len,
            r.top.toFloat(),
            borderPaint
        )
        canvas.drawLine(
            r.left.toFloat(),
            r.top.toFloat(),
            r.left.toFloat(),
            r.top + len,
            borderPaint
        )
        canvas.drawLine(
            r.right - len,
            r.top.toFloat(),
            r.right.toFloat(),
            r.top.toFloat(),
            borderPaint
        )
        canvas.drawLine(
            r.right.toFloat(),
            r.top.toFloat(),
            r.right.toFloat(),
            r.top + len,
            borderPaint
        )
        canvas.drawLine(
            r.left.toFloat(),
            r.bottom - len,
            r.left.toFloat(),
            r.bottom.toFloat(),
            borderPaint
        )
        canvas.drawLine(
            r.left.toFloat(),
            r.bottom.toFloat(),
            r.left + len,
            r.bottom.toFloat(),
            borderPaint
        )
        canvas.drawLine(
            r.right - len,
            r.bottom.toFloat(),
            r.right.toFloat(),
            r.bottom.toFloat(),
            borderPaint
        )
        canvas.drawLine(
            r.right.toFloat(),
            r.bottom - len,
            r.right.toFloat(),
            r.bottom.toFloat(),
            borderPaint
        )
    }

    private fun drawLaser(canvas: Canvas) {
        val r = framingRect
        val laserY = r.top + r.height() * laserPosition
        canvas.drawRect(
            (r.left + 2).toFloat(), laserY - 2f,
            (r.right - 2).toFloat(), laserY + 2f,
            laserPaint
        )
    }

    private fun dp(value: Int): Int =
        (resources.displayMetrics.density * value + 0.5f).toInt()
}
