import SwiftUI

// MARK: - 设计 Token

/// 统一设计规范常量
enum AppDesign {
    // MARK: 圆角
    enum CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let `default`: CGFloat = 14   // 按钮 / 输入框默认圆角
        static let large: CGFloat = 18       // 卡片圆角
        static let xl: CGFloat = 24          // 登录页白色卡片顶部圆角
        static let capsule: CGFloat = 20     // 胶囊/Toast 圆角
        static let circle: CGFloat = 17      // 胶囊组件（半高 = 圆角）
    }

    // MARK: 尺寸
    enum Button {
        static let height: CGFloat = 54       // 主按钮高度（full-width）
        static let mediumHeight: CGFloat = 48 // 底部弹窗按钮高度
        static let smallHeight: CGFloat = 38  // 小按钮高度
        static let iconSize: CGFloat = 38     // header 圆形图标按钮
        static let circleSize: CGFloat = 44   // 视频悬浮圆形按钮
    }

    // MARK: 间距
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let `default`: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: 阴影
    enum Shadow {
        static let card: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) =
        (.black.opacity(0.04), 4, 0, 1)
        static let elevated: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) =
        (.black.opacity(0.08), 8, 0, 2)
    }
}

// MARK: - 按钮样式

// MARK: 1. 主按钮（渐变填充）

/// 主操作按钮 —— 渐变背景 + 白色粗体文字
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var enabled: Bool = true

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .kerning(0.1)
                }
                Spacer()
            }
            .frame(height: AppDesign.Button.height)
            .background(
                LinearGradient(
                    colors: [.gradientStart, .gradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(AppDesign.CornerRadius.default)
            .opacity(isLoading ? 0.6 : 1.0)
        }
        .disabled(!enabled || isLoading)
    }
}

// MARK: 2. 主按钮（纯色填充）

/// 纯色主按钮 —— 用于不需要渐变的场景（如登录页）
struct SolidPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var enabled: Bool = true
    var height: CGFloat = AppDesign.Button.height

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .kerning(0.1)
                }
                Spacer()
            }
            .frame(height: height)
            .background(Color.primaryColor)
            .cornerRadius(AppDesign.CornerRadius.default)
        }
        .disabled(!enabled || isLoading)
    }
}

// MARK: 3. 描边次要按钮

/// 描边样式按钮 —— 白色背景 + 主色边框 + 主色文字
struct OutlinedButton: View {
    let title: String
    let action: () -> Void
    var height: CGFloat = AppDesign.Button.height

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primaryColor)
                Spacer()
            }
            .frame(height: height)
            .background(Color.cardBg)
            .cornerRadius(AppDesign.CornerRadius.default)
            .overlay(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                    .stroke(Color.primaryColor, lineWidth: 1)
            )
        }
    }
}

// MARK: 4. 危险/破坏性按钮

/// 危险操作按钮 —— 红色渐变背景
struct DestructiveButton: View {
    let title: String
    let action: () -> Void
    var height: CGFloat = AppDesign.Button.height

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.42, blue: 0.42),
                                Color(red: 1.0, green: 0.27, blue: 0.27),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
    }
}

// MARK: 5. 取消按钮

/// 取消/次要操作按钮 —— 浅灰背景 + 深灰文字 + 边框
/// 用于底部弹窗中
struct CancelButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: AppDesign.Button.mediumHeight)
                .background(Color.bgColor)
                .cornerRadius(AppDesign.CornerRadius.default)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                        .stroke(Color.borderColor, lineWidth: 1)
                )
        }
    }
}

// MARK: 6. Header 圆形图标按钮

/// Header 区域白色圆形小按钮（带图标）
struct HeaderIconButton: View {
    let systemName: String
    let action: () -> Void
    var size: CGFloat = 38
    var cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundColor(.primaryColor)
                .frame(width: size, height: size)
                .background(Color.white)
                .cornerRadius(cornerRadius)
        }
    }
}

// MARK: 7. 视频悬浮圆形按钮

/// 视频播放器区域的半透明圆形按钮
struct VideoCircleButton: View {
    var icon: String = ""
    var text: String = ""
    var color: Color = .white.opacity(0.9)
    var action: () -> Void
    var size: CGFloat = 44

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: size, height: size)

                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: size, height: size)

                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(color)
                } else {
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(color)
                }
            }
        }
    }
}

// MARK: 8. 控制面板按钮（含标签）

