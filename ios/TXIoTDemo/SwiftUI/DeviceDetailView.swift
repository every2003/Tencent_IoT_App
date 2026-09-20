import AVFoundation
import Combine
import Photos
import SwiftUI
import TXLiteAVSDK_IOT

// MARK: - ViewModel

@MainActor
class DeviceDetailViewModel: NSObject, ObservableObject, TXIoTMonitorSessionDelegate {
    let device: Device
    let channelList: [Int]

    /// 本页在 ScreenAwakeManager 中的常亮持有者标识
    /// （统一走管理器仲裁，避免与云存回看等其它业务互相覆盖系统息屏开关）
    private let screenAwakeOwnerId = "DeviceDetail-\(UUID().uuidString)"

    // 当前操作的通道 ID（对齐 Android currentChannelId）
    var activeChannelId: Int { channelList.first ?? 0 }

    @Published var sessionEstablished = false
    @Published var isFullscreen = false
    @Published var showLoading = false
    @Published var isStreamFailed = false

    @Published var isMuted = false
    @Published var isHighQuality = true
    @Published var isTalking = false
    @Published var recordingDurationMs: Int64 = 0

    /// 正在录像的通道集合；isRecording 由此推导
    @Published private(set) var recordingChannels: Set<Int> = []
    var isRecording: Bool { !recordingChannels.isEmpty }

    @Published var toastMessage: String?
    @Published var toastIsError = false

    // MARK: - 远程视频渲染视图

    @Published var remoteVideoViews: [Int: UIView] = [:]

    // MARK: - 内部状态

    private var isFirstSession = true
    nonisolated(unsafe) var mediaSession: TXIoTMonitorSession?
    nonisolated(unsafe) private var toastWorkItem: DispatchWorkItem?

    var onSessionEstablishedCallback: (() -> Void)?
    var onSessionError: ((String) -> Void)?

    init(device: Device, channelList: [Int]) {
        self.device = device
        self.channelList = channelList
        super.init()
        for ch in channelList {
            self.remoteVideoViews[ch] = UIView()
        }
    }

    deinit {
        toastWorkItem?.cancel()
        mediaSession?.stop()
    }

    private func show(_ message: String) {
        toastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
            toastIsError = false
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.toastMessage = nil
            }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    /// 供 View 层调用的 Toast 方法
    func showToastMessage(_ message: String) {
        show(message)
    }

    private func showError(_ message: String) {
        toastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            toastMessage = message
            toastIsError = true
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.toastMessage = nil
            }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    // MARK: - TXIoTMonitorSessionDelegate

    nonisolated func onError(_ channelId: Int, errorCode: TXIoTErrorCode, errorMessage: String) {
        print("Media session error: channelId=\(channelId), \(errorCode.rawValue), \(errorMessage)")
        if errorCode == .deviceSwitchToVoIP {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.stopAllRemoteViews()
                ScreenAwakeManager.release(self.screenAwakeOwnerId)
                self.showError(L("Device switched to call mode, streaming stopped"))
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isStreamFailed = true
            self.sessionEstablished = false
            self.showLoading = true
            ScreenAwakeManager.release(self.screenAwakeOwnerId)
            self.stopAllRemoteViews()
            self.mediaSession?.stop()
            self.onSessionError?(errorMessage)
            self.showError(L("Streaming failed: %@", "\(errorMessage)"))
        }
    }

