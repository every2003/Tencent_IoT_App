import Combine
import Foundation
import SwiftUI

@objc @MainActor class DeviceViewModel: NSObject, ObservableObject {
    @Published var devices: [Device] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var selectedDevice: Device?
    /// 当前家庭名称（由 getFamilyList 成功后自动设置，供 View 绑定显示）
    @Published var currentFamilyName: String = ""
    /// 家庭列表缓存（由 getFamilyList 成功后写入，供 View 直接复用，避免并发调用 SDK）
    @Published var cachedFamilyList: [[String: Any]] = []
    /// 分享设备 key 集合（"productId/deviceName"），用于区分自有/分享设备
    @Published var sharedDeviceKeys: Set<String> = []

    @objc var addDeviceSuccessCallback:
        ((_ deviceId: String, _ deviceName: String, _ location: String) -> Void)?
    @objc var deleteDeviceCallback: ((_ deviceId: String) -> Void)?

    private let devicesKey = "savedDevices"

    override init() {
        super.init()
        loadDevicesFromAPI()
    }

    /// 从 TXIoTEngine API 加载设备列表
    /// 完整流程：始终先获取家庭列表（填充 cachedFamilyList 供切换弹窗复用）→ 再获取设备列表
    @objc func loadDevicesFromAPI() {
        isLoading = true
        errorMessage = nil
        print("Start loading device list...")

        // 始终先调 getFamilyList，确保 cachedFamilyList 被填充，供选择家庭弹窗直接复用，无需额外请求
        getFamilyList()
    }

    // MARK: - 私有方法：完整的加载流程

    /// 第一步：获取家庭列表，填充 cachedFamilyList，再加载设备
    private func getFamilyList() {
        DeviceAPIBridge.getFamilyList { [weak self] success, familyList, errorMsg in
            guard let self = self else { return }
            if success, let familyList = familyList, !familyList.isEmpty {
                if let firstFamily = familyList.first,
                    let familyId = firstFamily["FamilyId"] as? String
                {
                    print("Got family list, \(familyList.count) families")

                    // 缓存家庭列表，供选择家庭弹窗直接复用，不再发起额外请求
                    self.cachedFamilyList = familyList.compactMap { dict in
                        var result: [String: Any] = [:]
                        for (key, value) in dict {
                            if let strKey = key as? String { result[strKey] = value }
                        }
                        return result.isEmpty ? nil : result
                    }

                    // 确定当前家庭：优先沿用已选中的家庭，否则默认取第一个
                    let activeFamilyId: String
                    if let existing = DeviceAPIBridge.currentFamilyId, !existing.isEmpty,
                        familyList.contains(where: { ($0["FamilyId"] as? String) == existing })
                    {
                        activeFamilyId = existing
                    } else {
                        activeFamilyId = familyId
                        DeviceAPIBridge.currentFamilyId = familyId
                        UserDefaults.standard.set(familyId, forKey: "firstFamilyId")
                    }

                    // 同步家庭名称
                    if let activeFamily = familyList.first(where: {
                        ($0["FamilyId"] as? String) == activeFamilyId
                    }),
                        let activeName = activeFamily["Name"] as? String, !activeName.isEmpty
                    {
                        self.currentFamilyName = activeName
                        UserDefaults.standard.set(activeName, forKey: "currentFamilyName")
                    } else if let firstName = firstFamily["Name"] as? String, !firstName.isEmpty {
                        if self.currentFamilyName.isEmpty {
                            self.currentFamilyName = firstName
                        }
                    }

                    // 第二步：获取设备列表
                    self.getDeviceList(familyId: activeFamilyId)
                } else {
                    self.isLoading = false
                    self.errorMessage = L("Invalid family data format")
                    print("Invalid family data format")
                }
            } else {
                // 没有家庭，创建一个
                print("No family found, creating one...")
                self.createFamily()
            }
        }
    }

