function getCurrentUserId(): string {
  return getApp<IAppOption>().globalData.currentUserId || '';
}

import {
  getDeviceList,
  getFamilyList,
  createFamily,
  updateFamilyInfo,
  deleteFamily,
  createFamilyInviteToken,
  joinFamilyAsMember,
  removeMemberFromFamily,
  getMemberList,
  createRoom,
  deleteRoom,
  getRoomList,
  renameRoom,
  createDeviceSharingToken,
  bindDeviceSharedWithMe,
  removeDeviceSharedUser,
  getDeviceListSharedWithMe,
  unbindDeviceSharedWithMe,
  modifyDeviceAliasName,
  addDeviceToRoom,
  removeDeviceFromRoom,
  unbindDevice,
  getDeviceSharedUsers,
  registerVoIPNotificationForDevice,
  requestVoIPSnTicket,
  unregisterVoIPNotificationForDevice,
  getAuthorizedVoIPUserList,
} from '../../utils/iotEngine';

function defaultChannelOptions(): Array<{ id: number; selected: boolean }> {
  return [
    { id: 0, selected: true },
    { id: 1, selected: false },
    { id: 2, selected: false },
    { id: 3, selected: false },
  ];
}

// 智能吸顶灯产品的 ProductId 列表
// 命中则进灯控页，其余默认为安防摄像头。
const CEILING_LAMP_PRODUCT_IDS = ['988BYEG00X'];

function isCeilingLamp(productId?: string): boolean {
  return !!productId && CEILING_LAMP_PRODUCT_IDS.indexOf(productId) >= 0;
}

interface Family {
  id: string;
  name: string;
}

interface Device {
  id: string;
  name: string;
  pid: string;
  online: boolean;
  productId?: string;
  deviceName?: string;
  iconUrl?: string;
  roomId?: string;
  voipRegistered?: boolean;
}

interface Member {
  id: string;
  name: string;
  userId: string;
  isAdmin: boolean;
  isSelf?: boolean;
}

interface Room {
  id: string;
  name: string;
}

interface ShareItem {
  id: string;
  name: string;
  productId?: string;
  deviceName?: string;
  online?: boolean;
  userId?: string;
  userName?: string;
  letter?: string;
  /** 当前用户是否已对该设备注册 VoIP 授权（undefined = 未查询） */
  voipRegistered?: boolean;
}

