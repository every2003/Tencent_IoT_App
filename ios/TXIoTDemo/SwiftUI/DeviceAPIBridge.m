#import "DeviceAPIBridge.h"

@implementation DeviceInfoItem
@end

@implementation DeviceAPIBridge

static NSString *_currentFamilyId = nil;

+ (NSString *)currentFamilyId {
    return _currentFamilyId;
}

+ (void)setCurrentFamilyId:(NSString *)familyId {
    _currentFamilyId = [familyId copy];
}

#pragma mark - 内部工具

/// 构建一个仅包含 onError 的失败回调（SDK 保证回调在主线程，completion 直接同步调用）
+ (TXIoTVoidCallback *)voidCallbackWithCompletion:(SimpleCompletion)completion
                                       successLog:(NSString *)successLog
                                      failureHint:(NSString *)failureHint {
    TXIoTVoidCallback *cb = [[TXIoTVoidCallback alloc] init];
    cb.onSuccess = ^{
      if (successLog)
          NSLog(@"✅ %@", successLog);
      if (completion)
          completion(YES, nil);
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = errorMessage ?: failureHint ?: NSLocalizedString(@"Operation Failed", nil);
      NSLog(@"%@: %@", failureHint ?: @"Operation failed", errorMsg);
      if (completion)
          completion(NO, errorMsg);
    };
    return cb;
}

#pragma mark - 家庭管理

+ (void)getFamilyListWithCompletion:(FamilyListCompletion)completion {
    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, nil, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTCallback<NSArray<TXIoTFamilyInfo *> *> *cb = [[TXIoTCallback alloc] init];
    cb.onSuccess = ^(NSArray<TXIoTFamilyInfo *> * _Nullable result) {
        NSMutableArray<NSDictionary *> *familyList = [NSMutableArray array];
        for (TXIoTFamilyInfo *info in (result ?: @[])) {
            NSDictionary *dict = @{
                @"FamilyId": info.familyId ?: @"",
                @"Name": info.name ?: @"",
                @"CreateTime": @(info.createTime),
                @"UpdateTime": @(info.updateTime),
                @"Role": @(info.role),
            };
            [familyList addObject:dict];
        }
        NSLog(@"Got family list, %lu families", (unsigned long)familyList.count);
        if (completion) completion(YES, familyList, nil);
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = errorMessage ?: NSLocalizedString(@"Failed to get family list", nil);
      NSLog(@"Failed to get family list: %@", errorMsg);
      if (completion)
          completion(NO, nil, errorMsg);
    };
    [familyManager getFamilyList:cb];
}

+ (void)createFamilyWithName:(NSString *)familyName
                     address:(NSString *)address
                  completion:(CreateFamilyCompletion)completion {
    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, nil, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTCallback<TXIoTFamilyInfo *> *cb = [[TXIoTCallback alloc] init];
    cb.onSuccess = ^(TXIoTFamilyInfo *_Nullable result) {
      NSString *familyId = result.familyId;
      NSLog(@"Family created: %@", familyId ?: @"");
      if (completion)
          completion(YES, familyId, nil);
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = errorMessage ?: NSLocalizedString(@"Failed to create family", nil);
      NSLog(@"Failed to create family: %@", errorMsg);
      if (completion)
          completion(NO, nil, errorMsg);
    };
    [familyManager createFamily:familyName callback:cb];
}

+ (void)updateFamilyName:(NSString *)newName
             forFamilyId:(NSString *)familyId
              completion:(SimpleCompletion)completion {
    if (!familyId || familyId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        return;
    }
    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }
    TXIoTFamilyInfo *newInfo = [[TXIoTFamilyInfo alloc] init];
    newInfo.familyId = familyId;
    newInfo.name = newName;

    TXIoTVoidCallback *cb = [self
        voidCallbackWithCompletion:completion
                        successLog:[NSString stringWithFormat:@"Family renamed: %@", newName]
                       failureHint:NSLocalizedString(@"Failed to rename family", nil)];
    [familyManager updateFamilyInfo:newInfo callback:cb];
}

+ (void)deleteFamilyWithId:(NSString *)familyId completion:(SimpleCompletion)completion {
    if (!familyId || familyId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        return;
    }
    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }
    TXIoTVoidCallback *cb =
        [self voidCallbackWithCompletion:completion
                              successLog:[NSString stringWithFormat:@"Family deleted: %@", familyId]
                             failureHint:NSLocalizedString(@"Failed to delete family", nil)];
    [familyManager deleteFamily:familyId callback:cb];
}

