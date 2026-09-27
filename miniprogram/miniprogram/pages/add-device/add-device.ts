
import { getFamilyList, bindDevice } from '../../utils/iotEngine';

interface Family {
  id: string;
  name: string;
}

interface DevicePageInstance {
  route?: string;
  data?: { currentFamily?: { id: string; name: string } };
  setCurrentFamilyById?: (id: string, name?: string) => void;
}

Page({
  data: {
    statusBarHeight: 20,
    navBarHeight: 44,
    menuRight: 100,
    family: { id: '', name: '请先选择家庭' } as Family,
    families: [] as Family[],
    channelType: 'single' as 'single' | 'multi',
    pid: '',
    deviceName: '',
    signature: '',
  },

  onLoad(options: Record<string, string | undefined>) {
    const sys = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
    const menu = wx.getMenuButtonBoundingClientRect();
    const statusBarHeight = sys.statusBarHeight || 20;
    const gap = menu.top - statusBarHeight;
    const navBarHeight = menu.height + gap * 2;
    const menuRight = sys.windowWidth - menu.left + 8;
    const channelType = (options && options.type === 'multi') ? 'multi' : 'single';

    // 优先：device 页带过来的 familyId/familyName
    const passedId = decodeURIComponent((options && options.familyId) || '');
    const passedName = decodeURIComponent((options && options.familyName) || '');
    let fallbackId = '';
    let fallbackName = '';
    if (!passedId) {
      const pages = getCurrentPages();
      const prev =
        pages.length >= 2
          ? (pages[pages.length - 2] as unknown as DevicePageInstance)
          : null;
      const cf = prev && prev.data && prev.data.currentFamily;
      if (cf && cf.id) {
        fallbackId = cf.id;
        fallbackName = cf.name || '';
      }
    }

    let initialFamily: Family;
    if (passedId) {
      initialFamily = { id: passedId, name: passedName || '' };
    } else if (fallbackId) {
      initialFamily = { id: fallbackId, name: fallbackName };
    } else {
      initialFamily = { id: '', name: '请先选择家庭' };
    }

    this.setData({
      statusBarHeight,
      navBarHeight,
      menuRight,
      channelType,
      family: initialFamily,
    });

    // 异步拉真实家庭列表，供"切换"用；并回填 family.name
    getFamilyList()
      .then((families) => {
        const cur = this.data.family;
        const matched = families.find((f) => f.id === cur.id);
        const next: Partial<{ family: Family; families: Family[] }> = { families };
        if (matched) {
          next.family = matched;
        } else if (!cur.id && families.length > 0) {
          // 完全没指定时，默认选第一个家庭
          next.family = families[0];
        }
        this.setData(next);
      })
      .catch((err: Error) => {
        console.error('[add-device] getFamilyList failed', err);
      });
  },

  onBack() {
    wx.navigateBack({ delta: 1 }).catch(() => {
      wx.redirectTo({ url: '/pages/device/device' });
    });
  },

  onScan() {
    wx.scanCode({
      onlyFromCamera: true,
      scanType: ['qrCode', 'barCode'],
      success: (res) => {
        // 二维码内容为 JSON: {"ProductId":"xxx","DeviceName":"xxx","Signature":"xxx"}
        // 兼容小写格式: {"pid":"xxx","deviceName":"xxx","signature":"xxx"}
        let pid = '';
        let deviceName = '';
        let signature = '';
        try {
          const obj = JSON.parse(res.result);
          // 优先使用首字母大写的字段名（对齐 iOS/HarmonyOS）
          pid = obj.ProductId || obj.productId || obj.pid || '';
          deviceName = obj.DeviceName || obj.deviceName || obj.name || '';
          signature = obj.Signature || obj.signature || obj.sign || '';

          if (signature || pid) {
            if (pid) this.setData({ pid });
            if (deviceName) this.setData({ deviceName });
            if (signature) this.setData({ signature });
            wx.showToast({ title: '扫码成功', icon: 'success' });
          } else {
            wx.showToast({ title: '二维码格式错误', icon: 'none' });
          }
        } catch {
          wx.showToast({ title: '二维码格式错误：无法解析数据', icon: 'none' });
        }
      },
      fail: (err) => {
        const msg = (err && err.errMsg) || '';
        if (msg.indexOf('cancel') > -1) {
          wx.showToast({ title: '已取消扫码', icon: 'none' });
        } else if (msg.indexOf('auth') > -1 || msg.indexOf('permission') > -1) {
          wx.showModal({
            title: '需要相机权限',
            content: '请在设置中开启相机权限以扫描设备二维码',
            confirmText: '去设置',
            success: (r) => {
              if (r.confirm) {
                wx.openSetting();
              }
            },
          });
        } else {
          wx.showToast({ title: '扫码失败', icon: 'none' });
        }
      },
    });
  },

  onSwitchFamily() {
    const { families } = this.data;
    if (!families || families.length === 0) {
      wx.showToast({ title: '暂无可选家庭，请先创建家庭', icon: 'none' });
      return;
    }
    wx.showActionSheet({
      itemList: families.map((f) => f.name || f.id),
      success: (res) => {
        const target = families[res.tapIndex];
        if (target) {
          this.setData({ family: target });
        }
      },
    });
  },

  onPidInput(e: WechatMiniprogram.Input) {
    this.setData({ pid: e.detail.value });
  },

  onNameInput(e: WechatMiniprogram.Input) {
    this.setData({ deviceName: e.detail.value });
  },

  onSignInput(e: WechatMiniprogram.Input) {
    this.setData({ signature: e.detail.value });
  },

  onSubmit() {
    const { pid, deviceName, signature, family } = this.data;
    if (!family || !family.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    // SDK 真实绑定只需要 signature，pid / deviceName 仅作展示与本地提示。
    if (!signature.trim()) {
      wx.showToast({ title: '请扫码或输入设备签名', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '添加中...', mask: true });
    bindDevice(family.id, signature.trim())
      .then((info) => {
        wx.hideLoading();
        console.log('[add-device] bindDevice ok:', info);
        // 用户填写的 pid / deviceName 与签名解析结果不一致时，仅打日志，不阻塞绑定结果
        if (pid && info.productId && pid !== info.productId) {
          console.warn('[add-device] pid mismatch: input=', pid, 'returned=', info.productId);
        }
        if (deviceName && info.deviceName && deviceName !== info.deviceName) {
          console.warn('[add-device] deviceName mismatch: input=', deviceName, 'returned=', info.deviceName);
        }
        wx.showToast({ title: '添加成功', icon: 'success' });
        // 如果不主动改，返回后会刷成旧家庭的设备。
        this.notifyDevicePageSwitchFamily(family);
        setTimeout(() => {
          wx.navigateBack({ delta: 1 });
        }, 800);
      })
      .catch((err: Error & { errMsg?: string; code?: number }) => {
        wx.hideLoading();
        console.error('[add-device] bindDevice failed:', err);
        const msg = (err && (err.message || err.errMsg)) || '添加失败';
        wx.showModal({
          title: '添加失败',
          content: msg,
          showCancel: false,
        });
      });
  },

  /**
   * 通过 getCurrentPages 找到上一页（device 页），调用其 setCurrentFamilyById。
   */
  notifyDevicePageSwitchFamily(family: Family) {
    const pages = getCurrentPages();
    if (!pages || pages.length < 2) return;
    const prev = pages[pages.length - 2] as unknown as DevicePageInstance;
    if (
      prev &&
      typeof prev.route === 'string' &&
      prev.route.indexOf('pages/device/device') > -1 &&
      typeof prev.setCurrentFamilyById === 'function'
    ) {
      prev.setCurrentFamilyById(family.id, family.name);
    }
  },
});
