import SwiftUI
import TXLiteAVSDK_IOT

/// 智能吸顶灯控制页
/// 物模型（lamp_data_model.json）：
/// - power_switch：bool，0 关 / 1 开
/// - brightness：int，1~100，单位 %
/// - color_temp：int，2700~6500，步进 100，单位 K
/// - light_mode：enum，0 手动 / 1 阅读 / 2 休闲 / 3 夜灯
struct LampDetailView: View {
    let device: Device
    @Environment(\.dismiss) private var dismiss

    @State private var powerOn = false
    @State private var brightness: Double = 80
    @State private var colorTemp: Double = 4000
    @State private var lightMode = 0
    @State private var isLoading = false
    @State private var toastMessage: String?
    @ObservedObject private var pushStore: PushMessageStore = .shared

    private let modeValues = [0, 1, 2, 3]

    var body: some View {
        ZStack {
            Color.bgColor.ignoresSafeArea()
            VStack(spacing: 0) {
                headerView
                contentView
            }
        }
        .navigationBarHidden(true)
        .onAppear { loadProperties() }
        .appToast(message: $toastMessage)
    }

    // MARK: - 头部

    private var headerView: some View {
        HStack(spacing: 0) {
            NavBackButton(action: { dismiss() })
            headerTitleView
            Spacer()
            statusCapsule
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: 44)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Color.headerGradient.ignoresSafeArea(edges: .top))
    }

    private var headerTitleView: some View {
        Text(displayName)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
    }

    /// 在线状态胶囊：圆点 + 文字，毛玻璃风格适配渐变头部
    private var statusCapsule: some View {
        HStack(spacing: 5) {
            OnlineStatusDot(isOnline: isOnline, size: 6)
            Text(statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.18))
        .clipShape(Capsule())
    }

    // MARK: - 内容区

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoading { InlineLoader(message: L("Loading...")) }
                powerCard
                brightnessCard
                colorTempCard
                sceneModeCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await refreshProperties() }
    }

    /// 离线时禁用全部控制卡片
    private var controlsDisabled: Bool {
        !isOnline
    }

    /// 实时在线状态：优先取推送消息（onReceivePushMessage）中本设备最后一次上下线事件，
    /// 没有匹配消息时回退到设备列表快照值
    private var isOnline: Bool {
        for message in pushStore.messages {
            guard message.type == .statusChange,
                message.productId == device.productId,
                message.deviceName == device.deviceName
            else { continue }
            return message.subType == .online
        }
        return device.isOnline
    }

    private var statusText: String {
        isOnline ? L("Online") : L("Offline")
    }

    // MARK: - 电源开关卡片

    private var powerCard: some View {
        HStack(spacing: 14) {
            powerIconView
            powerTextView
            Spacer()
            Toggle("", isOn: powerBinding)
                .labelsHidden()
                .tint(.primaryColor)
        }
        .padding(16)
        .cardStyle(disabled: controlsDisabled)
    }

    private var powerIconView: some View {
        ZStack {
            Circle()
                .fill(powerOn ? Color.primaryColor : Color.inputBg)
                .frame(width: 52, height: 52)
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 24))
                .foregroundColor(powerOn ? .white : .textSecondary)
        }
    }

    private var powerTextView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Power"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(powerOn ? L("On") : L("Off"))
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
        }
    }

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { powerOn },
            set: { onPowerChanged($0) }
        )
    }

    private func onPowerChanged(_ on: Bool) {
        powerOn = on
        controlProperty("power_switch", value: on ? 1 : 0)
    }

    // MARK: - 亮度卡片（1~100%）

    private var brightnessCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(title: L("Brightness"), icon: "sun.max.fill")
            brightnessSliderRow
        }
        .cardStyle(disabled: controlsDisabled)
    }

    private var brightnessSliderRow: some View {
        HStack(spacing: 12) {
            Slider(
                value: $brightness,
                in: 1...100,
                step: 1,
                onEditingChanged: onBrightnessEdit
            )
            .tint(.primaryColor)
            Text("\(Int(brightness))%")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    /// 拖动结束后再下发，避免滑动过程中频繁下发指令
    private func onBrightnessEdit(_ editing: Bool) {
        guard !editing else { return }
        controlProperty("brightness", value: Int(brightness))
    }

    // MARK: - 色温卡片（2700~6500K，步进 100）

    private var colorTempCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(title: L("Color Temperature"), icon: "thermometer.medium")
            colorTempSliderRow
        }
        .cardStyle(disabled: controlsDisabled)
    }

    private var colorTempSliderRow: some View {
        HStack(spacing: 12) {
            Slider(
                value: $colorTemp,
                in: 2700...6500,
                step: 100,
                onEditingChanged: onColorTempEdit
            )
            .tint(.primaryColor)
            Text("\(Int(colorTemp))K")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textPrimary)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func onColorTempEdit(_ editing: Bool) {
        guard !editing else { return }
        controlProperty("color_temp", value: Int(colorTemp))
    }

    // MARK: - 场景模式卡片

    private var sceneModeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(title: L("Scene Mode"), icon: "sparkles")
            modeGridView
        }
        .cardStyle(disabled: controlsDisabled)
    }

    private var modeGridView: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            ForEach(modeValues, id: \.self) { mode in
                modeChipView(mode)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func modeChipView(_ mode: Int) -> some View {
        Button(action: { selectMode(mode) }) {
            modeChipContent(mode, selected: lightMode == mode)
        }
        .buttonStyle(.plain)
    }

    private func modeChipContent(_ mode: Int, selected: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: modeIcon(mode))
                .font(.system(size: 18))
            Text(modeTitle(mode))
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(selected ? .white : .textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(selected ? Color.primaryColor : Color.inputBg)
        .cornerRadius(10)
    }

    private func modeIcon(_ mode: Int) -> String {
        switch mode {
        case 1: return "book.fill"
        case 2: return "cup.and.saucer.fill"
        case 3: return "moon.fill"
        default: return "hand.tap.fill"
        }
    }

    private func modeTitle(_ mode: Int) -> String {
        switch mode {
        case 1: return L("Reading")
        case 2: return L("Leisure")
        case 3: return L("Night Light")
        default: return L("Manual")
        }
    }

    private func selectMode(_ mode: Int) {
        lightMode = mode
        controlProperty("light_mode", value: mode)
    }

    // MARK: - 物模型数据

    /// 下拉刷新：等待属性拉取回调后再收起刷新控件
    private func refreshProperties() async {
        await withCheckedContinuation { continuation in
            loadProperties(showLoader: false) { continuation.resume() }
        }
    }

    /// 拉取设备属性（返回 JSON 字符串），解析后同步到页面状态
    private func loadProperties(showLoader: Bool = true, completion: (() -> Void)? = nil) {
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            toastMessage = L("Not logged in or failed to get DeviceManager")
            completion?()
            return
        }
        let did = TXIoTDeviceId()
        did.productId = device.productId
        did.deviceName = device.deviceName
        if showLoader { isLoading = true }

        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { result in
            self.onPropertiesLoaded(result)
            completion?()
        }
        cb.onError = { _, errorMessage in
            DispatchQueue.main.async {
                self.isLoading = false
                self.toastMessage = L("Failed to get properties: %@", "\(errorMessage ?? "")")
                completion?()
            }
        }
        deviceManager.getProperties(did, callback: cb)
    }

    private func onPropertiesLoaded(_ result: NSString?) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.applyProperties(json: (result as String?) ?? "")
        }
    }

    /// 解析 getProperties 返回的 JSON（兼容顶层平铺或 properties/data 嵌套结构）
    private func applyProperties(json: String) {
        guard let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let props =
            (root["properties"] as? [String: Any])
            ?? (root["data"] as? [String: Any])
            ?? root
        if let value = Self.intValue(props["power_switch"]) { powerOn = (value != 0) }
        if let value = Self.intValue(props["brightness"]) {
            brightness = Double(Self.clamped(value, min: 1, max: 100))
        }
        if let value = Self.intValue(props["color_temp"]) {
            colorTemp = Double(Self.clamped(value, min: 2700, max: 6500))
        }
        if let value = Self.intValue(props["light_mode"]) {
            lightMode = Self.clamped(value, min: 0, max: 3)
        }
    }

    /// 下发属性控制命令，payload 形如 {"brightness": 80}
    private func controlProperty(_ propertyId: String, value: Int) {
        guard let deviceManager = TXIoTEngine.getInstance().getDeviceManager() else {
            toastMessage = L("Not logged in or failed to get DeviceManager")
            return
        }
        guard let json = Self.commandJson(propertyId: propertyId, value: value) else { return }
        let did = TXIoTDeviceId()
        did.productId = device.productId
        did.deviceName = device.deviceName

        let cb = TXIoTCallback<NSString>()
        cb.onSuccess = { _ in }
        cb.onError = { _, errorMessage in
            DispatchQueue.main.async {
                self.toastMessage = L("Failed to send command: %@", "\(errorMessage ?? "")")
            }
        }
        deviceManager.sendCommand(did, jsonData: json, callback: cb)
    }

    private static func commandJson(propertyId: String, value: Int) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [propertyId: value]),
            let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json
    }

    /// 物模型属性值可能为 Int / Bool / Double / String，统一转成 Int
    private static func intValue(_ raw: Any?) -> Int? {
        if let intVal = raw as? Int { return intVal }
        if let boolVal = raw as? Bool { return boolVal ? 1 : 0 }
        if let doubleVal = raw as? Double { return Int(doubleVal) }
        if let stringVal = raw as? String { return Int(stringVal) }
        return nil
    }

    private static func clamped(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }

    /// 优先展示别名，否则展示 deviceName（与设备卡片保持一致）
    private var displayName: String {
        if !device.name.isEmpty && device.name != device.deviceName {
            return device.name
        }
        return device.deviceName.isEmpty ? device.productId : device.deviceName
    }
}

// MARK: - 卡片样式

private struct LampCardModifier: ViewModifier {
    let disabled: Bool

    func body(content: Content) -> some View {
        content
            .background(Color.cardBg)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
            .disabled(disabled)
            .opacity(disabled ? 0.6 : 1)
    }
}

extension View {
    fileprivate func cardStyle(disabled: Bool) -> some View {
        modifier(LampCardModifier(disabled: disabled))
    }
}

#Preview {
    LampDetailView(device: Device(id: "PID/lamp_1", name: "客厅吸顶灯"))
}
