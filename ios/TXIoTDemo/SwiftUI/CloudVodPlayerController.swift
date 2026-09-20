import SwiftUI
import TXLiteAVSDK_IOT
import UIKit

// MARK: - 屏幕常亮集中管理

@MainActor
enum ScreenAwakeManager {
    private static var holders: Set<String> = []

    static func acquire(_ owner: String) {
        holders.insert(owner)
        apply()
    }

    static func release(_ owner: String) {
        holders.remove(owner)
        apply()
    }

    static func set(_ keepAwake: Bool, owner: String) {
        keepAwake ? acquire(owner) : release(owner)
    }

    private static func apply() {
        let shouldDisableIdleTimer = !holders.isEmpty
        guard UIApplication.shared.isIdleTimerDisabled != shouldDisableIdleTimer else { return }
        UIApplication.shared.isIdleTimerDisabled = shouldDisableIdleTimer
    }
}

// MARK: - TXVodPlayer 控制器 + 渲染视图

/// 渲染宿主优先级：全屏优先于内嵌。控制器始终把画面绑定到优先级最高的存活宿主。
enum RenderPriority: Int {
    case inline = 0
    case fullscreen = 1
}

@MainActor
final class CloudVodPlayerController: NSObject, ObservableObject, TXVodPlayListener {
    let player = TXVodPlayer()

    /// 播放状态变化时同步系统息屏开关：播放中禁止息屏，暂停 / 播完 / 出错 / 停止后恢复。
    @Published var isPlaying: Bool = false {
        didSet {
            guard isPlaying != oldValue else { return }
            ScreenAwakeManager.set(isPlaying, owner: screenAwakeOwnerId)
            isPlaying ? startProgressSmoothing() : stopProgressSmoothing()
        }
    }
    @Published var isLoading: Bool = false
    @Published var isMuted: Bool = false
    /// 当前播放进度（**事件相对秒数**，区间 `0 ... duration`）。
    /// 由 SDK 进度事件驱动，并在两次回调之间按本地时钟平滑内插，保证时间 UI 均匀走秒。
    @Published var currentTime: Double = 0
    /// 进度条总长度（**事件时长秒数**，等于 `eventDurationMs / 1000`）
    @Published var duration: Double = 0
    @Published var errorMessage: String?

    // MARK: - 渲染宿主（不再移动共享 view，而是把渲染绑定到当前可见宿主）

    /// 内嵌播放宿主视图（弱引用，由内嵌 VodPlayerRenderView 注册）
    private weak var inlineHost: UIView?
    /// 全屏播放宿主视图（弱引用，由全屏 VodPlayerRenderView 注册）
    private weak var fullscreenHost: UIView?
    /// 当前已绑定渲染的宿主视图
    private weak var boundHost: UIView?

    private var isSeeking: Bool = false

    // MARK: - 播放进度平滑

    /// 进度平滑定时器：SDK 进度回调间隔约 0.5s 且不均匀，期间按本地时钟内插推进
    private var progressTimer: Timer?
    /// 最近一次进度锚点：事件相对秒数 + 设定该锚点的本地时间
    private var progressAnchor: (seconds: Double, date: Date)?
    /// seek 后的短暂窗口内忽略 SDK 补发的旧进度，避免时间回跳
    private var ignoreProgressUntil: Date = .distantPast

    // MARK: - 事件 / 文件队列状态

    /// 当前播放的事件起始墙上时间（毫秒）。`currentTime = 0` 对应该时刻。
    private var eventStartMs: Int64 = 0
    /// 事件总时长（毫秒）。
    private var eventDurationMs: Int64 = 0
    /// 按 startTimeMs 升序排序后的播放队列
    private var fileQueue: [CloudVideoFile] = []
    /// 当前正在播放的文件在队列中的索引，-1 表示未开始
    private var currentFileIndex: Int = -1
    /// 当前文件由 SDK 上报的真实时长（秒）。用于在 PROGRESS 事件中 clamp 文件内秒数。
    private var currentFileDurationSec: Double = 0
    /// 切换到新文件后，待 SDK Prepared 时执行的 seek（文件内秒数）。<0 表示无 pending。
    private var pendingFileSeekSec: Double = -1
    /// 是否已进入"播完"终态。
    private var isAtEventEnd: Bool = false
    nonisolated private let screenAwakeOwnerId = "CloudVodPlayer-\(UUID().uuidString)"

