//
//  CloudTimelineBar.swift
//  TXIoTDemo
//
//  云存时间线控件：横向 24 小时刻度，在有事件/视频的区间以蓝色高亮。
//  默认一屏展示 1.5 小时（占满可见宽度），无缩放按钮；
//  灰色轨道 + 绿色播放位置指示线（含时间标签）。
//

import SwiftUI
import UIKit

/// 时间线滚动请求：通过 token 保证即使同一事件重复请求，也会触发 onChange
struct TimelineScrollRequest: Equatable {
    let eventId: UUID
    let token = UUID()
}

/// 按"日内秒数"定位时间线中心的请求：通过 token 保证同值重复请求也会触发 onChange。
/// 用于全屏退出后把内嵌时间线中心同步到全屏的中心位置。
struct TimelineSecondsRequest: Equatable {
    let seconds: Double
    let token = UUID()
}

// MARK: - 时间线主题

/// 时间线主题：非全屏使用白色主题（.light），全屏使用黑色主题（.dark）
enum TimelineTheme {
    /// 白色主题（页面内嵌，浅色背景）
    case light
    /// 黑色主题（全屏播放，深色背景）
    case dark

    /// 轨道底色（灰色背景条）
    var trackBackground: Color {
        switch self {
        case .light:
            return Color(red: 0xE3 / 255, green: 0xE5 / 255, blue: 0xEA / 255)
        case .dark:
            return Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
        }
    }

    /// 刻度文字颜色
    var tickLabel: Color {
        switch self {
        case .light:
            return .textSecondary
        case .dark:
            return .white.opacity(0.6)
        }
    }

    /// 刻度线颜色
    var tickLine: Color {
        switch self {
        case .light:
            return .textDisabled.opacity(0.6)
        case .dark:
            return .white.opacity(0.4)
        }
    }

    /// 事件色块颜色
    var segment: Color {
        .primaryColor
    }

    /// 时间线面板背景色
    var panelBackground: Color {
        switch self {
        case .light:
            return .white
        case .dark:
            return Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
        }
    }

    /// 时间线面板边框色
    var panelBorder: Color {
        switch self {
        case .light:
            return .borderColor
        case .dark:
            return .white.opacity(0.1)
        }
    }
}

// MARK: - 时间线控件

/// 云存时间线：横向 24 小时刻度，在有事件/视频的区间以蓝色高亮
struct CloudTimelineBar: View {
    let events: [CloudEventItem]
    /// 外部请求滚动到的事件（带 token，保证同一 event 重复请求也能触发）
    let scrollRequest: TimelineScrollRequest?
    let onSegmentTap: (CloudEventItem) -> Void
    /// 时间线滚动停止后的回调，参数为中心点对应的"日内秒数"（0~86400）。
    /// 返回值表示该时间点是否命中录像：返回 false 时，时间线会自动回弹到上一次有效位置。
    let onScrollEnd: (Double) -> Bool
    /// 时间线主题：默认白色主题，全屏播放时使用黑色主题
    var theme: TimelineTheme = .light
    /// 是否在首次加载后自动把中心线定位到"第一个有视频的时间点"
    var autoPositionToFirstVideo: Bool = false
    /// 若设置，则首次布局完成后把中心线精确定位到该"日内秒数"（0~86400）；
    /// 优先级高于 autoPositionToFirstVideo，用于全屏时间线与内嵌时间线中心完全对齐。
    var autoPositionToSeconds: Double? = nil
    /// 中心秒数变化回调：中心线对应的"日内秒数"变化时上报，供外部（如进入全屏）读取当前中心位置。
    var onCenterSecondsChange: ((Double) -> Void)? = nil
    /// 按"日内秒数"定位中心线的请求（带 token 可重复触发）；用于全屏退出后同步中心位置。
    var secondsScrollRequest: TimelineSecondsRequest? = nil
    /// 播放进度对应的"日内秒数"：非 nil 时绿色时间标签实时跟随播放位置，
    /// 且时间线跟随播放实时滚动（用户拖动 / 惯性滑行期间暂停跟随，不抢手势）。
    var playbackSeconds: Double? = nil

