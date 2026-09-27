// IoT Engine 单例封装（demo 侧）
//
// 说明：此文件不随插件发布，属于 demo 业务代码。
// 插件（tx-iot-sdk）只导出原始 SDK 类（TXIoTEngine / 各 Manager / Session / 枚举）。
// demo 在这里基于原始类做一层 Promise 风格的便捷封装，供页面调用。

import { hmacSha1Base64 } from './hmacSha1';
import * as logger from './logger';

// 通过 requirePlugin 拿到插件导出的原始 SDK 类。
// 注意：必须【懒加载】——不能在模块顶层直接 requirePlugin()。
// 因为本模块会被 app.ts 在启动早期 import，此时插件可能尚未注册完成，
// 顶层 requirePlugin 会抛 "Plugin xxx/0 is not defined"。改用 ensureSdk() 在
// 实际调用（initIoTEngine / login）时再取，那时插件必然已就绪。
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let _TXIoTEngine: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let _TXIoTUserSignature: any = null;
function ensureSdk(): void {
  if (_TXIoTEngine) return;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const raw = requirePlugin('tx-iot-sdk') as any;
  // 插件入口用 export default {...}，requirePlugin 返回的对象里能力在 .default 下；
  // 兼容两种形态，优先解包 default。
  const sdk = (raw && raw.default) ? raw.default : raw;
  _TXIoTEngine = sdk.TXIoTEngine;
  _TXIoTUserSignature = sdk.TXIoTUserSignature;
  if (!_TXIoTEngine) {
    throw new Error('插件 tx-iot-sdk 未导出 TXIoTEngine，请检查插件版本/是否已注册');
  }
}
// TXIoTEngine 由插件提供，这里仅作为类型占位
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type TXIoTEngine = any;

let initPromise: Promise<TXIoTEngine> | null = null;
// 缓存已 resolve 的 engine 实例，供 _getEngineSync() 同步访问
let _engineInstance: TXIoTEngine | null = null;

/**
 * 异步获取引擎实例（内部自动完成 wasm 加载）。
 * 多次调用返回同一个实例，仅首次会真正加载 wasm。
 */
export async function initIoTEngine(): Promise<TXIoTEngine> {
  if (initPromise) return initPromise;
  ensureSdk();
  const p: Promise<TXIoTEngine> = (_TXIoTEngine as any).getInstance().catch((err: unknown) => {
    initPromise = null;
    _engineInstance = null;
    throw err;
  });
  initPromise = p;
  // 监听 Promise 完成，缓存实例
  p.then((engine) => {
    _engineInstance = engine;
  }).catch(() => {
    _engineInstance = null;
  });
  return p;
}

// 与 app 端 SignParams 对齐
interface SignParams {
  OpenID: string;
  Timestamp: number;
  Nonce: number;
  AppKey: string;
  RequestId: string;
}

/**
 * 拼接签名串：五个字段按 key 字典序拼成 query string。
 * 与 app 端 createSortedQueryString 逻辑一致。
 */
function buildSortedQueryString(p: SignParams): string {
  const items = [
    `AppKey=${p.AppKey}`,
    `Nonce=${p.Nonce}`,
    `OpenID=${p.OpenID}`,
    `RequestId=${p.RequestId}`,
    `Timestamp=${p.Timestamp}`,
  ];
  return items.sort().join('&');
}

export interface LoginOptions {
  appKey: string;
  appSecret: string;
  userId: string; // OpenID
}

/**
 * Promise 风格的登录：
 * 1. 用 AppKey/AppSecret/UserId 计算 HMAC-SHA1 签名
 * 2. 调 wasm 端 engine.login(appKey, userId, userSignature)
 * 3. 等 onLoginSuccess / onLoginFailure 转 Promise
 */
