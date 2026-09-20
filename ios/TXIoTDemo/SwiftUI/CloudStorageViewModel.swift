//
//  CloudStorageViewModel.swift
//  TXIoTDemo
//
//  云存回看主视图的 ViewModel：日期列表、事件分页加载等。
//

import Foundation
import TXLiteAVSDK_IOT

@MainActor
final class CloudStorageViewModel: ObservableObject {
    @Published var dayList: [String] = []
    @Published var selectedDay: String = ""
    @Published var events: [CloudEventItem] = []

    @Published var isLoadingDays: Bool = false
    @Published var isLoadingEvents: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?

    @Published private(set) var nextPageToken: String? = nil
    @Published private(set) var hasMore: Bool = false

    /// 整体加载状态：首屏拉取中 或 自动续拉中 或 还有下一页未拉
    /// 仅在【有选中日期】的前提下才为 true，避免初始状态误判
    var isPagingAll: Bool {
        guard !selectedDay.isEmpty else { return false }
        return isLoadingEvents || isLoadingMore || hasMore
    }

    private let device: Device
    private(set) var channelId: Int
    private let cachedDeviceId: TXIoTDeviceId?

    /// 分页会话号：每次重置（切日期 / 切通道 / 下拉刷新）自增。
    /// 请求回调时校验，过期分页链的返回直接丢弃，避免旧数据追加进新列表造成重复 item
    private var eventsSession: Int = 0

    init(device: Device, channelId: Int = 0) {
        self.device = device
        self.channelId = channelId
        self.cachedDeviceId = Self.makeDeviceId(
            productId: device.productId,
            deviceName: device.deviceName
        )
    }

    /// 切换通道：复位列表与状态，并重新拉取日期 / 事件
    func switchChannel(_ newId: Int) {
        guard newId != channelId else { return }
        channelId = newId
        eventsSession += 1
        dayList = []
        selectedDay = ""
        events = []
        nextPageToken = nil
        hasMore = false
        errorMessage = nil
        isLoadingEvents = false
        isLoadingMore = false
        loadDayList()
    }

    private static func makeDeviceId(productId: String, deviceName: String) -> TXIoTDeviceId? {
        guard !productId.isEmpty, !deviceName.isEmpty else { return nil }
        let did = TXIoTDeviceId()
        did.productId = productId
        did.deviceName = deviceName
        return did
    }

    /// 刷新前的即时重置：点击刷新瞬间清空事件列表并作废在途分页链，
    /// 让列表 / 时间线高亮立即回到空态，不等 getDayList 网络回调。
    /// 直接进入"整体加载中"态，避免刷新期间闪现"当天无云存事件"空态；
    /// 若日期请求失败会在 loadDayList 的 onError 中复位 isLoadingEvents。
    func prepareForRefresh() {
        eventsSession += 1
        events = []
        nextPageToken = nil
        hasMore = false
        errorMessage = nil
        isLoadingEvents = true
        isLoadingMore = false
    }

    /// 获取含有云存事件的日期列表
    func loadDayList() {
        guard !isLoadingDays else { return }
        guard let storage = obtainStorage() else { return }
        isLoadingDays = true
        errorMessage = nil

        let cb = TXIoTCallback<NSArray>()
        cb.onSuccess = { [weak self] result in
            self?.runOnMain { vm in vm.handleDayListSuccess(result) }
        }
        cb.onError = { [weak self] code, msg in
            self?.runOnMain { vm in
                vm.isLoadingDays = false
                // 复位 prepareForRefresh 可能置位的加载标志，让错误页正常展示
                vm.isLoadingEvents = false
                vm.isLoadingMore = false
                vm.applyError(
                    prefix: "CloudStorage - Failed to load day list",
                    code: code.rawValue,
                    msg: msg,
                    fallback: L("Failed to load day list")
                )
            }
        }
        storage.getDayList(channelId, timeZone: TimeZone.current, callback: cb)
    }

    /// 切换选中日期并重新加载事件列表
    func selectDay(_ day: String) {
        guard !day.isEmpty else { return }
        selectedDay = day
        events = []
        nextPageToken = nil
        hasMore = false
        eventsSession += 1
        loadEvents(reset: true)
    }