Page({
  data: {
    statusBarHeight: 20,
    navBarHeight: 44,
    menuRight: 100,
    menuTop: 26,
    menuHeight: 32,
    currentFamily: { id: '', name: '我的家' } as Family,
    families: [{ id: '', name: '我的家' }] as Family[],
    devices: [] as Device[],

    // 管理弹窗
    showManage: false,
    activeTab: 0,
    showFamilyPicker: false,
    showFamilyMenu: false,
    _pickerFromManage: false,

    // 家庭名称编辑弹窗（新建/修改）
    showFamilyEdit: false,
    familyEditMode: 'create' as 'create' | 'rename',
    familyEditName: '',
    // 删除家庭确认弹窗
    showFamilyDelete: false,
    // 记录新建/修改/删除弹窗是否由「管理面板」打开，关闭后用于恢复上一层
    _dialogFromManage: false,

    sheetDragStyle: '',
    _dragStartY: 0,

    showShareCodeSheet: false,
    shareCodeText: '',
    shareCodeTitle: '设备分享码',
    shareCodeCopyText: '复制分享码',

    showInputSheet: false,
    inputSheetTitle: '',
    inputSheetPlaceholder: '',
    inputSheetValue: '',
    inputSheetAction: '' as '' | 'joinFamily' | 'createRoom' | 'bindShare' | 'renameRoom',
    // 输入弹窗作用的目标对象 id（如改名房间的 roomId）
    inputSheetTargetId: '',

    showConfirmSheet: false,
    confirmSheetTitle: '',
    confirmSheetMsg: '',
    confirmSheetConfirmText: '删除',
    confirmSheetAction: '' as '' | 'removeMember' | 'removeRoom' | 'quitFamily',
    confirmSheetId: '',

    // 设备卡片下拉菜单（当前打开的设备 id）
    deviceMenuId: '',

    showChannelPicker: false,
    currentDeviceId: '',
    channelDeviceDesc: '',
    channelOptions: defaultChannelOptions(),

    // 选择通话方式弹窗（视频/语音）
    showCallPicker: false,
    callDeviceId: '',

    // 成员管理
    members: [] as Member[],

    // 房间管理
    rooms: [] as Room[],

    // 房间设备管理弹窗
    showRoomManage: false,
    roomManageRoom: { id: '', name: '' } as { id: string; name: string },
    roomManageDevices: [] as Array<{
      id: string;
      name: string;
      productId: string;
      deviceName: string;
      online: boolean;
      inRoom: boolean;
    }>,

    // 设备分享
    shareDevice: {
      id: '',
      name: '',
      productId: '',
      deviceName: '',
    } as { id: string; name: string; productId: string; deviceName: string },
    shareDevices: [] as Array<{ id: string; name: string; productId: string; deviceName: string }>,
    sharedToMe: [] as ShareItem[],
    sharedByMe: [] as ShareItem[],

    refreshing: false,
  },

  onLoad() {
    const sys = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
    const menu = wx.getMenuButtonBoundingClientRect();
    const statusBarHeight = sys.statusBarHeight || 20;
    // 让顶部内容行与胶囊垂直居中：状态栏下方留出 (胶囊上沿 - 状态栏) 的间距
    // navBarHeight 用胶囊高度 + 上下与状态栏对称的间距
    const gap = menu.top - statusBarHeight; // 胶囊距状态栏的间距
    const navBarHeight = menu.height + gap * 2; // 让内容行垂直居中对齐胶囊
    // 按钮右边距 = 屏幕宽度 - 胶囊左边界 + 间距
    const menuRight = sys.windowWidth - menu.left - 8;
    this.setData({
      statusBarHeight,
      navBarHeight,
      menuRight,
      menuTop: menu.top,
      menuHeight: menu.height,
    });
  },

  onShow() {
    const cur = this.data.currentFamily;
    if (cur && cur.id) {
      this.refreshCurrentFamilyDevices();
      return;
    }
    this.refreshFromSDK();
  },

  onPullRefresh() {
    this.setData({ refreshing: true });
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      this.refreshFromSDK();
      this.setData({ refreshing: false });
      return;
    }
    getFamilyList()
      .then((families) => {
        // 当前家庭已被移除（如管理员把该成员移出家庭）→ 全量刷新，不再拉旧家庭数据
        if (!families.some((f) => f.id === cur.id)) {
          this.refreshFromSDK();
          return null;
        }
        if (this.data.currentFamily && this.data.currentFamily.id === cur.id) {
          this.setData({ families });
        }
        // family 回来后请求 device；失败不阻塞 shared
        return getDeviceList(cur.id)
          .then((devices) => {
            if (this.data.currentFamily && this.data.currentFamily.id === cur.id) {
              this.setData({ devices });
              this._checkAllVoipRegistered();
            }
          })
          .catch((e: Error) => {
            console.error('[device] pull refresh getDeviceList failed', e);
          });
      })
      .catch((err: Error) => {
        console.error('[device] pull refresh getFamilyList failed', err);
      })
      .then(() => {
        // family（及 device）回来后拉 shared；放 .catch 之后保证始终执行
        this._loadSharedDevices();
      })
      .finally(() => {
        this.setData({ refreshing: false });
      });
  },

  /**
   * 仅刷新当前选中家庭的设备列表；不动 currentFamily。
   * 同时后台拉一次 families，保证家庭列表也是最新的。
   */
  refreshCurrentFamilyDevices() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) return;
    getDeviceList(cur.id)
      .then((devices) => {
        // 期间用户可能切了家庭，写入前再校验一次
        if (this.data.currentFamily && this.data.currentFamily.id === cur.id) {
          this.setData({ devices });
          this._checkAllVoipRegistered();
        }
      })
      .catch((err: Error) => {
        console.error('[device] refreshCurrentFamilyDevices failed', err);
      });
    // 分享设备不依赖家庭，一并刷新
    this._loadSharedDevices();
    // 后台同步 family 列表（不改 currentFamily）
    getFamilyList()
      .then((families) => {
        // 当前家庭已被删 → 退回默认逻辑
        if (!families.some((f) => f.id === cur.id)) {
          this.refreshFromSDK();
          return;
        }
        this.setData({ families });
      })
      .catch(() => {
        // 后台同步失败静默
      });
  },

  /**
   * 从 SDK 拉真实数据填到 families/currentFamily/devices。
   * 失败时保留默认 mock，避免页面空白。
   *
   * 注：plugin 只暴露 getFamilyList / getDeviceList 两个原子接口，
   * 这里在页面层串联（先拉家庭、再拉第一个家庭的设备），
   * "默认选第一个家庭" 是 UI 决策，因此放在页面层。
   */
  refreshFromSDK() {
    getFamilyList()
      .then((families) => {
        if (families.length === 0) {
          // 没有家庭：清空设备区，提示用户先去鸿蒙/iOS 端创建家庭
          this.setData({
            families: [],
            currentFamily: { id: '', name: '请先创建家庭' } as any,
            devices: [],
          });
          return;
        }
        const currentFamily = families[0];
        this.setData({ families, currentFamily, devices: [] });
        return getDeviceList(currentFamily.id)
          .then((devices) => {
            if (this.data.currentFamily && this.data.currentFamily.id === currentFamily.id) {
              this.setData({ devices });
              this._checkAllVoipRegistered();
            }
          })
          .catch((e: Error) => {
            console.error('[device] getDeviceList failed', e);
          });
      })
      .catch((err: Error) => {
        console.error('[device] refreshFromSDK failed', err);
        wx.showToast({ title: err.message || '加载设备失败', icon: 'none' });
        // 不清 mock，保留页面可点击调试
      })
      .then(() => {
        this._loadSharedDevices();
      });
  },

  _loadSharedDevices() {
    getDeviceListSharedWithMe()
      .then((list) => {
        const sharedToMe: ShareItem[] = list.map((d) => ({
          id: d.id,
          name: d.name,
          productId: d.productId,
          deviceName: d.deviceName,
          online: d.online,
        }));
        this.setData({ sharedToMe });
        this._checkAllVoipRegistered();
      })
      .catch((err: Error) => {
        console.error('[device] loadSharedDevices failed', err);
      });
  },

  // 顶部动作
  goMessage() {
    wx.navigateTo({ url: '/pages/message/message' });
  },

  onAdd() {
    this.setData({ deviceMenuId: '' });
    const cur = this.data.currentFamily;
    const qs = cur && cur.id
      ? '?familyId=' + encodeURIComponent(cur.id) +
      '&familyName=' + encodeURIComponent(cur.name || '')
      : '';
    wx.navigateTo({ url: '/pages/add-device/add-device' + qs });
  },

  /**
   * 提供给 add-device 等子页通过 getCurrentPages() 主动调用。
   * 把当前选中家庭切到指定 id（通常是 add-device 页用户切换 / 添加成功的家庭），
   * 同时持久化、清空旧家庭设备并立即拉一次新家庭设备列表。
   * 之后 onShow 会再 refreshCurrentFamilyDevices 一次（双保险）。
   */
  setCurrentFamilyById(id: string, name?: string) {
    if (!id) return;
    const cur = this.data.currentFamily;
    if (cur && cur.id === id) {
      // 同一个家庭，无需切换
      return;
    }
    const fromList = this.data.families.find((f) => f.id === id);
    const target: Family = fromList || { id, name: name || '' };
    this.setData({
      currentFamily: target,
      devices: [], // 清空旧家庭设备，避免回到 device 页瞬间看到错位数据
    });
    getDeviceList(id)
      .then((devices) => {
        // 写回前再校验一次，防止用户极速再次切换造成的竞态
        if (this.data.currentFamily && this.data.currentFamily.id === id) {
          this.setData({ devices });
          this._checkAllVoipRegistered();
        }
      })
      .catch((err: Error) => {
        console.error('[device] setCurrentFamilyById fetch failed', err);
      });
  },

  onSharedDeviceTap(e: WechatMiniprogram.TouchEvent) {
    const ds = e.currentTarget.dataset as { id: string; name: string; productId: string; deviceName: string };
    // 吸顶灯类设备进灯控页（对齐 iOS handleDeviceTap）
    if (isCeilingLamp(ds.productId)) {
      this._navigateToLamp(ds.productId, ds.deviceName, ds.name);
      return;
    }
    this.setData({
      showChannelPicker: true,
      currentDeviceId: ds.id,
      channelOptions: defaultChannelOptions(),
      channelDeviceDesc: ds.productId + '/' + ds.deviceName,
    });
  },

  onDeviceTap(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    // 如果当前有菜单展开，则只关闭菜单，不弹出通道选择
    if (this.data.deviceMenuId) {
      this.setData({ deviceMenuId: '' });
      return;
    }
    const dev = this.data.devices.find((d) => d.id === id);
    const productId = (dev && dev.productId) || '';
    const deviceName = (dev && dev.deviceName) || (dev ? dev.name : '');
    // 吸顶灯类设备进灯控页，其余走通道选择（对齐 iOS handleDeviceTap）
    if (dev && isCeilingLamp(productId)) {
      this._navigateToLamp(productId, deviceName, dev.name);
      return;
    }
    this.setData({
      showChannelPicker: true,
      currentDeviceId: id,
      channelOptions: defaultChannelOptions(),
      channelDeviceDesc: productId + '/' + deviceName,
    });
  },

  /** 跳转吸顶灯控制页 */
  _navigateToLamp(productId: string, deviceName: string, name?: string) {
    const params = [
      'productId=' + encodeURIComponent(productId),
      'deviceName=' + encodeURIComponent(deviceName),
      'name=' + encodeURIComponent(name || ''),
    ].join('&');
    wx.navigateTo({ url: '/pages/lamp/lamp?' + params });
  },

  onDeviceIconError(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    if (!id) return;
    const idx = this.data.devices.findIndex((d) => d.id === id);
    if (idx < 0) return;
    if (!this.data.devices[idx].iconUrl) return;
    this.setData({ [`devices[${idx}].iconUrl`]: '' });
  },

  closeChannelPicker() {
    this.setData({ showChannelPicker: false });
  },

  onSelectChannelItem(e: WechatMiniprogram.TouchEvent) {
    const id = Number((e.currentTarget.dataset as { id: string }).id);
    const idx = this.data.channelOptions.findIndex((c) => c.id === id);
    if (idx < 0) return;
    this.setData({ [`channelOptions[${idx}].selected`]: !this.data.channelOptions[idx].selected });
  },

  // 选择通话方式弹窗
  closeCallPicker() {
    this.setData({ showCallPicker: false });
  },

  onSelectCall(e: WechatMiniprogram.TouchEvent) {
    const mode = (e.currentTarget.dataset as { mode: string }).mode;
    const id = this.data.callDeviceId;
    const dev = this.data.devices.find((d) => d.id === id) || this.data.sharedToMe.find((s) => s.id === id);
    this.setData({ showCallPicker: false });
    if (!dev) {
      wx.showToast({ title: '设备不存在', icon: 'none' });
      return;
    }
    if (!dev.productId || !dev.deviceName) {
      wx.showToast({ title: '设备信息不完整', icon: 'none' });
      return;
    }
    const callMode = mode === 'video' ? 'video' : 'audio';
    const params = [
      'mode=' + callMode,
      'productId=' + encodeURIComponent(dev.productId),
      'deviceName=' + encodeURIComponent(dev.deviceName),
      'name=' + encodeURIComponent(dev.name || ''),
    ].join('&');
    wx.navigateTo({ url: '/pages/call/call?' + params });
  },

  onConfirmChannels() {
    const channels = this.data.channelOptions
      .filter((c) => c.selected)
      .map((c) => c.id)
      .sort((a, b) => a - b);
    if (channels.length === 0) {
      wx.showToast({ title: '请至少选择一个通道', icon: 'none' });
      return;
    }
    const dev = this.data.devices.find((d) => d.id === this.data.currentDeviceId);
    const shared = !dev ? this.data.sharedToMe.find((s) => s.id === this.data.currentDeviceId) : undefined;
    const name = dev ? dev.name : (shared ? shared.name : 'device');
    const productId = (dev && dev.productId) || (shared && shared.productId) || '';
    const deviceName = (dev && dev.deviceName) || (shared && shared.deviceName) || name;
    const familyId = (this.data.currentFamily && this.data.currentFamily.id) || '';
    const channelType = channels.length === 1 ? 'single' : 'multi';
    this.setData({ showChannelPicker: false });
    wx.navigateTo({
      url:
        '/pages/preview/preview?type=' + channelType + '&name=' +
        encodeURIComponent(name) +
        '&channels=' + channels.join(',') +
        '&productId=' +
        encodeURIComponent(productId) +
        '&deviceName=' +
        encodeURIComponent(deviceName) +
        '&familyId=' +
        encodeURIComponent(familyId),
    });
  },

  onUser() {
    wx.navigateTo({ url: '/pages/profile/profile' });
  },

  onDeviceMore(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.setData({ deviceMenuId: this.data.deviceMenuId === id ? '' : id });
  },

  /** 对当前列表里的每个设备做一次 VoIP 注册检查（已检查过的跳过） */
  _checkAllVoipRegistered() {
    this.data.devices.forEach((d) => this._checkVoipRegistered(d.id));
    this.data.sharedToMe.forEach((s) => this._checkVoipRegistered(s.id));
  },

  /** 查询单个设备当前用户是否已注册 VoIP 授权（刷新时随列表触发） */
  _checkVoipRegistered(id: string) {
    const dev = this.data.devices.find((d) => d.id === id);
    const shared = !dev ? this.data.sharedToMe.find((s) => s.id === id) : undefined;
    const src = dev || shared;
    if (!src || !src.productId || !src.deviceName) return;
    // 已查询过则不再重复请求
    if (typeof src.voipRegistered === 'boolean') return;
    const openId = getApp<IAppOption>().globalData.openId || '';
    if (!openId) return;
    getAuthorizedVoIPUserList(src.productId, src.deviceName)
      .then((list) => {
        const registered = (list || []).indexOf(openId) >= 0;
        this._setVoipRegistered(id, registered);
      })
      .catch((err: Error) => {
        console.error('[device] check voip registered failed', err);
      });
  },

  /** 更新某个设备的 VoIP 注册状态（devices / sharedToMe 两处均支持） */
  _setVoipRegistered(id: string, registered: boolean) {
    let key = 'devices';
    let idx = this.data.devices.findIndex((d) => d.id === id);
    if (idx < 0) {
      key = 'sharedToMe';
      idx = this.data.sharedToMe.findIndex((s) => s.id === id);
    }
    if (idx < 0) return;
    this.setData({ [key + '[' + idx + '].voipRegistered']: registered } as Record<string, boolean>);
  },

  closeDeviceMenu() {
    if (this.data.deviceMenuId) this.setData({ deviceMenuId: '' });
  },

  onDeviceCall(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.setData({
      deviceMenuId: '',
      showCallPicker: true,
      callDeviceId: id,
    });
  },

  onDeviceUnbind(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.setData({ deviceMenuId: '' });
    const dev = this.data.devices.find((d) => d.id === id);
    const shared = !dev ? this.data.sharedToMe.find((s) => s.id === id) : undefined;
    if (!dev && !shared) return;
    const productId = (dev && dev.productId) || (shared && shared.productId) || '';
    const deviceName = (dev && dev.deviceName) || (shared && shared.deviceName) || '';
    const isShared = !!shared;
    wx.showModal({
      title: '提示',
      content: isShared ? '确认取消该分享设备？' : '确认解绑该设备？',
      confirmColor: '#ff4757',
      success: (r) => {
        if (!r.confirm) return;
        const promise = isShared
          ? unbindDeviceSharedWithMe(productId, deviceName)
          : unbindDevice(this.data.currentFamily.id, productId, deviceName);
        promise
          .then(() => {
            if (isShared) {
              this.setData({ sharedToMe: this.data.sharedToMe.filter((s) => s.id !== id) });
            } else {
              this.setData({ devices: this.data.devices.filter((d) => d.id !== id) });
            }
            wx.showToast({ title: isShared ? '已取消分享' : '已解绑', icon: 'success' });
          })
          .catch((err: Error) => {
            console.error('[device] unbind failed:', err);
            wx.showToast({ title: err.message || (isShared ? '取消失败' : '解绑失败'), icon: 'none' });
          });
      },
    });
  },

  onDeviceShare(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.setData({ deviceMenuId: '' });
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    const dev = this.data.devices.find((d) => d.id === id);
    if (!dev || !dev.productId || !dev.deviceName) {
      wx.showToast({ title: '设备信息不完整', icon: 'none' });
      return;
    }
    const productId = dev.productId;
    const deviceName = dev.deviceName;
    wx.showLoading({ title: '生成中...', mask: true });
    createDeviceSharingToken(cur.id, productId, deviceName)
      .then((token) => {
        wx.hideLoading();
        if (!token) {
          wx.showToast({ title: '生成分享失败', icon: 'none' });
          return;
        }
        const codeText = JSON.stringify({
          productId,
          deviceName,
          token,
        });
        this.openCodeSheet('设备分享码', codeText, '复制分享码');
      })
      .catch((err: Error) => {
        wx.hideLoading();
        console.warn('[device] onDeviceShare createDeviceSharingToken failed', err);
        wx.showToast({
          title: (err && err.message) || '生成分享失败',
          icon: 'none',
        });
      });
  },

  /** 复制设备分享码到剪贴板 */
  onCopyShareCode() {
    const text = this.data.shareCodeText;
    if (!text) return;
    wx.setClipboardData({
      data: text,
      success: () => {
        this.setData({
          showShareCodeSheet: false,
          sheetDragStyle: '',
          ...this._resumeFromDialog(),
        });
        wx.showToast({ title: '已复制', icon: 'success' });
      },
      fail: () => {
        wx.showToast({ title: '复制失败', icon: 'none' });
      },
    });
  },

  /** 关闭设备分享码弹窗 */
  closeShareCodeSheet() {
    this.setData({
      showShareCodeSheet: false,
      sheetDragStyle: '',
      ...this._resumeFromDialog(),
    });
  },

  onDeviceCloud(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.setData({ deviceMenuId: '' });
    const dev = this.data.devices.find((d) => d.id === id) || this.data.sharedToMe.find((s) => s.id === id);
    if (!dev || !dev.productId || !dev.deviceName) {
      wx.showToast({ title: '设备信息不完整', icon: 'none' });
      return;
    }
    const online = (dev as { online?: boolean }).online;
    // 跳转云存页（数据由插件 tx-iot-sdk 透传）
    const params = [
      'productId=' + encodeURIComponent(dev.productId),
      'deviceName=' + encodeURIComponent(dev.deviceName),
      'aliasName=' + encodeURIComponent(dev.name || ''),
      'online=' + (online ? '1' : '0'),
    ].join('&');
    wx.navigateTo({
      url: '/pages/cloud-storage/cloud-storage?' + params,
      fail: (err) => {
        console.error('[device] navigateTo cloud-storage failed:', err);
        wx.showToast({ title: '打开云存失败', icon: 'none' });
      },
    });
  },

  /** 设备 VoIP 授权：未注册 → 注册；已注册 → 解除 */
  onDeviceVoIP(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.setData({ deviceMenuId: '' });
    const dev = this.data.devices.find((d) => d.id === id) || this.data.sharedToMe.find((s) => s.id === id);
    if (!dev || !dev.productId || !dev.deviceName) {
      wx.showToast({ title: '设备信息不完整', icon: 'none' });
      return;
    }
    const productId = dev.productId;
    const deviceName = dev.deviceName;
    // modelId 固定（微信公众平台「设备管理」分配的 model_id）
    const modelId = 'fK_0maiGYgvsQt-gXejjNg';
    // 小程序 AppID（运行时读取当前宿主小程序的 appId）
    const appId = wx.getAccountInfoSync().miniProgram.appId;
    // 当前用户 OpenID（登录时的 userId）
    const app = getApp<IAppOption>();
    const openId = app.globalData.openId || '';
    if (!openId) {
      wx.showToast({ title: '未获取到用户 OpenID，请先登录', icon: 'none' });
      return;
    }
    if (dev.voipRegistered) {
      // 已注册 → 解除授权（二次确认）
      wx.showModal({
        title: '解除VoIP授权',
        content: '解除后将不再接收该设备的微信 VoIP 通话提醒，确定解除？',
        success: (res) => {
          if (!res.confirm) return;
          wx.showLoading({ title: '解除中...', mask: true });
          unregisterVoIPNotificationForDevice(productId, deviceName, modelId, appId, openId)
            .then(() => {
              wx.hideLoading();
              this._setVoipRegistered(id, false);
              wx.showToast({ title: '已解除授权', icon: 'success' });
            })
            .catch((err: Error) => {
              wx.hideLoading();
              console.error('[device] unregisterVoIPNotificationForDevice failed', err);
              wx.showToast({ title: err.message || '解除失败', icon: 'none' });
            });
        },
      });
      return;
    }
    // 未注册 → 注册授权（三步：SDK 取票据 → 微信授权弹窗 → SDK 登记）
    wx.showLoading({ title: '开通中...', mask: true });
    (async () => {
      try {
        const ticket = await requestVoIPSnTicket(productId, deviceName, modelId, appId);
        await new Promise<void>((resolve, reject) => {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const wxAny = wx as any;
          if (typeof wxAny.requestDeviceVoIP !== 'function') {
            reject(new Error('wx.requestDeviceVoIP 不可用（需真机；基础库 >= 2.27.3）'));
            return;
          }
          wxAny.requestDeviceVoIP({
            sn: ticket.sn,
            snTicket: ticket.snTicket,
            modelId,
            deviceName: dev.name || deviceName,
            success: () => resolve(),
            fail: (err: { errCode?: number; errMsg?: string }) => {
              if (err && err.errCode === 10001) {
                resolve();
                return;
              }
              reject(new Error((err && err.errMsg) || 'wx.requestDeviceVoIP failed'));
            },
          });
        });
        await registerVoIPNotificationForDevice(productId, deviceName, modelId, appId, openId);
        wx.hideLoading();
        this._setVoipRegistered(id, true);
        wx.showToast({ title: '开通成功', icon: 'success' });
      } catch (err) {
        wx.hideLoading();
        console.error('[device] registerVoIP failed', err, err && (err as Error).stack);
        const e = err as Error;
        wx.showToast({ title: (e && e.message) || '开通失败', icon: 'none' });
      }
    })();
  },

  /** 修改设备别名 */
  onDeviceRename(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.setData({ deviceMenuId: '' });
    const dev = this.data.devices.find((d) => d.id === id);
    const shared = !dev ? this.data.sharedToMe.find((s) => s.id === id) : undefined;
    const src = dev || shared;
    if (!src) return;
    if (!src.productId || !src.deviceName) {
      wx.showToast({ title: '设备信息不完整', icon: 'none' });
      return;
    }
    const productId = src.productId;
    const deviceName = src.deviceName;
    const oldName = src.name || deviceName;
    wx.showModal({
      title: '修改别名',
      editable: true,
      placeholderText: '请输入新别名',
      content: oldName,
      success: (r) => {
        if (!r.confirm) return;
        const next = (r.content || '').trim();
        if (!next) {
          wx.showToast({ title: '别名不能为空', icon: 'none' });
          return;
        }
        if (next === oldName) return;
        wx.showLoading({ title: '保存中...', mask: true });
        modifyDeviceAliasName(productId, deviceName, next)
          .then(() => {
            wx.hideLoading();
            const patch: Record<string, unknown> = {};
            if (dev) {
              patch.devices = this.data.devices.map((d) =>
                d.id === id ? { ...d, name: next } : d,
              );
            } else if (shared) {
              patch.sharedToMe = this.data.sharedToMe.map((s) =>
                s.id === id ? { ...s, name: next } : s,
              );
            }
            // 同步分享管理弹窗里选中的设备名称
            const sd = this.data.shareDevice;
            if (sd && sd.id === id) {
              patch.shareDevice = { ...sd, name: next };
            }
            this.setData(patch);
            wx.showToast({ title: '已修改', icon: 'success' });
          })
          .catch((err) => {
            wx.hideLoading();
            console.warn('[device] modifyDeviceAliasName failed', err);
            wx.showToast({
              title: (err && err.message) || '修改失败',
              icon: 'none',
            });
          });
      },
    });
  },

  // 管理弹窗
  openManage() {
    this.setData({ showManage: true });
    // 自动按当前 tab 拉对应真实数据
    this.loadActiveTabData();
  },

  closeManage() {
    this.setData({ showManage: false, showFamilyMenu: false, sheetDragStyle: '' });
  },

  // 拖拽关闭 bottom sheet
  onSheetTouchStart(e: WechatMiniprogram.TouchEvent) {
    this.data._dragStartY = e.touches[0].clientY;
  },

  onSheetTouchMove(e: WechatMiniprogram.TouchEvent) {
    const deltaY = e.touches[0].clientY - this.data._dragStartY;
    if (deltaY <= 0) return; // 向上拉忽略
    this.setData({
      sheetDragStyle: `transform: translateY(${deltaY}px); transition: none;`,
    });
  },

  onSheetTouchEnd(e: WechatMiniprogram.TouchEvent) {
    const deltaY = e.changedTouches[0].clientY - this.data._dragStartY;
    const THRESHOLD = 100;
    if (deltaY >= THRESHOLD) {
      this.setData({
        sheetDragStyle: `transform: translateY(100vh); transition: transform 200ms ease;`,
      });
      setTimeout(() => {
        this.setData({ sheetDragStyle: '' });
        this._closeCurrentSheet();
      }, 200);
    } else {
      this.setData({ sheetDragStyle: '' });
    }
  },

  /** 关闭当前可见的弹窗 */
  _closeCurrentSheet() {
    if (this.data.showFamilyEdit) {
      this.closeFamilyEdit();
    } else if (this.data.showFamilyDelete) {
      this.closeFamilyDelete();
    } else if (this.data.showShareCodeSheet) {
      this.closeShareCodeSheet();
    } else if (this.data.showManage) {
      this.setData({ showManage: false, showFamilyMenu: false });
    } else if (this.data.showFamilyPicker) {
      this.closeFamilyPicker();
    } else if (this.data.showChannelPicker) {
      this.setData({ showChannelPicker: false });
    } else if (this.data.showCallPicker) {
      this.setData({ showCallPicker: false });
    }
  },

  switchTab(e: WechatMiniprogram.TouchEvent) {
    const i = Number((e.currentTarget.dataset as { i: string }).i);
    this.setData({ activeTab: i, showFamilyMenu: false });
    this.loadActiveTabData();
  },

  /**
   * 根据 activeTab 拉对应的真实数据：
   *   0 → 成员
   *   1 → 房间
   *   2 → 设备分享（"分享给我" + "我分享出去"）
   * 当未选中家庭时静默跳过。
   */
  loadActiveTabData() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) return;
    switch (this.data.activeTab) {
      case 0:
        this.loadMembers(cur.id);
        break;
      case 1:
        this.loadRooms(cur.id);
        break;
      case 2:
      default:
        this.loadShares();
        break;
    }
  },

  /** 拉成员列表，写入 data.members */
  loadMembers(familyId: string) {
    if (!familyId) return;
    getMemberList(familyId)
      .then((members) => {
        // 期间用户可能切换了家庭 → 防御一下
        if (this.data.currentFamily && this.data.currentFamily.id === familyId) {
          const myId = getCurrentUserId();
          const list = members.map((m) => ({
            ...m,
            isSelf: !!myId && m.userId === myId,
          }));
          this.setData({ members: list });
        }
      })
      .catch((err: Error) => {
        console.error('[device] getMemberList failed', err);
        wx.showToast({ title: err.message || '加载成员失败', icon: 'none' });
      });
  },

  _roomsWithCount(rooms: Room[]): Room[] {
    const devices = this.data.devices || [];
    return rooms.map((r) => ({
      ...r,
      deviceCount: devices.filter((d) => d.roomId === r.id).length,
    }));
  },

  /** 拉房间列表，写入 data.rooms */
  loadRooms(familyId: string) {
    if (!familyId) return;
    getRoomList(familyId)
      .then((rooms) => {
        if (this.data.currentFamily && this.data.currentFamily.id === familyId) {
          this.setData({ rooms: this._roomsWithCount(rooms) });
        }
      })
      .catch((err: Error) => {
        console.error('[device] getRoomList failed', err);
        wx.showToast({ title: err.message || '加载房间失败', icon: 'none' });
      });
  },

  /**
   * 拉设备分享相关数据：
   *   - sharedToMe：别人分享给我的（getDeviceListSharedWithMe）
   *   - sharedByMe：我分享出去的，按 (设备 × 用户) 展开（页面层并发调用 getDeviceSharedUsers 聚合）
   * 同时如果 shareDevice 还未选中，默认取当前家庭的第一台设备。
   */
  loadShares() {
    const shareDevices = this.data.devices
      .filter((d) => d.productId && d.deviceName)
      .map((d) => ({
        id: d.id,
        name: d.name || d.deviceName || d.id,
        productId: d.productId as string,
        deviceName: d.deviceName as string,
      }));
    this.setData({ shareDevices });

    let active = this.data.shareDevice;
    if ((!active.id || !active.productId) && shareDevices.length) {
      const d = shareDevices[0];
      active = {
        id: d.id,
        name: d.name,
        productId: d.productId,
        deviceName: d.deviceName,
      };
      this.setData({ shareDevice: active });
    }

    // 别人分享给我
    getDeviceListSharedWithMe()
      .then((list) => {
        const sharedToMe: ShareItem[] = list.map((d) => ({
          id: d.id,
          name: d.name,
          productId: d.productId,
          deviceName: d.deviceName,
          online: d.online,
        }));
        this.setData({ sharedToMe });
      })
      .catch((err: Error) => {
        console.error('[device] getDeviceListSharedWithMe failed', err);
        wx.showToast({ title: err.message || '加载分享失败', icon: 'none' });
      });

    this.loadSharedByMe(active);
  },

  /**
   * 拉「当前选中设备」分享出去的用户列表。
   */
  loadSharedByMe(dev?: { name?: string; productId: string; deviceName: string }) {
    const sd = dev || this.data.shareDevice;
    const productId = sd.productId;
    const deviceName = sd.deviceName;
    if (!productId || !deviceName) {
      this.setData({ sharedByMe: [] });
      return;
    }
    getDeviceSharedUsers(productId, deviceName)
      .then((users) => {
        const sharedByMe: ShareItem[] = users.map((u) => {
          const display = u.name || u.userId || '';
          return {
            id: `${productId}_${deviceName}_${u.userId}`,
            name: sd.name || deviceName,
            productId,
            deviceName,
            userId: u.userId,
            userName: u.name,
            letter: (display.charAt(0) || '?').toUpperCase(),
          };
        });
        this.setData({ sharedByMe });
      })
      .catch((err: Error) => {
        console.warn(
          '[device] getDeviceSharedUsers failed',
          productId,
          deviceName,
          err,
        );
        this.setData({ sharedByMe: [] });
      });
  },

  /**
   */
  onSelectShareDevice(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    const d = this.data.shareDevices.find((x) => x.id === id);
    if (!d) return;
    this.setData({
      shareDevice: {
        id: d.id,
        name: d.name,
        productId: d.productId,
        deviceName: d.deviceName,
      },
    });
    this.loadSharedByMe(d);
  },

  // 家庭选择器
  openFamilyPicker() {
    const fromManage = this.data.showManage;
    this.setData({
      showFamilyPicker: true,
      showFamilyMenu: false,
      showManage: false,
      _pickerFromManage: fromManage,
    });
  },

  closeFamilyPicker() {
    const resume = this.data._pickerFromManage;
    this.setData({
      showFamilyPicker: false,
      showManage: resume ? true : this.data.showManage,
      _pickerFromManage: false,
    });
  },

  selectFamily(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    const f = this.data.families.find((x) => x.id === id);
    const resume = this.data._pickerFromManage;
    if (!f) {
      this.setData({
        showFamilyPicker: false,
        showManage: resume ? true : this.data.showManage,
        _pickerFromManage: false,
      });
      return;
    }
    // 切换 family 后立即拉对应的设备列表，并持久化用户选择
    // 同时清空"管理弹窗"里属于旧家庭的成员/房间/分享数据，避免错位
    this.setData({
      currentFamily: f,
      showFamilyPicker: false,
      showManage: resume ? true : this.data.showManage,
      _pickerFromManage: false,
      devices: [], // 先清空，loading 期间不显示旧 family 的设备
      members: [],
      rooms: [],
      sharedByMe: [],
      shareDevice: { id: '', name: '', productId: '', deviceName: '' },
    });
    wx.showLoading({ title: '加载中...', mask: true });
    getDeviceList(f.id)
      .then((devices) => {
        this.setData({ devices });
        // 设备就绪后，如果管理弹窗开着，按当前 tab 自动刷新
        if (this.data.showManage) {
          this.loadActiveTabData();
        }
        wx.hideLoading();
      })
      .catch((err: Error) => {
        console.error('[device] getDeviceList failed', err);
        wx.hideLoading();
        wx.showToast({ title: err.message || '加载设备失败', icon: 'none' });
      })
  },

  // 家庭操作菜单
  toggleFamilyMenu() {
    this.setData({ showFamilyMenu: !this.data.showFamilyMenu });
  },

  closeFamilyMenu() {
    if (this.data.showFamilyMenu) {
      this.setData({ showFamilyMenu: false });
    }
  },

  onRenameFamily() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    this.setData({
      showFamilyMenu: false,
      showManage: false,
      _dialogFromManage: this.data.showManage,
      familyEditMode: 'rename',
      familyEditName: cur.name || '',
      showFamilyEdit: true,
    });
  },

  onCreateFamily() {
    this.setData({
      showFamilyMenu: false,
      showManage: false,
      _dialogFromManage: this.data.showManage,
      familyEditMode: 'create',
      familyEditName: '',
      showFamilyEdit: true,
    });
  },

  // 家庭名称输入
  onFamilyEditInput(e: WechatMiniprogram.Input) {
    this.setData({ familyEditName: e.detail.value });
  },

  closeFamilyEdit() {
    this.setData({ showFamilyEdit: false, ...this._resumeFromDialog() });
  },

  // 关闭新建/修改/删除弹窗后，恢复打开它的「管理面板」（如有）
  _resumeFromDialog() {
    const resume = this.data._dialogFromManage;
    return { showManage: resume ? true : this.data.showManage, _dialogFromManage: false };
  },

  // 阻止点击弹窗内容时冒泡关闭
  noop() { },

  // ============ 统一底部弹窗：Token 展示 / 输入 / 确认 ============

  openCodeSheet(title: string, text: string, copyText: string) {
    this.setData({
      shareCodeTitle: title,
      shareCodeText: text,
      shareCodeCopyText: copyText || '复制',
      showShareCodeSheet: true,
      showManage: false,
      _dialogFromManage: this.data.showManage,
      sheetDragStyle: '',
    });
  },

  openInputSheet(
    action: 'joinFamily' | 'createRoom' | 'bindShare' | 'renameRoom',
    title: string,
    placeholder: string,
    value?: string,
    targetId?: string,
  ) {
    this.setData({
      showInputSheet: true,
      inputSheetAction: action,
      inputSheetTitle: title,
      inputSheetPlaceholder: placeholder,
      inputSheetValue: value || '',
      inputSheetTargetId: targetId || '',
      showManage: false,
      _dialogFromManage: this.data.showManage,
    });
  },

  onInputSheetInput(e: WechatMiniprogram.Input) {
    this.setData({ inputSheetValue: e.detail.value });
  },

  closeInputSheet() {
    this.setData({ showInputSheet: false, ...this._resumeFromDialog() });
  },

  confirmInputSheet() {
    const value = (this.data.inputSheetValue || '').trim();
    const action = this.data.inputSheetAction;
    if (action === 'joinFamily') {
      if (!value) {
        wx.showToast({ title: '邀请 Token 不能为空', icon: 'none' });
        return;
      }
      this.setData({ showInputSheet: false, ...this._resumeFromDialog() });
      this.doJoinFamily(value);
    } else if (action === 'createRoom') {
      if (!value) {
        wx.showToast({ title: '房间名称不能为空', icon: 'none' });
        return;
      }
      this.setData({ showInputSheet: false, ...this._resumeFromDialog() });
      this.doCreateRoom(value);
    } else if (action === 'renameRoom') {
      if (!value) {
        wx.showToast({ title: '房间名称不能为空', icon: 'none' });
        return;
      }
      const roomId = this.data.inputSheetTargetId;
      this.setData({ showInputSheet: false, inputSheetTargetId: '', ...this._resumeFromDialog() });
      this.doRenameRoom(roomId, value);
    } else if (action === 'bindShare') {
      // 与分享码生成方式保持一致：解析 JSON 分享码 {productId, deviceName, token}
      let productId = '';
      let deviceName = '';
      let shareToken = '';
      try {
        const obj = JSON.parse(value.trim()) as {
          productId?: string;
          deviceName?: string;
          token?: string;
          shareToken?: string;
        };
        productId = String(obj.productId || '').trim();
        deviceName = String(obj.deviceName || '').trim();
        shareToken = String(obj.token || obj.shareToken || '').trim();
      } catch (e) {
        wx.showToast({ title: '分享码格式不正确', icon: 'none' });
        return;
      }
      if (!productId || !deviceName || !shareToken) {
        wx.showToast({ title: '分享码格式不正确', icon: 'none' });
        return;
      }
      this.setData({ showInputSheet: false, ...this._resumeFromDialog() });
      this.doBindShare(productId, deviceName, shareToken);
    }
  },

  openConfirmSheet(
    action: 'removeMember' | 'removeRoom' | 'quitFamily',
    title: string,
    msg: string,
    id: string,
    confirmText?: string,
  ) {
    this.setData({
      showConfirmSheet: true,
      confirmSheetAction: action,
      confirmSheetTitle: title,
      confirmSheetMsg: msg,
      confirmSheetId: id || '',
      confirmSheetConfirmText: confirmText || '删除',
      showManage: false,
      _dialogFromManage: this.data.showManage,
    });
  },

  closeConfirmSheet() {
    this.setData({ showConfirmSheet: false, ...this._resumeFromDialog() });
  },

  confirmConfirmSheet() {
    const action = this.data.confirmSheetAction;
    const id = this.data.confirmSheetId;
    this.setData({ showConfirmSheet: false, ...this._resumeFromDialog() });
    if (action === 'removeMember') {
      this.doRemoveMember(id);
    } else if (action === 'removeRoom') {
      this.doRemoveRoom(id);
    } else if (action === 'quitFamily') {
      this.doQuitFamily(id);
    }
  },

  confirmFamilyEdit() {
    const name = (this.data.familyEditName || '').trim();
    if (!name) {
      wx.showToast({ title: '家庭名称不能为空', icon: 'none' });
      return;
    }
    if (this.data.familyEditMode === 'rename') {
      this.doRenameFamily(name);
    } else {
      this.doCreateFamily(name);
    }
  },

  doRenameFamily(name: string) {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      this.setData({ showFamilyEdit: false, ...this._resumeFromDialog() });
      return;
    }
    if (name === cur.name) {
      this.setData({ showFamilyEdit: false, ...this._resumeFromDialog() });
      return;
    }
    wx.showLoading({ title: '修改中...', mask: true });
    updateFamilyInfo(cur.id, name)
      .then(() => getFamilyList())
      .then((families) => {
        const target =
          families.find((f) => f.id === cur.id) || { id: cur.id, name };
        this.setData({
          families,
          currentFamily: target,
          showFamilyEdit: false,
          ...this._resumeFromDialog(),
        });
        wx.hideLoading();
        wx.showToast({ title: '已修改', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] updateFamilyInfo failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '修改家庭名称失败',
          icon: 'none',
        });
      })
  },

  doCreateFamily(name: string) {
    wx.showLoading({ title: '创建中...', mask: true });
    createFamily(name)
      .then((newFamily) => {
        // 拉一次最新列表，保证和服务端一致；并切到新家庭
        return getFamilyList().then((families) => {
          const target =
            families.find((f) => f.id === newFamily.id) || newFamily;
          this.setData({
            families,
            currentFamily: target,
            devices: [],
            showFamilyEdit: false,
            ...this._resumeFromDialog(),
          });
          return getDeviceList(target.id).then((devices) => {
            this.setData({ devices });
            // 管理面板恢复显示时，刷新其当前 tab 数据（家庭已切换）
            if (this.data.showManage) {
              this.loadActiveTabData();
            }
          });
        });
      })
      .then(() => {
        wx.hideLoading();
        wx.showToast({ title: '已创建', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] createFamily failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '创建家庭失败',
          icon: 'none',
        });
      })
  },

  onDeleteFamily() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    this.setData({
      showFamilyMenu: false,
      showManage: false,
      _dialogFromManage: this.data.showManage,
      showFamilyDelete: true,
    });
  },

  closeFamilyDelete() {
    this.setData({ showFamilyDelete: false, ...this._resumeFromDialog() });
  },

  confirmFamilyDelete() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      this.setData({ showFamilyDelete: false, ...this._resumeFromDialog() });
      return;
    }
    this.setData({ showFamilyDelete: false, ...this._resumeFromDialog() });
    wx.showLoading({ title: '删除中...', mask: true });
    deleteFamily(cur.id)
      .then(() => getFamilyList())
      .then((families) => {
        if (families.length === 0) {
          this.setData({
            families: [],
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            currentFamily: { id: '', name: '请先创建家庭' } as any,
            devices: [],
          });
          return;
        }
        // 切到列表里的第一个家庭，并拉其设备
        const next = families[0];
        this.setData({
          families,
          currentFamily: next,
          devices: [],
        });
        return getDeviceList(next.id).then((devices) => {
          this.setData({ devices });
          // 管理面板恢复显示时，刷新其当前 tab 数据（家庭已切换）
          if (this.data.showManage) {
            this.loadActiveTabData();
          }
        });
      })
      .then(() => {
        wx.hideLoading();
        wx.showToast({ title: '已删除', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] deleteFamily failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '删除家庭失败',
          icon: 'none',
        });
      })
  },

  // 成员管理
  onCreateInvite() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '生成中...', mask: true });
    createFamilyInviteToken(cur.id)
      .then((token) => {
        wx.hideLoading();
        if (!token) {
          wx.showToast({ title: '生成邀请失败', icon: 'none' });
          return;
        }
        this.openCodeSheet('邀请码', token, '复制邀请码');
      })
      .catch((err: Error) => {
        wx.hideLoading();
        console.error('[device] createFamilyInviteToken failed', err);
        wx.showToast({
          title: err.message || '生成邀请失败',
          icon: 'none',
        });
      });
  },

  onJoinFamily() {
    this.openInputSheet('joinFamily', '加入家庭', '请输入邀请 Token', '');
  },

  doJoinFamily(token: string) {
    wx.showLoading({ title: '加入中...', mask: true });
    joinFamilyAsMember(token)
      .then(() => getFamilyList())
      .then((families) => {
        // 加入后刷新家庭列表；若当前未选中任何家庭，默认选中第一个
        const cur = this.data.currentFamily;
        const next =
          (cur && cur.id && families.find((f) => f.id === cur.id)) ||
          families[0] ||
          null;
        this.setData({
          families,
          ...(next ? { currentFamily: next, devices: [] } : {}),
        });
        if (next) {
          return getDeviceList(next.id).then((devices) => {
            this.setData({ devices });
          });
        }
        return undefined;
      })
      .then(() => {
        wx.hideLoading();
        wx.showToast({ title: '已加入', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] joinFamilyAsMember failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '加入家庭失败',
          icon: 'none',
        });
      });
  },

  onRemoveMember(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    const member = this.data.members.find((m) => m.id === id);
    const userId = member ? member.userId || member.id : id;
    if (!userId) {
      wx.showToast({ title: '成员信息缺失', icon: 'none' });
      return;
    }
    this.openConfirmSheet(
      'removeMember',
      '移除成员',
      `确认移除成员「${member ? member.name : userId}」？`,
      id,
      '移除',
    );
  },

  doRemoveMember(id: string) {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) return;
    const member = this.data.members.find((m) => m.id === id);
    const userId = member ? member.userId || member.id : id;
    if (!userId) {
      wx.showToast({ title: '成员信息缺失', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '移除中...', mask: true });
    removeMemberFromFamily(cur.id, userId)
      .then(() => getMemberList(cur.id))
      .then((members) => {
        const myId = getCurrentUserId();
        this.setData({
          members: members.map((m) => ({ ...m, isSelf: !!myId && m.userId === myId })),
        });
        wx.hideLoading();
        wx.showToast({ title: '已移除', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] removeMemberFromFamily failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '移除成员失败',
          icon: 'none',
        });
      })
  },

  onQuitFamily(e: WechatMiniprogram.TouchEvent) {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    const id = (e.currentTarget.dataset as { id: string }).id;
    this.openConfirmSheet(
      'quitFamily',
      '退出家庭',
      `确认退出家庭「${cur.name}」？退出后将无法访问该家庭下的设备。`,
      id,
      '退出',
    );
  },

  doQuitFamily(id: string) {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) return;
    // 退出 = 把"自己"从家庭成员中移除
    const member = this.data.members.find((m) => m.id === id);
    const userId = getCurrentUserId() || (member ? member.userId : '');
    if (!userId) {
      wx.showToast({ title: '用户信息缺失', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '退出中...', mask: true });
    removeMemberFromFamily(cur.id, userId)
      .then(() => getFamilyList())
      .then((families) => {
        if (families.length === 0) {
          this.setData({
            families: [],
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            currentFamily: { id: '', name: '请先创建家庭' } as any,
            devices: [],
            members: [],
            showManage: false,
            showFamilyMenu: false,
          });
          wx.hideLoading();
          wx.showToast({ title: '已退出', icon: 'success' });
          return;
        }
        const next = families[0];
        this.setData({
          families,
          currentFamily: next,
          devices: [],
          members: [],
          showManage: false,
          showFamilyMenu: false,
        });
        wx.showToast({ title: '已退出', icon: 'success' });
        return getDeviceList(next.id).then((devices) => {
          if (this.data.currentFamily && this.data.currentFamily.id === next.id) {
            this.setData({ devices });
          }
        });
      })
      .catch((err: Error) => {
        console.error('[device] quitFamily failed', err);
        wx.hideLoading();
        wx.showToast({ title: err.message || '退出家庭失败', icon: 'none' });
      })
  },

  // 房间管理
  onCreateRoom() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    this.openInputSheet('createRoom', '新建房间', '请输入房间名称', '');
  },

  doCreateRoom(name: string) {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) return;
    wx.showLoading({ title: '创建中...', mask: true });
    createRoom(cur.id, name)
      .then(() => getRoomList(cur.id))
      .then((rooms) => {
        this.setData({ rooms: this._roomsWithCount(rooms) });
        wx.hideLoading();
        wx.showToast({ title: '已创建', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] createRoom failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '创建房间失败',
          icon: 'none',
        });
      })
  },

  // 打开房间设备管理弹窗：拉当前家庭设备，标记是否已属于该房间
  onManageRoom(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    const room = this.data.rooms.find((r) => r.id === id);
    wx.showLoading({ title: '加载中...', mask: true });
    getDeviceList(cur.id)
      .then((devices) => {
        const roomManageDevices = devices.map((d) => ({
          id: d.id,
          name: d.name,
          productId: d.productId || '',
          deviceName: d.deviceName || '',
          online: d.online,
          inRoom: !!d.roomId && d.roomId === id,
        }));
        this.setData({
          devices,
          showRoomManage: true,
          showManage: false,
          _dialogFromManage: this.data.showManage,
          roomManageRoom: { id, name: room ? room.name : '' },
          roomManageDevices,
        });
        wx.hideLoading();
      })
      .catch((err: Error) => {
        console.error('[device] onManageRoom getDeviceList failed', err);
        wx.hideLoading();
        wx.showToast({ title: err.message || '加载设备失败', icon: 'none' });
      })
  },

  // 勾选/取消勾选：把设备加入或移出当前房间
  toggleRoomDevice(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    const cur = this.data.currentFamily;
    const roomId = this.data.roomManageRoom.id;
    if (!cur || !cur.id || !roomId) return;
    const dev = this.data.roomManageDevices.find((d) => d.id === id);
    if (!dev) return;
    if (!dev.productId || !dev.deviceName) {
      wx.showToast({ title: '设备信息不完整', icon: 'none' });
      return;
    }
    const willAdd = !dev.inRoom;
    wx.showLoading({ title: '处理中...', mask: true });
    const action = willAdd
      ? addDeviceToRoom(cur.id, roomId, dev.productId, dev.deviceName)
      : removeDeviceFromRoom(cur.id, dev.productId, dev.deviceName);
    action
      .then(() => {
        const roomManageDevices = this.data.roomManageDevices.map((d) =>
          d.id === id ? { ...d, inRoom: willAdd } : d,
        );
        this.setData({ roomManageDevices });
        // 同步本地 devices 的 roomId，避免重开弹窗状态不一致
        const devices = this.data.devices.map((d) =>
          d.id === id ? { ...d, roomId: willAdd ? roomId : '' } : d,
        );
        this.setData({ devices });
        wx.hideLoading();
        wx.showToast({ title: willAdd ? '已加入' : '已移出', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] toggleRoomDevice failed', err);
        wx.hideLoading();
        wx.showToast({ title: err.message || '操作失败', icon: 'none' });
      })
  },

  closeRoomManage() {
    this.setData({
      showRoomManage: false,
      rooms: this._roomsWithCount(this.data.rooms),
      ...this._resumeFromDialog(),
    });
  },

  onRenameRoom(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    const room = this.data.rooms.find((r) => r.id === id);
    this.openInputSheet(
      'renameRoom',
      '房间改名',
      '请输入新的房间名称',
      room ? room.name : '',
      id,
    );
  },

  doRenameRoom(id: string, name: string) {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) return;
    if (!id) {
      wx.showToast({ title: '房间信息缺失', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '保存中...', mask: true });
    renameRoom(cur.id, id, name)
      .then(() => getRoomList(cur.id))
      .then((rooms) => {
        this.setData({ rooms: this._roomsWithCount(rooms) });
        wx.hideLoading();
        wx.showToast({ title: '已保存', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] renameRoom failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '房间改名失败',
          icon: 'none',
        });
      })
  },

  onRemoveRoom(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    const room = this.data.rooms.find((r) => r.id === id);
    this.openConfirmSheet(
      'removeRoom',
      '删除房间',
      `确认删除房间「${room ? room.name : id}」？`,
      id,
      '删除',
    );
  },

  doRemoveRoom(id: string) {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) return;
    wx.showLoading({ title: '删除中...', mask: true });
    deleteRoom(cur.id, id)
      .then(() => getRoomList(cur.id))
      .then((rooms) => {
        this.setData({ rooms: this._roomsWithCount(rooms) });
        wx.hideLoading();
        wx.showToast({ title: '已删除', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] deleteRoom failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '删除房间失败',
          icon: 'none',
        });
      })
  },

  // 分享
  onCreateShare() {
    const cur = this.data.currentFamily;
    if (!cur || !cur.id) {
      wx.showToast({ title: '请先选择家庭', icon: 'none' });
      return;
    }
    // 优先用用户在分享 tab 顶部选中的 shareDevice；
    // 若未选中则尝试取当前家庭第一台真实设备
    const sd = this.data.shareDevice;
    const matched =
      this.data.devices.find((d) => d.id === sd.id) ||
      this.data.devices[0];
    const productId = sd.productId || (matched && matched.productId) || '';
    const deviceName = sd.deviceName || (matched && matched.deviceName) || '';
    if (!productId || !deviceName) {
      wx.showToast({ title: '请先选择要分享的设备', icon: 'none' });
      return;
    }
    wx.showLoading({ title: '生成中...', mask: true });
    createDeviceSharingToken(cur.id, productId, deviceName)
      .then((token) => {
        wx.hideLoading();
        if (!token) {
          wx.showToast({ title: '生成分享失败', icon: 'none' });
          return;
        }
        // 与设备列表 item menu 的分享保持一致：输出含 productId/deviceName/token 的分享码
        const codeText = JSON.stringify({
          productId,
          deviceName,
          token,
        });
        this.openCodeSheet('设备分享码', codeText, '复制分享码');
      })
      .catch((err: Error) => {
        wx.hideLoading();
        console.error('[device] createDeviceSharingToken failed', err);
        wx.showToast({
          title: err.message || '生成分享失败',
          icon: 'none',
        });
      });
  },

  onBindShare() {
    this.openInputSheet(
      'bindShare',
      '绑定分享',
      '请粘贴对方的设备分享码',
      '',
    );
  },

  doBindShare(productId: string, deviceName: string, shareToken: string) {
    wx.showLoading({ title: '绑定中...', mask: true });
    bindDeviceSharedWithMe(productId, deviceName, shareToken)
      .then(() => getDeviceListSharedWithMe())
      .then((list) => {
        const sharedToMe: ShareItem[] = list.map((d) => ({
          id: d.id,
          name: d.name,
          productId: d.productId,
          deviceName: d.deviceName,
          online: d.online,
        }));
        this.setData({ sharedToMe });
        wx.hideLoading();
        wx.showToast({ title: '已绑定', icon: 'success' });
      })
      .catch((err: Error) => {
        console.error('[device] bindDeviceSharedWithMe failed', err);
        wx.hideLoading();
        wx.showToast({
          title: err.message || '绑定分享失败',
          icon: 'none',
        });
      })
  },

  /**
   * "撤销分享"按钮：解绑所有分享给我的设备
   */
  onRevokeShareBtn() {
    const { sharedToMe } = this.data;
    if (sharedToMe.length === 0) {
      wx.showToast({ title: '暂无分享给您的设备', icon: 'none' });
      return;
    }
    wx.showModal({
      title: '撤销分享',
      content: `确认解绑全部 ${sharedToMe.length} 个分享给您的设备？`,
      confirmColor: '#ff4757',
      success: async (r) => {
        if (!r.confirm) return;
        wx.showLoading({ title: '解绑中...', mask: true });
        try {
          for (const item of sharedToMe) {
            const productId = item.productId || '';
            const deviceName = item.deviceName || '';
            if (productId && deviceName) {
              await unbindDeviceSharedWithMe(productId, deviceName);
            }
          }
          // 刷新列表
          const list = await getDeviceListSharedWithMe();
          const nextSharedToMe: ShareItem[] = list.map((d) => ({
            id: d.id,
            name: d.name,
            productId: d.productId,
            deviceName: d.deviceName,
            online: d.online,
          }));
          this.setData({ sharedToMe: nextSharedToMe });
          wx.hideLoading();
          wx.showToast({ title: '已解绑', icon: 'success' });
        } catch (err) {
          const error = err as Error;
          console.error('[device] onRevokeShareBtn failed', error, error && error.stack);
          wx.hideLoading();
          wx.showToast({ title: error.message || '解绑失败', icon: 'none' });
        }
      },
    });
  },

  onRevokeShare(e: WechatMiniprogram.TouchEvent) {
    const id = (e.currentTarget.dataset as { id: string }).id;
    // 判断该 id 属于哪一侧：
    //   - sharedByMe：设备主撤销某个被分享用户 → removeDeviceSharedUser
    //   - sharedToMe：被分享方主动解绑分享给我的设备 → unbindDeviceSharedWithMe
    const byMeItem = this.data.sharedByMe.find((s) => s.id === id);
    if (byMeItem) {
      const productId = byMeItem.productId || '';
      const deviceName = byMeItem.deviceName || '';
      const userId = byMeItem.userId || '';
      if (!productId || !deviceName || !userId) {
        wx.showToast({ title: '分享信息缺失', icon: 'none' });
        return;
      }
      wx.showModal({
        title: '撤销分享',
        content: `确认撤销「${byMeItem.name || deviceName}」对用户「${byMeItem.userName || userId
          }」的分享？`,
        confirmColor: '#ff4757',
        success: (r) => {
          if (!r.confirm) return;
          wx.showLoading({ title: '撤销中...', mask: true });
          removeDeviceSharedUser(productId, deviceName, userId)
            .then(() => {
              this.setData({
                sharedByMe: this.data.sharedByMe.filter((s) => s.id !== id),
              });
              wx.hideLoading();
              wx.showToast({ title: '已撤销', icon: 'success' });
            })
            .catch((err: Error) => {
              console.error('[device] removeDeviceSharedUser failed', err, err && (err as Error).stack);
              wx.hideLoading();
              wx.showToast({
                title: err.message || '撤销分享失败',
                icon: 'none',
              });
            })
        },
      });
      return;
    }

    // sharedToMe：解绑别人分享给我的设备
    const toMeItem = this.data.sharedToMe.find((s) => s.id === id);
    if (!toMeItem) return;
    const productId = toMeItem.productId || '';
    const deviceName = toMeItem.deviceName || '';
    if (!productId || !deviceName) {
      wx.showToast({ title: '分享信息缺失', icon: 'none' });
      return;
    }
    wx.showModal({
      title: '撤销分享',
      content: `确认撤销设备「${toMeItem.name || deviceName}」的分享？`,
      confirmColor: '#ff4757',
      success: (r) => {
        if (!r.confirm) return;
        wx.showLoading({ title: '撤销中...', mask: true });
        unbindDeviceSharedWithMe(productId, deviceName)
          .then(() => getDeviceListSharedWithMe())
          .then((list) => {
            const sharedToMe: ShareItem[] = list.map((d) => ({
              id: d.id,
              name: d.name,
              productId: d.productId,
              deviceName: d.deviceName,
              online: d.online,
            }));
            this.setData({ sharedToMe });
            wx.hideLoading();
            wx.showToast({ title: '已撤销', icon: 'success' });
          })
          .catch((err: Error) => {
            console.error('[device] unbindDeviceSharedWithMe failed', err, err && err.stack);
            wx.hideLoading();
            wx.showToast({
              title: err.message || '撤销分享失败',
              icon: 'none',
            });
          })
      },
    });
  },
});