    /// 默认一屏展示的小时数：1.5 小时（1 个半钟）占满整个可见宽度
    private static let hoursPerScreen: CGFloat = 1.5

    /// ScrollView 实际可见宽度（用于计算中心点）
    @State private var scrollViewWidth: CGFloat = 0
    /// 当前滚动偏移（content 左边相对 ScrollView 左边的距离）
    @State private var scrollOffset: CGFloat = 0
    /// 待应用的 contentOffset.x（回弹到指定位置时使用），应用完成后清空
    @State private var pendingOffsetX: CGFloat?
    /// 滚动停止检测：debounce 计时器
    @State private var scrollEndWorkItem: DispatchWorkItem?
    /// 程序化滚动（scrollTo）抑制窗口截止时间；
    /// 在此之前的滚动停止不触发 onScrollEnd，避免列表点击后重复起播。
    @State private var programmaticScrollDeadline: Date = Date().addingTimeInterval(1.2)
    /// 上一次命中录像的中心"日内秒数"，用于拖到无录像处时回弹。
    @State private var lastValidSeconds: Double = 0
    /// 已完成自动定位的"第一个有视频事件"的 id。
    /// 以事件 id 为键：切换日期后事件列表整体重置（旧 id 不在新列表中）会重新定位；
    /// 同一天分页续拉（旧 id 仍在列表中）不重复定位，避免打断用户后续拖动。
    @State private var positionedEventId: UUID?
    /// 是否已完成 autoPositionToSeconds 精确定位（全屏对齐内嵌中心），仅执行一次。
    @State private var didAutoPosition: Bool = false
    /// 目标中心"日内秒数"（唯一真相）：宽度变化（旋转 / 进出全屏）时按新宽度重算偏移以保持该中心时间不变。
    @State private var targetCenterSeconds: Double?
    /// 用户是否正在拖动时间线：拖动期间绿色时间标签显示拖动位置而非播放位置
    @State private var isUserDragging: Bool = false
    /// 用户是否正在拖动 / 惯性滑行时间线（由 Tracker 经 UIScrollView 状态实时上报）：
    /// 播放跟随期间据此避让，不与手势抢位置
    @State private var isUserInteracting: Bool = false
    /// 用户滚动停止并触发 seek 后的收敛目标（落点的日内秒数）：非 nil 期间抑制播放跟随，
    /// 直到播放进度真正推进到落点（或超时兜底），避免 seek 生效前的旧播放进度把落点冲掉
    @State private var seekConvergeTarget: Double?
    /// 收敛等待的最晚截止时间：seek 未生效等异常情况下约 3s 后恢复跟随，避免永久抑制
    @State private var seekConvergeDeadline: Date = .distantPast

    /// 每小时宽度：按可见宽度动态计算，使 hoursPerScreen 小时正好占满一屏。
    /// 宽度未就绪时回退到 60，避免除零。
    private var hourWidth: CGFloat {
        guard scrollViewWidth > 0 else { return 60 }
        return scrollViewWidth / Self.hoursPerScreen
    }

    /// 刻度文字高度
    private let labelHeight: CGFloat = 14
    /// 刻度线高度
    private let tickHeight: CGFloat = 6
    /// 轨道（灰色背景条）高度
    private let trackHeight: CGFloat = 26
    /// 刻度区域顶部预留的空白（增大刻度线到背景顶部的距离）
    private let topInset: CGFloat = 14
    /// 每个刻度文字列所占宽度（用于居中对齐）
    private let columnWidth: CGFloat = 50
    /// 轨道底部与播放指示时间标签之间的间距
    private let bubbleGap: CGFloat = 3
    /// 时间标签自身高度
    private let bubbleHeight: CGFloat = 16

    /// 刻度 + 轨道区域高度（含顶部预留空白，不含底部播放时间标签）
    private var contentHeight: CGFloat { topInset + labelHeight + tickHeight + trackHeight }
    /// 组件总高度
    var totalHeight: CGFloat { contentHeight + bubbleGap + bubbleHeight }