#pragma mark - 房间管理

+ (void)getRoomListWithFamilyId:(NSString *)familyId completion:(RoomListCompletion)completion {

    if (!familyId || familyId.length == 0) {
        if (completion) {
            completion(NO, nil, NSLocalizedString(@"Family ID cannot be empty", nil));
        }
        return;
    }

    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, nil, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTCallback<NSArray<TXIoTRoomInfo *> *> *cb = [[TXIoTCallback alloc] init];
    cb.onSuccess = ^(NSArray<TXIoTRoomInfo *> *_Nullable result) {
      NSMutableArray<NSDictionary *> *roomList = [NSMutableArray array];
      for (TXIoTRoomInfo *info in (result ?: @[])) {
          NSDictionary *dict = @{
              @"RoomId" : info.roomId ?: @"",
              @"RoomName" : info.name ?: @"",
              @"FamilyId" : info.familyId ?: @"",
              @"DeviceCount" : @(info.deviceCount),
              @"CreateTime" : @(info.createTime),
              @"UpdateTime" : @(info.updateTime),
          };
          [roomList addObject:dict];
      }
      NSLog(@"Got room list, %lu rooms", (unsigned long)roomList.count);
      if (completion)
          completion(YES, roomList, nil);
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = errorMessage ?: NSLocalizedString(@"Failed to get room list", nil);
      NSLog(@"Failed to get room list: %@", errorMsg);
      if (completion)
          completion(NO, nil, errorMsg);
    };
    [familyManager getRoomList:familyId callback:cb];
}

+ (void)createRoomWithName:(NSString *)roomName
                  familyId:(NSString *)familyId
                completion:(SimpleCompletion)completion {
    if (!familyId || familyId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        return;
    }
    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTCallback<TXIoTRoomInfo *> *cb = [[TXIoTCallback alloc] init];
    cb.onSuccess = ^(TXIoTRoomInfo *_Nullable result) {
      NSLog(@"Room created: %@", result.name);
      if (completion)
          completion(YES, nil);
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = errorMessage ?: NSLocalizedString(@"Failed to create room", nil);
      NSLog(@"Failed to create room: %@", errorMsg);
      if (completion)
          completion(NO, errorMsg);
    };
    [familyManager createRoom:familyId name:roomName callback:cb];
}

+ (void)renameRoomWithId:(NSString *)roomId
                 newName:(NSString *)newName
                familyId:(NSString *)familyId
              completion:(SimpleCompletion)completion {
    if (!familyId || familyId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        return;
    }
    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }
    TXIoTVoidCallback *cb =
        [self voidCallbackWithCompletion:completion
                              successLog:[NSString stringWithFormat:@"Room renamed: %@", newName]
                             failureHint:NSLocalizedString(@"Failed to rename room", nil)];
    [familyManager setRoomName:familyId roomId:roomId name:newName callback:cb];
}

+ (void)deleteRoomWithId:(NSString *)roomId
                familyId:(NSString *)familyId
              completion:(SimpleCompletion)completion {
    if (!familyId || familyId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        return;
    }
    TXIoTFamilyManager *familyManager = [[TXIoTEngine getInstance] getFamilyManager];
    if (!familyManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }
    TXIoTVoidCallback *cb =
        [self voidCallbackWithCompletion:completion
                              successLog:[NSString stringWithFormat:@"Room deleted: %@", roomId]
                             failureHint:NSLocalizedString(@"Failed to delete room", nil)];
    [familyManager deleteRoom:familyId roomId:roomId callback:cb];
}

+ (void)bindDeviceToRoomWithFamilyId:(NSString *)familyId
                           productId:(NSString *)productId
                          deviceName:(NSString *)deviceName
                              roomId:(NSString *)roomId
                          completion:(SimpleCompletion)completion {
    if (!familyId || familyId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        return;
    }
    if (!productId || productId.length == 0 || !deviceName || deviceName.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Device info cannot be empty", nil));
        return;
    }
    if (!roomId || roomId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Room ID cannot be empty", nil));
        return;
    }
    TXIoTDeviceManager *deviceManager = [[TXIoTEngine getInstance] getDeviceManager];
    if (!deviceManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }
    TXIoTDeviceId *deviceId = [[TXIoTDeviceId alloc] init];
    deviceId.productId = productId;
    deviceId.deviceName = deviceName;

    TXIoTVoidCallback *cb = [self
        voidCallbackWithCompletion:completion
                        successLog:[NSString stringWithFormat:@"Device moved into room: %@/%@ -> %@",
                                                              productId, deviceName, roomId]
                       failureHint:NSLocalizedString(@"Failed to move device into room", nil)];
    [deviceManager addDeviceToRoom:deviceId familyId:familyId roomId:roomId callback:cb];
}