/// 设备详情控制栏按钮 —— 图标区 48×48 + 标签
struct ControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var isActive: Bool = false
    var activeColor: Color? = nil

    var body: some View {
        let tint: Color = (isActive ? (activeColor ?? .red) : AppDesignTokens.controlBtnTint)
        let labelColor: Color = (isActive ? tint : AppDesignTokens.controlLabelColor)

        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                        .fill(AppDesignTokens.controlBtnBg)
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(tint)
                }
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(labelColor)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: 9. 底部操作按钮

/// 底部行动按钮 —— 浅蓝背景 + 图标 + 文字
struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 14))
            }
            .foregroundColor(AppDesignTokens.controlBtnTint)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                    .fill(AppDesignTokens.controlBtnBg)
            )
        }
    }
}

// MARK: 10. 胶囊/标签按钮

/// 选择型胶囊按钮 —— 选中时主色填充，未选中时描边
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : .textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.primaryColor : Color.cardBg)
                .cornerRadius(AppDesign.CornerRadius.default)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                        .stroke(
                            isSelected ? Color.clear : Color.borderColor,
                            lineWidth: 1
                        )
                )
        }
    }
}

// MARK: 11. 菜单 "···" 按钮

/// 三点菜单按钮 —— 常用于卡片右上角
struct MenuButton: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.textDisabled)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - Toast 样式

// MARK: 通用 Toast 修饰器

/// Toast 显示修饰器 —— 底部居中，黑色半透明背景，白色文字
/// 用法: .appToast(message: $toastMessage)
struct AppToastModifier: ViewModifier {
    @Binding var message: String?
    var isError: Bool = false
    var duration: TimeInterval = 2.0

    func body(content: Content) -> some View {
        content.overlay(toastOverlay)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let msg = message {
            VStack {
                Spacer()
                Text(msg)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        isError
                        ? Color.red.opacity(0.85)
                        : Color.black.opacity(0.75)
                    )
                    .cornerRadius(AppDesign.CornerRadius.capsule)
                    .padding(.bottom, 50)
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: message != nil)
        }
    }
}

// MARK: Toast View（可独立使用）

/// 独立 Toast 视图组件
/// 用法: AppToastView(message: "操作成功")
struct AppToastView: View {
    let message: String
    var isError: Bool = false

    var body: some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                isError
                ? Color.red.opacity(0.85)
                : Color.black.opacity(0.75)
            )
            .cornerRadius(AppDesign.CornerRadius.capsule)
    }
}

// MARK: View Extension — 便捷 Toast

extension View {
    /// 绑定式 Toast（自动 2s 消失）
    func appToast(message: Binding<String?>, isError: Bool = false, duration: TimeInterval = 2.0) -> some View {
        modifier(AppToastModifier(message: message, isError: isError, duration: duration))
    }
}

// MARK: - 输入框样式

// MARK: 标准输入框

/// 标准输入框组件 —— 圆角浅灰背景 + 边框
struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.textSecondary)
                    .frame(width: 18)
            }

            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .autocapitalization(.none)
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .autocapitalization(.none)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.default)
        .frame(height: 52)
        .background(Color.inputBg)
        .cornerRadius(AppDesign.CornerRadius.default)
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                .stroke(Color.borderColor, lineWidth: 1)
        )
    }
}

// MARK: 带标签的输入框

/// 带标签的输入字段（标签在上，输入框在下）
struct LabeledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
            AppTextField(placeholder: placeholder, text: $text, icon: icon)
        }
    }
}

// MARK: 选择器型输入框（只读，点击弹出选择器）

/// 只读选择器 —— 外观类似输入框，点击弹出选择器
struct PickerField: View {
    let label: String
    let placeholder: String
    let selectedText: String
    let actionLabel: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)

            Button(action: action) {
                HStack(spacing: 0) {
                    Image(systemName: "house")
                        .font(.system(size: 18))
                        .foregroundColor(.textSecondary)

                    Text(selectedText.isEmpty ? placeholder : selectedText)
                        .font(.system(size: 15))
                        .foregroundColor(
                            selectedText.isEmpty ? .textDisabled : .textPrimary
                        )
                        .lineLimit(1)
                        .padding(.leading, 12)

                    Spacer()

                    Text(actionLabel)
                        .font(.system(size: 13))
                        .foregroundColor(.primaryColor)
                }
                .padding(.horizontal, AppDesign.Spacing.default)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                        .fill(Color.inputBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                        .stroke(Color.borderColor, lineWidth: 1)
                )
            }
            .disabled(disabled)
        }
    }
}

