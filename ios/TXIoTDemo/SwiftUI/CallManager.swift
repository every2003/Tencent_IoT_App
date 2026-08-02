import AVFoundation
import Combine
import SwiftUI
import TXLiteAVSDK_Professional
import UIKit

// MARK: - 通话类型

@objc enum CallMode: Int {
    case audio = 0  // 语音通话
    case video = 1  // 视频通话

    var title: String {
        switch self {
        case .audio: return L("Voice Call")
        case .video: return L("Video Call")
        }
    }

    /// 转成 SDK 定义的媒体类型
    var sdkMediaType: TXIoTCallMediaType {
        switch self {
        case .audio: return .audio
        case .video: return .video
        }
    }
}

// MARK: - 通话状态

enum CallState {
    case idle  // 空闲
    case calling  // 主叫：呼叫中，等待对方接受
    case ringing  // 被叫：收到来电邀请
    case connected  // 通话中
    case ended  // 通话结束（对方已挂断/取消/网络错误等）
}

// MARK: - 通话会话模型（UI 层使用）

struct CallSession: Identifiable, Equatable {
    let id: String  // 通话会话 ID（由 WebSocket 消息携带或本地生成）
    let peerName: String  // 对方昵称
    let peerAvatar: String?  // 对方头像 URL（可选）
    let mode: CallMode  // 语音/视频
    let isCaller: Bool  // 自己是否为主叫方
    let deviceId: String?  // 关联设备 ID（格式: "productId/deviceName"）

    static func == (lhs: CallSession, rhs: CallSession) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 通话管理器（单例）

@MainActor
final class CallManager: NSObject, ObservableObject {
    static let shared = CallManager()

    @Published var currentSession: CallSession?
    @Published var state: CallState = .idle
    @Published var durationSeconds: Int = 0
    @Published var endReasonText: String = ""

    @Published var micOn: Bool = true  // 麦克风开/关
    @Published var speakerOn: Bool = false  // 扬声器开/关（音频默认关，视频默认开）
    @Published var cameraOn: Bool = true  // 摄像头开/关（仅视频）
    @Published var blurBackground: Bool = false  // 模糊背景（仅视频待接听时）
    @Published var isFrontCamera: Bool = true  // 是否前置摄像头

    // 远端/本地视频是否已来帧（用于切换头像/画面显示）
    @Published var hasRemoteVideoFrame: Bool = false

    // 全屏通话页面弹出
    @Published var showCallScreen: Bool = false {
        didSet {
            guard oldValue != showCallScreen else { return }
            if showCallScreen {
                CallWindowController.shared.present(manager: self)
            } else {
                CallWindowController.shared.dismiss()
            }
        }
    }
    // 横幅来电通知弹出
    @Published var showIncomingBanner: Bool = false
    // Toast 消息（SDK 错误等）
    @Published var toastMessage: String?

    // MARK: - SDK 会话
    private var callSession: TXIoTCallSession?

    // 缓存的远端通话用户（用于回到前台时重新绑定渲染视图）
    private var remoteCallUser: TXIoTCallUser?

