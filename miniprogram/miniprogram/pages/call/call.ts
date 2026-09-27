// 通话页：语音 / 视频
// query: mode=audio|video, productId, deviceName, name

import { getIoTEngine } from '../../utils/iotEngine';
import type { TXIoTCallUser, TXIoTCallSession, TXIoTDeviceId } from '../../../typings/tx-iot-sdk';

type CallMode = 'audio' | 'video';
// ringing：被叫响铃中（用户尚未点击接听）
// connecting：主叫已发起 / 被叫接听后等待 RTC 通道
// connected：通话中
// ended：已结束
type CallPhase = 'ringing' | 'connecting' | 'connected' | 'ended';

/** call场景固定只有一个远端设备，统一用固定 componentId，与 <iot-player component-id> 对齐 */
const CALL_REMOTE_COMPONENT_ID = 'iot-player-call-0';

// 与 SDK TXIoTCallSession::TXIoTCallEndReason 保持一致，用于区分 onCallEnd 的挂断原因，
// 避免本端主动挂断（侧滑退出 / 点击挂断按钮）时被误判为「对方已挂断」。
enum CallEndReason {
  Unknown = 0,
  LocalHangup = 1,
  RemoteHangup = 2,
  CallPermissionDenied = 3,
  NetworkError = 4,
}

interface CallEngineLike {
  awaitCallSession?: () => Promise<TXIoTCallSession>;
  getCallSession?: () => TXIoTCallSession | null;
}

const fmtCallTime = (s: number): string => {
  const mm = String(Math.floor(s / 60)).padStart(2, '0');
  const ss = String(s % 60).padStart(2, '0');
  return mm + ':' + ss;
};

