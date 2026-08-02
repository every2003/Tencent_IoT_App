import SwiftUI

struct LoginView: View {
    @EnvironmentObject var userManager: UserManager

    @State private var appKey = ""
    @State private var appSecret = ""
    @State private var userId = ""

    @State private var showAlert = false
    @State private var alertMessage = ""

    /// Header 视图总高度（用于定位白色卡片）
    private var headerHeight: CGFloat {
        // 图标80 + 标题间距14 + 标题高度~31 + 副标题间距6 + 副标题高度~17 + 底部间距50 - offset18
        80 + 14 + 31 + 6 + 17 + 50 - 18
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.headerGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView

                Spacer(minLength: 0)
            }

            loginCardView
                .padding(.top, headerHeight + 2)  // 卡片顶部位置 = header高度 + 少量间距
        }
        .ignoresSafeArea(edges: .bottom)
        .alert(alertMessage, isPresented: $showAlert) {
            Button(L("OK"), role: .cancel) {}
        }
    }

    // MARK: - 渐变 Header（背景延伸到状态栏下方，内容通过 offset 上移贴近状态栏）

    private var headerView: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "video.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }

            Text(L("Smart Camera"))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 14)

            Text(L("Smart security, smart life"))
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .padding(.top, 6)
        }
        .padding(.bottom, 50)
        .frame(maxWidth: .infinity)
        .offset(y: -18)
    }

    // MARK: - 白色登录卡片（全宽，顶部圆角，延伸至屏幕底部）

    private var loginCardView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Account Login"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.textPrimary)
                .padding(.bottom, 6)

            Text(L("Please fill in the following information to log in"))
                .font(.system(size: 13))
                .foregroundColor(.textSecondary)
                .padding(.bottom, 28)

            LabeledTextField(
                label: "UserId",
                placeholder: L("Please enter UserId"),
                text: $userId,
                icon: "person.fill"
            )
            .padding(.bottom, 16)

            LabeledTextField(
                label: "AppKey",
                placeholder: L("Please enter AppKey"),
                text: $appKey,
                icon: "key.fill"
            )
            .padding(.bottom, 16)

            LabeledTextField(
                label: "AppSecret",
                placeholder: L("Please enter AppSecret"),
                text: $appSecret,
                icon: "lock.fill"
            )
            .padding(.bottom, 32)

            SolidPrimaryButton(
                title: L("Log In"),
                action: handleLogin,
                isLoading: userManager.isLoading,
                enabled: !userId.isEmpty && !appKey.isEmpty && !appSecret.isEmpty
            )
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.cardBg)
        .clipShape(RoundedCorner(radius: 24, corners: [.topLeft, .topRight]))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: -4)
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared
                .sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
        }
    }

    // MARK: - Actions

    func handleLogin() {
        userManager.login(appKey: appKey, appSecret: appSecret, userId: userId) {
            success,
            errorMessage in
            if success {
                alertMessage = L("Login successful")
                showAlert = true
            } else {
                alertMessage = errorMessage ?? L("Login Failed")
                showAlert = true
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(UserManager())
}