    /// 加载事件列表（首屏或下一页）
    /// - parameter reset: true 表示首屏 / 刷新；false 表示续拉下一页
    /// 注：自动分页期间 isLoadingEvents 始终保持 true，直到全部拉完才置 false，
    /// 这样顶部加载条/下拉刷新能表现“整体还在拉”。
    func loadEvents(reset: Bool) {
        guard !selectedDay.isEmpty else { return }
        if reset { eventsSession += 1 }
        let session = eventsSession
        guard let storage = obtainStorage() else { return }
        guard prepareLoadingFlags(reset: reset) else { return }
        errorMessage = nil

        let token = nextPageToken ?? ""
        let cb = TXIoTCallback<TXIoTPageResult<TXIoTEvent>>()
        cb.onSuccess = { [weak self] result in
            self?.runOnMain { vm in
                guard vm.eventsSession == session else { return }
                vm.handleEventsSuccess(result, reset: reset)
            }
        }
        cb.onError = { [weak self] code, msg in
            self?.runOnMain { vm in
                guard vm.eventsSession == session else { return }
                // 出错时中断整个分页链路
                vm.isLoadingEvents = false
                vm.isLoadingMore = false
                vm.hasMore = false
                vm.applyError(
                    prefix: "CloudStorage - Failed to load event list",
                    code: code.rawValue,
                    msg: msg,
                    fallback: L("Failed to load event list")
                )
            }
        }
        storage.getEventList(
            channelId,
            timeZone: TimeZone.current,
            date: selectedDay,
            nextPageToken: token,
            callback: cb
        )
    }

    // MARK: - Private helpers

    /// 取云存实例；不可用时设置错误并返回 nil
    private func obtainStorage() -> TXIoTCloudStorage? {
        guard let deviceId = cachedDeviceId else {
            errorMessage = L("Incomplete device info")
            return nil
        }
        guard let storage = TXIoTEngine.getInstance().getCloudStorage(deviceId) else {
            errorMessage = L("Failed to get cloud storage instance")
            return nil
        }
        return storage
    }

    /// 设置 loading 标志；返回是否应继续加载
    /// 说明：同一个“分页链路”期间 isLoadingEvents 始终保持 true，
    /// 仅 isLoadingMore 在首页之后的每页请求中反映“在续拉下一页”状态。
    private func prepareLoadingFlags(reset: Bool) -> Bool {
        if reset {
            isLoadingEvents = true
            isLoadingMore = false
            nextPageToken = nil
            return true
        }
        guard hasMore, !isLoadingMore else { return false }
        // 续拉下一页时，同时保持顶层 loading 为 true
        isLoadingEvents = true
        isLoadingMore = true
        return true
    }

    private func handleDayListSuccess(_ result: NSArray?) {
        isLoadingDays = false
        let sorted = ((result as? [String]) ?? []).sorted(by: >)
        dayList = sorted
        guard let first = sorted.first else {
            events = []
            nextPageToken = nil
            hasMore = false
            isLoadingEvents = false
            isLoadingMore = false
            eventsSession += 1
            return
        }
        selectDay(first)
    }

    private func handleEventsSuccess(_ result: TXIoTPageResult<TXIoTEvent>?, reset: Bool) {
        let raw = (result?.dataList as? [TXIoTEvent]) ?? []
        let mapped = mapEvents(raw)
        if reset {
            events = mapped
        } else {
            events.append(contentsOf: mapped)
        }
        events.sort { $0.eventTimeMs > $1.eventTimeMs }

        // 分页终止条件：本页返回为空 或 nextPageToken 为空
        let token = result?.nextPageToken
        let hasToken = (token?.isEmpty == false)
        if raw.isEmpty || !hasToken {
            nextPageToken = nil
            hasMore = false
            isLoadingEvents = false
            isLoadingMore = false
            return
        }
        nextPageToken = token
        hasMore = true
        // 仍有下一页：保持顶层 loading 为 true，续拉下一页
        // isLoadingEvents 不重置，仅重置 isLoadingMore 以便 prepareLoadingFlags 能重新进入
        isLoadingMore = false
        loadEvents(reset: false)
    }

    private func mapEvents(_ raw: [TXIoTEvent]) -> [CloudEventItem] {
        return raw.map { ev in
            let files = ev.videoFiles.map(mapVideoFile)
            return CloudEventItem(
                eventType: ev.eventType,
                thumbnailUrl: ev.thumbnailUrl,
                eventTimeMs: ev.eventTimeMs,
                durationMs: ev.durationMs,
                videoFiles: files
            )
        }
    }

    /// 将 SDK TXIoTVideoFile 转换为内部 CloudVideoFile 模型
    private func mapVideoFile(_ f: TXIoTVideoFile) -> CloudVideoFile {
        CloudVideoFile(
            videoUrl: f.videoUrl,
            vodAppId: f.vodAppId,
            vodFileId: f.vodFileId,
            vodPlaySign: f.vodPlaySign,
            startTimeMs: f.startTimeMs,
            durationMs: f.durationMs
        )
    }

    private func applyError(prefix: String, code: Int, msg: String?, fallback: String) {
        errorMessage = msg ?? fallback
        print("\(prefix): code=\(code), msg=\(msg ?? "")")
    }

    /// 主线程派发到 self 的便捷封装
    private func runOnMain(_ block: @escaping (CloudStorageViewModel) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            block(self)
        }
    }
}
