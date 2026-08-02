import SwiftUI

/// 确定按钮样式
enum CommonSheetConfirmStyle {
    case primary  // 蓝色填充（bg_primary_button）
    case danger  // 红色填充（bg_danger_button）
    case outlined  // 描边样式（bg_outline_button）
}

/// 通用底部弹窗控件
///
/// 用法：
/// ```swift
/// .sheet(isPresented: $show) {
///     CommonBottomSheet(
///         title: "标题",
///         hint: "提示文本",
///         confirmTitle: "确定",
///         onConfirm: { ... },
///         onCancel: { show = false }
///     ) {
///         // 自定义内容区域
///         MyContentView()
///     }
/// }
/// ```
struct CommonBottomSheet<Content: View>: View {
    /// 标题
    let title: String
    /// 提示文本，传 nil 或空字符串则隐藏（对齐 setHint）
    var hint: String? = nil
    /// 确定按钮文字，传 nil 则隐藏确定按钮（对齐 hideConfirm）
    var confirmTitle: String? = L("OK")
    /// 确定按钮样式
    var confirmStyle: CommonSheetConfirmStyle = .primary
    /// 确定按钮是否可用
    var confirmEnabled: Bool = true
    /// 取消按钮文字
    var cancelTitle: String = L("Cancel")
    /// 自定义弹窗高度，传 nil 则使用 .medium/.large 自适应
    var sheetHeight: CGFloat? = nil
    /// 确定回调
    var onConfirm: (() -> Void)? = nil
    /// 取消回调
    var onCancel: (() -> Void)? = nil
    /// 内容区域
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.cardBg

                VStack(spacing: 0) {
                    Color.clear.frame(height: 25)

                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    hintView

                    content()
                        .padding(.top, 12)

                    Spacer(minLength: 0)
                        .layoutPriority(-1)

                    buttonRow
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)

                Capsule()
                    .fill(Color.textDisabled.opacity(0.6))
                    .frame(width: 36, height: 5)
                    .position(x: geometry.size.width / 2, y: 10.5)
            }
        }
        .ignoresSafeArea(edges: .top)
        .modifier(CommonSheetPresentation(height: sheetHeight))
    }

    // MARK: - 提取的子视图

    @ViewBuilder
    private var hintView: some View {
        if let hint = hint, !hint.isEmpty {
            Text(hint)
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 6)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 12) {
            if let confirmTitle = confirmTitle {
                confirmButton(confirmTitle)
            }
            cancelButton
        }
    }

    private func confirmButton(_ title: String) -> some View {
        Button(action: { onConfirm?() }) {
            Text(title)
                .modifier(ButtonTextModifier(fg: confirmForeground, bg: confirmBackground))
                .sheetBorder(confirmBorder, lineWidth: confirmStyle == .outlined ? 1 : 0)
        }
        .disabled(!confirmEnabled)
        .opacity(confirmEnabled ? 1 : 0.5)
    }

    private var cancelButton: some View {
        Button(action: { (onCancel ?? {})() }) {
            Text(cancelTitle)
                .modifier(ButtonTextModifier(fg: .textSecondary, bg: .bgColor))
                .sheetBorder(.borderColor)
        }
    }

    // MARK: - 确定按钮样式

    private var confirmForeground: Color {
        switch confirmStyle {
        case .primary, .danger:
            return .white
        case .outlined:
            return .primaryColor
        }
    }

    private var confirmBackground: Color {
        switch confirmStyle {
        case .primary:
            return .primaryColor
        case .danger:
            return .dangerColor
        case .outlined:
            return .cardBg
        }
    }

    private var confirmBorder: Color {
        switch confirmStyle {
        case .outlined:
            return .primaryColor
        default:
            return .clear
        }
    }
}

/// 底部弹窗的呈现修饰符（detents + 浅色背景 + 隐藏系统拖拽条，因为已自绘）
private struct CommonSheetPresentation: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            applyDetents(content)
                .presentationBackground(Color.cardBg)
                .presentationDragIndicator(.hidden)
        } else if #available(iOS 16.0, *) {
            applyDetents(content)
                .presentationDragIndicator(.hidden)
        } else {
            content
        }
    }

    @available(iOS 16.0, *)
    @ViewBuilder
    private func applyDetents(_ content: Content) -> some View {
        if let height = height {
            content.presentationDetents([.height(height)])
        } else {
            content.presentationDetents([.medium, .large])
        }
    }
}

// MARK: - 按钮样式 & 描边辅助

struct ButtonTextModifier: ViewModifier {
    let fg: Color
    let bg: Color
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(bg)
            .cornerRadius(14)
    }
}

extension View {
    func sheetBorder(_ color: Color, lineWidth: CGFloat = 1, cornerRadius: CGFloat = 14) -> some View {
        self.overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(color, lineWidth: lineWidth))
    }
}
