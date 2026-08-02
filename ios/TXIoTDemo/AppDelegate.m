#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "TXIoTDemo-Swift.h"
#import <TXLiteAVSDK_Professional/TXIoTEngine.h>
#import <TXLiteAVSDK_Professional/TXIoTEngineDef.h>
#import <TXLiteAVSDK_Professional/TXLiveBase.h>

@interface AppDelegate () <TXIoTEngineDelegate, TXLiveBaseDelegate>

@end

// 全局屏幕方向控制，默认仅竖屏
static UIInterfaceOrientationMask gSupportedOrientations = UIInterfaceOrientationMaskPortrait;

@implementation AppDelegate

+ (void)setAllowedOrientations:(UIInterfaceOrientationMask)orientations {
    gSupportedOrientations = orientations;
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application
    supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return gSupportedOrientations;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // 配置 License（请替换为从腾讯云控制台获取的 licenseUrl 和 key）
    // 官方文档：https://cloud.tencent.com/document/product/881/77526
    NSString *const licenseURL =
        @"https://1256454991.trtcube-license.cn/license/v2/1256454991_1/v_cube.license";
    NSString *const licenseKey = @"2aaf3d8ce5d00b1dfe93891c0b8fddc6";
    [TXLiveBase setLicenceURL:licenseURL key:licenseKey];
    [TXLiveBase sharedInstance].delegate = self;
    NSLog(@"SDK Version = %@", [TXLiveBase getSDKVersionStr]);

    [[TXIoTEngine getInstance] addDelegate:self];

    return YES;
}

#pragma mark - TXLiveBaseDelegate

- (void)onLicenceLoaded:(int)result Reason:(NSString *)reason {
    NSLog(@"onLicenceLoaded: result:%d reason:%@", result, reason);
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                          sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application
    didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called
    // shortly after application:didFinishLaunchingWithOptions. Use this method to release any
    // resources that were specific to the discarded scenes, as they will not return.
}

#pragma mark - TXIoTEngineDelegate

- (void)onLoginSuccess {
    NSLog(@"TXIoTEngine login succeeded");
    // 发送通知给 UserManager
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSNotificationCenter defaultCenter] postNotificationName:@"TXIoTLoginSuccess" object:nil];
    });
}

- (void)onLoginFailure:(TXIoTErrorCode)errorCode errMsg:(NSString *)errorMessage {
    NSLog(@"TXIoTEngine login failed: %ld, %@", (long)errorCode, errorMessage);
    // 发送通知给 UserManager
    dispatch_async(dispatch_get_main_queue(), ^{
      [[NSNotificationCenter defaultCenter] postNotificationName:@"TXIoTLoginFailure"
                                                          object:nil
                                                        userInfo:@{
                                                            @"errorCode" : @(errorCode),
                                                            @"errorMessage" : errorMessage ?: @""
                                                        }];
    });
}

- (void)onLogout {
    NSLog(@"TXIoTEngine logged out");
    dispatch_async(dispatch_get_main_queue(), ^{
      SceneDelegate *sceneDelegate = (SceneDelegate *)
          [UIApplication.sharedApplication.connectedScenes.allObjects.firstObject delegate];
      [sceneDelegate showLoginView];
    });
}

- (void)onUserSignatureExpired {
    NSLog(@"TXIoTEngine user signature expired");
    dispatch_async(dispatch_get_main_queue(), ^{
      SceneDelegate *sceneDelegate = (SceneDelegate *)
          [UIApplication.sharedApplication.connectedScenes.allObjects.firstObject delegate];
      [sceneDelegate showLoginView];
    });
}

- (void)onReceivePushMessage:(TXIoTPushMessage *)pushMessage {
    if (!pushMessage) {
        NSLog(@"onReceivePushMessage: pushMessage is nil, ignored");
        return;
    }
    NSLog(@"Push message received: type=%ld, subType=%ld", (long)pushMessage.type,
          (long)pushMessage.subType);

    dispatch_async(dispatch_get_main_queue(), ^{
      [[PushMessageStore shared] appendMessage:pushMessage];
    });
}

@end