    // 视频渲染视图（由 CallView 创建并注入）
    let localVideoView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        return v
    }()
    let remoteVideoView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        return v
    }()

    private var timer: Timer?

    private override init() {
        super.init()
        // 监听来自 AppDelegate / WebSocket 的来电通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIncomingCallNotification(_:)),
            name: .txIoTIncomingCall,
            object: nil
        )
        // 监听系统音频会话中断通知（闹钟/来电等打断通话音频）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruptionNotification(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 构造 SDK DeviceId

    /// 设备 ID 格式约定：productId/deviceName
    private func buildSdkDeviceId() -> TXIoTDeviceId? {
        guard let raw = currentSession?.deviceId, !raw.isEmpty else {
            return nil
        }
        let parts = raw.split(
            separator: "/",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return nil
        }
        let did = TXIoTDeviceId()
        did.productId = parts[0]
        did.deviceName = parts[1]
        return did
    }

    // MARK: - 主叫：发起呼叫

    /// 发起音视频呼叫
    /// - Parameters:
    ///   - peerName: 对方昵称
    ///   - mode: 音频 / 视频
    ///   - deviceId: 关联设备 "productId/deviceName"
    func startCall(
        peerName: String,
        peerAvatar: String? = nil,
        mode: CallMode,
        deviceId: String? = nil
    ) {
        // 已在通话中则忽略
        guard state == .idle else {
            print("[CallManager] Already in a call, ignoring new startCall")
            return
        }

        let session = CallSession(
            id: UUID().uuidString,
            peerName: peerName,
            peerAvatar: peerAvatar,
            mode: mode,
            isCaller: true,
            deviceId: deviceId
        )
        self.currentSession = session
        self.state = .calling
        self.durationSeconds = 0
        self.endReasonText = ""
        self.hasRemoteVideoFrame = false
        self.micOn = true
        self.speakerOn = (mode == .video)
        self.cameraOn = (mode == .video)
        self.blurBackground = false
        self.isFrontCamera = true
        self.showCallScreen = true

        // 创建 SDK 会话
        guard let did = buildSdkDeviceId() else {
            print("[CallManager] Invalid deviceId, cannot start call: \(deviceId ?? "nil")")
            self.endCallWithReason(L("Abnormal device info"))
            return
        }
        guard let sdkSession = TXIoTEngine.getInstance().getCallSession() else {
            print("[CallManager] Failed to get CallSession")
            self.endCallWithReason(L("Failed to initialize call session"))
            return
        }
        sdkSession.add(self)
        self.callSession = sdkSession

        // 视频模式：打开本地摄像头并渲染到本地预览视图
        if mode == .video {
            sdkSession.open(
                self.isFrontCamera ? .front : .back,
                view: localVideoView
            )
        }
        // 默认开启麦克风
        sdkSession.openMicrophone()
        // 同步扬声器/听筒选择
        sdkSession.select(self.speakerOn ? .speakerphone : .earpiece)
        // 发起呼叫
        sdkSession.callDevice(did, call: mode.sdkMediaType)

        print(
            "📞 [CallManager] Calling \(mode.title) → \(peerName)  deviceId=\(deviceId ?? "")"
        )
    }

    // MARK: - 被叫：收到来电（由 WebSocket 触发）

    /// 接收来电（外部可手动调用，或由 NotificationCenter 触发）
    func receiveIncomingCall(session: CallSession) {
        self.currentSession = session
        self.state = .ringing
        self.durationSeconds = 0
        self.endReasonText = ""
        self.hasRemoteVideoFrame = false
        self.micOn = true
        self.speakerOn = (session.mode == .video)
        self.cameraOn = (session.mode == .video)
        self.blurBackground = false
        self.isFrontCamera = true
        // 优先展示横幅，用户点击接听/进入后再弹出全屏页
        self.showIncomingBanner = true

        print(
            "📞 [CallManager] Incoming call \(session.mode.title) ← \(session.peerName)"
        )
    }

    /// 横幅被点击：进入全屏来电页
    func expandIncomingToFullScreen() {
        self.showIncomingBanner = false
        self.showCallScreen = true
    }

    // MARK: - 接听（被叫）

    func answer() {
        guard state == .ringing else { return }
        self.showIncomingBanner = false
        self.showCallScreen = true

        // 被叫侧创建 SDK 会话并准备本地媒体，等待 SDK 触发 onCallBegin 进入通话
        guard let session = currentSession, buildSdkDeviceId() != nil else {
            print("[CallManager] answer: incomplete device info")
            endCallWithReason(L("Abnormal device info"))
            return
        }
        guard let sdkSession = TXIoTEngine.getInstance().getCallSession() else {
            print("[CallManager] answer: failed to get CallSession")
            endCallWithReason(L("Failed to initialize call session"))
            return
        }
        sdkSession.add(self)
        self.callSession = sdkSession

        if session.mode == .video {
            sdkSession.open(
                self.isFrontCamera ? .front : .back,
                view: localVideoView
            )
        }
        sdkSession.openMicrophone()
        sdkSession.select(self.speakerOn ? .speakerphone : .earpiece)

        // 被叫侧 UI 先切到 connected，媒体链路建立以 onCallBegin 为准（delegate 中会补一次 state 同步）
        self.state = .connected
        startDurationTimer()
        print("[CallManager] Answered")
    }

    // MARK: - 拒绝（被叫）/ 取消（主叫）/ 挂断（通话中）

    /// 挂断：主叫=取消 / 被叫=拒绝 / 通话中=挂断
    func hangup() {
        let wasConnected = (state == .connected)
        stopDurationTimer()

        // 释放 SDK 会话
        if let s = callSession {
            s.hangup()
            s.remove(self)
        }
        callSession = nil
        remoteCallUser = nil

        self.state = .idle
        self.showCallScreen = false
        self.showIncomingBanner = false
        self.currentSession = nil
        self.durationSeconds = 0
        self.endReasonText = ""
        self.hasRemoteVideoFrame = false
        print("[CallManager] Hang up (wasConnected=\(wasConnected))")
    }

    // MARK: - 结束态：保留挂断原因 2s 后自动关闭页面

    private func endCallWithReason(_ reason: String) {
        stopDurationTimer()
        if let s = callSession {
            s.remove(self)
        }
        callSession = nil
        remoteCallUser = nil

        self.endReasonText = reason
        self.state = .ended
        self.showIncomingBanner = false

        // 若全屏未展示（例如主叫 deviceId 错误时），直接清空并关闭
        if !self.showCallScreen {
            self.finishEnded()
        } else {
            // 停留 2s 后自动关闭
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                [weak self] in
                guard let self = self else { return }
                if self.state == .ended { self.finishEnded() }
            }
        }
    }

    private func finishEnded() {
        remoteCallUser = nil
        self.state = .idle
        self.showCallScreen = false
        self.currentSession = nil
        self.durationSeconds = 0
        self.endReasonText = ""
        self.hasRemoteVideoFrame = false
    }

    // MARK: - 前后台切换恢复

    /// App 从后台回到前台时调用：
    /// 重新绑定渲染视图 + 唤醒音频输出（不重启会话，避免断线）
    func recoverFromBackground() {
        guard state == .connected else { return }
        guard let sdkSession = callSession else { return }

        // 唤醒音频输出：iOS 后台可能回收 AVAudioSession，重新选择输出设备来恢复
        sdkSession.select(speakerOn ? .speakerphone : .earpiece)

        // 重新绑定远端视频渲染：后台时 GPU 渲染管线可能停滞，回到前台后重绑视图
        if let user = remoteCallUser {
            sdkSession.startRemoteView(user, view: remoteVideoView)
            print("[CallManager] Back to foreground, rebinding remote video renderer")
        }

        // 重新绑定本地摄像头预览
        if currentSession?.mode == .video, cameraOn {
            sdkSession.open(
                isFrontCamera ? .front : .back,
                view: localVideoView
            )
        }

        print("[CallManager] Foreground resume completed")
    }

    // MARK: - UI 控件切换（与 SDK 同步）

    func toggleMic() {
        micOn.toggle()
        if micOn {
            callSession?.openMicrophone()
        } else {
            callSession?.closeMicrophone()
        }
    }
    func toggleSpeaker() {
        speakerOn.toggle()
        callSession?.select(speakerOn ? .speakerphone : .earpiece)
    }
    func toggleCamera() {
        cameraOn.toggle()
        if cameraOn {
            callSession?.open(
                isFrontCamera ? .front : .back,
                view: localVideoView
            )
        } else {
            callSession?.closeCamera()
        }
    }
    func toggleBlur() { blurBackground.toggle() }
    /// 翻转前/后摄像头
    func switchCamera() {
        isFrontCamera.toggle()
        callSession?.switch(isFrontCamera ? .front : .back)
    }

    // MARK: - 计时器

    private func startDurationTimer() {
        stopDurationTimer()
        durationSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.durationSeconds += 1
            }
        }
    }

    private func stopDurationTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - 通知处理（WebSocket 来电）

    /// 通过 WebSocket 接收到来电推送后，由 AppDelegate/IoTAPIBridge 发送此通知
    @objc private func handleIncomingCallNotification(
        _ notification: Notification
    ) {
        guard state == .idle else {
            print("[CallManager] Already in a call, ignoring new incoming call")
            return
        }
        guard let info = notification.userInfo else { return }
        let sessionId = info["sessionId"] as? String ?? UUID().uuidString
        let peerName = info["peerName"] as? String ?? L("Unknown Contact")
        let peerAvatar = info["peerAvatar"] as? String
        let modeInt = info["mode"] as? Int ?? 0
        let deviceId = info["deviceId"] as? String
        let mode: CallMode = (modeInt == 1) ? .video : .audio

        let session = CallSession(
            id: sessionId,
            peerName: peerName,
            peerAvatar: peerAvatar,
            mode: mode,
            isCaller: false,
            deviceId: deviceId
        )
        Task { @MainActor in
            self.receiveIncomingCall(session: session)
        }
    }

    // MARK: - 通知处理（系统音频会话中断，如闹钟/来电打断通话音频）

    /// 系统音频会话被打断（开始/结束）时触发。
    /// 打断结束后系统不会自动恢复采集，需要主动重新激活 AVAudioSession 并重开麦克风，
    /// 否则会出现打断结束后本地采集无声的问题。
    @objc private func handleAudioSessionInterruptionNotification(
        _ notification: Notification
    ) {
        guard let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            print("[CallManager] Audio session interrupted by system")
        case .ended:
            let optionsValue =
                info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(
                rawValue: optionsValue
            )
            guard options.contains(.shouldResume) else { return }
            Task { @MainActor in
                self.recoverFromAudioInterruption()
            }
        @unknown default:
            break
        }
    }

    /// 音频打断结束后恢复本地采集：重新激活 AVAudioSession，
    /// 并按当前麦克风开关状态与音频路由重新开启麦克风采集
    private func recoverFromAudioInterruption() {
        guard state == .calling || state == .ringing || state == .connected
        else {
            return
        }
        guard let sdkSession = callSession else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print(
                "[CallManager] Failed to resume from audio interruption, error activating AVAudioSession: \(error)"
            )
        }

        sdkSession.select(speakerOn ? .speakerphone : .earpiece)
        if micOn {
            sdkSession.closeMicrophone()
            sdkSession.openMicrophone()
        }
        print("[CallManager] Audio interruption ended, mic capture resumed")
    }

    // MARK: - 展示工具

    var durationText: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// 状态文本
    var statusText: String {
        guard let session = currentSession else { return "" }
        switch state {
        case .calling:
            return L("Waiting for the other party to accept...")
        case .ringing:
            return session.mode == .audio ? L("Invites you to a voice call...") : L("Invites you to a video call...")
        case .connected:
            return durationText
        case .ended:
            return endReasonText.isEmpty ? L("Call ended") : endReasonText
        case .idle:
            return ""
        }
    }
}