    override init() {
        super.init()
        player.vodDelegate = self
        player.isAutoPlay = true
        player.enableHWAcceleration = true
    }

    deinit {
        // 控制器被释放时兜底释放常亮持有，避免播放中直接销毁导致屏幕永久常亮
        let owner = screenAwakeOwnerId
        Task { @MainActor in ScreenAwakeManager.release(owner) }
    }

    // MARK: - 公共播放入口

    /// 播放一个云存事件（推荐入口）。
    ///
    /// 行为：
    /// 1. 进度条总长度对外呈现为 `event.durationMs / 1000`；
    /// 2. 自动从 `event.eventTimeMs` 对应的视频文件起播；
    /// 3. 当一个文件播放结束时，自动切换到队列中的下一个文件继续播放。
    /// 播放一个云存事件（推荐入口），从事件触发时刻起播。
    func start(with event: CloudEventItem) {
        start(with: event, fromWallMs: event.eventTimeMs)
    }

    /// 播放一个云存事件，并从指定的墙上时间（毫秒）起播。
    /// 用于时间线滚动停止后，从停止位置继续播放。
    func start(with event: CloudEventItem, fromWallMs wallMs: Int64) {
        let files = event.sortedVideoFiles
        guard !files.isEmpty else {
            resetPlaybackState(loading: false)
            errorMessage = L("No playable video file for this event")
            return
        }

        // 切换播放源前先清掉旧的，避免叠加渲染
        player.stopPlay()

        eventStartMs = event.eventTimeMs
        eventDurationMs = max(event.durationMs, 0)
        fileQueue = files
        currentFileIndex = -1
        currentFileDurationSec = 0
        pendingFileSeekSec = -1

        resetPlaybackState(loading: true)
        duration = Double(eventDurationMs) / 1000.0
        // 进度立即指向目标位置：loading 期间平滑器不推进，仅刷新锚点；
        // 避免时间线跟随 / 进度条在起播加载期间停在事件起点，待 pending seek 落点后从目标位置继续
        currentTime = clampToDuration(Double(wallMs - event.eventTimeMs) / 1000.0)
        progressAnchor = (currentTime, Date())

        // 若已有可用宿主但尚未绑定渲染（如上次 stop 后重新起播），先补绑
        ensureRenderBound()

        // 从指定时刻起播：找到包含该时刻的文件并 seek
        seekToEventMs(wallMs)
    }

    func stop() {
        player.stopPlay()
        player.removeVideoWidget()
        boundHost = nil
        fileQueue = []
        currentFileIndex = -1
        currentFileDurationSec = 0
        pendingFileSeekSec = -1
        eventStartMs = 0
        eventDurationMs = 0
        resetPlaybackState(loading: false)
        stopProgressSmoothing()
        ScreenAwakeManager.release(screenAwakeOwnerId)
    }

    func togglePlay() {
        if isFinished {
            replay()
            return
        }
        if player.isPlaying() {
            player.pause()
            isPlaying = false
        } else {
            isAtEventEnd = false
            player.resume()
            isPlaying = true
        }
    }

    /// 是否已播放到事件末尾（正常播完或被事件末尾截停）：用于展示"播放结束"提示层
    var isFinished: Bool {
        duration > 0 && errorMessage == nil && !isLoading && !isPlaying && currentTime >= duration
    }

