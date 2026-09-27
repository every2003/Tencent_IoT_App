# tx-iot-sdk 腾讯云 IoT 音视频小程序插件

tx-iot-sdk 是接入腾讯云 IoT Explorer 平台的音视频设备小程序插件。核心引擎基于 WebAssembly 实现，为接入方小程序提供物联网设备的登录认证、家庭与设备管理、实时音视频监控（观看 / 对讲 / PTZ / 截图 / 录像）、设备音视频通话、设备分享、VoIP 微信强提醒等完整能力。

## 功能特性

- **登录认证**：基于 AppKey / AppSecret 的 HMAC-SHA1 用户签名登录，支持登录态持久化与签名过期回调
- **家庭管理**：家庭 / 房间的增删改查、家庭成员邀请与移除
- **设备管理**：设备绑定 / 解绑、别名修改、房间归属、设备列表分页
- **设备分享**：生成分享 token、绑定分享给我的设备、取消分享、分享用户管理
- **设备控制**：下发控制指令（`sendCommand`）、查询设备属性（`getProperties`）
- **实时监控**：多通道实时画面（`iot-player`）、对讲（`iot-pusher`）、云台 PTZ 控制、通道截图、本地录像、码流切换（SD / HD）、静音控制
- **设备通话**：呼叫设备并进行音视频通话（主叫侧），含麦克风 / 摄像头 / 扬声器听筒切换
- **VoIP 微信强提醒**：注册 / 解除设备 VoIP 授权、查询已授权用户，配合微信 VoIP 通话插件实现设备呼叫微信用户（被叫侧）
- **消息推送**：设备状态变化等推送消息实时回调

## 接入前置条件

1. **主体要求**：宿主小程序主体须为企业、媒体、政府或其他组织类型（个人主体无法使用 live-pusher / live-player 组件）。
2. **组件权限**：宿主小程序须通过相关服务类目审核（智能家居 / 摄像头场景一般对应「IT科技 - 多方通信 / 音视频设备」类目），并在小程序管理后台「开发 → 接口设置」中开通「实时播放音视频流」（live-player）与「实时录制音视频流」（live-pusher）组件权限。未开通时监控画面与对讲功能不可用。
3. **基础库版本**：≥ 2.19.0（依赖 WXWebAssembly 能力）。
4. **平台侧资源**：需在腾讯云 IoT Explorer 控制台开通产品并获取 AppKey / AppSecret；设备侧需完成 TRTC 音视频链路接入。
5. **网络域名**：插件网络请求走插件自身配置的服务器域名（由插件方在插件管理后台配置），宿主小程序无需为插件请求单独配置 request 合法域名。

## 快速开始

### 1. 声明插件

在宿主小程序 `app.json` 中声明：

```json
{
  "plugins": {
    "tx-iot-sdk": {
      "version": "1.0.5",
      "provider": "wx5201edc27c631209"
    }
  }
}
```

`version` 可填写具体版本号，也可填 `latest` 自动使用最新版本。

### 2. 初始化并登录

```js
// utils/iot.js —— 插件接入封装示例
const plugin = requirePlugin('tx-iot-sdk');
const { TXIoTEngine, TXIoTUserSignature } = plugin;

// 引擎单例：内部自动完成 wasm 加载，多次调用返回同一实例
function getEngine() {
  return TXIoTEngine.getInstance();
}

// 登录签名算法（与 App 端一致）：
//   1. 拼接参数串：['AppKey=xx', 'Nonce=xx', 'OpenID=xx', 'RequestId=xx', 'Timestamp=xx']
//      按 key 字典序排序后用 '&' 连接
//   2. signature = Base64( HMAC-SHA1(appSecret, 拼接串) )
// 建议在生产环境将签名计算放在业务后端完成。
async function login(appKey, appSecret, userId) {
  const engine = await getEngine();

  const timestamp = Math.floor(Date.now() / 1000);
  const nonce = Math.floor(Math.random() * 0x7fffffff) + 1;
  const requestId = `${timestamp}-${nonce}`;
  const sortedQuery = [
    `AppKey=${appKey}`,
    `Nonce=${nonce}`,
    `OpenID=${userId}`,
    `RequestId=${requestId}`,
    `Timestamp=${timestamp}`,
  ].sort().join('&');

  // hmacSha1Base64 为接入方自行实现的 HMAC-SHA1（Base64 输出）
  const signature = hmacSha1Base64(appSecret, sortedQuery);

  const sig = new TXIoTUserSignature();
  sig.requestId = requestId;
  sig.timestamp = timestamp;
  sig.nonce = nonce;
  sig.signature = signature;

  return new Promise((resolve, reject) => {
    const listener = {
      onLoginSuccess() {
        engine.removeListener(listener);
        resolve();
      },
      onLoginFailure(errCode, errMsg) {
        engine.removeListener(listener);
        reject(new Error(`登录失败 (${errCode}): ${errMsg}`));
      },
    };
    engine.addListener(listener);
    engine.login(appKey, userId, sig);
  });
}
```

