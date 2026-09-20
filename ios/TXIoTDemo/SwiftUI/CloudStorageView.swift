//
//  CloudStorageView.swift
//  TXIoTDemo
//
//  云存储回看页面（主视图）：
//  - 顶部日期选择（getDayList）
//  - 事件列表（getEventList 分页）
//  - 点击事件通过 CloudVodPlayerController 在页内 / 全屏播放
//
//  其它依赖已拆分到独立文件：
//    - 数据模型 / DateFormatter   -> CloudStorageModels.swift
//    - ViewModel                  -> CloudStorageViewModel.swift
//    - 时间线控件                  -> CloudTimelineBar.swift
//    - 日期 Chip / 事件卡片        -> CloudEventCard.swift
//    - TXVodPlayer 控制器与桥接    -> CloudVodPlayerController.swift
//    - 内嵌 / Sheet / 全屏播放视图 -> CloudVideoPlayerViews.swift
//

import SwiftUI

// MARK: - 全屏时间线中心共享状态

/// 全屏时间线中心的共享引用：进入全屏时创建，全屏视图回调写入，退出全屏时读取。
/// 用 class（引用类型）是因为 struct View 的闭包捕获的是当时的拷贝，属性回写传不回 self。
private final class FullscreenCenterState {
    var seconds: Double = 0
}

// MARK: - 主视图

struct CloudStorageView: View {
    let device: Device

    /// 最多支持的通道数；超过时只显示前 maxChannelCount 个
    private static let maxChannelCount: Int = 4

    @StateObject private var viewModel: CloudStorageViewModel
    /// 内嵌视频播放器控制器（页面内播放，避免 sheet 跳转）
    @StateObject private var inlinePlayer = CloudVodPlayerController()
    @State private var channelId: Int
    @State private var playingEvent: CloudEventItem?
    /// 选中的事件 id：用于列表高亮 + 时间线高亮 + 双向滚动同步
    @State private var selectedEventId: UUID?
    /// 是否正在以全屏方式展示当前播放（全屏为独立 UIKit 模态，会触发本页 onDisappear）
    @State private var isPresentingFullscreen: Bool = false
    /// 时间线滚动请求（列表点击 / 列表滑动 -> 时间线）
    @State private var timelineScrollRequest: TimelineScrollRequest?
    /// 列表请求滚动到的事件 id（时间线 -> 列表）
    @State private var listScrollTarget: UUID?
    /// 当前列表滚动到的焦点事件 id（用户手指滑动列表 -> 时间线跟随）
    @State private var focusedEventId: UUID?
    /// 已自动定位到"第一个视频"的事件 id：同一天分页续拉不重复定位；切换日期列表重置后重新定位
    @State private var autoPositionedEventId: UUID?
    /// 当前正在内嵌位置查看的抓图事件（点击列表抓图卡片后展示在播放器同位置）
    @State private var viewingSnapshotEvent: CloudEventItem?
    /// 正在由时间线点击触发列表滚动，期间不反向驱动时间线，避免双向联动互相抢焦点
    @State private var isProgrammaticListScroll: Bool = false
    /// 轻提示文案（如拖动时间线到无录像处的提示），非 nil 时展示 Toast
    @State private var toastMessage: String?
    /// Toast 自动消失去抖 token，避免连续提示时被上一条提前清空
    @State private var toastToken: UUID?
    /// 内嵌时间线当前中心对应的"日内秒数"，进入全屏时用于对齐全屏时间线中心
    @State private var inlineCenterSeconds: Double = 0
    /// 全屏时间线中心的共享引用（退出全屏时读取最新值，把内嵌同步到该位置）。
    /// 仅在闭包间传递、不驱动 UI 重建，用普通属性即可。
    private let fullscreenCenter = FullscreenCenterState()
    /// 请求内嵌时间线定位到指定秒数（退出全屏时同步中心位置）
    @State private var inlineSecondsRequest: TimelineSecondsRequest?
    /// 时间线重置 token：刷新时变更，强制时间线整体重建（滚动位置 / 内部定位状态归零）
    @State private var timelineResetToken = UUID()

