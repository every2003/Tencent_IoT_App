package com.tencent.iot.txiotdemo.activity

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.common.log.L
import com.tencent.iot.txiotdemo.databinding.IotActivityIotCallBinding
import com.tencent.liteav.iot.TXIoTCallSession
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTAudioPlaybackDevice
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTCallEndReason
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTCallListener
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTCallMediaType
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTCallUser
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTCamera
import com.tencent.liteav.iot.TXIoTCallSession.TXIoTQuality
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceId
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTErrorCode

class IoTCallActivity : BaseActivity<IotActivityIotCallBinding>() {

    companion object {
        private const val TAG = "IoTCallActivity"

        const val EXTRA_PRODUCT_ID = "extra_product_id"
        const val EXTRA_DEVICE_NAME = "extra_device_name"
        const val EXTRA_ALIAS_NAME = "extra_alias_name"
        const val EXTRA_CALL_TYPE = "extra_call_type"
        const val EXTRA_IS_INCOMING = "extra_is_incoming"

        fun start(
            context: Context,
            productId: String,
            deviceName: String,
            aliasName: String?,
            callType: TXIoTCallMediaType,
            isIncoming: Boolean = false
        ) {
            val intent = Intent(context, IoTCallActivity::class.java).apply {
                putExtra(EXTRA_PRODUCT_ID, productId)
                putExtra(EXTRA_DEVICE_NAME, deviceName)
                putExtra(EXTRA_ALIAS_NAME, aliasName)
                putExtra(EXTRA_CALL_TYPE, callType.name)
                putExtra(EXTRA_IS_INCOMING, isIncoming)
            }
            context.startActivity(intent)
        }
    }

    private var callSession: TXIoTCallSession? = null
    private var callType: TXIoTCallMediaType = TXIoTCallMediaType.VIDEO
    private var isIncoming: Boolean = false

    private var isInCall: Boolean = false

    private var micMuted: Boolean = false
    private var videoMuted: Boolean = false
    private var speakerOn: Boolean = true
    private var frontCamera: Boolean = true

    private val uiHandler = Handler(Looper.getMainLooper())
    private var callStartTimeMs: Long = 0
    private val tickRunnable = object : Runnable {
        override fun run() {
            updateDurationText()
            uiHandler.postDelayed(this, 1000)
        }
    }

    override fun getViewBinding(): IotActivityIotCallBinding =
        IotActivityIotCallBinding.inflate(layoutInflater)

    override fun onCreate(savedInstanceState: Bundle?) {
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
        super.onCreate(savedInstanceState)
    }

    override fun initView() {
        setImmersiveStatusBar()

        val productId = intent.getStringExtra(EXTRA_PRODUCT_ID).orEmpty()
        val deviceName = intent.getStringExtra(EXTRA_DEVICE_NAME).orEmpty()
        val aliasName = intent.getStringExtra(EXTRA_ALIAS_NAME)
        val callTypeName = intent.getStringExtra(EXTRA_CALL_TYPE)
            ?: TXIoTCallMediaType.VIDEO.name
        callType = runCatching { TXIoTCallMediaType.valueOf(callTypeName) }
            .getOrDefault(TXIoTCallMediaType.VIDEO)
        isIncoming = intent.getBooleanExtra(EXTRA_IS_INCOMING, false)

        speakerOn = callType == TXIoTCallMediaType.VIDEO

        binding.iotTvDeviceName.text = when {
            !aliasName.isNullOrBlank() -> aliasName
            deviceName.isNotBlank() -> deviceName
            else -> getString(R.string.iot_call_default_device)
        }

        applyInitialUiByCallType()
        refreshButtonTexts()

        if (productId.isBlank() || deviceName.isBlank()) {
            show(getString(R.string.iot_call_device_info_missing))
            finish()
            return
        }

        initCallSession(productId, deviceName)
    }