// MARK: - 文本样式

// MARK: 文本层级

/// 统一文本层级
enum AppText {
    /// 页面标题：26pt, bold
    static func pageTitle(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 26, weight: .bold))
    }

    /// 区块标题：20pt, bold
    static func sectionTitle(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 20, weight: .bold))
    }

    /// 卡片/弹窗标题：17pt, semibold
    static func cardTitle(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
    }

    /// 导航栏标题：18pt, bold, white
    static func navTitle(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 18, weight: .bold))
    }

    /// 正文：15pt, regular
    static func body(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 15))
    }

    /// 正文粗体：16pt, bold
    static func bodyBold(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 16, weight: .bold))
    }

    /// 说明/副文本：13pt, regular
    static func caption(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 13))
    }

    /// 小标注：12pt, regular
    static func small(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 12))
    }

    /// 微小标注：11pt, regular
    static func tiny(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 11))
    }

    /// 标签文字：13pt, bold
    static func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 13, weight: .bold))
    }
}

// MARK: 文本颜色修饰器

extension View {
    /// 主文字色 #15161A
    func textPrimaryColor() -> some View {
        foregroundColor(.textPrimary)
    }

    /// 辅助文字色 #9DA3B0
    func textSecondaryColor() -> some View {
        foregroundColor(.textSecondary)
    }

    /// 禁用文字色 #C8CDD8
    func textDisabledColor() -> some View {
        foregroundColor(.textDisabled)
    }

    /// 主色文字
    func textAccentColor() -> some View {
        foregroundColor(.primaryColor)
    }

    /// 危险色文字
    func textDangerColor() -> some View {
        foregroundColor(.dangerColor)
    }

    /// 成功色文字
    func textSuccessColor() -> some View {
        foregroundColor(.successColor)
    }
}

// MARK: - 卡片/容器样式

// MARK: 标准卡片

/// 标准白色卡片 —— 圆角 + 浅阴影
struct AppCard<Content: View>: View {
    var cornerRadius: CGFloat = AppDesign.CornerRadius.large
    var padding: CGFloat = AppDesign.Spacing.default
    var hasShadow: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.cardBg)
            .cornerRadius(cornerRadius)
            .if(hasShadow) { view in
                view.shadow(
                    color: AppDesign.Shadow.card.color,
                    radius: AppDesign.Shadow.card.radius,
                    x: AppDesign.Shadow.card.x,
                    y: AppDesign.Shadow.card.y
                )
            }
    }
}

// MARK: 信息行

/// 标准信息展示行 —— 标签(左) + 值(右)
struct InfoRow: View {
    let label: String
    let value: String
    var showChevron: Bool = false
    var iconEmoji: String = ""

    var body: some View {
        HStack(spacing: 0) {
            if !iconEmoji.isEmpty {
                Circle()
                    .fill(Color(red: 0.93, green: 0.96, blue: 1.0))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(iconEmoji)
                            .font(.system(size: 16))
                    )
            }

            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.textPrimary)
                .padding(.leading, iconEmoji.isEmpty ? 0 : 14)

            Spacer()

            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .lineLimit(1)

            if showChevron {
                Text("›")
                    .font(.system(size: 22))
                    .foregroundColor(.textDisabled)
                    .padding(.leading, 6)
            }
        }
        .padding(.horizontal, AppDesign.Spacing.default)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: AppDesign.CornerRadius.default)
                .fill(Color.inputBg)
        )
    }
}

// MARK: 区块标题行

/// 卡片内的区块标题 —— 图标 + 标题文字
struct SectionHeaderView: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.primaryColor)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, AppDesign.Spacing.default)
        .padding(.top, AppDesign.CornerRadius.default)
        .padding(.bottom, 10)
    }
}

// MARK: - 导航栏样式

// MARK: 导航栏返回按钮

/// 标准返回按钮
struct NavBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 加载指示器

// MARK: 全屏加载

/// 全屏加载状态 —— 居中 spinner + 提示文字
struct FullScreenLoader: View {
    var message: String = ""
    var tint: Color = .primaryColor

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: tint))

            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: 内嵌加载

/// 内嵌加载指示器 —— 与其他内容混排
struct InlineLoader: View {
    var message: String = ""

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryColor))
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
            }
        }
    }
}

// MARK: - 空状态