    /// 从头重播当前事件（播放结束后调用）：强制重启对应文件，
    /// 不依赖 ended / paused 状态下 seek / resume 的 SDK 行为差异
    func replay() {
        guard !fileQueue.isEmpty else { return }
        errorMessage = nil
        currentTime = 0
        isAtEventEnd = false
        let target = locateFile(forWallMs: eventStartMs) ?? (index: 0, fileSeekSec: 0)
        switchToFile(at: target.index, file: fileQueue[target.index], seekSecond: target.fileSeekSec)
    }

    /// 跳转：直接执行 seek（用于 ±10s 按钮）。time 单位为**事件相对秒数**。
    func seek(to time: Double) {
        guard duration > 0 else { return }
        let clamped = clampToDuration(time)
        currentTime = clamped
        progressAnchor = (clamped, Date())
        isAtEventEnd = false
        seekToEventMs(eventStartMs + Int64(clamped * 1000))
    }

    // MARK: Slider 拖动期间的状态保护

    func beginSeeking() {
        isSeeking = true
    }

    /// 拖动过程中的预览：仅更新 UI，不真正 seek，避免来回抖动
    func previewSeek(to time: Double) {
        let clamped = clampToDuration(time)
        currentTime = clamped
        progressAnchor = (clamped, Date())
    }

    /// 松手后真正 seek
    func commitSeek() {
        defer { isSeeking = false }
        guard duration > 0 else { return }
        isAtEventEnd = false
        progressAnchor = (currentTime, Date())
        seekToEventMs(eventStartMs + Int64(currentTime * 1000))
    }

    func toggleMute() {
        isMuted.toggle()
        player.setMute(isMuted)
    }

    // MARK: - 渲染宿主注册 / 绑定

    /// 注册渲染宿主视图（由 VodPlayerRenderView 在 make/update 时调用，幂等）。
    /// 注册后立即把渲染绑定到当前优先级最高的存活宿主。
    func registerRenderHost(_ view: UIView, priority: RenderPriority) {
        switch priority {
        case .inline: inlineHost = view
        case .fullscreen: fullscreenHost = view
        }
        rebindActiveHostIfNeeded()
    }

    /// 注销渲染宿主视图（由 VodPlayerRenderView 在 dismantle 时调用）。
    /// 例如全屏退出时注销全屏宿主，渲染会自动交回内嵌宿主。
    func unregisterRenderHost(priority: RenderPriority) {
        switch priority {
        case .inline: inlineHost = nil
        case .fullscreen: fullscreenHost = nil
        }
        rebindActiveHostIfNeeded()
    }

    /// 全屏退出后主动把渲染交回内嵌宿主（兜底，避免依赖 dismantle 时机）。
    func requestReattach() {
        fullscreenHost = nil
        rebindActiveHostIfNeeded()
    }

    /// 若当前绑定的宿主不是优先级最高的存活宿主，则重建渲染表面并绑定过去。
    /// 每次绑定都通过 `setupVideoWidget` 创建全新渲染表面，避免跨 window / 旋转后表面失效导致的黑屏。
    private func rebindActiveHostIfNeeded() {
        guard let target = fullscreenHost ?? inlineHost, boundHost !== target else { return }
        let isRebind = boundHost != nil
        boundHost = target

        player.removeVideoWidget()
        player.setupVideoWidget(target, insert: 0)
        player.setRenderMode(TX_Enum_Type_RenderMode.RENDER_MODE_FILL_EDGE)

        // 宿主切换（内嵌<->全屏）后画面可能停在黑帧，强制解码一帧刷新；首次绑定则无需。
        if isRebind {
            forceRefreshCurrentFrame()
        }
    }

    /// 起播时若已有宿主但尚未绑定渲染，则补绑（不强制刷新帧，由起播 seek 负责首帧）。
    private func ensureRenderBound() {
        guard boundHost == nil, let target = fullscreenHost ?? inlineHost else { return }
        boundHost = target
        player.setupVideoWidget(target, insert: 0)
        player.setRenderMode(TX_Enum_Type_RenderMode.RENDER_MODE_FILL_EDGE)
    }