    private fun initCallSession(productId: String, deviceName: String) {
        val deviceId = TXIoTDeviceId().apply {
            this.productId = productId
            this.deviceName = deviceName
        }
        val callUser = TXIoTCallUser().apply { this.deviceId = deviceId }
        val session = TXIoTEngine.getInstance(this).callSession
        if (session == null) {
            show(getString(R.string.iot_call_get_session_failed)); finish(); return
        }
        callSession = session
        session.addListener(sessionListener)
        if (callType == TXIoTCallMediaType.VIDEO) {
            session.openCamera(TXIoTCamera.FRONT, binding.iotVideoLocal)
            session.startRemoteView(callUser, binding.iotVideoRemote)
        }
        session.openMicrophone()

        if (isIncoming) {
            binding.iotTvCallStatus.text = getString(R.string.iot_call_inviting)
            binding.iotLayoutAccept.visibility = View.VISIBLE
        } else {
            binding.iotTvCallStatus.text = getString(R.string.iot_call_waiting_accept)
            binding.iotLayoutAccept.visibility = View.GONE
            session.callDevice(deviceId, callType)
        }

        val playbackDevice =
            if (speakerOn) TXIoTAudioPlaybackDevice.SPEAKER_PHONE else TXIoTAudioPlaybackDevice.EAR_PIECE
        session.selectAudioPlaybackDevice(playbackDevice)
    }

    override fun setListener() {
        binding.iotBtnHangupVideo.setOnClickListener { hangupAndFinish() }
        binding.iotBtnHangupAudio.setOnClickListener { hangupAndFinish() }

        binding.iotBtnAccept.setOnClickListener {
            isIncoming = false
            binding.iotLayoutAccept.visibility = View.GONE
            binding.iotTvCallStatus.text = getString(R.string.iot_call_connecting)
        }

        val micClick = View.OnClickListener {
            micMuted = !micMuted
            if (micMuted) {
                callSession?.closeMicrophone()
            } else {
                callSession?.openMicrophone()
            }
            refreshButtonTexts()
        }
        binding.iotBtnMicVideo.setOnClickListener(micClick)
        binding.iotBtnMicAudio.setOnClickListener(micClick)

        val speakerClick = View.OnClickListener {
            speakerOn = !speakerOn
            if (speakerOn) {
                callSession?.selectAudioPlaybackDevice(TXIoTAudioPlaybackDevice.SPEAKER_PHONE)
            } else {
                callSession?.selectAudioPlaybackDevice(TXIoTAudioPlaybackDevice.EAR_PIECE)
            }
            refreshButtonTexts()
        }
        binding.iotBtnSpeakerVideo.setOnClickListener(speakerClick)
        binding.iotBtnSpeakerAudio.setOnClickListener(speakerClick)

        binding.iotBtnCamera.setOnClickListener {
            videoMuted = !videoMuted
            if (videoMuted) {
                callSession?.closeCamera()
            } else {
                callSession?.openCamera(
                    if (frontCamera) TXIoTCamera.FRONT else TXIoTCamera.BACK,
                    binding.iotVideoLocal
                )
            }
            refreshButtonTexts()
        }

        binding.iotBtnSwitchCamera.setOnClickListener {
            frontCamera = !frontCamera
            callSession?.switchCamera(if (frontCamera) TXIoTCamera.FRONT else TXIoTCamera.BACK)
        }
    }

    private fun applyInitialUiByCallType() {
        if (callType == TXIoTCallMediaType.VIDEO) {
            binding.iotVideoLocal.visibility = View.VISIBLE
            binding.iotVideoLocal.layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            binding.iotVideoRemote.visibility = View.GONE
            binding.iotLayoutRowVideoTop.visibility = View.VISIBLE
            binding.iotLayoutRowVideoBottom.visibility = View.VISIBLE
            binding.iotLayoutRowAudio.visibility = View.GONE
        } else {
            binding.iotVideoLocal.visibility = View.GONE
            binding.iotVideoRemote.visibility = View.GONE
            binding.iotLayoutRowVideoTop.visibility = View.GONE
            binding.iotLayoutRowVideoBottom.visibility = View.GONE
            binding.iotLayoutRowAudio.visibility = View.VISIBLE
        }
    }

