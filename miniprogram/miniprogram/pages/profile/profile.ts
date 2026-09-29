import { getIoTEngine, logout as sdkLogout } from '../../utils/iotEngine';

function getEngine() {
  return getIoTEngine();
}

Page({
  data: {
    statusBarHeight: 20,
    navBarHeight: 44,
    menuRight: 100,
    nickname: '',
    userId: '',
    avatarUrl: '',
    wechatOpenId: '',
  },

  onLoad() {
    this._loadUserInfo();
  },

  onShow() {
    this._loadUserInfo();
  },

  async _loadUserInfo() {
    const sys = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
    const menu = wx.getMenuButtonBoundingClientRect();
    const statusBarHeight = sys.statusBarHeight || 20;
    const gap = menu.top - statusBarHeight;
    const navBarHeight = menu.height + gap * 2;
    const menuRight = sys.windowWidth - menu.left + 8;

    const info = (wx.getStorageSync('loginInfo') || {}) as LoginInfo;

    // 优先使用 iot_engine 的 getLoginUserInfo
    const engine = await getEngine().catch(() => null);
    let nickname = info.openId || 'qwerty';
    let userId = info.openId || 'qwerty';
    let avatarUrl = '';

    if (engine && typeof engine.getLoginUserInfo === 'function') {
      const userInfo = engine.getLoginUserInfo();
      console.info(`[profile] - getLoginUserInfo`, userInfo);
      if (userInfo) {
        nickname = userInfo.nickName || userInfo.userId || nickname;
        userId = userInfo.userId || userId;
        avatarUrl = userInfo.avatarUrl || '';
      }
    }

    // 微信 OpenID：由 app.onLaunch 经云函数 getOpenId 写入 globalData（异步，可能为空）
    const app = getApp<IAppOption>();
    const wechatOpenId = app.globalData.openId || '';

    this.setData({
      statusBarHeight,
      navBarHeight,
      menuRight,
      nickname: nickname || userId,
      userId,
      avatarUrl,
      wechatOpenId: wechatOpenId || '未获取',
    });
  },

  onCopyOpenId() {
    const { wechatOpenId } = this.data;
    if (!wechatOpenId || wechatOpenId === '未获取') return;
    wx.setClipboardData({
      data: wechatOpenId,
      success: () => {
        wx.showToast({ title: '已复制OpenID', icon: 'none' });
      },
    });
  },

  onBack() {
    wx.navigateBack({ delta: 1 }).catch(() => {
      wx.redirectTo({ url: '/pages/device/device' });
    });
  },

  onAvatarError() {
    // 头像加载失败，使用默认头像
    this.setData({
      avatarUrl: '',
    });
  },

  onLogout() {
    wx.showModal({
      title: '提示',
      content: '确认退出登录？',
      confirmColor: '#ff4757',
      success: (r) => {
        if (r.confirm) {
          try {
            sdkLogout();
          } catch (e) {
            console.warn('[profile] sdk logout failed:', e);
          }
          const app = getApp<IAppOption>();
          app.globalData.currentUserId = '';
          app.globalData.nickname = '';
          wx.reLaunch({ url: '/pages/login/login' });
        }
      },
    });
  },
});
