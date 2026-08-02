import SwiftUI
import TXLiteAVSDK_Professional

// MARK: - 推送消息数据模型（用于 UI 展示）

struct PushMessageItem: Identifiable {
    let id = UUID()
    let messageTime: Date
    let type: TXIoTPushMessageType
    let subType: TXIoTPushMessageSubType
    let productId: String
    let deviceName: String

    var typeLabel: String {
        switch type {
        case .statusChange: return L("Status Changed")
        @unknown default: return L("Unknown")
        }
    }

    var subTypeLabel: String {
        switch subType {
        case .online: return L("Went Online")
        case .offline: return L("Went Offline")
        @unknown default: return ""
        }
    }

    var typeColor: Color {
        switch type {
        case .statusChange: return subType == .online ? .green : .gray
        @unknown default: return .primaryColor
        }
    }
}

// MARK: - 全局消息存储（单例，供 AppDelegate 写入）

@MainActor
final class PushMessageStore: NSObject, ObservableObject {
    @objc static let shared = PushMessageStore()
    private override init() {}

    @Published var messages: [PushMessageItem] = []

    /// 供 AppDelegate（OC）直接调用，将推送消息存入 store
    @objc func appendMessage(_ msg: TXIoTPushMessage) {
        append(msg)
    }

    func append(_ msg: TXIoTPushMessage) {
        let item = PushMessageItem(
            messageTime: Date(timeIntervalSince1970: TimeInterval(msg.messageTime)),
            type: msg.type,
            subType: msg.subType,
            productId: msg.deviceId.productId,
            deviceName: msg.deviceId.deviceName
        )
        messages.insert(item, at: 0)
        // 最多保留 200 条
        if messages.count > 200 {
            messages = Array(messages.prefix(200))
        }
    }

    func clear() {
        messages = []
    }
}

// MARK: - 推送消息列表页面

struct PushMessageView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var store: PushMessageStore = PushMessageStore.shared
    @State private var showClearAlert = false
    @State private var expandedId: UUID?

    var body: some View {
        NavigationView {
            ZStack {
                Color.bgColor.ignoresSafeArea()

                if store.messages.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.textDisabled)
                        Text(L("No push messages"))
                            .font(.system(size: 16))
                            .foregroundColor(.textSecondary)
                        Text(L("Device online/offline messages will appear here"))
                            .font(.system(size: 13))
                            .foregroundColor(.textDisabled)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    List {
                        ForEach(store.messages) { item in
                            PushMessageRowView(
                                item: item,
                                isExpanded: expandedId == item.id
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    expandedId = expandedId == item.id ? nil : item.id
                                }
                            }
                            .listRowBackground(Color.white)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .background(Color.white)
                }
            }
            .navigationTitle(L("Push Messages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L("Close")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    clearButton
                }
            }
            .alert(L("Clear Messages"), isPresented: $showClearAlert) {
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Clear"), role: .destructive) { store.clear() }
            } message: {
                Text(L("Are you sure you want to clear all push messages?"))
            }
        }
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var clearButton: some View {
        if !store.messages.isEmpty {
            Button(action: { showClearAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.dangerColor)
            }
        }
    }
}

// MARK: - 消息行视图

struct PushMessageRowView: View {
    let item: PushMessageItem
    let isExpanded: Bool
    let onTap: () -> Void

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    typeLabel
                    deviceInfoView
                    Spacer()
                    expandChevron
                }
                .padding(.vertical, 12)

                expandedDetails
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 主行子视图

    private var typeLabel: some View {
        Text(item.typeLabel)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(item.typeColor)
            .cornerRadius(4)
    }

    private var deviceInfoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(item.productId)/\(item.deviceName)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                if !item.subTypeLabel.isEmpty {
                    Text(item.subTypeLabel)
                        .font(.system(size: 11))
                        .foregroundColor(item.typeColor)
                }
                Text(timeFormatter.string(from: item.messageTime))
                    .font(.system(size: 11))
                    .foregroundColor(.textDisabled)
            }
        }
    }

    private var expandChevron: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 12))
            .foregroundColor(.textDisabled)
    }

    // MARK: - 展开详情

    @ViewBuilder
    private var expandedDetails: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 6) {
                Divider()

                Text(L("Product ID: %@", "\(item.productId)"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
                Text(L("Device: %@", "\(item.deviceName)"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
                Text(L("Time: %@", "\(timeFormatter.string(from: item.messageTime))"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textSecondary)
            }
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

#Preview {
    PushMessageView()
}