    private fun refreshButtonTexts() {
        val micRes = if (micMuted) R.drawable.iot_ic_mic_off else R.drawable.iot_ic_mic_on
        val micBg = if (micMuted) R.drawable.iot_bg_call_btn_gray else R.drawable.iot_bg_call_btn_white
        val micTint = if (micMuted) 0xFFFFFFFF.toInt() else 0xFF111111.toInt()
        val micText =
            if (micMuted) getString(R.string.iot_call_mic_off) else getString(R.string.iot_call_mic_on)
        binding.iotBtnMicVideo.setImageResource(micRes)
        binding.iotBtnMicVideo.setBackgroundResource(micBg)
        binding.iotBtnMicVideo.setColorFilter(micTint)
        binding.iotTvMicVideo.text = micText
        binding.iotBtnMicAudio.setImageResource(micRes)
        binding.iotBtnMicAudio.setBackgroundResource(micBg)
        binding.iotBtnMicAudio.setColorFilter(micTint)
        binding.iotTvMicAudio.text = micText

        val spkRes = if (speakerOn) R.drawable.iot_ic_speaker_on else R.drawable.iot_ic_speaker_off
        val spkBg = if (speakerOn) R.drawable.iot_bg_call_btn_white else R.drawable.iot_bg_call_btn_gray
        val spkTint = if (speakerOn) 0xFF111111.toInt() else 0xFFFFFFFF.toInt()
        val spkText =
            if (speakerOn) getString(R.string.iot_call_speaker_on) else getString(R.string.iot_call_speaker_off)
        binding.iotBtnSpeakerVideo.setImageResource(spkRes)
        binding.iotBtnSpeakerVideo.setBackgroundResource(spkBg)
        binding.iotBtnSpeakerVideo.setColorFilter(spkTint)
        binding.iotTvSpeakerVideo.text = spkText
        binding.iotBtnSpeakerAudio.setImageResource(spkRes)
        binding.iotBtnSpeakerAudio.setBackgroundResource(spkBg)
        binding.iotBtnSpeakerAudio.setColorFilter(spkTint)
        binding.iotTvSpeakerAudio.text = spkText

        val camRes = if (videoMuted) R.drawable.iot_ic_video_slash else R.drawable.iot_ic_video_camera
        val camBg = if (videoMuted) R.drawable.iot_bg_call_btn_gray else R.drawable.iot_bg_call_btn_white
        val camTint = if (videoMuted) 0xFFFFFFFF.toInt() else 0xFF111111.toInt()
        binding.iotBtnCamera.setImageResource(camRes)
        binding.iotBtnCamera.setBackgroundResource(camBg)
        binding.iotBtnCamera.setColorFilter(camTint)
        binding.iotTvCamera.text =
            if (videoMuted) getString(R.string.iot_call_camera_off) else getString(R.string.iot_call_camera_on)
    }

