#import "SceneDelegate.h"

@interface SceneDelegate ()

@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    
    // 通过 SDK getLoginUserInfo 判断是否已登录（登录状态完全由 SDK 管理）
    if ([UserManager checkLoginValid]) {
        [self showDeviceListView];
    } else {
        [self showLoginView];
    }
    
    [self.window makeKeyAndVisible];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
}

- (void)sceneWillResignActive:(UIScene *)scene {
    // This may occur due to temporary interruptions (ex. an incoming phone call).
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    // to restore the scene back to its current state.
}

#pragma mark - Navigation Methods

- (void)showDeviceListView {
    UserManager *userManager = [[UserManager alloc] init];
    DeviceViewModel *deviceViewModel = [[DeviceViewModel alloc] init];
    NavigationBridge *navigationBridge = [[NavigationBridge alloc] init];
    
    __weak typeof(self) weakSelf = self;
    userManager.logoutCallback = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf showLoginView];
        });
    };
    
    UIViewController *deviceListVC = [SwiftUIHelper createDeviceListViewControllerWithUserManager:userManager
                                                                                   deviceViewModel:deviceViewModel
                                                                                  navigationBridge:navigationBridge];
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:deviceListVC];
    navController.navigationBar.prefersLargeTitles = NO;
    
    self.window.rootViewController = navController;
    [SwiftUIHelper setNavigationController:navController];
}

- (void)showLoginView {
    UserManager *userManager = [[UserManager alloc] init];
    
    __weak typeof(self) weakSelf = self;
    userManager.loginSuccessCallback = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf showDeviceListView];
        });
    };
    
    UIViewController *loginVC = [SwiftUIHelper createLoginViewControllerWithUserManager:userManager];
    
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:loginVC];
    navController.navigationBar.prefersLargeTitles = NO;
    
    self.window.rootViewController = navController;
    [SwiftUIHelper setNavigationController:navController];
}

@end
