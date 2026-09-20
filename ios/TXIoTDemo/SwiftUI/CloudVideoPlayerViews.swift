//
//  CloudVideoPlayerViews.swift
//  TXIoTDemo
//
//  云存视频播放相关的 SwiftUI 视图：
//  - InlineCloudPlayerView：页面内嵌播放器
//  - CloudVideoPlayerView：弹窗 / 全页 sheet 播放器
//  - FullscreenCloudPlayerView：全屏播放器（复用同一个 controller）
//

import SwiftUI

// MARK: - 播放结束提示层（内嵌 / 全屏播放器共用）

/// 播放到事件末尾时覆盖在画面上的提示层：半透明遮罩 + 重播按钮
private struct PlaybackEndOverlay: View {
    let onReplay: () -> Void

    var body: some View {
        ZStack {
            // 遮罩不拦截点击：让点击穿透到底层手势层，保证播完后仍能唤出控制层
            Color.black.opacity(0.45)
                .allowsHitTesting(false)
            VStack(spacing: 10) {
                Button(action: onReplay) {
                    Image(systemName: "gobackward")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.white)
                }
                Text(L("Playback ended"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }
}

// MARK: - 暂停/播放按钮（内嵌 / 全屏播放器共用）

/// 画面中央的暂停/播放按钮：播放中显示暂停图标，暂停时显示播放图标。
/// 加载中 / 出错 / 播完时不展示，由对应浮层接管。
private struct CenterPlayPauseButton: View {
    @ObservedObject var player: CloudVodPlayerController

    var body: some View {
        if !player.isLoading, player.errorMessage == nil, !player.isFinished {
            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
            }
        }
    }
}

// MARK: - 内嵌云存播放器（页面内播放，非 sheet）

/// 内嵌播放视图：固定高度，顶部右上角带关闭按钮，底部带紧凑控制条。
/// 与 CloudVideoPlayerView 的区别：
/// - 不持有 player（由父视图传入），切换事件时复用同一 controller
/// - 不使用全屏 sheet 与 dismiss
struct InlineCloudPlayerView: View {
    @ObservedObject var player: CloudVodPlayerController
    let onFullscreen: () -> Void

    /// 中央暂停/播放按钮是否可见：播放中几秒后自动隐藏，点击画面可重新唤出
    @State private var centerButtonVisible: Bool = true
    /// 中央按钮自动隐藏任务（暂停 / 手动隐藏时取消）
    @State private var autoHideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            VodPlayerRenderView(controller: player)
                .background(Color.black)

            videoTapLayer

            if player.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }

            if let err = player.errorMessage {
                errorOverlay(message: err)
            }

            if player.isFinished {
                PlaybackEndOverlay(onReplay: { player.replay() })
            }

            if centerButtonVisible || !player.isPlaying {
                CenterPlayPauseButton(player: player)
            }
            floatingControls
        }
        .clipped()
        .onChange(of: player.isPlaying) { handlePlayingChange($0) }
        .onDisappear { autoHideTask?.cancel() }
    }

    /// 透明点击层：播放中点击画面唤出 / 隐藏中央按钮；暂停时按钮常驻，不响应隐藏
    private var videoTapLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { handleVideoTap() }
    }

    private func handleVideoTap() {
        guard player.isPlaying else { return }
        if centerButtonVisible {
            autoHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) { centerButtonVisible = false }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { centerButtonVisible = true }
            scheduleAutoHide()
        }
    }

    /// 播放状态变化：按钮恢复可见；进入播放时启动 3 秒自动隐藏，暂停时常驻显示
    private func handlePlayingChange(_ playing: Bool) {
        autoHideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) { centerButtonVisible = true }
        if playing { scheduleAutoHide() }
    }

    /// 3 秒后自动隐藏中央按钮
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) { centerButtonVisible = false }
            }
        }
    }

    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundColor(.warningColor)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    /// 右侧悬浮按钮：静音、全屏
    private var floatingControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 24) {
                muteButton
                fullscreenButton
            }
            .padding(.trailing, 10)
        }
    }

    private var muteButton: some View {
        Button(action: { player.toggleMute() }) {
            Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        }
    }

    private var fullscreenButton: some View {
        Button(action: onFullscreen) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        }
    }

}