    nonisolated func onSessionEstablished() {
        print("Media session established")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.sessionEstablished = true
            self.isStreamFailed = false
            self.show(L("Connected"))
            ScreenAwakeManager.acquire(self.screenAwakeOwnerId)
            self.startRemoteViews()
            self.showLoading = false
            self.onSessionEstablishedCallback?()
        }
    }

    nonisolated func onSessionReconnecting() {
        print("Media session reconnecting...")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.sessionEstablished = false
            self.show(L("Reconnecting..."))
            if !self.isStreamFailed {
                self.showLoading = true
            }
        }
    }

    nonisolated func onSessionRecovery() {
        print("Media session resumed")
        Task { @MainActor [weak self] in
            self?.sessionEstablished = true
            self?.show(L("Connection restored"))
            self?.showLoading = false
        }
    }

    nonisolated func onRenderFirstFrame(_ channelId: Int) {
        print("First frame rendered: channelId=\(channelId)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isStreamFailed = false
            self.showLoading = false
        }
    }

    nonisolated func onPlayStateChanged(_ channelId: Int, state: TXIoTPlayState) {
        print("Playback state changed: channelId=\(channelId), state=\(state.rawValue)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let loading = state != .playing
            if !self.isStreamFailed {
                self.showLoading = loading
            }
        }
    }

    nonisolated func onLocalRecordBegin(
        _ channelId: Int,
        errorCode: TXIoTErrorCode,
        storagePath: String
    ) {
        print("Recording started callback: channelId=\(channelId), errorCode=\(errorCode.rawValue), path=\(storagePath)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if errorCode == .success {
                self.recordingChannels.insert(channelId)
                self.recordingDurationMs = 0
                if self.recordingChannels.count == 1 {
                    self.show(L("Recording started"))
                }
            } else {
                self.showError(L("Failed to start recording on channel %@", "\(channelId)"))
            }
        }
    }

    nonisolated func onLocalRecording(_ channelId: Int, durationMs: Int64, storagePath: String) {
        Task { @MainActor [weak self] in
            self?.recordingDurationMs = durationMs
        }
    }

    nonisolated func onLocalRecordComplete(
        _ channelId: Int,
        errorCode: TXIoTErrorCode,
        storagePath: String
    ) {
        print("Recording finished callback: channelId=\(channelId), errorCode=\(errorCode.rawValue), path=\(storagePath)")
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.recordingChannels.remove(channelId)
            if self.recordingChannels.isEmpty {
                self.recordingDurationMs = 0
            }
            if errorCode == .success {
                self.saveVideoToAlbum(filePath: storagePath)
            } else {
                self.showError(L("Recording failed on channel %@", "\(channelId)"))
            }
        }
    }

    nonisolated func onSnapshotComplete(
        _ channelId: Int,
        image: UIImage?,
        errorCode: TXIoTErrorCode
    ) {
        print("Snapshot callback: channelId=\(channelId), errorCode=\(errorCode.rawValue)")
        guard errorCode == .success, let image = image else {
            Task { @MainActor [weak self] in
                self?.showError(L("Screenshot failed"))
            }
            return
        }
        Self.saveImageToAlbum(image: image) { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.show(msg)
            }
            _ = self
        }
    }

    // MARK: - 辅助：保存图片到相册

    nonisolated private static func saveImageToAlbum(
        image: UIImage,
        completion: @escaping @Sendable (String) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(L("Screenshot failed: no photo library permission"))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                let msg = success
                    ? L("Screenshot saved to album")
                    : L("Failed to save screenshot: %@", "\(error?.localizedDescription ?? L("Unknown error"))")
                completion(msg)
            }
        }
    }

    private func saveVideoToAlbum(filePath: String) {
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            showError(L("Recording file does not exist"))
            return
        }
        Self.saveVideoToAlbum(fileURL: fileURL) { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.show(msg)
            }
            _ = self
        }
    }

    nonisolated private static func saveVideoToAlbum(
        fileURL: URL,
        completion: @escaping @Sendable (String) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(L("Failed to save recording: no photo library permission"))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { success, error in
                try? FileManager.default.removeItem(at: fileURL)
                let msg = success
                    ? L("Recording saved to album")
                    : L("Failed to save recording: %@", "\(error?.localizedDescription ?? L("Unknown error"))")
                completion(msg)
            }
        }
    }

    private func stopAllRemoteViews() {
        for channelId in channelList {
            mediaSession?.stopRemoteView(channelId)
        }
    }

    private func startRemoteViews() {
        let streamType: TXIoTStreamType = isHighQuality ? .HD : .SD
        for channelId in channelList {
            if let view = remoteVideoViews[channelId] {
                mediaSession!.startRemoteView(channelId, streamType: streamType, view: view)
                print("startRemoteView: channelId=\(channelId), streamType=\(streamType.rawValue)")
            }
        }
    }

    /// 用户点击重试拉流
    func retryStream() {
        print("User tapped retry streaming")
        isStreamFailed = false
        showLoading = true
        let familyId =
            DeviceAPIBridge.currentFamilyId
            ?? UserDefaults.standard.string(forKey: "firstFamilyId")
            ?? ""
        guard !familyId.isEmpty else {
            print("Family ID not found")
            return
        }
        let deviceId = TXIoTDeviceId()
        deviceId.productId = device.productId
        deviceId.deviceName = device.deviceName

        guard let session = mediaSession else {
            print("Media session already released")
            return
        }
        startRemoteViews()
        session.muteAllRemoteAudio(isMuted)
        session.start(deviceId)
        print("Retry streaming finished")
    }

    func startVideoCall(channelViews: [Int: UIView]) {
        let familyId =
            DeviceAPIBridge.currentFamilyId
            ?? UserDefaults.standard.string(forKey: "firstFamilyId")
            ?? ""
        guard !familyId.isEmpty else {
            print("Family ID not found, cannot start video session")
            return
        }
        let deviceId = TXIoTDeviceId()
        deviceId.productId = device.productId
        deviceId.deviceName = device.deviceName

        guard let session = TXIoTEngine.getInstance().getMonitorSession() else {
            print("Failed to get TXIoTMonitorSession, please check login status")
            return
        }
        session.add(self)
        self.mediaSession = session

        if isFirstSession {
            isFirstSession = false
            isMuted = true
        }

        showLoading = true
        startRemoteViews()
        session.muteAllRemoteAudio(isMuted)
        session.start(deviceId)
        print("TXIoTMonitorSession started, device: \(device.productId)/\(device.deviceName), channels: \(channelList)")
    }

    func startVideoCall(remoteView: UIView) {
        startVideoCall(channelViews: [channelList.first ?? 0: remoteView])
    }

    /// 停止会话
    /// 退后台时自动停止拉流；若正在对讲或录像，也一并停止。
    /// 回到前台后仅恢复拉流，不自动恢复对讲/录像。
    func pauseSession() {
        guard let session = mediaSession else { return }
        if isTalking {
            session.stopLocalAudio()
            isTalking = false
        }
        if isRecording {
            for channelId in channelList {
                session.stopLocalRecording(channelId)
            }
            recordingChannels.removeAll()
            recordingDurationMs = 0
        }
        stopAllRemoteViews()
        session.stop()
        sessionEstablished = false
        ScreenAwakeManager.release(screenAwakeOwnerId)
        print("Entering background, stopping session")
    }

    /// 重启会话
    /// 回到前台后自动恢复拉流，但不自动恢复对讲/录像。
    func resumeSession() {
        guard let session = mediaSession else { return }
        if isStreamFailed {
            print("Back to foreground, but streaming already failed, waiting for user retry")
            return
        }
        showLoading = true
        let deviceId = TXIoTDeviceId()
        deviceId.productId = device.productId
        deviceId.deviceName = device.deviceName
        startRemoteViews()
        session.muteAllRemoteAudio(isMuted)
        session.start(deviceId)
        ScreenAwakeManager.acquire(screenAwakeOwnerId)
        print("Back to foreground, restarting session")
    }

    /// 完全销毁
    func stopVideoCall() {
        guard let session = mediaSession else { return }
        if isTalking {
            session.stopLocalAudio()
            isTalking = false
        }
        if isRecording {
            for channelId in channelList {
                session.stopLocalRecording(channelId)
            }
            recordingChannels.removeAll()
        }
        stopAllRemoteViews()
        session.stop()
        session.remove(self)
        mediaSession = nil
        sessionEstablished = false
        ScreenAwakeManager.release(screenAwakeOwnerId)
        print("TXIoTMonitorSession destroyed")
    }

    func toggleTalk() {
        if isTalking {
            isTalking = false
            mediaSession?.stopLocalAudio()
            show(L("Talkback off"))
        } else {
            isTalking = true
            mediaSession?.startLocalAudio()
            show(L("Talkback on"))
        }
    }

    func toggleQuality() {
        isHighQuality.toggle()
        let streamType: TXIoTStreamType = isHighQuality ? .HD : .SD
        for channelId in channelList {
            mediaSession?.switchRemoteStream(channelId, streamType: streamType)
        }
        show(isHighQuality ? L("Switched to HD") : L("Switched to SD"))
    }

    var qualityLabel: String {
        isHighQuality ? L("HD") : L("SD")
    }

    func toggleMute() {
        isMuted.toggle()
        mediaSession?.muteAllRemoteAudio(isMuted)
        show(isMuted ? L("Muted") : L("Sound on"))
    }

    /// 多通道串行截图（间隔 0.5s，避免 SDK 并发调用被吞）
    func takeSnapshot() {
        let channels = channelList
        guard !channels.isEmpty else { return }
        takeSnapshotForChannel(at: 0, channels: channels)
    }

    private func takeSnapshotForChannel(at index: Int, channels: [Int]) {
        guard index < channels.count else { return }
        mediaSession?.takeSnapshot(channels[index])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.takeSnapshotForChannel(at: index + 1, channels: channels)
        }
    }

    /// 多通道同时开始/停止录像
    func toggleRecording() {
        if isRecording {
            for channelId in channelList {
                mediaSession?.stopLocalRecording(channelId)
            }
        } else {
            // 开始所有通道的录像
            let timestamp = Int(Date().timeIntervalSince1970)
            for channelId in channelList {
                let fileName = "record_ch\(channelId)_\(timestamp).mp4"
                let filePath = NSTemporaryDirectory() + fileName
                let params = TXIoTLocalRecordingParams()
                params.filePath = filePath
                mediaSession?.startLocalRecording(channelId, params: params)
            }
        }
    }

    /// 录像时长格式化
    var recordingDurationText: String {
        let totalSec = recordingDurationMs / 1000
        let min = totalSec / 60
        let sec = totalSec % 60
        return String(format: "● REC %02d:%02d", min, sec)
    }

    func toggleFullscreen() {
        isFullscreen.toggle()
        let targetOrientation: UIInterfaceOrientation = isFullscreen ? .landscapeRight : .portrait
        let targetMask: UIInterfaceOrientationMask = isFullscreen ? .landscapeRight : .portrait

        AppDelegate.setAllowedOrientations(targetMask)

        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(
                    interfaceOrientations: targetMask
                )
                windowScene.requestGeometryUpdate(geometryPreferences) { error in
                    print("Failed to rotate screen: \(error.localizedDescription)")
                }
                UIDevice.current.setValue(targetOrientation.rawValue, forKey: "orientation")
            }
        } else {
            UIDevice.current.setValue(targetOrientation.rawValue, forKey: "orientation")
            UINavigationController.attemptRotationToDeviceOrientation()
        }
    }

    func sendPTZCommand(channelId: Int, command: TXIoTPTZCommand) {
        mediaSession?.sendPTZCommand(channelId, command: command, speed: 5)
        print("PTZ command sent: channelId=\(channelId), command=\(command.rawValue)")
    }

    func sendPTZCenterCommand() {
        sendDeviceCommand(jsonData: "{\"cmd\":\"center\"}")
    }

    func createShareToken(completion: @escaping (String?) -> Void) {
        let familyId =
            DeviceAPIBridge.currentFamilyId
            ?? UserDefaults.standard.string(forKey: "firstFamilyId")
            ?? ""
        guard !familyId.isEmpty else {
            print("Family ID not found, cannot share device")
            completion(nil)
            return
        }
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            print("Failed to get DeviceManager")
            completion(nil)
            return
        }
        let deviceId = TXIoTDeviceId()
        deviceId.productId = device.productId
        deviceId.deviceName = device.deviceName

        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { [weak self] tokenStr in
            guard let self = self else { return }
            let token = (tokenStr as String?) ?? ""
            let payload: [String: String] = [
                "productId": self.device.productId,
                "deviceName": self.device.deviceName,
                "token": token,
            ]
            if let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: .prettyPrinted
            ),
                let jsonString = String(data: data, encoding: .utf8)
            {
                print("Device share token created")
                completion(jsonString)
            } else {
                completion(nil)
            }
        }
        cb.onError = { errorCode, errorMessage in
            print("Failed to create share token: \(errorMessage ?? "")")
            completion(nil)
        }
        deviceManager.createDeviceSharingToken(familyId, deviceId: deviceId, callback: cb)
    }

    func sendDeviceCommand(jsonData: String) {
        let familyId =
            DeviceAPIBridge.currentFamilyId
            ?? UserDefaults.standard.string(forKey: "firstFamilyId")
            ?? ""
        guard !familyId.isEmpty else {
            print("Family ID not found, cannot send device command")
            return
        }
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            print("Failed to get DeviceManager")
            return
        }
        let deviceId = TXIoTDeviceId()
        deviceId.productId = device.productId
        deviceId.deviceName = device.deviceName

        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { [weak self] result in
            Task { @MainActor in self?.show(L("Command sent successfully")) }
            print("Device command sent, response: \(result ?? "")")
        }
        cb.onError = { [weak self] errorCode, errorMessage in
            Task { @MainActor in self?.showError(L("Failed to send command: %@", "\(errorMessage ?? "")")) }
            print("Failed to send device command: \(errorMessage ?? "")")
        }
        deviceManager.sendCommand(deviceId, jsonData: jsonData, callback: cb)
        print("Sending device command: \(jsonData)")
    }

    func getRemoteVideoView() -> UIView {
        return channelList.first.flatMap { remoteVideoViews[$0] } ?? UIView()
    }
}

