#import <Foundation/Foundation.h>
#import <TXLiteAVSDK_IOT/TXIoTDeviceManager.h>
#import <TXLiteAVSDK_IOT/TXIoTEngine.h>
#import <TXLiteAVSDK_IOT/TXIoTEngineDef.h>
#import <TXLiteAVSDK_IOT/TXIoTFamilyManager.h>

NS_ASSUME_NONNULL_BEGIN

/// 设备绑定完成回调
typedef void (^DeviceBindingCompletion)(BOOL success, NSString *_Nullable message);

/// 强类型设备信息（替代 NSDictionary，避免 Swift 并发 Sendable 问题）
NS_SWIFT_SENDABLE
@interface DeviceInfoItem : NSObject
@property(nonatomic, copy) NSString *deviceId;
@property(nonatomic, copy) NSString *productId;
@property(nonatomic, copy) NSString *deviceName;
@property(nonatomic, copy) NSString *aliasName;
@property(nonatomic, copy) NSString *familyId;
@property(nonatomic, copy) NSString *roomId;
@property(nonatomic, copy) NSString *iconUrl;
@property(nonatomic, assign) NSInteger deviceType;
@property(nonatomic, assign) NSInteger createTime;
@property(nonatomic, assign) NSInteger updateTime;
@property(nonatomic, assign) BOOL isOnline;
@end

/// 设备列表获取完成回调
/// @param success 是否成功
/// @param deviceList 强类型设备列表
/// @param errorMessage 错误信息（失败时）
typedef void (^DeviceListCompletion)(BOOL success, NSArray<DeviceInfoItem *> *_Nullable deviceList,
                                     NSString *_Nullable errorMessage);

/// 解绑设备完成回调
/// @param success 是否成功
/// @param errorMessage 错误信息（失败时）
typedef void (^UnbindDeviceCompletion)(BOOL success, NSString *_Nullable errorMessage);

/// 家庭列表获取完成回调
/// @param success 是否成功
/// @param familyList 家庭列表数组
/// @param errorMessage 错误信息（失败时）
typedef void (^FamilyListCompletion)(BOOL success, NSArray<NSDictionary *> *_Nullable familyList,
                                     NSString *_Nullable errorMessage);

/// 创建家庭完成回调
typedef void (^CreateFamilyCompletion)(BOOL success, NSString *_Nullable familyId,
                                       NSString *_Nullable errorMessage);

/// 通用操作完成回调（无返回数据）
typedef void (^SimpleCompletion)(BOOL success, NSString *_Nullable errorMessage);

/// 房间列表获取完成回调
typedef void (^RoomListCompletion)(BOOL success, NSArray<NSDictionary *> *_Nullable roomList,
                                   NSString *_Nullable errorMessage);

@interface DeviceAPIBridge : NSObject

/// 当前使用的家庭ID（由 getFamilyList 成功后自动设置）
@property(class, nonatomic, copy, nullable) NSString *currentFamilyId;

#pragma mark - 家庭管理

/// 获取家庭列表
/// @param completion 完成回调
+ (void)getFamilyListWithCompletion:(FamilyListCompletion)completion;

/// 创建家庭
/// @param familyName 家庭名称
/// @param address 家庭地址
/// @param completion 完成回调
+ (void)createFamilyWithName:(NSString *)familyName
                     address:(NSString *)address
                  completion:(CreateFamilyCompletion)completion;

/// 更新家庭名称
/// @param familyId 家庭ID
/// @param newName 新名称
/// @param completion 完成回调
+ (void)updateFamilyName:(NSString *)newName
             forFamilyId:(NSString *)familyId
              completion:(SimpleCompletion)completion;

/// 删除家庭
/// @param familyId 家庭ID
/// @param completion 完成回调
+ (void)deleteFamilyWithId:(NSString *)familyId completion:(SimpleCompletion)completion;

#pragma mark - 房间管理

/// 获取房间列表
/// @param familyId 家庭ID
/// @param completion 完成回调
+ (void)getRoomListWithFamilyId:(NSString *)familyId completion:(RoomListCompletion)completion;

/// 创建房间
/// @param roomName 房间名称
/// @param familyId 家庭ID
/// @param completion 完成回调
+ (void)createRoomWithName:(NSString *)roomName
                  familyId:(NSString *)familyId
                completion:(SimpleCompletion)completion;

/// 重命名房间
/// @param roomId 房间ID
/// @param newName 新名称
/// @param familyId 家庭ID
/// @param completion 完成回调
+ (void)renameRoomWithId:(NSString *)roomId
                 newName:(NSString *)newName
                familyId:(NSString *)familyId
              completion:(SimpleCompletion)completion;

/// 删除房间
/// @param roomId 房间ID
/// @param familyId 家庭ID
/// @param completion 完成回调
+ (void)deleteRoomWithId:(NSString *)roomId
                familyId:(NSString *)familyId
              completion:(SimpleCompletion)completion;

/// 将设备绑定到指定房间（设备换房间）
/// @param familyId 家庭ID
/// @param productId 产品ID
/// @param deviceName 设备名称
/// @param roomId 目标房间ID
/// @param completion 完成回调
+ (void)bindDeviceToRoomWithFamilyId:(NSString *)familyId
                           productId:(NSString *)productId
                          deviceName:(NSString *)deviceName
                              roomId:(NSString *)roomId
                          completion:(SimpleCompletion)completion;

/// 将设备从房间移除（设备回到无房间状态）
/// @param familyId 家庭ID
/// @param productId 产品ID
/// @param deviceName 设备名称
/// @param completion 完成回调
+ (void)unbindDeviceFromRoomWithFamilyId:(NSString *)familyId
                               productId:(NSString *)productId
                              deviceName:(NSString *)deviceName
                              completion:(SimpleCompletion)completion;

#pragma mark - 设备绑定

/// 绑定设备（使用设备签名）
/// @param signature 设备签名
/// @param completion 完成回调
+ (void)bindDeviceWithSignature:(NSString *)signature
                     completion:(DeviceBindingCompletion)completion;

#pragma mark - 设备列表

/// 获取设备列表
/// @param familyId 家庭ID
/// @param roomId 房间ID（可选，传 @"" 或 nil 表示获取所有房间的设备）
/// @param completion 完成回调
+ (void)getDeviceListWithFamilyId:(NSString *)familyId
                           roomId:(NSString *_Nullable)roomId
                       completion:(DeviceListCompletion)completion;

/// 获取分享给我的设备列表
/// @param familyId 家庭ID
/// @param completion 完成回调
+ (void)getSharedDeviceListWithFamilyId:(NSString *)familyId
                             completion:(DeviceListCompletion)completion;

#pragma mark - 设备解绑

/// 解绑设备
/// @param familyId 家庭ID
/// @param productId 产品ID
/// @param deviceName 设备名称
/// @param completion 完成回调
+ (void)unbindDeviceWithFamilyId:(NSString *)familyId
                       productId:(NSString *)productId
                      deviceName:(NSString *)deviceName
                      completion:(UnbindDeviceCompletion)completion;

@end

NS_ASSUME_NONNULL_END
