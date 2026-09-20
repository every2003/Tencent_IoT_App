import SwiftUI
import TXLiteAVSDK_IOT

// MARK: - SDK UIView → SwiftUI 容器

/// 把 CallManager 里创建的 SDK 视图（remote/local）嵌入 SwiftUI
struct SDKVideoContainer: UIViewRepresentable {
    let uiView: UIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(uiView, to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if uiView.superview !== container {
            uiView.removeFromSuperview()
            attach(uiView, to: container)
        }
    }

    private func attach(_ v: UIView, to parent: UIView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            v.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            v.topAnchor.constraint(equalTo: parent.topAnchor),
            v.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}

// MARK: - 全屏通话页面

struct CallView: View {
    @ObservedObject var manager: CallManager = .shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            callBackground
            callOverlayMask
            callMainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .statusBar(hidden: false)
        .preferredColorScheme(.dark)
        .appToast(message: $manager.toastMessage, isError: true)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                manager.recoverFromBackground()
            }
        }
    }

    @ViewBuilder
    private var callBackground: some View {
        if manager.currentSession?.mode == .video {
            videoBackground
        } else {
            audioBackground
        }
    }

    @ViewBuilder
    private var callOverlayMask: some View {
        if manager.currentSession?.mode == .audio {
            Color.black.opacity(0.55).ignoresSafeArea()
        } else if manager.currentSession?.mode == .video,
            manager.state != .connected || !manager.hasRemoteVideoFrame
        {
            Color.black.opacity(0.35).ignoresSafeArea()
        }
    }

    private var callMainContent: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar.padding(.top, geo.safeAreaInsets.top)
                Spacer().frame(height: 20)
                callBodyContent
                bottomControls.padding(.bottom, 36)
            }
        }
    }

    @ViewBuilder
    private var callBodyContent: some View {
        if manager.state == .connected,
            manager.currentSession?.mode == .video,
            manager.hasRemoteVideoFrame
        {
            HStack {
                Spacer()
                localPreviewWindow.padding(.trailing, 16)
            }
            Spacer()
        } else {
            peerInfoBlock
            Spacer()
            statusTextBlock.padding(.bottom, 24)
        }
    }

    // MARK: - 顶部导航栏（左：画中画、中：计时、右：+ 添加成员）

    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 40, height: 40)
            Spacer()
            durationDisplay
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var durationDisplay: some View {
        if manager.state == .connected {
            Text(manager.durationText)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    // MARK: - 头像 + 昵称 块

    private var peerInfoBlock: some View {
        VStack(spacing: 12) {
            avatarView
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(manager.currentSession?.peerName ?? "")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.top, manager.currentSession?.mode == .video ? 80 : 120)
    }

    private var avatarView: some View {
        Group {
            if let urlStr = manager.currentSession?.peerAvatar,
                let url = URL(string: urlStr)
            {
                avatarAsyncImage(url: url)
            } else {
                avatarPlaceholder
            }
        }
    }

    private func avatarAsyncImage(url: URL) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.68, green: 0.55, blue: 0.42),
                    Color(red: 0.5, green: 0.38, blue: 0.28),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "person.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    // MARK: - 状态文字块（等待对方接受邀请… / 邀请你语音通话… / 对方已挂断，通话结束）

    private var statusTextBlock: some View {
        Text(manager.statusText)
            .font(.system(size: 15))
            .foregroundColor(.white.opacity(0.85))
    }

    // MARK: - 底部按钮区（根据状态切换）

    @ViewBuilder
    private var bottomControls: some View {
        switch manager.state {
        case .calling:
            callingControls
        case .ended:
            endedActions
        case .ringing:
            ringingControls
        case .connected:
            connectedControls
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var callingControls: some View {
        if manager.currentSession?.mode == .video {
            callingVideoRows
        } else {
            callerActions
        }
    }

    private var callingVideoRows: some View {
        VStack(spacing: 24) {
            connectedVideoTopRow
            connectedVideoBottomRow
        }
    }

    @ViewBuilder
    private var ringingControls: some View {
        if manager.currentSession?.mode == .video {
            ringingVideoRows
        } else {
            rejectAnswerRow
        }
    }

    private var ringingVideoRows: some View {
        VStack(spacing: 24) {
            videoRingingSecondaryRow
            rejectAnswerRow
        }
    }

    @ViewBuilder
    private var connectedControls: some View {
        if manager.currentSession?.mode == .video {
            callingVideoRows
        } else {
            connectedAudioRow
        }
    }

    // MARK: - 子按钮行

    /// 主叫呼叫中：麦克风（白）/ 挂断（红）/ 扬声器（灰）
    private var callerActions: some View {
        HStack(spacing: 32) {
            CallActionButton(
                icon: "mic.fill",
                title: manager.micOn ? L("Microphone on") : L("Microphone off"),
                style: manager.micOn ? .white : .dim
            ) { manager.toggleMic() }

            CallActionButton(icon: "phone.down.fill", title: L("Cancel"), style: .redCircle) {
                manager.hangup()
            }

            CallActionButton(
                icon: manager.speakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                title: manager.speakerOn ? L("Speaker on") : L("Speaker off"),
                style: manager.speakerOn ? .white : .dim
            ) { manager.toggleSpeaker() }
        }
    }

    /// 被叫：拒绝 / 接听
    private var rejectAnswerRow: some View {
        HStack(spacing: 90) {
            CallActionButton(icon: "phone.down.fill", title: L("Decline"), style: .redCircle) {
                manager.hangup()
            }
            CallActionButton(icon: "phone.fill", title: L("Answer"), style: .greenCircle) {
                manager.answer()
            }
        }
    }

    /// 视频被叫次要行：翻转 / 摄像头
    private var videoRingingSecondaryRow: some View {
        HStack(spacing: 60) {
            CallActionButton(
                icon: "arrow.triangle.2.circlepath.camera.fill",
                title: L("Flip"),
                style: .dim
            ) {
                manager.switchCamera()
            }
            CallActionButton(
                icon: "video.fill",
                title: manager.cameraOn ? L("Camera on") : L("Camera off"),
                style: manager.cameraOn ? .white : .dim
            ) { manager.toggleCamera() }
        }
    }

    /// 通话中（音频）：麦克风 / 挂断 / 扬声器
    private var connectedAudioRow: some View {
        HStack(spacing: 32) {
            CallActionButton(
                icon: "mic.fill",
                title: manager.micOn ? L("Microphone on") : L("Microphone off"),
                style: manager.micOn ? .white : .dim
            ) { manager.toggleMic() }

            CallActionButton(icon: "phone.down.fill", title: L("Hang Up"), style: .redCircle) {
                manager.hangup()
            }

            CallActionButton(
                icon: manager.speakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                title: manager.speakerOn ? L("Speaker on") : L("Speaker off"),
                style: manager.speakerOn ? .white : .dim
            ) { manager.toggleSpeaker() }
        }
    }

    /// 通话中（视频）上排：麦克风 / 扬声器 / 摄像头
    private var connectedVideoTopRow: some View {
        HStack(spacing: 32) {
            CallActionButton(
                icon: "mic.fill",
                title: manager.micOn ? L("Microphone on") : L("Microphone off"),
                style: manager.micOn ? .white : .dim
            ) { manager.toggleMic() }

            CallActionButton(
                icon: manager.speakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                title: manager.speakerOn ? L("Speaker on") : L("Speaker off"),
                style: manager.speakerOn ? .white : .dim
            ) { manager.toggleSpeaker() }

            CallActionButton(
                icon: "video.fill",
                title: manager.cameraOn ? L("Camera on") : L("Camera off"),
                style: manager.cameraOn ? .white : .dim
            ) { manager.toggleCamera() }
        }
    }

    /// 通话中（视频）下排：挂断（居中）/ 翻转（右侧）
    /// 左侧以等宽占位保持挂断按钮始终处于屏幕中间
    private var connectedVideoBottomRow: some View {
        HStack(spacing: 70) {
            // 左侧占位（宽度=dimSmall 的按钮尺寸 52）
            Color.clear.frame(width: 52, height: 52)
            CallActionButton(icon: "phone.down.fill", title: "", style: .redCircle) {
                manager.hangup()
            }
            CallActionButton(
                icon: "arrow.triangle.2.circlepath.camera.fill",
                title: "",
                style: .dimSmall
            ) {
                manager.switchCamera()
            }
        }
    }

    /// 通话已结束 - 拒绝（关闭） / 接听（重拨，预留）
    private var endedActions: some View {
        HStack(spacing: 90) {
            CallActionButton(icon: "phone.down.fill", title: L("Decline"), style: .redCircle) {
                manager.hangup()
            }
            CallActionButton(icon: "phone.fill", title: L("Answer"), style: .greenCircle) {
                // TODO: 预留重拨接口
                manager.hangup()
            }
        }
    }

    // MARK: - 视频背景 / 音频背景 / 小窗

    /// 视频远端画面（SDK 远端渲染视图）；未接通或无帧时隐藏显示灰色
    private var videoBackground: some View {
        ZStack {
            // 兜底灰色（SDK 尚未出帧时）
            LinearGradient(
                colors: [Color(white: 0.25), Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
            SDKVideoContainer(uiView: manager.remoteVideoView)
                .opacity(manager.state == .connected && manager.hasRemoteVideoFrame ? 1 : 0)
        }
        .ignoresSafeArea()
    }

    /// 音频通话背景（暗色 + 模糊圆形）
    private var audioBackground: some View {
        ZStack {
            Color(red: 0.18, green: 0.15, blue: 0.12).ignoresSafeArea()
            Circle()
                .fill(Color(red: 0.35, green: 0.28, blue: 0.22).opacity(0.6))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(y: 100)
        }
    }

    /// 本地摄像头小窗（视频通话右上角）
    private var localPreviewWindow: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.4), Color(white: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            SDKVideoContainer(uiView: manager.localVideoView)
                .opacity(manager.cameraOn ? 1 : 0)
            cameraOffIndicator
        }
        .frame(width: 110, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 80)
    }

    @ViewBuilder
    private var cameraOffIndicator: some View {
        if !manager.cameraOn {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.85))
        }
    }
}