struct DeviceDetailView: View {
    let device: Device
    let channelList: [Int]

    /// 本页在 ScreenAwakeManager 中的常亮持有者标识（避免与云存回看等其它业务互相覆盖息屏开关）
    private let screenAwakeOwnerId = "DeviceDetail-\(UUID().uuidString)"
    @StateObject private var viewModel: DeviceDetailViewModel

    private let ctrlBtnTint = Color(red: 0x00 / 255, green: 0x6E / 255, blue: 0xFF / 255)
    private let ptzDiskFill = Color(red: 0xF5 / 255, green: 0xF7 / 255, blue: 0xFA / 255)
    private let ptzDiskStroke = Color(red: 0xE7 / 255, green: 0xE8 / 255, blue: 0xEB / 255)

    // 分享相关
    @State private var showShareSheet = false
    @State private var shareJSON: String = ""
    @State private var showShareFailAlert = false

    @Environment(\.dismiss) private var dismiss

    init(device: Device, channelList: [Int]) {
        self.device = device
        self.channelList = channelList
        self._viewModel = StateObject(
            wrappedValue: DeviceDetailViewModel(device: device, channelList: channelList)
        )
    }

    var body: some View {
        ZStack {
            Color(red: 0x0D / 255, green: 0x0D / 255, blue: 0x0D / 255)
                .ignoresSafeArea()
            if viewModel.isFullscreen {
                fullscreenView
            } else {
                portraitView
            }
        }
        .navigationBarHidden(true)
        .onAppear { onViewAppear() }
        .onDisappear { viewModel.stopVideoCall() }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
        ) { _ in
            viewModel.pauseSession()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            viewModel.resumeSession()
        }
        .sheet(isPresented: $showShareSheet) { shareSheetContent }
        .alert(L("Share Failed"), isPresented: $showShareFailAlert) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L("Unable to create device share token. Please try again later."))
        }
        .overlay(toastOverlayView)
    }

    // MARK: - Toast

    private var toastOverlayView: some View {
        Group {
            if let msg = viewModel.toastMessage {
                VStack {
                    Spacer()
                    AppToastView(message: msg, isError: viewModel.toastIsError)
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: viewModel.toastMessage != nil)
            }
        }
    }

    // MARK: - 导航栏（渐变背景，设备名为标题，右侧通道信息）

    private var navBar: some View {
        HStack(spacing: 0) {
            NavBackButton(action: { dismiss() })

            Spacer()

            Text(device.name)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            channelInfoBadge
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 44)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Color.headerGradient.ignoresSafeArea(edges: .top))
    }

    // MARK: - 生命周期

    private func onViewAppear() {
        setupSessionCallbacks()
    }

    // MARK: - 全屏视图

    private var fullscreenView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            videoPlayerContent.ignoresSafeArea()
        }
    }

    private var portraitView: some View {
        VStack(spacing: 0) {
            // 导航栏（渐变背景，设备名为标题，右侧通道信息）
            navBar

            videoPlayerContent.frame(height: 280)

            controlBar

            ptzControlPanel

            Spacer(minLength: 0)

            bottomActionButtons
        }
    }

    private var channelInfoBadge: some View {
        InfoCapsule(text: channelInfoText)
    }

    private var channelInfoText: String {
        channelList.count <= 1
            ? L("Single Channel")
            : L("Multi-channel (%@)", "\(channelList.count)")
    }

    // MARK: - 会话初始化

    private func setupSessionCallbacks() {
        viewModel.onSessionEstablishedCallback = {
            print("DeviceDetailView: media session established")
        }
        viewModel.onSessionError = { errorMessage in
            print("DeviceDetailView: media session error - \(errorMessage)")
        }
        viewModel.startVideoCall(channelViews: viewModel.remoteVideoViews)
    }

    private var videoPlayerContent: some View {
        ZStack {
            Color.black

            MultiChannelGridView(
                channelList: channelList,
                channelViews: viewModel.remoteVideoViews,
                activeChannelId: viewModel.activeChannelId,
                onTapChannel: { _ in }
            )

            if viewModel.isRecording {
                VStack {
                    HStack {
                        Text(viewModel.recordingDurationText)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(4)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    Spacer()
                }
            }

            floatingControls

            if viewModel.showLoading {
                Color.black.opacity(0.8)
                if viewModel.isStreamFailed {
                    Text(L("Streaming failed. Tap to retry."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.13))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.retryStream()
                        }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            }
        }
    }

    // MARK: - 悬浮控制按钮

    private var floatingControls: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    // 静音按钮
                    VideoCircleButton(
                        icon: viewModel.isMuted
                            ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        color: viewModel.isMuted ? .red.opacity(0.9) : .white.opacity(0.9)
                    ) {
                        viewModel.toggleMute()
                    }

                    // 画质按钮
                    VideoCircleButton(
                        text: viewModel.qualityLabel,
                        color: .white.opacity(0.9)
                    ) {
                        viewModel.toggleQuality()
                    }

                    // 全屏按钮
                    VideoCircleButton(
                        icon: viewModel.isFullscreen
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                        color: .white.opacity(0.9)
                    ) {
                        viewModel.toggleFullscreen()
                    }
                }
                .padding(.trailing, 16)
                .padding(.top, 60)
            }
            Spacer()
        }
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            ControlButton(
                icon: viewModel.isTalking ? "mic.fill" : "mic.slash.fill",
                label: viewModel.isTalking ? L("Talking") : L("Talk"),
                action: { viewModel.toggleTalk() },
                isActive: viewModel.isTalking,
                activeColor: .red
            )

            ControlButton(icon: "camera.fill", label: L("Snapshot")) {
                viewModel.takeSnapshot()
            }

            ControlButton(
                icon: viewModel.isRecording ? "stop.circle.fill" : "video.fill",
                label: viewModel.isRecording ? L("Recording") : L("Record"),
                action: { viewModel.toggleRecording() },
                isActive: viewModel.isRecording,
                activeColor: .red
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    private var ptzControlPanel: some View {
        let diskSize: CGFloat = 220
        let offset = diskSize / 2 - 30 - 25  // margin=30dp, buttonHalf=25dp

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(ptzDiskFill)
                    .frame(width: diskSize, height: diskSize)

                Circle()
                    .stroke(ptzDiskStroke, lineWidth: 1.5)
                    .frame(width: diskSize, height: diskSize)

                ptzButton(icon: "chevron.up") {
                    viewModel.sendPTZCommand(channelId: viewModel.activeChannelId, command: .up)
                }
                .offset(y: -offset)

                ptzButton(icon: "chevron.down") {
                    viewModel.sendPTZCommand(channelId: viewModel.activeChannelId, command: .down)
                }
                .offset(y: offset)

                ptzButton(icon: "chevron.left") {
                    viewModel.sendPTZCommand(channelId: viewModel.activeChannelId, command: .left)
                }
                .offset(x: -offset)

                ptzButton(icon: "chevron.right") {
                    viewModel.sendPTZCommand(channelId: viewModel.activeChannelId, command: .right)
                }
                .offset(x: offset)

                Button(action: { viewModel.sendPTZCenterCommand() }) {
                    ZStack {
                        Circle()
                            .fill(ctrlBtnTint)
                            .frame(width: 40, height: 40)
                        Image(systemName: "scope")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(width: diskSize, height: diskSize)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    /// 单个 PTZ 方向按钮
    private func ptzButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 50, height: 50)
                    .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(ctrlBtnTint)
            }
        }
    }

    private var bottomActionButtons: some View {
        HStack(spacing: 16) {
            ActionButton(icon: "square.and.arrow.up", title: L("Share")) {
                viewModel.createShareToken { token in
                    DispatchQueue.main.async {
                        if let json = token {
                            shareJSON = json
                            showShareSheet = true
                        } else {
                            showShareFailAlert = true
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(Color.white)
    }

    private var shareSheetContent: some View {
        CommonBottomSheet(
            title: L("Device Share Code"),
            hint: nil,
            confirmTitle: L("Copy Share Code"),
            cancelTitle: L("Close"),
            sheetHeight: 300,
            onConfirm: {
                UIPasteboard.general.string = shareJSON
                showShareSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    viewModel.showToastMessage(L("Share code copied"))
                }
            },
            onCancel: { showShareSheet = false }
        ) {
            Text(shareJSON)
                .font(.system(size: 15, design: .monospaced))
                .foregroundColor(.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 36)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                .background(Color.inputBg)
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 12)
        }
    }
}

// MARK: - 多通道网格视图组件

/// 根据 channelList 数量自适应布局，支持 1/2/3/4 路视频并行展示
struct MultiChannelGridView: View {
    let channelList: [Int]
    let channelViews: [Int: UIView]
    let activeChannelId: Int
    let onTapChannel: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            gridContent(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private func gridContent(width: CGFloat, height: CGFloat) -> some View {
        let count = channelList.count
        let isLandscape = width > height
        Group {
            if count <= 1 {
                channelCell(channelList.first ?? 0)
            } else if count == 2 {
                twoChannelGrid(isLandscape: isLandscape)
            } else {
                multiChannelGrid
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func twoChannelGrid(isLandscape: Bool) -> some View {
        if isLandscape {
            HStack(spacing: 2) {
                channelCell(channelList[0])
                channelCell(channelList[1])
            }
        } else {
            VStack(spacing: 2) {
                channelCell(channelList[0])
                channelCell(channelList[1])
            }
        }
    }

    private var multiChannelGrid: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                channelCell(channelList[0])
                channelCellOrPlaceholder(at: 1)
            }
            HStack(spacing: 2) {
                channelCellOrPlaceholder(at: 2)
                channelCellOrPlaceholder(at: 3)
            }
        }
    }

    @ViewBuilder
    private func channelCellOrPlaceholder(at index: Int) -> some View {
        if channelList.count > index {
            channelCell(channelList[index])
        } else {
            Color.black
        }
    }

    @ViewBuilder
    private func channelCell(_ channelId: Int) -> some View {
        ZStack(alignment: .topLeading) {
            if let view = channelViews[channelId] {
                ChannelVideoView(uiView: view)
            } else {
                Color.black
            }
            // 通道标签
            Text(L("Channel %@", "\(channelId)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.55))
                .cornerRadius(4)
                .padding(6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTapChannel(channelId)
        }
    }
}

// MARK: - 通道视频 UI 视图包装

struct ChannelVideoView: UIViewRepresentable {
    let uiView: UIView

    func makeUIView(context: Context) -> UIView {
        uiView.backgroundColor = .black
        return uiView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - 圆角扩展

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
