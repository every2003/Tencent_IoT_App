# TWeCall 设备音视频通话接入指南

TWeCall 是腾讯云 IoT Explorer 提供的设备↔微信音视频通话能力：智能硬件（门禁、摄像头、儿童手表、校园话机等）可以直接呼叫用户手机微信，用户也可以从小程序内呼叫设备。本文说明宿主小程序如何基于 tx-iot-sdk 插件完成 TWeCall 的完整接入：**增加硬件（绑定设备）→ 授权设备（VoIP 强提醒）→ 发起 / 接听通话**。

## 1. 整体链路

TWeCall 涉及三方角色：

| 角色 | 平台 | 职责 |
| --- | --- | --- |
| 微信硬件平台 | 微信公众平台「设备接入」 | 申请硬件型号（model_id）、设备 VoIP 授权体系、微信侧通话链路 |
| 腾讯云 IoT Explorer | 腾讯云控制台 | 产品 / 设备管理、TWeCall License、设备绑定与授权状态存储 |
| 宿主小程序 | 接入 tx-iot-sdk 插件 | 设备绑定、拉起授权、发起 / 接听通话的 UI 与逻辑 |

典型时序（用户视角）：

```
扫码/配网拿到绑定签名
        │
        ▼
小程序 bindDevice(familyId, signature)   ──── 设备进入家庭列表
        │
        ▼
授权三步（见 4.1 节）：
  requestVoIPSnTicket ─► wx.requestDeviceVoIP（宿主调用，拉起授权弹窗）─► 用户同意授权 ─► registerVoIPNotificationForDevice
        │
        ▼
设备侧发起呼叫 ──► 音视频通话
```

## 2. 前置条件

1. **企业主体小程序**：微信 VoIP 设备通话能力仅对企业、媒体、政府及其他组织主体开放，个人主体不可用。
2. **微信硬件平台开通**：在微信公众平台「设备接入」中申请硬件型号，获得 **model_id**. 同时申请设备的`消息能力`和
`小程序音视频能力`。
3. **基础库版本**：`wx.requestDeviceVoIP` 需基础库 **≥ 2.27.3**；设备组（批量授权）需 **≥ 2.30.4**；授权状态查询 `wx.getDeviceVoIPList` 需 **≥ 2.30.3**，微信客户端 **≥ 8.0.30**。**注意：`wx.requestDeviceVoIP` / `wx.getDeviceVoIPList` 在开发者工具模拟器上不可用（API 不存在），设备授权相关流程必须在真机上验证。**
4. **腾讯云 IoT Explorer**：已创建产品与设备；已购买并激活 TWeCall License（云 API `ActivateTWeCallLicense`）。
5. **类目与接口权限**：宿主小程序类目须覆盖音视频通话能力，并开通 live-player / live-pusher 组件权限（见主文档「接入前置条件」）。

## 3. 小程序中增加硬件（绑定设备）

用户使用 TWeCall 前，须先把硬件绑定到自己的家庭。绑定凭证是**设备绑定签名**（deviceBindSignature），通常由设备配网页面或设备二维码给出，格式为 JSON 字符串：

```json
{ "ProductId": "xxx", "DeviceName": "xxx", "signature": "xxx" }
```

（兼容小写键名 `pid` / `deviceName` / `signature`。）

### 3.1 绑定到家庭

```js
const plugin = requirePlugin('tx-iot-sdk');
const engine = plugin.TXIoTEngine.getInstance();
const dm = engine.getDeviceManager();

// 1. 选择要绑定的家庭（首次接入可先 getFamilyList / createFamily）
const families = await dm.getFamilyList();
const familyId = families[0].familyId;

// 2. 用绑定签名绑定设备（signature 为配网 / 扫码得到的完整签名串）
const info = await dm.bindDevice(familyId, signature);
// info: { productId, deviceName, aliasName, status, ... }
```

绑定成功后设备出现在 `getDeviceList(familyId)` 结果中。可继续调用 `addDeviceToRoom({ productId, deviceName }, familyId, roomId)` 把设备归入房间。

