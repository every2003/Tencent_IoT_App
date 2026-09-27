// 通过 demo 封装 utils/iotEngine 获取 IoT Engine 实例
import { getIoTEngine, createDeviceSharingToken } from '../../utils/iotEngine';
function getEngine() {
  return getIoTEngine();
}

/** 真机 onLoad 的 query 不会自动解码（开发者工具会），统一安全解码 */
function decodeParam(v: string): string {
  if (!v) return v;
  try {
    return decodeURIComponent(v);
  } catch (_) {
    return v;
  }
}

const STREAM_HD = 0;
const STREAM_SD = 1;

function channelCellStyle(index: number, count: number): string {
  const base = 'position:absolute;';
  if (count <= 1) {
    return base + 'left:0;top:0;width:100%;height:100%;';
  }
  if (count === 2) {
    return base + `left:${index * 50}%;top:0;width:50%;height:100%;`;
  }
  const col = index % 2;
  const row = Math.floor(index / 2);
  return base + `left:${col * 50}%;top:${row * 50}%;width:50%;height:50%;`;
}

interface PreviewData {
  statusBarHeight: number;
  navBarHeight: number;
  title: string;
  channelLabel: string;
  channels: number[];
  currentChannel: number;
  speakerOn: boolean;
  isHighQuality: boolean;
  intercomActive: boolean;
  loading: boolean;
  errorMsg: string;
  productId: string;
  deviceName: string;
  familyId: string;
  remotePlayers: Array<{ channelId: number; componentId: string; style: string }>;
  shareVisible: boolean;
  shareCode: string;
  shareLoading: boolean;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type MonitorSession = any;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const pageObj: WechatMiniprogram.Page.Options<PreviewData, WechatMiniprogram.IAnyObject> & { _monitorSession: MonitorSession; _monitorSessionListener: any } = {
  _monitorSession: null as MonitorSession,
  _monitorSessionListener: null,

  data: {
    statusBarHeight: 20,
    navBarHeight: 44,
    title: 'ota_test/trtc_test_eagle',
    channelLabel: '单通道',
    channels: [1],
    currentChannel: 1,
    speakerOn: true,
    isHighQuality: true,
    intercomActive: false,
    loading: true,
    errorMsg: '错误：设备未连接',
    productId: '',
    deviceName: '',
    familyId: '',
    remotePlayers: [],
    shareVisible: false,
    shareCode: '',
    shareLoading: false,
  },

  onLoad(query: Record<string, string>) {
    const sys = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
    const menu = wx.getMenuButtonBoundingClientRect();
    const statusBarHeight = sys.statusBarHeight || 20;
    const gap = menu.top - statusBarHeight;
    const navBarHeight = menu.height + gap * 2;

    const type = query.type || 'single';
    const name = decodeParam(query.name || '') || 'trtc_test_eagle';
    const channelsStr = query.channels || '1';
    const channels = channelsStr
      .split(',')
      .filter((s) => s !== '')
      .map((x) => Number(x))
      .filter((x) => Number.isFinite(x));
    const channelLabel = type === 'multi' ? '多通道' : '单通道';
    const productId = decodeParam(query.productId || '');
    const deviceName = decodeParam(query.deviceName || '') || name;
    const familyId = query.familyId || '';

    this.setData({
      statusBarHeight,
      navBarHeight,
      title: (productId || 'ota_test') + '/' + deviceName,
      channelLabel,
      channels: channels.length ? channels : [1],
      currentChannel: channels.length ? channels[0] : 1,
      productId,
      deviceName,
      familyId,
    });

    this._startMediaSession(productId, deviceName);
  },

  onUnload() {
    this._stopMediaSession();
  },

  async _startMediaSession(productId: string, deviceName: string) {
    if (!productId || !deviceName) {
      this.setData({ loading: false, errorMsg: '错误：设备信息不完整' });
      return;
    }
    // getEngine() 返回 Promise<TXIoTEngine>，需先 await 拿到实例再调用 getMonitorSession()
    let engine: any;
    try {
      engine = await getEngine();
    } catch (e) {
      console.error('[preview] getEngine failed:', e);
      this.setData({ loading: false, errorMsg: '错误：引擎初始化失败' });
      return;
    }
    const session = engine.getMonitorSession();
    this._monitorSession = session;
    if (this._monitorSessionListener) {
      try { this._monitorSession.removeListener(this._monitorSessionListener); } catch (_e) { /* ignore */ }
    }
    this._monitorSessionListener = {
      onSessionEstablished: () => {
        console.info('[preview] session established');
        this.setData({ loading: false, errorMsg: '' });
      },
      onSessionRecovery: () => {
        console.info('[preview] session recovered');
        this.setData({ loading: false, errorMsg: '' });
      },
      onSessionReconnecting: () => {
        console.info('[preview] session reconnecting...');
        this.setData({ loading: true });
      },
      onRenderFirstFrame: (channelId: number) => {
        console.info('[preview] first frame rendered, channel:', channelId);
        this.setData({ loading: false });
      },
      onError: (_channelId: number, code: number, msg: string) => {
        console.error('[preview] session error:', code, msg);
        wx.showToast({ title: msg, icon: 'none' });
        this.setData({ loading: false, errorMsg: '错误：' + (msg || code) });
      },
      onRemoteStreamAvailable: (channelId: number, available: boolean) => {
        console.info('[preview] onRemoteStreamAvailable:', channelId, ', available:', available);
        this._addOrRefreshRemotePlayer(channelId);
      },
      onSnapshotComplete: (channelId: number, filePath: string) => {
        console.info('[preview] onSnapshotComplete:', channelId, ' filePath:', filePath);
        wx.saveImageToPhotosAlbum({
          filePath: filePath,
          success() {
            wx.showToast({ title: '已保存到相册', icon: 'success' });
          },
          fail(err) {
            if (err.errMsg && err.errMsg.indexOf('auth deny') >= 0) {
              wx.showModal({
                title: '需要相册权限',
                content: '请在设置中允许小程序访问相册',
                success(res) {
                  if (res.confirm) wx.openSetting();
                }
              });
            } else {
              console.error('保存失败', err);
              wx.showToast({ title: '保存失败', icon: 'none' });
            }
          }
        });
      },
    };
    this._monitorSession.addListener(this._monitorSessionListener);
    this._startAllRemoteViews(productId, deviceName);
  },

  _startAllRemoteViews(productId: string, deviceName: string) {
    if (!this._monitorSession) return;
    const channels = this.data.channels;
    const st = this.data.isHighQuality ? STREAM_HD : STREAM_SD;
    const start = () => {
      if (this._monitorSession) {
        this._monitorSession.startSession({ productId, deviceName }, this);
      }
    };
    if (!channels || channels.length === 0) {
      start();
      return;
    }
    const count = channels.length;
    // 一次性创建所有通道的 player（含分屏样式），避免循环内多次 setData
    const players = channels.map((ch, idx) => ({
      channelId: ch,
      componentId: 'iot-player-' + ch,
      style: channelCellStyle(idx, count),
    }));
    this.setData({ remotePlayers: players }, () => {
      wx.nextTick(() => {
        if (!this._monitorSession) return;
        for (const p of players) {
          this._monitorSession.setIoTPlayer(p.channelId, p.componentId);
          this._monitorSession.startRemoteView(p.channelId, st);
        }
        start();
      });
    });
  },

  _stopMediaSession() {
    if (this._monitorSession) {
      // 摘掉本页面实例注册的监听器，避免 monitorSession 单例上累积（导致 1 张截图回调 N 次）
      if (this._monitorSessionListener) {
        try { this._monitorSession.removeListener(this._monitorSessionListener); } catch (_e) { /* ignore */ }
        this._monitorSessionListener = null;
      }
      try {
        this._monitorSession.stopSession();
      } catch (e) { /* ignore */ }
      this._monitorSession = null;
    }
    this.setData({ remotePlayers: [], loading: true, errorMsg: '' });
  },

  _addOrRefreshRemotePlayer(channelId: number) {
    if (!this._monitorSession) {
      console.warn('[preview] _addOrRefreshRemotePlayer: session destroyed');
      return;
    }
    const existed = this.data.remotePlayers.find((p) => p.channelId === channelId);
    if (existed) {
      console.info('[preview] channel already exists:', channelId, 'componentId:', existed.componentId);
      return;
    }

    const componentId = 'iot-player-' + channelId;
    console.info('[preview] add channel:', channelId, 'componentId:', componentId);
    const nextPlayers = [...this.data.remotePlayers, { channelId, componentId, style: '' }];
    const nextCount = nextPlayers.length;
    nextPlayers.forEach((p, idx) => { p.style = channelCellStyle(idx, nextCount); });
    this.setData({ remotePlayers: nextPlayers }, () => {
      wx.nextTick(() => {
        if (!this._monitorSession) return;
        this._monitorSession.setIoTPlayer(channelId, componentId);
        this._monitorSession.startRemoteView(channelId, this.data.isHighQuality ? STREAM_HD : STREAM_SD);
      });
    });
  },

  onBack() {
    wx.navigateBack({ delta: 1 });
  },

  onSwitchChannel() {
    if (this.data.channels.length <= 1) return;
    const idx = this.data.channels.indexOf(this.data.currentChannel);
    const next = this.data.channels[(idx + 1) % this.data.channels.length];
    this.setData({ currentChannel: next });
    wx.showToast({ title: '已切换到通道 ' + next, icon: 'none' });
  },

  toggleSpeaker() {
    this.setData({ speakerOn: !this.data.speakerOn });
    if (this._monitorSession) {
      this._monitorSession.muteAllRemoteAudio(!this.data.speakerOn);
    }
    wx.showToast({ title: this.data.speakerOn ? '已开声音' : '已静音', icon: 'none' });
  },

  toggleQuality() {
    // 对齐 iOS toggleQuality：切换 HD/SD，对所有正在播放的通道下发 switchRemoteStream。
    const isHighQuality = !this.data.isHighQuality;
    this.setData({ isHighQuality });
    const streamType = isHighQuality ? STREAM_HD : STREAM_SD;
    if (this._monitorSession) {
      for (const p of this.data.remotePlayers) {
        try {
          this._monitorSession.switchRemoteStream(p.channelId, streamType);
        } catch (e) {
          console.error('[preview] switchRemoteStream failed:', p.channelId, e);
        }
      }
    }
    wx.showToast({ title: isHighQuality ? '已切换为高清' : '已切换为标清', icon: 'none' });
  },

  onIntercom() {
    const active = !this.data.intercomActive;
    this.setData({ intercomActive: active });

    // 对齐 iOS toggleTalk：对讲只开/关本地音频，不开启本地视频。
    if (this._monitorSession) {
      if (active) {
        this._monitorSession.startLocalAudio();
      } else {
        this._monitorSession.stopLocalAudio();
      }
    }

    wx.showToast({
      title: active ? '对讲已开启' : '对讲已关闭',
      icon: 'none',
    });
  },

  onSnapshot() {
    if (!this._monitorSession) return;
    // 每个通道都截：串行 takeSnapshot（间隔 0.5s），避免 SDK 并发调用被吞。
    const channels = this.data.remotePlayers.map((p) => p.channelId);
    if (channels.length === 0) {
      wx.showToast({ title: '暂无可截图通道', icon: 'none' });
      return;
    }
    this._takeSnapshotForChannel(0, channels);
  },

  _takeSnapshotForChannel(index: number, channels: number[]) {
    if (index >= channels.length || !this._monitorSession) return;
    this._monitorSession.takeSnapshot(channels[index]);
    if (index + 1 < channels.length) {
      setTimeout(() => this._takeSnapshotForChannel(index + 1, channels), 500);
    }
  },

  onDirection(e: WechatMiniprogram.TouchEvent) {
    const dir = (e.currentTarget.dataset as { dir: string }).dir;
    // UP=0 DOWN=1 LEFT=2 RIGHT=3 ZOOM_IN=4 ZOOM_OUT=5 STOP=6
    const cmdMap: Record<string, number> = {
      up: 0,
      down: 1,
      left: 2,
      right: 3,
    };
    const cmd = cmdMap[dir];

    if (cmd === undefined) {
      wx.showToast({ title: '复位', icon: 'none' });
      return;
    }

    if (!this._monitorSession) {
      console.warn('[preview] PTZ: monitorSession not available');
      return;
    }

    const channelId = this.data.currentChannel;
    try {
      this._monitorSession.sendPTZCommand(channelId, cmd, 5);
      console.info('[preview] PTZ:', dir, 'channelId=', channelId, 'cmd=', cmd);
    } catch (err) {
      console.error('[preview] PTZ failed:', err);
    }
  },

  async onShare() {
    if (this.data.shareLoading) return;
    const { productId, deviceName } = this.data;
    if (!productId || !deviceName) {
      wx.showToast({ title: '设备信息缺失', icon: 'none' });
      return;
    }
    let familyId = this.data.familyId;
    if (!familyId) {
      const pages = getCurrentPages();
      for (let i = pages.length - 2; i >= 0; i--) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const p = pages[i] as any;
        if (p && p.data && p.data.currentFamily && p.data.currentFamily.id) {
          familyId = p.data.currentFamily.id;
          break;
        }
      }
    }
    if (!familyId) {
      wx.showToast({ title: '未找到家庭', icon: 'none' });
      return;
    }

    this.setData({ shareLoading: true });
    wx.showLoading({ title: '生成分享码...', mask: true });
    try {
      const token = await createDeviceSharingToken(familyId, productId, deviceName);
      if (!token) {
        throw new Error('token 为空');
      }
      const shareCode = JSON.stringify({ productId, deviceName, token }, null, 2);
      wx.hideLoading();
      this.setData({ shareVisible: true, shareCode });
    } catch (e) {
      wx.hideLoading();
      console.error('[preview] createDeviceSharingToken failed:', e);
      wx.showToast({ title: '生成分享码失败', icon: 'none' });
    } finally {
      this.setData({ shareLoading: false });
    }
  },

  onCloseShare() {
    this.setData({ shareVisible: false });
  },

  onCopyShare() {
    if (!this.data.shareCode) return;
    wx.setClipboardData({
      data: this.data.shareCode,
      success: () => {
        wx.showToast({ title: '分享码已复制', icon: 'success' });
      },
    });
  },
};

Page(pageObj);
