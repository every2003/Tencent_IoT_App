interface PushItem {
  id: string;
  title: string;
  content: string;
  time: string;
  read: boolean;
}

const allPush: PushItem[] = [
  {
    id: 'p1',
    title: '系统通知',
    content: '您的设备有新的固件版本可用，建议尽快升级。',
    time: '05-25 09:12',
    read: false,
  },
];

Page({
  data: {
    statusBarHeight: 20,
    topTab: 1, // 当前页固定为「推送通知」
    pushList: [] as PushItem[],
  },

  onLoad() {
    const sys = wx.getSystemInfoSync();
    this.setData({
      statusBarHeight: sys.statusBarHeight || 20,
      pushList: allPush.slice(),
    });
  },

  onBack() {
    wx.navigateBack({
      fail: () => {
        wx.redirectTo({ url: '/pages/device/device' });
      },
    });
  },

  onReadAll() {
    const list = allPush.map((m) => ({ ...m, read: true }));
    allPush.splice(0, allPush.length, ...list);
    this.setData({ pushList: allPush.slice() });
    wx.showToast({ title: '已全部标记为已读', icon: 'success' });
  },

  switchTopTab(e: WechatMiniprogram.TouchEvent) {
    const i = Number((e.currentTarget.dataset as { i: string }).i);
    if (i === this.data.topTab) return;
    if (i === 0) {
      // 切回「消息」页
      wx.redirectTo({ url: '/pages/message/message' });
    }
  },
});
