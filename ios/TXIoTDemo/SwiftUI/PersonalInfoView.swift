import SwiftUI

struct PersonalInfoView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) var dismiss

    private var userInfo: TXIoTUserInfo? {
        TXIoTEngine.getInstance().getLoginUserInfo()
    }

    var body: some View {
        VStack(spacing: 0) {
            gradientBanner
            whiteCard
        }
        .background(Color.bgColor.ignoresSafeArea())
    }

    // MARK: - 渐变 Banner（bg_profile_header: #1A73E8→#006EFF 135°, paddingBottom=36dp）
    private var gradientBanner: some View {
        VStack(spacing: 0) {
            navBar
            avatarAndNickname
        }
        .padding(.bottom, 36)
        .background(Color.headerGradient.ignoresSafeArea(edges: .top))
    }

    // MARK: - 导航栏（48dp, gravity=center_vertical）
    private var navBar: some View {
        HStack {
            NavBackButton(action: { dismiss() })

            Spacer()

            Text(L("Personal Info"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
    }

    // MARK: - 头像 + 昵称（marginTop=16dp, gravity=center）
    private var avatarAndNickname: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 84, height: 84)
                Circle()
                    .fill(Color(red: 0.91, green: 0.93, blue: 1.0))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.primaryColor.opacity(0.6))
            }

            Text(displayNickname)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 10)
        }
        .padding(.top, 16)
    }

    // MARK: - 白色内容卡片（marginTop=-20dp, paddingTop=28dp, paddingHorizontal=20dp, weight=1）
    private var whiteCard: some View {
        VStack(spacing: 0) {
            sectionLabel

            InfoRow(label: L("Nickname"), value: displayNickname, showChevron: true, iconEmoji: "👤")

            InfoRow(label: L("User ID"), value: userInfo?.userId ?? "", iconEmoji: "🆔")
                .padding(.top, 2)

            DestructiveButton(title: L("🚪 Log Out")) {
                userManager.logout()
                dismiss()
            }
            .padding(.top, 32)

            // 版本信息（marginTop=20dp）
            versionLabel
                .padding(.top, 20)

            Spacer(minLength: 0)
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    // MARK: - 分区标题（"👤 账号信息", 12sp, #9DA3B0, letterSpacing=0.05）
    private var sectionLabel: some View {
        Text(L("Account Info"))
            .font(.system(size: 12))
            .foregroundColor(.textSecondary)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
    }

    // MARK: - 版本信息（"IoT Link App", 12sp, #C8CDD8, gravity=center）
    private var versionLabel: some View {
        Text("IoT Link App")
            .font(.system(size: 12))
            .foregroundColor(.textDisabled)
            .frame(maxWidth: .infinity)
    }

    // MARK: - 辅助
    private var displayNickname: String {
        userInfo?.nickName ?? userManager.currentUsername
    }
}

#Preview {
    PersonalInfoView()
        .environmentObject(UserManager())
}