+ (void)unbindDeviceFromRoomWithFamilyId:(NSString *)familyId
                               productId:(NSString *)productId
                              deviceName:(NSString *)deviceName
                              completion:(SimpleCompletion)completion {
    if (!familyId || familyId.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        return;
    }
    if (!productId || productId.length == 0 || !deviceName || deviceName.length == 0) {
        if (completion)
            completion(NO, NSLocalizedString(@"Device info cannot be empty", nil));
        return;
    }
    TXIoTDeviceManager *deviceManager = [[TXIoTEngine getInstance] getDeviceManager];
    if (!deviceManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }
    TXIoTDeviceId *deviceId = [[TXIoTDeviceId alloc] init];
    deviceId.productId = productId;
    deviceId.deviceName = deviceName;

    TXIoTVoidCallback *cb =
        [self voidCallbackWithCompletion:completion
                              successLog:[NSString stringWithFormat:@"Device removed from room: %@/%@",
                                                                    productId, deviceName]
                             failureHint:NSLocalizedString(@"Failed to remove device from room", nil)];
    [deviceManager removeDeviceFromRoom:deviceId familyId:familyId callback:cb];
}

#pragma mark - 设备绑定

+ (void)bindDeviceWithSignature:(NSString *)signature
                     completion:(DeviceBindingCompletion)completion {
    if (!signature || signature.length == 0) {
        if (completion) {
            completion(NO, NSLocalizedString(@"Device signature cannot be empty", nil));
        }
        return;
    }

    NSString *familyId = _currentFamilyId;
    if (!familyId || familyId.length == 0) {
        if (completion) {
            completion(NO, NSLocalizedString(@"User not logged in or not in a family", nil));
        }
        return;
    }

    TXIoTDeviceManager *deviceManager = [[TXIoTEngine getInstance] getDeviceManager];
    if (!deviceManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTCallback<TXIoTDeviceInfo *> *cb = [[TXIoTCallback alloc] init];
    cb.onSuccess = ^(TXIoTDeviceInfo *_Nullable result) {
      NSLog(@"Device bound: %@", result.deviceId.deviceName ?: @"");
      if (completion)
          completion(YES, NSLocalizedString(@"Device added successfully!", nil));
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = [errorMessage copy] ?: NSLocalizedString(@"Device binding failed. Please try again.", nil);
      NSLog(@"Failed to bind device: %@", errorMsg);
      if (completion)
          completion(NO, errorMsg);
    };
    [deviceManager bindDevice:familyId deviceBindSignature:signature callback:cb];
}

#pragma mark - 设备列表

+ (void)getDeviceListWithFamilyId:(NSString *)familyId
                           roomId:(NSString *_Nullable)roomId
                       completion:(DeviceListCompletion)completion {

    if (!familyId || familyId.length == 0) {
        if (completion) {
            completion(NO, nil, NSLocalizedString(@"Family ID cannot be empty", nil));
        }
        return;
    }

    TXIoTDeviceManager *deviceManager = [[TXIoTEngine getInstance] getDeviceManager];
    if (!deviceManager) {
        if (completion)
            completion(NO, nil, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTCallback<TXIoTPageResult<TXIoTDeviceInfo *> *> *cb = [[TXIoTCallback alloc] init];
    cb.onSuccess = ^(TXIoTPageResult<TXIoTDeviceInfo *> *_Nullable result) {
      NSMutableArray<DeviceInfoItem *> *deviceList = [NSMutableArray array];
      for (TXIoTDeviceInfo *info in (result.dataList ?: @[])) {
          DeviceInfoItem *item = [[DeviceInfoItem alloc] init];
          item.deviceId = info.deviceId.deviceName ?: @"";
          item.productId = info.deviceId.productId ?: @"";
          item.deviceName = info.deviceId.deviceName ?: @"";
          item.aliasName = info.aliasName ?: info.deviceId.deviceName ?: @"";
          item.familyId = info.familyId ?: @"";
          item.roomId = info.roomId ?: @"";
          item.iconUrl = info.iconUrl ?: @"";
          item.deviceType = 0;
          item.createTime = info.createTime;
          item.updateTime = info.updateTime;
          item.isOnline = info.status ? info.status.isOnline : NO;
          [deviceList addObject:item];
      }
      NSLog(@"Got device list, %lu devices", (unsigned long)deviceList.count);
      if (completion)
          completion(YES, deviceList, nil);
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = errorMessage ?: NSLocalizedString(@"Failed to get device list", nil);
      NSLog(@"Failed to get device list: %@", errorMsg);
      if (completion)
          completion(NO, nil, errorMsg);
    };
    [deviceManager getDeviceList:familyId nextPageToken:nil callback:cb];
}

+ (void)getSharedDeviceListWithFamilyId:(NSString *)familyId
                             completion:(DeviceListCompletion)completion {

    if (!familyId || familyId.length == 0) {
        if (completion) {
            completion(NO, nil, NSLocalizedString(@"Family ID cannot be empty", nil));
        }
        return;
    }

    TXIoTDeviceManager *deviceManager = [[TXIoTEngine getInstance] getDeviceManager];
    if (!deviceManager) {
        if (completion)
            completion(NO, nil, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTCallback<TXIoTPageResult<TXIoTDeviceInfo *> *> *cb = [[TXIoTCallback alloc] init];
    cb.onSuccess = ^(TXIoTPageResult<TXIoTDeviceInfo *> *_Nullable result) {
      NSMutableArray<DeviceInfoItem *> *deviceList = [NSMutableArray array];
      for (TXIoTDeviceInfo *info in (result.dataList ?: @[])) {
          DeviceInfoItem *item = [[DeviceInfoItem alloc] init];
          item.deviceId = info.deviceId.deviceName ?: @"";
          item.productId = info.deviceId.productId ?: @"";
          item.deviceName = info.deviceId.deviceName ?: @"";
          item.aliasName = info.aliasName ?: info.deviceId.deviceName ?: @"";
          item.familyId = info.familyId ?: @"";
          item.roomId = info.roomId ?: @"";
          item.iconUrl = info.iconUrl ?: @"";
          item.deviceType = 0;
          item.createTime = info.createTime;
          item.updateTime = info.updateTime;
          item.isOnline = info.status ? info.status.isOnline : NO;
          [deviceList addObject:item];
      }
      NSLog(@"Got shared device list, %lu devices", (unsigned long)deviceList.count);
      if (completion)
          completion(YES, deviceList, nil);
    };
    cb.onError = ^(TXIoTErrorCode errorCode, NSString *_Nullable errorMessage) {
      NSString *errorMsg = errorMessage ?: NSLocalizedString(@"Failed to get shared device list", nil);
      NSLog(@"Failed to get shared device list: %@", errorMsg);
      if (completion)
          completion(NO, nil, errorMsg);
    };
    // 新接口的「分享给我的设备列表」不再以 familyId 为参数
    [deviceManager getDeviceListSharedWithMe:nil callback:cb];
}

#pragma mark - 设备解绑

+ (void)unbindDeviceWithFamilyId:(NSString *)familyId
                       productId:(NSString *)productId
                      deviceName:(NSString *)deviceName
                      completion:(UnbindDeviceCompletion)completion {

    if (!familyId || familyId.length == 0) {
        if (completion) {
            completion(NO, NSLocalizedString(@"Family ID cannot be empty", nil));
        }
        return;
    }

    if (!productId || productId.length == 0) {
        if (completion) {
            completion(NO, NSLocalizedString(@"Product ID cannot be empty", nil));
        }
        return;
    }

    if (!deviceName || deviceName.length == 0) {
        if (completion) {
            completion(NO, NSLocalizedString(@"Device name cannot be empty", nil));
        }
        return;
    }

    TXIoTDeviceManager *deviceManager = [[TXIoTEngine getInstance] getDeviceManager];
    if (!deviceManager) {
        if (completion)
            completion(NO, NSLocalizedString(@"Not logged in", nil));
        return;
    }

    TXIoTDeviceId *deviceId = [[TXIoTDeviceId alloc] init];
    deviceId.productId = productId;
    deviceId.deviceName = deviceName;

    TXIoTVoidCallback *cb =
        [self voidCallbackWithCompletion:completion
                              successLog:[NSString stringWithFormat:@"Device unbound: %@/%@",
                                                                    productId, deviceName]
                             failureHint:NSLocalizedString(@"Failed to unbind device", nil)];
    [deviceManager unbindDevice:familyId deviceId:deviceId callback:cb];
}

@end
