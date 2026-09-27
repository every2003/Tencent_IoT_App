import { login } from '../../utils/iotEngine';

Page({
  data: {
    statusBarHeight: 20,
    // 字段语义对齐鸿蒙 LoginPage.ets：appKey / appSecret / userId
    openId: '', // WxOpenID = userId
    secretId: '', // AppKey
    secretKey: '', // AppSecret
    canLogin: false,
    isLoggingIn: false,
    showSecret: false,
  },

  onLoad() {
    const sys = wx.getSystemInfoSync();
    const { openId, secretId, secretKey } = this.data;
    this.setData({
      statusBarHeight: sys.statusBarHeight || 20,
      canLogin: !!(openId && secretId && secretKey),
    });
  },

  onInput(e: WechatMiniprogram.Input) {
    const key = (e.currentTarget.dataset as { key: string }).key;
    const value = e.detail.value;
    this.setData({ [key]: value } as unknown as Record<string, string>);
    const d = { ...this.data, [key]: value };
    this.setData({ canLogin: !!(d.openId && d.secretId && d.secretKey) });
  },

  toggleSecret() {
    this.setData({ showSecret: !this.data.showSecret });
  },

  /**
   * 调底层 IoTEngine 完成登录（不处理 UI/存储），返回 Promise。
   */
  doLogin(openId: string, secretId: string, secretKey: string) {
    return login({
      appKey: secretId,
      appSecret: secretKey,
      userId: openId,
    });
  },

  onLogin() {
    const { openId, secretId, secretKey, isLoggingIn } = this.data;
    if (isLoggingIn) return;
    if (!openId || !secretId || !secretKey) {
      wx.showToast({ title: '请完整填写信息', icon: 'none' });
      return;
    }

    this.setData({ isLoggingIn: true });
    wx.showLoading({ title: '登录中...', mask: true });

    // 与鸿蒙保持一致：构造 HMAC-SHA1 签名 → 调 IoTEngine.login → 等 onLoginSuccess
    this.doLogin(openId, secretId, secretKey)
      .then(() => {
        wx.hideLoading();
        const app = getApp<IAppOption>();
        app.globalData.currentUserId = openId;
        app.globalData.nickname = openId;
        wx.showToast({ title: '登录成功', icon: 'success' });
        setTimeout(() => {
          wx.redirectTo({ url: '/pages/device/device' });
        }, 600);
      })
      .catch((err: Error) => {
        wx.hideLoading();
        console.error('[login] IoTEngine login failed', err);
        wx.showToast({ title: err.message || '登录失败', icon: 'none' });
      })
      .finally(() => {
        this.setData({ isLoggingIn: false });
      });
  },
});
