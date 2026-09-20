import SwiftUI
import TXLiteAVSDK_IOT

// MARK: - String Identifiable 扩展（用于 sheet(item:) 传递 Token）
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - TXIoTUserInfo Identifiable 扩展（用于 sheet(item:) 直接传递用户对象）

extension TXIoTUserInfo: @retroactive Identifiable {
    public var id: String { userId }
}

// MARK: - 家庭信息模型

struct FamilyItem: Identifiable, Sendable {
    let id: String
    var name: String
}

// MARK: - 家庭管理主页面

struct FamilyManageView: View {
    @EnvironmentObject var deviceViewModel: DeviceViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0

    @State private var currentFamilyId: String = ""
    @State private var currentFamilyName: String = ""

    @State private var showCreateFamilySheet = false
    @State private var showRenameFamilySheet = false
    @State private var showDeleteFamilyAlert = false
    @State private var showLeaveFamilySheet = false
    @State private var newFamilyName = ""
    @State private var renameFamilyText = ""

    @State private var toastMessage: String?

    private let tabTitles = [L("Members"), L("Rooms"), L("Devices"), L("Shared with Me")]

    // MARK: - 导航栏（渐变背景，家庭名为标题，右侧菜单）
    private var navBar: some View {
        HStack(spacing: 0) {
            NavBackButton(action: { dismiss() })

            Spacer()

            Text(currentFamilyName.isEmpty ? L("Loading...") : currentFamilyName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Menu {
                Button(action: {
                    renameFamilyText = currentFamilyName
                    showRenameFamilySheet = true
                }) {
                    Label(L("Rename"), systemImage: "pencil")
                }
                Button(action: { showCreateFamilySheet = true }) {
                    Label(L("New Family"), systemImage: "plus.circle")
                }
                Divider()
                Button(action: { showLeaveFamilySheet = true }) {
                    Label(L("Leave Family"), systemImage: "rectangle.portrait.and.arrow.right")
                }
                Button(role: .destructive, action: { showDeleteFamilyAlert = true }) {
                    Label(L("Delete Family"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Color.headerGradient.ignoresSafeArea(edges: .top))
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            Divider()

            customTabBar

            Divider()

            VStack(spacing: 0) {
                if selectedTab == 0 {
                    FamilyMemberView(familyId: currentFamilyId)
                } else if selectedTab == 1 {
                    RoomManageView(familyId: currentFamilyId)
                } else if selectedTab == 2 {
                    DeviceSharingView()
                } else {
                    SharedToMeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.bgColor.ignoresSafeArea())
            .sheet(isPresented: $showCreateFamilySheet) {
                CommonBottomSheet(
                    title: L("New Family"),
                    confirmTitle: L("Create"),
                    sheetHeight: 210,
                    onConfirm: { createFamily() },
                    onCancel: { showCreateFamilySheet = false }
                ) {
                    SheetTextField(label: L("Please enter family name"), placeholder: L("Please enter family name"), text: $newFamilyName)
                }
            }
            // 修改家庭名称 Sheet
            .sheet(isPresented: $showRenameFamilySheet) {
                CommonBottomSheet(
                    title: L("Rename Family"),
                    confirmTitle: L("OK"),
                    sheetHeight: 210,
                    onConfirm: { updateFamilyName() },
                    onCancel: { showRenameFamilySheet = false }
                ) {
                    SheetTextField(label: L("Please enter a new name"), placeholder: L("Please enter a new name"), text: $renameFamilyText)
                }
            }
            // 删除家庭确认
            .sheet(isPresented: $showDeleteFamilyAlert) { deleteFamilySheet }
            .sheet(isPresented: $showLeaveFamilySheet) { leaveFamilySheet }
            // Toast
            .overlay(alignment: .bottom) {
                if let msg = toastMessage {
                    AppToastView(message: msg)
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
            }
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .memberRequestLeaveFamily)) { _ in
            showLeaveFamilySheet = true
        }
        .onAppear {
            // 同步赋值已有的家庭信息（主界面已拉取过），避免 currentFamilyId 为空
            // 导致 FamilyMemberView / RoomManageView 的 loadXxx() 因 familyId 为空而跳过
            if currentFamilyId.isEmpty {
                let savedId = DeviceAPIBridge.currentFamilyId ?? ""
                if !savedId.isEmpty {
                    currentFamilyId = savedId
                    // 同步家庭名称：优先用 ViewModel 缓存，其次用 UserDefaults
                    if !deviceViewModel.currentFamilyName.isEmpty {
                        currentFamilyName = deviceViewModel.currentFamilyName
                    } else if let name = UserDefaults.standard.string(forKey: "currentFamilyName"),
                        !name.isEmpty
                    {
                        currentFamilyName = name
                    }
                }
            }
        }
    }

    var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabTitles.count, id: \.self) { index in
                tabButton(index)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.cardBg)
    }

    private func tabButton(_ index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            VStack(spacing: 0) {
                Text(tabTitles[index])
                    .font(tabFont(for: index))
                    .foregroundColor(tabColor(for: index))
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(tabIndicatorColor(for: index))
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func tabFont(for index: Int) -> Font {
        .system(size: 14, weight: selectedTab == index ? .semibold : .regular)
    }

    private func tabColor(for index: Int) -> Color {
        selectedTab == index ? .primaryColor : .textSecondary
    }

    private func tabIndicatorColor(for index: Int) -> Color {
        selectedTab == index ? .primaryColor : .clear
    }

    // MARK: - 家庭操作 Sheet

    private var leaveFamilySheet: some View {
        CommonBottomSheet(
            title: L("Leave Family"),
            confirmTitle: L("Leave"),
            confirmStyle: .danger,
            sheetHeight: 210,
            onConfirm: {
                showLeaveFamilySheet = false
                leaveFamily()
            },
            onCancel: { showLeaveFamilySheet = false }
        ) {
            Text(L("Are you sure you want to leave the current family? You will no longer be a member of this family."))
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    private var deleteFamilySheet: some View {
        CommonBottomSheet(
            title: L("Delete Family"),
            confirmTitle: L("Delete"),
            confirmStyle: .danger,
            sheetHeight: 210,
            onConfirm: {
                showDeleteFamilyAlert = false
                deleteCurrentFamily()
            },
            onCancel: { showDeleteFamilyAlert = false }
        ) {
            Text(L("Are you sure you want to delete the family \"%@\"? This action cannot be undone.", "\(currentFamilyName)"))
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    // MARK: - 家庭操作

    private func selectFamily() {
        DeviceAPIBridge.currentFamilyId = currentFamilyId
        UserDefaults.standard.set(currentFamilyId, forKey: "firstFamilyId")
        // 刷新设备列表
        deviceViewModel.loadDevicesFromAPI()
    }

    private func createFamily() {
        let name = newFamilyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showToast(L("Please enter family name"))
            return
        }
        showCreateFamilySheet = false
        DeviceAPIBridge.createFamily(withName: name, address: "") { success, familyId, errorMsg in
            // SDK 保证回调在主线程执行
            MainActor.assumeIsolated {
                handleCreateFamilyResult(success: success, familyId: familyId, name: name, errorMsg: errorMsg)
            }
        }
    }

    private func handleCreateFamilyResult(success: Bool, familyId: String?, name: String, errorMsg: String?) {
        guard success, let fid = familyId else {
            showToast(errorMsg ?? L("Failed to create family"))
            return
        }
        currentFamilyId = fid
        currentFamilyName = name
        selectFamily()
        newFamilyName = ""
        showToast(L("Family created successfully"))
    }

    private func updateFamilyName() {
        let name = renameFamilyText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showToast(L("Please enter family name"))
            return
        }
        showRenameFamilySheet = false
        DeviceAPIBridge.updateFamilyName(name, forFamilyId: currentFamilyId) { success, errorMsg in
            MainActor.assumeIsolated {
                handleUpdateFamilyNameResult(success: success, name: name, errorMsg: errorMsg)
            }
        }
    }

    private func handleUpdateFamilyNameResult(success: Bool, name: String, errorMsg: String?) {
        guard success else {
            showToast(errorMsg ?? L("Modify Failed"))
            return
        }
        currentFamilyName = name
        showToast(L("Family name updated"))
    }

    private func deleteCurrentFamily() {
        guard !currentFamilyId.isEmpty else { return }
        DeviceAPIBridge.deleteFamily(withId: currentFamilyId) { success, errorMsg in
            MainActor.assumeIsolated {
                handleDeleteFamilyResult(success: success, errorMsg: errorMsg)
            }
        }
    }

    private func handleDeleteFamilyResult(success: Bool, errorMsg: String?) {
        guard success else {
            showToast(errorMsg ?? L("Delete Failed"))
            return
        }
        showToast(L("Family deleted"))
        // 回到主界面，由主界面重新选择家庭
        dismiss()
    }

    private func leaveFamily() {
        guard !currentFamilyId.isEmpty,
            let currentUser = TXIoTEngine.getInstance().getLoginUserInfo()
        else {
            showToast(L("Not logged in or failed to get user info"))
            return
        }
        guard let familyManager = TXIoTEngine.getInstance().getFamilyManager() else {
            showToast(L("Failed to get FamilyManager"))
            return
        }
        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                showToast(L("Left family"))
                dismiss()
                // 通知主界面刷新
                NotificationCenter.default.post(name: .familyDidChange, object: nil)
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Failed to leave: %@", "\(errorMessage ?? "")"))
            }
        }
        familyManager.removeMember(
            fromFamily: currentFamilyId,
            userId: currentUser.userId,
            callback: cb
        )
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - 家庭变更通知

extension Notification.Name {
    /// 家庭变更通知（退出/切换后通知主界面刷新）
    static let familyDidChange = Notification.Name("familyDidChange")
    /// 成员列表行请求退出家庭（由 FamilyMemberView → FamilyManageView）
    static let memberRequestLeaveFamily = Notification.Name("memberRequestLeaveFamily")
}

// MARK: - 通用输入 Sheet

struct FamilyInputSheet: View {
    let title: String
    let placeholder: String
    let confirmText: String
    @Binding var inputText: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField(placeholder, text: $inputText)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(confirmText) { onConfirm() }
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - 通用带标签的文本框（用于 Sheet 内统一风格）

struct SheetTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundColor(Color(red: 0x6A / 255, green: 0x6E / 255, blue: 0x78 / 255))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.bottom, 4)
        TextField(placeholder, text: $text)
            .autocorrectionDisabled().font(.system(size: 15))
            .frame(height: 44).padding(.horizontal, 12)
            .background(Color.inputBg).cornerRadius(8)
            .sheetBorder(.borderColor, cornerRadius: 8)
            .padding(.horizontal, 20)
    }
}

// MARK: - 房间管理视图

struct RoomManageView: View {
    let familyId: String
    @State private var rooms: [RoomItem] = []
    @State private var isLoading = false
    @State private var showCreateSheet = false
    @State private var showRenameSheet = false
    @State private var showDeleteSheet = false
    @State private var selectedRoom: RoomItem?
    @State private var newRoomName = ""
    @State private var renameText = ""
    @State private var toastMessage: String?
    // 绑定设备到房间
    @State private var showBindDeviceSheet = false
    @State private var roomForBinding: RoomItem?
    @State private var allDevices: [DeviceInfoItem] = []
    @State private var isLoadingDevices = false
    @State private var showUnbindDeviceSheet = false
    @State private var roomForUnbinding: RoomItem?
    @State private var devicesInRoom: [DeviceInfoItem] = []

    var body: some View {
        ZStack {
            Color.bgColor.ignoresSafeArea()
            VStack(spacing: 0) {
                roomListContent
                createRoomButton
            }
            toastOverlay
        }
        .task(id: familyId) { loadRooms() }
        .sheet(isPresented: $showCreateSheet) { createRoomSheet }
        .sheet(isPresented: $showRenameSheet) { renameRoomSheet }
        .sheet(isPresented: $showDeleteSheet) { deleteRoomSheet }
        .sheet(isPresented: $showBindDeviceSheet) { bindDeviceSheet }
        .sheet(isPresented: $showUnbindDeviceSheet) { unbindDeviceSheet }
    }

    // MARK: - 提取的 UI 子视图

    private var createRoomButton: some View {
        Button(action: { showCreateSheet = true }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 16))
                Text(L("New Room")).font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.primaryColor)
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var roomListContent: some View {
        if isLoading {
            Spacer()
            ProgressView(L("Loading..."))
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
            Spacer()
        } else if rooms.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 60))
                    .foregroundColor(.textDisabled)
                Text(L("No rooms")).font(.system(size: 16)).foregroundColor(.textSecondary)
            }
            Spacer()
        } else {
            roomListView
        }
    }