export function login(opts: LoginOptions): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    if (!opts.appKey || !opts.appSecret || !opts.userId) {
      reject(new Error('appKey / appSecret / userId 不能为空'));
      return;
    }

    initIoTEngine().then(async (engine) => {

      // 0. 短路：如果 SDK 内部 storage 里已经有 token，原版 iot_engine.cc::Login
      //    直接 return 不会回调 OnLoginSuccess。我们这里手动 resolve，
      //    让上层 demo 拿到 "登录成功"。
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const existing = engine.getLoginUserInfo();
      if (existing && existing.userId) {
        logger.info('[login] already logged in:', existing.userId);
        resolve();
        return;
      }

      // 1. 构造签名参数（与 app 端一致）
      const timestamp = Math.floor(Date.now() / 1000);
      const nonce = Math.floor(Math.random() * 0x7fffffff) + 1;
      const requestId = `${timestamp}-${nonce}`;
      const params: SignParams = {
        OpenID: opts.userId,
        Timestamp: timestamp,
        Nonce: nonce,
        AppKey: opts.appKey,
        RequestId: requestId,
      };

      // 2. HMAC-SHA1(message, appSecret) → Base64
      const sortedQuery = buildSortedQueryString(params);
      const signature = hmacSha1Base64(opts.appSecret, sortedQuery);

      // 3. 构造 TXIoTUserSignature
      const sig = new _TXIoTUserSignature();
      sig.requestId = requestId;
      sig.timestamp = timestamp;
      sig.nonce = nonce;
      sig.signature = signature;

      // 4. 一次性 listener 转 Promise
      const listener = {
        onLoginSuccess() {
          engine.removeListener(listener);
          resolve();
        },
        onLoginFailure(errCode: number, errMsg: string) {
          engine.removeListener(listener);
          reject(new Error(`登录失败 (${errCode}): ${errMsg}`));
        },
      };
      engine.addListener(listener);

      // 5. 调 wasm 登录
      try {
        engine.login(opts.appKey, opts.userId, sig);
      } catch (e) {
        engine.removeListener(listener);
        reject(e as Error);
      }
    }).catch(reject);
  });
}

export function logout(): void {
  const engine = _getEngineSync();
  if (engine) engine.logout();
}