    /// 创建家庭（如果没有家庭）
    private func createFamily() {
        let familyName = NSLocalizedString("my_family", comment: L("My Home"))

        DeviceAPIBridge.createFamily(withName: familyName, address: "") {
            [weak self] success, familyId, errorMsg in
            // OC 层已通过 dispatch_async(main_queue) 保证回调在主线程执行
            MainActor.assumeIsolated {
                guard let self = self else { return }
                if success {
                    print("Family created successfully")
                    // 重新获取家庭列表，然后继续流程
                    self.getFamilyList()
                } else {
                    self.isLoading = false
                    self.errorMessage = errorMsg ?? L("Failed to create family")
                    print("Failed to create family: \(self.errorMessage ?? "")")
                }
            }
        }
    }

    /// 绑定设备成功后刷新设备列表（对齐 ohos AddDevicePage.handleAddDevice 的快速路径）
    /// 直接使用当前 currentFamilyId 拉取，不走 getFamilyList 整圈。
    /// 刚绑定完服务端的家庭设备索引偶发会有短暂延迟（`AppGetFamilyDeviceList` 返回 Total:0），
    /// 注意：此处 **不设 isLoading = true**，避免触发 DeviceListView 的 loadingView 分支
    /// 产生 "设备列表 → 加载中 → 设备列表" 的 UI 闪动。
    /// - Parameter completion: 数据到达（或重试完成）后回调，调用方在此时机执行 dismiss()，
    ///   确保列表已有数据再关闭添加页，避免先 dismiss 后数据才到导致空态闪现。
    func refreshDevicesAfterBindSuccess(completion: (@MainActor @Sendable () -> Void)? = nil) {
        let familyId = DeviceAPIBridge.currentFamilyId
            ?? UserDefaults.standard.string(forKey: "firstFamilyId")
            ?? ""
        guard !familyId.isEmpty else {
            print("Post-bind refresh: family ID not found, falling back to full refresh")
            loadDevicesFromAPI()
            completion?()
            return
        }
        print("Bind succeeded, closing add page after data arrives, familyId=\(familyId)")
        errorMessage = nil
        // 不设 isLoading，保持当前 devices 原样显示，新列表到达后再平滑替换
        getDeviceList(familyId: familyId, retryIfEmpty: true, completion: completion)
    }