    private var roomListView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(rooms) { room in
                    RoomRowView(
                        room: room,
                        onRename: { selectRoomForRename(room) },
                        onDelete: { selectRoomForDelete(room) },
                        onBindDevice: { selectRoomForBind(room) },
                        onUnbindDevice: { selectRoomForUnbind(room) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var createRoomSheet: some View {
        CommonBottomSheet(
            title: L("🚪 New Room"),
            confirmTitle: L("Create"),
            sheetHeight: 210,
            onConfirm: { createRoom() },
            onCancel: { showCreateSheet = false }
        ) {
            SheetTextField(label: L("Please enter room name"), placeholder: L("Please enter room name"), text: $newRoomName)
        }
    }

    private var renameRoomSheet: some View {
        CommonBottomSheet(
            title: L("Rename Room"),
            confirmTitle: L("OK"),
            sheetHeight: 210,
            onConfirm: { renameRoom() },
            onCancel: { showRenameSheet = false }
        ) {
            SheetTextField(label: L("Please enter a new name"), placeholder: L("Please enter a new name"), text: $renameText)
        }
    }

    private var deleteRoomSheet: some View {
        CommonBottomSheet(
            title: L("Delete Room"),
            confirmTitle: L("Delete"),
            confirmStyle: .danger,
            sheetHeight: 190,
            onConfirm: {
                showDeleteSheet = false
                if let room = selectedRoom { deleteRoom(room) }
            },
            onCancel: {
                showDeleteSheet = false
                selectedRoom = nil
            }
        ) {
            if let room = selectedRoom {
                Text(L("Are you sure you want to delete the room \"%@\"?", "\(room.name)"))
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
        }
    }

    private var bindDeviceSheet: some View {
        let bindableDevices = allDevices.filter { $0.roomId != (roomForBinding?.id ?? "") }
        return CommonBottomSheet(
            title: L("Move Device into Room"),
            hint: roomForBinding?.name,
            confirmTitle: nil,
            sheetHeight: 400,
            onCancel: { showBindDeviceSheet = false }
        ) {
            if isLoadingDevices {
                ProgressView(L("Loading devices..."))
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
            } else if bindableDevices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.textDisabled)
                    Text(L("No devices available to move in"))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(bindableDevices, id: \.deviceId) { device in
                            DeviceRoomRowView(
                                device: device,
                                isInRoom: false,
                                currentRoomName: roomForBinding?.name ?? "",
                                onAction: {
                                    showBindDeviceSheet = false
                                    bindDeviceToRoom(device: device)
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    private var unbindDeviceSheet: some View {
        CommonBottomSheet(
            title: L("Remove Device from Room"),
            hint: roomForUnbinding?.name,
            confirmTitle: nil,
            sheetHeight: 400,
            onCancel: { showUnbindDeviceSheet = false }
        ) {
            if devicesInRoom.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "video.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.textDisabled)
                    Text(roomForUnbinding == nil ? L("No Devices") : L("No devices in \"%@\"", "\(roomForUnbinding?.name ?? "")"))
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(devicesInRoom, id: \.deviceId) { device in
                            DeviceRoomRowView(
                                device: device,
                                isInRoom: true,
                                currentRoomName: roomForUnbinding?.name ?? "",
                                onAction: {
                                    showUnbindDeviceSheet = false
                                    unbindDeviceFromRoom(device: device)
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let msg = toastMessage {
            VStack {
                Spacer()
                AppToastView(message: msg)
                    .padding(.bottom, 40)
            }
            .transition(.opacity)
        }
    }

    private func selectRoomForRename(_ room: RoomItem) {
        selectedRoom = room
        renameText = room.name
        showRenameSheet = true
    }
    private func selectRoomForDelete(_ room: RoomItem) {
        selectedRoom = room
        showDeleteSheet = true
    }
    private func selectRoomForBind(_ room: RoomItem) {
        roomForBinding = room
        loadAllDevices()
        showBindDeviceSheet = true
    }
    private func selectRoomForUnbind(_ room: RoomItem) {
        roomForUnbinding = room
        loadDevicesInRoom(room)
        showUnbindDeviceSheet = true
    }

    private func loadRooms() {
        guard !familyId.isEmpty else { return }
        isLoading = true
        DeviceAPIBridge.getRoomList(withFamilyId: familyId) { success, roomList, errorMsg in
            nonisolated(unsafe) let roomList = roomList
            MainActor.assumeIsolated {
                handleRoomList(success: success, roomList: roomList, errorMsg: errorMsg)
            }
        }
    }

    private func handleRoomList(success: Bool, roomList: [[AnyHashable: Any]]?, errorMsg: String?) {
        isLoading = false
        guard success, let list = roomList else {
            showToast(errorMsg ?? L("Failed to get room list"))
            return
        }
        rooms = list.compactMap { dict in
            guard let rid = dict["RoomId"] as? String,
                let name = dict["RoomName"] as? String
            else { return nil }
            let count = dict["DeviceCount"] as? Int ?? 0
            return RoomItem(id: rid, name: name, deviceCount: count)
        }
    }

    private func loadAllDevices() {
        guard !familyId.isEmpty else { return }
        isLoadingDevices = true
        DeviceAPIBridge.getDeviceList(withFamilyId: familyId, roomId: nil) {
            success,
            deviceList,
            errorMsg in
            MainActor.assumeIsolated {
                handleAllDevices(success: success, deviceList: deviceList, errorMsg: errorMsg)
            }
        }
    }

    private func handleAllDevices(success: Bool, deviceList: [DeviceInfoItem]?, errorMsg: String?) {
        isLoadingDevices = false
        guard success, let list = deviceList else {
            showToast(errorMsg ?? L("Failed to get device list"))
            return
        }
        allDevices = list
    }

    /// 加载指定房间中的设备（用于解绑设备时的设备选择列表）
    private func loadDevicesInRoom(_ room: RoomItem) {
        guard !familyId.isEmpty else { return }
        isLoadingDevices = true
        DeviceAPIBridge.getDeviceList(withFamilyId: familyId, roomId: nil) {
            success,
            deviceList,
            errorMsg in
            MainActor.assumeIsolated {
                handleDevicesInRoom(success: success, deviceList: deviceList, room: room, errorMsg: errorMsg)
            }
        }
    }

    private func handleDevicesInRoom(success: Bool, deviceList: [DeviceInfoItem]?, room: RoomItem, errorMsg: String?) {
        isLoadingDevices = false
        guard success, let list = deviceList else {
            showToast(errorMsg ?? L("Failed to get device list"))
            return
        }
        // 过滤出该房间的设备
        devicesInRoom = list.filter { $0.roomId == room.id }
    }

    private func createRoom() {
        let name = newRoomName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showToast(L("Please enter room name"))
            return
        }
        showCreateSheet = false
        DeviceAPIBridge.createRoom(withName: name, familyId: familyId) { success, errorMsg in
            MainActor.assumeIsolated {
                handleCreateRoomResult(success: success, errorMsg: errorMsg)
            }
        }
    }

    private func handleCreateRoomResult(success: Bool, errorMsg: String?) {
        guard success else {
            showToast(errorMsg ?? L("Failed to create room"))
            return
        }
        newRoomName = ""
        showToast(L("Room created successfully"))
        loadRooms()
    }

    private func renameRoom() {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let room = selectedRoom else { return }
        showRenameSheet = false
        DeviceAPIBridge.renameRoom(withId: room.id, newName: name, familyId: familyId) {
            success,
            errorMsg in
            MainActor.assumeIsolated {
                handleRenameRoomResult(success: success, room: room, name: name, errorMsg: errorMsg)
            }
        }
    }

    private func handleRenameRoomResult(success: Bool, room: RoomItem, name: String, errorMsg: String?) {
        guard success else {
            showToast(errorMsg ?? L("Rename failed"))
            selectedRoom = nil
            return
        }
        if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[idx].name = name
        }
        showToast(L("Room renamed"))
        selectedRoom = nil
    }

    private func deleteRoom(_ room: RoomItem) {
        DeviceAPIBridge.deleteRoom(withId: room.id, familyId: familyId) { success, errorMsg in
            MainActor.assumeIsolated {
                handleDeleteRoomResult(success: success, room: room, errorMsg: errorMsg)
            }
        }
    }

    private func handleDeleteRoomResult(success: Bool, room: RoomItem, errorMsg: String?) {
        guard success else {
            showToast(errorMsg ?? L("Delete Failed"))
            selectedRoom = nil
            return
        }
        rooms.removeAll { $0.id == room.id }
        showToast(L("Room deleted"))
        selectedRoom = nil
    }

    private func bindDeviceToRoom(device: DeviceInfoItem) {
        guard let room = roomForBinding else { return }
        showBindDeviceSheet = false
        DeviceAPIBridge.bindDeviceToRoom(
            withFamilyId: familyId,
            productId: device.productId,
            deviceName: device.deviceName,
            roomId: room.id
        ) { success, errorMsg in
            MainActor.assumeIsolated {
                handleBindDeviceResult(success: success, room: room, errorMsg: errorMsg)
            }
        }
    }

    private func handleBindDeviceResult(success: Bool, room: RoomItem, errorMsg: String?) {
        guard success else {
            showToast(errorMsg ?? L("Binding Failed"))
            return
        }
        showToast(L("Device moved into \"%@\"", "\(room.name)"))
        loadRooms()
    }

    private func unbindDeviceFromRoom(device: DeviceInfoItem) {
        DeviceAPIBridge.unbindDeviceFromRoom(
            withFamilyId: familyId,
            productId: device.productId,
            deviceName: device.deviceName
        ) { success, errorMsg in
            MainActor.assumeIsolated {
                handleUnbindDeviceResult(success: success, errorMsg: errorMsg)
            }
        }
    }

    private func handleUnbindDeviceResult(success: Bool, errorMsg: String?) {
        guard success else {
            showToast(errorMsg ?? L("Failed to remove"))
            return
        }
        showToast(L("Device removed from room"))
        loadRooms()
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - 绑定设备到房间 Sheet

struct BindDeviceToRoomSheet: View {
    let room: RoomItem?
    let devices: [DeviceInfoItem]
    let isLoading: Bool
    let onBind: (DeviceInfoItem) -> Void
    let onUnbind: (DeviceInfoItem) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.bgColor.ignoresSafeArea()
                sheetContent
            }
            .navigationTitle(L("Manage Devices - %@", "\(room?.name ?? "")"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Done")) { onCancel() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var sheetContent: some View {
        if isLoading {
            ProgressView(L("Loading devices..."))
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
        } else if devices.isEmpty {
            emptyDevicesView
        } else {
            deviceListContent
        }
    }

    private var emptyDevicesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.textDisabled)
            Text(L("No Devices"))
                .font(.system(size: 16))
                .foregroundColor(.textSecondary)
        }
    }

    private var deviceListContent: some View {
        let inRoom = devices.filter { $0.roomId == (room?.id ?? "") }
        let notInRoom = devices.filter { $0.roomId != (room?.id ?? "") }
        return List {
            if !inRoom.isEmpty {
                Section(header: sectionHeader(L("Already in this room"))) {
                    ForEach(inRoom, id: \.deviceId) { device in
                        DeviceRoomRowView(
                            device: device,
                            isInRoom: true,
                            currentRoomName: room?.name ?? "",
                            onAction: { onUnbind(device) }
                        )
                        .listRowBackground(Color.white)
                    }
                }
            }
            if !notInRoom.isEmpty {
                Section(header: sectionHeader(L("Other Devices"))) {
                    ForEach(notInRoom, id: \.deviceId) { device in
                        DeviceRoomRowView(
                            device: device,
                            isInRoom: false,
                            currentRoomName: room?.name ?? "",
                            onAction: { onBind(device) }
                        )
                        .listRowBackground(Color.white)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 13)).foregroundColor(.textSecondary)
    }
}

// MARK: - 解绑设备出房间 Sheet

struct UnbindDeviceFromRoomSheet: View {
    let room: RoomItem?
    let devices: [DeviceInfoItem]
    let isLoading: Bool
    let onUnbind: (DeviceInfoItem) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            ZStack {
                Color.bgColor.ignoresSafeArea()
                unbindContent
            }
            .navigationTitle(L("Unbind Device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Cancel")) { onCancel() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var unbindContent: some View {
        if devices.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "video.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.textDisabled)
                Text(room == nil ? L("No Devices") : L("No devices in \"%@\"", "\(room?.name ?? "")"))
                    .font(.system(size: 16))
                    .foregroundColor(.textSecondary)
            }
        } else {
            List {
                Section(
                    header: Text(L("Select devices to remove"))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                ) {
                    ForEach(devices, id: \.deviceId) { device in
                        DeviceRoomRowView(
                            device: device,
                            isInRoom: true,
                            currentRoomName: room?.name ?? "",
                            onAction: { onUnbind(device) }
                        )
                        .listRowBackground(Color.white)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - 设备房间行视图

struct DeviceRoomRowView: View {
    let device: DeviceInfoItem
    let isInRoom: Bool
    let currentRoomName: String
    let onAction: () -> Void

    var displayName: String {
        device.aliasName.isEmpty ? device.deviceName : device.aliasName
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primaryColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "video.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primaryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text(
                    device.roomId.isEmpty
                        ? L("Unassigned") : (isInRoom ? L("Current room: %@", "\(currentRoomName)") : L("Other rooms"))
                )
                .font(.system(size: 12))
                .foregroundColor(.textDisabled)
            }

            Spacer()

            Button(action: onAction) {
                Text(isInRoom ? L("Move Out") : L("Move In"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isInRoom ? .dangerColor : .primaryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .sheetBorder(isInRoom ? .dangerColor : .primaryColor, cornerRadius: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 房间数据模型

struct RoomItem: Identifiable {
    let id: String
    var name: String
    let deviceCount: Int
}

// MARK: - 房间行视图

struct RoomRowView: View {
    let room: RoomItem
    let onRename: () -> Void
    let onDelete: () -> Void
    let onBindDevice: () -> Void
    let onUnbindDevice: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primaryColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 20))
                    .foregroundColor(.primaryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text(L("%@ devices", "\(room.deviceCount)"))
                    .font(.system(size: 12))
                    .foregroundColor(.textDisabled)
            }

            Spacer()

            Menu {
                Button(action: onRename) {
                    Label(L("Rename Room"), systemImage: "pencil")
                }
                Button(action: onBindDevice) {
                    Label(L("Move Device into Room"), systemImage: "arrow.right.circle")
                }
                Button(action: onUnbindDevice) {
                    Label(L("Remove Device from Room"), systemImage: "arrow.left.circle")
                }
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label(L("Delete Room"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - 成员管理

struct FamilyMemberView: View {
    let familyId: String
    @State private var members: [TXIoTUserInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeleteMemberSheet = false
    @State private var memberToDelete: TXIoTUserInfo?
    @State private var toastMessage: String?
    @State private var inviteToken: String? = nil
    @State private var showJoinFamilySheet = false
    @State private var joinToken = ""

    var body: some View {
        ZStack {
            Color.bgColor.ignoresSafeArea()
            VStack(spacing: 0) {
                memberListContent
                inviteActionButtons
            }
            memberToastOverlay
        }
        .task(id: familyId) { loadMembers() }
        .sheet(item: $inviteToken) { inviteTokenSheet($0) }
        .sheet(isPresented: $showJoinFamilySheet) { joinFamilySheet }
        .sheet(isPresented: $showDeleteMemberSheet) { deleteMemberSheet }
    }

    private var inviteActionButtons: some View {
        HStack(spacing: 12) {
            Button(action: { createInviteToken() }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus").font(.system(size: 16))
                    Text(L("Create Invite")).font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 44)
                .background(Color.primaryColor).cornerRadius(8)
            }
            Button(action: { showJoinFamilySheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key").font(.system(size: 16))
                    Text(L("Join Family")).font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.primaryColor).frame(maxWidth: .infinity).frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primaryColor, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder
    private var memberListContent: some View {
        if isLoading {
            Spacer()
            ProgressView(L("Loading..."))
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
            Spacer()
        } else if members.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 60)).foregroundColor(.textDisabled)
                Text(L("No family members")).font(.system(size: 16)).foregroundColor(.textSecondary)
            }
            Spacer()
        } else {
            memberListView
        }
    }

    private var memberListView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(members, id: \.userId) { member in
                    MemberRowView(
                        member: member,
                        currentUserId: TXIoTEngine.getInstance().getLoginUserInfo()?.userId ?? "",
                        onDelete: {
                            memberToDelete = member
                            showDeleteMemberSheet = true
                        },
                        onLeave: {
                            NotificationCenter.default.post(
                                name: .memberRequestLeaveFamily,
                                object: nil
                            )
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func inviteTokenSheet(_ token: String) -> some View {
        CommonBottomSheet(
            title: L("🔑 Family Invite Code"),
            confirmTitle: L("📋 Copy"),
            sheetHeight: 210,
            onConfirm: {
                UIPasteboard.general.string = token
                inviteToken = nil
            },
            onCancel: { inviteToken = nil }
        ) {
            Text(token)
                .font(.system(size: 15, design: .monospaced))
                .foregroundColor(.textPrimary)
                .textSelection(.enabled)
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            .background(Color.inputBg)
            .cornerRadius(8)
            .sheetBorder(.borderColor, cornerRadius: 8)
            .padding(.horizontal, 20)
        }
    }

    private var joinFamilySheet: some View {
        CommonBottomSheet(
            title: L("🔗 Join Family"),
            confirmTitle: L("OK"),
            sheetHeight: 220,
            onConfirm: { joinFamily() },
            onCancel: {
                showJoinFamilySheet = false
                joinToken = ""
            }
        ) {
            Text(L("Please enter invite code"))
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0x6A / 255, green: 0x6E / 255, blue: 0x78 / 255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 4)
            TextField(L("Please enter invite code"), text: $joinToken)
                .autocorrectionDisabled().textInputAutocapitalization(.never).font(
                    .system(size: 15)
                )
                .frame(height: 44).padding(.horizontal, 12)
                .background(Color.inputBg).cornerRadius(8)
                .sheetBorder(.borderColor, cornerRadius: 8)
                .padding(.horizontal, 20)
        }
    }

    private var deleteMemberSheet: some View {
        let displayName = memberToDelete?.userId ?? ""
        return CommonBottomSheet(
            title: L("Remove Member"),
            confirmTitle: L("Delete"),
            confirmStyle: .danger,
            sheetHeight: 210,
            onConfirm: {
                showDeleteMemberSheet = false
                if let m = memberToDelete { deleteMember(m) }
            },
            onCancel: {
                showDeleteMemberSheet = false
                memberToDelete = nil
            }
        ) {
            Text(L("Are you sure you want to remove \"%@\" from the family?", "\(displayName)"))
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    @ViewBuilder
    private var memberToastOverlay: some View {
        if let msg = toastMessage {
            VStack {
                Spacer()
                AppToastView(message: msg)
                    .padding(.bottom, 40)
            }
            .transition(.opacity)
        }
    }

    private func loadMembers() {
        guard !familyId.isEmpty,
            let familyManager = TXIoTEngine.getInstance().getFamilyManager()
        else { return }
        isLoading = true
        let cb = TXIoTCallback<NSArray>()
        cb.onSuccess = { result in
            DispatchQueue.main.async {
                isLoading = false
                members = (result as? [TXIoTUserInfo]) ?? []
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                isLoading = false
                showToast(L("Failed to get member list: %@", "\(errorMessage ?? "")"))
            }
        }
        familyManager.getMemberList(familyId, callback: cb)
    }

    private func createInviteToken() {
        guard let familyManager = TXIoTEngine.getInstance().getFamilyManager() else {
            showToast(L("Not logged in or failed to get FamilyManager"))
            return
        }
        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { token in
            DispatchQueue.main.async {
                if let token = token as String? {
                    inviteToken = token
                } else {
                    showToast(L("Failed to create invite token"))
                }
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Failed to create invite token: %@", "\(errorMessage ?? "")"))
            }
        }
        familyManager.createFamilyInviteToken(familyId, callback: cb)
    }

    private func joinFamily() {
        let token = joinToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty,
            let familyManager = TXIoTEngine.getInstance().getFamilyManager()
        else {
            showToast(L("Please enter a valid invite token"))
            return
        }
        showJoinFamilySheet = false
        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                showToast(L("Joined family successfully"))
                joinToken = ""
                loadMembers()
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Failed to join: %@", "\(errorMessage ?? "")"))
            }
        }
        familyManager.joinFamily(asMember: token, callback: cb)
    }

    private func deleteMember(_ member: TXIoTUserInfo) {
        guard let familyManager = TXIoTEngine.getInstance().getFamilyManager() else { return }
        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                showToast(L("Member removed"))
                members.removeAll { $0.userId == member.userId }
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Failed to remove: %@", "\(errorMessage ?? "")"))
            }
        }
        familyManager.removeMember(fromFamily: familyId, userId: member.userId, callback: cb)
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - 成员行视图

struct MemberRowView: View {
    let member: TXIoTUserInfo
    let currentUserId: String
    let onDelete: () -> Void
    let onLeave: () -> Void

    private var isSelf: Bool { member.userId == currentUserId }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        isSelf ? Color.warningColor.opacity(0.15) : Color.primaryColor.opacity(0.15)
                    )
                    .frame(width: 44, height: 44)
                Text(String(member.userId.prefix(1)))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelf ? .warningColor : .primaryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(member.userId)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.textPrimary)
                    if member.role == .admin {
                        Text(L("Admin"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primaryColor)
                            .cornerRadius(4)
                    }
                    if isSelf {
                        Text(L("Me"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.warningColor)
                            .cornerRadius(4)
                    }
                }
                Text(L("Nickname: %@", "\(member.nickName)"))
                    .font(.system(size: 12))
                    .foregroundColor(.textDisabled)
            }

            Spacer()

            if isSelf {
                Button(action: onLeave) {
                    Text(L("Leave"))
                        .font(.system(size: 13))
                        .foregroundColor(.dangerColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .sheetBorder(.dangerColor, cornerRadius: 6)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onDelete) {
                    Text(L("Delete"))
                        .font(.system(size: 13))
                        .foregroundColor(.dangerColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .sheetBorder(.dangerColor, cornerRadius: 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - 通用 Token 展示 Sheet

struct ShareTokenSheet: View {
    let title: String
    let token: String
    let description: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "key.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.primaryColor)
                Text(token)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button(action: {
                    UIPasteboard.general.string = token
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text(L("Copy Token"))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.primaryColor)
                    .cornerRadius(8)
                }
                .padding(.horizontal, 24)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Done")) { onDismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - 通用 Token 输入 Sheet

struct JoinTokenSheet: View {
    let title: String
    let placeholder: String
    @Binding var token: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Token")) {
                    TextField(placeholder, text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Text(L("Please enter the token shared with you, then tap Confirm to complete."))
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Confirm")) { onConfirm() }
                        .font(.system(size: 16, weight: .semibold))
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

// MARK: - 设备分享管理

struct DeviceSharingView: View {
    @EnvironmentObject var deviceViewModel: DeviceViewModel
    @State private var selectedDevice: Device?
    @State private var sharedUsers: [TXIoTUserInfo] = []
    @State private var isLoadingUsers = false
    @State private var userToRemove: TXIoTUserInfo?
    @State private var toastMessage: String?
    @State private var shareToken: String? = nil
    @State private var showSharedUsersSheet = false
    @State private var sharedUserCounts: [String: Int] = [:]

    var body: some View {
        ScrollView {
            deviceListView
        }
        .background(Color.bgColor)
        .overlay(alignment: .bottom) { toastOverlay }
        .onAppear {
            onShareViewAppear()
            loadAllSharedUserCounts()
        }
        .onChange(of: deviceViewModel.devices) { onDevicesChange($0) }
        .sheet(isPresented: $showSharedUsersSheet) {
            sharedUsersSheet
        }
        .sheet(item: $shareToken) { shareTokenSheet($0) }
    }

    // MARK: - 提取的子视图

    private var deviceListView: some View {
        let ownedDevices = deviceViewModel.devices.filter { !$0.isShared }
        return VStack(spacing: 10) {
            if ownedDevices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.textDisabled)
                    Text(L("No Devices"))
                        .font(.system(size: 14))
                        .foregroundColor(.textDisabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color.cardBg)
                .cornerRadius(12)
            } else {
                ForEach(ownedDevices) { device in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.primaryColor.opacity(0.12))
                                .frame(width: 44, height: 44)
                            Image(systemName: "video.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.primaryColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            if let count = sharedUserCounts[device.id] {
                                Label(L("%@ users", "\(count)"), systemImage: "person.2")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        Spacer()

                        Menu {
                            Button(action: {
                                selectedDevice = device
                                createShareToken()
                            }) {
                                Label(L("Create Share"), systemImage: "person.badge.plus")
                            }
                            Button(action: {
                                selectedDevice = device
                                loadSharedUsers(for: device)
                                showSharedUsersSheet = true
                            }) {
                                Label(L("Shared Users"), systemImage: "person.2")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    .onTapGesture {
                        selectedDevice = device
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var sharedUsersContent: some View {
        if isLoadingUsers {
            ProgressView(L("Loading..."))
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
                .padding(.top, 20)
        } else if sharedUsers.isEmpty {
            Spacer()
            emptyStateView(icon: "person.crop.circle.badge.xmark", text: L("No shared users"))
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sharedUsers, id: \.userId) { user in
                        SharedUserRowView(user: user) {
                            userToRemove = user
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        Divider().padding(.leading, 20)
                    }
                }
            }
        }
    }

    private func emptyStateView(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.textDisabled)
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.textDisabled)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color.cardBg)
    }

    // MARK: - 生命周期回调（提取以减少 body 复杂度）

    private var toastOverlay: some View {
        Group {
            if let msg = toastMessage {
                AppToastView(message: msg)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
    }

    private func onShareViewAppear() {
        if selectedDevice == nil {
            selectedDevice = deviceViewModel.devices.first
            if let d = selectedDevice { loadSharedUsers(for: d) }
        }
    }

    private func onDevicesChange(_ newDevices: [Device]) {
        let currentId = selectedDevice?.id
        if let matched = newDevices.first(where: { $0.id == currentId }) {
            selectedDevice = matched
            loadSharedUsers(for: matched)
        } else {
            selectedDevice = newDevices.first
            sharedUsers = []
            if let d = selectedDevice { loadSharedUsers(for: d) }
        }
    }

    // MARK: - Sheet content（提取以减少 body 复杂度）

    private var sharedUsersSheet: some View {
        let deviceName = selectedDevice?.name ?? ""
        return CommonBottomSheet(
            title: L("Shared Users"),
            hint: deviceName,
            confirmTitle: nil,
            sheetHeight: 420,
            onCancel: { showSharedUsersSheet = false }
        ) {
            sharedUsersContent
                .sheet(item: $userToRemove) { user in
                    removeUserSheet(for: user)
                }
        }
    }

    private func removeUserSheet(for user: TXIoTUserInfo) -> some View {
        CommonBottomSheet(
            title: L("Remove Shared User"),
            confirmTitle: L("Remove"),
            confirmStyle: .danger,
            sheetHeight: 210,
            onConfirm: {
                userToRemove = nil
                onRemoveShareUser(with: user)
            },
            onCancel: {
                userToRemove = nil
            }
        ) {
            Text(L("Are you sure you want to remove the sharing permission of user \"%@\"?", "\(user.userId)"))
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.top, 24)
        }
    }

    private func shareTokenSheet(_ token: String) -> some View {
        CommonBottomSheet(
            title: L("🔑 Device Share Code"),
            confirmTitle: L("📋 Copy Share Code"),
            sheetHeight: 300,
            onConfirm: {
                UIPasteboard.general.string = token
                shareToken = nil
            },
            onCancel: { shareToken = nil }
        ) {
            ScrollView {
                Text(token)
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .frame(height: 132)
            .background(Color.inputBg)
            .cornerRadius(8)
            .sheetBorder(.borderColor, cornerRadius: 8)
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private func onRemoveShareUser(with user: TXIoTUserInfo) {
        if let d = selectedDevice { removeSharedUser(user, from: d) }
    }

    // MARK: - 分享给我的设备数据加载

    // MARK: - 已分享用户相关方法

    private func loadSharedUsers(for device: Device) {
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else { return }
        let deviceId = makeDeviceId(device)
        isLoadingUsers = true
        let cb = TXIoTCallback<NSArray>()
        cb.onSuccess = { result in
            DispatchQueue.main.async {
                isLoadingUsers = false
                sharedUsers = (result as? [TXIoTUserInfo]) ?? []
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                isLoadingUsers = false
                showToast(L("Failed to get shared users: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.getDeviceSharedUsers(deviceId, callback: cb)
    }

    private func loadAllSharedUserCounts() {
        let ownedDevices = deviceViewModel.devices.filter { !$0.isShared }
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else { return }
        for device in ownedDevices {
            let deviceId = makeDeviceId(device)
            let cb = TXIoTCallback<NSArray>()
            cb.onSuccess = { result in
                let users = (result as? [TXIoTUserInfo]) ?? []
                DispatchQueue.main.async {
                    sharedUserCounts[device.id] = users.count
                }
            }
            deviceManager.getDeviceSharedUsers(deviceId, callback: cb)
        }
    }

    private func removeSharedUser(_ user: TXIoTUserInfo, from device: Device) {
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else { return }
        let deviceId = makeDeviceId(device)
        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                showToast(L("Shared user removed"))
                sharedUsers.removeAll { $0.userId == user.userId }
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Failed to remove: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.removeDeviceSharedUser(deviceId, userId: user.userId, callback: cb)
    }

    private func createShareToken() {
        guard let device = selectedDevice,
            let deviceManager = TXIoTEngine.getInstance().getDeviceManager()
        else {
            showToast(L("Please select a device first"))
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
        let deviceId = makeDeviceId(device)
        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { token in
            DispatchQueue.main.async {
                guard let token = token as String? else {
                    showToast(L("Failed to create share token"))
                    return
                }
                let payload: [String: String] = [
                    "productId": device.productId,
                    "deviceName": device.deviceName,
                    "token": token,
                ]
                if let data = try? JSONSerialization.data(
                    withJSONObject: payload,
                    options: .prettyPrinted
                ),
                    let jsonString = String(data: data, encoding: .utf8)
                {
                    shareToken = jsonString
                } else {
                    showToast(L("Failed to create share token"))
                }
            }
        }
        cb.onError = { errorCode, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Failed to create share token: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.createDeviceSharingToken(familyId, deviceId: deviceId, callback: cb)
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - 分享给我的设备页面

struct SharedToMeView: View {
    @EnvironmentObject var deviceViewModel: DeviceViewModel
    @State private var sharedToMeDevices: [DeviceInfoItem] = []
    @State private var isLoadingSharedToMe = false
    @State private var deviceIdToUnbind: String?
    @State private var toastMessage: String?
    @State private var showBindShareSheet = false
    @State private var bindShareToken = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    if isLoadingSharedToMe {
                        ProgressView(L("Loading..."))
                            .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
                            .padding()
                    } else if sharedToMeDevices.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "video.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.textDisabled)
                            Text(L("No devices shared with me"))
                                .font(.system(size: 14))
                                .foregroundColor(.textDisabled)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(sharedToMeDevices, id: \.deviceId) { deviceInfo in
                                SharedToMeDeviceRow(
                                    deviceInfo: deviceInfo,
                                    onUnbind: {
                                        deviceIdToUnbind = deviceInfo.deviceId
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.bottom, 80)
            }

            // 绑定分享按钮（固定在底部）
            bindShareButton
        }
        .background(Color.bgColor)
        .overlay(alignment: .bottom) {
            if let msg = toastMessage {
                AppToastView(message: msg)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .onAppear { loadSharedToMeDevices() }
        .sheet(item: $deviceIdToUnbind) { deviceId in
            unbindSheet(forDeviceId: deviceId)
        }
        .sheet(isPresented: $showBindShareSheet) {
            bindShareSheet
        }
    }

    // MARK: - 绑定分享按钮

    private var bindShareButton: some View {
        Button(action: { showBindShareSheet = true }) {
            HStack(spacing: 6) {
                Image(systemName: "link.badge.plus").font(.system(size: 14))
                Text(L("Bind Share")).font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.primaryColor)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .sheetBorder(.primaryColor, cornerRadius: 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.bgColor)
    }

    // MARK: - 绑定分享 Sheet

    private var bindShareSheet: some View {
        CommonBottomSheet(
            title: L("🔗 Bind Shared Device"),
            hint: nil,
            confirmTitle: L("OK"),
            sheetHeight: 300,
            onConfirm: { bindSharedDevice() },
            onCancel: {
                showBindShareSheet = false
                bindShareToken = ""
            }
        ) {
            Text(L("Please enter device share code"))
                .font(.system(size: 13))
                .foregroundColor(Color(red: 0x6A / 255, green: 0x6E / 255, blue: 0x78 / 255))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)

            TextEditor(text: $bindShareToken)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.system(size: 15))
                .frame(height: 132)
                .padding(.horizontal, 8)
                .background(Color.inputBg)
                .cornerRadius(8)
                .sheetBorder(.borderColor, cornerRadius: 8)
                .padding(.horizontal, 20)
                .onAppear { UITextView.appearance().backgroundColor = .clear }
                .onDisappear { UITextView.appearance().backgroundColor = nil }
        }
    }

    // MARK: - 绑定分享设备

    private func bindSharedDevice() {
        let jsonString = bindShareToken.trimmingCharacters(in: .whitespaces)
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
        let deviceId = TXIoTDeviceId()
        deviceId.productId = productId
        deviceId.deviceName = deviceName
        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                showToast(L("Device bound successfully"))
                bindShareToken = ""
                deviceViewModel.loadDevicesFromAPI()
                loadSharedToMeDevices()
            }
        }
        cb.onError = { _, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Binding failed: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.bindDeviceShared(withMe: deviceId, shareToken: token, callback: cb)
    }

    // MARK: - 加载分享给我的设备

    private func loadSharedToMeDevices() {
        guard
            let familyId = DeviceAPIBridge.currentFamilyId
                ?? UserDefaults.standard.string(forKey: "firstFamilyId"),
            !familyId.isEmpty
        else { return }
        isLoadingSharedToMe = true
        DeviceAPIBridge.getSharedDeviceList(withFamilyId: familyId) { success, deviceList, _ in
            MainActor.assumeIsolated {
                handleSharedToMeDevices(success: success, deviceList: deviceList)
            }
        }
    }

    /// 过滤出"分享给我且不在自有列表中"的设备
    private func handleSharedToMeDevices(success: Bool, deviceList: [DeviceInfoItem]?) {
        isLoadingSharedToMe = false
        guard success, let list = deviceList else { return }
        let ownedIds = Set(deviceViewModel.devices.map { "\($0.productId)/\($0.deviceName)" })
        sharedToMeDevices = list.filter {
            let key = "\($0.productId)/\($0.deviceName)"
            return !ownedIds.contains(key) || deviceViewModel.sharedDeviceKeys.contains(key)
        }
    }

    // MARK: - 解除绑定

    private func revokeSharedToMeDevice(_ deviceInfo: DeviceInfoItem) {
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else { return }
        let did = TXIoTDeviceId()
        did.productId = deviceInfo.productId
        did.deviceName = deviceInfo.deviceName
        let cb = TXIoTVoidCallback()
        cb.onSuccess = {
            DispatchQueue.main.async {
                showToast(L("Share revoked"))
                sharedToMeDevices.removeAll { $0.deviceId == deviceInfo.deviceId }
            }
        }
        cb.onError = { _, errorMessage in
            DispatchQueue.main.async {
                showToast(L("Failed to revoke: %@", "\(errorMessage ?? "")"))
            }
        }
        deviceManager.unbindDeviceShared(withMe: did, callback: cb)
    }

    private func unbindSheet(forDeviceId deviceId: String) -> some View {
        let device = sharedToMeDevices.first { $0.deviceId == deviceId }
        let displayName = (device?.aliasName.isEmpty == false ? device?.aliasName : device?.deviceName) ?? ""
        return CommonBottomSheet(
            title: L("Remove Binding"),
            confirmTitle: L("Confirm Unbind"),
            confirmStyle: .danger,
            sheetHeight: 210,
            onConfirm: {
                deviceIdToUnbind = nil
                if let d = device { revokeSharedToMeDevice(d) }
            },
            onCancel: { deviceIdToUnbind = nil }
        ) {
            (
                Text(L("Do you want to unbind the device shared with you \""))
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                + Text(displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primaryColor)
                + Text(L("\"? The device will no longer appear after unbinding."))
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
            )
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
    }

    private func showToast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}

// MARK: - 分享给我的设备行视图

struct SharedToMeDeviceRow: View {
    let deviceInfo: DeviceInfoItem
    let onUnbind: () -> Void

    private var displayName: String {
        deviceInfo.aliasName.isEmpty ? deviceInfo.deviceName : deviceInfo.aliasName
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primaryColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "video.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primaryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text("ProductId: \(deviceInfo.productId)")
                    .font(.system(size: 12))
                    .foregroundColor(.textDisabled)
            }

            Spacer()

            Button(action: onUnbind) {
                Text(L("Remove Binding"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.dangerColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .sheetBorder(.dangerColor, cornerRadius: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - 分享用户行视图（对齐 DeviceRoomRowView 样式）

struct SharedUserRowView: View {
    let user: TXIoTUserInfo
    let onRemove: () -> Void

    private var displayNickName: String {
        let nick = user.nickName
        return nick.isEmpty ? L("Nickname not set") : nick
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primaryColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.primaryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(user.userId)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.textPrimary)
                Text(L("Nickname: %@", "\(displayNickName)"))
                    .font(.system(size: 12))
                    .foregroundColor(.textDisabled)
            }

            Spacer()

            Button(action: onRemove) {
                Text(L("Remove"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.dangerColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .sheetBorder(.dangerColor, cornerRadius: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 公共辅助函数

private func makeDeviceId(_ device: Device) -> TXIoTDeviceId {
    let did = TXIoTDeviceId()
    did.productId = device.productId
    did.deviceName = device.deviceName
    return did
}

#Preview {
    FamilyManageView()
        .environmentObject(DeviceViewModel())
}