export async function getIoTEngine(): Promise<TXIoTEngine> {
  return initIoTEngine();
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function _getEngineSync(): any {
  // 此函数仅在已确认 initIoTEngine() resolve 后被调用（例如 app.ts onLaunch 中
  // await initIoTEngine() 之后才会触发 onPushMessage / getFamilyList 等）。
  // _engineInstance 在 initIoTEngine() resolve 后会被设置为实际的 engine 实例。
  return _engineInstance;
}

// =========================== 推送消息（透传） ===========================

/**
 * 推送消息类型常量（原样透传 SDK iot_engine.js 中 TXIoTPushMessageType 数值）。
 * 业务侧请引用本常量而非硬编码数值，便于以后 SDK 扩展。
 */
export const PushMessageType = Object.freeze({
  /** 设备状态变化（上下线） */
  StatusChange: 0,
});

/**
 * 推送消息子类型常量（原样透传 SDK iot_engine.js 中 TXIoTPushMessageSubType 数值）。
 */
export const PushMessageSubType = Object.freeze({
  Online: 0,
  Offline: 1,
});

/**
 * SDK 透出的原始推送消息（plain object 形式，便于序列化和跨页面传递）。
 * 字段语义与 SDK TXIoTPushMessage 完全对齐。
 */
export interface PushMessageRaw {
  /** 消息时间戳 */
  messageTime: number;
  /** 消息类型，参见 {@link PushMessageType} */
  type: number;
  /** 消息子类型，参见 {@link PushMessageSubType} */
  subType: number;
  /** 触发设备 */
  deviceId: { productId: string; deviceName: string };
}

export type PushMessageListener = (msg: PushMessageRaw) => void;

const _pushListeners = new Set<PushMessageListener>();
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let _pushListener: { onReceivePushMessage: (raw: any) => void } | null = null;
// 是否已发起（或完成）listener 注册，避免并发重复注册
let _pushListenerRegistering = false;

/**
 * 构造并向 SDK 注册推送 listener（仅注册一次）。
 * 内部 await initIoTEngine()，因此可在 engine 尚未就绪时安全调用。
 */
function _ensurePushListener(): void {
  if (_pushListener || _pushListenerRegistering) return;
  _pushListenerRegistering = true;
  initIoTEngine()
    .then((engine) => {
      // 期间所有 listener 都被取消了，则无需注册
      if (_pushListeners.size === 0) {
        _pushListenerRegistering = false;
        return;
      }
      _pushListener = {
        // 此回调由 wasm 端主动触发，禁止抛错以免污染 SDK 流程
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        onReceivePushMessage(raw: any) {
          const msg: PushMessageRaw = {
            messageTime: Number(raw && raw.messageTime) || 0,
            type: Number(raw && raw.type) || 0,
            subType: Number(raw && raw.subType) || 0,
            deviceId: {
              productId: (raw && raw.deviceId && raw.deviceId.productId) || '',
              deviceName: (raw && raw.deviceId && raw.deviceId.deviceName) || '',
            },
          };
          console.info('[iotEngine] onReceivePushMessage:', JSON.stringify(msg));
          // 拷贝快照，防止 listener 在回调中调用 unsub 改动原 Set 破坏迭代
          const snapshot = Array.from(_pushListeners);
          for (const fn of snapshot) {
            try {
              fn(msg);
            } catch (e) {
              console.warn('[iotEngine] push listener threw:', (e as Error).message);
            }
          }
        },
      };
      (engine as any).addListener(_pushListener);
      logger.info('[iotEngine] push listener registered');
    })
    .catch((e) => {
      _pushListenerRegistering = false;
      logger.warn('[iotEngine] register push listener failed:', (e as Error).message);
    });
}

/**
 * 订阅推送消息（透传通道）。
 *
 * @param listener 回调函数，参数为 plain object 形式的 {@link PushMessageRaw}
 * @returns 取消订阅函数；重复调用安全，最后一个 listener 取消时会自动
 *          从 SDK 移除 listener，不会泄漏。
 *
 * @example
 *   const unsub = onPushMessage((msg) => {
 *     if (msg.type === PushMessageType.StatusChange) {
 *       console.log('device', msg.deviceId.deviceName,
 *         msg.subType === PushMessageSubType.Online ? 'online' : 'offline');
 *     }
 *   });
 *   // ...page unload
 *   unsub();
 */
export function onPushMessage(listener: PushMessageListener): () => void {
  if (typeof listener !== 'function') {
    throw new Error('onPushMessage: listener 必须是函数');
  }
  _pushListeners.add(listener);

  // 异步确保 listener 已注册（engine 尚未就绪时会等待 initIoTEngine() resolve）
  _ensurePushListener();

  let removed = false;
  return () => {
    if (removed) return;
    removed = true;
    _pushListeners.delete(listener);
    if (_pushListeners.size === 0 && _pushListener) {
      const engine = _getEngineSync();
      if (engine) {
        (engine as any).removeListener(_pushListener);
      }
      _pushListener = null;
      _pushListenerRegistering = false;
      logger.info('[iotEngine] push listener unregistered');
    }
  };
}

// =========================== 业务辅助 ===========================

export interface UiFamily {
  id: string;
  name: string;
}

export interface UiDevice {
  id: string;     // productId + '_' + deviceName，用作 wxml :key
  name: string;   // 别名优先，没别名用 deviceName
  pid: string;    // productId
  online: boolean;
  productId: string;
  deviceName: string;
  iconUrl: string;
  roomId: string; // 设备所属房间 id，无归属为空串
}

/**
 * 只拉家庭列表
 */
export async function getFamilyList(): Promise<UiFamily[]> {
  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const families: any[] = await fm.getFamilyList();
  logger.debug('[iotEngine] getFamilyList raw:', JSON.stringify(families));
  return (families || []).map((f) => ({
    id: f.familyId,
    name: f.name || '未命名家庭',
  }));
}

/**
 * 创建家庭。
 * 对应 app 端的 familyManager.createFamily(name, callback)。
 * 成功后返回新家庭的 UI 模型（id/name）。
 */
export async function createFamily(name: string): Promise<UiFamily> {
  const trimmed = (name || '').trim();
  if (!trimmed) throw new Error('家庭名称不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const info: any = await fm.createFamily(trimmed);
  logger.debug('[iotEngine] createFamily raw:', JSON.stringify(info));
  return {
    id: (info && info.familyId) || '',
    name: (info && info.name) || trimmed,
  };
}

/**
 * 修改家庭名称。
 * 对应 app 端的 familyManager.updateFamilyInfo(newInfo, callback)。
 * 小程序版底层签名为 updateFamilyInfo(familyInfo)，familyInfo 必须带 familyId。
 */
export async function updateFamilyInfo(familyId: string, name: string): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');
  const trimmed = (name || '').trim();
  if (!trimmed) throw new Error('家庭名称不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  await fm.updateFamilyInfo({ familyId, name: trimmed });
  logger.info('[iotEngine] updateFamilyInfo ok:', familyId, '->', trimmed);
}

/**
 * 删除家庭。
 * 对应 app 端的 familyManager.deleteFamily(familyId, callback)。
 */
export async function deleteFamily(familyId: string): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  await fm.deleteFamily(familyId);
  logger.info('[iotEngine] deleteFamily ok:', familyId);
}

// =========================== 成员管理 ===========================

export interface UiMember {
  id: string;     // userId，作为 wxml :key
  name: string;   // 昵称优先，无昵称用 userId
  userId: string;
  isAdmin: boolean; // 是否管理员（role=1 为管理员/创建者，与鸿蒙端对齐）
}

/**
 * 创建家庭邀请 Token。
 * 对应 app 端的 familyManager.createFamilyInviteToken(familyId, callback)。
 * @returns 邀请 token 字符串，由分享给被邀请人
 */
export async function createFamilyInviteToken(familyId: string): Promise<string> {
  if (!familyId) throw new Error('家庭ID不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  const token: string = await fm.createFamilyInviteToken(familyId);
  logger.info('[iotEngine] createFamilyInviteToken ok, length:', (token || '').length);
  return token || '';
}

/**
 * 用邀请 Token 加入家庭。
 * 对应 app 端的 familyManager.joinFamilyAsMember(inviteToken, callback)。
 * 注意：底层不需要 familyId（token 自带）。
 */
export async function joinFamilyAsMember(inviteToken: string): Promise<void> {
  const trimmed = (inviteToken || '').trim();
  if (!trimmed) throw new Error('邀请 Token 不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  await fm.joinFamilyAsMember(trimmed);
  logger.info('[iotEngine] joinFamilyAsMember ok');
}

/**
 * 从家庭移除成员。
 * 对应 app 端的 familyManager.removeMemberFromFamily(familyId, userId, callback)。
 */
export async function removeMemberFromFamily(familyId: string, userId: string): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');
  if (!userId) throw new Error('成员ID不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  await fm.removeMemberFromFamily(familyId, userId);
  logger.info('[iotEngine] removeMemberFromFamily ok:', familyId, userId);
}

/**
 * 拉成员列表。
 * 对应 app 端的 familyManager.getMemberList(familyId, callback)。
 */
export async function getMemberList(familyId: string): Promise<UiMember[]> {
  if (!familyId) return [];

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const list: any[] = await fm.getMemberList(familyId);
  logger.debug('[iotEngine] getMemberList raw', familyId, ':', JSON.stringify(list));
  return (list || []).map((u) => ({
    id: u.userId || '',
    name: u.nickName || u.userId || '未命名',
    userId: u.userId || '',
    isAdmin: Number(u.role) === 1, // 管理员/家庭创建者（与鸿蒙端约定对齐：1=管理员，2=普通成员）
  }));
}

// =========================== 房间管理 ===========================

export interface UiRoom {
  id: string;     // roomId，作为 wxml :key
  name: string;
}

/**
 * 创建房间。
 * 对应 app 端的 familyManager.createRoom(familyId, name, callback)。
 */
export async function createRoom(familyId: string, name: string): Promise<UiRoom> {
  if (!familyId) throw new Error('家庭ID不能为空');
  const trimmed = (name || '').trim();
  if (!trimmed) throw new Error('房间名称不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const info: any = await fm.createRoom(familyId, trimmed);
  logger.debug('[iotEngine] createRoom raw:', JSON.stringify(info));
  return {
    id: (info && info.roomId) || '',
    name: (info && info.name) || trimmed,
  };
}

/**
 * 删除房间。
 * 对应 app 端的 familyManager.deleteRoom(familyId, roomId, callback)。
 */
export async function deleteRoom(familyId: string, roomId: string): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');
  if (!roomId) throw new Error('房间ID不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  await fm.deleteRoom(familyId, roomId);
  logger.info('[iotEngine] deleteRoom ok:', familyId, roomId);
}

/**
 * 重命名房间。
 * 对应 app 端的 familyManager.setRoomName(familyId, roomId, name, callback)。
 */
export async function renameRoom(familyId: string, roomId: string, name: string): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');
  if (!roomId) throw new Error('房间ID不能为空');
  const trimmed = (name || '').trim();
  if (!trimmed) throw new Error('房间名称不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  await fm.setRoomName(familyId, roomId, trimmed);
  logger.info('[iotEngine] renameRoom ok:', familyId, roomId, trimmed);
}

/**
 * 拉房间列表。
 * 对应 app 端的 familyManager.getRoomList(familyId, callback)。
 * 底层 wasm 透传，可能返回 array 或 { list, nextPageToken }，这里做一次兼容。
 */
export async function getRoomList(familyId: string): Promise<UiRoom[]> {
  if (!familyId) return [];

  await initIoTEngine();
  const engine = _getEngineSync();
  const fm = engine.getFamilyManager();
  if (!fm) throw new Error('FamilyManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const raw: any = await fm.getRoomList(familyId);
  console.info('[iotEngine] getRoomList raw', familyId, ':', JSON.stringify(raw));
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const list: any[] = Array.isArray(raw) ? raw : (raw && raw.dataList) || [];
  return list.map((r) => ({
    id: r.roomId || '',
    name: r.name || '未命名房间',
  }));
}

/**
 * 拉指定 family 下的设备列表（含在线状态）。
 * 与 app 端对齐：getDeviceList 在 DeviceManager 上，返回的
 * 每个 DeviceInfo 已内嵌 status，无需再单独查在线状态。
 */
export async function getDeviceList(familyId: string): Promise<UiDevice[]> {
  if (!familyId) return [];
  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const page: any = await dm.getDeviceList(familyId);
  logger.debug('[iotEngine] getDeviceList raw', familyId, ':', JSON.stringify(page));
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const list: any[] = (page && page.dataList) || [];

  return list.map((info) => {
    const productId = info.deviceId?.productId || '';
    const deviceName = info.deviceId?.deviceName || '';
    return {
      id: productId + '_' + deviceName,
      name: info.aliasName || deviceName || '设备',
      pid: productId,
      productId,
      deviceName,
      online: !!(info.status && info.status.isOnline),
      iconUrl: typeof info.iconUrl === 'string' ? info.iconUrl : '',
      roomId: typeof info.roomId === 'string' ? info.roomId : '',
    };
  });
}

/**
 * 获取设备 VoIP 授权票据（APPGetWechatDeviceTicket）。
 * 返回 sn/snTicket 供宿主自行调用 wx.requestDeviceVoIP 拉起微信原生授权弹窗。
 *
 * @param productId 产品 ID
 * @param deviceName 设备名称
 * @param modelId 微信公众平台「设备接入」分配的 model_id
 * @param appId 小程序 AppID
 */
export async function requestVoIPSnTicket(
  productId: string,
  deviceName: string,
  modelId: string,
  appId: string,
): Promise<{ sn: string; snTicket: string }> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  if (!modelId) throw new Error('modelId 不能为空');
  if (!appId) throw new Error('appId 不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  logger.debug('[iotEngine] requestVoIPSnTicket', productId, deviceName,
    'modelId:', modelId, 'appId:', appId);
  const ticket = await dm.requestVoIPSnTicket({ productId, deviceName }, modelId, appId);
  logger.info('[iotEngine] requestVoIPSnTicket done, sn=', (ticket as any)?.sn);
  return ticket;
}

/**
 * 开通设备的微信 VoIP 通话提醒。
 * 前置条件：宿主已调用 requestVoIPSnTicket + wx.requestDeviceVoIP 完成微信侧授权。
 * 内部走 2 步：AppInsertWechatAppOpenID → AppUpdateDeviceTWeCallAuthorizeStatus。
 *
 * @param productId 产品 ID
 * @param deviceName 设备名称
 * @param modelId 微信公众平台「设备接入」分配的 model_id
 * @param appId 小程序 AppID
 * @param wxOpenId 当前用户微信 OpenID（即登录 userId）
 */
export async function registerVoIPNotificationForDevice(
  productId: string,
  deviceName: string,
  modelId: string,
  appId: string,
  wxOpenId: string,
): Promise<void> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  if (!modelId) throw new Error('modelId 不能为空');
  if (!appId) throw new Error('appId 不能为空');
  if (!wxOpenId) throw new Error('wxOpenId 不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  logger.debug('[iotEngine] registerVoIPNotificationForDevice', productId, deviceName,
    'modelId:', modelId, 'appId:', appId, 'wxOpenId:', wxOpenId);
  await dm.registerVoIPNotificationForDevice({ productId, deviceName }, modelId, appId, wxOpenId);
  logger.info('[iotEngine] registerVoIPNotificationForDevice done');
}

/**
 * 关闭设备的微信 VoIP 通话提醒（仅上报云端 Status=0）。
 * 注意：微信侧授权记录只能由用户在「设置 → 语音、视频通话提醒」中手动取消。
 *
 * @param productId 产品 ID
 * @param deviceName 设备名称
 * @param modelId 微信公众平台「设备接入」分配的 model_id
 * @param appId 小程序 AppID
 * @param wxOpenId 当前用户微信 OpenID（即登录 userId）
 */
export async function unregisterVoIPNotificationForDevice(
  productId: string,
  deviceName: string,
  modelId: string,
  appId: string,
  wxOpenId: string,
): Promise<void> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  if (!modelId) throw new Error('modelId 不能为空');
  if (!wxOpenId) throw new Error('wxOpenId 不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  logger.debug('[iotEngine] unregisterVoIPNotificationForDevice', productId, deviceName,
    'modelId:', modelId, 'appId:', appId, 'wxOpenId:', wxOpenId);
  await dm.unregisterVoIPNotificationForDevice({ productId, deviceName }, modelId, appId, wxOpenId);
  logger.info('[iotEngine] unregisterVoIPNotificationForDevice done');
}

/**
 * 拉取设备物模型属性。
 * 对应 app 端的 deviceManager.getProperties(deviceId, callback)。
 *
 * @returns 解析后的属性对象（兼容顶层平铺或 properties/data 嵌套，原样返回由调用方解析）
 */
export async function getDeviceProperties(
  productId: string,
  deviceName: string,
): Promise<unknown> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  logger.debug('[iotEngine] getDeviceProperties', productId, deviceName);
  const result = await dm.getProperties({ productId, deviceName });
  // SDK 已 JSON.parse；兼容极端情况下仍是字符串
  if (typeof result === 'string') {
    try {
      return JSON.parse(result);
    } catch (_) {
      return null;
    }
  }
  return result;
}

/**
 * 下发设备控制指令。
 * 对应 app 端的 deviceManager.sendCommand(deviceId, jsonData, callback)。
 *
 * @param data 物模型键值对，如 { power_switch: 1 }
 */
export async function sendDeviceCommand(
  productId: string,
  deviceName: string,
  data: Record<string, unknown>,
): Promise<unknown> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  if (!data || typeof data !== 'object') throw new Error('指令数据不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  logger.debug('[iotEngine] sendDeviceCommand', productId, deviceName, JSON.stringify(data));
  const result = await dm.sendCommand({ productId, deviceName }, JSON.stringify(data));
  return result;
}

/**
 * 查询设备已授权的 VoIP 用户列表。
 * 对应 app 端的 deviceManager.getAuthorizedVoIPUserList(deviceId)。
 *
 * @param productId 产品 ID
 * @param deviceName 设备名称
 * @returns 已授权用户的微信 OpenId 列表
 */
export async function getAuthorizedVoIPUserList(
  productId: string,
  deviceName: string,
): Promise<string[]> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  logger.debug('[iotEngine] getAuthorizedVoIPUserList', productId, deviceName);
  const list = await dm.getAuthorizedVoIPUserList({ productId, deviceName });
  logger.info('[iotEngine] getAuthorizedVoIPUserList ok, count:', (list || []).length);
  return list || [];
}