// MARK: - 抓图事件内嵌图片视图（占用与视频播放器相同的位置）

/// 抓图事件（无视频，仅缩略图）的内嵌展示视图：
/// - 与 InlineCloudPlayerView 等高（220），黑底，居中按比例展示图片
struct InlineSnapshotView: View {
    let event: CloudEventItem

    var body: some View {
        ZStack {
            Color.black
            imageContent
        }
        .clipped()
    }

    @ViewBuilder
    private var imageContent: some View {
        if let url = URL(string: event.thumbnailUrl), !event.thumbnailUrl.isEmpty {
            AsyncImage(url: url) { phase in
                asyncImageForPhase(phase)
            }
        } else {
            failurePlaceholder
        }
    }

    @ViewBuilder
    private func asyncImageForPhase(_ phase: AsyncImagePhase) -> some View {
        switch phase {
        case .success(let image):
            image.resizable().scaledToFit()
        case .empty:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
        case .failure:
            failurePlaceholder
        @unknown default:
            failurePlaceholder
        }
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.6))
            Text(L("Failed to load image"))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct CloudVideoPlayerView: View {
    let event: CloudEventItem
    let eventTitle: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = CloudVodPlayerController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                videoArea
                Spacer(minLength: 0)
                controlBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.6))
            }
        }
        .onAppear { player.start(with: event) }
        .onDisappear { player.stop() }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }

            Spacer()

            VStack(spacing: 2) {
                Text(L("Cloud Playback"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.8))
                Text(eventTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var videoArea: some View {
        ZStack {
            VodPlayerRenderView(controller: player)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)

            if player.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            }

            if let err = player.errorMessage {
                videoErrorOverlay(message: err)
            }
        }
    }

    private func videoErrorOverlay(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.warningColor)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(formatTime(player.currentTime))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 44, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.previewSeek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.1),
                    onEditingChanged: { editing in
                        if editing {
                            player.beginSeeking()
                        } else {
                            player.commitSeek()
                        }
                    }
                )
                .accentColor(.primaryColor)
                .disabled(player.duration <= 0)

                Text(formatTime(player.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 44, alignment: .trailing)
            }

            HStack(spacing: 28) {
                Button(action: { player.seek(to: max(0, player.currentTime - 10)) }) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }

                Button(action: { player.togglePlay() }) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.white)
                }

                Button(action: { player.seek(to: min(player.duration, player.currentTime + 10)) }) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }

                Button(action: { player.toggleMute() }) {
                    Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite, time >= 0 else { return "00:00" }
        let total = Int(time)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - 全屏播放视图（复用同一个 CloudVodPlayerController）

/// 全屏播放视图：
/// - 复用外部传入的 player（不创建新的 controller，进度/状态连续）
/// - 使用 aspectRatio(.fit) 让视频按原始比例最大化显示
/// - 横屏布局，控件叠加在画面之上
struct FullscreenCloudPlayerView: View {
    @ObservedObject var player: CloudVodPlayerController
    @ObservedObject var viewModel: CloudStorageViewModel
    /// 进入全屏时正在播放的事件 id，用于同事件 seek / 不同事件切换判断
    @State private var currentEventId: UUID?
    /// 控制层（时间线、静音、退出全屏）是否可见；全屏下 3 秒无操作自动隐藏
    @State private var controlsVisible: Bool = true
    @State private var autoHideTask: Task<Void, Never>?
    /// 轻提示文案（拖动时间线到无录像处时提示），非 nil 时展示 Toast
    @State private var toastMessage: String?
    /// Toast 自动消失去抖 token
    @State private var toastToken: UUID?
    let initialEventId: UUID?
    /// 进入全屏时内嵌时间线的中心"日内秒数"，用于让全屏时间线中心与内嵌完全对齐
    let initialCenterSeconds: Double?
    /// 全屏时间线中心秒数变化回调（上报精确的 targetCenterSeconds），退出全屏时用于同步内嵌位置
    let onCenterSecondsChange: (Double) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            videoRenderLayer
            tapGestureLayer

            if player.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)
            }

            if let err = player.errorMessage {
                fullscreenErrorOverlay(message: err)
            }

            if player.isFinished {
                PlaybackEndOverlay(onReplay: { player.replay() })
                    .ignoresSafeArea()
            }

            if controlsVisible || !player.isPlaying {
                CenterPlayPauseButton(player: player)
            }
            bottomTimelineArea
            fullscreenFloatingControls
        }
        .appToast(message: $toastMessage)
        .statusBarHidden(true)
        .onAppear {
            currentEventId = initialEventId
            scheduleAutoHide()
        }
        .onChange(of: player.isFinished) { finished in
            guard finished else { return }
            // 播完时取消自动隐藏并唤出控制层，保证退出全屏 / 静音按钮可见可操作
            autoHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) { controlsVisible = true }
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
    }

    // MARK: 子图层

    /// 视频画面层
    private var videoRenderLayer: some View {
        VodPlayerRenderView(controller: player, priority: .fullscreen)
            .ignoresSafeArea()
    }

    /// 透明点击层：位于视频之上、控件之下
    private var tapGestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { handleScreenTap() }
            .ignoresSafeArea()
    }

    /// 底部时间线（仅横屏全屏模式使用暗色主题）
    private var bottomTimelineArea: some View {
        VStack {
            Spacer()
            CloudTimelineBar(
                events: viewModel.events,
                scrollRequest: nil,
                onSegmentTap: { handleSegmentTap($0) },
                onScrollEnd: { handleTimelineScrollEnd($0) },
                theme: .dark,
                autoPositionToSeconds: initialCenterSeconds,
                onCenterSecondsChange: { onCenterSecondsChange($0) },
                playbackSeconds: playbackSecondsOfDay
            )
            .frame(height: 76, alignment: .top)
            .offset(y: -6)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .padding(.bottom, -12)
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
    }

    /// 右侧悬浮按钮：静音、退出全屏
    private var fullscreenFloatingControls: some View {
        HStack {
            Spacer()
            VStack(spacing: 24) {
                fullscreenMuteButton
                exitFullscreenButton
            }
            .padding(.trailing, 16)
        }
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
    }

    private var fullscreenMuteButton: some View {
        Button(action: { player.toggleMute() }) {
            Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
    }

    private var exitFullscreenButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
    }

    private func fullscreenErrorOverlay(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.warningColor)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }

    // MARK: - 控制层自动隐藏

    /// 启动 3 秒后自动隐藏控制层的定时器
    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) {
                    controlsVisible = false
                }
            }
        }
    }

    /// 点击屏幕：控制层可见时隐藏，隐藏时显示并重新计时
    private func handleScreenTap() {
        if controlsVisible {
            autoHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                controlsVisible = true
            }
            scheduleAutoHide()
        }
    }

    // MARK: - 时间线播放（自包含，基于 viewModel + player）

    /// 时间线滚动停止：把中心点换算为墙上时间，定位事件并从该位置起播 / seek。
    /// - Returns: 是否命中录像。返回 false 时提示"该时间点附近无录像"，时间线会自动回弹到上次位置。
    @discardableResult
    private func handleTimelineScrollEnd(_ centerSeconds: Double) -> Bool {
        guard !viewModel.selectedDay.isEmpty else { return true }
        guard let dayStart = CloudDateFormatters.yyyyMMdd.date(from: viewModel.selectedDay) else { return true }
        let wallMs = Int64(dayStart.addingTimeInterval(centerSeconds).timeIntervalSince1970 * 1000)
        guard let event = eventCovering(wallMs: wallMs), !event.isSnapshot else {
            showToast(L("No recording near this time"))
            return false
        }

        if currentEventId == event.id {
            player.seek(to: Double(wallMs - event.eventTimeMs) / 1000.0)
        } else {
            currentEventId = event.id
            player.start(with: event, fromWallMs: wallMs)
        }
        return true
    }

    /// 展示一条自动消失的轻提示（2 秒后清除）。
    private func showToast(_ text: String) {
        let token = UUID()
        toastToken = token
        withAnimation { toastMessage = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard toastToken == token else { return }
            withAnimation { toastMessage = nil }
        }
    }

    /// 点击时间线色块：从该事件起点起播。
    private func handleSegmentTap(_ event: CloudEventItem) {
        guard !event.isSnapshot else { return }
        currentEventId = event.id
        player.start(with: event)
    }

    /// 查找覆盖墙上时间 wallMs 的事件。
    private func eventCovering(wallMs: Int64) -> CloudEventItem? {
        if let hit = viewModel.events.first(where: { coversWallTimeStrict($0, wallMs: wallMs) }) {
            return hit
        }
        return viewModel.events.first(where: { coversWallTimeLoose($0, wallMs: wallMs) })
    }

    /// 当前播放进度对应的"日内秒数"：非 nil 时全屏时间线绿色时间标签实时跟随播放位置
    private var playbackSecondsOfDay: Double? {
        guard let id = currentEventId,
              let event = viewModel.events.first(where: { $0.id == id })
        else { return nil }
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.eventTimeMs) / 1000.0)
        return eventDate.secondsOfDay + player.currentTime
    }

    private func coversWallTimeStrict(_ event: CloudEventItem, wallMs: Int64) -> Bool {
        guard let first = event.videoFiles.first,
              let last = event.videoFiles.last else { return false }
        return wallMs >= first.startTimeMs && wallMs < last.endTimeMs
    }

    private func coversWallTimeLoose(_ event: CloudEventItem, wallMs: Int64) -> Bool {
        let startMs = event.videoFiles.first?.startTimeMs ?? event.eventTimeMs
        return wallMs >= startMs && wallMs < startMs + max(event.durationMs, 0)
    }
}