## 4. 授权设备（用户授权 VoIP 通话提醒）

设备若要**向用户发起通话**，需要用户在手机微信端先对设备授权。授权后设备呼叫会以微信「服务通知」强提醒触达用户。官方说明见[用户授权设备](https://developers.weixin.qq.com/miniprogram/dev/framework/device/voip/auth.html)。

> **插件接入须知**：`wx.requestDeviceVoIP` 在小程序插件上下文中不可用（官方 API 标注「小程序插件：不支持」，[文档](https://developers.weixin.qq.com/miniprogram/dev/api/open-api/device-voip/wx.requestDeviceVoIP.html)）。因此插件模式下的授权流程拆为三步：SDK 获取票据（`requestVoIPSnTicket`）→ **宿主自行调用 `wx.requestDeviceVoIP`** → SDK 完成登记（`registerVoIPNotificationForDevice`）。内联 SDK（小程序直接引入，非插件）可跳过第一步拆分，但推荐统一走三步流程。

### 4.1 授权三步流程

**第 1 步：获取授权票据（SDK）**

```js
const dm = engine.getDeviceManager();

// modelId：微信公众平台「设备接入」分配的 model_id
const modelId = '';
// appId：当前宿主小程序 AppID
const appId = '';

const ticket = await dm.requestVoIPSnTicket(
  { productId, deviceName },  // deviceId
  modelId,
  appId,
);
// ticket: { sn, snTicket }，snTicket 5 分钟内有效
```

**第 2 步：拉起微信授权弹窗（宿主，必须在小程序上下文调用）**

```js
wx.requestDeviceVoIP({
  sn: ticket.sn,             // 需与设备注册时一致
  snTicket: ticket.snTicket, // 第 1 步获取，5 分钟内有效
  modelId,
  deviceName,                // 授权弹窗中显示，不超过 13 字符
  success(res) { console.log('requestDeviceVoIP success:', res); },
  fail(err) {
    // errCode 10001 = 已授权，视为成功
    console.error('requestDeviceVoIP fail:', err);
  },
});
```

注意：此 API 仅真机可用（开发者工具模拟器不支持），需基础库 ≥ 2.27.3；用户拒绝过授权后再次调用**不再弹窗**，须引导用户到小程序设置页手动开启。

**第 3 步：完成授权登记（SDK）**

```js
// wxOpenId：当前用户微信 OpenID
const wxOpenId = '';

await dm.registerVoIPNotificationForDevice(
  { productId, deviceName },  // deviceId
  modelId,
  appId,
  wxOpenId,
);
```

内部执行 `AppInsertWechatAppOpenID` → `AppUpdateDeviceTWeCallAuthorizeStatus`，将用户 OpenID 与设备关联、登记授权状态。三步全部完成后，设备即可向该用户发起微信 VoIP 通话。

### 4.2 查询授权状态

**方式一：云端查询（设备维度）**——查询某设备已被哪些用户授权，适合刷新设备列表时回显开关状态：

```js
const list = await dm.getAuthorizedVoIPUserList({ productId, deviceName });
// list: OpenID 字符串数组
const registered = list.indexOf(wxOpenId) >= 0;
```

**方式二：微信侧查询（用户维度）**——查询当前用户授权过 / 拒绝过哪些设备，适合在发起通话前自检（基础库 ≥ 2.30.3）：

```js
wx.getDeviceVoIPList({
  success(res) {
    // res.list: [{ sn, model_id, status }]，status: 0 未授权 / 1 已授权
  },
});
```

### 4.3 解除授权

```js
// 云侧重置状态（Status=0），之后不再收到该设备的通话强提醒
await dm.unregisterVoIPNotificationForDevice(
  { productId, deviceName }, modelId, appId, wxOpenId,
);
```

注意：云侧解除**不会**删除微信侧授权记录。用户须在小程序「设置 → 语音、视频通话提醒」中手动管理 / 取消授权。

### 4.4 授权失效的处理

以下情况会导致授权失效，接入方需在业务中兜底：

| 场景 | 表现 | 处理方式 |
| --- | --- | --- |
| 用户删除小程序 | 授权记录被清空 | 可直接再次调用 `registerVoIPNotificationForDevice` 重新拉起弹窗 |
| 用户在设置页取消授权 | 再次调用 `requestDeviceVoIP` **不再弹窗** | 引导用户进入小程序设置页手动开启授权开关 |
| 用户拒绝过授权 | 同上，不弹窗 | 同上 |


## 5. 发起与接听通话

### 5.1 小程序呼叫设备

授权完成后（或无需授权的微信→设备方向），使用通话会话：

```js
const session = engine.getCallSession();
await session.callDevice({ productId, deviceName }, callType); // callType: 0 音频 / 1 视频
```

完整通话 API（挂断、麦克风、摄像头、听筒切换、事件回调）见主文档「呼叫设备（音视频通话）」与 API 参考的 `TXIoTCallSession` 一节。

### 5.2 设备呼叫用户微信（接听侧）

设备侧通过微信硬件 VoIP 能力发起呼叫后，用户收到微信「服务通知」强提醒，点击即进入通话：

- 接听 UI 由 **wmpf-voip 插件**（provider `wxf830863afde621eb`）的通话页承载，宿主小程序需在 `app.json` 中声明并初始化：

```json
{ "plugins": { "wmpf-voip": { "version": "latest", "provider": "wxf830863afde621eb" } } }
```

```js
const wmpfVoip = requirePlugin('wmpf-voip').default;
wmpfVoip.setUIConfig({ /* 接听页 UI 定制 */ });
wmpfVoip.onVoipEvent((event) => { console.log(event.eventName, event); });
```

- 该方向依赖第 4 节的用户授权：**未授权用户收不到强提醒通话**。

## 6. 常见问题

**Q：`registerVoIPNotificationForDevice` 报「modelId 不能为空」？**
modelId 来自微信公众平台「设备接入」，与 IoT Explorer 的 productId 是两套体系，不要混用。

**Q：授权弹窗不出现？**
依次确认：① 基础库 ≥ 2.27.3；② 用户此前未拒绝过授权（拒绝后不再弹窗，须引导去设置页开启）；③ model_id 已在微信硬件平台审核通过；④ snTicket 有效（由后台 `APPGetWechatDeviceTicket` 实时获取）。

**Q：设备呼叫用户，用户没有收到提醒？**
确认该用户 OpenID 在 `getAuthorizedVoIPUserList` 返回列表中；确认 TWeCall License 已激活且未过期；确认用户未在设置页取消授权。

**Q：绑定签名从哪里来？**
由设备配网流程（SoftAP / SmartConfig / 蓝牙配网）或设备机身二维码提供，格式见 3.1 节。签名由设备侧生成，IoT Explorer 校验，小程序只做透传。

**Q：他人分享给我的设备能授权 VoIP 吗？**
可以。`getDeviceListSharedWithMe` 返回的设备与自有设备走完全相同的授权与通话流程。

## 7. 参考链接

- [用户授权设备（官方）](https://developers.weixin.qq.com/miniprogram/dev/framework/device/voip/auth.html)
- [wx.requestDeviceVoIP（官方 API）](https://developers.weixin.qq.com/miniprogram/dev/api/open-api/device-voip/wx.requestDeviceVoIP.html)
- [wx.getDeviceVoIPList（官方 API）](https://developers.weixin.qq.com/miniprogram/dev/api/open-api/device-voip/wx.getDeviceVoIPList.html)
- [获取设备票据 snTicket（官方服务端 API）](https://developers.weixin.qq.com/miniprogram/dev/server/API/hardware-device/api_getsnticket)
- [设备组（官方）](https://developers.weixin.qq.com/miniprogram/dev/framework/device/device-group)
- [设备呼叫微信（官方）](https://developers.weixin.qq.com/miniprogram/dev/framework/device/voip/call-wechat.html)