// MARK: - TXIoTCallDelegate

extension CallManager: TXIoTCallDelegate {

    /// 通话开始（主叫：对端已接受；被叫：接听完成，媒体通道已建立）
    nonisolated func onCallBegin(_ mediaType: TXIoTCallMediaType) {
        Task { @MainActor in
            print("📞 [CallManager] onCallBegin mediaType=\(mediaType.rawValue)")
            guard self.state != .connected else { return }
            self.state = .connected
            self.startDurationTimer()
        }
    }

    /// 通话结束
    nonisolated func onCallEnd(
        _ mediaType: TXIoTCallMediaType,
        reason: TXIoTCallEndReason
    ) {
        Task { @MainActor in
            let text = CallManager.endReasonText(reason)
            print(
                "📞 [CallManager] onCallEnd mediaType=\(mediaType.rawValue) reason=\(reason.rawValue)(\(text))"
            )
            self.endCallWithReason(text)
        }
    }

    /// 对方拒绝
    nonisolated func onCallRejected(_ callUser: TXIoTCallUser) {
        Task { @MainActor in
            print("[CallManager] onCallRejected")
            self.endCallWithReason(L("Declined"))
        }
    }

    /// 对方无应答
    nonisolated func onCallNoResponse(_ callUser: TXIoTCallUser) {
        Task { @MainActor in
            print("[CallManager] onCallNoResponse")
            self.endCallWithReason(L("No answer"))
        }
    }