// MARK: - 通话按钮（统一封装）

struct CallActionButton: View {
    enum Style {
        case white  // 白底黑图标（如：麦克风已开）
        case dim  // 深灰底白图标（如：扬声器已关）
        case dimSmall  // 深灰底白图标 - 较小
        case redCircle  // 红色圆形挂断
        case greenCircle  // 绿色圆形接听
    }

    let icon: String
    let title: String
    let style: Style
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(backgroundColor)
                        .frame(width: size, height: size)
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .medium))
                        .foregroundColor(iconColor)
                }
            }
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    private var size: CGFloat {
        switch style {
        case .white, .dim, .redCircle, .greenCircle: return 64
        case .dimSmall: return 52
        }
    }
    private var iconSize: CGFloat {
        switch style {
        case .redCircle, .greenCircle: return 28
        case .dimSmall: return 22
        default: return 24
        }
    }
    private var backgroundColor: Color {
        switch style {
        case .white: return .white
        case .dim, .dimSmall: return Color.black.opacity(0.35)
        case .redCircle: return Color(red: 0.90, green: 0.30, blue: 0.30)
        case .greenCircle: return Color(red: 0.22, green: 0.78, blue: 0.42)
        }
    }
    private var iconColor: Color {
        switch style {
        case .white: return .black
        default: return .white
        }
    }
}