    private val sessionListener = object : TXIoTCallListener {
        override fun onError(errorCode: TXIoTErrorCode?, errorMsg: String?) {
            L.e("$TAG onLocalMediaDeviceError code=$errorCode msg=$errorMsg")
            runOnUiThread { show(getString(R.string.iot_call_error, errorCode, errorMsg)) }
        }

        override fun onCallBegin(mediaType: TXIoTCallMediaType?) {
            L.e("$TAG onRemoteAccepted")
            runOnUiThread { enterInCallState() }
        }

        override fun onCallEnd(
            mediaType: TXIoTCallMediaType?,
            reason: TXIoTCallEndReason?
        ) {
            L.e("$TAG onCallEnd reason=$reason")
            runOnUiThread {
                show(reasonText(reason!!))
                releaseAndFinish()
            }
        }

        override fun onCallRejected(callUser: TXIoTCallUser?) {
            runOnUiThread { show(getString(R.string.iot_call_rejected)) }
        }

        override fun onCallNoResponse(callUser: TXIoTCallUser?) {
            runOnUiThread { show(getString(R.string.iot_call_no_response)) }
        }

        override fun onCallLineBusy(callUser: TXIoTCallUser?) {
            runOnUiThread { show(getString(R.string.iot_call_busy)) }
        }

        override fun onCallUserOffline(callUser: TXIoTCallUser?) {
            runOnUiThread { show(getString(R.string.iot_call_device_offline)) }
        }

        override fun onCallUserAudioAvailable(
            callUser: TXIoTCallUser?,
            available: Boolean
        ) {
            L.e("$TAG onCallUserAudioAvailable=$available")
        }

        override fun onCallUserVideoAvailable(
            callUser: TXIoTCallUser?,
            available: Boolean
        ) {
            L.e("$TAG onCallUserVideoAvailable=$available")
            if (available) {
                L.e("$TAG onFirstVideoFrameRendered")
                runOnUiThread {
                    if (callType == TXIoTCallMediaType.VIDEO) {
                        binding.iotLayoutInfo.visibility = View.GONE
                        callSession?.startRemoteView(callUser, binding.iotVideoRemote)
                    }
                }
            }
        }

        override fun onCallNetworkQualityChanged(
            localQuality: TXIoTQuality?,
            remoteQualityList: List<TXIoTQuality?>?
        ) {
        }
    }

    private fun enterInCallState() {
        if (isInCall) return
        isInCall = true
        binding.iotTvCallStatus.text = getString(R.string.iot_call_in_progress)
        binding.iotLayoutAccept.visibility = View.GONE
        binding.iotTvCallDuration.visibility = View.VISIBLE
        callStartTimeMs = System.currentTimeMillis()
        uiHandler.removeCallbacks(tickRunnable)
        uiHandler.post(tickRunnable)

        if (callType == TXIoTCallMediaType.VIDEO) {
            binding.iotVideoRemote.visibility = View.VISIBLE
            val density = resources.displayMetrics.density
            val w = (110 * density).toInt()
            val h = (160 * density).toInt()
            val lp = FrameLayout.LayoutParams(w, h).apply {
                gravity = Gravity.TOP or Gravity.END
                topMargin = (80 * density).toInt()
                marginEnd = (16 * density).toInt()
            }
            binding.iotVideoLocal.layoutParams = lp
        }
    }

    private fun updateDurationText() {
        val seconds =
            ((System.currentTimeMillis() - callStartTimeMs) / 1000).toInt().coerceAtLeast(0)
        val mm = seconds / 60
        val ss = seconds % 60
        binding.iotTvCallDuration.text = String.format("%02d:%02d", mm, ss)
    }

    private fun reasonText(reason: TXIoTCallEndReason): String = when (reason) {
        TXIoTCallEndReason.LOCAL_HANGUP -> getString(R.string.iot_call_reason_local_hangup)
        TXIoTCallEndReason.REMOTE_HANGUP -> getString(R.string.iot_call_reason_remote_hangup)
        TXIoTCallEndReason.NETWORK_ERROR -> getString(R.string.iot_call_reason_network_error)
        TXIoTCallEndReason.CALL_PERMISSION_DENIED -> getString(R.string.iot_call_reason_permission_denied)
        TXIoTCallEndReason.UNKNOWN -> getString(R.string.iot_call_reason_unknown)
    }

    private fun hangupAndFinish() {
        callSession?.hangup()
        releaseAndFinish()
    }

    private fun releaseAndFinish() {
        uiHandler.removeCallbacks(tickRunnable)
        callSession?.let {
            it.hangup()
            it.removeListener(sessionListener)
        }
        callSession = null
        if (!isFinishing) finish()
    }

    override fun onDestroy() {
        uiHandler.removeCallbacks(tickRunnable)
        callSession?.let {
            it.hangup()
            it.removeListener(sessionListener)
        }
        callSession = null
        super.onDestroy()
    }
}
