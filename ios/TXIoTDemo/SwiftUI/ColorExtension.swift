import SwiftUI

extension Color {
    static let primaryColor = Color(red: 0x00 / 255, green: 0x6E / 255, blue: 0xFF / 255)

    static let gradientStart = Color(red: 0x1A / 255, green: 0x73 / 255, blue: 0xE8 / 255)

    static let gradientEnd = Color(red: 0x00 / 255, green: 0x6E / 255, blue: 0xFF / 255)

    static let successColor = Color(red: 0.322, green: 0.769, blue: 0.102)

    static let warningColor = Color(red: 0.980, green: 0.678, blue: 0.078)

    static let dangerColor = Color(red: 1.0, green: 0.302, blue: 0.310)

    static let bgColor = Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF8 / 255)

    static let cardBg = Color.white

    static let textPrimary = Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x1A / 255)

    static let textSecondary = Color(red: 0x9D / 255, green: 0xA3 / 255, blue: 0xB0 / 255)

    static let textDisabled = Color(red: 0xC8 / 255, green: 0xCD / 255, blue: 0xD8 / 255)

    static let borderColor = Color(red: 0xE7 / 255, green: 0xE8 / 255, blue: 0xEB / 255)

    static let wechatGreen = Color(red: 0.027, green: 0.757, blue: 0.376)

    static let inputBg = Color(red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xFA / 255)

    // 设备图标背景渐变起始
    static let deviceIconStart = Color(red: 0xE8 / 255, green: 0xF0 / 255, blue: 0xFF / 255)
    // 设备图标背景渐变结束
    static let deviceIconEnd = Color(red: 0xD0 / 255, green: 0xE4 / 255, blue: 0xFF / 255)

    // 渐变色 - 用于 Header 背景
    static let headerGradient = LinearGradient(
        colors: [Color.gradientStart, Color.gradientEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // 渐变色 - 用于设备卡片图标背景
    static let deviceIconGradient = LinearGradient(
        colors: [Color.deviceIconStart, Color.deviceIconEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