/**
 * 把设备加入指定房间。
 * 对应 app 端的 deviceManager.addDeviceToRoom(deviceId, familyId, roomId, callback)。
 */
export async function addDeviceToRoom(
  familyId: string,
  roomId: string,
  productId: string,
  deviceName: string,
): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');
  if (!roomId) throw new Error('房间ID不能为空');
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  await dm.addDeviceToRoom({ productId, deviceName }, familyId, roomId);
  logger.info('[iotEngine] addDeviceToRoom ok:', familyId, roomId, productId, deviceName);
}

/**
 * 把设备移出其所在房间。
 * 对应 app 端的 deviceManager.removeDeviceFromRoom(deviceId, familyId, callback)。
 */
export async function removeDeviceFromRoom(
  familyId: string,
  productId: string,
  deviceName: string,
): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  await dm.removeDeviceFromRoom({ productId, deviceName }, familyId);
  logger.info('[iotEngine] removeDeviceFromRoom ok:', familyId, productId, deviceName);
}

/**
 * 把设备绑定到指定家庭。
 * 对应 app 端的 deviceManager.bindDevice(familyId, deviceBindSignature)。
 *
 * 入参只需要：
 *   - familyId：目标家庭
 *   - deviceBindSignature：配网/扫码得到的设备绑定签名串
 *     （productId、deviceName 已编码在签名内，由后端解析校验，无需前端单独传）
 *
 * @returns 绑定后的设备信息（productId / deviceName / aliasName / status 等）
 */
