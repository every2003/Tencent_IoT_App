/// <reference path="./types/index.d.ts" />

/**
 * Demo 层用来表达消息中心 / 推送通知的统一 UI 模型。
 *
 * 只在 demo 内部使用，与插件无关 —— 插件仅透传 SDK 原始结构
 * (`PushMessageRaw`)，title / content / category / read 等 UI 相关字段
 * 全部由 demo 层根据原始消息派生。
 */
interface AppPushMessage {
  /** 唯一 id（messageTime + 设备标识 + 序号） */
  id: string;
  /** UI 标题 */
  title: string;
  /** UI 详情文本 */
  content: string;
  /** 已格式化的展示时间，例如 "06-09 15:30" */
  time: string;
  /** 排序 / 去重用的时间戳（毫秒），永远使用本地接收时间，避免后端时区/秒毫秒不一致 */
  receivedAt: number;
  /** 是否已读 */
  read: boolean;
  /**
   * UI 分类，对应消息中心的二级 Tab：
   *   - 'device' 设备消息（SDK 上下线推送均归到这里）
   *   - 'family' 家庭消息（SDK 暂未推送，预留）
   *   - 'notify' 通知消息（SDK 暂未推送，预留）
   */
  category: 'device' | 'family' | 'notify';
}

/** 消息列表变更监听器 */
type AppPushMessageListener = (messages: AppPushMessage[]) => void;

/**
 * 设备来电（被叫）UI 模型。
 *
 * 当前 SDK 暂未对外暴露"设备主动呼叫 App"的事件，
 * demo 层先把数据模型 + 全局横幅 UI 做好，等 SDK 给出
 * 类似 `onReceiveCallInvite(deviceId, callType)` 后，
 * 在 app.ts 里订阅再 forward 到 `notifyIncomingCall` 即可。
 */
interface IncomingCallPayload {
  /** 设备 productId */
  productId: string;
  /** 设备 deviceName */
  deviceName: string;
  /** 横幅展示用名称（别名优先） */
  name: string;
  /** 头像 url，可选；缺省时组件用内置 SVG */
  avatar?: string;
  /** 'audio' = 语音，'video' = 视频 */
  mode: 'audio' | 'video';
  /** 邀请到达时间戳（ms），用于自动超时关闭 */
  receivedAt: number;
}

/** 来电监听器；payload=null 表示当前没有来电（已被接听 / 拒接 / 超时） */
type AppIncomingCallListener = (payload: IncomingCallPayload | null) => void;

interface IAppOption {
  globalData: {
    userInfo?: WechatMiniprogram.UserInfo;
    /** 累积的推送消息（最新在前） */
    pushMessages: AppPushMessage[];
    /** 当前未处理的设备来电；无来电时为 null */
    incomingCall: IncomingCallPayload | null;
    currentUserId?: string;
    nickname?: string;
    openId?: string;
  };
  userInfoReadyCallback?: WechatMiniprogram.GetUserInfoSuccessCallback;

  // ---- 推送消息中心：demo 层提供给页面的 API ----

  /**
   * 订阅消息列表变更。返回取消订阅函数。
   * 页面在 onShow / attached 中订阅，在 onHide / detached 中取消。
   */
  subscribePushMessages(listener: AppPushMessageListener): () => void;

  /**
   * 标记消息为已读，并广播列表更新。
   * - 不传参数：全部标记为已读
   * - 传 category：仅标记该分类
   */
  markPushMessagesRead(category?: AppPushMessage['category']): void;

  /** 清空所有累积的消息（debug / 测试用） */
  clearPushMessages(): void;

  // ---- 设备来电：demo 层提供给页面的 API ----

  /**
   * 订阅设备来电变更。组件在 attached 时调用，detached 时取消。
   * 订阅后立即派发一次当前状态，便于跨页面切换无感保留弹窗。
   */
  subscribeIncomingCall(listener: AppIncomingCallListener): () => void;

  /**
   * 触发一次"设备来电"，全局唯一；同时只能有一个来电横幅。
   * 调用此方法会广播给所有 incoming-call-banner 组件。
   */
  notifyIncomingCall(payload: IncomingCallPayload): void;

  /** 清空当前来电（接听后 / 拒接后 / 超时）。 */
  dismissIncomingCall(): void;
}
