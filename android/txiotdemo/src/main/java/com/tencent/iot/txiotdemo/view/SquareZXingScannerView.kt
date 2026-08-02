package com.tencent.iot.txiotdemo.view

import android.content.Context
import android.util.AttributeSet
import android.util.Log
import android.view.Gravity
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import me.dm7.barcodescanner.core.IViewFinder
import me.dm7.barcodescanner.zxing.ZXingScannerView
import kotlin.math.max
import kotlin.math.roundToInt

class SquareZXingScannerView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : ZXingScannerView(context, attrs) {

    companion object {
        private const val TAG = "SquareZXingScanner"

        private const val SCALE_THRESHOLD = 1.001f
    }

    private var cameraPreview: View? = null

    protected override fun createViewFinderView(context: Context): IViewFinder =
        SquareViewFinderView(context)

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        viewTreeObserver.addOnGlobalLayoutListener(globalLayoutListener)
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        viewTreeObserver.removeOnGlobalLayoutListener(globalLayoutListener)
    }

    private val globalLayoutListener = ViewTreeObserver.OnGlobalLayoutListener {
        applyCropToFill()
    }

    private fun applyCropToFill() {
        val pw = width
        val ph = height
        if (pw == 0 || ph == 0) return

        val preview = (cameraPreview?.takeIf { it.parent != null } ?: findCameraPreview()) ?: return
        cameraPreview = preview

        val cw = preview.width
        val ch = preview.height
        if (cw == 0 || ch == 0) return

        val scale = max(pw.toFloat() / cw, ph.toFloat() / ch)
        if (scale <= SCALE_THRESHOLD) return

        val newW = (cw * scale).roundToInt()
        val newH = (ch * scale).roundToInt()
        val lp = preview.layoutParams ?: return

        if (lp.width != newW || lp.height != newH) {
            Log.d(TAG, "crop-to-fill: $cw x $ch -> $newW x $newH (scale=$scale)")
            lp.width = newW
            lp.height = newH
            if (lp is LayoutParams) {
                lp.gravity = Gravity.CENTER
            }
            preview.layoutParams = lp
        }
    }

    private fun findCameraPreview(root: View = this): View? {
        if (root is SurfaceView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findCameraPreview(root.getChildAt(i))?.let { return it }
            }
        }
        return null
    }
}