### 3. 监听全局事件

```js
const engine = await TXIoTEngine.getInstance();

engine.addListener({
  onLoginSuccess() { /* 登录成功 */ },
  onLoginFailure(errCode, errMsg) { /* 登录失败 */ },
  onLogout() { /* 登出 */ },
  onUserSignatureExpired() { /* 签名过期，需重新签名登录 */ },
  onReceivePushMessage(msg) {
    // 设备推送：msg.type / msg.subType 见 TXIoTPushMessageType / TXIoTPushMessageSubType 枚举
    // msg.deviceId 为 { productId, deviceName } 或 null
  },
});
```

### 4. 获取设备列表

```js
const deviceManager = engine.getDeviceManager();

const page = await deviceManager.getDeviceList(familyId);
page.list.forEach((device) => {
  console.log(device.deviceId.productId, device.deviceId.deviceName,
    device.aliasName, device.status && device.status.isOnline);
});
```

### 5. 实时监控（观看 + 对讲）

页面 `index.json`：

```json
{
  "usingComponents": {
    "iot-player": "plugin://tx-iot-sdk/iot-player",
    "iot-pusher": "plugin://tx-iot-sdk/iot-pusher"
  }
}
```

页面 `index.wxml`：

```xml
<iot-player component-id="iot-player-1" style="width:100%;height:420rpx;" />
<iot-pusher style="width:200rpx;height:280rpx;" />
```

页面 `index.js`：

```js
const monitor = engine.getMonitorSession();

// 监听会话事件
monitor.addListener({
  onSessionEstablished() { /* 会话建立成功 */ },
  onSessionReconnecting() { /* 断线重连中 */ },
  onSessionRecovery() { /* 重连成功 */ },
  onRenderFirstFrame(channelId) { /* 指定通道首帧已渲染 */ },
  onRemoteStreamAvailable(channelId, available) { /* 远端流可用性变化 */ },
  onSnapshotComplete(channelId, filePath) { /* 截图完成，filePath 为临时文件路径 */ },
  onError(channelId, code, msg) { /* 会话错误 */ },
});

// 1. 绑定通道与播放组件（component-id 需与 wxml 中一致）
monitor.setIoTPlayer(1, 'iot-player-1');
// 2. 请求远端画面（streamType 见 StreamType 枚举，如 SD / HD）
monitor.startRemoteView(1, plugin.StreamType.HD);
// 3. 启动监控会话（deviceId 为 { productId, deviceName }）
monitor.startSession({ productId: 'PRODUCT_ID', deviceName: 'DEVICE_NAME' });

// 对讲：开启本地麦克风（音频经 iot-pusher 上行）
monitor.startLocalAudio();
// 云台控制：command 见 PTZCommand 枚举（UP/DOWN/LEFT/RIGHT），speed 取值 1-10
monitor.sendPTZCommand(1, plugin.PTZCommand.UP, 5);
// 截图
monitor.takeSnapshot(1);

// 退出页面时停止会话
monitor.stopSession();
```

### 6. 呼叫设备（音视频通话）