    /// 中心点对应的秒数（0 ~ 86400）。
    /// 优先使用"目标中心秒数"（稳定、精确，跨旋转/进出全屏持续保持），
    /// 避免动画/旋转补间期间因实时 scrollOffset 换算造成的时间漂移；用户拖动时按实时滚动计算。
    private var centerSeconds: Double {
        if let target = targetCenterSeconds { return target }
        return realTimeCenterSeconds
    }

    /// 按实时 scrollOffset 换算的中心秒数（用于用户拖动跟手更新）。
    private var realTimeCenterSeconds: Double {
        guard scrollViewWidth > 0, hourWidth > 0 else { return 0 }
        // 内容两端各加 edgeInset（= scrollViewWidth/2）的填充，
        // 因此 00:00 起点相对 ScrollView 内容左边缘偏移 edgeInset。
        let centerX = scrollOffset + scrollViewWidth / 2 - edgeInset
        let totalSec = centerX / hourWidth * 3600
        return min(max(totalSec, 0), 86400)
    }

    /// 内容两端的内边距：等于可见宽度的一半，使 00:00 与 24:00 能滚到中心指示线。
    private var edgeInset: CGFloat { scrollViewWidth / 2 }

    /// 中心点对应的格式化时间字符串：拖动中显示拖动位置；seek 收敛等待中显示落点；
    /// 其余情况播放中优先显示实时播放位置
    private var centerTimeText: String {
        let seconds = isUserDragging ? centerSeconds : (seekConvergeTarget ?? playbackSeconds ?? centerSeconds)
        let total = Int(min(max(seconds, 0), 86400))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// 滚动停止检测：每次 offset 变化都重置 debounce，静默 0.35s 后视为停止并回调中心时间。
    private func scheduleScrollEnd() {
        scrollEndWorkItem?.cancel()
        let work = DispatchWorkItem {
            // isUserDragging 为 true 表示刚结束的是用户手势：必须放行本次 onScrollEnd，
            // 不能被播放跟随刷新的抑制窗（programmaticScrollDeadline）拦截，
            // 否则播放中较短的拖动会因抑制窗未过期而被静默丢弃
            let wasUserDrag = isUserDragging
            isUserDragging = false
            guard wasUserDrag || Date() > programmaticScrollDeadline else { return }
            let seconds = centerSeconds
            if onScrollEnd(seconds) {
                // 命中录像：记录为最新有效位置，并把用户拖动后的落点作为新的目标中心
                lastValidSeconds = seconds
                targetCenterSeconds = seconds
                // 进入收敛等待：播放进度推进到落点之前抑制播放跟随，
                // 避免 seek 生效前的旧进度刷新把落点冲掉
                seekConvergeTarget = seconds
                seekConvergeDeadline = Date().addingTimeInterval(3)
            } else {
                // 未命中录像：回弹到上一次有效位置（本次无 seek，取消收敛等待）
                seekConvergeTarget = nil
                restore(to: lastValidSeconds)
            }
        }
        scrollEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// 将时间线中心线回弹到指定"日内秒数"（无录像时使用）。
    /// 设置抑制窗口，避免回弹引发的滚动停止再次触发 onScrollEnd。
    private func restore(to seconds: Double) {
        targetCenterSeconds = seconds
        programmaticScrollDeadline = Date().addingTimeInterval(0.8)
        withAnimation(.easeInOut(duration: 0.25)) {
            pendingOffsetX = CGFloat(seconds / 3600.0) * hourWidth
        }
    }

    /// 加载后把中心线定位到初始目标（优先精确秒数，其次第一个有视频的事件）。
    /// 仅定位展示，不触发起播（设置抑制窗口拦截由此引发的 onScrollEnd）。
    private func positionToInitialTargetIfNeeded() {
        guard scrollViewWidth > 0 else { return }

        // 优先按精确秒数定位（全屏对齐内嵌时间线中心），仅执行一次
        if let seconds = autoPositionToSeconds {
            guard !didAutoPosition else { return }
            didAutoPosition = true
            applyInitialPosition(seconds: seconds)
            return
        }

        // 已定位事件仍在列表中（同一天分页续拉 / 用户已点击定位过）：不重复定位，避免打断拖动
        if let positionedId = positionedEventId,
           events.contains(where: { $0.id == positionedId }) {
            return
        }

        // 首屏加载完成 / 切换日期（列表整体重置）后：定位到第一个有视频的事件发生时刻。
        guard let event = firstVideoEvent else { return }
        positionedEventId = event.id
        applyInitialPosition(seconds: secondsOfDay(from: event.eventDate))
    }

    /// 应用初始定位：设置抑制窗口并把中心线滚到指定"日内秒数"。
    private func applyInitialPosition(seconds: Double) {
        targetCenterSeconds = seconds
        programmaticScrollDeadline = Date().addingTimeInterval(0.8)
        lastValidSeconds = seconds
        pendingOffsetX = CGFloat(seconds / 3600.0) * hourWidth
    }

    /// 第一个有视频的事件（按开始时间取最早，无视频事件时返回 nil）
    private var firstVideoEvent: CloudEventItem? {
        guard autoPositionToFirstVideo else { return nil }
        return events.filter { !$0.videoFiles.isEmpty }.min(by: { $0.eventTimeMs < $1.eventTimeMs })
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Color.clear.frame(width: edgeInset)
                ZStack(alignment: .topLeading) {
                    hourTicks
                    trackBackground
                    segmentLayer
                    TimelineScrollOffsetTracker(
                        offset: $scrollOffset,
                        pendingOffsetX: $pendingOffsetX,
                        isUserInteracting: $isUserInteracting
                    )
                    .frame(width: 0, height: 0)
                }
                .frame(width: hourWidth * 24, height: contentHeight, alignment: .topLeading)
                Color.clear.frame(width: edgeInset)
            }
        }
        // 将 ScrollView 高度固定为内容高度，避免横向 ScrollView 在更高的父容器中
        // 沿竖直（cross axis）居中，导致内部轨道与 .top 对齐的绿色指示线错位。
        .frame(height: contentHeight)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { scrollViewWidth = geo.size.width }
                    .onChange(of: geo.size.width) { scrollViewWidth = $0 }
            }
        )
        .background(
            theme.panelBackground
                .padding(.top, -6)
                .padding(.bottom, -bubbleHeight)
        )
        .overlay(
            Rectangle()
                .stroke(theme.panelBorder, lineWidth: 0.5)
                .padding(.top, -6)
                .padding(.bottom, -bubbleHeight)
        )
        .overlay(alignment: .top) {
            centerIndicator
                .allowsHitTesting(false)
        }
        .onChange(of: scrollRequest) { request in
            guard let id = request?.eventId,
                  let event = events.first(where: { $0.id == id }) else { return }
            // 精确把中心线对准该事件的发生时刻（按秒数换算偏移）
            let seconds = secondsOfDay(from: event.eventDate)
            // 记录已定位事件，避免自动定位（第一个视频）覆盖用户点击
            positionedEventId = event.id
            applyInitialPosition(seconds: seconds)
        }
        .onChange(of: scrollOffset) { _ in
            scheduleScrollEnd()
            // 用户拖动 / 惯性滑行（或抑制窗口外的其它滚动）期间，实时把目标中心跟手更新，
            // 保证中心时间标签跟随拖动连续变化；程序化 / 播放跟随滚动不动目标，保持时间稳定。
            if isUserInteracting || Date() > programmaticScrollDeadline {
                isUserDragging = true
                targetCenterSeconds = realTimeCenterSeconds
            }
        }
        .onChange(of: targetCenterSeconds) { newValue in
            // 目标中心（精确指令值）变化时上报，避免用回读的像素换算值造成多次切换后累计漂移
            if let seconds = newValue { onCenterSecondsChange?(seconds) }
        }
        .onChange(of: scrollViewWidth) { newWidth in
            guard newWidth > 0 else { return }
            if let target = targetCenterSeconds {
                // 宽度变化（旋转 / 进出全屏）：按新宽度重算偏移，保持中心时间不变
                programmaticScrollDeadline = Date().addingTimeInterval(0.8)
                pendingOffsetX = CGFloat(target / 3600.0) * hourWidth
            } else {
                positionToInitialTargetIfNeeded()
            }
        }
        // 观察"第一个有视频事件"的 id 而非 events.count：
        // 切换日期时若两天事件数相同，count 不变会漏触发；id 变化则必然触发
        .onChange(of: firstVideoEvent?.id) { _ in
            positionToInitialTargetIfNeeded()
        }
        .onChange(of: secondsScrollRequest) { req in
            guard let seconds = req?.seconds else { return }
            applyInitialPosition(seconds: seconds)
        }
        .onChange(of: playbackSeconds) { seconds in
            followPlaybackIfNeeded(seconds)
        }
    }

    /// 播放驱动的时间线跟随：播放中绿色指示线实时对准播放位置，刻度时间戳随之滚动。
    /// 用户正在拖动 / 惯性滑行时跳过，避免与手势抢位置；滚动停止后的 seek 会让播放位置
    /// 跳到用户落点，跟随自然从新位置继续。
    /// 注意必须同时检查 isUserDragging：松手后 isUserInteracting 约 0.1s 即收回，
    /// 而滚动停止判定需 0.35s debounce；空窗期内若恢复跟随，会把时间线拽回播放位置
    /// 并刷新程序化滚动抑制窗，导致 debounce 被拦截、onScrollEnd 永不触发（无法 seek）。
    /// isUserDragging 在 debounce 执行时才复位，恰好封住这段空窗。
    private func followPlaybackIfNeeded(_ seconds: Double?) {
        guard let seconds, !isUserInteracting, !isUserDragging, scrollViewWidth > 0 else { return }
        // 收敛等待中：仅当播放进度真正推进到用户落点（或超时兜底）后才恢复跟随，
        // 否则旧播放位置的刷新会把时间线从落点拽走，导致 seek 无法生效
        if let convergeTarget = seekConvergeTarget {
            let converged = abs(seconds - convergeTarget) <= 2
            guard converged || Date() > seekConvergeDeadline else { return }
            seekConvergeTarget = nil
        }
        // 标记为程序化滚动：抑制由此引发的 onScrollEnd，且不被误判为用户拖动
        programmaticScrollDeadline = Date().addingTimeInterval(0.6)
        targetCenterSeconds = seconds
        // 跟随期间当前位置必为录像区，作为拖空时的回弹落点
        lastValidSeconds = seconds
        pendingOffsetX = CGFloat(seconds / 3600.0) * hourWidth
    }

    /// 固定在 ScrollView 中心的绿色指示线 + 时间标签
    private var centerIndicator: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.successColor)
                .frame(width: 1.5, height: contentHeight - topInset)
            Text(centerTimeText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.successColor)
                .cornerRadius(3)
        }
        .offset(y: topInset)
    }

    // MARK: 子图层

    /// 轨道底色（灰色背景条），位于刻度区域下方
    private var trackBackground: some View {
        Rectangle()
            .fill(theme.trackBackground)
            .frame(width: hourWidth * 24, height: trackHeight)
            .offset(x: 0, y: topInset + labelHeight + tickHeight)
            .allowsHitTesting(false)
    }

    /// 事件叠加的蓝色色块
    private var segmentLayer: some View {
        ForEach(events) { event in
            TimelineSegmentView(
                rect: segmentRect(for: event),
                trackHeight: trackHeight,
                color: theme.segment,
                onTap: { onSegmentTap(event) }
            )
            .offset(x: 0, y: topInset + labelHeight + tickHeight)
        }
    }

    /// 24 小时刻度：每小时一个文字标签，逐小时细刻度线
    private var hourTicks: some View {
        ForEach(0..<25, id: \.self) { hour in
            tickColumn(hour: hour)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func tickColumn(hour: Int) -> some View {
        VStack(spacing: 2) {
            if hour < 24 {
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(theme.tickLabel)
            } else {
                Color.clear.frame(height: labelHeight)
            }
            Rectangle()
                .fill(theme.tickLine)
                .frame(width: 1, height: tickHeight)
        }
        .frame(width: columnWidth, height: labelHeight + tickHeight, alignment: .center)
        .offset(x: CGFloat(hour) * hourWidth - columnWidth / 2, y: topInset)
    }

    // MARK: 位置计算

    /// 计算某事件在轨道上的 (x, width)：起点取事件发生时刻，长度取事件自身时长。
    /// 色块右边界裁剪到 24:00（hourWidth * 24），避免跨午夜事件延伸到时间线之外。
    private func segmentRect(for event: CloudEventItem) -> (x: CGFloat, width: CGFloat) {
        let startSec = secondsOfDay(from: event.eventDate)
        let durationSec = max(Double(event.durationMs) / 1000.0, 30)  // 最小 30s 以保证可见
        let pxPerSec = hourWidth / 3600.0
        let x = CGFloat(startSec) * pxPerSec
        let endX = min(x + CGFloat(durationSec) * pxPerSec, hourWidth * 24)
        let w = max(endX - x, 3)
        return (x, w)
    }

    private func secondsOfDay(from date: Date) -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        var seconds = (comps.hour ?? 0) * 3600
        seconds += (comps.minute ?? 0) * 60
        seconds += (comps.second ?? 0)
        return Double(seconds)
    }
}

