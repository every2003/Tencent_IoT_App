// app.ts

// ============================ 能力来源 ============================
//
// 推送相关能力由 demo 本地 utils/iotEngine 封装（基于插件导出的原始 SDK 类）。
// 插件层 onPushMessage 是「仅透传」，把 SDK 原始消息原样回调出来；
// 显示文案、分类、Toast 提示、持久化、未读状态都由本 app.ts 自行决定。
import { onPushMessage, PushMessageType, PushMessageSubType } from './utils/iotEngine';

const PUSH_CONST = { PushMessageType, PushMessageSubType };

// ============================ 推送消息常量 ============================

const MAX_PUSH_MESSAGES = 200; // 上限，避免内存列表无限增长

// 一秒内连续到达的推送只弹一次合并 Toast，避免设备批量上下线时刷屏
const TOAST_BATCH_WINDOW_MS = 1000;

// ============================ 工具函数 ============================

/**
 * 把 SDK 给的 messageTime 兼容成毫秒。
 * 经验：< 1e12（约 2001-09 之前）认为是秒；否则当作毫秒。
 * 当 messageTime 缺失（=0）时返回 0，调用方用本地时间兜底。
 */
function toMillis(messageTime: number): number {
  if (!messageTime || messageTime <= 0) return 0;
  return messageTime < 1e12 ? messageTime * 1000 : messageTime;
}