    /// 对方忙线
    nonisolated func onCallLineBusy(_ callUser: TXIoTCallUser) {
        Task { @MainActor in
            print("[CallManager] onCallLineBusy")
            self.endCallWithReason(L("Busy"))
        }
    }

    /// 通话方离线
    nonisolated func onCallUserOffline(_ callUser: TXIoTCallUser) {
        Task { @MainActor in
            print("[CallManager] onCallUserOffline")
            self.endCallWithReason(L("Device offline"))
        }
    }

    /// 远端音频流可用性变化
    nonisolated func onCallUserAudioAvailable(
        _ callUser: TXIoTCallUser,
        available: Bool
    ) {
        print("[CallManager] onCallUserAudioAvailable=\(available)")
    }

    /// 远端视频流可用性变化：可用时拉起远端渲染，不可用时移除渲染
    nonisolated func onCallUserVideoAvailable(
        _ callUser: TXIoTCallUser,
        available: Bool
    ) {
        // TXIoTCallUser 未实现 NSCopying，无法 copy()；
        // SendableBox(@unchecked Sendable) 已处理跨隔离域传递
        let userBox = SendableBox(callUser)
        Task { @MainActor in
            let user = userBox.value
            print("[CallManager] onCallUserVideoAvailable=\(available)")
                if available {
                    self.remoteCallUser = user
                    self.callSession?.startRemoteView(
                        user,
                        view: self.remoteVideoView
                    )
                    self.hasRemoteVideoFrame = true
                } else {
                    self.remoteCallUser = nil
                    self.callSession?.stopRemoteView(user)
                    self.hasRemoteVideoFrame = false
                }
        }
    }

