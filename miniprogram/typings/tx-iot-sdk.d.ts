// Type definitions for tx-iot-sdk plugin.
//
// 插件只导出底层 SDK 原始能力。业务侧 import iotPlugin from 'plugin://tx-iot-sdk' 后，
// 通过 iotPlugin.TXIoTEngine.getInstance() 拿到引擎单例，再获取各 Manager / Session。

// ============================ 基础数据类型 ============================

export interface TXIoTDeviceId {
  productId: string;
  deviceName: string;
}

export interface TXIoTDeviceStatus {
  isOnline: boolean;
  [k: string]: unknown;
}

export interface TXIoTDeviceInfo {
  deviceId: TXIoTDeviceId;
  aliasName?: string;
  iconUrl?: string;
  roomId?: string;
  status?: TXIoTDeviceStatus;
  [k: string]: unknown;
}

export interface TXIoTFamilyInfo {
  familyId: string;
  name: string;
  [k: string]: unknown;
}

export interface TXIoTRoomInfo {
  roomId: string;
  name: string;
  [k: string]: unknown;
}

export interface TXIoTUserInfo {
  userId: string;
  nickName: string;
  avatarUrl: string;
  role: number;
  deviceBindTime: number;
}

export interface TXIoTUserSignatureLike {
  requestId: string;
  timestamp: number;
  nonce: number;
  signature: string;
}

export interface TXIoTPageResult<T> {
  list: T[];
  nextPageToken?: string;
}

// ============================ 推送消息 ============================

export interface TXIoTPushMessage {
  messageTime: number;
  type: number;
  subType: number;
  deviceId: TXIoTDeviceId | null;
}

export interface TXIoTEngineDelegate {
  onLoginSuccess?: () => void;
  onLoginFailure?: (errCode: number, errMsg: string) => void;
  onLogout?: () => void;
  onUserSignatureExpired?: () => void;
  onReceivePushMessage?: (msg: TXIoTPushMessage) => void;
}

// ============================ 家庭管理 ============================

export interface TXIoTFamilyManager {
  createFamily(name: string): Promise<TXIoTFamilyInfo>;
  deleteFamily(familyId: string): Promise<void>;
  getFamilyList(): Promise<TXIoTFamilyInfo[]>;
  updateFamilyInfo(familyInfo: { familyId: string; name: string }): Promise<void>;
  createRoom(familyId: string, name: string): Promise<TXIoTRoomInfo>;
  deleteRoom(familyId: string, roomId: string): Promise<void>;
  setRoomName(familyId: string, roomId: string, name: string): Promise<void>;
  getRoomList(familyId: string): Promise<TXIoTRoomInfo[]>;
  createFamilyInviteToken(familyId: string): Promise<string>;
  joinFamilyAsMember(inviteToken: string): Promise<void>;
  removeMemberFromFamily(familyId: string, userId: string): Promise<void>;
  getMemberList(familyId: string): Promise<Array<{ userId: string; nickName?: string; role?: number }>>;
}

// ============================ 设备管理 ============================

export interface TXIoTDeviceManager {
  bindDevice(familyId: string, deviceBindSignature: string): Promise<unknown>;
  unbindDevice(familyId: string, deviceId: TXIoTDeviceId): Promise<void>;
  addDeviceToRoom(deviceId: TXIoTDeviceId, familyId: string, roomId: string): Promise<void>;
  removeDeviceFromRoom(deviceId: TXIoTDeviceId, familyId: string): Promise<void>;
  getDeviceList(familyId: string, nextPageToken?: string): Promise<TXIoTPageResult<TXIoTDeviceInfo>>;
  createDeviceSharingToken(familyId: string, deviceId: TXIoTDeviceId): Promise<string>;
  bindDeviceSharedWithMe(deviceId: TXIoTDeviceId, shareToken: string): Promise<void>;
  unbindDeviceSharedWithMe(deviceId: TXIoTDeviceId): Promise<void>;
  getDeviceSharedUsers(deviceId: TXIoTDeviceId): Promise<Array<{ userId: string; [k: string]: unknown }>>;
  removeDeviceSharedUser(deviceId: TXIoTDeviceId, userId: string): Promise<void>;
  getDeviceListSharedWithMe(nextPageToken?: string): Promise<TXIoTPageResult<TXIoTDeviceInfo>>;
  sendCommand(deviceId: TXIoTDeviceId, jsonData: string | object): Promise<unknown>;
  getProperties(deviceId: TXIoTDeviceId): Promise<unknown>;
  modifyAliasName(deviceId: TXIoTDeviceId, aliasName: string): Promise<void>;
  /** 获取设备 VoIP 授权票据；返回 { sn, snTicket } 供宿主自行调用 wx.requestDeviceVoIP */
  requestVoIPSnTicket(deviceId: TXIoTDeviceId, modelId: string, appId: string): Promise<{ sn: string; snTicket: string }>;
  registerVoIPNotificationForDevice(deviceId: TXIoTDeviceId, modelId: string, appId: string, wxOpenId: string): Promise<unknown>;
  unregisterVoIPNotificationForDevice(deviceId: TXIoTDeviceId, modelId: string, appId: string, wxOpenId: string): Promise<unknown>;
  getAuthorizedVoIPUserList(deviceId: TXIoTDeviceId): Promise<unknown>;
}