export async function bindDevice(
  familyId: string,
  deviceBindSignature: string,
): Promise<UiDevice> {
  if (!familyId) throw new Error('家庭ID不能为空');
  const sig = (deviceBindSignature || '').trim();
  if (!sig) throw new Error('设备绑定签名不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const info: any = await dm.bindDevice(familyId, sig);
  logger.info('[iotEngine] bindDevice ok:', familyId);
  logger.debug('[iotEngine] bindDevice raw:', JSON.stringify(info));

  const productId = info?.deviceId?.productId || '';
  const deviceName = info?.deviceId?.deviceName || '';
  return {
    id: productId + '_' + deviceName,
    name: info?.aliasName || deviceName || '设备',
    pid: productId,
    productId,
    deviceName,
    online: !!(info?.status && info.status.isOnline),
    iconUrl: typeof info?.iconUrl === 'string' ? info.iconUrl : '',
    roomId: typeof info?.roomId === 'string' ? info.roomId : '',
  };
}

/**
 * 修改设备别名（aliasName）。
 * 对应 app 端的 deviceManager.modifyAliasName(deviceId, aliasName, callback)。
 *
 * @param productId   产品ID
 * @param deviceName  设备名（设备唯一标识）
 * @param aliasName   新别名（不能为空）
 */
export async function modifyDeviceAliasName(
  productId: string,
  deviceName: string,
  aliasName: string,
): Promise<void> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  const trimmed = (aliasName || '').trim();
  if (!trimmed) throw new Error('别名不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  await dm.modifyAliasName({ productId, deviceName }, trimmed);
  logger.info('[iotEngine] modifyDeviceAliasName ok:', productId, deviceName, trimmed);
}

// =========================== 设备分享 ===========================

export interface UiSharedDevice {
  id: string;          // productId + '_' + deviceName，作为 wxml :key
  name: string;        // 别名优先
  productId: string;
  deviceName: string;
  online: boolean;
}

/**
 * 创建设备分享 Token。
 * 对应 app 端的 deviceManager.createDeviceSharingToken(familyId, deviceId, callback)。
 * @returns shareToken 字符串，可分享给被邀请人用于绑定
 */
export async function createDeviceSharingToken(
  familyId: string,
  productId: string,
  deviceName: string,
): Promise<string> {
  if (!familyId) throw new Error('家庭ID不能为空');
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');
  logger.debug('[iotEngine] createDeviceSharingToken', productId, deviceName);

  const token: string = await dm.createDeviceSharingToken(familyId, {
    productId,
    deviceName,
  });
  logger.info('[iotEngine] createDeviceSharingToken ok, length:', (token || '').length);
  return token || '';
}

/**
 * 用分享 Token 绑定别人分享给我的设备。
 * 对应 app 端的 deviceManager.bindDeviceSharedWithMe(deviceId, shareToken, callback)。
 */
export async function bindDeviceSharedWithMe(
  productId: string,
  deviceName: string,
  shareToken: string,
): Promise<void> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  const trimmed = (shareToken || '').trim();
  if (!trimmed) throw new Error('分享 Token 不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  await dm.bindDeviceSharedWithMe({ productId, deviceName }, trimmed);
  logger.info('[iotEngine] bindDeviceSharedWithMe ok:', productId, deviceName);
}

/**
 * 设备主撤销某个被分享用户。
 * 对应 app 端的 deviceManager.removeDeviceSharedUser(deviceId, userId, callback)。
 */
export async function removeDeviceSharedUser(
  productId: string,
  deviceName: string,
  userId: string,
): Promise<void> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  if (!userId) throw new Error('用户ID不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  await dm.removeDeviceSharedUser({ productId, deviceName }, userId);
  logger.info('[iotEngine] removeDeviceSharedUser ok:', productId, deviceName, userId);
}

/**
 * 拉「分享给我」的设备列表（分页，仅取首页）。
 * 对应 app 端的 deviceManager.getDeviceListSharedWithMe(nextPageToken, callback)。
 */
export async function getDeviceListSharedWithMe(): Promise<UiSharedDevice[]> {
  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const page: any = await dm.getDeviceListSharedWithMe('');
  logger.debug('[iotEngine] getDeviceListSharedWithMe raw:', JSON.stringify(page));
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const list: any[] = (page && page.dataList) || (Array.isArray(page) ? page : []);
  return list.map((info) => {
    const productId = info.deviceId?.productId || '';
    const deviceName = info.deviceId?.deviceName || '';
    return {
      id: productId + '_' + deviceName,
      name: info.aliasName || deviceName || '设备',
      productId,
      deviceName,
      online: !!(info.status && info.status.isOnline),
    };
  });
}

/**
 * 被分享方主动解绑「分享给我」的设备。
 * 对应 app 端的 deviceManager.unbindDeviceSharedWithMe(deviceId, callback)。
 */
export async function unbindDeviceSharedWithMe(
  productId: string,
  deviceName: string,
): Promise<void> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  await dm.unbindDeviceSharedWithMe({ productId, deviceName });
  logger.info('[iotEngine] unbindDeviceSharedWithMe ok:', productId, deviceName);
}