    /// 第二步：获取设备列表（串行：先拉自有设备，完成后再拉分享设备）
    /// 注意：底层 SDK 的 HTTP 通道对并发请求存在响应错配问题（不同请求的响应会串流），
    /// 因此这里必须串行发起，避免 `AppGetFamilyDeviceList` 与 `AppListUserShareDevices` 的响应互相污染。
    /// - Parameter retryIfEmpty: 合并结果为空时是否延迟重试一次（仅用于绑定后刷新场景）
    /// - Parameter completion: 数据到达（或重试完成）后回调，供调用方执行 dismiss() 等后续操作
    private func getDeviceList(familyId: String, retryIfEmpty: Bool = false, completion: (@MainActor @Sendable () -> Void)? = nil) {
        // 第 1 步：获取自有设备列表
        DeviceAPIBridge.getDeviceList(withFamilyId: familyId, roomId: nil) {
            [weak self] ownedSuccess, ownedDeviceList, ownedErrorMsg in
            guard let self = self else { return }
            let ownedList: [DeviceInfoItem] = ownedDeviceList ?? []
            let ownedError: String? = ownedSuccess ? nil : (ownedErrorMsg ?? L("Failed to get device list"))
            if ownedSuccess {
                print("Got owned device list, \(ownedList.count) devices")
            } else {
                print("Failed to get owned device list: \(ownedError ?? "")")
            }

            // 第 2 步：自有设备请求回调后，再串行获取分享设备列表
            DeviceAPIBridge.getSharedDeviceList(withFamilyId: familyId) {
                [weak self] sharedSuccess, sharedDeviceList, sharedErrorMsg in
                guard let self = self else { return }
                let sharedList: [DeviceInfoItem] = sharedDeviceList ?? []
                if sharedSuccess {
                    print("Got shared device list, \(sharedList.count) devices")
                } else {
                    print("Failed to get shared device list: \(sharedErrorMsg ?? "")")
                }

                // 合并结果（两个回调已串行，OC Bridge 层已保证回调在主线程）
                self.isLoading = false

                if ownedList.isEmpty && ownedError != nil && sharedList.isEmpty {
                    self.errorMessage = ownedError
                    self.devices = []
                    print("Failed to load device list: \(self.errorMessage ?? "")")
                    MainActor.assumeIsolated {
                        completion?()
                    }
                    return
                }

                // 合并自有设备和分享设备，去重（以 productId/deviceName 为唯一键）
                var merged: [DeviceInfoItem] = ownedList
                let ownedIds = Set(ownedList.map { "\($0.productId)/\($0.deviceName)" })
                var newSharedKeys: Set<String> = []
                for item in sharedList {
                    let key = "\(item.productId)/\(item.deviceName)"
                    newSharedKeys.insert(key)
                    if !ownedIds.contains(key) {
                        merged.append(item)
                    }
                }
                self.sharedDeviceKeys = newSharedKeys
                self.parseDeviceList(merged)
                print(
                    "Loaded \(self.devices.count) devices (owned: \(ownedList.count), shared: \(sharedList.count))"
                )

                // 绑定后立即查询偶发会遇到服务端索引延迟，合并结果为空则延迟重试一次
                // 重试时同样不设 isLoading，静默重试，避免 UI 闪动
                if retryIfEmpty && merged.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self else { return }
                        self.getDeviceList(
                            familyId: familyId,
                            retryIfEmpty: false,
                            completion: completion
                        )
                    }
                } else {
                    // 数据已到达（或不需要重试），通知调用方可以安全地 dismiss()
                    MainActor.assumeIsolated {
                        completion?()
                    }
                }
            }
        }
    }

    // 解析设备列表数据（使用强类型 DeviceInfoItem，避免 [String: Any] 跨并发边界）
    // 差量合并策略：相同 id 的设备复用旧实例，
    // 内容无变化时直接跳过赋值，减少不必要的 SwiftUI 重建闪动。
    // 在线状态直接从 DeviceInfoItem.isOnline 读取（自有/分享设备均含此字段）。
    private func parseDeviceList(_ deviceList: [DeviceInfoItem]) {
        // 先把现有设备按 id 建立索引，用于在新列表里复用实例
        var oldMap: [String: Device] = [:]
        for d in self.devices { oldMap[d.id] = d }

        var newDevices: [Device] = []
        newDevices.reserveCapacity(deviceList.count)

        for item in deviceList {
            let productId = item.productId
            let deviceName = item.deviceName
            guard !productId.isEmpty, !deviceName.isEmpty else { continue }

            let deviceId = "\(productId)/\(deviceName)"
            let displayName = item.aliasName.isEmpty ? deviceName : item.aliasName
            let location = item.roomId

            if let existing = oldMap[deviceId] {
                // 复用已有实例，只同步可能变动的展示字段，避免整卡片重建
                existing.name = displayName
                existing.location = location
                existing.productId = productId
                existing.deviceName = deviceName
                existing.isShared = sharedDeviceKeys.contains(deviceId)
                existing.isOnline = item.isOnline
                newDevices.append(existing)
            } else {
                let device = Device(
                    id: deviceId,
                    name: displayName,
                    location: location,
                    productId: productId,
                    deviceName: deviceName
                )
                device.isShared = sharedDeviceKeys.contains(deviceId)
                device.isOnline = item.isOnline
                newDevices.append(device)
            }
        }

        // 内容无差异则跳过赋值，避免无意义的 UI 重渲染
        let oldIds = self.devices.map { $0.id }
        let newIds = newDevices.map { $0.id }
        if oldIds == newIds {
            // id 顺序一致，不需要整体替换；若有展示字段变化，上面已就地更新，触发 objectWillChange 以局部刷新
            self.objectWillChange.send()
        } else {
            self.devices = newDevices
        }
        saveDevices()
    }

    // 从 UserDefaults 加载设备列表（作为缓存备用）
    func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: devicesKey),
            let decoded = try? JSONDecoder().decode([Device].self, from: data)
        {
            self.devices = decoded
        }
    }

    // 保存设备列表到 UserDefaults
    func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: devicesKey)
        }
    }

    // 添加设备
    func addDevice(id: String, name: String, location: String) -> Bool {
        // 检查设备ID是否已存在
        if devices.contains(where: { $0.id == id }) {
            return false
        }

        let newDevice = Device(id: id, name: name, location: location)
        devices.append(newDevice)
        saveDevices()

        // 触发回调，让OC处理实际的添加设备逻辑
        addDeviceSuccessCallback?(id, name, location)

        return true
    }

    // 删除设备
    func deleteDevice(at offsets: IndexSet) {
        for index in offsets {
            let device = devices[index]
            // 触发回调
            deleteDeviceCallback?(device.id)
        }
        devices.remove(atOffsets: offsets)
        saveDevices()
    }

    // 删除指定设备
    @objc func deleteDevice(deviceId: String) {
        if let index = devices.firstIndex(where: { $0.id == deviceId }) {
            devices.remove(at: index)
            saveDevices()
        }
    }

    // 解绑设备（调用 TXIoTDeviceManager 标准化接口）
    func unbindDevice(_ device: Device, completion: @escaping @Sendable (Bool, String?) -> Void) {
        // 获取家庭ID
        let familyId =
            DeviceAPIBridge.currentFamilyId ?? UserDefaults.standard.string(forKey: "firstFamilyId")
            ?? ""

        guard !familyId.isEmpty else {
            completion(false, L("Family ID not found. Please log in again."))
            return
        }

        // 检查必要的参数
        guard !device.productId.isEmpty else {
            completion(false, L("Device missing product ID"))
            return
        }

        guard !device.deviceName.isEmpty else {
            completion(false, L("Device missing device name"))
            return
        }

        print(
            "🔄 Start unbinding device: \(device.name), productId: \(device.productId), deviceName: \(device.deviceName)"
        )

        // 调用API解绑设备
        DeviceAPIBridge.unbindDevice(
            withFamilyId: familyId,
            productId: device.productId,
            deviceName: device.deviceName
        ) { [weak self] success, errorMessage in
            DispatchQueue.main.async {
                if success {
                    print("Device unbound: \(device.name)")

                    // 从本地列表中移除设备
                    if let index = self?.devices.firstIndex(where: { $0.id == device.id }) {
                        self?.devices.remove(at: index)
                        self?.saveDevices()

                        // 触发回调
                        self?.deleteDeviceCallback?(device.id)
                    }

                    completion(true, nil)
                } else {
                    let errorMsg = errorMessage ?? L("Failed to unbind device")
                    print("Failed to unbind device: \(device.name) - \(errorMsg)")
                    completion(false, errorMsg)
                }
            }
        }
    }

    // 更新设备
    func updateDevice(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
            saveDevices()
        }
    }

    // 获取设备
    func getDevice(by id: String) -> Device? {
        return devices.first(where: { $0.id == id })
    }

    // OC调用此方法添加设备
    @objc func addDeviceFromOC(
        deviceId: String,
        deviceName: String,
        location: String,
        isOnline: Bool
    ) {
        let newDevice = Device(id: deviceId, name: deviceName, location: location)
        devices.append(newDevice)
        saveDevices()
    }

    // OC调用此方法更新设备列表
    @objc func updateDevicesFromOC(deviceArray: [[String: Any]]) {
        var newDevices: [Device] = []
        for deviceDict in deviceArray {
            if let productId = deviceDict["ProductId"] as? String,
                let deviceName = deviceDict["DeviceName"] as? String
            {
                let aliasName = deviceDict["AliasName"] as? String ?? deviceName
                let location = deviceDict["RoomId"] as? String ?? ""
                let deviceId = "\(productId)/\(deviceName)"
                let device = Device(
                    id: deviceId,
                    name: aliasName,
                    location: location,
                    productId: productId,
                    deviceName: deviceName
                )
                newDevices.append(device)
            }
        }
        self.devices = newDevices
        saveDevices()
    }

    // 清空设备列表
    @objc func clearDevices() {
        devices.removeAll()
        saveDevices()
    }
}