    /// 强制解码并刷新当前帧：宿主切换、重建渲染表面后用于消除黑帧。
    private func forceRefreshCurrentFrame() {
        guard duration > 0 else { return }
        seekToEventMs(eventStartMs + Int64(currentTime * 1000))
        if isPlaying { player.resume() }
    }

    // MARK: - 文件队列 / 跨文件 seek

    /// 跳转到指定的墙上时间（毫秒）。
    private func seekToEventMs(_ wallMs: Int64) {
        guard !fileQueue.isEmpty else { return }

        // seek 后 SDK 可能补发一次 seek 前的旧进度：短暂窗口内忽略，避免时间回跳
        ignoreProgressUntil = Date().addingTimeInterval(0.6)

        if let (index, fileSeekSec) = locateFile(forWallMs: wallMs) {
            playFile(at: index, seekToFileSecond: fileSeekSec)
            return
        }

        // 已超出所有文件：定位到最后一个文件末尾
        let lastIdx = fileQueue.count - 1
        let last = fileQueue[lastIdx]
        playFile(at: lastIdx, seekToFileSecond: Double(last.durationMs) / 1000.0)
    }

    /// 在文件队列中定位墙上时间 `wallMs` 对应的播放位置。
    /// - Returns: `(文件索引, 文件内秒数)`；若 wallMs 超过所有文件结束时间则返回 nil。
    private func locateFile(forWallMs wallMs: Int64) -> (index: Int, fileSeekSec: Double)? {
        for (idx, file) in fileQueue.enumerated() {
            // 落在文件区间内：直接定位
            if wallMs >= file.startTimeMs && wallMs < file.endTimeMs {
                let offsetMs = max(0, wallMs - file.startTimeMs)
                return (idx, Double(offsetMs) / 1000.0)
            }
            // 落在前一个文件结束 ~ 当前文件开始之间的间隙：跳到当前文件开头
            if wallMs < file.startTimeMs {
                return (idx, 0)
            }
        }
        return nil
    }

    /// 切换到指定索引的文件并 seek 到文件内秒数。
    /// 若目标就是当前文件，则只 seek 不重启 startVodPlay。
    private func playFile(at index: Int, seekToFileSecond fileSec: Double) {
        guard fileQueue.indices.contains(index) else { return }
        let file = fileQueue[index]

        if index == currentFileIndex {
            // 同文件内 seek
            let clamped = clampedFileSeek(fileSec, fileDurationMs: file.durationMs)
            player.seek(Float(clamped))
            return
        }

        switchToFile(at: index, file: file, seekSecond: clampedFileSeek(fileSec, fileDurationMs: file.durationMs))
    }

    /// 切换到新文件：先 stop 再 start，并把目标 seek 暂存到 pendingFileSeekSec
    private func switchToFile(at index: Int, file: CloudVideoFile, seekSecond sec: Double) {
        player.stopPlay()
        currentFileIndex = index
        currentFileDurationSec = 0
        pendingFileSeekSec = sec
        isLoading = true

        if let err = startPlay(file: file) {
            errorMessage = err
            isLoading = false
            pendingFileSeekSec = -1
        }
    }

    private func clampedFileSeek(_ sec: Double, fileDurationMs: Int64) -> Double {
        guard sec > 0 else { return 0 }
        // 文件实际时长以 SDK 上报的 currentFileDurationSec 优先，回退到 model 中的 durationMs
        let modelDurationSec = Double(max(fileDurationMs, 0)) / 1000.0
        let limit = currentFileDurationSec > 0 ? currentFileDurationSec : modelDurationSec
        guard limit > 0 else { return sec }
        return min(sec, limit)
    }

    // MARK: - Private helpers