/**
 * 解绑设备（从家庭中移除设备）。
 * 对应 app 端的 deviceManager.unbindDevice(familyId, deviceId, callback)。
 */
export async function unbindDevice(
  familyId: string,
  productId: string,
  deviceName: string,
): Promise<void> {
  if (!familyId) throw new Error('家庭ID不能为空');
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  await dm.unbindDevice(familyId, { productId, deviceName });
  logger.info('[iotEngine] unbindDevice ok:', familyId, productId, deviceName);
}

export interface UiSharedUser {
  id: string;            // userId，作为 wxml :key
  userId: string;
  name: string;          // 昵称优先，无昵称用 userId
  shareTime?: number;
  sharePermission?: string;
}

/**
 * 拉指定设备的"被分享用户"列表。
 * 对应 app 端的 deviceManager.getDeviceSharedUsers(deviceId, callback)。
 */
export async function getDeviceSharedUsers(
  productId: string,
  deviceName: string,
): Promise<UiSharedUser[]> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  const dm = engine.getDeviceManager();
  if (!dm) throw new Error('DeviceManager 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const list: any[] = await dm.getDeviceSharedUsers({ productId, deviceName });
  logger.debug(
    '[iotEngine] getDeviceSharedUsers raw',
    productId,
    deviceName,
    ':',
    JSON.stringify(list),
  );
  return (list || []).map((u) => ({
    id: u.userId || '',
    userId: u.userId || '',
    name: u.nickName || u.userId || '未命名',
    shareTime: typeof u.shareTime === 'number' ? u.shareTime : undefined,
    sharePermission: u.sharePermission || '',
  }));
}