```js
const callSession = engine.getCallSession();
const callUser = new plugin.CallUser({ productId: 'PRODUCT_ID', deviceName: 'DEVICE_NAME' });

callSession.addListener({
  onCallBegin(mediaType) { /* 通话接通，mediaType: 0 音频 / 1 视频 */ },
  onCallEnd(mediaType, reason) { /* 通话结束，reason 见 CallEndReason 枚举 */ },
  onCallRejected(callUser) { /* 对端拒接 */ },
  onCallNoResponse(callUser) { /* 对端无应答 */ },
  onCallLineBusy(callUser) { /* 对端占线 */ },
  onCallUserVideoAvailable(callUser, available) { /* 对端视频流可用性变化 */ },
  onError(code, msg) { /* 通话错误 */ },
});

// 绑定对端画面到 iot-player 组件
callSession.setIoTPlayer(callUser, 'iot-player-1');
// 发起呼叫：callType 0 音频 / 1 视频
callSession.callDevice({ productId: 'PRODUCT_ID', deviceName: 'DEVICE_NAME' }, 1);
// 接通后渲染对端画面、打开本地麦克风
callSession.startRemoteView(callUser);
callSession.openMicrophone();

// 挂断
callSession.hangup();
```

## 自定义组件

### iot-player（远端画面播放）

内部封装 live-player（RTC 模式），用于渲染设备侧音视频流。支持多实例（多通道）。

| 属性 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| component-id | String | '' | 组件标识。须与 `monitorSession.setIoTPlayer(channelId, componentId)` 或 `callSession.setIoTPlayer(callUser, componentId)` 传入的值一致，SDK 据此将设备流路由到对应组件 |

组件样式由使用方通过外层容器控制（组件内 live-player 铺满组件区域）。播放地址、静音、扬声器 / 听筒切换等由 SDK 通过监控 / 通话会话接口控制，无需使用方干预。

### iot-pusher（本地上行推流）

内部封装 live-pusher（RTC 模式），用于对讲与通话中的本地上行（麦克风 / 摄像头）。**全局单实例**（SDK 内部媒体桥仅支持一个推流组件），同一页面请勿放置多个。

组件无对外属性，随会话的 `startLocalAudio()` / `startLocalVideo()` 等调用自动开启对应能力。通话场景挂断后请随页面销毁组件。

## API 参考

### TXIoTEngine（引擎单例）

通过 `requirePlugin('tx-iot-sdk').TXIoTEngine.getInstance()` 获取（异步），随后可同步调用以下接口：

| 接口 | 说明 |
| --- | --- |
| addListener(listener) / removeListener(listener) | 注册 / 移除全局事件监听（见「监听全局事件」） |
| login(appKey, userId, userSignature) | 登录，签名算法见快速开始 |
| logout() | 登出 |
| getLoginUserInfo() | 已登录用户信息（`{ userId, nickName, avatarUrl, role, deviceBindTime }`），未登录返回 null |
| getFamilyManager() | 家庭管理器 |
| getDeviceManager() | 设备管理器 |
| getMonitorSession() | 监控会话 |
| getCallSession() | 通话会话 |

### TXIoTFamilyManager（家庭管理）

所有接口返回 Promise，`options` 可指定 `{ timeout, raw }`。

| 接口 | 说明 |
| --- | --- |
| createFamily(name) | 创建家庭 |
| deleteFamily(familyId) | 删除家庭 |
| getFamilyList() | 家庭列表 `[{ familyId, name }]` |
| updateFamilyInfo({ familyId, name }) | 修改家庭名称 |
| createRoom(familyId, name) / deleteRoom(familyId, roomId) / setRoomName(familyId, roomId, name) / getRoomList(familyId) | 房间管理 |
| createFamilyInviteToken(familyId) | 生成家庭成员邀请 token |
| joinFamilyAsMember(inviteToken) | 通过邀请 token 加入家庭 |
| removeMemberFromFamily(familyId, userId) | 移除家庭成员 |
| getMemberList(familyId) | 成员列表 `[{ userId, nickName, role }]` |