// ============================ 监控会话 ============================

export interface TXIoTVideoEncoderParams {
  /** 视频分辨率，见 TXIoTVideoResolution，缺省为 RESOLUTION_360_640 */
  resolution: number;
}

export interface TXIoTLocalRecordingParams {
  /** 录制文件的保存路径 */
  filePath: string;
}

export interface TXIoTMonitorSessionListener {
  onError?: (channelId: number, code: number, msg: string) => void;
  onSessionEstablished?: () => void;
  onSessionReconnecting?: () => void;
  onSessionRecovery?: () => void;
  onRemoteStreamAvailable?: (channelId: number, available: boolean) => void;
  onRenderFirstFrame?: (channelId: number) => void;
  onPlayStateChanged?: (channelId: number, state: number) => void;
  /** 截图完成；imagePath 为空表示截图失败 */
  onSnapshotComplete?: (channelId: number, imagePath?: string) => void;
  onLocalRecordBegin?: (channelId: number, code: number, path: string) => void;
  onLocalRecording?: (channelId: number, duration: number, path: string) => void;
  onLocalRecordComplete?: (channelId: number, code: number, path: string) => void;
}

export interface TXIoTMonitorSession {
  addListener(listener: TXIoTMonitorSessionListener): void;
  removeListener(listener: TXIoTMonitorSessionListener): void;
  /** 把通道与 <iot-player component-id="xxx"> 绑定，SDK 内部按 channelId 存起来 */
  setIoTPlayer(channelId: number, iotPlayerComponentId: string): void;
  startSession(deviceId: TXIoTDeviceId): void;
  stopSession(): void;
  startRemoteView(channelId: number, streamType: number): void;
  stopRemoteView(channelId: number): void;
  switchRemoteStream(channelId: number, streamType: number): void;
  muteRemoteAudio(channelId: number, mute: boolean): void;
  muteAllRemoteAudio(mute: boolean): void;
  startLocalAudio(): void;
  stopLocalAudio(): void;
  muteLocalAudio(mute: boolean): void;
  startLocalVideo(videoEncoderParams?: TXIoTVideoEncoderParams): void;
  stopLocalVideo(): void;
  sendPTZCommand(channelId: number, command: number, speed?: number): void;
  takeSnapshot(channelId: number): void;
  startLocalRecording(channelId: number, params?: TXIoTLocalRecordingParams): void;
  stopLocalRecording(channelId: number): void;
}

// ============================ 通话会话 ============================

export interface TXIoTCallUser {
  /** 对端设备 ID */
  deviceId: TXIoTDeviceId | null;
}

export interface TXIoTCallSessionListener {
  onError?: (code: number, msg: string) => void;
  onCallBegin?: (mediaType: number) => void;
  onCallEnd?: (mediaType: number, reason: number) => void;
  onCallRejected?: (callUser: TXIoTCallUser) => void;
  onCallNoResponse?: (callUser: TXIoTCallUser) => void;
  onCallLineBusy?: (callUser: TXIoTCallUser) => void;
  onCallUserOffline?: (callUser: TXIoTCallUser) => void;
  onCallUserAudioAvailable?: (callUser: TXIoTCallUser, available: boolean) => void;
  onCallUserVideoAvailable?: (callUser: TXIoTCallUser, available: boolean) => void;
}

export interface TXIoTCallSession {
  addListener(listener: TXIoTCallSessionListener): void;
  removeListener(listener: TXIoTCallSessionListener): void;
  callDevice(deviceId: TXIoTDeviceId, callType: number): void;
  hangup(): void;
  startRemoteView(callUser: TXIoTCallUser): void;
  stopRemoteView(callUser: TXIoTCallUser): void;
  /** 把远端 TXIoTCallUser 与<iot-player component-id="xxx"> 绑定，SDK 内部按 CallUser 存起来 */
  setIoTPlayer(callUser: TXIoTCallUser, iotPlayerComponentId: string): void;
  openMicrophone(): void;
  closeMicrophone(): void;
  openCamera(camera: number): void;
  closeCamera(): void;
  switchCamera(camera: number): void;
  selectAudioPlaybackDevice(device: number): void;
}

