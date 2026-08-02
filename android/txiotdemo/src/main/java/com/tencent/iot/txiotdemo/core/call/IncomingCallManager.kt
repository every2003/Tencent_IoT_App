package com.tencent.iot.txiotdemo.core.call

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.activity.IoTCallActivity
import com.tencent.iot.txiotdemo.common.log.L
import com.tencent.liteav.iot.TXIoTCallSession
import java.lang.ref.WeakReference

@SuppressLint("StaticFieldLeak")
object IncomingCallManager {

    private const val TAG = "IncomingCallManager"

    @Volatile
    private var started: Boolean = false

    private var foregroundActivityRef: WeakReference<Activity>? = null

    private var pendingCall: IncomingCall? = null

    private var bannerView: View? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    fun init(application: Application) {
        application.registerActivityLifecycleCallbacks(lifecycleCallbacks)
    }

    fun start(context: Context) {
        if (started) return
        started = true
        L.e("$TAG start(): Register global incoming call listener (waiting for SDK integration)")
    }

    @Synchronized
    fun stop() {
        if (!started) return
        started = false
        L.e("$TAG stop(): Remove global incoming call listener")
        mainHandler.post { dismissBanner() }

    }

    fun notifyIncomingCall(
        productId: String,
        deviceName: String,
        aliasName: String?,
        callType: TXIoTCallSession.TXIoTCallMediaType
    ) {
        mainHandler.post {
            pendingCall = IncomingCall(productId, deviceName, aliasName, callType)
            attachBannerToForeground()
        }
    }

    fun showIncoming(
        context: Context,
        productId: String,
        deviceName: String,
        aliasName: String?,
        callType: TXIoTCallSession.TXIoTCallMediaType
    ) {
        val intent = Intent(context, IoTCallActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(IoTCallActivity.EXTRA_PRODUCT_ID, productId)
            putExtra(IoTCallActivity.EXTRA_DEVICE_NAME, deviceName)
            putExtra(IoTCallActivity.EXTRA_ALIAS_NAME, aliasName)
            putExtra(IoTCallActivity.EXTRA_CALL_TYPE, callType.name)
            putExtra(IoTCallActivity.EXTRA_IS_INCOMING, true)
        }
        context.startActivity(intent)
    }

    private fun attachBannerToForeground() {
        val call = pendingCall ?: return
        val activity = foregroundActivityRef?.get()
        if (activity == null || activity.isFinishing) {
            L.e("$TAG attachBannerToForeground(): No foreground activity, will attach on Activity resume")
            return
        }
        removeBannerFromCurrentActivity()

        val decor = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val view = LayoutInflater.from(activity)
            .inflate(R.layout.iot_view_incoming_call_banner, decor, false)

        val lp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.TOP
            topMargin = getStatusBarHeight(activity) + dp(activity, 4f)
        }
        view.layoutParams = lp

        view.findViewById<TextView>(R.id.iot_tvIncomingName).text =
            call.aliasName?.takeIf { it.isNotBlank() } ?: call.deviceName
        view.findViewById<TextView>(R.id.iot_tvIncomingSubtitle).text = when (call.callType) {
            TXIoTCallSession.TXIoTCallMediaType.VIDEO -> activity.getString(R.string.iot_incoming_video_call)
            TXIoTCallSession.TXIoTCallMediaType.AUDIO -> activity.getString(R.string.iot_incoming_audio_call)
        }
        view.findViewById<ImageView>(R.id.iot_btnIncomingAccept).setOnClickListener {
            onAcceptClicked(activity)
        }
        view.findViewById<ImageView>(R.id.iot_btnIncomingReject).setOnClickListener {
            onRejectClicked()
        }

        decor.addView(view)
        bannerView = view
    }

    private fun onAcceptClicked(activity: Activity) {
        val call = pendingCall ?: return
        dismissBanner()
        IoTCallActivity.start(
            activity,
            call.productId,
            call.deviceName,
            call.aliasName,
            call.callType,
            isIncoming = true
        )
    }

    private fun onRejectClicked() {
        L.e("$TAG Reject incoming call: ${pendingCall}")
        dismissBanner()
    }

    private fun dismissBanner() {
        removeBannerFromCurrentActivity()
        pendingCall = null
    }

    private fun removeBannerFromCurrentActivity() {
        bannerView?.let { v ->
            (v.parent as? ViewGroup)?.removeView(v)
        }
        bannerView = null
    }

    private fun getStatusBarHeight(context: Context): Int {
        val id = context.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) context.resources.getDimensionPixelSize(id) else dp(context, 24f)
    }

    private fun dp(context: Context, value: Float): Int =
        (context.resources.displayMetrics.density * value + 0.5f).toInt()

    private val lifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}

        override fun onActivityStarted(activity: Activity) {}

        override fun onActivityResumed(activity: Activity) {
            foregroundActivityRef = WeakReference(activity)
            if (pendingCall != null && bannerView?.context !== activity) {
                removeBannerFromCurrentActivity()
                attachBannerToForeground()
            }
        }

        override fun onActivityPaused(activity: Activity) {
            if (bannerView?.context === activity) {
                removeBannerFromCurrentActivity()
            }
        }

        override fun onActivityStopped(activity: Activity) {}

        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

        override fun onActivityDestroyed(activity: Activity) {
            if (foregroundActivityRef?.get() === activity) {
                foregroundActivityRef = null
            }
        }
    }

    private data class IncomingCall(
        val productId: String,
        val deviceName: String,
        val aliasName: String?,
        val callType: TXIoTCallSession.TXIoTCallMediaType
    )
}