// =========================== 云存 ===========================

export interface UiCloudStorageVideoFile {
  videoUrl: string;
  startTimeMs: number;
  durationMs: number;
}

export interface UiCloudStorageEvent {
  eventType: string;
  thumbnailUrl: string;
  eventTimeMs: number;
  durationMs: number;
  videoFiles: UiCloudStorageVideoFile[];
}

export interface UiCloudStorageEventPage {
  list: UiCloudStorageEvent[];
  nextPageToken: string;
}

/**
 * 取本机 IANA 时区 ID（如 "Asia/Shanghai"），与安卓端
 * TimeZone.getDefault().getID() 语义对齐。wx 基础库的 Intl 实现在个别机型上可能
 * 缺失，此时兜底为 'Asia/Shanghai'。
 */
function getLocalTimeZoneId(): string {
  try {
    const id = Intl.DateTimeFormat().resolvedOptions().timeZone;
    return id || 'Asia/Shanghai';
  } catch (e) {
    return 'Asia/Shanghai';
  }
}

/**
 * 拉指定通道在当前时区下"有云存录像"的日期列表（元素形如 "YYYY-MM-DD"）。
 * 对应 app 端的 cloudStorage.getDayList(channelId, timeZone, callback)。
 */
export async function getCloudStorageDayList(
  productId: string,
  deviceName: string,
  channelId: number,
): Promise<string[]> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');

  await initIoTEngine();
  const engine = _getEngineSync();
  if (!engine || typeof engine.getCloudStorage !== 'function') {
    throw new Error('CloudStorage 不可用');
  }
  const cloud = engine.getCloudStorage({ productId, deviceName });
  if (!cloud) throw new Error('CloudStorage 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const days: any = await cloud.getDayList(channelId, getLocalTimeZoneId());
  logger.debug('[iotEngine] getCloudStorageDayList raw:', JSON.stringify(days));
  return Array.isArray(days) ? days.filter((d) => typeof d === 'string') : [];
}