### TXIoTDeviceManager（设备管理）

所有接口返回 Promise。`deviceId` 均为 `{ productId, deviceName }` 对象。

| 接口 | 说明 |
| --- | --- |
| bindDevice(familyId, deviceBindSignature) | 绑定设备（签名为配网 / 扫码获得） |
| unbindDevice(familyId, deviceId) | 解绑设备 |
| getDeviceList(familyId, nextPageToken?) | 当前家庭设备列表（分页，返回 `{ list, nextPageToken }`） |
| getDeviceListSharedWithMe(nextPageToken?) | 他人分享给我的设备列表 |
| modifyAliasName(deviceId, aliasName) | 修改设备别名 |
| addDeviceToRoom(deviceId, familyId, roomId) / removeDeviceFromRoom(deviceId, familyId, roomId) | 设备房间归属 |
| createDeviceSharingToken(familyId, deviceId) | 生成设备分享 token |
| bindDeviceSharedWithMe(deviceId, shareToken) | 绑定他人分享的设备 |
| unbindDeviceSharedWithMe(deviceId) | 取消绑定他人分享的设备 |
| getDeviceSharedUsers(deviceId) | 设备已分享用户列表 |
| removeDeviceSharedUser(deviceId, userId) | 移除设备分享用户 |
| sendCommand(deviceId, jsonData) | 下发设备控制指令（对象或 JSON 字符串） |
| getProperties(deviceId) | 查询设备属性 |
| requestVoIPSnTicket(deviceId, modelId, appId) | 获取设备 VoIP 授权票据（`APPGetWechatDeviceTicket`），返回 `{ sn, snTicket }` 供宿主自行调用 `wx.requestDeviceVoIP` 拉起微信原生授权弹窗。**插件模式下必须走此接口 + 宿主自行调用 `wx.requestDeviceVoIP`**（该 API 在插件上下文中不可用，官方限制） |
| registerVoIPNotificationForDevice(deviceId, modelId, appId, wxOpenId) | 登记设备 VoIP 授权（微信强提醒）：将用户 OpenID 与设备关联并更新授权状态。**前置条件**：宿主已通过 `requestVoIPSnTicket` + `wx.requestDeviceVoIP` 完成微信侧授权。`modelId` 为微信公众平台「设备接入」分配的 model_id，`appId` 为宿主小程序 AppID，`wxOpenId` 为当前用户 OpenID |
| unregisterVoIPNotificationForDevice(deviceId, modelId, appId, wxOpenId) | 解除设备 VoIP 授权 |
| getAuthorizedVoIPUserList(deviceId) | 查询设备已授权 VoIP 用户 OpenID 列表 |

> 设备绑定（增加硬件）、VoIP 授权全流程（含授权失效处理、批量授权设备组）、设备↔微信双向通话的完整接入说明，见 [TWeCall 设备音视频通话接入指南](./twecall.md)。

### IotMonitorSession（监控会话）

| 接口 | 说明 |
| --- | --- |
| addListener(listener) / removeListener(listener) | 会话事件监听（onSessionEstablished / onSessionReconnecting / onSessionRecovery / onRenderFirstFrame / onRemoteStreamAvailable / onSnapshotComplete / onError 等） |
| setIoTPlayer(channelId, componentId) | 绑定通道与 iot-player 组件 |
| startSession(deviceId) / stopSession() | 启动 / 停止监控会话 |
| startRemoteView(channelId, streamType) / stopRemoteView(channelId) | 开始 / 停止指定通道远端画面 |
| switchRemoteStream(channelId, streamType) | 切换通道码流（SD / HD） |
| muteRemoteAudio(channelId, mute) / muteAllRemoteAudio(mute) | 通道 / 全局静音 |
| startLocalAudio() / stopLocalAudio() / muteLocalAudio(mute) | 对讲（本地上行音频） |
| startLocalVideo(videoEncoderParams?) / stopLocalVideo() | 本地上行视频 |
| sendPTZCommand(channelId, command, speed?) | 云台控制，command 见 PTZCommand 枚举 |
| takeSnapshot(channelId) | 通道截图，结果经 onSnapshotComplete 回调 |
| startLocalRecording(channelId, params?) / stopLocalRecording(channelId) | 本地录像 |

