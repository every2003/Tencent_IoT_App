// 消息中心：从 globalData.pushMessages 实时读取，监听全局推送变化。
// 插件层只透传 SDK 推送，文案/已读/Toast 等 UI 行为均由本页 + app.ts 决定。

export {};

const app = getApp<IAppOption>();

Page({
  data: {
    statusBarHeight: 20,
    readRight: 0,
    messages: [] as AppPushMessage[],
    /** 未读总数，给后续顶栏小红点等扩展用 */
    unread: 0,
  },

  // 取消订阅句柄
  _unsub: null as null | (() => void),

  onLoad() {
    const sys = wx.getSystemInfoSync();
    const menu = wx.getMenuButtonBoundingClientRect();
    // 已读按钮右边缘靠近胶囊左边缘
    const readRight = (sys.windowWidth - menu.left) - 8;
    this.setData({
      statusBarHeight: sys.statusBarHeight || 20,
      readRight,
    });
  },

  onShow() {
    // 订阅会立即派发一次当前列表，因此首屏不需要再额外手动 setData
    this._unsub = app.subscribePushMessages((list) => {
      this._refreshFromList(list);
    });
  },

  onHide() {
    if (this._unsub) {
      this._unsub();
      this._unsub = null;
    }
  },

  onUnload() {
    if (this._unsub) {
      this._unsub();
      this._unsub = null;
    }
  },

  onBack() {
    wx.navigateBack({
      fail: () => {
        wx.redirectTo({ url: '/pages/device/device' });
      },
    });
  },

  onReadAll() {
    // 不再按 category 过滤，全部标记为已读
    app.markPushMessagesRead();
    wx.showToast({ title: '已全部标记为已读', icon: 'success' });
  },

  /** 刷新视图：直接展示全部消息，并统计未读总数 */
  _refreshFromList(list: AppPushMessage[]) {
    let unread = 0;
    for (const m of list) {
      if (!m.read) unread += 1;
    }
    this.setData({
      messages: list,
      unread,
    });
  },
});
