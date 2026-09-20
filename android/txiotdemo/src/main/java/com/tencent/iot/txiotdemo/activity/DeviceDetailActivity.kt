package com.tencent.iot.txiotdemo.activity

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.view.isVisible
import androidx.recyclerview.widget.GridLayoutManager
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.adapter.MultiChannelAdapter
import com.tencent.iot.txiotdemo.common.CommonBottomSheet
import com.tencent.iot.txiotdemo.common.log.L
import com.tencent.iot.txiotdemo.common.util.DeviceJsonUtils
import com.tencent.iot.txiotdemo.common.util.Utils
import com.tencent.iot.txiotdemo.databinding.IotActivityDeviceDetailBinding
import com.tencent.liteav.iot.TXIoTDeviceManager
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngineDef
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTCallback
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTErrorCode
import com.tencent.liteav.iot.TXIoTMonitorSession
import com.tencent.liteav.iot.TXIoTMonitorSession.TXIoTLocalRecordingParams
import com.tencent.liteav.iot.TXIoTMonitorSession.TXIoTMonitorSessionListener
import com.tencent.liteav.iot.TXIoTMonitorSession.TXIoTPTZCommand
import com.tencent.liteav.iot.TXIoTMonitorSession.TXIoTPlayState
import com.tencent.liteav.iot.TXIoTMonitorSession.TXIoTStreamType
import com.tencent.rtmp.ui.TXCloudVideoView

private const val COLOR_PRIMARY = "#006EFF"
private const val COLOR_LABEL_NORMAL = "#9DA3B0"

private val NON_FATAL_ERROR_CODES = setOf(
    TXIoTErrorCode.ERR_MIC_START_FAIL,
    TXIoTErrorCode.ERR_MIC_NOT_AUTHORIZED,
    TXIoTErrorCode.ERR_MIC_OCCUPY,
    TXIoTErrorCode.ERR_CAMERA_START_FAIL,
    TXIoTErrorCode.ERR_CAMERA_NOT_AUTHORIZED,
    TXIoTErrorCode.ERR_CAMERA_OCCUPY
)

class DeviceDetailActivity : BaseActivity<IotActivityDeviceDetailBinding>() {

    private val deviceInfo by lazy {
        intent.getStringExtra("deviceInfo")?.let {
            DeviceJsonUtils.fromJson(it)
        }
    }

    private val channelType by lazy {
        intent.getStringExtra("channelType") ?: "single"
    }

    private val selectedChannels by lazy {
        intent.getIntArrayExtra("selectedChannels")?.toList() ?: emptyList()
    }

    private val isMulti by lazy { "multi" == channelType }

    private val currentChannelId: Int
        get() = if (isMulti) selectedChannels.firstOrNull() ?: 0 else 0

    private val deviceManager: TXIoTDeviceManager? by lazy {
        TXIoTEngine.getInstance(this).deviceManager
    }

    private val mediaSession: TXIoTMonitorSession? by lazy {
        TXIoTEngine.getInstance(this).monitorSession
    }
    private var isSessionStarted = false
    private var isOpenTalk = false

    private val recordingChannels = mutableSetOf<Int>()
    private val isRecording get() = recordingChannels.isNotEmpty()
    private var recordDurationMs = 0L
    private val recordHandler = Handler(Looper.getMainLooper())
    private val recordTickRunnable = object : Runnable {
        override fun run() {
            recordDurationMs += 1000
            updateRecordDurationUI()
            recordHandler.postDelayed(this, 1000)
        }
    }
    private var isMuted = false
    private var isFirstSession = true
    private var isFullscreen = false
    private var isStreamFailed = false

    private var multiChannelAdapter: MultiChannelAdapter? = null

    override fun getViewBinding(): IotActivityDeviceDetailBinding =
        IotActivityDeviceDetailBinding.inflate(layoutInflater)

    override fun performInitView() {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }

    override fun initView() {
        setImmersiveStatusBar()
        with(binding) {
            iotTvDeviceName.text =
                deviceInfo?.aliasName ?: deviceInfo?.deviceId?.deviceName
            iotTvChannelInfo.text =
                if (isMulti) getString(
                    R.string.iot_detail_multi_channel,
                    selectedChannels.size
                ) else getString(R.string.iot_detail_single_channel)

            iotTvStreamError.setOnClickListener {
                if (isStreamFailed) {
                    if (isMulti) retryMultiStream() else retryStream()
                }
            }
            if (isMulti) {
                iotSingleChannelLayout.visibility = View.GONE
                iotMultiChannelRecyclerView.visibility = View.VISIBLE
                val adapter = MultiChannelAdapter(selectedChannels)
                multiChannelAdapter = adapter
                iotMultiChannelRecyclerView.layoutManager =
                    GridLayoutManager(this@DeviceDetailActivity, 2)
                iotMultiChannelRecyclerView.adapter = adapter
                iotMultiChannelRecyclerView.isNestedScrollingEnabled = false
                iotMultiChannelRecyclerView.overScrollMode = View.OVER_SCROLL_NEVER
                iotMultiStreamErrorOverlay.setOnClickListener {
                    if (isStreamFailed) retryMultiStream()
                }
            } else {
                iotSingleChannelLayout.visibility = View.VISIBLE
                iotMultiChannelRecyclerView.visibility = View.GONE
                iotMultiStreamErrorOverlay.visibility = View.GONE
                iotLoadingOverlay.setOnClickListener {
                    if (isStreamFailed) retryStream()
                }
            }
        }

        fetchDeviceProperties()
        startMediaSession()
    }

    private fun startMediaSession() {
        val deviceId = deviceInfo?.deviceId ?: return
        mediaSession?.addListener(mediaSessionListener)
        startRemoteViews()
        isSessionStarted = true

        if (isFirstSession) {
            isFirstSession = false
            isMuted = true
        }
        mediaSession?.muteAllRemoteAudio(isMuted)
        mediaSession?.startSession(deviceId)
        binding.iotBtnSound.setImageResource(
            if (isMuted) R.drawable.iot_ic_sound_off else R.drawable.iot_ic_sound_on
        )
        L.e("[$TAG] Media session started, deviceId=${deviceId.productId}_${deviceId.deviceName}")
    }

    private val mediaSessionListener = object : TXIoTMonitorSessionListener {
        override fun onSessionEstablished() = runOnUiThread { handleSessionEstablished() }
        override fun onSessionReconnecting() = runOnUiThread { handleSessionReconnecting() }
        override fun onSessionRecovery() = runOnUiThread {
            L.e("[$TAG] Session recovered successfully"); show(getString(R.string.iot_detail_connection_recovered))
        }

        override fun onRemoteStreamAvailable(channelId: Int, available: Boolean) = runOnUiThread {
            L.e("[$TAG] Channel[$channelId] stream availability changed: $available")
        }

        override fun onRenderFirstFrame(channelId: Int) = runOnUiThread {
            handleFirstFrame(channelId)
        }

        override fun onPlayStateChanged(channelId: Int, state: TXIoTPlayState) = runOnUiThread {
            handlePlayState(channelId, state)
        }

        override fun onSnapshotComplete(
            channelId: Int, image: Bitmap?, errorCode: TXIoTErrorCode
        ) = runOnUiThread { handleSnapshotComplete(channelId, image, errorCode) }

        override fun onLocalRecordBegin(
            channelId: Int, errorCode: TXIoTErrorCode, storagePath: String
        ) = runOnUiThread { handleLocalRecordBegin(channelId, errorCode, storagePath) }

        override fun onLocalRecording(channelId: Int, durationMs: Long, storagePath: String) {
            L.e("[$TAG] Channel[$channelId] recording, duration: ${durationMs / 1000}s")
        }

        override fun onLocalRecordComplete(
            channelId: Int, errorCode: TXIoTErrorCode, storagePath: String
        ) = runOnUiThread { handleLocalRecordComplete(channelId, errorCode, storagePath) }

        override fun onError(
            channelId: Int, errorCode: TXIoTErrorCode, errorMessage: String
        ) = runOnUiThread { handleError(channelId, errorCode, errorMessage) }
    }