/**
 * 拉指定日期的云存事件列表（单页）。
 * 对应 app 端的 cloudStorage.getEventList(channelId, timeZone, date, nextPageToken, callback)。
 * 分页由调用方（页面层）自行循环调用直至返回的 nextPageToken 为空字符串。
 */
export async function getCloudStorageEventList(
  productId: string,
  deviceName: string,
  channelId: number,
  date: string,
  nextPageToken: string,
): Promise<UiCloudStorageEventPage> {
  if (!productId || !deviceName) throw new Error('设备信息不完整');
  if (!date) throw new Error('日期不能为空');

  await initIoTEngine();
  const engine = _getEngineSync();
  if (!engine || typeof engine.getCloudStorage !== 'function') {
    throw new Error('CloudStorage 不可用');
  }
  const cloud = engine.getCloudStorage({ productId, deviceName });
  if (!cloud) throw new Error('CloudStorage 不可用');

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const page: any = await cloud.getEventList(
    channelId,
    getLocalTimeZoneId(),
    date,
    nextPageToken || '',
  );
  logger.debug('[iotEngine] getCloudStorageEventList raw:', JSON.stringify(page));
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const rawList: any[] = (page && page.dataList) || [];
  const list: UiCloudStorageEvent[] = rawList.map((e) => ({
    eventType: typeof e.eventType === 'string' ? e.eventType : '',
    thumbnailUrl: typeof e.thumbnailUrl === 'string' ? e.thumbnailUrl : '',
    eventTimeMs: typeof e.eventTimeMs === 'number' ? e.eventTimeMs : 0,
    durationMs: typeof e.durationMs === 'number' ? e.durationMs : 0,
    videoFiles: Array.isArray(e.videoFiles)
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      ? e.videoFiles.map((f: any) => ({
          videoUrl: typeof f.videoUrl === 'string' ? f.videoUrl : '',
          startTimeMs: typeof f.startTimeMs === 'number' ? f.startTimeMs : 0,
          durationMs: typeof f.durationMs === 'number' ? f.durationMs : 0,
        }))
      : [],
  }));
  return {
    list,
    nextPageToken: typeof (page && page.nextPageToken) === 'string' ? page.nextPageToken : '',
  };
}
