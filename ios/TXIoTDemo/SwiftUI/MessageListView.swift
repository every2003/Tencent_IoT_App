import SwiftUI
import TXLiteAVSDK_IOT

// MARK: - 消息中心主视图（仅推送通知）

struct MessageListView: View {
    @ObservedObject private var pushStore = PushMessageStore.shared
    @State private var expandedPushId: UUID?
    @State private var showClearPushAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBanner
            pushNotificationContent
        }
        .background(Color.bgColor.ignoresSafeArea())
        .alert(L("Clear Push"), isPresented: $showClearPushAlert) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Clear"), role: .destructive) { pushStore.clear() }
        } message: {
            Text(L("Are you sure you want to clear all push messages?"))
        }
    }

    // MARK: - 头部 Banner
    private var headerBanner: some View {
        VStack(spacing: 0) {
            navBar
        }
        .background(Color.headerGradient.ignoresSafeArea(edges: .top))
    }

    // MARK: - 导航栏
    private var navBar: some View {
        HStack {
            NavBackButton(action: { dismiss() })

            Spacer()

            Text(L("Message Center"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            if pushStore.messages.isEmpty {
                Color.clear
                    .frame(width: 44, height: 44)
            } else {
                Button(action: { showClearPushAlert = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                }
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
    }

    // MARK: - 推送通知内容区域
    @ViewBuilder
    private var pushNotificationContent: some View {
        if pushStore.messages.isEmpty {
            VStack(spacing: 14) {
                Spacer()
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
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(pushStore.messages) { item in
                    PushMessageRowView(
                        item: item,
                        isExpanded: expandedPushId == item.id
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            expandedPushId = expandedPushId == item.id ? nil : item.id
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
}

#Preview {
    MessageListView()
}