// MARK: - 来电横幅（图8）

struct IncomingCallBanner: View {
    @ObservedObject var manager: CallManager = .shared

    var body: some View {
        if manager.showIncomingBanner, let session = manager.currentSession {
            bannerContent(session: session)
        }
    }

    private func bannerContent(session: CallSession) -> some View {
        HStack(spacing: 12) {
            bannerAvatar(session: session)
            bannerPeerInfo(session: session)
            Spacer()
            bannerHangupButton
            bannerAnswerButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        )
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .onTapGesture { manager.expandIncomingToFullScreen() }
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(9999)
    }

    private func bannerAvatar(session: CallSession) -> some View {
        Group {
            if let urlStr = session.peerAvatar, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarFallback
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bannerPeerInfo(session: CallSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.peerName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(session.mode == .audio ? L("Invites you to a voice call...") : L("Invites you to a video call..."))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
        }
    }

    private var bannerHangupButton: some View {
        Button(action: { manager.hangup() }) {
            ZStack {
                Circle().fill(Color(red: 0.90, green: 0.30, blue: 0.30))
                    .frame(width: 40, height: 40)
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 17))
                    .foregroundColor(.white)
            }
        }
    }

    private var bannerAnswerButton: some View {
        Button(action: { manager.answer() }) {
            ZStack {
                Circle().fill(Color(red: 0.22, green: 0.78, blue: 0.42))
                    .frame(width: 40, height: 40)
                Image(systemName: "phone.fill")
                    .font(.system(size: 17))
                    .foregroundColor(.white)
            }
        }
    }

    private var avatarFallback: some View {
        LinearGradient(
            colors: [
                Color(red: 0.68, green: 0.55, blue: 0.42), Color(red: 0.5, green: 0.38, blue: 0.28),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - 呼叫类型选单（图3：视频通话 / 语音通话 / 取消）

struct CallTypeActionSheet {
    /// 返回一个 SwiftUI confirmationDialog 使用的 view modifier helper
    /// 业务层直接调用 ``confirmationDialog(..)`` 即可，此结构仅用于文档约束
}