    /// 启动播放；返回错误提示，nil 表示成功
    private func startPlay(file: CloudVideoFile) -> String? {
        if !file.videoUrl.isEmpty {
            let code = player.startVodPlay(file.videoUrl)
            return code == 0 ? nil : L("Playback failed (code=%d)", code)
        }
        guard !file.vodFileId.isEmpty, let appId = Int32(file.vodAppId) else {
            return L("No playable video URL")
        }
        let params = TXPlayerAuthParams()
        params.appId = appId
        params.fileId = file.vodFileId
        params.sign = file.vodPlaySign
        let code = player.startVodPlay(with: params)
        return code == 0 ? nil : L("Playback failed (code=%d)", code)
    }

    private func resetPlaybackState(loading: Bool) {
        errorMessage = nil
        isLoading = loading
        isPlaying = false
        currentTime = 0
        // 注意：duration 不在此处重置，由 start(with:) 显式设置为事件时长
        isSeeking = false
        isAtEventEnd = false
    }

    private func clampToDuration(_ time: Double) -> Double {
        return max(0, min(time, duration))
    }

    // MARK: - 播放进度平滑（内插）

    /// 启动进度平滑定时器：0.2s 一格在两次 SDK 进度回调之间内插推进。
    /// 控制器释放后下一拍自动 invalidate，定时器不会在 RunLoop 中残留空转。
    private func startProgressSmoothing() {
        guard progressTimer == nil else { return }
        progressAnchor = (currentTime, Date())
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            // 定时器已加入 RunLoop.main，回调必然发生在主线程
            MainActor.assumeIsolated {
                self.smoothProgressTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressSmoothing() {
        progressTimer?.invalidate()
        progressTimer = nil
        progressAnchor = nil
    }

    /// 定时推进播放进度：缓冲 / 拖动滑条期间不推进，仅刷新锚点基准，
    /// 使恢复后从当前位置继续平滑，而不是把停滞时长一次性跳过。
    private func smoothProgressTick() {
        guard isPlaying, duration > 0 else { return }
        guard !isLoading, !isSeeking, let anchor = progressAnchor else {
            progressAnchor = (currentTime, Date())
            return
        }
        currentTime = clampToDuration(anchor.seconds + Date().timeIntervalSince(anchor.date))
    }

    // MARK: - TXVodPlayListener

    nonisolated func onPlayEvent(
        _ player: TXVodPlayer!,
        event EvtID: Int32,
        withParam param: [AnyHashable: Any]!
    ) {
        // 在非隔离上下文中先提取所需字段为 Sendable 基础类型，避免跨 actor 发送非 Sendable 字典
        let code = Int(EvtID)
        let dict: [AnyHashable: Any] = param ?? [:]
        let progress = (dict["EVT_PLAY_PROGRESS"] as? NSNumber)?.doubleValue
        let totalDuration = (dict["EVT_PLAY_DURATION"] as? NSNumber)?.doubleValue
        let msg = dict["EVT_MSG"] as? String

        DispatchQueue.main.async { [weak self] in
            self?.dispatchPlayEvent(
                code: code,
                progress: progress,
                duration: totalDuration,
                msg: msg
            )
        }
    }

    nonisolated func onNetStatus(_ player: TXVodPlayer!, withParam param: [AnyHashable: Any]!) {
        // 可选：统计网络信息
    }

    private func dispatchPlayEvent(
        code: Int,
        progress: Double?,
        duration totalDuration: Double?,
        msg: String?
    ) {
        // 已进入"播完"终态：忽略 SDK 补发的滞后播放中事件（PREPARED / BEGIN / PROGRESS / LOADING…），
        // 否则 isPlaying 会被重新置为 true 并再次禁用息屏，造成播完后屏幕永久常亮。
        // 仅放行错误事件，保证异常仍能反馈给用户。
        if isAtEventEnd, code >= 0 { return }

        switch Int32(code) {
        case PLAY_EVT_VOD_PLAY_PREPARED.rawValue:
            handlePrepared(fileDuration: totalDuration)
        case PLAY_EVT_VOD_LOADING_END.rawValue,
            PLAY_EVT_RCV_FIRST_I_FRAME.rawValue:
            isLoading = false
        case PLAY_EVT_PLAY_BEGIN.rawValue:
            isPlaying = true
            isLoading = false
        case PLAY_EVT_PLAY_LOADING.rawValue:
            isLoading = true
        case PLAY_EVT_PLAY_PROGRESS.rawValue:
            applyProgress(fileProgress: progress, fileDuration: totalDuration)
        case PLAY_EVT_PLAY_END.rawValue:
            handleFileEnd()
        default:
            // 负值一般代表错误
            guard code < 0 else { return }
            applyError(code: code, msg: msg)
        }
    }

    /// SDK 通知文件已 Prepared：执行该文件的 pending seek（首播或切文件时计算出的文件内秒数）
    private func handlePrepared(fileDuration: Double?) {
        if let dv = fileDuration, dv > 0 {
            currentFileDurationSec = dv
        }
        isLoading = false
        guard pendingFileSeekSec >= 0 else { return }
        let target = clampedFileSeek(
            pendingFileSeekSec,
            fileDurationMs: currentFile()?.durationMs ?? 0
        )
        pendingFileSeekSec = -1
        // 即使为 0 也调一次 seek，确保起播位置准确
        ignoreProgressUntil = Date().addingTimeInterval(0.6)
        player.seek(Float(target))
    }

    /// 把 SDK 上报的文件内进度换算为事件相对进度
    private func applyProgress(fileProgress: Double?, fileDuration: Double?) {
        if let dv = fileDuration, dv > 0 {
            currentFileDurationSec = dv
        }
        guard !isSeeking, let p = fileProgress, let file = currentFile() else { return }
        // 事件相对秒数 = 文件起点相对事件的偏移 + 文件内秒数
        let fileOffsetSec = Double(file.startTimeMs - eventStartMs) / 1000.0
        let eventTimeSec = fileOffsetSec + p
        // 部分事件的录像文件覆盖区间长于事件时长：播放到事件末尾即截停，避免播放时间超出事件时长
        if duration > 0, eventTimeSec >= duration {
            stopAtEventEnd()
            return
        }
        // 切文件的 pending seek 未落地、或 seek 后窗口内补发的旧进度，直接丢弃：
        // 此类进度约为文件起点 / seek 前旧值，采纳会把已指向目标位置的进度冲回
        guard pendingFileSeekSec < 0, Date() >= ignoreProgressUntil else { return }
        let clamped = clampToDuration(eventTimeSec)
        currentTime = clamped
        progressAnchor = (clamped, Date())
    }

    /// 播放位置到达事件末尾：截停播放并呈现"播完"状态（进度停在事件时长处，画面保留最后一帧）
    private func stopAtEventEnd() {
        enterFinishedState()
    }

    /// 当前文件播放结束：尝试切到下一文件；若无下一文件则视为事件结束
    private func handleFileEnd() {
        let nextIndex = currentFileIndex + 1
        if fileQueue.indices.contains(nextIndex) {
            // 顺序播放下一个文件，从头开始
            playFile(at: nextIndex, seekToFileSecond: 0)
            return
        }
        // 已是最后一个文件
        enterFinishedState()
    }

    /// 进入"播完"状态：
    /// 1. 置终态标记，屏蔽 SDK 后续补发的滞后播放中事件（避免 isPlaying 被顶回 true 而重新禁用息屏）；
    /// 2. 显式 pause 让 SDK 内部播放回路彻底停下
    ///    （SDK 内部基于 AVPlayer，默认 preventsDisplaySleepDuringVideoPlayback = true，
    ///     自然播完若不显式 pause，系统可能继续抑制息屏）；
    /// 3. 显式释放常亮持有，不依赖 isPlaying 的 didSet（其在已为 false 时不会触发）。
    private func enterFinishedState() {
        isAtEventEnd = true
        player.pause()
        isLoading = false
        isPlaying = false
        currentTime = duration
        ScreenAwakeManager.release(screenAwakeOwnerId)
    }

    private func currentFile() -> CloudVideoFile? {
        guard fileQueue.indices.contains(currentFileIndex) else { return nil }
        return fileQueue[currentFileIndex]
    }

    private func applyError(code: Int, msg: String?) {
        errorMessage = msg ?? L("Playback error (%ld)", code)
        isLoading = false
        isPlaying = false
        // 出错后播放已中断，同样需要显式释放常亮持有
        ScreenAwakeManager.release(screenAwakeOwnerId)
    }
}

/// SwiftUI -> UIKit 桥接：将 TXVodPlayer 的渲染呈现到 SwiftUI。
///
/// 设计：每个 RenderView 拥有自己独立的宿主 UIView，不再在内嵌 / 全屏之间移动同一个共享 view。
/// 出现时把自己的宿主视图按优先级注册给 controller，由 controller 通过 `setupVideoWidget`
/// 把渲染重新绑定到优先级最高的存活宿主（全屏 > 内嵌）。
/// 这样进入 / 退出全屏都会重建全新的渲染表面，从根本上避免跨 window / 旋转后表面失效导致的黑屏。
struct VodPlayerRenderView: UIViewRepresentable {
    let controller: CloudVodPlayerController
    /// 该宿主的渲染优先级：内嵌为 .inline，全屏为 .fullscreen
    var priority: RenderPriority = .inline

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, priority: priority)
    }

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .black
        controller.registerRenderHost(host, priority: priority)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 幂等重注册：处理 SwiftUI 复用 host 的场景；controller 内部会判断是否需要重绑
        controller.registerRenderHost(uiView, priority: priority)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.unregister()
    }

    /// Coordinator 仅用于在宿主视图被销毁（如退出全屏）时向 controller 注销该优先级的宿主，
    /// 从而让 controller 自动把渲染交回更低优先级的存活宿主（内嵌）。
    @MainActor
    final class Coordinator {
        private weak var controller: CloudVodPlayerController?
        private let priority: RenderPriority

        init(controller: CloudVodPlayerController, priority: RenderPriority) {
            self.controller = controller
            self.priority = priority
        }

        func unregister() {
            controller?.unregisterRenderHost(priority: priority)
        }
    }
}