// MARK: - 全屏播放窗口控制器

/// 全屏播放宿主控制器：仅横屏，方向由 window 级门控（AppDelegate）配合锁定。
final class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscapeRight }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

/// 以标准模态转场（coverVertical）呈现云存全屏播放页，并同步旋转横屏 / 竖屏。
/// 标准动画 + 并行旋转，保证多次进出状态一致、动画稳定。
@MainActor
final class CloudFullscreenWindowController {
    static let shared = CloudFullscreenWindowController()

    private weak var hostingController: UIViewController?
    private var onDismissCompletion: (() -> Void)?
    private var isTransitioning = false

    private init() {}

    /// 呈现全屏播放页
    func present<Content: View>(rootView: Content, onDismiss: @escaping () -> Void) {
        guard hostingController == nil, !isTransitioning else { return }
        guard let topVC = Self.topMostViewController() else { return }

        isTransitioning = true
        // 全屏期间仅允许横屏（window 级门控），并主动旋转
        AppDelegate.setAllowedOrientations(.landscapeRight)
        Self.rotate(to: .landscapeRight)

        let host = LandscapeHostingController(rootView: rootView)
        // 使用 .overFullScreen：全屏期间不移除内嵌宿主视图，使其始终留在 window 层级，
        // 退出全屏后内嵌宿主可立即重建有效渲染表面，避免黑屏。
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .coverVertical
        hostingController = host
        onDismissCompletion = onDismiss
        topVC.present(host, animated: true) { [weak self] in
            self?.isTransitioning = false
        }
    }

    /// 关闭全屏播放页并恢复竖屏
    func dismiss() {
        guard let host = hostingController, !isTransitioning else { return }
        let completion = onDismissCompletion
        isTransitioning = true

        // 恢复竖屏门控并主动旋转，与 dismiss 转场并行
        AppDelegate.setAllowedOrientations(.portrait)
        Self.rotate(to: .portrait)

        host.dismiss(animated: true) { [weak self] in
            self?.hostingController = nil
            self?.onDismissCompletion = nil
            self?.isTransitioning = false
            completion?()
        }
    }

    /// 触发界面旋转到指定方向（带系统动画）
    private static func rotate(to orientation: UIInterfaceOrientation) {
        let mask: UIInterfaceOrientationMask = orientation.isLandscape ? .landscapeRight : .portrait

        if #available(iOS 16.0, *) {
            requestGeometryUpdateiOS16(mask: mask)
        } else {
            UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
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

    private static func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard let root = scene?.keyWindow?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