Page({
  data: {
    statusBarHeight: 20,
    navBarHeight: 44,

    productId: '',
    deviceName: '',
    name: 'device',

    mode: 'audio' as CallMode,
    phase: 'connecting' as CallPhase,
    /** 是否被叫响铃流程（query.incoming === '1'） */
    isIncoming: false,

    seconds: 0,
    timerText: '',
    statusText: '等待对方接受邀请..',

    micEnabled: true,
    speakerEnabled: true, // 语音 / 视频通话统一默认开启扬声器
    cameraEnabled: false,
    cameraFront: true,
    /** 视频响铃 UI：模糊背景占位状态（SDK 暂无虚拟背景接口） */
    bgBlur: false,
  },

  // 私有字段（不进 setData）
  _timer: 0 as number,
  _session: null as TXIoTCallSession | null,
  _ended: false,

  onLoad(query: Record<string, string | undefined>) {
    const mode: CallMode = query && query.mode === 'video' ? 'video' : 'audio';
    const productId = decodeURIComponent((query && query.productId) || '');
    const deviceName = decodeURIComponent((query && query.deviceName) || '');
    // 通话页（响铃 / 通话中）统一展示名称：与主动拨打、被叫接听保持一致
    // 暂按需求固定为 'rocky_video'，后续如要走真实昵称改回：
    //   const rawName = decodeURIComponent((query && query.name) || '');
    //   const name = rawName || deviceName || 'device';
    const name = 'rocky_video';
    const isIncoming = !!(query && query.incoming === '1');
    // accepted=1：横幅上已点过「接听」，直接进 connecting，跳过 ringing UI
    const acceptedFromBanner = !!(query && query.accepted === '1');
    const initialPhase: CallPhase = isIncoming && !acceptedFromBanner ? 'ringing' : 'connecting';

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sys = (wx as any).getWindowInfo ? (wx as any).getWindowInfo() : wx.getSystemInfoSync();
    const menu = wx.getMenuButtonBoundingClientRect();
    const statusBarHeight = sys.statusBarHeight || 20;
    const navBarHeight = (menu.top - statusBarHeight) * 2 + menu.height;

    this.setData({
      mode,
      productId,
      deviceName,
      name,
      isIncoming,
      phase: initialPhase,
      speakerEnabled: true,
      cameraEnabled: mode === 'video',
      statusBarHeight,
      navBarHeight,
      statusText:
        isIncoming && !acceptedFromBanner
          ? mode === 'video'
            ? '邀请你视频通话.'
            : '邀请你语音通话…'
          : acceptedFromBanner
            ? '连接中..'
            : '等待对方接受邀请..',
    });

    try {
      wx.setKeepScreenOn({ keepScreenOn: true });
    } catch (e) {}

    if (!productId || !deviceName) {
      wx.showToast({ title: '设备信息缺失', icon: 'none' });
      setTimeout(() => wx.navigateBack({ delta: 1 }), 800);
      return;
    }

    // 主叫 OR 横幅已点接听：立即发起 RTC
    // 被叫且未接听（停留在 ringing UI）：等用户在响铃页点击「接听」后再发起
    if (!isIncoming || acceptedFromBanner) {
      this._startCall();
    }
  },

  onUnload() {
    this._clearTimer();
    try {
      wx.setKeepScreenOn({ keepScreenOn: false });
    } catch (e) {}
    this._stopCall();
  },

  _getEngine(): CallEngineLike | null {
    try {
      return getIoTEngine() as unknown as CallEngineLike | null;
    } catch (e) {
      return null;
    }
  },

  _startCall() {
    const self = this;
    getIoTEngine()
      .then((engine: unknown) => {
        const eng = engine as unknown as CallEngineLike;
        if (!eng || typeof eng.getCallSession !== 'function') {
          console.warn('[call] no call session available');
          return;
        }
        const cs = eng.getCallSession();
        if (!cs) {
          console.warn('[call] getCallSession returned null');
          return;
        }
        self._session = cs;
        cs.addListener({
          onCallBegin: () => self._onConnected(),
          onCallEnd: (...args: unknown[]) => self._onCallEnd(args[1] as number | undefined),
          onCallRejected: () => self._onRemoteEnded('对方已拒绝'),
          onCallNoResponse: () => self._onRemoteEnded('无人接听'),
          onCallUserOffline: () => self._onRemoteEnded('设备不在线'),
          onCallLineBusy: () => self._onRemoteEnded('对方忙线中'),
          onCallUserAudioAvailable: (...args: unknown[]) => console.log('[call] audio available', args),
          onCallUserVideoAvailable: (...args: unknown[]) => console.log('[call] video available', args),
          onError: (...args: unknown[]) => console.warn('[call] error', args),
        } as Record<string, (...args: unknown[]) => void>);

        const deviceId: TXIoTDeviceId = { productId: self.data.productId, deviceName: self.data.deviceName };
        // SDK侧 setIoTPlayer/startRemoteView/stopRemoteView 收的是完整 TXIoTCallUser
        // （{ deviceId: {...} }），与 callDevice 直接收裸 deviceId 不同，这里单独包一层。
        const callUser: TXIoTCallUser = { deviceId };
        // 先把这次通话的对端 CallUser 与 <iot-player component-id> 绑定好，SDK 内部先存起来；
        // 再发起 callDevice。等拿到 TRTC 进房参数后，SDK 会把 componentId 一起带下来，
        // JS 层据此更新对应 player 的播放地址（不需要等对端真正进房）。
        try {
          if (typeof cs.setIoTPlayer === 'function') {
            cs.setIoTPlayer(callUser, CALL_REMOTE_COMPONENT_ID);
          }
        } catch (e) {
          console.warn('[call] setIoTPlayer fail', e);
        }

        cs.callDevice(deviceId, self.data.mode === 'video' ? 1 : 0);
        // 视频模式标记需要拉远端视图（用于接收对端音视频）
        try {
          if (typeof cs.startRemoteView === 'function') {
            cs.startRemoteView(callUser);
          }
        } catch (e) {
          console.warn('[call] startRemoteView fail', e);
        }
      })
      .catch((err: unknown) => {
        console.warn('[call] getIoTEngine failed', err);
      });
  },

  _stopCall() {
    try {
      if (this._session) {
        this._session.hangup();
      }
    } catch (e) {}
    this._session = null;
  },

  _onConnected() {
    if (this._ended) return;
    this.setData({ phase: 'connected', statusText: '' });
    this._startTimer();
    // 通话接通时按 UI 默认的麦克风开关状态主动启动本地音频采集。
    // 若不在这里显式调用 openMicrophone()，本地音频会话在接通后不会被激活，
    // 导致 selectAudioPlaybackDevice（扬声器/听筒切换）设置的音频路由无法立即生效，
    // 必须等用户手动切换一次麦克风开关（触发 StartLocalAudio）后才会生效。
    try {
      if (this._session && this.data.micEnabled) {
        this._session.openMicrophone();
      }
    } catch (e) {
      console.warn('[call] auto openMicrophone failed', e);
    }
    if (this.data.mode === 'video') {
      try {
        if (this._session) {
          this._session.openCamera(this.data.cameraFront ? 0 : 1);
        }
      } catch (e) {
        console.warn('[call] auto openCamera failed', e);
      }
    }
  },

  /**
   * SDK onCallEnd 回调统一处理：本端主动挂断（侧滑退出 / 点击挂断按钮触发的 hangup()）
   * 不应提示，其余 reason 按具体原因分别给出提示文案，不能一律当作「对方已挂断」
   * （例如网络异常 / 权限被拒 / 未知原因结束，与对方主动挂断是不同的场景）。
   */
  _onCallEnd(reason: number | undefined) {
    if (reason === CallEndReason.LocalHangup) {
      if (this._ended) return;
      this._ended = true;
      this._clearTimer();
      return;
    }
    this._onRemoteEnded(this._callEndReasonText(reason));
  },

  _callEndReasonText(reason: number | undefined): string {
    switch (reason) {
      case CallEndReason.RemoteHangup:
        return '对方已挂断';
      case CallEndReason.NetworkError:
        return '网络异常，通话结束';
      case CallEndReason.CallPermissionDenied:
        return '通话权限被拒绝';
      case CallEndReason.Unknown:
      default:
        return '通话意外结束';
    }
  },

  _onRemoteEnded(text: string) {
    if (this._ended) return;
    this._ended = true;
    this._clearTimer();
    wx.showToast({ title: text, icon: 'none', duration: 1500 });
    setTimeout(() => {
      try {
        wx.navigateBack({ delta: 1 });
      } catch (e) {}
    }, 1200);
  },

  _startTimer() {
    this._clearTimer();
    this._timer = setInterval(() => {
      const s = this.data.seconds + 1;
      this.setData({ seconds: s, timerText: fmtCallTime(s) });
    }, 1000) as unknown as number;
  },

  _clearTimer() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = 0;
    }
  },

  // ==== 控件交互 ====

  onToggleMic() {
    const next = !this.data.micEnabled;
    this.setData({ micEnabled: next });
    try {
      if (this._session) {
        if (next) this._session.openMicrophone();
        else this._session.closeMicrophone();
      }
    } catch (e) {}
  },

  onToggleSpeaker() {
    const next = !this.data.speakerEnabled;
    this.setData({ speakerEnabled: next });
    try {
      if (this._session) {
        // 0: SPEAKERPHONE 扬声器, 1: EARPIECE 听筒
        this._session.selectAudioPlaybackDevice(next ? 0 : 1);
      } else {
        wx.setInnerAudioOption && wx.setInnerAudioOption({ speakerOn: next });
      }
    } catch (e) {}
  },

  onToggleCamera() {
    const next = !this.data.cameraEnabled;
    this.setData({ cameraEnabled: next });
    try {
      if (this._session) {
        if (next) this._session.openCamera(this.data.cameraFront ? 0 : 1);
        else this._session.closeCamera();
      }
    } catch (e) {}
  },

  onSwitchCamera() {
    if (this.data.mode !== 'video') return;
    const front = !this.data.cameraFront;
    this.setData({ cameraFront: front });
    try {
      if (this._session) this._session.switchCamera(front ? 0 : 1);
    } catch (e) {}
  },

  onHangup() {
    this._stopCall();
    this._clearTimer();
    wx.navigateBack({ delta: 1 });
  },

  // ==== 被叫响铃：接听 / 拒绝 / 模糊背景占位 ====

  /** 响铃中点击「接听」：切到 connecting，启动 RTC。 */
  onAccept() {
    if (this.data.phase !== 'ringing') return;
    this.setData({ phase: 'connecting', statusText: '连接中..' });
    // 当前 SDK 暂未对外暴露"接受被叫邀请"接口；
    // 兼容方案：复用主叫 callDevice 触发 RTC 通道。等 SDK 暴露
    // `acceptCall(deviceId)` 后替换为对应调用。
    this._startCall();
  },

  /** 响铃中点击「拒绝」：返回上一页（不发起任何 RTC）。 */
  onReject() {
    // TODO: SDK 暴露 rejectCall 后调用 this._session?.rejectCall(...)
    this._stopCall();
    this._clearTimer();
    wx.navigateBack({ delta: 1 });
  },

  /** 响铃视频：切换"模糊背景"按钮态。SDK 暂无虚拟背景接口，仅做 UI 反馈。 */
  onToggleBgBlur() {
    this.setData({ bgBlur: !this.data.bgBlur });
  },

  /** <camera> 错误兜底（被叫视频响铃用本地预览） */
  onCameraError(e: unknown) {
    console.warn('[call] ringing camera error', e);
  },

  // ==== 顶部操作（小窗 / 加号），均为占位入口 ====

  /** 顶部「画中画」按钮：当前没有原生小窗 API，给 toast 占位。 */
  onMinimize() {
    // TODO: 接入小程序「悬浮窗」/ 后台保持通话能力时在此实现
    wx.showToast({ title: '小窗暂未支持', icon: 'none' });
  },

  /** 顶部「+」按钮：预留更多操作（邀请、录像等）。 */
  onMore() {
    wx.showActionSheet({
      itemList: ['邀请其它设备', '通话设置'],
      fail: () => {},
    });
  },

  // ==== 顶部操作（小窗 / 加号），均为占位入口 ====
});
