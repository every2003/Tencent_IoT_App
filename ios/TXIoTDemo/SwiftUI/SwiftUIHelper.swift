import SwiftUI
import UIKit

@objc class SwiftUIHelper: NSObject {

    nonisolated(unsafe) static var navigationController: UINavigationController?

    @MainActor @objc static func createLoginViewController(userManager: UserManager)
        -> UIViewController
    {
        let loginView = LoginView()
            .environmentObject(userManager)

        let hostingController = UIHostingController(rootView: loginView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        return hostingController
    }

    @MainActor @objc static func createDeviceListViewController(
        userManager: UserManager,
        deviceViewModel: DeviceViewModel,
        navigationBridge: NavigationBridge
    ) -> UIViewController {
        let deviceListView = DeviceListView(navigationBridge: navigationBridge)
            .environmentObject(userManager)
            .environmentObject(deviceViewModel)

        let hostingController = UIHostingController(rootView: deviceListView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        return hostingController
    }

    @MainActor @objc static func createDeviceDetailViewController(
        device: Device,
        channelList: [Int]
    ) -> UIViewController {
        let deviceDetailView = DeviceDetailView(device: device, channelList: channelList)

        let hostingController = UIHostingController(rootView: deviceDetailView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        return hostingController
    }

    @MainActor @objc static func createLampDetailViewController(device: Device) -> UIViewController {
        let lampDetailView = LampDetailView(device: device)

        let hostingController = UIHostingController(rootView: lampDetailView)
        hostingController.navigationItem.largeTitleDisplayMode = .never
        return hostingController
    }

    // 创建添加设备视图控制器
    @MainActor @objc static func createAddDeviceViewController(deviceViewModel: DeviceViewModel)
        -> UIViewController
    {
        let addDeviceView = AddDeviceView()
            .environmentObject(deviceViewModel)
        return UIHostingController(rootView: addDeviceView)
    }

    // 原有方法保留兼容性
    @MainActor @objc static func createHostingController() -> UIViewController {
        let swiftUIView = AddDeviceView().environmentObject(DeviceViewModel())
        return UIHostingController(rootView: swiftUIView)
    }

    // 设置导航控制器
    @objc static func setNavigationController(_ navigationController: UINavigationController) {
        self.navigationController = navigationController
    }
}

// 导航桥接类 - 用于SwiftUI中触发OC页面跳转
@objc class NavigationBridge: NSObject, ObservableObject {
    @Published var shouldNavigateToDeviceDetail = false
    @Published var selectedDeviceInfo: [String: Any]?
}
