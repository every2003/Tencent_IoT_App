import Foundation

/// 设备硬件类型（按 ProductId 推断，未命中吸顶灯列表时默认为安防摄像头）
@objc enum DeviceHardwareType: Int {
    case camera = 0
    case ceilingLamp = 1
}

/// 设备硬件类型判定：写死智能吸顶灯的 ProductId 列表，其余一律视为安防摄像头。
/// 新增吸顶灯产品时，将其 ProductId 加入 `ceilingLampProductIds` 即可。
enum DeviceHardwareRegistry {

    /// 智能吸顶灯产品的 ProductId 列表（按物联网平台实际创建的产品 ID 配置）
    private static let ceilingLampProductIds: Set<String> = [
        "988BYEG00X"
    ]

    /// 查询 ProductId 对应的硬件类型，未命中吸顶灯列表时返回摄像头
    static func hardwareType(for productId: String) -> DeviceHardwareType {
        ceilingLampProductIds.contains(productId) ? .ceilingLamp : .camera
    }
}

extension Device {
    /// 硬件类型：ProductId 命中吸顶灯列表则为吸顶灯，否则默认为安防摄像头
    var hardwareType: DeviceHardwareType {
        DeviceHardwareRegistry.hardwareType(for: productId)
    }

    var isCeilingLamp: Bool {
        hardwareType == .ceilingLamp
    }
}
