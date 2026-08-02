import SwiftUI
import TXLiteAVSDK_Professional

struct DeviceListView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var deviceViewModel: DeviceViewModel  // = DeviceViewModel()
    @ObservedObject var navigationBridge: NavigationBridge

    @State private var showAddDevice = false
    @State private var showUserProfile = false
    @State private var showMessageList = false
    @State private var deviceToDelete: Device?
    @State private var isDeleting = false

    @State private var currentFamilyName: String = ""
    @State private var showFamilySwitchSheet = false
    @State private var showFamilyManageSheet = false

    @State private var selectedChannels: Set<Int> = [0]  // 默认选择通道0
    @State private var selectedDevice: Device?

    @State private var renameDevice: Device?
    @State private var renameText: String = ""
    @State private var isRenaming = false

    @State private var shareTokenContent: String?  // 非 nil 则显示分享码 Sheet
    @State private var showBindShareSheet = false
    @State private var bindShareTokenText: String = ""

    @State private var toastMessage: String?

    @ObservedObject private var callManager: CallManager = .shared

    init(navigationBridge: NavigationBridge = NavigationBridge()) {
        self.navigationBridge = navigationBridge
    }

    let columns = [
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color.bgColor.ignoresSafeArea()
            mainContentArea
            incomingCallBanner
        }
        .navigationBarHidden(true)
        .sheet(item: $selectedDevice) { device in
            channelSelectorSheet(for: device)
        }
        .sheet(isPresented: $showAddDevice) {
            AddDeviceView(deviceViewModel: _deviceViewModel)
        }
        .sheet(isPresented: $showUserProfile) {
            PersonalInfoView()
        }
        .sheet(isPresented: $showMessageList) {
            MessageListView()
        }
        .sheet(isPresented: $showFamilySwitchSheet) {
            familySwitchSheetContent
        }
        // 家庭管理 Sheet
        .sheet(isPresented: $showFamilyManageSheet) {
            FamilyManageView()
                .environmentObject(deviceViewModel)
        }
        .onAppear {
            // 家庭名称同步由 headerView.onAppear -> syncFamilyName() 统一处理
        }
        // 监听 ViewModel 的家庭名称变化（由 getFamilyList 回调设置），实时刷新显示
        .onReceive(deviceViewModel.$currentFamilyName) { name in
            if !name.isEmpty { currentFamilyName = name }
        }
        .onReceive(PushMessageStore.shared.$messages) { messages in
            if let latest = messages.first, latest.type == .statusChange {
                deviceViewModel.loadDevicesFromAPI()
            }
        }
        .sheet(item: $shareTokenContent) { content in
            shareTokenSheetContent(content)
        }
        .sheet(isPresented: $showBindShareSheet) {
            JoinTokenSheet(
                title: L("Bind Shared Device"),
                placeholder: L("Please paste the share content from the other party"),
                token: $bindShareTokenText,
                onConfirm: { bindSharedDevice() },
                onCancel: {
                    showBindShareSheet = false
                    bindShareTokenText = ""
                }
            )
        }
        // 解绑设备 Sheet（基于 CommonBottomSheet，由 deviceToDelete 驱动）
        .sheet(item: $deviceToDelete) { device in
            deleteConfirmSheetContent(device: device)
        }
        // 修改设备别名 Sheet（基于 CommonBottomSheet，由 renameDevice 驱动）
        .sheet(item: $renameDevice) { device in
            renameSheetContent(device: device)
        }
        .overlay(toastOverlay)
    }

    private var incomingCallBanner: some View {
        VStack {
            IncomingCallBanner(manager: callManager)
            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: callManager.showIncomingBanner)
    }

    private var mainContentArea: some View {
        VStack(spacing: 0) {
            headerView
            mainContentView
        }
    }

    var headerView: some View {
        HStack(alignment: .top, spacing: 0) {
            headerLeftSection
            Spacer()
            headerRightButtons
                .offset(y: -4)
        }
        .padding(.horizontal, 20)
        .frame(height: 120)
        .background(Color.headerGradient)
        .onAppear { syncFamilyName() }
    }

    private var headerLeftSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("My Devices"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
            headerFamilyCapsule
        }
    }

    private var headerFamilyCapsule: some View {
        HStack(spacing: 0) {
            Button(action: { loadFamilyListAndSwitch() }) {
                HStack(spacing: 5) {
                    Image(systemName: "house.fill").font(.system(size: 13))
                    Text(currentFamilyName.isEmpty ? L("My Home") : currentFamilyName)
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.leading, 12).padding(.trailing, 8)
            }
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 16)
            Button(action: { showFamilyManageSheet = true }) {
                Text(L("Manage"))
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.leading, 8).padding(.trailing, 12)
            }
        }
        .frame(height: 34)
        .background(Color.white.opacity(0.2))
        .cornerRadius(17)
    }

    private var headerRightButtons: some View {
        HStack(spacing: 8) {
            HeaderIconButton(systemName: "bell.fill") { showMessageList = true }
            HeaderIconButton(systemName: "plus") { showAddDevice = true }
            HeaderIconButton(systemName: "person.fill") { showUserProfile = true }
        }
    }

    var familyCapsule: some View {
        HStack(spacing: 0) {
            familyCapsuleNameButton
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 2, height: 18)
            familyCapsuleManageButton
        }
        .frame(height: 36)
        .background(Color.white.opacity(0.2))
        .cornerRadius(18)
    }

    private var familyCapsuleNameButton: some View {
        Button(action: { loadFamilyListAndSwitch() }) {
            HStack(spacing: 6) {
                Image(systemName: "house.fill")
                    .font(.system(size: 14)).foregroundColor(.white)
                Text(currentFamilyName.isEmpty ? L("My Home") : currentFamilyName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white).lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .padding(.leading, 14).padding(.trailing, 10)
        }
    }

    private var familyCapsuleManageButton: some View {
        Button(action: { showFamilyManageSheet = true }) {
            Text(L("Manage"))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .padding(.leading, 10).padding(.trailing, 14)
        }
    }

    // 同步当前家庭名称
    // 优先以 DeviceAPIBridge.currentFamilyId 对应的名称为准，避免显示 UserDefaults 里的旧缓存
    private func syncFamilyName() {
        // 优先用 ViewModel 的家庭名（由 getFamilyList 回调设置，最准确）
        if !deviceViewModel.currentFamilyName.isEmpty {
            currentFamilyName = deviceViewModel.currentFamilyName
        } else if let savedName = UserDefaults.standard.string(forKey: "currentFamilyName"),
            !savedName.isEmpty
        {
            currentFamilyName = savedName
        }
        // 通过 onReceive(deviceViewModel.$currentFamilyName) 监听后续更新，见 body 中的 .onReceive
    }

    // 加载家庭列表并弹出切换 Sheet
    // sheet 闭包里直接读 cachedFamilyList，无需 @State 中间变量，彻底避免时序问题
    private func loadFamilyListAndSwitch() {
        if !deviceViewModel.cachedFamilyList.isEmpty {
            // 缓存已有数据，直接弹窗（sheet 闭包会实时读取 cachedFamilyList）
            showFamilySwitchSheet = true
            return
        }
        // 缓存为空说明 loadDevicesFromAPI 还未完成，等待后再弹窗
        waitAndShowFamilySheet(retries: 6)
    }

    private func waitAndShowFamilySheet(retries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !deviceViewModel.cachedFamilyList.isEmpty {
                showFamilySwitchSheet = true
            } else if retries > 1 {
                waitAndShowFamilySheet(retries: retries - 1)
            } else {
                showFamilySwitchSheet = true
            }
        }
    }

    private func selectFamily(_ family: FamilyItem) {
        currentFamilyName = family.name
        DeviceAPIBridge.currentFamilyId = family.id
        UserDefaults.standard.set(family.id, forKey: "firstFamilyId")
        UserDefaults.standard.set(family.name, forKey: "currentFamilyName")
        // 同步更新 ViewModel 的家庭名称
        deviceViewModel.currentFamilyName = family.name
        // 先清空旧家庭的设备列表，再加载新家庭设备
        deviceViewModel.devices = []
        deviceViewModel.loadDevicesFromAPI()
    }

    var loadingView: some View {
        FullScreenLoader(message: L("Loading devices..."))
    }

    var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer()
            deviceEmptyIconView
            Text(L("No Devices"))
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.top, 20)
            Text(L("Tap the button below to add your first device"))
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .padding(.top, 8)
            Button(action: { showAddDevice = true }) {
                Text(L("Add Device"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 160, height: 50)
                    .background(Color.primaryColor)
                    .cornerRadius(14)
            }
            .padding(.top, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deviceEmptyIconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.deviceIconGradient)
                .frame(width: 100, height: 100)
            Image(systemName: "video.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(.primaryColor)
        }
    }

    // MARK: - 提取的 UI 子视图（降低 body 缩进层级）

    @ViewBuilder
    private var mainContentView: some View {
        if deviceViewModel.isLoading && deviceViewModel.devices.isEmpty {
            loadingView.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if deviceViewModel.devices.isEmpty {
            emptyScrollView
        } else {
            deviceListView
        }
    }

    private var emptyScrollView: some View {
        ScrollView {
            emptyStateView.frame(minHeight: UIScreen.main.bounds.height * 0.5)
        }
        .refreshable { await refreshDeviceList() }
    }

    private var deviceListView: some View {
        ScrollView {
            deviceGrid
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
        }
        .refreshable { await refreshDeviceList() }
    }

    private var deviceGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(deviceViewModel.devices) { device in
                DeviceCardView(
                    device: device,
                    onUnbindAction: { showDeleteConfirmation(for: $0) },
                    onVideoCall: {
                        callManager.startCall(peerName: $0.name, mode: .video, deviceId: $0.id)
                    },
                    onAudioCall: {
                        callManager.startCall(peerName: $0.name, mode: .audio, deviceId: $0.id)
                    },
                    onTapAction: { showChannelSelector(for: $0) },
                    onRenameAction: { showRenameDialog(for: $0) },
                    onShareAction: { createShareToken(for: $0) }
                )
            }
        }
    }

    @ViewBuilder
    private var familySwitchSheetContent: some View {
        let items = deviceViewModel.cachedFamilyList.compactMap { dict -> FamilyItem? in
            guard let fid = dict["FamilyId"] as? String,
                let name = dict["Name"] as? String
            else { return nil }
            return FamilyItem(id: fid, name: name)
        }
        let currentFid = DeviceAPIBridge.currentFamilyId ?? ""
        let rowHeight: CGFloat = 60
        let headerFooter: CGFloat = 155
        let familyHeight = CGFloat(max(items.count, 1)) * rowHeight + headerFooter
        CommonBottomSheet(
            title: L("🏠 Select Family"),
            hint: L("Current: %@", "\(currentFamilyName)"),
            confirmTitle: nil,
            cancelTitle: L("Cancel"),
            sheetHeight: min(familyHeight, 420),
            onCancel: { showFamilySwitchSheet = false }
        ) {
            familySwitchList(items: items, currentFid: currentFid)
        }
    }

    @ViewBuilder
    private func familySwitchList(items: [FamilyItem], currentFid: String) -> some View {
        if items.isEmpty {
            Text(L("No Family"))
                .font(.system(size: 16))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            VStack(spacing: 0) {
                ForEach(items) { family in
                    FamilySwitchRow(
                        family: family,
                        isCurrent: family.id == currentFid,
                        onTap: {
                            showFamilySwitchSheet = false
                            selectFamily(family)
                        }
                    )
                }
            }
        }
    }

    private var toastOverlay: some View {
        Group {
            if let msg = toastMessage {
                VStack {
                    Spacer()
                    AppToastView(message: msg)
                        .padding(.bottom, 50)
                }
                .transition(.opacity)
            }
        }
    }

    private func refreshDeviceList() async {
        await withCheckedContinuation { continuation in
            deviceViewModel.loadDevicesFromAPI()
            // 等待一小段时间确保数据加载完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
    }

    private func showDeleteConfirmation(for device: Device) {
        deviceToDelete = device
    }

    // 直接显示通道选择框（固定使用TRTC方式）
    // 通过设置 selectedDevice 驱动 sheet(item:) 弹出
    private func showChannelSelector(for device: Device) {
        print("showChannelSelector called, device: \(device.name), ID: \(device.id)")
        selectedChannels = [0]
        deviceViewModel.selectedDevice = device
        selectedDevice = device
    }

    // 通道选择 sheet 内容
    @ViewBuilder
    private func channelSelectorSheet(for device: Device) -> some View {
        ChannelSelectorView(
            device: device,
            selectedChannels: $selectedChannels,
            onConfirm: { channels in handleChannelConfirmation(channels) },
            onCancel: {
                selectedDevice = nil
                selectedChannels = [0]
            }
        )
    }

    // 处理通道选择确认
    private func handleChannelConfirmation(_ channels: Set<Int>) {
        guard !channels.isEmpty else {
            showToast(L("Please select at least one channel"))
            return
        }
        // 先捕获目标设备，再关闭 sheet（selectedDevice 置空会关闭 sheet(item:)）
        let device = selectedDevice
        selectedDevice = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.navigateToDeviceDetail(device: device, with: channels)
        }
    }

    private func createShareToken(for device: Device) {
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            showToast(L("Failed to get DeviceManager"))
            return
        }
        let familyId =
            DeviceAPIBridge.currentFamilyId
            ?? UserDefaults.standard.string(forKey: "firstFamilyId")
            ?? ""
        guard !familyId.isEmpty else {
            showToast(L("Family ID not found"))
            return
        }
        let did = TXIoTDeviceId()
        did.productId = device.productId
        did.deviceName = device.deviceName

        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { token in
            DispatchQueue.main.async {
                self.handleShareTokenCallback(token: token as String?, device: device)
            }
        }
        cb.onError = { _, errorMessage in
            DispatchQueue.main.async {
                self.showToast(L("Failed to create share code: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.createDeviceSharingToken(familyId, deviceId: did, callback: cb)
    }

    // 分享码回调处理（提取自 createShareToken 回调解耦缩进层级）
    private func handleShareTokenCallback(token: String?, device: Device) {
        guard let token = token else {
            showToast(L("Failed to create share code"))
            return
        }
        let jsonString = Self.buildShareTokenJSON(
            productId: device.productId,
            deviceName: device.deviceName,
            token: token
        )
        if let jsonString = jsonString {
            shareTokenContent = jsonString
        } else {
            showToast(L("Failed to create share code"))
        }
    }

    private func bindSharedDevice() {
        let jsonString = bindShareTokenText.trimmingCharacters(in: .whitespaces)
        guard !jsonString.isEmpty,
            let deviceManager = TXIoTEngine.getInstance().getDeviceManager()
        else {
            showToast(L("Please enter valid share content"))
            return
        }
        guard let data = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let productId = json["productId"], !productId.isEmpty,
            let deviceName = json["deviceName"], !deviceName.isEmpty,
            let token = json["token"], !token.isEmpty
        else {
            showToast(L("Invalid share content. Please check the format."))
            return
        }
        showBindShareSheet = false
        let did = TXIoTDeviceId()
        did.productId = productId
        did.deviceName = deviceName
        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                self.showToast(L("Device bound successfully"))
                self.bindShareTokenText = ""
                self.deviceViewModel.loadDevicesFromAPI()
            }
        }
        cb.onError = { _, errorMessage in
            DispatchQueue.main.async {
                self.showToast(L("Binding failed: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.bindDeviceShared(withMe: did, shareToken: token, callback: cb)
    }

    // 显示修改设备别名弹窗
    private func showRenameDialog(for device: Device) {
        print("Opening edit-alias dialog, device: \(device.name)")
        renameDevice = device
        renameText = device.name
    }

    // MARK: - 基于 CommonBottomSheet 的弹窗内容

    @ViewBuilder
    private func deleteConfirmSheetContent(device: Device) -> some View {
        CommonBottomSheet(
            title: L("Unbind Device"),
            confirmTitle: L("Unbind"),
            confirmStyle: .danger,
            confirmEnabled: !isDeleting,
            cancelTitle: L("Cancel"),
            sheetHeight: 200,
            onConfirm: { deleteDevice(device) },
            onCancel: {
                if !isDeleting { deviceToDelete = nil }
            }
        ) {
            if isDeleting {
                deletingProgressView
            } else {
                deleteWarningContent(device: device)
            }
        }
    }

    private func deleteWarningContent(device: Device) -> some View {
        VStack(spacing: 12) {
            Text(L("Are you sure you want to unbind the device \"%@\"?", "\(device.name)"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
            Text(L("This action cannot be undone. You will no longer be able to control the device after unbinding."))
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var deletingProgressView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text(L("Unbinding device..."))
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func renameSheetContent(device: Device) -> some View {
        CommonBottomSheet(
            title: L("Edit Device Alias"),
            hint: "\(device.productId)/\(device.deviceName)",
            confirmTitle: L("Save"),
            confirmEnabled: !isRenaming && !renameText.trimmingCharacters(in: .whitespaces).isEmpty,
            cancelTitle: L("Cancel"),
            sheetHeight: 240,
            onConfirm: { renameDeviceAlias(device, newName: renameText) },
            onCancel: {
                renameDevice = nil
                renameText = ""
            }
        ) {
            VStack(spacing: 12) {
                TextField(L("Please enter a new alias"), text: $renameText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 16))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(Color.inputBg)
                    .cornerRadius(12)
                    .sheetBorder(.borderColor)
                if isRenaming {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                        Text(L("Saving..."))
                            .font(.system(size: 13))
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func shareTokenSheetContent(_ content: String) -> some View {
        CommonBottomSheet(
            title: L("🔑 Device Share Code"),
            hint: L("Please send this content to the other party"),
            confirmTitle: L("📋 Copy Share Code"),
            sheetHeight: 320,
            onConfirm: {
                UIPasteboard.general.string = content
                shareTokenContent = nil
            },
            onCancel: { shareTokenContent = nil }
        ) {
            VStack(spacing: 12) {
                ScrollView {
                    Text(content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .frame(height: 132)
                .background(Color.inputBg)
                .cornerRadius(8)
                .sheetBorder(.borderColor, cornerRadius: 8)
                Text(L("The other party can paste this content in \"Bind Share\" to bind the device."))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // 调用 SDK 修改设备别名
    private func renameDeviceAlias(_ device: Device, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            showToast(L("Alias cannot be empty"))
            return
        }
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            showToast(L("Not logged in or failed to get DeviceManager"))
            return
        }

        let did = TXIoTDeviceId()
        did.productId = device.productId
        did.deviceName = device.deviceName
        isRenaming = true

        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                self.isRenaming = false
                self.showToast(L("Alias updated to \"%@\"", "\(trimmed)"))
                self.renameDevice = nil
                self.renameText = ""
                // 修改成功后刷新列表
                self.deviceViewModel.loadDevicesFromAPI()
            }
        }
        cb.onError = { _, errorMessage in
            DispatchQueue.main.async {
                self.isRenaming = false
                self.showToast(L("Modify failed: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.modifyAliasName(did, aliasName: trimmed, callback: cb)
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation { toastMessage = nil }
        }
    }

    private func navigateToDeviceDetail(device: Device?, with channels: Set<Int>) {
        guard let device = device else {
            print("navigateToDeviceDetail: device is nil, cannot navigate")
            return
        }

        let channelList = Array(channels).sorted()
        let channelType = channelList.count == 1 ? "single" : "multi"

        print("Preparing to navigate to device detail, device: \(device.name), channels: \(channelList), type: \(channelType)")

        if let navigationController = SwiftUIHelper.navigationController {
            let detailVC = SwiftUIHelper.createDeviceDetailViewController(
                device: device,
                channelList: channelList
            )
            navigationController.pushViewController(detailVC, animated: true)
        } else {
            print("Unable to get navigationController, navigation failed")
        }
    }

    // 执行设备解绑操作
    private func deleteDevice(_ device: Device) {
        isDeleting = true

        deviceViewModel.unbindDevice(device) { success, errorMessage in
            DispatchQueue.main.async {
                self.isDeleting = false
                if success {
                    print("Device unbound: \(device.name)")
                } else {
                    let errorMsg = errorMessage ?? L("Unbind Failed")
                    print("Failed to unbind device: \(errorMsg)")
                }
                self.deviceToDelete = nil
            }
        }
    }

    /// 将 productId、deviceName、token 组合成 JSON 字符串
    static func buildShareTokenJSON(productId: String, deviceName: String, token: String) -> String?
    {
        let payload: [String: String] = [
            "productId": productId,
            "deviceName": deviceName,
            "token": token,
        ]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: .prettyPrinted
            ),
            let jsonString = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return jsonString
    }
}

struct DeviceCardView: View {
    let device: Device
    var onUnbindAction: (Device) -> Void
    var onVideoCall: ((Device) -> Void)? = nil  // 视频通话
    var onAudioCall: ((Device) -> Void)? = nil  // 语音通话
    var onTapAction: (Device) -> Void
    var onRenameAction: ((Device) -> Void)? = nil
    var onShareAction: ((Device) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                // 左侧内容区：点击进入通道选择（不包含菜单按钮，避免与 Menu 点击冲突）
                HStack(alignment: .center, spacing: 0) {
                    deviceIconView
                    deviceNameStatusView
                        .padding(.leading, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture { onTapAction(device) }

                // 右侧菜单按钮：独立响应点击
                deviceMenuView
            }
            // 下半部分（分割线 + PID/DeviceName）也作为进入通道选择的可点区域
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(Color.bgColor)
                    .frame(height: 1)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                Text("\(device.productId)/\(device.deviceName)")
                    .font(.system(size: 11))
                    .foregroundColor(.textDisabled)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapAction(device) }
        }
        .padding(14)
        .background(Color.cardBg)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
    }

    // MARK: - HStack 子视图提取

    private var deviceIconView: some View {
        DeviceIconView()
    }

    private var deviceNameStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                if device.isShared {
                    TinyBadge(text: L("Share"))
                }
            }
            // 在线状态
            StatusIndicator(isOnline: device.isOnline, text: device.statusText)
        }
    }

    private var deviceMenuView: some View {
        Menu {
            menuButtonItem(L("Video Call"), icon: "video.fill") { onVideoCall?(device) }
            menuButtonItem(L("Voice Call"), icon: "phone.fill") { onAudioCall?(device) }
            menuButtonItem(L("Edit Alias"), icon: "pencil") { onRenameAction?(device) }
            menuButtonItem(L("Share Device"), icon: "square.and.arrow.up") { onShareAction?(device) }
            Divider()
            Button(role: .destructive) {
                onUnbindAction(device)
            } label: {
                Label(L("Unbind Device"), systemImage: "trash")
            }
        } label: {
            MenuButton()
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .controlSize(.small)
    }

    private func menuButtonItem(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
    }

    /// 优先展示别名，否则展示 deviceName
    private var displayName: String {
        if !device.name.isEmpty && device.name != device.deviceName {
            return device.name
        }
        return device.deviceName.isEmpty ? device.productId : device.deviceName
    }
}

struct ChannelSelectorView: View {
    var device: Device
    @Binding var selectedChannels: Set<Int>
    let onConfirm: (Set<Int>) -> Void
    let onCancel: () -> Void

    private let availableChannels = [0, 1, 2, 3]

    var body: some View {
        CommonBottomSheet(
            title: L("Select Video Channel"),
            hint: L("Device: %@/%@", "\(device.productId)", "\(device.deviceName)"),
            confirmTitle: L("OK"),
            cancelTitle: L("Cancel"),
            sheetHeight: 240,
            onConfirm: { onConfirm(selectedChannels) },
            onCancel: onCancel
        ) {
            channelGridContent
        }
    }

    private var channelGridContent: some View {
        VStack {
            Spacer(minLength: 0)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(availableChannels, id: \.self) { channel in
                    channelCircleItem(channel: channel)
                }
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
    }

    /// 通道圆圈项
    @ViewBuilder
    private func channelCircleItem(channel: Int) -> some View {
        let isSelected = selectedChannels.contains(channel)
        Button(action: { toggleChannel(channel) }) {
            channelCircleContent(channel: channel, isSelected: isSelected)
        }
        .frame(maxWidth: .infinity)
    }

    private func channelCircleContent(channel: Int, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.primaryColor : Color.cardBg)
                .frame(width: 56, height: 56)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primaryColor : Color.borderColor, lineWidth: 2)
                )
            Text(L("Channel %@", "\(channel)"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .textPrimary)
        }
    }

    private func toggleChannel(_ channel: Int) {
        if selectedChannels.contains(channel) {
            selectedChannels.remove(channel)
        } else {
            selectedChannels.insert(channel)
        }
    }
}

// 保留原 ChannelOptionView 兼容
struct ChannelOptionView: View {
    let channel: Int
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            channelOptionContent
        }
    }

    private var channelOptionContent: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.primaryColor : Color.cardBg)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(
                                isSelected ? Color.primaryColor : Color.borderColor,
                                lineWidth: 2
                            )
                    )
                Text(L("Channel %@", "\(channel)"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .textPrimary)
            }
            Text(L("Channel %@", "\(channel)"))
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .primaryColor : .textSecondary)
        }
        .padding(8)
        .background(Color.cardBg)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct FamilySwitchRow: View {
    let family: FamilyItem
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            familySwitchRowContent
        }
        .buttonStyle(.plain)
    }

    private var familySwitchRowContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primaryColor.opacity(0.1))
                    .frame(width: 40, height: 40)
                Text("🏠")
                    .font(.system(size: 17))
            }
            Text(family.name)
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            Spacer()
            if isCurrent {
                Text("✓")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primaryColor)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 60)
        .contentShape(Rectangle())
    }
}

#Preview {
    DeviceListView()
        .environmentObject(UserManager())
        .environmentObject(DeviceViewModel())
}
