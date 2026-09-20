package com.tencent.iot.txiotdemo.activity

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.SurfaceTexture
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.isVisible
import androidx.recyclerview.widget.LinearLayoutManager
import com.bumptech.glide.Glide
import com.tencent.iot.txiotdemo.R
import com.tencent.iot.txiotdemo.adapter.CloudStorageEventAdapter
import com.tencent.iot.txiotdemo.common.PopupMenuHelper
import com.tencent.iot.txiotdemo.common.log.L
import com.tencent.iot.txiotdemo.databinding.IotActivityCloudStorageBinding
import com.tencent.liteav.iot.TXIoTCloudStorage
import com.tencent.liteav.iot.TXIoTCloudStorage.TXIoTEvent
import com.tencent.liteav.iot.TXIoTCloudStorage.TXIoTVideoFile
import com.tencent.liteav.iot.TXIoTDeviceManager
import com.tencent.liteav.iot.TXIoTEngine
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTCallback
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceId
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTDeviceInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTErrorCode
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTFamilyInfo
import com.tencent.liteav.iot.TXIoTEngineDef.TXIoTPageResult
import com.tencent.rtmp.ITXVodPlayListener
import com.tencent.rtmp.TXLiveBase
import com.tencent.rtmp.TXLiveConstants
import com.tencent.rtmp.TXPlayInfoParams
import com.tencent.rtmp.TXVodPlayConfig
import com.tencent.rtmp.TXVodPlayer
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class CloudStorageActivity : BaseActivity<IotActivityCloudStorageBinding>() {

    companion object {
        private const val TAG = "CloudStorageActivity"
        private const val EXTRA_PRODUCT_ID = "extra_product_id"
        private const val EXTRA_DEVICE_NAME = "extra_device_name"

        private const val PROGRESS_INTERVAL_MS = 500L

        private const val FULLSCREEN_AUTO_HIDE_DELAY_MS = 5000L
        private const val PLAY_PAUSE_AUTO_HIDE_DELAY_MS = 3000L

        private const val COLOR_TEXT_SELECTED_PRIMARY = "#FFFFFF"
        private const val COLOR_TEXT_SELECTED_SECONDARY = "#CCFFFFFF"
        private const val COLOR_TEXT_NORMAL_PRIMARY = "#15161A"
        private const val COLOR_TEXT_NORMAL_SECONDARY = "#9DA3B0"

        private const val DEFAULT_CHANNEL_ID = 0

        private const val CHANNEL_COUNT = 4

        private const val TIMELINE_SCROLL_IDLE_MS = 150L

        private const val BASE_TIMELINE_HOURS_ON_SCREEN = 1.5f

        private const val FALLBACK_BASE_HOUR_WIDTH_DP = 240f

        // 前往腾讯云点播播放器页面购买：https://cloud.tencent.com/document/product/881/74588
        // 如果不打算使用腾讯云点播播放器，可以将以下两个常量设置为空字符串
        private const val LICENSE_URL = 
        private const val LICENSE_KEY = 

        fun start(context: Context, deviceId: TXIoTDeviceId) {
            val intent = Intent(context, CloudStorageActivity::class.java).apply {
                putExtra(EXTRA_PRODUCT_ID, deviceId.productId)
                putExtra(EXTRA_DEVICE_NAME, deviceId.deviceName)
            }
            context.startActivity(intent)
        }
    }

    private val deviceId: TXIoTDeviceId? by lazy {
        val pid = intent.getStringExtra(EXTRA_PRODUCT_ID)
        val dn = intent.getStringExtra(EXTRA_DEVICE_NAME)
        if (pid.isNullOrEmpty() || dn.isNullOrEmpty()) return@lazy null
        TXIoTDeviceId().apply {
            productId = pid
            deviceName = dn
        }
    }

    private val cloudStorage by lazy {
        deviceId?.let { TXIoTEngine.getInstance(this).getCloudStorage(it) }
    }

    private var selectedDate: String = ""

    private var currentChannelId: Int = DEFAULT_CHANNEL_ID

    private val dateChipMap = linkedMapOf<String, View>()

    private val eventList = mutableListOf<TXIoTEvent>()

    private val allEventsForTimeline = mutableListOf<TXIoTEvent>()
    private lateinit var eventAdapter: CloudStorageEventAdapter

    private val isoDateFormatter = SimpleDateFormat("yyyy-MM-dd", Locale.CHINA)
    private val dayFormatter = SimpleDateFormat("dd", Locale.CHINA)
    private val monthFormatter by lazy {
        SimpleDateFormat(getString(R.string.iot_cloud_month_pattern), Locale.CHINA)
    }
    private val timeFormatter = SimpleDateFormat("HH:mm:ss", Locale.CHINA)

    private var isFullscreen: Boolean = false
    private var isMuted: Boolean = true
    private var originalVideoLayoutParams: ViewGroup.LayoutParams? = null

    private var timelineOriginalParent: ViewGroup? = null
    private var timelineOriginalIndex: Int = -1
    private var timelineOriginalLayoutParams: LinearLayout.LayoutParams? = null

    private val autoHideHandler = Handler(Looper.getMainLooper())
    private val autoHideRunnable = Runnable { setFullscreenControlsVisible(false) }
    private var fullscreenControlsVisible: Boolean = true

    private var isPlaybackPaused: Boolean = false
    private val playPauseHideHandler = Handler(Looper.getMainLooper())
    private val playPauseHideRunnable = Runnable { binding.iotBtnPlayPause.isVisible = false }

    private var vodPlayer: TXVodPlayer? = null
    private var isPlayerStarted: Boolean = false

    private var isSegmentPrepared: Boolean = false

    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    private val progressHandler = Handler(Looper.getMainLooper())
    private val progressRunnable = object : Runnable {
        override fun run() {
            updatePlayProgressFromPlayer()
            progressHandler.postDelayed(this, PROGRESS_INTERVAL_MS)
        }
    }

    private var isUserScrollingTimeline: Boolean = false
    private var isTimelinePositionedByUser: Boolean = false
    private var pinnedCenterTimeMs: Long? = null

    private val timelineScrollIdleRunnable = Runnable { onTimelineScrollIdle() }

    private val baseHourWidthDp: Float
        get() {
            val widthPx = binding.iotTimelineScroll.width
            if (widthPx <= 0) return FALLBACK_BASE_HOUR_WIDTH_DP
            return widthPx / resources.displayMetrics.density / BASE_TIMELINE_HOURS_ON_SCREEN
        }

    private var currentSession: PlaybackSession? = null

    private var lastSession: PlaybackSession? = null

    private var currentFileDurationMs: Long = 0L

    override fun getViewBinding(): IotActivityCloudStorageBinding =
        IotActivityCloudStorageBinding.inflate(layoutInflater)

    override fun initView() {
        setImmersiveStatusBar()
        TXLiveBase.getInstance().setLicence(this, LICENSE_URL, LICENSE_KEY)

        if (deviceId == null) {
            show(getString(R.string.iot_cloud_device_info_invalid))
            finish()
            return
        }

        bindDeviceInfo()
        setupRecyclerView()
        setupVideoView()
        setupTimelineView()
        loadDayList()
    }

    override fun setListener() {
        binding.iotBtnBack.setOnClickListener {
            if (isFullscreen) exitFullscreen() else finish()
        }
        binding.iotBtnRefresh.setOnClickListener {
            loadDayList()
        }
        binding.iotBtnFullscreen.setOnClickListener {
            toggleFullscreen()
            if (isFullscreen) scheduleAutoHide()
        }
        binding.iotBtnMute.setOnClickListener {
            toggleMute()
            if (isFullscreen) scheduleAutoHide()
        }
        binding.iotBtnChannel.setOnClickListener { showChannelMenu(it) }
        binding.iotBtnSnapshotClose.setOnClickListener { hideSnapshotPreview() }
        binding.iotSnapshotPreviewLayer.setOnClickListener { }
        binding.iotBtnPlayPause.setOnClickListener {
            togglePlayPause()
            if (isFullscreen) scheduleAutoHide()
        }
        binding.iotBtnReplay.setOnClickListener { replayLastSession() }
        binding.iotVideoContainer.setOnClickListener {
            if (!isFullscreen) {
                if (binding.iotBtnPlayPause.isVisible) hidePlayPauseButton() else showPlayPauseButtonWithAutoHide()
                return@setOnClickListener
            }
            fullscreenControlsVisible = !fullscreenControlsVisible
            setFullscreenControlsVisible(fullscreenControlsVisible)
            if (fullscreenControlsVisible) scheduleAutoHide()
        }
        updateChannelButtonText()
    }

    private fun showChannelMenu(anchor: View) {
        PopupMenuHelper.show(
            this, anchor, listOf(
                PopupMenuHelper.Item(label = getString(R.string.iot_cloud_no_channel)) {
                    onChannelSelected(
                        0
                    )
                },
                PopupMenuHelper.Item(
                    label = getString(
                        R.string.iot_cloud_channel_n,
                        1
                    )
                ) { onChannelSelected(1) },
                PopupMenuHelper.Item(
                    label = getString(
                        R.string.iot_cloud_channel_n,
                        2
                    )
                ) { onChannelSelected(2) },
                PopupMenuHelper.Item(
                    label = getString(
                        R.string.iot_cloud_channel_n,
                        3
                    )
                ) { onChannelSelected(3) },
            )
        )
    }

    private fun onChannelSelected(channelId: Int) {
        if (channelId == currentChannelId) return
        if (channelId !in 0 until CHANNEL_COUNT) return
        currentChannelId = channelId
        updateChannelButtonText()
        resetForChannelSwitch()
        loadDayList()
    }

    private fun updateChannelButtonText() {
        binding.iotBtnChannel.text =
            if (currentChannelId == 0) getString(R.string.iot_cloud_no_channel) else getString(
                R.string.iot_cloud_channel_n,
                currentChannelId
            )
    }

    private fun resetForChannelSwitch() {
        vodPlayer?.let { stopCurrentPlayback(it) }
        binding.iotVideoLoading.isVisible = false
        hideReplayOverlay()
        lastSession = null
        if (isFullscreen) exitFullscreen()

        selectedDate = ""
        dateChipMap.clear()
        binding.iotLlDateList.removeAllViews()
        eventList.clear()
        allEventsForTimeline.clear()
        eventAdapter.notifyDataSetChanged()
        binding.iotTimelineView.setVideoFiles(emptyList())
        binding.iotTvTimelineTip.isVisible = false
        binding.iotTimelineCenterGroup.isVisible = false
        binding.iotEmptyView.isVisible = false

        binding.iotTimelineView.hourWidthDp = baseHourWidthDp
    }

    private fun setupTimelineView() {
        binding.iotTimelineView.onSegmentClickListener = { videoFile, tappedTimeMs ->
            playVideoFile(videoFile, tappedTimeMs)
        }
        binding.iotTimelineScroll.post {
            binding.iotTimelineView.sidePaddingPx = binding.iotTimelineScroll.width / 2f
            binding.iotTimelineView.hourWidthDp = baseHourWidthDp
        }
        setupTimelineScrollInteraction()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun setupTimelineScrollInteraction() {
        binding.iotTimelineScroll.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> {

                    isUserScrollingTimeline = true
                    pinnedCenterTimeMs = null
                    binding.iotTimelineScroll.removeCallbacks(timelineScrollIdleRunnable)
                    if (isFullscreen) scheduleAutoHide()
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (isUserScrollingTimeline) {
                        binding.iotTimelineScroll.removeCallbacks(timelineScrollIdleRunnable)
                        binding.iotTimelineScroll.postDelayed(
                            timelineScrollIdleRunnable, TIMELINE_SCROLL_IDLE_MS
                        )
                    }
                }
            }
            false
        }
        binding.iotTimelineScroll.setOnScrollChangeListener { _, _, _, _, _ ->
            updateTimelineCenterTime()
            if (!isUserScrollingTimeline) return@setOnScrollChangeListener
            binding.iotTimelineScroll.removeCallbacks(timelineScrollIdleRunnable)
            binding.iotTimelineScroll.postDelayed(
                timelineScrollIdleRunnable, TIMELINE_SCROLL_IDLE_MS
            )
        }
    }

    private fun updateTimelineCenterTime() {
        if (isPlaybackTimeDriven()) return
        val pinned = pinnedCenterTimeMs
        if (pinned != null) {
            binding.iotTvTimelineCenterTime.text = timeFormatter.format(Date(pinned))
            return
        }
        val scrollX = binding.iotTimelineScroll.scrollX
        val centerTime =
            binding.iotTimelineView.timeAtCenter(scrollX, binding.iotTimelineScroll.width)
        binding.iotTvTimelineCenterTime.text = timeFormatter.format(Date(centerTime))
    }

    private fun isPlaybackTimeDriven(): Boolean =
        !isUserScrollingTimeline && isPlayerStarted && currentSession != null

    private fun onTimelineScrollIdle() {
        if (!isUserScrollingTimeline) return
        isUserScrollingTimeline = false
        pinnedCenterTimeMs = null
        isTimelinePositionedByUser = true
        val scrollX = binding.iotTimelineScroll.scrollX
        val centerTime =
            binding.iotTimelineView.timeAtCenter(scrollX, binding.iotTimelineScroll.width)
        binding.iotTvTimelineCenterTime.text = timeFormatter.format(Date(centerTime))

        val directFile = binding.iotTimelineView.videoFileAt(centerTime)
        if (directFile != null) {
            playVideoFile(directFile, centerTime)
            return
        }
        val nearest = binding.iotTimelineView.nearestVideoFileNear(centerTime)
        if (nearest != null) {
            val (file, playTime) = nearest
            playVideoFile(file, playTime)
        } else {
            show(getString(R.string.iot_cloud_no_recording_near))
        }
    }

    private fun bindDeviceInfo() {
        val did = deviceId ?: return
        binding.iotTextView.text = did.deviceName.orEmpty()
        binding.iotTvDeviceName.text = "${did.productId.orEmpty()}/${did.deviceName.orEmpty()}"
        updateOnlineStatus(false)
        queryDeviceStatus()
    }

    private fun queryDeviceStatus() {
        val did = deviceId ?: return
        val engine = TXIoTEngine.getInstance(this)
        val familyManager = engine.familyManager ?: return
        val deviceManager = engine.deviceManager ?: return

        familyManager.getFamilyList(createQueryStatusCallback(deviceManager, did))
    }

    private fun createQueryStatusCallback(
        deviceManager: TXIoTDeviceManager,
        did: TXIoTDeviceId
    ): TXIoTCallback<List<TXIoTFamilyInfo>> = object : TXIoTCallback<List<TXIoTFamilyInfo>> {
        override fun onSuccess(result: List<TXIoTFamilyInfo>) {
            result.forEach { family ->
                queryDeviceInFamily(deviceManager, family.familyId, did)
            }
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {}
    }

    private fun queryDeviceInFamily(
        deviceManager: TXIoTDeviceManager,
        familyId: String?,
        did: TXIoTDeviceId
    ) {
        deviceManager.getDeviceList(familyId, "", queryDeviceInFamilyCallback(did))
    }

    private fun queryDeviceInFamilyCallback(did: TXIoTDeviceId):
            TXIoTCallback<TXIoTPageResult<TXIoTDeviceInfo>> =
        object : TXIoTCallback<TXIoTPageResult<TXIoTDeviceInfo>> {
            override fun onSuccess(pageResult: TXIoTPageResult<TXIoTDeviceInfo>) {
                val online = isDeviceOnlineInPage(pageResult, did)
                runOnUiThread { updateOnlineStatus(online) }
            }

            override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) {}
        }

    private fun isDeviceOnlineInPage(
        pageResult: TXIoTPageResult<TXIoTDeviceInfo>,
        did: TXIoTDeviceId
    ): Boolean {
        val matched = pageResult.dataList?.firstOrNull {
            it.deviceId?.productId == did.productId &&
                    it.deviceId?.deviceName == did.deviceName
        }
        return matched?.status?.isOnline == true
    }

    private fun updateOnlineStatus(online: Boolean) {
        if (online) {
            binding.iotTvOnlineStatus.text = getString(R.string.iot_device_status_online)
            binding.iotStatusDot.setBackgroundResource(R.drawable.iot_bg_cloud_online_dot)
        } else {
            binding.iotTvOnlineStatus.text = getString(R.string.iot_device_status_offline)
            binding.iotStatusDot.setBackgroundResource(R.drawable.iot_bg_cloud_offline_dot)
        }
    }

    private fun setupRecyclerView() {
        eventAdapter = CloudStorageEventAdapter(
            data = eventList,
            onPlayEvent = { event -> playEvent(event) },
            onViewSnapshot = { event -> viewSnapshot(event) }
        )
        binding.iotRvEventList.apply {
            layoutManager = LinearLayoutManager(this@CloudStorageActivity)
            adapter = eventAdapter
        }
    }

    private fun setupVideoView() {
        binding.iotVideoView.surfaceTextureListener = textureListener
        val player = TXVodPlayer(this).apply {
            setConfig(TXVodPlayConfig().apply {
                isEnableAccurateSeek = true
                progressInterval = PROGRESS_INTERVAL_MS.toInt()
            })

            setRenderMode(TXLiveConstants.RENDER_MODE_FULL_FILL_SCREEN)
            setMute(true)
            setAutoPlay(true)
            setVodListener(vodListener)
        }
        vodPlayer = player
    }

    private val textureListener = object : TextureView.SurfaceTextureListener {
        override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
            vodPlayer?.setSurface(Surface(surface))
        }

        override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
            updateVideoAspect()
        }

        override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
            return true
        }

        override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {}
    }

    private val vodListener = object : ITXVodPlayListener {
        override fun onPlayEvent(player: TXVodPlayer, event: Int, param: Bundle) {
            when (event) {
                TXLiveConstants.PLAY_EVT_VOD_PLAY_PREPARED -> {
                    isSegmentPrepared = true
                }

                TXLiveConstants.PLAY_EVT_PLAY_BEGIN -> {
                    binding.iotVideoLoading.isVisible = false
                    progressHandler.removeCallbacks(progressRunnable)
                    progressHandler.postDelayed(progressRunnable, PROGRESS_INTERVAL_MS)
                    isPlaybackPaused = false
                    setKeepScreenOn(true)
                    showPlayPauseButtonWithAutoHide()
                }

                TXLiveConstants.PLAY_EVT_PLAY_LOADING ->
                    binding.iotVideoLoading.isVisible = true

                TXLiveConstants.PLAY_EVT_VOD_LOADING_END ->
                    binding.iotVideoLoading.isVisible = false

                TXLiveConstants.PLAY_EVT_CHANGE_RESOLUTION -> {
                    videoWidth = param.getInt(TXLiveConstants.EVT_PARAM1, 0)
                    videoHeight = param.getInt(TXLiveConstants.EVT_PARAM2, 0)
                    updateVideoAspect()
                }

                TXLiveConstants.PLAY_EVT_PLAY_END -> onSegmentPlayEnd()
                else -> {
                    if (event < 0) {
                        handlePlayError(event, 0)
                    }
                }
            }
        }

        override fun onNetStatus(player: TXVodPlayer, bundle: Bundle) {}
    }

    private fun updateVideoAspect() {
        if (videoWidth <= 0 || videoHeight <= 0) return
        val cw = binding.iotVideoContainer.width
        val ch = binding.iotVideoContainer.height
        if (cw <= 0 || ch <= 0) return
        val targetRatio = videoWidth.toFloat() / videoHeight
        val containerRatio = cw.toFloat() / ch
        val lp = binding.iotVideoView.layoutParams as FrameLayout.LayoutParams
        if (targetRatio > containerRatio) {
            lp.width = cw
            lp.height = (cw / targetRatio).toInt()
        } else {
            lp.width = (ch * targetRatio).toInt()
            lp.height = ch
        }
        lp.gravity = Gravity.CENTER
        binding.iotVideoView.layoutParams = lp
    }

    private fun onSegmentPlayEnd() {
        if (!isPlayerStarted) return
        val session = currentSession
        if (session == null) {
            finishPlaybackSession()
            return
        }
        if (session.advanceToNextValidSegment()) {
            startCurrentSegment(session, seekWallMs = null)
            return
        }
        finishPlaybackSession()
    }

    private fun onSessionDurationReached() {
        finishPlaybackSession()
    }

    private fun finishPlaybackSession() {
        L.e("[$TAG] Video playback finished")
        vodPlayer?.let { stopCurrentPlayback(it) }
        binding.iotVideoLoading.isVisible = false
        showReplayOverlay()
        currentSession = null
        currentFileDurationMs = 0L
    }

    private fun showReplayOverlay() {
        if (lastSession == null) return
        hidePlayPauseButton()
        binding.iotReplayOverlay.isVisible = true
    }

    private fun hideReplayOverlay() {
        binding.iotReplayOverlay.isVisible = false
    }

    private fun replayLastSession() {
        val session = lastSession ?: return
        session.resetToStart()
        startSession(session)
    }

    private fun handlePlayError(what: Int, extra: Int) {
        L.e("[$TAG] Video playback error what=$what extra=$extra")
        binding.iotVideoLoading.isVisible = false
        progressHandler.removeCallbacks(progressRunnable)
        hidePlayPauseButton()
        hideReplayOverlay()
        isPlaybackPaused = false
        setKeepScreenOn(false)
        show(getString(R.string.iot_cloud_play_failed))
        isPlayerStarted = false
        currentSession = null
        currentFileDurationMs = 0L
    }

    private fun updatePlayProgressFromPlayer() {
        val player = vodPlayer ?: return
        if (!isPlayerStarted) return
        val progressMs: Long = try {
            (player.currentPlaybackTime * 1000).toLong()
        } catch (_: Exception) {
            return
        }
        val durationMs: Long = try {
            (player.duration * 1000).toLong()
        } catch (_: Exception) {
            0L
        }
        if (durationMs > 0L) currentFileDurationMs = durationMs

        val session = currentSession ?: return
        val totalDuration = session.totalDurationMs
        if (totalDuration <= 0L) return
        val currentFile = session.currentFile() ?: return

        val wallMs = currentFile.startTimeMs + progressMs
        if (wallMs >= session.endWallMs) {
            onSessionDurationReached()
            return
        }

        if (!isUserScrollingTimeline) {
            pinnedCenterTimeMs = null
            binding.iotTvTimelineCenterTime.text = timeFormatter.format(Date(wallMs))
            centerTimelineAtTime(wallMs)
        }
    }

    private fun centerTimelineAtTime(timeMs: Long) {
        val targetX = binding.iotTimelineView.getXForTime(timeMs)
        val scrollTo = (targetX - binding.iotTimelineScroll.width / 2).coerceAtLeast(0)
        binding.iotTimelineScroll.scrollTo(scrollTo, 0)
    }

    private fun toggleFullscreen() {
        if (isFullscreen) exitFullscreen() else enterFullscreen()
    }

    private fun toggleMute() {
        isMuted = !isMuted
        vodPlayer?.setMute(isMuted)
        binding.iotBtnMute.setImageResource(
            if (isMuted) R.drawable.iot_ic_sound_off else R.drawable.iot_ic_sound_on
        )
    }

    private fun togglePlayPause() {
        val player = vodPlayer ?: return
        if (!isPlayerStarted) return
        if (isPlaybackPaused) {
            runSafely { player.resume() }
            isPlaybackPaused = false
            setKeepScreenOn(true)
            schedulePlayPauseAutoHide()
        } else {
            runSafely { player.pause() }
            isPlaybackPaused = true
            setKeepScreenOn(false)
            playPauseHideHandler.removeCallbacks(playPauseHideRunnable)
        }
        updatePlayPauseButtonIcon()
    }

    private fun updatePlayPauseButtonIcon() {
        binding.iotBtnPlayPause.setImageResource(
            if (isPlaybackPaused) R.drawable.iot_ic_video_play else R.drawable.iot_ic_video_pause
        )
    }

    private fun showPlayPauseButtonWithAutoHide() {
        if (!isPlayerStarted || currentSession == null) return
        binding.iotBtnPlayPause.isVisible = true
        updatePlayPauseButtonIcon()
        schedulePlayPauseAutoHide()
    }

    private fun schedulePlayPauseAutoHide() {
        playPauseHideHandler.removeCallbacks(playPauseHideRunnable)
        if (isFullscreen || isPlaybackPaused) return
        playPauseHideHandler.postDelayed(playPauseHideRunnable, PLAY_PAUSE_AUTO_HIDE_DELAY_MS)
    }

    private fun hidePlayPauseButton() {
        playPauseHideHandler.removeCallbacks(playPauseHideRunnable)
        binding.iotBtnPlayPause.isVisible = false
    }

    private fun updatePlayPauseVisibility(visible: Boolean) {
        binding.iotBtnPlayPause.isVisible = visible && isPlayerStarted && currentSession != null
        if (binding.iotBtnPlayPause.isVisible) updatePlayPauseButtonIcon()
    }

    private fun setKeepScreenOn(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun enterFullscreen() {
        if (isFullscreen) return
        isFullscreen = true
        if (originalVideoLayoutParams == null) {
            originalVideoLayoutParams = binding.iotVideoContainer.layoutParams
        }
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        setNonVideoUiVisible(false)
        binding.iotVideoContainer.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )

        reparentTimelineIntoVideoContainer()
        binding.iotBtnFullscreen.setImageResource(R.drawable.iot_ic_video_fullscreen_exit)
        binding.iotVideoContainer.post { updateVideoAspect() }
        refreshTimelineLayout()
        fullscreenControlsVisible = true
        playPauseHideHandler.removeCallbacks(playPauseHideRunnable)
        updatePlayPauseVisibility(true)
        scheduleAutoHide()
    }

    private fun exitFullscreen() {
        if (!isFullscreen) return
        isFullscreen = false
        autoHideHandler.removeCallbacks(autoHideRunnable)
        fullscreenControlsVisible = true
        setFullscreenControlsVisible(true)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        setNonVideoUiVisible(true)

        reparentTimelineBack()
        originalVideoLayoutParams?.let { binding.iotVideoContainer.layoutParams = it }
        binding.iotBtnFullscreen.setImageResource(R.drawable.iot_ic_video_fullscreen_enter)
        binding.iotVideoContainer.post { updateVideoAspect() }
        refreshTimelineLayout()
        schedulePlayPauseAutoHide()
    }

    private fun reparentTimelineIntoVideoContainer() {
        val tlParent = binding.iotTimelineContainer.parent as? ViewGroup ?: return
        if (timelineOriginalParent == null) {
            timelineOriginalParent = tlParent
            timelineOriginalIndex = tlParent.indexOfChild(binding.iotTimelineContainer)
            timelineOriginalLayoutParams =
                binding.iotTimelineContainer.layoutParams as? LinearLayout.LayoutParams
        }
        tlParent.removeView(binding.iotTimelineContainer)
        val flLp = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM
        )
        binding.iotVideoContainer.addView(binding.iotTimelineContainer, flLp)
        binding.iotTimelineContainer.setBackgroundColor(Color.parseColor("#B3000000"))
        binding.iotTimelineView.darkMode = true
        binding.iotTimelineContainer.isVisible = true
    }

    private fun reparentTimelineBack() {
        val parent = timelineOriginalParent
        val lp = timelineOriginalLayoutParams
        if (parent != null && lp != null) {
            (binding.iotTimelineContainer.parent as? ViewGroup)?.removeView(binding.iotTimelineContainer)
            val index = timelineOriginalIndex.coerceAtLeast(0)
            parent.addView(binding.iotTimelineContainer, index, lp)
        }
        binding.iotTimelineContainer.setBackgroundColor(Color.parseColor("#FFFFFF"))
        binding.iotTimelineView.darkMode = false
        timelineOriginalParent = null
        timelineOriginalIndex = -1
        timelineOriginalLayoutParams = null
    }

    private fun setFullscreenControlsVisible(visible: Boolean) {
        fullscreenControlsVisible = visible
        binding.iotPlayerFloatControls.isVisible = visible
        binding.iotTimelineContainer.isVisible = visible
        updatePlayPauseVisibility(visible)
    }

    private fun scheduleAutoHide() {
        autoHideHandler.removeCallbacks(autoHideRunnable)
        autoHideHandler.postDelayed(autoHideRunnable, FULLSCREEN_AUTO_HIDE_DELAY_MS)
    }

    private fun setNonVideoUiVisible(visible: Boolean) {
        binding.iotTopBar.isVisible = visible
        binding.iotDateScroll.isVisible = visible
        binding.iotEventListContainer.isVisible = visible
    }

    private fun refreshTimelineLayout() {
        binding.iotTimelineScroll.post {
            binding.iotTimelineView.sidePaddingPx = binding.iotTimelineScroll.width / 2f
            binding.iotTimelineView.hourWidthDp = baseHourWidthDp
            val player = vodPlayer
            val session = currentSession
            val file = session?.currentFile()
            if (player != null && file != null && isPlayerStarted) {
                val pos = try {
                    (player.currentPlaybackTime * 1000).toLong()
                } catch (_: Exception) {
                    0L
                }
                centerTimelineAtTime(file.startTimeMs + pos)
            }
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        when (newConfig.orientation) {
            Configuration.ORIENTATION_LANDSCAPE ->
                window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)

            Configuration.ORIENTATION_PORTRAIT ->
                window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
        }
    }

    override fun onBackPressed() {
        if (isFullscreen) {
            exitFullscreen()
            return
        }
        super.onBackPressed()
    }

    private fun loadDayList() {
        val storage = cloudStorage ?: run {
            show(getString(R.string.iot_cloud_init_failed))
            return
        }
        binding.iotListLoading.isVisible = true
        binding.iotEmptyView.isVisible = false
        storage.getDayList(currentChannelId, TimeZone.getDefault(), dayListCallback)
    }

    private val dayListCallback = object : TXIoTCallback<List<String>> {
        override fun onSuccess(result: List<String>) = runOnUiThread {
            binding.iotListLoading.isVisible = false
            renderDateList(result)
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) = runOnUiThread {
            binding.iotListLoading.isVisible = false
            L.e("[$TAG] Failed to get cloud storage date list: $errorMessage")
            show(getString(R.string.iot_cloud_get_days_failed, errorMessage))
            renderDateList(emptyList())
        }
    }

    private fun renderDateList(days: List<String>) {
        binding.iotLlDateList.removeAllViews()
        dateChipMap.clear()

        if (days.isEmpty()) {
            binding.iotEmptyView.isVisible = true
            binding.iotDateScroll.isVisible = false
            return
        }

        binding.iotDateScroll.isVisible = true
        val sorted = days.sortedDescending()
        sorted.forEach { date ->
            val chip = LayoutInflater.from(this)
                .inflate(R.layout.iot_item_cloud_storage_date, binding.iotLlDateList, false)
            bindDateChip(chip, date)
            chip.setOnClickListener { selectDate(date) }
            binding.iotLlDateList.addView(chip)
            dateChipMap[date] = chip
        }

        val previous = selectedDate
        val target =
            if (previous.isNotEmpty() && sorted.contains(previous)) previous else sorted.first()
        selectDate(target, forceReload = true)
    }

    private fun bindDateChip(chipView: View, date: String) {
        val tvWeekDay = chipView.findViewById<TextView>(R.id.iot_tvWeekDay)
        val tvDay = chipView.findViewById<TextView>(R.id.iot_tvDay)
        val tvMonth = chipView.findViewById<TextView>(R.id.iot_tvMonth)

        val parsed = parseDateOrNull(date)
        if (parsed == null) {
            tvWeekDay.text = ""
            tvDay.text = date
            tvMonth.text = ""
            return
        }
        tvWeekDay.text = relativeWeekDayText(parsed)
        tvDay.text = dayFormatter.format(parsed)
        tvMonth.text = monthFormatter.format(parsed)
    }

    private fun parseDateOrNull(date: String): Date? = try {
        isoDateFormatter.parse(date)
    } catch (_: Exception) {
        null
    }

    private fun relativeWeekDayText(d: Date): String {
        val today = startOfDay(Calendar.getInstance())
        val target = startOfDay(Calendar.getInstance().apply { time = d })
        val diffDays = ((today.timeInMillis - target.timeInMillis) / (24L * 60 * 60 * 1000)).toInt()
        return when (diffDays) {
            0 -> getString(R.string.iot_today)
            1 -> getString(R.string.iot_yesterday)
            else -> weekDayText(target.get(Calendar.DAY_OF_WEEK))
        }
    }

    private fun startOfDay(cal: Calendar): Calendar = cal.apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    private fun weekDayText(dayOfWeek: Int): String = when (dayOfWeek) {
        Calendar.SUNDAY -> getString(R.string.iot_weekday_sunday)
        Calendar.MONDAY -> getString(R.string.iot_weekday_monday)
        Calendar.TUESDAY -> getString(R.string.iot_weekday_tuesday)
        Calendar.WEDNESDAY -> getString(R.string.iot_weekday_wednesday)
        Calendar.THURSDAY -> getString(R.string.iot_weekday_thursday)
        Calendar.FRIDAY -> getString(R.string.iot_weekday_friday)
        Calendar.SATURDAY -> getString(R.string.iot_weekday_saturday)
        else -> ""
    }

    private fun selectDate(date: String, forceReload: Boolean = false) {
        val dateChanged = selectedDate != date
        if (!dateChanged && !forceReload && allEventsForTimeline.isNotEmpty()) return

        selectedDate = date
        if (dateChanged) {
            binding.iotTimelineView.setDate(date, TimeZone.getDefault())
            binding.iotTimelineView.clear()
            binding.iotTvTimelineTip.isVisible = false
        }
        updateDateChipStyles(date)
        loadEventList(date)
    }

    private fun updateDateChipStyles(selected: String) {
        dateChipMap.forEach { (date, view) ->
            val isSelected = date == selected
            view.isSelected = isSelected
            applyChipColors(view, isSelected)
        }
    }

    private fun applyChipColors(chipView: View, selected: Boolean) {
        val tvWeekDay = chipView.findViewById<TextView>(R.id.iot_tvWeekDay)
        val tvDay = chipView.findViewById<TextView>(R.id.iot_tvDay)
        val tvMonth = chipView.findViewById<TextView>(R.id.iot_tvMonth)
        if (selected) {
            tvWeekDay.setTextColor(Color.parseColor(COLOR_TEXT_SELECTED_SECONDARY))
            tvDay.setTextColor(Color.parseColor(COLOR_TEXT_SELECTED_PRIMARY))
            tvMonth.setTextColor(Color.parseColor(COLOR_TEXT_SELECTED_SECONDARY))
        } else {
            tvWeekDay.setTextColor(Color.parseColor(COLOR_TEXT_NORMAL_SECONDARY))
            tvDay.setTextColor(Color.parseColor(COLOR_TEXT_NORMAL_PRIMARY))
            tvMonth.setTextColor(Color.parseColor(COLOR_TEXT_NORMAL_SECONDARY))
        }
    }

    private fun loadEventList(date: String) {
        val storage = cloudStorage ?: return
        binding.iotListLoading.isVisible = true
        binding.iotEmptyView.isVisible = false
        eventList.clear()
        allEventsForTimeline.clear()
        isTimelinePositionedByUser = false
        pinnedCenterTimeMs = null
        eventAdapter.notifyDataSetChanged()

        binding.iotTimelineView.setVideoFiles(emptyList())
        binding.iotTvTimelineTip.isVisible = false
        binding.iotTimelineCenterGroup.isVisible = false

        binding.iotTimelineView.hourWidthDp = baseHourWidthDp
        loadEventPage(storage, date, "")
    }

    private fun loadEventPage(
        storage: TXIoTCloudStorage,
        date: String,
        pageToken: String
    ) {
        storage.getEventList(
            currentChannelId,
            TimeZone.getDefault(),
            date,
            pageToken,
            createEventPageCallback(storage, date)
        )
    }

    private fun createEventPageCallback(
        storage: TXIoTCloudStorage,
        date: String
    ) = object : TXIoTCallback<TXIoTPageResult<TXIoTEvent>> {
        override fun onSuccess(pageResult: TXIoTPageResult<TXIoTEvent>) = runOnUiThread {
            onEventPageSuccess(storage, date, pageResult)
        }

        override fun onError(errorCode: TXIoTErrorCode, errorMessage: String) = runOnUiThread {
            onEventPageError(date, errorMessage)
        }
    }

    private fun onEventPageSuccess(
        storage: TXIoTCloudStorage,
        date: String,
        pageResult: TXIoTPageResult<TXIoTEvent>
    ) {
        if (date != selectedDate) return

        val pageData = pageResult.dataList ?: emptyList()
        if (pageData.isNotEmpty()) {
            allEventsForTimeline.addAll(pageData)
            val visibleEvents = pageData.filter { !it.eventType.isNullOrEmpty() }
            if (visibleEvents.isNotEmpty()) {
                eventList.addAll(visibleEvents)
                eventList.sortByDescending { it.eventTimeMs }
                eventAdapter.notifyDataSetChanged()
            }
            refreshTimelineFromEvents(allEventsForTimeline)
        }

        val nextToken = pageResult.nextPageToken.orEmpty()
        if (nextToken.isNotEmpty() && pageData.isNotEmpty()) {
            loadEventPage(storage, date, nextToken)
            return
        }

        eventList.sortByDescending { it.eventTimeMs }
        eventAdapter.notifyDataSetChanged()
        binding.iotListLoading.isVisible = false
        binding.iotEmptyView.isVisible = eventList.isEmpty()
        if (allEventsForTimeline.isEmpty()) refreshTimelineFromEvents(emptyList())
        logAllEvents(date)
    }

    private fun logAllEvents(date: String) {
        L.e("[$TAG] Date[$date] pagination finished, total ${allEventsForTimeline.size} events fetched")
        allEventsForTimeline.forEachIndexed { index, event ->
            if (event.videoFiles.isNotEmpty()) {
                L.e(
                    "[$TAG] Event[$index] " +
                            "eventType=${event.eventType} " +
                            "eventTimeMs=${event.eventTimeMs} " +
                            "durationMs=${event.durationMs} " +
                            "videoFiles=${event.videoFiles?.size ?: 0} " +
                            "url=${event.videoFiles[0].videoUrl}"
                )
            }
        }
    }

    private fun onEventPageError(date: String, errorMessage: String) {
        if (date != selectedDate) return
        binding.iotListLoading.isVisible = false
        L.e("[$TAG] Failed to get event list: $errorMessage")
        show(getString(R.string.iot_cloud_get_events_failed, errorMessage))

        binding.iotEmptyView.isVisible = eventList.isEmpty()
        if (allEventsForTimeline.isEmpty()) refreshTimelineFromEvents(emptyList())
    }

    private fun refreshTimelineFromEvents(events: List<TXIoTEvent>) {
        val videoFiles = events.flatMap { it.videoFiles ?: emptyList() }
        binding.iotTimelineView.setVideoFiles(videoFiles)
        binding.iotTvTimelineTip.isVisible = videoFiles.isEmpty()
        val hasVideos = videoFiles.isNotEmpty()

        binding.iotTimelineCenterGroup.isVisible = hasVideos
        if (hasVideos && !isUserScrollingTimeline && !isPlaybackTimeDriven()
                && !isTimelinePositionedByUser) {
            scrollTimelineToFirstSegment()
        }
    }

    private fun scrollTimelineToFirstSegment() {
        binding.iotTimelineView.post {
            val startMs = binding.iotTimelineView.firstSegmentStartMs() ?: return@post
            scrollTimelineToTime(startMs)
        }
    }

    private fun scrollTimelineToTime(timeMs: Long) {
        pinnedCenterTimeMs = timeMs
        binding.iotTvTimelineCenterTime.text = timeFormatter.format(Date(timeMs))
        binding.iotTimelineView.post {
            val targetX = binding.iotTimelineView.getXForTime(timeMs)
            val scrollWidth = binding.iotTimelineScroll.width
            val scrollTo = (targetX - scrollWidth / 2).coerceAtLeast(0)
            binding.iotTimelineScroll.smoothScrollTo(scrollTo, 0)
        }
    }

    private fun viewSnapshot(event: TXIoTEvent) {
        val url = event.thumbnailUrl
        if (url.isNullOrEmpty()) {
            show(getString(R.string.iot_cloud_no_snapshot_image))
            return
        }
        cancelTimelineScrollIdle()
        isTimelinePositionedByUser = true
        showSnapshotPreview(url, buildSnapshotTitle(event))
        if (event.eventTimeMs > 0L) scrollTimelineToTime(event.eventTimeMs)
    }

    private fun cancelTimelineScrollIdle() {
        binding.iotTimelineScroll.removeCallbacks(timelineScrollIdleRunnable)
        isUserScrollingTimeline = false
    }

    private fun showSnapshotPreview(url: String, title: String) {
        vodPlayer?.let { stopCurrentPlayback(it) }
        binding.iotTvSnapshotTitle.text = title
        binding.iotTvSnapshotTitle.isVisible = title.isNotEmpty()
        binding.iotSnapshotLoading.isVisible = true
        binding.iotSnapshotPreviewLayer.isVisible = true
        Glide.with(this)
            .load(url)
            .into(binding.iotIvSnapshotPreview)
        binding.iotIvSnapshotPreview.postDelayed({
            binding.iotSnapshotLoading.isVisible = false
        }, 300L)
    }

    private fun hideSnapshotPreview() {
        binding.iotSnapshotPreviewLayer.isVisible = false
        binding.iotIvSnapshotPreview.setImageDrawable(null)
        binding.iotSnapshotLoading.isVisible = false
    }

    private fun buildSnapshotTitle(event: TXIoTEvent): String {
        val typeName = snapshotEventTypeName(event.eventType)
        val time = timeFormatter.format(Date(event.eventTimeMs))
        if (typeName.isEmpty()) return time
        return "$typeName · $time"
    }

    private fun snapshotEventTypeName(eventType: String?): String = when (eventType) {
        "100" -> getString(R.string.iot_cloud_event_face)
        "101" -> getString(R.string.iot_cloud_event_door)
        else -> ""
    }

    private fun playEvent(event: TXIoTEvent) {
        val files = event.videoFiles
            ?.filter { it.startTimeMs > 0L && it.durationMs > 0L }
            ?.sortedBy { it.startTimeMs }
            ?: emptyList()
        if (files.isEmpty()) {
            show(getString(R.string.iot_cloud_no_playable_video))
            return
        }
        val session = PlaybackSession.forEvent(event, files)
        startSession(session)
    }

    private fun playVideoFile(videoFile: TXIoTVideoFile, seekWallMs: Long? = null) {
        val session = PlaybackSession.forSingleFile(videoFile)
        startSession(session, seekWallMs)
    }

    private fun startSession(session: PlaybackSession, seekWallMs: Long? = null) {
        if (vodPlayer == null) {
            show(getString(R.string.iot_cloud_player_not_init))
            return
        }
        cancelTimelineScrollIdle()
        isTimelinePositionedByUser = true
        hideReplayOverlay()
        hideSnapshotPreview()
        expandVideo()
        binding.iotVideoLoading.isVisible = true
        lastSession = session
        currentSession = session
        currentFileDurationMs = 0L
        startCurrentSegment(session, seekWallMs = seekWallMs)
    }

    private fun startCurrentSegment(session: PlaybackSession, seekWallMs: Long?) {
        val player = vodPlayer ?: return
        val file = session.currentFile() ?: run {
            finishPlaybackSession()
            return
        }
        binding.iotVideoLoading.isVisible = true
        stopCurrentPlayback(player)

        if (seekWallMs != null) session.markPendingSeekWallMs(seekWallMs)

        val pendingSeek = session.consumePendingSeekWallMs()
        val targetWallMs = pendingSeek
            ?: file.startTimeMs.coerceAtLeast(session.startWallMs)
        scrollTimelineToTime(targetWallMs)
        val offsetMs = (targetWallMs - file.startTimeMs).coerceAtLeast(0L)
        runSafely { player.setStartTime(offsetMs / 1000f) }

        val ok = try {
            startPlayWithVideoFile(player, file)
        } catch (e: Exception) {
            L.e("[$TAG] Playback exception: ${e.message}")
            onPlayStartFailed()
            return
        }
        if (!ok) {
            L.e("[$TAG] Failed to start playback")
            onPlayStartFailed()
            return
        }
        isPlayerStarted = true
    }

    private fun onPlayStartFailed() {
        binding.iotVideoLoading.isVisible = false
        hidePlayPauseButton()
        hideReplayOverlay()
        isPlaybackPaused = false
        setKeepScreenOn(false)
        show(getString(R.string.iot_cloud_play_failed))
        currentSession = null
        currentFileDurationMs = 0L
    }

    private fun stopCurrentPlayback(player: TXVodPlayer) {
        progressHandler.removeCallbacks(progressRunnable)
        hidePlayPauseButton()
        isPlaybackPaused = false
        setKeepScreenOn(false)
        if (!isPlayerStarted) return
        try {
            player.stopPlay(true)
        } catch (_: Exception) {
        }
        isPlayerStarted = false
        isSegmentPrepared = false
        currentFileDurationMs = 0L
    }

    private fun startPlayWithVideoFile(
        player: TXVodPlayer,
        videoFile: TXIoTVideoFile
    ): Boolean {
        val fileId = videoFile.vodFileId
        val appId = videoFile.vodAppId

        if (!fileId.isNullOrEmpty() && !appId.isNullOrEmpty()) {
            L.e("[$TAG] Playing cloud storage video by fileId fileId=$fileId appId=$appId")
            val pSign = videoFile.vodPlaySign.orEmpty()
            val playInfoParams = TXPlayInfoParams(appId.toInt(), fileId, pSign)
            player.startVodPlay(playInfoParams)
            return true
        }

        val url = videoFile.videoUrl
        if (url.isNullOrEmpty()) {
            show(getString(R.string.iot_cloud_no_playable_video))
            return false
        }
        L.e("[$TAG] Playing cloud storage video by url url=$url")

        val ret = player.startVodPlay(url)
        return ret == 0
    }

    private fun expandVideo() {
        binding.iotVideoContainer.isVisible = true
    }

    override fun onPause() {
        super.onPause()
        runSafely { if (isPlayerStarted) vodPlayer?.pause() }
    }

    override fun onResume() {
        super.onResume()
        runSafely { if (isPlayerStarted && !isPlaybackPaused) vodPlayer?.resume() }
    }

    override fun onDestroy() {
        super.onDestroy()
        binding.iotTimelineScroll.removeCallbacks(timelineScrollIdleRunnable)
        progressHandler.removeCallbacks(progressRunnable)
        autoHideHandler.removeCallbacks(autoHideRunnable)
        playPauseHideHandler.removeCallbacks(playPauseHideRunnable)
        setKeepScreenOn(false)
        runSafely {
            vodPlayer?.stopPlay(true)
            vodPlayer?.setSurface(null)
        }
        vodPlayer = null
    }

    private inline fun runSafely(block: () -> Unit) {
        try {
            block()
        } catch (_: Exception) {
        }
    }

    fun formatTimeOfDay(timeMs: Long): String = timeFormatter.format(Date(timeMs))

    private class PlaybackSession private constructor(
        val files: List<TXIoTVideoFile>,
        val startWallMs: Long,
        val endWallMs: Long,
        val totalDurationMs: Long,
        private val initialIndex: Int
    ) {
        var currentIndex: Int = initialIndex

        private var pendingSeekWallMs: Long? = null

        fun currentFile(): TXIoTVideoFile? = files.getOrNull(currentIndex)

        fun markPendingSeekWallMs(wallMs: Long) {
            pendingSeekWallMs = wallMs
        }

        fun consumePendingSeekWallMs(): Long? {
            val v = pendingSeekWallMs
            pendingSeekWallMs = null
            return v
        }

        fun resetToStart() {
            currentIndex = initialIndex
            pendingSeekWallMs = null
        }

        fun advanceToNextValidSegment(): Boolean {
            var idx = currentIndex + 1
            while (idx < files.size) {
                if (files[idx].startTimeMs < endWallMs) {
                    currentIndex = idx
                    return true
                }
                idx++
            }
            return false
        }

        companion object {
            fun forEvent(event: TXIoTEvent, files: List<TXIoTVideoFile>): PlaybackSession {
                val start = event.eventTimeMs
                val duration = event.durationMs.coerceAtLeast(0L)
                val end = computeEventEnd(duration, start, files)
                val total = (end - start).coerceAtLeast(0L)
                return PlaybackSession(
                    files,
                    start,
                    end,
                    total,
                    findFirstCoveringIndex(files, start)
                )
            }

            private fun computeEventEnd(
                duration: Long,
                start: Long,
                files: List<TXIoTVideoFile>
            ): Long {
                if (duration > 0L) return start + duration
                val last = files.last()
                return last.startTimeMs + last.durationMs
            }

            private fun findFirstCoveringIndex(files: List<TXIoTVideoFile>, start: Long): Int {
                val idx = files.indexOfFirst {
                    start in it.startTimeMs until (it.startTimeMs + it.durationMs)
                }
                return if (idx >= 0) idx else 0
            }

            fun forSingleFile(file: TXIoTVideoFile): PlaybackSession {
                val start = file.startTimeMs
                val duration = file.durationMs.coerceAtLeast(0L)
                val end = start + duration
                return PlaybackSession(listOf(file), start, end, duration, 0)
            }
        }
    }
}