// MARK: - 屏幕方向管理

/// 屏幕方向控制：通过 AppDelegate.setAllowedOrientations: 修改全局开关，
/// 并主动请求 UIKit 立刻刷新到新方向。
/// 内部全部访问 UIKit / UIApplication 等 MainActor 隔离 API，因此整体声明为 @MainActor。
@MainActor
enum OrientationManager {
    /// 允许横屏（左右两个方向），并主动旋转到 landscapeRight
    static func allowLandscape() {
        AppDelegate.setAllowedOrientations([.landscape, .portrait])
        forceRotate(to: .landscapeRight)
    }

    /// 仅允许竖屏，并主动旋转回 portrait
    static func lockPortrait() {
        AppDelegate.setAllowedOrientations(.portrait)
        forceRotate(to: .portrait)
    }

    /// 主动通知 UIKit 旋转到目标方向
    private static func forceRotate(to orientation: UIInterfaceOrientation) {
        let mask: UIInterfaceOrientationMask = orientation.isLandscape ? .landscape : .portrait

        if #available(iOS 16.0, *) {
            requestGeometryUpdateiOS16(mask: mask)
        }

        // 兼容旧版 / 兜底
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    @available(iOS 16.0, *)
    private static func requestGeometryUpdateiOS16(mask: UIInterfaceOrientationMask) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("Rotation failed: \(error.localizedDescription)")
            }
        }
        refreshInterfaceOrientation(scenes: scenes)
    }

    /// 触发所有 view controller（含 fullScreenCover 中的顶层 VC）重新评估方向
    private static func refreshInterfaceOrientation(scenes: [UIWindowScene]) {
        for scene in scenes {
            guard let root = scene.keyWindow?.rootViewController else { continue }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            if #available(iOS 16, *) {
                top.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}