/** "06-09 15:30" 格式 */
function formatShort(ts: number): string {
  const d = new Date(ts);
  const pad = (n: number) => (n < 10 ? '0' + n : '' + n);
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/**
 * 把 SDK 透传的 PushMessageRaw 翻译成 demo UI 模型。
 * 当前 SDK 只推 StatusChange / Online|Offline，其它类型走兜底文案。
 */
function buildAppPushMessage(
  raw: {
    messageTime: number;
    type: number;
    subType: number;
    deviceId: { productId: string; deviceName: string };
  },
  serial: number,
  pluginConst: { PushMessageType: { StatusChange: number }; PushMessageSubType: { Online: number; Offline: number } } = PUSH_CONST,
): AppPushMessage {
  const receivedAt = toMillis(raw.messageTime) || Date.now();
  const dn = raw.deviceId.deviceName || '(未知设备)';
  const pid = raw.deviceId.productId || '(未知产品)';

  let title = '设备消息';
  let content = `productId=${pid} deviceName=${dn}`;

  if (raw.type === pluginConst.PushMessageType.StatusChange) {
    if (raw.subType === pluginConst.PushMessageSubType.Online) {
      title = '设备上线';
      content = `${dn} 已上线`;
    } else if (raw.subType === pluginConst.PushMessageSubType.Offline) {
      title = '设备下线';
      content = `${dn} 已离线`;
    } else {
      title = '设备状态变化';
      content = `${dn} 状态变化 (subType=${raw.subType})`;
    }
  } else {
    // 兜底：未识别类型，留下原始数值方便排查
    title = '未知设备消息';
    content = `${dn} type=${raw.type} subType=${raw.subType}`;
  }

  return {
    id: `${receivedAt}-${pid}-${dn}-${serial}`,
    title,
    content,
    time: formatShort(receivedAt),
    receivedAt,
    read: false,
    // SDK 当前只推送设备相关消息，统一归入「设备消息」分类
    category: 'device',
  };
}

// ============================ App ============================

// 来电自动超时（30s 与 SDK 主叫端 CALL_TIMEOUT_SEC 保持一致）
const INCOMING_CALL_TIMEOUT_MS = 30 * 1000;

App<IAppOption>({
  globalData: {
    pushMessages: [],
    incomingCall: null,
    currentUserId: '',
    nickname: '',
    openId: '',
  },

  // ---- 内部状态（不进 globalData，避免被错误使用） ----
  // 监听器集合
  _pushListeners: new Set<AppPushMessageListener>(),
  // 取消 SDK 订阅的句柄
  _unsubFromSdk: null as null | (() => void),
  // 自增序号，保证同一毫秒到达的消息 id 不重复
  _pushSerial: 0,
  // Toast 合并窗口：定时器 + 累计计数
  _pendingToastCount: 0,
  _pendingToastTimer: null as null | ReturnType<typeof setTimeout>,
  _lastToastTitle: '',
  // 来电监听器集合 + 自动超时定时器
  _incomingCallListeners: new Set<AppIncomingCallListener>(),
  _incomingCallTimer: null as null | ReturnType<typeof setTimeout>,

  onLaunch() {
    // 0) 打印运行环境信息：手机平台 / 微信版本 / 基础库版本 / 小程序版本
    try {
      let platform = '';
      let system = '';
      let model = '';
      let wxVersion = '';
      let sdkVersion = '';
      let miniProgramVersion = '';
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const wxAny = wx as any;
      if (typeof wxAny.getDeviceInfo === 'function' && typeof wxAny.getAppBaseInfo === 'function') {
        const dev = wxAny.getDeviceInfo();
        const base = wxAny.getAppBaseInfo();
        platform = dev.platform || '';
        system = dev.system || '';
        model = dev.model || '';
        wxVersion = base.version || '';
        sdkVersion = base.SDKVersion || '';
      } else {
        // 低版本基础库回退（getSystemInfoSync 已停止维护，仅兜底）
        const si = wx.getSystemInfoSync();
        platform = si.platform || '';
        system = si.system || '';
        model = si.model || '';
        wxVersion = si.version || '';
        sdkVersion = si.SDKVersion || '';
      }
      try {
        miniProgramVersion = wx.getAccountInfoSync().miniProgram.version || '';
      } catch (_) {
        // 开发者工具 / 体验版可能拿不到，忽略
      }
      console.log(
        '[runtime] platform =', platform,
        '| system =', system,
        '| model =', model,
        '| wxVersion =', wxVersion,
        '| SDKVersion =', sdkVersion,
        '| miniProgramVersion =', miniProgramVersion || '(dev)'
      );
    } catch (e) {
      console.warn('[runtime] read system info failed', e);
    }

    // 1) 打印宿主 app.json 中声明的 tx-iot-sdk 插件版本号（host 侧声明）
    try {
      const accountInfo = wx.getAccountInfoSync();
      const pluginInfo = (accountInfo as { plugins?: Record<string, { version?: string }> }).plugins?.['tx-iot-sdk'];
      console.log('[tx-iot-sdk] host declared plugin version =', pluginInfo?.version);
    } catch (e) {
      console.warn('[tx-iot-sdk] read host plugin version failed', e);
    }

    // 2) 订阅 SDK 推送（透传通道，由 demo utils 封装）
    this._unsubFromSdk = onPushMessage((raw) => {
      try {
        this._handleIncomingPush(raw);
      } catch (e) {
        console.error('[push] handle incoming push failed', e);
      }
    });

    // 3) 微信登录：初始化云开发后经云函数获取 OpenID
    //    参考文档：https://developers.weixin.qq.com/miniprogram/dev/framework/open-ability/login.html
    //    云函数 getOpenId 内部通过 getWXContext() 直接拿到调用者 OpenID。
    //    若该 appid 未开通云开发，此处静默失败，登录页会回退到手动输入。
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const wxCloud = (wx as any).cloud;
    if (wxCloud && typeof wxCloud.init === 'function') {
      wxCloud.init({ traceUser: true });
    }
    wx.login({
      success: (res) => {
        console.info('[wx.login] code:', res.code);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        if (!wxCloud || typeof wxCloud.callFunction !== 'function') {
          console.warn('[wx.login] wx.cloud unavailable, base library too old?');
          return;
        }
        wxCloud.callFunction({
          name: 'getOpenId',
          success: (cfRes: { result?: { openid?: string; openId?: string } }) => {
            const openId = cfRes.result?.openid || cfRes.result?.openId || '';
            this.globalData.openId = openId;
            console.info('[wx.login] openId from cloud:', openId);
          },
          fail: (err: unknown) => {
            console.info('[wx.login] getOpenId cloud function failed:', err);
          },
        });
          },
        });

    // 4) VoIP 接听对接（设备呼叫手机微信）
    //    参考文档：https://developers.weixin.qq.com/miniprogram/dev/framework/device/voip/call-wechat.html
    //    接听侧完全由 wmpf-voip 插件通话页承载：用户点接听 → 微信直接打开
    //    plugin-private://wxf830863afde621eb/pages/call-page-plugin/call-page-plugin。
    //    此处仅做：验证插件引入、设置通话结束跳转页、监听通话事件。
    this._setupWmpfVoipPlugin();
  },

  /** VoIP 插件初始化（接听侧） */
  _setupWmpfVoipPlugin() {
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const wmpfVoip = (requirePlugin as any)('wmpf-voip').default;
      if (!wmpfVoip) {
        console.warn('[voip-plugin] requirePlugin("wmpf-voip") returned empty');
        return;
      }
      console.info('[voip-plugin] loaded');

      if (typeof wmpfVoip.setUIConfig === 'function') {
        wmpfVoip.setUIConfig({
          callerUI: {
            cameraRotation: 270,
            objectFit: 'contain'
      },
    });
      }

      // 通话结束后用户点「关闭」跳回设备列表页（不设置则直接关闭小程序）
      if (typeof wmpfVoip.setVoipEndPagePath === 'function') {
        wmpfVoip.setVoipEndPagePath({
          url: '/pages/device/device',
          key: 'Call',
        });
      }

      // 监听通话事件（调试用）：callPageOnShow / endVoip / finishVoip 等
      if (typeof wmpfVoip.onVoipEvent === 'function') {
        wmpfVoip.onVoipEvent((event: { eventName: string; [key: string]: unknown }) => {
          console.info('[voip-plugin] event:', event.eventName, event);
        });
      }
    } catch (e) {
      console.warn('[voip-plugin] setup failed (插件未在后台添加?):', e);
    }
  },

  // -------- 推送消息处理（demo 层） --------

  _handleIncomingPush(
    raw: {
      messageTime: number;
      type: number;
      subType: number;
      deviceId: { productId: string; deviceName: string };
    },
  ) {
    this._pushSerial = (this._pushSerial + 1) & 0x7fffffff;
    const item = buildAppPushMessage(raw, this._pushSerial);

    // 累积到 globalData，最新在前；超过上限时尾部裁剪
    const next = [item, ...this.globalData.pushMessages];
    if (next.length > MAX_PUSH_MESSAGES) {
      next.length = MAX_PUSH_MESSAGES;
    }
    this.globalData.pushMessages = next;


    // Toast 合并：1s 窗口内只弹一次
    this._lastToastTitle = item.title;
    this._pendingToastCount += 1;
    if (!this._pendingToastTimer) {
      this._pendingToastTimer = setTimeout(() => {
        const count = this._pendingToastCount;
        const title = this._lastToastTitle;
        this._pendingToastCount = 0;
        this._pendingToastTimer = null;
        wx.showToast({
          title: count > 1 ? `${count} 条新消息` : title,
          icon: 'none',
          duration: 1500,
        });
      }, TOAST_BATCH_WINDOW_MS);
    }

    // 广播给订阅页面
    this._notifyListeners();
  },

  _notifyListeners() {
    const snapshot = Array.from(this._pushListeners) as AppPushMessageListener[];
    for (const fn of snapshot) {
      try {
        fn(this.globalData.pushMessages);
      } catch (e) {
        console.error('[push] listener threw', e);
      }
    }
  },

  // -------- 暴露给页面的公共 API --------

  subscribePushMessages(listener: AppPushMessageListener) {
    this._pushListeners.add(listener);
    // 立即派发一次当前列表，让订阅方拿到首屏数据
    try {
      listener(this.globalData.pushMessages);
    } catch (e) {
      console.error('[push] initial listener call threw', e);
    }
    let removed = false;
    return () => {
      if (removed) return;
      removed = true;
      this._pushListeners.delete(listener);
    };
  },

  markPushMessagesRead(category?: AppPushMessage['category']) {
    let changed = false;
    const next = this.globalData.pushMessages.map((m) => {
      // 不传 category：全部标记；传 category：仅标记该分类
      if (!m.read && (category === undefined || m.category === category)) {
        changed = true;
        return { ...m, read: true };
      }
      return m;
    });
    if (!changed) return;
    this.globalData.pushMessages = next;
    this._notifyListeners();
  },

  clearPushMessages() {
    this.globalData.pushMessages = [];
    this._notifyListeners();
  },

  // -------- 设备来电（被叫）pub/sub --------
  //
  // 当前 SDK 只对外暴露"主叫"接口（callDevice），尚未开放"被叫"事件；
  // 这里先把 demo 层的横幅 UI 与广播管线打通，等 SDK 接入后只需要在
  // onLaunch 里订阅类似 `onReceiveCallInvite` 再 forward 到
  // `notifyIncomingCall` 即可，业务页面无需任何改动。
  //
  // 联调期间可在 devtools console 直接调用：
  //   getApp().notifyIncomingCall({
  //     productId: 'PRODUCT_ID', deviceName: 'DEVICE_NAME',
  //     name: '测试设备', mode: 'video', receivedAt: Date.now(),
  //   });

  subscribeIncomingCall(listener: AppIncomingCallListener) {
    this._incomingCallListeners.add(listener);
    // 立即派发一次当前状态，便于跨页面切换时新挂载的横幅组件无感接管
    try {
      listener(this.globalData.incomingCall);
    } catch (e) {
      console.error('[incoming-call] initial listener call threw', e);
    }
    let removed = false;
    return () => {
      if (removed) return;
      removed = true;
      this._incomingCallListeners.delete(listener);
    };
  },

  notifyIncomingCall(payload: IncomingCallPayload) {
    if (!payload || !payload.productId || !payload.deviceName) {
      console.warn('[incoming-call] invalid payload, ignored:', payload);
      return;
    }

    // 同一设备重复邀请：忽略，避免横幅闪烁
    const cur = this.globalData.incomingCall;
    if (
      cur &&
      cur.productId === payload.productId &&
      cur.deviceName === payload.deviceName &&
      cur.mode === payload.mode
    ) {
      return;
    }

    // 已经在通话页面：来电直接丢弃（避免被叫 -> 进入通话 -> 又被叫的多重弹窗）
    const pages = getCurrentPages();
    const top = pages[pages.length - 1];
    if (top && top.route === 'pages/call/call') {
      console.info('[incoming-call] already on call page, drop new invite');
      return;
    }

    const next: IncomingCallPayload = {
      ...payload,
      receivedAt: payload.receivedAt || Date.now(),
    };
    this.globalData.incomingCall = next;
    this._broadcastIncomingCall();

    // 重置自动超时定时器：30s 内未接听则自动消失
    if (this._incomingCallTimer) {
      clearTimeout(this._incomingCallTimer);
    }
    this._incomingCallTimer = setTimeout(() => {
      // 仍是这条来电才清，避免覆盖新的来电
      const c = this.globalData.incomingCall;
      if (c && c.receivedAt === next.receivedAt) {
        console.info('[incoming-call] timeout, dismiss');
        this.dismissIncomingCall();
      }
    }, INCOMING_CALL_TIMEOUT_MS);
  },

  dismissIncomingCall() {
    if (this._incomingCallTimer) {
      clearTimeout(this._incomingCallTimer);
      this._incomingCallTimer = null;
    }
    if (!this.globalData.incomingCall) return;
    this.globalData.incomingCall = null;
    this._broadcastIncomingCall();
  },

  _broadcastIncomingCall() {
    const snapshot = Array.from(this._incomingCallListeners) as AppIncomingCallListener[];
    for (const fn of snapshot) {
      try {
        fn(this.globalData.incomingCall);
      } catch (e) {
        console.error('[incoming-call] listener threw', e);
      }
    }
  },
} as IAppOption & {
  _pushListeners: Set<AppPushMessageListener>;
  _unsubFromSdk: null | (() => void);
  _pushSerial: number;
  _pendingToastCount: number;
  _pendingToastTimer: null | ReturnType<typeof setTimeout>;
  _lastToastTitle: string;
  _incomingCallListeners: Set<AppIncomingCallListener>;
  _incomingCallTimer: null | ReturnType<typeof setTimeout>;
  _handleIncomingPush(
    raw: {
      messageTime: number;
      type: number;
      subType: number;
      deviceId: { productId: string; deviceName: string };
    },
  ): void;
  _notifyListeners(): void;
  _broadcastIncomingCall(): void;
  _setupWmpfVoipPlugin(): void;
  onLaunch(): void;
});
