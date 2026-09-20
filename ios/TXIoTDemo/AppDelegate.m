#import "AppDelegate.h"
#import "SceneDelegate.h"
#import "TXIoTDemo-Swift.h"
#import <TXLiteAVSDK_IOT/TXIoTEngine.h>
#import <TXLiteAVSDK_IOT/TXIoTEngineDef.h>
#import <TXLiteAVSDK_IOT/TXLiveBase.h>

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

    // 前往腾讯云点播播放器页面购买：https://cloud.tencent.com/document/product/881/74588
    // 如果不打算使用腾讯云点播播放器，可以将以下两个常量设置为空字符串
    NSString *const licenseURL = ;
    NSString *const licenseKey = ;
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