// ============================ 云存储 ============================

export interface TXIoTCloudStorage {
  getDayList(channelId: number, timeZoneId: string): Promise<unknown>;
  getEventList(channelId: number, timeZoneId: string, date: string, nextPageToken?: string): Promise<unknown>;
}

// ============================ 引擎单例 ============================

export interface TXIoTEngineInstance {
  /** 注册全局事件监听（登录/登出/推送等） */
  addListener(listener: TXIoTEngineDelegate): void;
  removeListener(listener: TXIoTEngineDelegate): void;
  /** 登录。userSignature 由业务用 AppKey/AppSecret 计算 HMAC-SHA1 得到 */
  login(appKey: string, userId: string, userSignature: TXIoTUserSignatureLike): void;
  logout(): void;
  /** 已登录用户信息；未就绪或未登录返回 null */
  getLoginUserInfo(): TXIoTUserInfo | null;
  getFamilyManager(): TXIoTFamilyManager | null;
  getDeviceManager(): TXIoTDeviceManager | null;
  getMonitorSession(): TXIoTMonitorSession | null;
  getCallSession(): TXIoTCallSession | null;
  /** 每次调用返回一个与 deviceId 绑定的新实例，不做缓存 */
  getCloudStorage(deviceId: TXIoTDeviceId): TXIoTCloudStorage | null;
}

export interface TXIoTEngineStatic {
  /**
   * 异步获取引擎单例。内部自动完成 wasm 加载与 bridge 初始化，
   * resolve 后即可调用 getXxxManager() 等同步接口。
   */
  getInstance(): Promise<TXIoTEngineInstance>;
}

/** TXIoTUserSignature 构造器：new 出来后填 requestId/timestamp/nonce/signature */
export interface TXIoTUserSignatureCtor {
  new (): TXIoTUserSignatureLike;
}

export interface TXIoTDeviceIdCtor {
  new (productId: string, deviceName: string): TXIoTDeviceId;
}

/** TXIoTCallUser 构造器：new TXIoTCallUser(deviceId) 包一层，用于原样传回 onCallXxx 回调收到的对端标识。 */
export interface TXIoTCallUserCtor {
  new (deviceId?: TXIoTDeviceId | null): TXIoTCallUser;
}

export interface TXIoTVideoEncoderParamsCtor {
  new (resolution?: number): TXIoTVideoEncoderParams;
}

export interface TXIoTLocalRecordingParamsCtor {
  new (filePath?: string): TXIoTLocalRecordingParams;
}

// ============================ 枚举 ============================

export type EnumMap = Readonly<Record<string, number>>;

// ============================ 插件默认导出 ============================

export interface TXIoTPlugin {
  VERSION: string;

  TXIoTEngine: TXIoTEngineStatic;
  TXIoTDeviceManager: new (engineHandler: unknown) => TXIoTDeviceManager;
  TXIoTFamilyManager: new (engineHandler: unknown) => TXIoTFamilyManager;
  TXIoTMonitorSession: new (engineImpl: unknown, wasmModule: unknown) => TXIoTMonitorSession;
  TXIoTCallSession: new (...args: unknown[]) => TXIoTCallSession;

  TXIoTPushMessage: new () => TXIoTPushMessage;
  TXIoTPushMessageType: EnumMap;
  TXIoTPushMessageSubType: EnumMap;

  TXIoTUserSignature: TXIoTUserSignatureCtor;
  TXIoTDeviceId: TXIoTDeviceIdCtor;
  TXIoTUserInfo: new () => TXIoTUserInfo;
  TXIoTErrorCode: EnumMap;
  TXIoTCallUser: TXIoTCallUserCtor;

  TXIoTVideoResolution: EnumMap;
  TXIoTVideoEncoderParams: TXIoTVideoEncoderParamsCtor;
  TXIoTLocalRecordingParams: TXIoTLocalRecordingParamsCtor;
  TXIoTStreamType: EnumMap;
  TXIoTPTZCommand: EnumMap;
  TXIoTPlayState: EnumMap;
  TXIoTCallMediaType: EnumMap;
  TXIoTCallEndReason: EnumMap;
  TXIoTAudioPlaybackDevice: EnumMap;
  TXIoTCamera: EnumMap;
}

export const VERSION: string;
declare const plugin: TXIoTPlugin;
export default plugin;
