/**
 * 全局设备来电横幅
 *
 * - attached 时向 app 订阅 `subscribeIncomingCall`，detached 取消
 * - 接听 → wx.navigateTo 到 /pages/call/call
 * - 拒接 → app.dismissIncomingCall()
 * - 跨页面切换：旧页面 detached、新页面 attached 自动接管，弹窗保持
 */

export {};

const app = getApp<IAppOption>();

type BannerData = {
  visible: boolean;
  exiting: boolean;
  mode: 'audio' | 'video';
  name: string;
  avatar: string;
  productId: string;
  deviceName: string;
  topOffset: number;
};

type BannerMethod = {
  noop(): void;
  _navigateToCall(accepted: boolean): void;
  onAccept(): void;
  onTapBanner(): void;
  onReject(): void;
  _playExit(): void;
};

type BannerInstanceProperty = {
  _unsub: null | (() => void);
  _exitTimer: null | ReturnType<typeof setTimeout>;
};

Component<BannerData, {}, BannerMethod, [], BannerInstanceProperty>({
  options: {
    multipleSlots: false,
    addGlobalClass: false,
  },

  data: {
    visible: false,
    exiting: false,
    mode: 'audio' as 'audio' | 'video',
    name: '',
    avatar: '',
    productId: '',
    deviceName: '',
    /** 顶部偏移，避开状态栏 */
    topOffset: 24,
  },

  lifetimes: {
    created() {
      // 内部字段初始化（非 data，避免触发 setData）
      this._unsub = null;
      this._exitTimer = null;
    },
    attached() {
      // 顶部偏移：状态栏高度 + 8rpx ≈ 4px 视觉间距
      try {
        const sys = wx.getWindowInfo
          ? wx.getWindowInfo()
          : wx.getSystemInfoSync();
        const statusBarHeight = sys.statusBarHeight || 20;
        this.setData({ topOffset: statusBarHeight + 4 });
      } catch (e) {
        // 容错：保持默认值
      }

      // 订阅 app 来电状态；attached 立即派发一次当前状态
      this._unsub = app.subscribeIncomingCall((payload) => {
        if (payload) {
          // 取消可能在跑的退出动画 timer，立刻显示
          if (this._exitTimer) {
            clearTimeout(this._exitTimer);
            this._exitTimer = null;
          }
          this.setData({
            visible: true,
            exiting: false,
            mode: payload.mode,
            // 与通话页 (pages/call/call.ts) 保持一致：统一展示 'rocky_video'
            // 后续要还原真实昵称，恢复为：payload.name || payload.deviceName || '设备'
            name: 'rocky_video',
            avatar: payload.avatar || '',
            productId: payload.productId,
            deviceName: payload.deviceName,
          });
        } else if (this.data.visible) {
          // payload=null 表示来电被清除：先播退出动画，再隐藏
          this._playExit();
        }
      });
    },
    detached() {
      if (this._unsub) {
        this._unsub();
        this._unsub = null;
      }
      if (this._exitTimer) {
        clearTimeout(this._exitTimer);
        this._exitTimer = null;
      }
    },
  },

  methods: {
    /** 占位：阻止点击穿透到下层页面（catchtap） */
    noop() {
      // intentionally empty
    },

    /**
     * 跳转到通话页。
     * @param accepted 为 true 表示已在横幅点击「接听」，跳过响铃 UI 直接进 connecting
     *                 为 false 表示点击横幅其它区域，进入响铃 UI（ringing）
     */
    _navigateToCall(accepted: boolean) {
      const { mode, productId, deviceName, name, visible } = this.data;
      if (!visible) return;

      // 先清掉全局来电状态（其它页面横幅一起消失），再跳转通话页
      app.dismissIncomingCall();

      const params = [
        'mode=' + (mode === 'video' ? 'video' : 'audio'),
        'productId=' + encodeURIComponent(productId),
        'deviceName=' + encodeURIComponent(deviceName),
        'name=' + encodeURIComponent(name),
        // incoming=1：被叫流程
        // accepted=1：横幅已接听，通话页直接进 connecting，跳过 ringing 二次确认
        'incoming=1',
        accepted ? 'accepted=1' : '',
      ].filter(Boolean).join('&');
      wx.navigateTo({
        url: '/pages/call/call?' + params,
        fail: (err) => {
          console.error('[incoming-call] navigateTo failed:', err);
          wx.showToast({ title: '进入通话失败', icon: 'none' });
        },
      });
    },

    /** 点击横幅「接听」：直接进通话中页面 */
    onAccept() {
      this._navigateToCall(true);
    },

    /** 点击横幅空白区域（非接听 / 拒绝按钮），进入响铃页让用户二次确认 */
    onTapBanner() {
      this._navigateToCall(false);
    },

    onReject() {
      // TODO: SDK 提供"拒接"接口后在此调用 sdk.rejectCall(productId, deviceName)
      app.dismissIncomingCall();
    },

    /** 播放退出动画后真正隐藏，避免直接消失突兀 */
    _playExit() {
      this.setData({ exiting: true });
      this._exitTimer = setTimeout(() => {
        this.setData({ visible: false, exiting: false });
        this._exitTimer = null;
      }, 200);
    },
  },
});