/// 通用空状态视图
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(.textDisabled)

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.top, 20)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .padding(.top, 8)
                .multilineTextAlignment(.center)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 160, height: 50)
                        .background(Color.primaryColor)
                        .cornerRadius(AppDesign.CornerRadius.default)
                }
                .padding(.top, 28)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 错误状态

/// 通用错误状态视图
struct ErrorStateView: View {
    let message: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.warningColor)
            Text(L("Load Failed"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Text(L("Retry"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 38)
                        .background(Color.primaryColor)
                        .cornerRadius(19)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 分隔线

/// 水平分割线 —— 两侧有文字或留空
struct HorizontalDivider: View {
    var text: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.borderColor)
                .frame(height: 1)

            if let text = text {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 14)
                Rectangle()
                    .fill(Color.borderColor)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - 胶囊/Badge

/// 信息胶囊 —— 半透明白色背景
struct InfoCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.15))
            .cornerRadius(AppDesign.CornerRadius.capsule)
    }
}

/// 小标签 —— 用于设备分享标记等
struct TinyBadge: View {
    let text: String
    var color: Color = .primaryColor

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.7))
            .cornerRadius(4)
    }
}

/// 在线状态点
struct OnlineStatusDot: View {
    let isOnline: Bool
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(isOnline ? Color.successColor : Color.textDisabled)
            .frame(width: size, height: size)
    }
}

// MARK: 状态点 + 文字组合

/// 在线状态指示器 —— 圆点 + 文字
struct StatusIndicator: View {
    let isOnline: Bool
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            OnlineStatusDot(isOnline: isOnline)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - 渐变 Header

/// 通用渐变 Header 背景
struct GradientHeader<Content: View>: View {
    var height: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .if(height != nil) { $0.frame(height: height!) }
            .background(Color.headerGradient)
    }
}

// MARK: - 通用锚点

/// 通用设备图标背景（圆角矩形 + 渐变 + 图标）
struct DeviceIconView: View {
    var size: CGFloat = 56
    var cornerRadius: CGFloat = AppDesign.CornerRadius.default
    var iconName: String = "video.fill"
    var iconSize: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.deviceIconGradient)
                .frame(width: size, height: size)
            Image(systemName: iconName)
                .font(.system(size: iconSize))
                .foregroundColor(.primaryColor)
        }
    }
}

// MARK: - 内部 Token 常量

/// 设计系统内部使用的颜色常量（不对外暴露）
private enum AppDesignTokens {
    static let controlBtnBg = Color(red: 0xF0 / 255, green: 0xF5 / 255, blue: 0xFF / 255)
    static let controlBtnTint = Color(red: 0x00 / 255, green: 0x6E / 255, blue: 0xFF / 255)
    static let controlLabelColor = Color(red: 0x9D / 255, green: 0xA3 / 255, blue: 0xB0 / 255)
}

// MARK: - 条件修饰器辅助

extension View {
    /// 条件应用修饰器
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            PrimaryButton(title: "主操作按钮", action: {})
            SolidPrimaryButton(title: "纯色按钮", action: {})
            OutlinedButton(title: "描边按钮", action: {})
            DestructiveButton(title: "危险操作", action: {})
            CancelButton(title: "取消", action: {})

            HStack {
                HeaderIconButton(systemName: "bell.fill", action: {})
                HeaderIconButton(systemName: "plus", action: {})
                HeaderIconButton(systemName: "person.fill", action: {})
            }

            VideoCircleButton(icon: "speaker.wave.2.fill", action: {})

            HStack {
                ControlButton(icon: "mic.fill", label: "对讲", action: {})
                ControlButton(icon: "camera.fill", label: "截图", action: {})
                ControlButton(icon: "video.fill", label: "录像", action: {})
            }

            AppTextField(placeholder: "请输入内容", text: .constant(""), icon: "person.fill")
            LabeledTextField(
                label: "用户名",
                placeholder: "请输入用户名",
                text: .constant(""),
                icon: "person.fill"
            )

            AppCard {
                VStack(alignment: .leading) {
                    Text("卡片标题")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("卡片内容描述文字")
                        .font(.system(size: 13))
                        .foregroundColor(.textSecondary)
                }
            }

            AppToastView(message: "这是一条提示消息")
            AppToastView(message: "操作失败，请重试", isError: true)

            FullScreenLoader(message: "加载中...")
        }
        .padding()
    }
    .background(Color.bgColor)
}