    /// 网络质量变化
    nonisolated func onCallNetworkQualityChanged(
        _ localQuality: TXIoTQuality,
        remoteQualityList: [TXIoTQuality]
    ) {
        // 预留
    }

    /// SDK 通用错误（包含原有本地媒体设备错误）
    nonisolated func onError(_ errorCode: TXIoTErrorCode, errorMessage: String) {
        print(
            "[CallManager] onError code=\(errorCode.rawValue) msg=\(errorMessage)"
        )
        Task { @MainActor in
            let text = L("Error (%@): %@", "\(errorCode.rawValue)", "\(errorMessage)")
            withAnimation { toastMessage = text }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                withAnimation { self?.toastMessage = nil }
            }
        }
    }

    /// 结束原因文案（新 SDK 移除了 deviceOffline/remoteBusy/remoteReject/remoteNoAnswer，
    /// 这些场景改由 onCallUserOffline / onCallLineBusy / onCallRejected / onCallNoResponse 单独回调）
    private static func endReasonText(_ reason: TXIoTCallEndReason) -> String {
        switch reason {
        case .localHangup: return L("Hung up")
        case .remoteHangup: return L("The other party hung up, call ended")
        case .callPermissionDenied: return L("No call permission")
        case .networkError: return L("Network error, call ended")
        default: return L("Call ended")
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// WebSocket 收到来电邀请时发送此通知（由 AppDelegate 或 OC 层桥接）
    /// userInfo: [sessionId, peerName, peerAvatar, mode(Int), deviceId]
    static let txIoTIncomingCall = Notification.Name(
        "TXIoTDidReceiveIncomingCall"
    )
}

// MARK: - Sendable Box

/// 用于将非 Sendable 的 OC 对象（如 TXIoTCallUser）安全地从 nonisolated 上下文
/// 传递到 @MainActor 任务中。调用者必须保证装入前对象不会再被外部修改。
private struct SendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - 通话独立窗口控制器

/// 用独立的 `UIWindow` 承载全屏通话页（CallView）。
@MainActor
final class CallWindowController {
    static let shared = CallWindowController()

    private var window: UIWindow?
    /// 记录展示通话窗口前的 keyWindow，关闭后恢复，避免影响主窗口的键盘/sheet 等
    private weak var previousKeyWindow: UIWindow?

    private init() {}

    /// 展示通话窗口
    func present(manager: CallManager) {
        guard window == nil else { return }
        guard let scene = Self.activeWindowScene() else {
            print("[CallWindowController] No available UIWindowScene found")
            return
        }

        previousKeyWindow = scene.keyWindow

        let host = UIHostingController(rootView: CallView(manager: manager))
        host.view.backgroundColor = .clear

        let w = UIWindow(windowScene: scene)
        w.windowLevel = .normal + 1  // 高于主窗口，覆盖在业务页面之上
        w.backgroundColor = .clear
        w.rootViewController = host
        w.makeKeyAndVisible()
        window = w
        print("[CallWindowController] Call window shown")
    }

    /// 关闭通话窗口
    func dismiss() {
        guard window != nil else { return }
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        // 恢复原 keyWindow，确保业务页面的 sheet/键盘等正常工作
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
        print("[CallWindowController] Call window closed")
    }

    /// 选取当前活跃的 windowScene（优先前台活跃场景）
    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
    }
}