// MARK: - UIScrollView 滚动偏移追踪器

/// 通过传统 KVO（`addObserver`）实时追踪 ScrollView 内部 UIScrollView 的 contentOffset.x，
/// 确保拖动过程中绿色时间标签能逐帧更新。
/// 注：Swift 6 严格并发下 `\.contentOffset` key path 无法跨 actor 隔离使用，
/// 因此回退到 `NSKeyValueObservation` 的底层 `addObserver(for:options:context:)` API。
private struct TimelineScrollOffsetTracker: UIViewRepresentable {
    @Binding var offset: CGFloat
    /// 程序化设置 contentOffset.x 的请求（回弹 / 定位 / 播放跟随），应用完成后由内部清空
    @Binding var pendingOffsetX: CGFloat?
    /// 用户是否正在拖动 / 惯性滑行（取自 UIScrollView.isDragging / isDecelerating）
    @Binding var isUserInteracting: Bool

    func makeUIView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.coordinator = context.coordinator
        view.attachToScrollView(retriesLeft: 10)
        return view
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {
        // 每次 SwiftUI 重建 struct 时，把最新的 Binding 更新到 Coordinator
        context.coordinator.offsetBinding = Binding(
            get: { self.offset },
            set: { self.offset = $0 }
        )
        context.coordinator.interactionBinding = Binding(
            get: { self.isUserInteracting },
            set: { self.isUserInteracting = $0 }
        )
        // 有待应用的偏移时，交给 TrackerView 内部保存并在就绪后应用；
        // 这里立即清空绑定即可（目标值已被 TrackerView 持有，不会丢失）。
        if let target = pendingOffsetX {
            uiView.scheduleOffset(target)
            DispatchQueue.main.async { self.pendingOffsetX = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var offsetBinding: Binding<CGFloat>?
        var interactionBinding: Binding<Bool>?

        func update(_ value: CGFloat, userDriven: Bool) {
            if interactionBinding?.wrappedValue != userDriven {
                interactionBinding?.wrappedValue = userDriven
            }
            offsetBinding?.wrappedValue = value
        }
    }

    /// 自定义 UIView：通过传统 KVO 注册观察 contentOffset，回调同步触发
    final class TrackerView: UIView {
        nonisolated(unsafe) weak var coordinator: Coordinator?
        private weak var observedScrollView: UIScrollView?
        /// 待应用的目标偏移；在 ScrollView 绑定且 contentSize 就绪前一直保留，避免被丢弃或 clamp 到 0
        private var pendingTargetX: CGFloat?
        // KVO 通过 @objc 运行时分发回调 observeValue，编译器将其视为 nonisolated；
        // contentOffset 变更始终在主线程触发，此处仅用作上下文比对指针，标记 nonisolated(unsafe) 以消除跨 actor 访问告警。
        nonisolated(unsafe) private var observerContext = 0

        func attachToScrollView(retriesLeft: Int) {
            guard observedScrollView == nil else { return }

            if let scrollView = findParentScrollView() {
                bindTo(scrollView: scrollView)
                return
            }

            // 首次创建时视图层级可能尚未挂载完成，延迟重试
            guard retriesLeft > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.attachToScrollView(retriesLeft: retriesLeft - 1)
            }
        }

        /// 向上遍历视图链查找 UIScrollView
        private func findParentScrollView() -> UIScrollView? {
            var current: UIView? = self
            while let v = current {
                if let sv = v as? UIScrollView { return sv }
                current = v.superview
            }
            return nil
        }

        /// 绑定 KVO 观察并报告初始偏移值
        private func bindTo(scrollView: UIScrollView) {
            observedScrollView = scrollView
            scrollView.addObserver(
                self,
                forKeyPath: "contentOffset",
                options: [.new],
                context: &observerContext
            )
            coordinator?.update(scrollView.contentOffset.x, userDriven: false)
        }

        deinit {
            observedScrollView?.removeObserver(self, forKeyPath: "contentOffset")
        }

        /// 程序化设置 contentOffset.x（回弹 / 定位）。
        /// 保存目标偏移并轮询等待：ScrollView 绑定成功且 contentSize 就绪后再应用，
        /// 否则（如全屏刚出现、布局未完成）会被 clamp 到 0 或直接丢弃，导致时间线停在 00:00。
        func scheduleOffset(_ x: CGFloat) {
            pendingTargetX = x
            applyPendingOffset(retriesLeft: 40)
        }

        private func applyPendingOffset(retriesLeft: Int) {
            guard let x = pendingTargetX else { return }

            // ScrollView 尚未绑定，或 contentSize 尚未就绪（目标为正但可滚动范围为 0）：稍后重试
            let sv = observedScrollView
            let notReady = sv == nil
                || (x > 0 && (sv!.contentSize.width - sv!.bounds.width) <= 0)
            if notReady {
                guard retriesLeft > 0 else { pendingTargetX = nil; return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                    self?.applyPendingOffset(retriesLeft: retriesLeft - 1)
                }
                return
            }

            let maxX = max(sv!.contentSize.width - sv!.bounds.width, 0)
            let clamped = min(max(x, 0), maxX)
            sv!.setContentOffset(CGPoint(x: clamped, y: sv!.contentOffset.y), animated: false)
            pendingTargetX = nil
        }

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard context == &observerContext,
                  let newOffset = change?[.newKey] as? CGPoint,
                  let scrollView = object as? UIScrollView
            else { return }
            // contentOffset 的 KVO 回调始终在主线程触发
            MainActor.assumeIsolated {
                let userDriven = scrollView.isDragging || scrollView.isDecelerating
                coordinator?.update(newOffset.x, userDriven: userDriven)
                // 拖动 / 惯性结束后不会再触发 contentOffset 变化，需主动轮询把"交互中"状态收回
                if userDriven { scheduleInteractionEndCheck() }
            }
        }

        /// 是否正在轮询等待用户交互结束（避免重复调度）
        private var isPollingInteractionEnd = false

        /// 轮询检测拖动 / 惯性滑行结束：结束后补报一次 userDriven = false，
        /// 否则"用户交互中"状态会停留在 true，导致播放跟随被永久抑制。
        private func scheduleInteractionEndCheck() {
            guard !isPollingInteractionEnd else { return }
            isPollingInteractionEnd = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                isPollingInteractionEnd = false
                guard let scrollView = observedScrollView else { return }
                if scrollView.isDragging || scrollView.isDecelerating {
                    scheduleInteractionEndCheck()
                } else {
                    coordinator?.update(scrollView.contentOffset.x, userDriven: false)
                }
            }
        }
    }
}

// MARK: - 时间线色块子视图

/// 单个事件色块：拆出为独立 View 避免父 body 表达式过复杂导致 type-check 超时
private struct TimelineSegmentView: View {
    let rect: (x: CGFloat, width: CGFloat)
    let trackHeight: CGFloat
    let color: Color
    let onTap: () -> Void

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: rect.width, height: trackHeight)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .offset(x: rect.x, y: 0)
    }
}