### IotCallSession（通话会话）

| 接口 | 说明 |
| --- | --- |
| addListener(listener) / removeListener(listener) | 通话事件监听（onCallBegin / onCallEnd / onCallRejected / onCallNoResponse / onCallLineBusy / onCallUserAudioAvailable / onCallUserVideoAvailable / onError） |
| callDevice(deviceId, callType) | 呼叫设备，callType 0 音频 / 1 视频 |
| hangup() | 挂断 |
| setIoTPlayer(callUser, componentId) | 绑定对端画面组件 |
| startRemoteView(callUser) / stopRemoteView(callUser) | 渲染 / 停止对端画面 |
| openMicrophone() / closeMicrophone() | 打开 / 关闭麦克风 |
| openCamera(camera) / closeCamera() / switchCamera(camera) | 摄像头控制，camera 见 Camera 枚举（前 / 后置） |
| selectAudioPlaybackDevice(device) | 扬声器 / 听筒切换，device 见 AudioPlaybackDevice 枚举 |

### 枚举一览

`requirePlugin('tx-iot-sdk')` 导出以下枚举对象（键值映射），常用键举例：

| 枚举 | 用途 |
| --- | --- |
| StreamType | 码流类型（监控画面 SD / HD 切换） |
| PTZCommand | 云台方向（UP / DOWN / LEFT / RIGHT） |
| VideoResolution | 视频分辨率 |
| PlayState | 播放状态 |
| CallMediaType | 通话媒体类型（音频 / 视频） |
| CallEndReason | 通话结束原因 |
| Camera | 摄像头（前置 / 后置） |
| AudioPlaybackDevice | 声音播放设备（扬声器 / 听筒） |
| NetworkQuality | 网络质量 |
| TXIoTPushMessageType / TXIoTPushMessageSubType | 推送消息类型 / 子类型 |
| TXIoTErrorCode | 错误码 |

## 常见问题

**Q：画面区域黑屏 / live-player 不渲染？**
按「接入前置条件」确认宿主小程序已开通 live-player 组件权限（企业主体 + 类目审核 + 接口设置）；确认 `setIoTPlayer` 传入的 componentId 与 wxml 中 `component-id` 一致。

**Q：登录回调不触发？**
若 SDK 内部已持有有效登录态，`login` 不会再回调 onLoginSuccess，可通过 `getLoginUserInfo()` 判断已登录后直接使用。签名过期会通过 `onUserSignatureExpired` 回调，需重新签名登录。

**Q：对讲没有声音？**
确认页面放置了 iot-pusher 组件（单实例），且已调用 `startLocalAudio()`；首次使用时用户须授权麦克风（scope.record）。

**Q：监控会话与通话会话能同时使用吗？**
两者共享底层 TRTC pipeline。进入通话前建议先 `stopSession()` 停止监控，通话结束后再重新建立监控会话。

**Q：如何排查接入问题？**
插件加载时会打印 `[tx-iot-sdk] plugin loaded, version = x.y.z`，可据此确认实际生效版本。各组件与接口在关键路径均有 `[iot-player]` / `[iot-pusher]` / `[iot-http]` 前缀日志，可在真机 vConsole 中查看。

## 更多资源

- [TWeCall 设备音视频通话接入指南](./twecall.md)（设备绑定、VoIP 授权、双向通话）
- [小程序插件开发文档](https://developers.weixin.qq.com/miniprogram/dev/framework/plugin/development.html)
- [使用插件的宿主小程序说明](https://developers.weixin.qq.com/miniprogram/dev/framework/plugin/using.html)
- [live-player 组件说明](https://developers.weixin.qq.com/miniprogram/dev/component/live-player.html)
- [live-pusher 组件说明](https://developers.weixin.qq.com/miniprogram/dev/component/live-pusher.html)