    private fun handleSessionEstablished() {
        L.e("[$TAG] Session established successfully")
        show(getString(R.string.iot_detail_connected))
        isStreamFailed = false
        startRemoteViews()
        binding.iotBtnSound.setImageResource(
            if (isMuted) R.drawable.iot_ic_sound_off else R.drawable.iot_ic_sound_on
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun handleSessionReconnecting() {
        L.e("[$TAG] Session reconnecting...")
        show(getString(R.string.iot_detail_reconnecting))
        if (!isMulti && !isStreamFailed) showLoadingUI()
    }

    private fun handleFirstFrame(channelId: Int) {
        L.e("[$TAG] Channel[$channelId] first frame rendered")
        isStreamFailed = false
        if (isMulti) {
            multiChannelAdapter?.onFirstFrame(channelId)
        } else {
            binding.iotLoadingOverlay.isVisible = false
        }
    }

    private fun handlePlayState(channelId: Int, state: TXIoTPlayState) {
        L.e("[$TAG] Channel[$channelId] play state changed: $state")
        val loading = state != TXIoTPlayState.PLAYING
        if (isMulti) {
            multiChannelAdapter?.onPlayStateChanged(channelId, loading)
        } else {
            if (!isStreamFailed) {
                with(binding) {
                    iotLoadingProgressBar.isVisible = loading
                    iotLoadingOverlay.isVisible = loading
                }
            }
        }
    }

    private fun handleSnapshotComplete(
        channelId: Int, image: Bitmap?, errorCode: TXIoTErrorCode
    ) {
        if (errorCode != TXIoTErrorCode.ERR_SUCCESS || image == null) {
            L.e("[$TAG] Channel[$channelId] snapshot failed: $errorCode")
            show(getString(R.string.iot_detail_channel_snapshot_failed, channelId + 1))
            return
        }
        L.e("[$TAG] Channel[$channelId] snapshot success, size: ${image.width}x${image.height}")
        val saved = Utils.saveImageToGallery(this, image)
        show(
            if (saved) getString(
                R.string.iot_detail_channel_snapshot_saved,
                channelId + 1
            ) else getString(R.string.iot_detail_channel_snapshot_save_failed, channelId + 1)
        )
    }

    private fun handleLocalRecordBegin(
        channelId: Int, errorCode: TXIoTErrorCode, storagePath: String
    ) {
        if (errorCode != TXIoTErrorCode.ERR_SUCCESS) {
            L.e("[$TAG] Channel[$channelId] recording start failed: $errorCode")
            show(getString(R.string.iot_detail_channel_record_start_failed, channelId + 1))
            return
        }
        val wasRecording = isRecording
        recordingChannels.add(channelId)
        if (!wasRecording) {
            applyRecordingUi(true)
            recordDurationMs = 0L
            showRecordDuration()
            updateRecordDurationUI()
            recordHandler.postDelayed(recordTickRunnable, 1000)
        }
        L.e("[$TAG] Channel[$channelId] recording started, path: $storagePath")
        show(getString(R.string.iot_detail_channel_record_started, channelId + 1))
    }

    private fun handleLocalRecordComplete(
        channelId: Int, errorCode: TXIoTErrorCode, storagePath: String
    ) {
        val success = errorCode == TXIoTErrorCode.ERR_SUCCESS
        L.e("[$TAG] Channel[$channelId] recording ${if (success) "completed" else "failed"}: ${if (success) storagePath else errorCode}")
        recordingChannels.remove(channelId)
        if (recordingChannels.isEmpty()) {
            applyRecordingUi(false)
            stopRecordTimer()
        }
        if (success) {
            Utils.saveVideoToGallery(this, storagePath)
            show(getString(R.string.iot_detail_channel_record_saved, channelId + 1))
        } else {
            show(getString(R.string.iot_detail_channel_record_failed, channelId + 1))
        }
    }

    private fun handleError(channelId: Int, errorCode: TXIoTErrorCode, errorMessage: String) {
        if (errorCode in NON_FATAL_ERROR_CODES) {
            L.e("[$TAG] Channel[$channelId] non-fatal error: $errorCode - $errorMessage")
            show(errorMessage)
            if (isOpenTalk) {
                isOpenTalk = false
                applyTalkUi(false)
            }
            return
        }
        L.e("[$TAG] Channel[$channelId] unrecoverable error: $errorCode - $errorMessage")
        if (errorCode == TXIoTErrorCode.ERR_DEVICE_SWITCH_TO_VOIP) {
            show(getString(R.string.iot_detail_device_voip_mode))
        } else {
            show(getString(R.string.iot_detail_stream_failed, errorMessage))
        }

        isStreamFailed = true
        stopAllRemoteViews()
        mediaSession?.stopSession()
        binding.iotTvStreamError.isVisible = true
        if (isMulti) {
            multiChannelAdapter?.hideAllLoading()
            binding.iotMultiStreamErrorOverlay.isVisible = true
        }
    }

    private fun applyRecordingUi(active: Boolean) {
        with(binding) {
            iotBtnRecord.setImageResource(
                if (active) R.drawable.iot_ic_record_stop else R.drawable.iot_ic_record
            )
            iotBtnRecord.setColorFilter(
                if (active) Color.RED else Color.parseColor(COLOR_PRIMARY)
            )
            iotTvRecordLabel.text =
                if (active) getString(R.string.iot_detail_recording_active) else getString(R.string.iot_detail_recording_idle)
            iotTvRecordLabel.setTextColor(
                if (active) Color.RED else Color.parseColor(COLOR_LABEL_NORMAL)
            )
        }
    }

    private val activeChannelIds: List<Int>
        get() = if (isMulti) selectedChannels else listOf(0)

    private fun stopAllRemoteViews() {
        activeChannelIds.forEach { mediaSession?.stopRemoteView(it) }
        if (!isMulti) {
            if (isStreamFailed) showStreamErrorUI() else showLoadingUI()
        }
    }

    private fun startRemoteViews() {
        if (isMulti) {
            binding.iotMultiChannelRecyclerView.post {
                activeChannelIds.forEach { startRemoteView(it) }
            }
        } else {
            activeChannelIds.forEach { startRemoteView(it) }
        }
    }

    private fun startRemoteView(channelId: Int) {
        val view: TXCloudVideoView? = if (isMulti) {
            multiChannelAdapter?.getVideoView(channelId)
        } else {
            binding.iotTrtcRemoteCloudView
        }
        view?.let {
            val streamType = if (isHighQuality) TXIoTStreamType.HD else TXIoTStreamType.SD
            mediaSession?.startRemoteView(channelId, streamType, it)
            L.e("[$TAG] Channel[$channelId] start rendering, quality=${if (isHighQuality) "HD" else "SD"}")
        }
    }

    private fun showStreamErrorUI() {
        with(binding) {
            iotLoadingProgressBar.isVisible = false
            iotTvStreamError.isVisible = true
            iotLoadingOverlay.isVisible = true
        }
    }

    private fun showLoadingUI() {
        with(binding) {
            iotLoadingProgressBar.isVisible = true
            iotTvStreamError.isVisible = false
            iotLoadingOverlay.isVisible = true
        }
    }

    private fun retryStream() {
        L.e("[$TAG] User clicked retry stream")
        isStreamFailed = false
        showLoadingUI()
        val deviceId = deviceInfo?.deviceId ?: return
        startRemoteViews()
        mediaSession?.muteAllRemoteAudio(isMuted)
        mediaSession?.startSession(deviceId)
    }

    private fun retryMultiStream() {
        L.e("[$TAG] User clicked retry multi-channel stream")
        isStreamFailed = false
        binding.iotTvStreamError.isVisible = false
        binding.iotMultiStreamErrorOverlay.isVisible = false
        multiChannelAdapter?.showAllLoading()
        val deviceId = deviceInfo?.deviceId ?: return
        startRemoteViews()
        mediaSession?.muteAllRemoteAudio(isMuted)
        mediaSession?.startSession(deviceId)
    }

    private fun toggleFullscreen() {
        isFullscreen = !isFullscreen
        requestedOrientation = if (isFullscreen) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        window.decorView.systemUiVisibility = if (isFullscreen) {
            (View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        } else {
            (View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        }
        binding.iotBtnFullscreen.setImageResource(
            if (isFullscreen) R.drawable.iot_ic_fullscreen_exit else R.drawable.iot_ic_fullscreen
        )
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        applyOrientationLayout(newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE)
    }

    private fun applyOrientationLayout(landscape: Boolean) {
        val iotVideoContainer = binding.iotVideoContainer
        iotVideoContainer.layoutParams = iotVideoContainer.layoutParams.apply {
            height = if (landscape) ViewGroup.LayoutParams.MATCH_PARENT else dp2px(240)
        }
        val visibility = if (landscape) View.GONE else View.VISIBLE
        with(binding) {
            iotTopBar.visibility = visibility
            iotLinearLayout2.visibility = visibility
            iotActionButtonsRow.visibility = visibility
            iotPtzPanel.visibility = visibility
        }
        if (!landscape) setImmersiveStatusBar()
    }

    private fun toggleMute() {
        isMuted = !isMuted
        mediaSession?.muteAllRemoteAudio(isMuted)
        binding.iotBtnSound.setImageResource(
            if (isMuted) R.drawable.iot_ic_sound_off
            else R.drawable.iot_ic_sound_on
        )
        show(if (isMuted) getString(R.string.iot_detail_muted) else getString(R.string.iot_detail_unmuted))
    }

    private var isHighQuality = true

    private fun toggleQuality() {
        isHighQuality = !isHighQuality
        val streamType = if (isHighQuality) TXIoTStreamType.HD else TXIoTStreamType.SD
        activeChannelIds.forEach { mediaSession?.switchRemoteStream(it, streamType) }
        binding.iotBtnQuality.text =
            if (isHighQuality) getString(R.string.iot_detail_quality_hd) else getString(R.string.iot_detail_quality_sd)
        show(if (isHighQuality) getString(R.string.iot_detail_switched_hd) else getString(R.string.iot_detail_switched_sd))
    }

    private fun takeSnapshot() {
        activeChannelIds.forEach { mediaSession?.takeSnapshot(it) }
    }

    private fun toggleRecording() {
        if (isRecording) {
            activeChannelIds.forEach { mediaSession?.stopLocalRecording(it) }
            return
        }
        activeChannelIds.forEach { channelId ->
            val params = TXIoTLocalRecordingParams().apply {
                filePath = getExternalFilesDir(Environment.DIRECTORY_MOVIES)
                    ?.absolutePath + "/record_ch${channelId}_${System.currentTimeMillis()}.mp4"
            }
            mediaSession?.startLocalRecording(channelId, params)
        }
    }

    private fun toggleTalk() {
        isOpenTalk = !isOpenTalk
        if (isOpenTalk) mediaSession?.startLocalAudio() else mediaSession?.stopLocalAudio()
        applyTalkUi(isOpenTalk)
        show(if (isOpenTalk) getString(R.string.iot_detail_talk_on) else getString(R.string.iot_detail_talk_off))
    }

    private fun applyTalkUi(active: Boolean) {
        with(binding) {
            iotBtnTalk.setImageResource(
                if (active) R.drawable.iot_ic_talk_active else R.drawable.iot_ic_talk
            )
            iotBtnTalk.setColorFilter(
                if (active) Color.RED else Color.parseColor(COLOR_PRIMARY)
            )
            iotTvTalkLabel.text =
                if (active) getString(R.string.iot_detail_talk_active) else getString(R.string.iot_detail_talk_idle)
            iotTvTalkLabel.setTextColor(
                if (active) Color.RED else Color.parseColor(COLOR_LABEL_NORMAL)
            )
        }
    }

    private fun updateRecordDurationUI() {
        val totalSec = recordDurationMs / 1000
        val min = totalSec / 60
        val sec = totalSec % 60
        binding.iotTvRecordDuration.text = "● REC %02d:%02d".format(min, sec)
    }

    private fun showRecordDuration() {
        binding.iotTvRecordDuration.visibility = View.VISIBLE
    }

    private fun stopRecordTimer() {
        recordHandler.removeCallbacks(recordTickRunnable)
        binding.iotTvRecordDuration.visibility = View.GONE
        recordDurationMs = 0L
    }

    private fun createDeviceSharingToken() {
        val deviceId = deviceInfo?.deviceId
            ?: run { show(getString(R.string.iot_detail_device_info_incomplete)); return }
        val familyId = deviceInfo?.familyId
            ?: run { show(getString(R.string.iot_detail_device_info_incomplete)); return }
        val dm =
            deviceManager ?: run { show(getString(R.string.iot_detail_dev_mgr_unavailable)); return }
        dm.createDeviceSharingToken(familyId, deviceId, sharingTokenCallback(deviceId))
    }

    private fun sharingTokenCallback(deviceId: TXIoTEngineDef.TXIoTDeviceId): TXIoTCallback<String> =
        object : TXIoTCallback<String> {
            override fun onSuccess(result: String) {
                runOnUiThread { showSharingTokenSheet(deviceId, result) }
            }

            override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
                runOnUiThread { show(getString(R.string.iot_detail_share_token_failed, errorMessage)) }
            }
        }

    private fun showSharingTokenSheet(deviceId: TXIoTEngineDef.TXIoTDeviceId, token: String) {
        val shareJson = org.json.JSONObject().apply {
            put("productId", deviceId.productId ?: "")
            put("deviceName", deviceId.deviceName ?: "")
            put("token", token)
        }.toString(2)

        val editText = makeShareTokenEditText(shareJson)
        val sheet = CommonBottomSheet(this).apply {
            setTitle(getString(R.string.iot_detail_share_token_title))
            setHint(null)
            setDividerVisible(false)
            setContent(editText)
            setConfirmDismiss(getString(R.string.iot_detail_copy_share_token)) {
                val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                clipboard.setPrimaryClip(ClipData.newPlainText("share_token", shareJson))
                show(getString(R.string.iot_detail_share_token_copied))
            }
        }
        sheet.show()
    }

    private fun makeShareTokenEditText(text: String): EditText = EditText(this).apply {
        setText(text)
        isFocusable = false
        isFocusableInTouchMode = false
        setTextIsSelectable(true)
        setBackgroundResource(R.drawable.iot_bg_dialog_input)
        setPadding(36, 24, 36, 24)
        gravity = android.view.Gravity.TOP
        setTextColor(Color.parseColor("#15161A"))
        this.textSize = 15f
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            (140 * resources.displayMetrics.density).toInt()
        )
    }

    private fun sendPTZ(command: TXIoTPTZCommand) {
        L.e(TAG, "sendPTZ: $command")
        mediaSession?.sendPTZCommand(currentChannelId, command, 5)
    }

    private inline fun <T> uiCallback(
        crossinline onOk: (T) -> Unit = {},
        crossinline onErr: (TXIoTErrorCode, String) -> Unit = { _, msg -> show("$msg") }
    ): TXIoTCallback<T> = object : TXIoTCallback<T> {
        override fun onSuccess(result: T) {
            runOnUiThread { onOk(result) }
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
            runOnUiThread { onErr(errorCode, errorMessage) }
        }
    }

    private fun logCallback(
        onOk: (String) -> Unit
    ): TXIoTCallback<String> = object : TXIoTCallback<String> {
        override fun onSuccess(result: String) {
            runOnUiThread { onOk(result) }
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {
            runOnUiThread { L.e("$errorMessage") }
        }
    }

    private fun fetchDeviceProperties() {
        val deviceId = deviceInfo?.deviceId ?: return
        val dm = deviceManager ?: return
        dm.getProperties(deviceId, logCallback { result -> L.e("Device properties: $result") })
    }

    private fun sendCommandToDevice(jsonData: String) {
        val deviceId = deviceInfo?.deviceId ?: return
        val dm = deviceManager ?: return
        dm.sendCommand(
            deviceId, jsonData,
            uiCallback(
                onOk = { show(getString(R.string.iot_detail_command_sent)) },
                onErr = { _, msg -> show(getString(R.string.iot_detail_command_send_failed, msg)) }
            )
        )
    }

    override fun setListener() {
        with(binding) {
            iotBtnBack.setOnClickListener { finish() }
            iotBtnSound.setOnClickListener { toggleMute() }
            iotBtnQuality.setOnClickListener { toggleQuality() }
            iotBtnFullscreen.setOnClickListener { toggleFullscreen() }
            iotBtnTalk.setOnClickListener { toggleTalk() }
            iotBtnSnapshot.setOnClickListener { takeSnapshot() }
            iotBtnRecord.setOnClickListener { toggleRecording() }
            iotBtnShareDevice.setOnClickListener { createDeviceSharingToken() }
            mapOf(
                iotBtnPTZUp to TXIoTPTZCommand.UP,
                iotBtnPTZDown to TXIoTPTZCommand.DOWN,
                iotBtnPTZLeft to TXIoTPTZCommand.LEFT,
                iotBtnPTZRight to TXIoTPTZCommand.RIGHT,
            ).forEach { (btn, cmd) -> btn.setOnClickListener { sendPTZ(cmd) } }
            iotBtnPTZCenter.setOnClickListener { sendCommandToDevice("{\"cmd\":\"center\"}") }
        }
    }

    override fun onPause() {
        super.onPause()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (!isSessionStarted) return
        stopTalkAndRecording()
        mediaSession?.stopSession()
        L.e("[$TAG] App went to background, stopping session")
    }

    override fun onResume() {
        super.onResume()
        if (!isSessionStarted) return
        val deviceId = deviceInfo?.deviceId ?: return
        if (isStreamFailed) {
            L.e("[$TAG] App returned to foreground, but stream failed, waiting for user to retry")
            return
        }
        startRemoteViews()
        mediaSession?.muteAllRemoteAudio(isMuted)
        mediaSession?.startSession(deviceId)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        L.e("[$TAG] App returned to foreground, restarting session")
    }

    override fun onDestroy() {
        super.onDestroy()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        releaseTalkAndRecording()
        stopRecordTimer()
        stopAllRemoteViews()
        if (isSessionStarted) {
            mediaSession?.stopSession()
            mediaSession?.removeListener(mediaSessionListener)
        }
        L.e("[$TAG] Media session destroyed")
    }

    private fun stopTalkAndRecording() {
        if (isOpenTalk) {
            mediaSession?.stopLocalAudio()
            isOpenTalk = false
            applyTalkUi(false)
            L.e("[$TAG] App went to background, stopping talk")
        }
        if (isRecording) {
            activeChannelIds.forEach { mediaSession?.stopLocalRecording(it) }
            recordingChannels.clear()
            applyRecordingUi(false)
            stopRecordTimer()
            L.e("[$TAG] App went to background, stopping recording")
        }
    }

    private fun releaseTalkAndRecording() {
        if (isOpenTalk) mediaSession?.stopLocalAudio()
        if (isRecording) activeChannelIds.forEach { mediaSession?.stopLocalRecording(it) }
    }
}