    init(device: Device, channelId: Int = 0) {
        self.device = device
        _channelId = State(initialValue: channelId)
        _viewModel = StateObject(
            wrappedValue: CloudStorageViewModel(device: device, channelId: channelId)
        )
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                navBar(topInset: geo.safeAreaInsets.top)
                Divider()

                ZStack {
                    LinearGradient(
                        colors: [Color.bgColor, Color.white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        inlinePlayerArea
                        dateScrollBar.padding(.top, 2)
                        timelineBar
                        pagingIndicator
                        Divider().padding(.top, 6)
                        content
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .preferredColorScheme(.light)
        .appToast(message: $toastMessage)
        .task {
            // 仅由 task 触发首屏加载，避免与 onAppear 双触发
            print(
                "☁️ CloudStorageView task triggered, productId=\(device.productId) deviceName=\(device.deviceName)"
            )
            guard viewModel.dayList.isEmpty, !viewModel.isLoadingDays else { return }
            viewModel.loadDayList()
        }
        .onChange(of: channelId) { newValue in
            viewModel.switchChannel(newValue)
            stopInlinePlayback()
            viewingSnapshotEvent = nil
        }
        .onChange(of: viewModel.events) { events in
            autoPositionTimelineToFirstVideo(events)
        }
        .onDisappear {
            // 全屏播放是真正的 UIKit 模态呈现，会触发本页 onDisappear；
            // 此时不能停止播放 / 锁竖屏，否则全屏画面会中断并转回竖屏。
            guard !isPresentingFullscreen else { return }
            stopInlinePlayback()
            viewingSnapshotEvent = nil
            OrientationManager.lockPortrait()
        }
    }

    // MARK: - 导航栏（渐变背景，与 Android 对齐：主标题前加在线状态点）

    private func navBar(topInset: CGFloat) -> some View {
        HStack(spacing: 0) {
            NavBackButton(action: { CloudStorageWindowController.shared.dismiss() })

            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(device.isOnline ? Color.successColor : Color.textDisabled)
                        .frame(width: 6, height: 6)
                    Text(device.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text("\(device.productId)/\(device.deviceName)")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    channelPicker
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: {
                // 立即停止播放 / 看图，清空选中态
                stopInlinePlayback()
                viewingSnapshotEvent = nil
                selectedEventId = nil
                focusedEventId = nil
                autoPositionedEventId = nil
                // 立即清空事件列表（时间线高亮随之消失）并作废在途分页链
                viewModel.prepareForRefresh()
                // 重建时间线：滚动位置与内部定位状态归零
                timelineResetToken = UUID()
                viewModel.loadDayList()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(height: 44)
        .padding(.top, compactTopInset(topInset))
        .background(Color.headerGradient)
    }

    /// 手动收紧顶部安全区留白：系统状态栏（含灵动岛）预留的安全区往往偏大，
    /// 这里只保留必要缓冲（避免与状态栏文字/图标重叠），其余部分主动收起，
    /// 从而缩小"状态栏和标题栏之间"的空白区域。
    private func compactTopInset(_ rawInset: CGFloat) -> CGFloat {
        max(rawInset - 10, 10)
    }

    // MARK: - 内嵌播放器

    /// 内嵌播放区域：未选中事件时显示占位提示；选中后展示视频与控制条；拓图事件则在同一位置展示图片
    @ViewBuilder
    private var inlinePlayerArea: some View {
        if playingEvent != nil {
            InlineCloudPlayerView(
                player: inlinePlayer,
                onFullscreen: { enterFullscreen() }
            )
            .frame(height: 220)
            .background(Color.black)
        } else if let snapshot = viewingSnapshotEvent {
            InlineSnapshotView(event: snapshot)
                .frame(height: 220)
                .background(Color.black)
        } else {
            inlinePlayerPlaceholder
        }
    }

    /// 进入全屏：通过 LandscapeHostingController 手动呈现，强制横屏。
    private func enterFullscreen() {
        isPresentingFullscreen = true
        // 记录全屏初始中心（= 内嵌当前中心）；全屏时间线定位后会通过回调写入共享引用，
        // 用户在全屏拖动后退出时也能同步到最新位置
        fullscreenCenter.seconds = inlineCenterSeconds
        let center = fullscreenCenter
        let rootView = FullscreenCloudPlayerView(
            player: inlinePlayer,
            viewModel: viewModel,
            initialEventId: playingEvent?.id,
            initialCenterSeconds: inlineCenterSeconds,
            onCenterSecondsChange: { center.seconds = $0 },
            onDismiss: { CloudFullscreenWindowController.shared.dismiss() }
        )
        CloudFullscreenWindowController.shared.present(rootView: rootView) {
            exitFullscreen()
        }
    }

    /// 退出全屏：主动把渲染交回内嵌宿主，避免“有声无画”，并把内嵌时间线同步到全屏当前位置
    private func exitFullscreen() {
        isPresentingFullscreen = false
        // 延迟到下一帧，确保全屏视图层级已经完全拆除
        DispatchQueue.main.async {
            inlinePlayer.requestReattach()
            // 同步到全屏当前中心位置
            inlineSecondsRequest = TimelineSecondsRequest(seconds: fullscreenCenter.seconds)
        }
    }

    private var inlinePlayerPlaceholder: some View {
        ZStack {
            Color.black
            VStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.5))
                Text(L("Tap an event below to start playing"))
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(height: 220)
    }

    private func stopInlinePlayback() {
        inlinePlayer.stop()
        playingEvent = nil
    }

    // MARK: - 通道选择

    /// 通道选择菜单：点击"通道 X"后弹出 0..<maxChannelCount 列表
    private var channelPicker: some View {
        Menu {
            ForEach(0..<Self.maxChannelCount, id: \.self) { idx in
                channelButton(for: idx)
            }
        } label: {
            HStack(spacing: 2) {
                Text(channelId == 0 ? L("No Channel") : L("Channel %ld", channelId))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primaryColor)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.primaryColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white)
            .cornerRadius(4)
        }
    }

    private func channelButton(for idx: Int) -> some View {
        let title = idx == 0 ? L("No Channel") : L("Channel %ld", idx)
        return Button(action: { channelId = idx }) {
            if idx == channelId {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    // MARK: - 全局加载指示

    /// 顶部轻量加载条：在分页拉取期间常驻显示，全部拉完后自动隐藏
    /// 例如首屏后后台仍在续拉时，用户能明确看到“还在加载”
    @ViewBuilder
    private var pagingIndicator: some View {
        if viewModel.isPagingAll && !viewModel.events.isEmpty {
            InlineLoader(message: L("Loading events · %ld loaded", viewModel.events.count))
                .padding(.horizontal, 16)
                .padding(.top, 5)
        }
    }

    // MARK: - 时间线

    /// 时间线列：24 小时刻度，有 event 的区间用蓝色高亮；中心固定绿色指示线
    @ViewBuilder
    private var timelineBar: some View {
        if !viewModel.dayList.isEmpty {
            CloudTimelineBar(
                events: viewModel.events,
                scrollRequest: timelineScrollRequest,
                onSegmentTap: { event in onTimelineTap(event) },
                onScrollEnd: { centerSeconds in
                    playFromTimelineCenter(centerSeconds: centerSeconds)
                },
                onCenterSecondsChange: { inlineCenterSeconds = $0 },
                secondsScrollRequest: inlineSecondsRequest,
                playbackSeconds: playbackSecondsOfDay
            )
            .id(timelineResetToken)
            .frame(height: 76, alignment: .top)
            .offset(y: 6)
        }
    }

    /// 当前播放进度对应的"日内秒数"（播放墙上时间 = 事件触发时刻 + 事件相对进度）。
    /// 非 nil 时时间线绿色时间标签实时跟随播放位置；inlinePlayer.currentTime 逐帧发布，驱动其实时刷新。
    private var playbackSecondsOfDay: Double? {
        guard let event = playingEvent else { return nil }
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.eventTimeMs) / 1000.0)
        return eventDate.secondsOfDay + inlinePlayer.currentTime
    }

    // MARK: - 日期选择

    private var dateScrollBar: some View {
        Group {
            if viewModel.isLoadingDays && viewModel.dayList.isEmpty {
                loadingDaysIndicator
            } else if viewModel.dayList.isEmpty {
                noDataIndicator
            } else {
                dateChipScrollView
            }
        }
    }

    private var loadingDaysIndicator: some View {
        InlineLoader(message: L("Loading days..."))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var noDataIndicator: some View {
        HStack {
            Image(systemName: "calendar.badge.exclamationmark").foregroundColor(.textDisabled)
            Text(L("No cloud storage data")).font(.system(size: 13)).foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var dateChipScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.dayList, id: \.self) { day in
                        dayChip(for: day, proxy: proxy)
                            .id(day)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            .onChange(of: viewModel.selectedDay) { newVal in
                withAnimation { proxy.scrollTo(newVal, anchor: .center) }
            }
        }
    }

    private func dayChip(for day: String, proxy: ScrollViewProxy) -> some View {
        DayChip(
            day: day,
            isSelected: viewModel.selectedDay == day,
            onTap: { selectDay(day, proxy: proxy) }
        )
    }

    /// 切换日期：与重新加载一致，先停止播放 / 看图并清空选中态，再加载新日期事件
    private func selectDay(_ day: String, proxy: ScrollViewProxy) {
        stopInlinePlayback()
        viewingSnapshotEvent = nil
        selectedEventId = nil
        focusedEventId = nil
        autoPositionedEventId = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.selectDay(day)
            proxy.scrollTo(day, anchor: .center)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingEvents && viewModel.events.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
                Text(L("Loading events..."))
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = viewModel.errorMessage, viewModel.events.isEmpty {
            errorView(message: msg)
        } else if visibleEvents.isEmpty {
            emptyView
        } else {
            eventList
        }
    }

    /// 列表中实际展示的事件：eventType 为空的不入列表（仅在时间线以色块呈现）
    private var visibleEvents: [CloudEventItem] {
        viewModel.events.filter { !$0.eventType.isEmpty }
    }
    private var eventList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ScrollOffsetReader(coordinateSpace: Self.eventListCoordinateSpace)
                eventListContent
            }
            .coordinateSpace(name: Self.eventListCoordinateSpace)
            .refreshable {
                viewModel.loadEvents(reset: true)
                await waitUntilPagingFinished()
            }
            .onChange(of: listScrollTarget) { target in
                handleListScrollTarget(target, proxy: proxy)
            }
        }
    }

    private func handleListScrollTarget(_ target: UUID?, proxy: ScrollViewProxy) {
        guard let id = target else { return }
        isProgrammaticListScroll = true
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isProgrammaticListScroll = false
        }
    }

    private var eventListContent: some View {
        LazyVStack(spacing: Self.eventCardSpacing) {
            ForEach(visibleEvents) { event in
                CloudEventCard(
                    event: event,
                    isSelected: selectedEventId == event.id,
                    onTap: { onListTap(event) }
                )
                .padding(.horizontal, Self.eventCardHorizontalPadding)
                .id(event.id)
            }
            eventListFooter
        }
        .padding(.top, Self.eventListTopPadding)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var eventListFooter: some View {
        if viewModel.hasMore {
            loadMoreFooter
        } else if !viewModel.events.isEmpty {
            Text(L("You've reached the end"))
                .font(.system(size: 11))
                .foregroundColor(.textDisabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    private static let eventCardSpacing: CGFloat = 12
    private static let eventCardHeight: CGFloat = 92
    private static let eventCardHorizontalPadding: CGFloat = 16
    private static let eventListTopPadding: CGFloat = 12
    private static let eventListCoordinateSpace = "CloudStorageEventListScroll"

    /// 根据 ScrollView 的真实滚动偏移计算当前视野范围内第一个可见事件。
    /// 这里不再依赖卡片的 onAppear/onDisappear 或 GeometryReader 坐标，避免 LazyVStack 预加载导致误判。
    private func updateFocusedCard(scrollOffset: CGFloat) {
        guard !isProgrammaticListScroll else { return }
        guard !visibleEvents.isEmpty else { return }

        let stride = Self.eventCardHeight + Self.eventCardSpacing
        let visibleTop = max(scrollOffset, Self.eventListTopPadding)
        let rawIndex = (visibleTop - Self.eventListTopPadding) / stride
        let index = min(max(Int(floor(rawIndex)), 0), visibleEvents.count - 1)
        let id = visibleEvents[index].id
        guard id != focusedEventId else { return }
        focusedEventId = id
        guard id != selectedEventId else { return }
        timelineScrollRequest = TimelineScrollRequest(eventId: id)
    }

    /// 自动分页时的底部状态指示：仅展示加载状态，不再承担触发请求的职责
    private var loadMoreFooter: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.8)
            Text(L("Loading remaining events..."))
        }
        .font(.system(size: 12))
        .foregroundColor(.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundColor(.textDisabled)
            Text(L("No events for this day"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textSecondary)
            Text(L("Try switching to another date"))
                .font(.system(size: 12))
                .foregroundColor(.textDisabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        ErrorStateView(message: message) {
            viewModel.loadDayList()
        }
    }

    // MARK: - 事件交互

    /// 加载云存事件后：若当天有视频文件，将时间线默认定位到第一个视频位置（仅定位展示，不起播）。
    /// 以事件 id 防重：同一天分页续拉（已定位事件仍在列表中）不重复定位，避免打断用户拖动；
    /// 切换日期后事件列表整体重置（旧 id 不在新列表中），自动重新定位到当天第一个视频。
    private func autoPositionTimelineToFirstVideo(_ events: [CloudEventItem]) {
        if let id = autoPositionedEventId, events.contains(where: { $0.id == id }) { return }
        guard let first = events.filter({ !$0.videoFiles.isEmpty }).min(by: { $0.eventTimeMs < $1.eventTimeMs }) else {
            return
        }
        autoPositionedEventId = first.id
        timelineScrollRequest = TimelineScrollRequest(eventId: first.id)
    }

    /// 点击时间线色块：选中 + 同步滚动列表，不直接起播
    private func onTimelineTap(_ event: CloudEventItem) {
        selectedEventId = event.id
        // 同上：允许重复点击同一色块时也能让列表重新定位
        listScrollTarget = nil
        DispatchQueue.main.async {
            self.listScrollTarget = event.id
        }
    }

    /// 点击列表卡片：选中 + 同步滚动时间线 + 起播（拓图事件则在播放器同位置展示图片）
    private func onListTap(_ event: CloudEventItem) {
        selectedEventId = event.id
        timelineScrollRequest = TimelineScrollRequest(eventId: event.id)
        if event.isSnapshot {
            stopInlinePlayback()
            viewingSnapshotEvent = event
        } else {
            viewingSnapshotEvent = nil
            playEvent(event)
        }
    }

    private func playEvent(_ event: CloudEventItem) {
        guard !event.videoFiles.isEmpty else {
            print("CloudStorage - event has no video files")
            return
        }
        playingEvent = event
        // 控制器内部会自行 stopPlay 并按事件起点切到对应文件
        inlinePlayer.start(with: event)
    }

    // MARK: - 时间线滚动停止起播

    /// 时间线滚动停止后：把中心点（日内秒数）换算为墙上时间，找到覆盖该时刻的事件并从该位置起播。
    /// - Returns: 是否命中录像。返回 false 时提示"该时间点附近无录像"，时间线会自动回弹到上次位置。
    @discardableResult
    private func playFromTimelineCenter(centerSeconds: Double) -> Bool {
        guard !viewModel.selectedDay.isEmpty else { return true }
        guard let dayStart = CloudDateFormatters.yyyyMMdd.date(from: viewModel.selectedDay) else {
            return true
        }
        let wallMs = Int64(dayStart.addingTimeInterval(centerSeconds).timeIntervalSince1970 * 1000)
        guard let event = eventCovering(wallMs: wallMs), !event.isSnapshot else {
            showToast(L("No recording near this time"))
            return false
        }

        viewingSnapshotEvent = nil
        selectedEventId = event.id
        playOrSeekToEvent(event, wallMs: wallMs)
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

    /// 播放或 seek 到目标事件：同一事件仅 seek，不同事件则重新起播
    private func playOrSeekToEvent(_ event: CloudEventItem, wallMs: Int64) {
        if playingEvent?.id == event.id {
            inlinePlayer.seek(to: Double(wallMs - event.eventTimeMs) / 1000.0)
        } else {
            playingEvent = event
            inlinePlayer.start(with: event, fromWallMs: wallMs)
        }
    }

    /// 查找覆盖墙上时间 wallMs 的事件：按事件时长计算覆盖区间。
    private func eventCovering(wallMs: Int64) -> CloudEventItem? {
        viewModel.events.first(where: { coversWallTime($0, wallMs: wallMs) })
    }

    /// 判断某事件是否覆盖给定墙上时间。
    /// 覆盖区间按“事件时长”计算，与时间线色块绘制方式一致：
    /// 起点取事件发生时刻 eventTimeMs，时长取事件自身 durationMs，
    /// 与视频文件无关（视频文件与事件是多对多关系）。
    private func coversWallTime(_ event: CloudEventItem, wallMs: Int64) -> Bool {
        wallMs >= event.eventTimeMs && wallMs < event.eventTimeMs + max(event.durationMs, 0)
    }

    /// 等待自动分页链路彻底结束，用于下拉刷新指示器持续显示直到全部加载完成
    /// 采用主线程轮询，每 100ms 检查一次 isPagingAll；最长等待 30s 防止异常情况下卡死
    private func waitUntilPagingFinished() async {
        let start = Date()
        while viewModel.isPagingAll {
            if Date().timeIntervalSince(start) > 30 { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

// MARK: - 列表滚动偏移辅助类型（仅本文件内使用）

/// 放在 ScrollView 内容顶部的零高哨兵，用于读取真实滚动偏移
private struct ScrollOffsetReader: View {
    let coordinateSpace: String

    var body: some View {
        GeometryReader { proxy in
            let offset = -proxy.frame(in: .named(coordinateSpace)).minY
            Color.clear.preference(key: ScrollOffsetKey.self, value: offset)
        }
        .frame(height: 0)
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 云存页面控制器

/// 以标准模态方式全屏展示云存回看页。
/// 使用系统自带的 modal 转场动画（coverVertical），无需手动管理 UIWindow / keyWindow。
@MainActor
final class CloudStorageWindowController {
    static let shared = CloudStorageWindowController()

    private weak var hostingController: UIViewController?

    private init() {}

    /// 展示云存回看页（标准模态动画）
    func present(device: Device, channelId: Int = 0) {
        guard hostingController == nil else { return }
        guard let topVC = Self.topMostViewController() else {
            print("[CloudStorageWindowController] No available ViewController found")
            return
        }

        let host = UIHostingController(
            rootView: CloudStorageView(device: device, channelId: channelId)
        )
        host.view.backgroundColor = .systemBackground
        host.modalPresentationStyle = .fullScreen
        host.modalTransitionStyle = .coverVertical
        // 隐藏系统返回手势的边缘滑动（页面已有自己的返回按钮）
        if #available(iOS 16.0, *) {
            host.isModalInPresentation = false
        }
        hostingController = host
        topVC.present(host, animated: true)
        print("[CloudStorageWindowController] Cloud storage page presented")
    }

    /// 关闭云存回看页（标准模态动画）
    func dismiss() {
        guard let host = hostingController else { return }
        host.dismiss(animated: true) { [weak self] in
            self?.hostingController = nil
            print("[CloudStorageWindowController] Cloud storage page dismissed")
        }
    }

    /// 获取当前最顶层的 ViewController（遍历 presentedViewController 链）
    private static func topMostViewController() -> UIViewController? {
        guard let scene = activeWindowScene(),
              let root = scene.keyWindow?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// 选取当前活跃的 windowScene（优先前台活跃场景）
    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }
}
