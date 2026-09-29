// pages/cloud-storage/cloud-storage.ts
// 云存页：从设备列表「⋮ -> 云存」入口进入，仿照安卓端 CloudStorageActivity 实现。
//
// 入参（query）：
//   - productId   产品 ID（必填）
//   - deviceName  设备名（必填）
//   - aliasName   设备别名（可选，作页面标题）
//   - online      在线状态 '1' / '0'（可选，作标题前小圆点）
//
// 数据流：page -> utils/iotEngine（Promise 封装） -> 插件 tx-iot-sdk（TXIoTCloudStorage）。
//
// 与安卓端 Demo 的主要差异（小程序侧简化）：
//   - 小程序端云存不需要加密播放能力，只走 videoFiles[].videoUrl 直链播放
//     （<video> 组件），SDK 侧也不再暴露安卓/iOS 端用于加密取流播放的
//     vodAppId/vodFileId/vodPlaySign 字段。
//   - 全屏使用 <video> 组件自带的原生 requestFullScreen（系统级真横屏，截屏/状态栏方向都
//     正确），固定传 direction 按横屏进入；全屏内需要展示的自定义内容（录像带式进度条、
//     悬浮按钮）按微信要求放在 video 节点内部。其中全屏内的时间轴刻意不使用 <scroll-view>，
//     而是用 transform: translateX 自绘平移 + 自定义 touchmove 拖拽，因为 scroll-view 在
//     原生全屏下会出现布局/裁切异常（刻度文字被截断），原生横向拖拽手势也不稳定。
//
// 时间轴（对齐安卓端 CloudStorageTimelineView + CloudStorageActivity）：
//   - 横向可拖拽滚动，固定在视口中心的绿色指示线 + 时间提示气泡跟随中心时间变化；
//   - 支持缩放（+/- 按钮）改变每小时的像素宽度；
//   - 拖拽过程中只更新中心时间气泡，不做任何 seek；必须等手指松开、且惯性滚动也停下之后，
//     才定位到中心时间覆盖的录像文件并从该偏移处播放（拖动中途的停顿不算结束，不会打断播放），
//     若中心时间附近没有录像，则在 10s 范围内找最近的录像文件播放；
//   - 播放过程中（非用户拖拽时）时间轴会跟随播放进度自动居中，与安卓端
//     updatePlayProgressFromPlayer -> centerTimelineAtTime 语义一致。
//
// 注意：云存的一个 videoUrl 对应的是一段连续录制的存储文件（可能长达几十分钟），
// 而列表上展示的时长是「事件」自身的时长（如一次移动侦测约几秒到几十秒）。
// 因此点击列表播放某个事件时，不能从文件开头整段播放，而是要：
//   1. seek 到事件在该文件内的偏移量（event.eventTimeMs - file.startTimeMs）；
//   2. 播放到事件结束时间点（event.eventTimeMs + event.durationMs）后自动停止。
// 与安卓端 CloudStorageActivity.PlaybackSession（startWallMs/endWallMs）语义一致。

import {
  getCloudStorageDayList,
  getCloudStorageEventList,
  UiCloudStorageEvent,
} from '../../utils/iotEngine';

interface DateChip {
  date: string; // 'YYYY-MM-DD'
  weekLabel: string; // 今天 / 昨天 / 周几
  day: string; // '28'
  month: string; // '07月'
}

interface EventVm {
  key: string;
  eventType: string;
  typeLabel: string; // 门铃呼叫事件 / 人形检测事件 / ...
  thumbnailUrl: string;
  timeText: string; // HH:mm:ss
  durationText: string; // 15s（<60s）或 1:05（>=60s），与安卓端 formatDuration 对齐
  eventTimeMs: number;
  hasVideo: boolean; // 该事件原始是否带 videoFiles（决定缩略图播放角标 / 文案，对齐安卓端 isSnapshotEvent）
  videoUrl: string; // 覆盖该事件的底层录像文件地址，可能为空（无直链时暂不支持播放）
  playOffsetSec: number; // 播放时需要 seek 到的文件内偏移（秒）
  fileStartTimeMs: number; // 底层文件的起始墙钟时间（ms），用于把 currentTime 换算回墙钟时间
  playEndWallMs: number; // 应该停止播放的墙钟时间（ms），0 表示不做时长裁剪
}

interface TimelineTickVm {
  key: string;
  style: string; // left: Xpx;
  label: string;
  major: boolean;
}

interface TimelineSegmentVm {
  key: string;
  style: string; // left: Xpx; width: Ypx;
}

interface TimelineFileVm {
  videoUrl: string;
  startTimeMs: number;
  durationMs: number;
}

const CHANNEL_LIST = ['无通道', '通道 1', '通道 2', '通道 3'];
const DAY_MS = 24 * 60 * 60 * 1000;
// 导航栏左侧按钮（返回 / 刷新）的点击区域尺寸，需与 .cs-nav-side-btn 的 width/height 保持一致
const NAV_SIDE_BTN_SIZE_PX = 44;

// 事件类型编码，与安卓端 CloudStorageEventAdapter.getEventTypeNames 完全对齐
const EVENT_TYPE_LABELS: Record<string, string> = {
  '1': '门铃呼叫事件',
  '2': '运动检测事件',
  '3': '人形检测事件',
  '4': '区域入侵事件',
  '5': '区域徘徊事件',
  '6': '异常声音事件',
  '100': '人脸识别抓拍',
  '101': '开门状态抓拍',
};

// 时间轴缩放档位，与安卓端 CloudStorageActivity.zoomMultipliers 对齐
const ZOOM_MULTIPLIERS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const BASE_HOUR_WIDTH_PX = 60;
// 拖拽/惯性滚动停止判定的静默时长，与安卓端 TIMELINE_SCROLL_IDLE_MS 对齐
const TIMELINE_IDLE_MS = 150;
// 中心时间附近查找最近录像文件的范围，与安卓端 nearestVideoFileNear 默认值对齐
const NEAREST_RANGE_MS = 10000;
// 连续解码报错（如 PIPELINE_ERROR_DECODE）的容忍上限。注意这是「连续」计数：两次报错之间只要
// 播放进度真正越过坏点继续推进，计数就会被清零（见 onVideoTimeUpdate）。因此长录像里散布的
// 孤立坏点可以一直靠「向后跳过续播」逐个越过，直到播放成功，不会中断用户观看；
// 只有接连多段码流都损坏（或网络持续不可用）时才提示播放失败。
const MAX_CONSECUTIVE_VIDEO_ERRORS = 5;
// 判定「播放已真正进入本次会话时间窗」时，起点侧允许的容差，用于容忍 seek 落到目标点
// 之前的关键帧。详见 _hasPlaybackEnteredSession 的注释。
const PLAYBACK_ENTER_TOLERANCE_MS = 1500;
// 上述判定的兜底等待时长：超过该时长仍未进入时间窗就强制视为已进入，避免 seek 落点越过
// 结束点时永远进不了会话（既不跟随进度也不结束）。
const PLAYBACK_ENTER_FALLBACK_MS = 3000;
// currentTime 的推进量超过该阈值才算「真的在播」，用于过滤同一帧的重复上报
const PROGRESS_EPSILON_SEC = 0.05;
// 解码报错重载之间的最小间隔，避免「重载 -> 立刻又报错」形成紧密循环导致画面反复闪烁
const VIDEO_RELOAD_DELAY_MS = 400;
// 解码报错后恢复播放的位置 = 报错位置再往后跳这么多秒，用于越过损坏的那一小段码流。
// 若仍从原来的起点恢复，会一次次撞上同一个坏点，表现为「播一段就跳回去重播」的死循环。
const ERROR_RESUME_SKIP_SEC = 2;
// 自上次解码报错的位置起，播放进度至少要再推进这么多秒，才认为确实越过了那个坏点、
// 可以补回重试预算。否则同一个坏点反复报错时预算会被无限补满，永远耗不尽。
const ERROR_RECOVERY_PROGRESS_SEC = 5;
// 全屏播放时，录像带式进度条无操作后自动隐藏的静默时长
const FS_CONTROLS_HIDE_MS = 3000;
// 进入原生全屏时的画面方向：90 表示屏幕逆时针 90 度（横屏）。云存录像都是横屏视频，
// 不传该参数时基础库会按视频宽高比自动判断，实测存在判成竖屏的情况，这里固定按横屏进入。
const FULLSCREEN_DIRECTION = 90;

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

// 与安卓端 CloudStorageEventAdapter.formatDuration 对齐：<60s 显示 "15s"，否则 "分:秒"（秒补零）
function fmtDuration(ms: number): string {
  const totalSec = Math.max(0, Math.floor(ms / 1000));
  if (totalSec < 60) return `${totalSec}s`;
  const mm = Math.floor(totalSec / 60);
  const ss = totalSec % 60;
  return `${mm}:${pad2(ss)}`;
}

function fmtTimeOfDay(ms: number): string {
  const d = new Date(ms);
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

function parseIsoDate(date: string): Date | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(d.getTime()) ? null : d;
}

function startOfDay(d: Date): Date {
  const r = new Date(d);
  r.setHours(0, 0, 0, 0);
  return r;
}

function weekDayCn(dayOfWeek: number): string {
  return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][dayOfWeek] || '';
}

function relativeWeekDayText(target: Date): string {
  const today = startOfDay(new Date());
  const day = startOfDay(target);
  const diffDays = Math.round((today.getTime() - day.getTime()) / DAY_MS);
  if (diffDays === 0) return '今天';
  if (diffDays === 1) return '昨天';
  return weekDayCn(day.getDay());
}

function buildDateChip(date: string): DateChip {
  const parsed = parseIsoDate(date);
  if (!parsed) return { date, weekLabel: '', day: date, month: '' };
  return {
    date,
    weekLabel: relativeWeekDayText(parsed),
    day: pad2(parsed.getDate()),
    month: `${pad2(parsed.getMonth() + 1)}月`,
  };
}

Page({
  data: {
    statusBarHeight: 20,
    navBarHeight: 44,
    // 导航栏左侧按钮组的起始偏移、以及中间内容区的左右避让间距（px），在 onLoad 中依据
    // 微信胶囊按钮的实际位置算出，避免自定义 UI 与官方胶囊互相遮挡
    navSideInset: 6,
    navContentInset: 96,

    productId: '',
    deviceName: '',
    aliasName: '',
    online: false,

    channelList: CHANNEL_LIST,
    channelIndex: 0,
    showChannelMenu: false,

    daysLoading: false,
    dateChips: [] as DateChip[],
    selectedDate: '',
    emptyDays: false,

    eventsLoading: false,
    events: [] as EventVm[],
    emptyEvents: false,

    // 播放
    playerUrl: '',
    playerTitle: '',
    videoMuted: false,
    videoPaused: false,
    // 是否正在加载/缓冲中（首次加载、seek 定位、报错重载、播放中途卡顿缓冲），驱动加载动画
    videoBuffering: false,

    // 时间轴几何信息（单位 px，与 scroll-view 的 scroll-left 单位保持一致）
    timelineViewportWidth: 0,
    timelineSidePadding: 0,
    timelineDayWidth: 0,
    timelineContentWidth: 0,
    timelineScrollLeft: 0,
    timelineScrollAnimate: false,
    timelineTicks: [] as TimelineTickVm[],
    timelineSegments: [] as TimelineSegmentVm[],
    timelineHasVideo: false,
    timelineCenterTimeText: '',
    timelineZoomIndex: 0,
    timelineZoomInDisabled: false,
    timelineZoomOutDisabled: true,

    // 全屏播放状态 + 全屏内覆盖的时间轴（录像带式进度条）。全屏后视频区域变为横屏整屏，
    // 尺寸和普通预览区完全不同，因此几何信息单独测量/存储，但共享同一份录像文件数据与
    // 缩放档位，随普通时间轴联动定位
    isFullscreen: false,
    fsControlsVisible: true,
    fsTimelineViewportWidth: 0,
    fsTimelineSidePadding: 0,
    fsTimelineDayWidth: 0,
    fsTimelineContentWidth: 0,
    fsTimelineScrollLeft: 0,
    fsTimelineScrollAnimate: false,
    fsTimelineTicks: [] as TimelineTickVm[],
    fsTimelineSegments: [] as TimelineSegmentVm[],
  },

  // 分页拉取时用于丢弃「已过期」的请求（用户切换日期后，老请求的回调应忽略）
  _dateRequestToken: 0 as number,

  // 当前播放会话的 seek/裁剪参数（详见 _buildEventVm / _startPlayerForFile 的注释）
  _playerSeeked: false,
  _playerOffsetSec: 0 as number,
  _playerFileStartTimeMs: 0 as number,
  _playerEndWallMs: 0 as number,
  // 同一次播放会话内，因解码错误已经自动重试过的次数，详见 onVideoError 的注释
  _videoErrorRetryCount: 0 as number,

  // 本次播放会话请求的起始墙钟位置，以及播放是否已真正进入该会话的时间窗。
  // seek 生效前 currentTime 还是旧位置，既不能用来定位时间轴也不能用来判断播放结束，
  // 详见 _hasPlaybackEnteredSession。
  _playerStartWallMs: 0 as number,
  _playerEnteredSession: false,
  // 本次会话开始的时刻，用于上述判定的兜底超时
  _playerSessionStartedAt: 0 as number,
  // 上一次 timeupdate 上报的 currentTime，用于判断进度是否真的在推进（据此补回重试预算）
  _lastProgressTimeSec: 0 as number,
  // 上一次解码报错时的播放位置（文件内偏移，秒），-1 表示本次会话还没报错过。
  // 用于报错后跳过坏点续播，以及判断进度是否真的越过了坏点，详见 onVideoError
  _lastErrorTimeSec: -1 as number,
  // 是否有一次「解码报错后重载」在途，以及它的延时定时器。用于避免重载叠加/紧密循环，
  // 详见 onVideoError 的注释
  _isReloading: false,
  _videoReloadTimer: 0 as unknown as ReturnType<typeof setTimeout> | 0,

  // seek 节流状态：<video> 组件的 seek 是异步的，若上一次 seek 尚未完成（未收到
  // bindseeked）就连续下发下一次 seek 指令，播放器内部状态会错乱，偶现「反复跳回
  // 某个固定片段」的问题。这里保证同一时刻只有一次 seek 在途，期间产生的更新目标
  // 只保留最新一个，等当前 seek 真正完成后再补发一次，详见 _seekVideoTo/onVideoSeeked。
  _isSeeking: false as boolean,
  _pendingSeekOffsetSec: null as number | null,
  _seekSafetyTimer: 0 as unknown as ReturnType<typeof setTimeout> | 0,

  // 时间轴状态：当前选中日期 0 点的墙钟时间、该日期下所有可播放录像文件、
  // 拖拽/惯性滚动状态、拖拽静默判定的定时器。
  // _isTimelineTouching（手指是否还按在时间轴上）与 _isTimelineDragging（拖拽会话是否
  // 进行中，含松手后的惯性滚动）必须分开：只有松手后才允许触发 seek 定位，否则拖动中途
  // 的短暂停顿会被误判成拖拽结束而不断打断播放。
  _dayStartMs: 0 as number,
  _timelineFiles: [] as TimelineFileVm[],
  _isTimelineTouching: false,
  _isTimelineDragging: false,
  _timelineIdleTimer: 0 as unknown as ReturnType<typeof setTimeout> | 0,
  _timelineLastCenterMs: 0 as number,

  // 全屏内时间轴的拖拽/惯性滚动状态，与普通时间轴的状态字段一一对应但相互独立
  _isFsTimelineDragging: false,
  _fsTimelineIdleTimer: 0 as unknown as ReturnType<typeof setTimeout> | 0,
  // 全屏内自定义拖拽（onFsTimelineTouchMove）上一次触摸点的横坐标，null 表示本次触摸
  // 还没有上一帧可供计算增量
  _fsDragLastClientX: null as number | null,
  // 全屏时间轴当前的内容偏移量，作为唯一事实来源同步维护。不能直接读 data.fsTimelineScrollLeft
  // 来做增量累加：setData 是异步的，而touchmove 高频触发，会读到尚未更新的旧值，
  // 表现为拖动过程中位置反复往回跳（抽搐）。
  _fsScrollLeft: 0 as number,
  // 全屏播放时，控制「录像带式进度条」自动隐藏的定时器
  _fsHideTimer: 0 as unknown as ReturnType<typeof setTimeout> | 0,

  onLoad(query: Record<string, string>) {
    const sys = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
    const menu = wx.getMenuButtonBoundingClientRect();
    const statusBarHeight = sys.statusBarHeight || 20;
    const gap = menu.top - statusBarHeight;
    const navBarHeight = menu.height + gap * 2;
    const viewportWidth = sys.windowWidth || 375;

    // 导航栏避让计算：右侧整块区域属于微信官方胶囊（···/⊙），自定义内容不能进入。
    // capsuleSafeRight 是从屏幕右边缘到胶囊左边缘再留一点余量的距离；中间内容区左右取
    // 「左侧按钮组宽度」与该安全区的较大值，保证既不压胶囊、标题又能保持屏幕居中。
    const capsuleSafeRight = Math.max(0, viewportWidth - (menu.left || viewportWidth) + gap);
    const navSideInset = 6;
    const leftGroupWidth = navSideInset + NAV_SIDE_BTN_SIZE_PX * 2 + gap;
    const navContentInset = Math.max(leftGroupWidth, capsuleSafeRight);

    const productId = decodeURIComponent(query.productId || '');
    const deviceName = decodeURIComponent(query.deviceName || '');
    const aliasName = decodeURIComponent(query.aliasName || '') || deviceName || '设备';
    const online = query.online === '1';

    this.setData({
      statusBarHeight,
      navBarHeight,
      navSideInset,
      navContentInset,
      productId,
      deviceName,
      aliasName,
      online,
      timelineViewportWidth: viewportWidth,
      timelineSidePadding: viewportWidth / 2,
    });

    if (!productId || !deviceName) {
      wx.showToast({ title: '设备信息缺失', icon: 'none' });
      setTimeout(() => wx.navigateBack({ delta: 1 }), 800);
      return;
    }

    this._loadDayList();
  },

  onUnload() {
    this._stopPlayer();
    this._clearTimelineIdleTimer();
    this._clearFsTimelineIdleTimer();
    this._clearFsHideTimer();
  },

  onBack() {
    wx.navigateBack({ delta: 1 });
  },

  /** 顶部刷新按钮：重新拉当天列表 */
  onRefresh() {
    if (this.data.daysLoading) return;
    this._loadDayList();
  },

  /** 通道选择展开 / 收起 */
  onToggleChannel() {
    this.setData({ showChannelMenu: !this.data.showChannelMenu });
  },

  /** 选中某通道：重置状态后重新拉当天列表 */
  onSelectChannel(e: WechatMiniprogram.TouchEvent) {
    const idx = Number((e.currentTarget.dataset as { idx: string }).idx);
    if (Number.isNaN(idx) || idx === this.data.channelIndex) {
      this.setData({ showChannelMenu: false });
      return;
    }
    this._stopPlayer();
    this._resetTimelineState();
    this.setData({
      channelIndex: idx,
      showChannelMenu: false,
      selectedDate: '',
      dateChips: [],
      events: [],
      emptyDays: false,
      emptyEvents: false,
    });
    this._loadDayList();
  },

  /** 拉当天列表；成功后自动选中（保留上次选中日期优先，否则选最新一天） */
  _loadDayList() {
    const { productId, deviceName, channelIndex } = this.data;
    this.setData({ daysLoading: true, emptyDays: false });
    getCloudStorageDayList(productId, deviceName, channelIndex)
      .then((days) => {
        this.setData({ daysLoading: false });
        this._renderDateList(days);
      })
      .catch((err: Error) => {
        console.warn('[cloud-storage] getCloudStorageDayList failed:', err);
        this.setData({ daysLoading: false });
        wx.showToast({ title: err.message || '获取日期列表失败', icon: 'none' });
        this._renderDateList([]);
      });
  },

  _renderDateList(days: string[]) {
    if (days.length === 0) {
      // 没有任何可选日期时不会走到 _loadEventList，这里补上停止播放，
      // 避免列表/时间轴都已清空、画面却还在放旧录像
      this._stopPlayer();
      this.setData({ dateChips: [], emptyDays: true, selectedDate: '' });
      this._renderEvents([]);
      return;
    }
    const sorted = [...days].sort().reverse();
    const dateChips = sorted.map(buildDateChip);
    const previous = this.data.selectedDate;
    const target = previous && sorted.includes(previous) ? previous : sorted[0];
    this.setData({ dateChips, emptyDays: false });
    this._selectDate(target);
  },

  onSelectDate(e: WechatMiniprogram.TouchEvent) {
    const date = (e.currentTarget.dataset as { date: string }).date;
    if (!date || date === this.data.selectedDate) return;
    this._selectDate(date);
  },

  _selectDate(date: string) {
    this.setData({ selectedDate: date });
    this._loadEventList(date);
  },

  /** 分页拉全部事件后再一次性渲染（与安卓端 Demo 策略一致，简化状态管理） */
  _loadEventList(date: string) {
    const { productId, deviceName, channelIndex } = this.data;
    const token = ++this._dateRequestToken;
    // 时间轴数据即将被重置重建，正在播的录像属于上一个日期/通道，继续播下去会出现
    // 「高亮的是新日期、画面却还是旧日期的录像」这种割裂状态，因此一并停止播放。
    this._stopPlayer();
    this._resetTimelineState();
    this.setData({
      eventsLoading: true,
      emptyEvents: false,
      events: [],
    });
    this._fetchEventPage(productId, deviceName, channelIndex, date, '', [], token);
  },

  _fetchEventPage(
    productId: string,
    deviceName: string,
    channelIndex: number,
    date: string,
    pageToken: string,
    accumulated: UiCloudStorageEvent[],
    token: number,
  ) {
    getCloudStorageEventList(productId, deviceName, channelIndex, date, pageToken)
      .then((page) => {
        if (token !== this._dateRequestToken) return; // 用户已切换日期/通道，丢弃过期结果
        const all = accumulated.concat(page.dataList);
        if (page.nextPageToken) {
          this._fetchEventPage(
            productId, deviceName, channelIndex, date, page.nextPageToken, all, token,
          );
          return;
        }
        this.setData({ eventsLoading: false });
        this._renderEvents(all);
      })
      .catch((err: Error) => {
        if (token !== this._dateRequestToken) return;
        console.warn('[cloud-storage] getCloudStorageEventList failed:', err);
        this.setData({ eventsLoading: false });
        wx.showToast({ title: err.message || '获取录像列表失败', icon: 'none' });
        this._renderEvents(accumulated);
      });
  },

  _renderEvents(all: UiCloudStorageEvent[]) {
    // 列表只展示有 eventType 的记录（纯录像分段用于时间轴，不单独出现在列表里，
    // 与安卓端 Demo `pageData.filter { !it.eventType.isNullOrEmpty() }` 一致）
    const visible = all.filter((e) => !!e.eventType);
    const events: EventVm[] = visible
      .map((e, idx) => this._buildEventVm(e, idx))
      .sort((a, b) => b.eventTimeMs - a.eventTimeMs);

    this.setData({
      events,
      emptyEvents: events.length === 0,
    });

    const files: TimelineFileVm[] = [];
    all.forEach((e) => {
      (e.videoFiles || []).forEach((f) => {
        if (f.durationMs > 0 && f.videoUrl) {
          files.push({ videoUrl: f.videoUrl, startTimeMs: f.startTimeMs, durationMs: f.durationMs });
        }
      });
    });
    this._renderTimeline(files);
  },

  /**
   * 事件 -> 播放参数换算：event.videoFiles 里的每一项是覆盖该事件的底层连续录像文件
   * （可能长达几十分钟），事件本身只是文件内的一小段时间窗口。这里选出覆盖
   * event.eventTimeMs 的那个文件，算出：
   *   - playOffsetSec：事件起点相对文件起点的偏移（播放时 seek 到这里）
   *   - playEndWallMs：事件终点的墙钟时间（播放到这里自动停止）
   * 与安卓端 PlaybackSession.forEvent 的 startWallMs/endWallMs 语义一致。
   */
  _buildEventVm(e: UiCloudStorageEvent, idx: number): EventVm {
    // 是否为「视频型」事件，与安卓端 isSnapshotEvent 的判定条件（原始 videoFiles 是否为空）
    // 完全一致，决定缩略图上是否叠加播放角标、以及底部提示文案是「播放视频」还是「查看图片」
    const hasVideo = (e.videoFiles || []).length > 0;
    const base = {
      key: `${e.eventTimeMs}_${idx}`,
      eventType: e.eventType,
      typeLabel: EVENT_TYPE_LABELS[e.eventType] || e.eventType,
      thumbnailUrl: e.thumbnailUrl,
      timeText: fmtTimeOfDay(e.eventTimeMs),
      durationText: fmtDuration(e.durationMs),
      eventTimeMs: e.eventTimeMs,
      hasVideo,
    };

    const files = (e.videoFiles || [])
      .filter((f) => f.startTimeMs > 0 && f.durationMs > 0 && !!f.videoUrl)
      .sort((a, b) => a.startTimeMs - b.startTimeMs);
    if (files.length === 0) {
      return { ...base, videoUrl: '', playOffsetSec: 0, fileStartTimeMs: 0, playEndWallMs: 0 };
    }

    const eventStart = e.eventTimeMs;
    const covering =
      files.find((f) => eventStart >= f.startTimeMs && eventStart < f.startTimeMs + f.durationMs) ||
      files[0];
    const fileEndMs = covering.startTimeMs + covering.durationMs;

    const eventEnd = e.durationMs > 0 ? eventStart + e.durationMs : fileEndMs;
    const playOffsetSec = Math.max(0, (eventStart - covering.startTimeMs) / 1000);
    const playEndWallMs = Math.min(eventEnd, fileEndMs);

    return {
      ...base,
      videoUrl: covering.videoUrl,
      playOffsetSec,
      fileStartTimeMs: covering.startTimeMs,
      playEndWallMs,
    };
  },

  // =========================== 时间轴 ===========================

  /** 重置时间轴到「空」状态：切换日期/通道时先清空，避免残留上一次的数据 */
  _resetTimelineState() {
    this._timelineFiles = [];
    this._dayStartMs = 0;
    this._clearTimelineIdleTimer();
    this._clearFsTimelineIdleTimer();
    this._isTimelineTouching = false;
    this._isTimelineDragging = false;
    this._isFsTimelineDragging = false;
    this._fsScrollLeft = 0;
    this.setData({
      timelineTicks: [],
      timelineSegments: [],
      timelineHasVideo: false,
      timelineZoomIndex: 0,
      timelineZoomOutDisabled: true,
      timelineZoomInDisabled: false,
      timelineScrollLeft: 0,
      timelineCenterTimeText: '',
      fsTimelineTicks: [],
      fsTimelineSegments: [],
      fsTimelineScrollLeft: 0,
    });
  },

  _clearTimelineIdleTimer() {
    if (this._timelineIdleTimer) {
      clearTimeout(this._timelineIdleTimer);
      this._timelineIdleTimer = 0;
    }
  },

  _clearFsTimelineIdleTimer() {
    if (this._fsTimelineIdleTimer) {
      clearTimeout(this._fsTimelineIdleTimer);
      this._fsTimelineIdleTimer = 0;
    }
  },

  /** 用当天全部录像文件重建时间轴：几何信息 + 自动定位到第一段录像 */
  _renderTimeline(files: TimelineFileVm[]) {
    this._timelineFiles = files.slice().sort((a, b) => a.startTimeMs - b.startTimeMs);

    const dayStart = parseIsoDate(this.data.selectedDate);
    if (!dayStart) {
      this._dayStartMs = 0;
      this.setData({ timelineTicks: [], timelineSegments: [], timelineHasVideo: false });
      return;
    }
    this._dayStartMs = dayStart.getTime();

    this.setData({ timelineZoomIndex: 0 }, () => {
      this._rebuildTimelineGeometry();
      this._rebuildFsTimelineGeometry();
      this._updateZoomButtonStates();
      const firstStart =
        this._timelineFiles.length > 0 ? this._timelineFiles[0].startTimeMs : this._dayStartMs;
      this._centerTimelineAtTime(firstStart, false);
    });
  },

  /** 纯计算：给定每小时像素宽度 + 侧边留白，算出当天刻度/录像色块的像素几何信息。
   *  普通时间轴与全屏内覆盖的时间轴共享同一份录像文件数据，仅侧边留白（由各自视口
   *  宽度的一半决定）不同，因此提取成公共函数，避免两处重复实现同一套算法。 */
  _buildTimelineGeometry(
    hourWidth: number,
    sidePadding: number,
  ): { dayWidth: number; contentWidth: number; ticks: TimelineTickVm[]; segments: TimelineSegmentVm[] } {
    const dayWidth = hourWidth * 24;
    const contentWidth = dayWidth + sidePadding * 2;
    const dayStartMs = this._dayStartMs;
    const dayEndMs = dayStartMs + DAY_MS;

    const timeToX = (t: number) => sidePadding + ((t - dayStartMs) / DAY_MS) * dayWidth;

    const ticks: TimelineTickVm[] = [];
    for (let h = 0; h <= 24; h += 1) {
      const x = timeToX(dayStartMs + h * 60 * 60 * 1000);
      const major = h % 6 === 0;
      const label = h < 24 && h % 2 === 0 ? `${pad2(h)}:00` : h === 24 ? '24:00' : '';
      ticks.push({ key: `t${h}`, style: `left: ${x}px;`, label, major });
    }

    const segments: TimelineSegmentVm[] = [];
    this._timelineFiles.forEach((f, idx) => {
      const s = Math.max(f.startTimeMs, dayStartMs);
      const e = Math.min(f.startTimeMs + f.durationMs, dayEndMs);
      if (e <= s) return;
      const left = timeToX(s);
      const width = Math.max(timeToX(e) - left, 1);
      segments.push({ key: `seg${idx}`, style: `left: ${left}px; width: ${width}px;` });
    });

    return { dayWidth, contentWidth, ticks, segments };
  },

  /** 依据当前缩放档位 + 当天录像文件，重新计算普通时间轴的刻度/色块几何信息 */
  _rebuildTimelineGeometry() {
    const zoomIndex = this.data.timelineZoomIndex;
    const hourWidth = BASE_HOUR_WIDTH_PX * ZOOM_MULTIPLIERS[zoomIndex];
    const geo = this._buildTimelineGeometry(hourWidth, this.data.timelineSidePadding);
    this.setData({
      timelineDayWidth: geo.dayWidth,
      timelineContentWidth: geo.contentWidth,
      timelineTicks: geo.ticks,
      timelineSegments: geo.segments,
      timelineHasVideo: geo.segments.length > 0,
    });
  },

  /** 重新计算全屏内覆盖的时间轴几何信息；侧边留白尚未测量（还没进入过全屏）时先跳过 */
  _rebuildFsTimelineGeometry() {
    if (!this.data.fsTimelineSidePadding) return;
    const zoomIndex = this.data.timelineZoomIndex;
    const hourWidth = BASE_HOUR_WIDTH_PX * ZOOM_MULTIPLIERS[zoomIndex];
    const geo = this._buildTimelineGeometry(hourWidth, this.data.fsTimelineSidePadding);
    this.setData({
      fsTimelineDayWidth: geo.dayWidth,
      fsTimelineContentWidth: geo.contentWidth,
      fsTimelineTicks: geo.ticks,
      fsTimelineSegments: geo.segments,
    });
  },

  _timeToXWith(dayWidth: number, sidePadding: number, timeMs: number): number {
    return sidePadding + ((timeMs - this._dayStartMs) / DAY_MS) * dayWidth;
  },

  _xToTimeWith(dayWidth: number, sidePadding: number, x: number): number {
    if (dayWidth <= 0) return this._dayStartMs;
    const ratio = (x - sidePadding) / dayWidth;
    const clamped = Math.min(Math.max(ratio, 0), 1);
    return this._dayStartMs + clamped * DAY_MS;
  },

  _timeToX(timeMs: number): number {
    return this._timeToXWith(this.data.timelineDayWidth, this.data.timelineSidePadding, timeMs);
  },

  _xToTime(x: number): number {
    return this._xToTimeWith(this.data.timelineDayWidth, this.data.timelineSidePadding, x);
  },

  /** 把时间轴滚动到「某个墙钟时间位于视口中心」的位置，并刷新中心时间提示气泡；
   *  若全屏内的时间轴已经测量过尺寸，同步联动定位，保证退出全屏后位置保持一致 */
  _centerTimelineAtTime(timeMs: number, animate: boolean) {
    if (!this._dayStartMs) return;
    const clamped = Math.min(Math.max(timeMs, this._dayStartMs), this._dayStartMs + DAY_MS - 1);
    const x = this._timeToX(clamped);
    const scrollLeft = Math.max(0, x - this.data.timelineViewportWidth / 2);
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const patch: any = {
      timelineScrollLeft: scrollLeft,
      timelineScrollAnimate: animate,
      timelineCenterTimeText: fmtTimeOfDay(clamped),
    };
    if (this.data.fsTimelineDayWidth > 0) {
      const fsX = this._timeToXWith(this.data.fsTimelineDayWidth, this.data.fsTimelineSidePadding, clamped);
      const fsScrollLeft = Math.max(0, fsX - this.data.fsTimelineViewportWidth / 2);
      this._fsScrollLeft = fsScrollLeft;
      patch.fsTimelineScrollLeft = fsScrollLeft;
      patch.fsTimelineScrollAnimate = animate;
    }
    this.setData(patch);
  },

  /** 用户开始触摸普通（非全屏）时间轴：标记为拖拽中，取消任何待触发的「静止」定时器 */
  onTimelineTouchStart() {
    this._isTimelineTouching = true;
    this._isTimelineDragging = true;
    this._clearTimelineIdleTimer();
  },

  /** 手指抬起：开始「静止」判定。若之后仍有 scroll 事件（惯性滚动），定时器会被不断重置，
   *  直到惯性真正停下来才定位播放 */
  onTimelineTouchEnd() {
    this._isTimelineTouching = false;
    if (!this._isTimelineDragging) return;
    this._clearTimelineIdleTimer();
    this._timelineIdleTimer = setTimeout(() => this._onTimelineIdle(false), TIMELINE_IDLE_MS);
  },

  /** 滚动中：实时刷新中心时间提示
   *  （仅用于非全屏的普通时间轴，全屏内的时间轴走自定义拖拽，见 onFsTimelineTouchMove）
   *
   * 只有「松手之后」才安排静止判定去seek 定位：手指还按在屏幕上时，中途停顿一下是很常见的
   * 操作（挪动、观察刻度），不应该被当成拖拽结束而触发 seek，否则拖动过程中会不断打断播放。
   * 松手后 scroll 事件仍会因惯性继续到来，此时不断重置定时器，直到惯性停下才真正定位。
   *
   * 注意：scroll-view 拖拽期间该回调会几乎每帧触发一次，若每次都无条件 setData，
   * 会产生大量原生/JS 线程通信，和用户手指的原生滚动抢占主线程，表现为拖拽抽搐/卡顿。
   * 这里只在展示文案真正变化（精确到秒）时才 setData，大幅降低更新频率。
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onTimelineScroll(e: any) {
    const scrollLeft = (e && e.detail && e.detail.scrollLeft) || 0;
    const centerX = scrollLeft + this.data.timelineViewportWidth / 2;
    const centerTime = this._xToTime(centerX);
    this._timelineLastCenterMs = centerTime;
    const centerTimeText = fmtTimeOfDay(centerTime);
    if (centerTimeText !== this.data.timelineCenterTimeText) {
      this.setData({ timelineCenterTimeText: centerTimeText });
    }
    if (this._isTimelineDragging && !this._isTimelineTouching) {
      this._clearTimelineIdleTimer();
      this._timelineIdleTimer = setTimeout(() => this._onTimelineIdle(false), TIMELINE_IDLE_MS);
    }
  },

  /** 全屏内时间轴：开始触摸。同时取消自动隐藏倒计时，避免拖拽中途控件被隐藏 */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onFsTimelineTouchStart(e: any) {
    this._isFsTimelineDragging = true;
    const touch = e && e.touches && e.touches[0];
    this._fsDragLastClientX = touch ? touch.clientX : null;
    this._clearFsTimelineIdleTimer();
    this._clearFsHideTimer();
    if (!this.data.fsControlsVisible) {
      this.setData({ fsControlsVisible: true });
    }
  },

  /**
   * 全屏内时间轴：自定义拖拽。全屏内的时间轴用 transform: translateX 自绘平移而不是
   * <scroll-view>（后者在原生全屏下会出现布局/裁切异常，且原生横向拖拽手势不稳定），
   * 因此这里手动把触摸点的横向位移换算成内容偏移量。
   * 原生全屏是系统级真横屏，触摸坐标会随系统一起旋转，所以直接用 clientX 即可。
   * 手指右滑 = 内容右移 = 时间回退，与「拖动内容」的触摸滚动直觉一致。
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onFsTimelineTouchMove(e: any) {
    if (!this._isFsTimelineDragging) return;
    const touch = e && e.touches && e.touches[0];
    if (!touch) return;
    if (this._fsDragLastClientX === null) {
      this._fsDragLastClientX = touch.clientX;
      return;
    }
    const deltaX = touch.clientX - this._fsDragLastClientX;
    this._fsDragLastClientX = touch.clientX;
    if (!deltaX) return;

    const maxScrollLeft = Math.max(
      0,
      this.data.fsTimelineContentWidth - this.data.fsTimelineViewportWidth,
    );
    const nextScrollLeft = Math.min(maxScrollLeft, Math.max(0, this._fsScrollLeft - deltaX));
    if (nextScrollLeft === this._fsScrollLeft) return;
    this._fsScrollLeft = nextScrollLeft;

    const centerX = nextScrollLeft + this.data.fsTimelineViewportWidth / 2;
    const centerTime = this._xToTimeWith(
      this.data.fsTimelineDayWidth,
      this.data.fsTimelineSidePadding,
      centerX,
    );
    this._timelineLastCenterMs = centerTime;

    this.setData({
      fsTimelineScrollLeft: nextScrollLeft,
      fsTimelineScrollAnimate: false,
      timelineCenterTimeText: fmtTimeOfDay(centerTime),
    });
  },

  /** 全屏内时间轴：手指抬起，静默一段时间后定位播放并恢复自动隐藏倒计时 */
  onFsTimelineTouchEnd() {
    this._fsDragLastClientX = null;
    if (!this._isFsTimelineDragging) return;
    this._clearFsTimelineIdleTimer();
    this._fsTimelineIdleTimer = setTimeout(() => this._onTimelineIdle(true), TIMELINE_IDLE_MS);
  },

  /** 滚动真正停止（且手指已松开）：定位到中心时间覆盖/最近的录像文件并播放，
   *  对齐安卓端 onTimelineScrollIdle；全屏内的时间轴拖拽结束后，还需要恢复自动隐藏倒计时 */
  _onTimelineIdle(isFs: boolean) {
    if (isFs) {
      this._fsTimelineIdleTimer = 0;
      if (!this._isFsTimelineDragging) return;
      this._isFsTimelineDragging = false;
      this._scheduleFsHideTimer();
    } else {
      this._timelineIdleTimer = 0;
      // 手指仍按在时间轴上说明拖拽还没结束，不做定位（保险，正常不会走到这里）
      if (this._isTimelineTouching) return;
      if (!this._isTimelineDragging) return;
      this._isTimelineDragging = false;
    }

    const centerTime = this._timelineLastCenterMs;
    const covering = this._timelineFiles.find(
      (f) => centerTime >= f.startTimeMs && centerTime < f.startTimeMs + f.durationMs,
    );
    if (covering) {
      this._startPlayerForFile(covering, centerTime);
      return;
    }
    const nearest = this._findNearestTimelineFile(centerTime);
    if (nearest) {
      this._startPlayerForFile(nearest.file, nearest.playAtMs);
    } else {
      wx.showToast({ title: '附近没有录像', icon: 'none' });
    }
  },

  _findNearestTimelineFile(timeMs: number): { file: TimelineFileVm; playAtMs: number } | null {
    const files = this._timelineFiles;
    let bestAfterIndex = -1;
    let bestAfterDiff = Infinity;
    let bestBeforeIndex = -1;
    let bestBeforeDiff = Infinity;

    for (let i = 0; i < files.length; i += 1) {
      const f = files[i];
      const end = f.startTimeMs + f.durationMs;
      if (f.startTimeMs >= timeMs) {
        const diff = f.startTimeMs - timeMs;
        if (diff <= NEAREST_RANGE_MS && diff < bestAfterDiff) {
          bestAfterDiff = diff;
          bestAfterIndex = i;
        }
      } else if (end <= timeMs) {
        const diff = timeMs - end;
        if (diff <= NEAREST_RANGE_MS && diff < bestBeforeDiff) {
          bestBeforeDiff = diff;
          bestBeforeIndex = i;
        }
      }
    }

    if (bestAfterIndex >= 0) {
      const file = files[bestAfterIndex];
      return { file, playAtMs: file.startTimeMs };
    }
    if (bestBeforeIndex >= 0) {
      const file = files[bestBeforeIndex];
      const end = file.startTimeMs + file.durationMs;
      return { file, playAtMs: Math.min(Math.max(timeMs, file.startTimeMs), end - 1) };
    }
    return null;
  },

  /** 缩放：改变每小时像素宽度的同时，保持当前视口中心对应的墙钟时间不变 */
  onZoomIn() {
    this._zoomTimeline(1);
  },

  onZoomOut() {
    this._zoomTimeline(-1);
  },

  _zoomTimeline(direction: number) {
    const maxIndex = ZOOM_MULTIPLIERS.length - 1;
    const nextIndex = Math.min(maxIndex, Math.max(0, this.data.timelineZoomIndex + direction));
    if (nextIndex === this.data.timelineZoomIndex) return;

    const centerX = this.data.timelineScrollLeft + this.data.timelineViewportWidth / 2;
    const centerTime = this._xToTime(centerX);
    this.setData({ timelineZoomIndex: nextIndex }, () => {
      this._rebuildTimelineGeometry();
      this._rebuildFsTimelineGeometry();
      this._updateZoomButtonStates();
      this._centerTimelineAtTime(centerTime, false);
    });
  },

  _updateZoomButtonStates() {
    const zoomIndex = this.data.timelineZoomIndex;
    this.setData({
      timelineZoomOutDisabled: zoomIndex <= 0,
      timelineZoomInDisabled: zoomIndex >= ZOOM_MULTIPLIERS.length - 1,
    });
  },

  // =========================== 播放 ===========================

  onPlayEvent(e: WechatMiniprogram.TouchEvent) {
    const key = (e.currentTarget.dataset as { key: string }).key;
    const vm = this.data.events.find((ev) => ev.key === key);
    if (!vm) return;
    if (!vm.videoUrl) {
      wx.showToast({ title: '该记录暂不支持播放', icon: 'none' });
      return;
    }
    this._startPlayer(
      vm.videoUrl,
      `${vm.typeLabel ? vm.typeLabel + ' · ' : ''}${vm.timeText}`,
      vm.playOffsetSec,
      vm.fileStartTimeMs,
      vm.playEndWallMs,
    );
  },

  onViewSnapshot(e: WechatMiniprogram.TouchEvent) {
    const key = (e.currentTarget.dataset as { key: string }).key;
    const vm = this.data.events.find((ev) => ev.key === key);
    if (!vm || !vm.thumbnailUrl) {
      wx.showToast({ title: '暂无快照图片', icon: 'none' });
      return;
    }
    wx.previewImage({ urls: [vm.thumbnailUrl], current: vm.thumbnailUrl });
  },

  /** 由时间轴拖拽定位触发的播放：从中心时间对应的文件内偏移开始，播到文件结束为止 */
  _startPlayerForFile(file: TimelineFileVm, seekWallMs: number) {
    if (!file.videoUrl) {
      wx.showToast({ title: '该记录暂不支持播放', icon: 'none' });
      return;
    }
    const offsetSec = Math.max(0, (seekWallMs - file.startTimeMs) / 1000);
    const endWallMs = file.startTimeMs + file.durationMs;
    this._startPlayer(file.videoUrl, fmtTimeOfDay(seekWallMs), offsetSec, file.startTimeMs, endWallMs);
  },

  /**
   * @param offsetSec 播放开始时需要 seek 到的文件内偏移（秒）
   * @param fileStartTimeMs 底层文件的起始墙钟时间（ms），配合 currentTime 换算播放进度
   * @param endWallMs 应该停止播放的墙钟时间（ms），0 表示不裁剪（播到文件自然结束）
   */
  _startPlayer(
    url: string,
    title: string,
    offsetSec: number,
    fileStartTimeMs: number,
    endWallMs: number,
  ) {
    // 目标仍是「当前正在播放的同一个底层文件」（例如在时间轴上小范围拖动），
    // 直接 seek 定位即可，不重新赋值 src / 不重启播放，避免卡顿以及指示器先跳回
    // 文件开头再跳回目标点的问题。真正的 seek 指令通过 _seekVideoTo 节流下发，
    // 见该函数注释。
    if (this.data.playerUrl && this.data.playerUrl === url) {
      this._playerOffsetSec = offsetSec || 0;
      this._playerFileStartTimeMs = fileStartTimeMs || 0;
      this._playerEndWallMs = endWallMs || 0;
      this._videoErrorRetryCount = 0;
      this._playerStartWallMs = (fileStartTimeMs || 0) + (offsetSec || 0) * 1000;
      this._playerEnteredSession = false;
      this._playerSessionStartedAt = Date.now();
      this._lastProgressTimeSec = 0;
      this._lastErrorTimeSec = -1;
      this.setData({ playerTitle: title, videoPaused: false, videoBuffering: true });
      this._seekVideoTo(this._playerOffsetSec);
      if (this._dayStartMs) {
        this._centerTimelineAtTime(fileStartTimeMs + (offsetSec || 0) * 1000, false);
      }
      return;
    }

    this._playerSeeked = false;
    this._playerOffsetSec = offsetSec || 0;
    this._playerFileStartTimeMs = fileStartTimeMs || 0;
    this._playerEndWallMs = endWallMs || 0;
    this._videoErrorRetryCount = 0;
    this._playerStartWallMs = (fileStartTimeMs || 0) + (offsetSec || 0) * 1000;
    this._playerEnteredSession = false;
    this._playerSessionStartedAt = Date.now();
    this._lastProgressTimeSec = 0;
    this._lastErrorTimeSec = -1;
    // 切到了新的底层文件，之前遗留的 seek 排队状态、以及可能在途的报错重载都已经没有意义
    this._clearPendingSeekState();
    this._clearVideoReloadTimer();
    this._isReloading = false;
    this.setData({ playerUrl: url, playerTitle: title, videoPaused: false, videoBuffering: true });

    if (this._dayStartMs) {
      this._centerTimelineAtTime(fileStartTimeMs + (offsetSec || 0) * 1000, true);
    }
  },

  /**
   * 下发 seek 指令。<video> 组件的 seek 是异步的，若同一时刻已有一次 seek 在途
   * （尚未收到 bindseeked），这里不会立即再发一次，只记录最新目标；等上一次
   * seek 真正完成后（onVideoSeeked）再补发一次，从而保证任意时刻只有一条 seek
   * 指令在途。否则连续快速拖拽时端上会连续收到多条 seek 指令，内部状态错乱，
   * 偶现「反复跳回某个固定片段」的问题。
   */
  _seekVideoTo(offsetSec: number) {
    if (this._isSeeking) {
      this._pendingSeekOffsetSec = offsetSec;
      return;
    }
    this._doSeekVideoTo(offsetSec);
  },

  _doSeekVideoTo(offsetSec: number) {
    const ctx = wx.createVideoContext ? wx.createVideoContext('cs-video-player', this) : null;
    if (!ctx) return;
    this._isSeeking = true;
    this._pendingSeekOffsetSec = null;
    this._clearSeekSafetyTimer();
    // 兜底：极少数情况下 bindseeked 可能不触发（如组件被卸载），一段时间后强制
    // 复位，避免 _isSeeking 卡死导致后续 seek 请求永远被排队而发不出去。
    this._seekSafetyTimer = setTimeout(() => this._onSeekSettled(), 2000);
    try {
      ctx.seek(offsetSec);
    } catch (err) {
      this._onSeekSettled();
    }
  },

  /** 上一次 seek 已经结束（收到 bindseeked，或兜底超时）：若期间有新目标，补发一次 */
  _onSeekSettled() {
    this._clearSeekSafetyTimer();
    this._isSeeking = false;
    if (this._pendingSeekOffsetSec !== null) {
      const next = this._pendingSeekOffsetSec;
      this._pendingSeekOffsetSec = null;
      this._doSeekVideoTo(next);
    }
  },

  _clearSeekSafetyTimer() {
    if (this._seekSafetyTimer) {
      clearTimeout(this._seekSafetyTimer);
      this._seekSafetyTimer = 0;
    }
  },

  _clearPendingSeekState() {
    this._clearSeekSafetyTimer();
    this._isSeeking = false;
    this._pendingSeekOffsetSec = null;
  },

  /** <video> 组件通知一次 seek 操作已经完成 */
  onVideoSeeked() {
    this._onSeekSettled();
    // 暂停状态下拖时间轴定位后不会再有 timeupdate 上报，缓冲动画需要在 seek 完成时直接收起
    if (this.data.videoPaused && this.data.videoBuffering) {
      this.setData({ videoBuffering: false });
    }
  },

  /** 播放中途因分片下载不足进入缓冲：展示加载动画，数据就绪恢复播放后由 timeupdate 收起 */
  onVideoWaiting() {
    if (this.data.playerUrl && !this.data.videoPaused && !this.data.videoBuffering) {
      this.setData({ videoBuffering: true });
    }
  },

  /**
   * 判断本次播放会话是否已经「真正开始」，即 currentTime 反映的位置确实落进了用户请求的
   * 播放窗口 [startWallMs, endWallMs) 内（起点侧留 PLAYBACK_ENTER_TOLERANCE_MS 容差，
   * 用于容忍 seek 落到目标前的关键帧）。
   *
   * 为什么必须有这一步：seek 是异步的，在它生效之前 currentTime 还是**上一个位置**——
   * 切换新文件时是 0、解码报错重载后也是 0、同一文件内 seek 时则是 seek 之前的旧位置。
   * 这段时间里的 currentTime 既不能用来定位时间轴（否则指示器会被拽到文件开头，表现为
   * 「松手后跳回其它位置」），更不能用来做结束判断：
   * 典型例子是先把时间轴拖到 14:56 播放，再点 14:51 的事件（向后 seek），旧位置 14:56
   * 已经超过了新会话的结束点 14:51:34，若照常做结束判断就会立刻误判「播放结束」。
   *
   * 一旦进入窗口就置位，之后按正常逻辑跟随进度并做结束判断。若seek 落点早于起点容差，
   * 播放向前推进几秒后自然进入，不会永久卡住。
   *
   * 另有时间兜底：seek 落点也可能**越过**结束点（短事件遇上稀疏关键帧），此时上界条件永远
   * 不成立，会既不跟随也不结束地一直播下去。因此超过 PLAYBACK_ENTER_FALLBACK_MS 后强制
   * 视为已进入，交还给正常逻辑处理（该等待时间足够 seek 生效，不会重新引发旧位置误判）。
   */
  _hasPlaybackEnteredSession(wallMs: number): boolean {
    if (this._playerEnteredSession) return true;
    const afterStart = wallMs >= this._playerStartWallMs - PLAYBACK_ENTER_TOLERANCE_MS;
    const beforeEnd = !this._playerEndWallMs || wallMs < this._playerEndWallMs;
    const waitedTooLong =
      !!this._playerSessionStartedAt &&
      Date.now() - this._playerSessionStartedAt > PLAYBACK_ENTER_FALLBACK_MS;
    if ((!afterStart || !beforeEnd) && !waitedTooLong) return false;
    this._playerEnteredSession = true;
    return true;
  },

  _stopPlayer() {
    this._playerSeeked = false;
    this._playerOffsetSec = 0;
    this._playerFileStartTimeMs = 0;
    this._playerEndWallMs = 0;
    this._videoErrorRetryCount = 0;
    this._playerStartWallMs = 0;
    this._playerEnteredSession = false;
    this._playerSessionStartedAt = 0;
    this._lastProgressTimeSec = 0;
    this._lastErrorTimeSec = -1;
    this._clearPendingSeekState();
    this._clearVideoReloadTimer();
    this._isReloading = false;
    if (!this.data.playerUrl) {
      // 报错重载的「清空 src」窗口期里 playerUrl 为空但缓冲动画还开着，这里一并收起
      if (this.data.videoBuffering) {
        this.setData({ videoBuffering: false });
      }
      return;
    }
    const ctx = wx.createVideoContext ? wx.createVideoContext('cs-video-player', this) : null;
    try {
      ctx && ctx.stop();
    } catch (err) {
      // 忽略：video 组件可能已随页面切换被销毁
    }
    this.setData({ playerUrl: '', playerTitle: '', videoPaused: false, videoBuffering: false });
  },

  /** 视频元数据加载完成：seek 到事件在文件内的起始偏移，而不是从文件开头播放 */
  onVideoLoadedMetadata() {
    // 新的一次加载已经就绪，解除「重载在途」，后续若再报错才允许发起下一次重载
    this._isReloading = false;
    if (this._playerSeeked || this._playerOffsetSec <= 0) return;
    this._playerSeeked = true;
    this._seekVideoTo(this._playerOffsetSec);
  },

  /**
   * 播放进度更新：
   *   1. 换算回墙钟时间，到达事件结束点后自动停止（而不是播完整段底层文件）；
   *   2. 若用户当前没有在拖拽时间轴，则让时间轴指示线跟随播放进度自动居中，
   *      与安卓端 updatePlayProgressFromPlayer -> centerTimelineAtTime 语义一致。
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onVideoTimeUpdate(e: any) {
    // seek 尚未真正完成前，currentTime 可能还停留在旧位置（甚至是上一段 seek
    // 目标附近），不能拿它去定位时间轴或做结束判断，否则会出现指示器来回跳动，
    // 或者用旧的 currentTime 误判「已到达结束点」的问题，因此要放在最前面判断。
    if (this._isSeeking) return;

    // 有真实的播放进度上报，说明数据已经就绪、画面在出帧，收起加载/缓冲动画
    if (this.data.videoBuffering) {
      this.setData({ videoBuffering: false });
    }

    const currentTimeSec = (e && e.detail && e.detail.currentTime) || 0;
    const wallMs = this._playerFileStartTimeMs + currentTimeSec * 1000;

    // 播放进度确实在往前推进，说明当前这段解码是健康的，补回错误重试预算。
    // 这一步必须放在下面的「是否已进入会话」判断之前：等待 seek 生效期间会一直提前返回，
    // 若把补预算放在后面，这段时间的瞬时报错会不断消耗预算且永不恢复，最终误报「播放失败」。
    //
    // 但补预算必须以「已经越过上次报错的坏点」为前提：坏点固定在码流的某个位置，报错后重载
    // 又会重新播到那里，若只要进度推进就无条件补满预算，重试次数永远耗不尽，就会变成
    // 「播一段 -> 报错 -> 重载 -> 再播到同一处报错」的无限循环。
    if (currentTimeSec > this._lastProgressTimeSec + PROGRESS_EPSILON_SEC) {
      const passedLastError =
        this._lastErrorTimeSec < 0 ||
        currentTimeSec > this._lastErrorTimeSec + ERROR_RECOVERY_PROGRESS_SEC;
      if (passedLastError) {
        this._videoErrorRetryCount = 0;
        this._lastErrorTimeSec = -1;
      }
    }
    this._lastProgressTimeSec = currentTimeSec;

    // seek 生效前 currentTime 还是旧位置（切新文件/报错重载时是 0，同一文件内 seek 时是
    // seek 之前的位置），此时既不能拿它定位时间轴，也绝不能拿它做结束判断，否则向后 seek
    // 时旧位置会超过新会话的结束点而误判「播放结束」。因此放在结束判断之前。
    if (!this._hasPlaybackEnteredSession(wallMs)) return;

    if (this._playerEndWallMs && wallMs >= this._playerEndWallMs) {
      this._stopPlayer();
      wx.showToast({ title: '播放结束', icon: 'none' });
      return;
    }
    // 用户正在拖时间轴（竖屏或全屏）时不要跟随播放进度自动居中，否则会和手指抢夺控制权，
    // 表现为拖动过程中指示器反复往回跳。
    //
    // 播放位置还必须落在「当前选中日期」这一天之内：切换日期/通道时已经会停止播放，这里
    // 主要兜住跨零点的录像（例如 23:50 开始、持续 20 分钟的文件播到了次日），避免其墙钟
    // 时间越过当天范围后被 _centerTimelineAtTime 的 clamp 夹到 23:59:59 而卡在末尾。
    if (
      !this._isTimelineDragging &&
      !this._isFsTimelineDragging &&
      this._playerFileStartTimeMs &&
      this._dayStartMs &&
      wallMs >= this._dayStartMs &&
      wallMs < this._dayStartMs + DAY_MS
    ) {
      this._centerTimelineAtTime(wallMs, false);
    }
  },

  /**
   * 解码/播放错误处理：SPS 解析失败等 `PIPELINE_ERROR_DECODE` 类错误多为局部性故障
   * （长录像文件中途编码参数变化、某个分片损坏、网络抖动打断分片下载等），
   * 遇到就直接向后跳过 ERROR_RESUME_SKIP_SEC 续播，越过损坏的那一小段码流。
   *
   * 没有设置「重试几次就放弃」的上限：只要播放能持续推进，连续报错计数就会被清零
   * （见 onVideoTimeUpdate），长录像里散布的一两个坏片段会被逐个跳过，直到播放成功，
   * 全程不打断用户。MAX_CONSECUTIVE_VIDEO_ERRORS 只兜住「接连多段码流全部损坏 /
   * 网络持续不可用」这种怎么跳都不可能恢复的情况，避免无限重载闪屏。
   *
   * 关键：恢复位置必须是「报错点之后」而不是本次会话的原起点。坏点固定在码流的某个位置，
   * 从原起点重载只会重新播到同一处再次报错，表现为「播一段就跳回去重播」的死循环（每循环
   * 一次打一条 error 日志）。
   *
   * 重载是「清空 src 再恢复」，视觉上会闪一下，因此还要避免重载叠加与紧密循环：
   *   - 同一时刻只允许一次重载在途（_isReloading，收到 loadedmetadata 才解除），否则
   *     短时间内多个 error 回调会各自触发一次重载，表现为同一帧反复闪烁；
   *   - 重载之间留一小段间隔，避免「重载 -> 立刻又报错」形成紧密循环把画面刷成闪屏。
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onVideoError(e: any) {
    const url = this.data.playerUrl;
    const errorAtSec = Math.max(this._lastProgressTimeSec, this._playerOffsetSec);
    // 重载在途期间的重复报错只记一行简讯，避免同一个坏点把控制台刷满
    if (this._isReloading) {
      console.warn('[cloud-storage] another decode error while reloading, ignored');
      return;
    }
    this._logVideoErrorSource(e && e.detail, url, errorAtSec);

    if (url && this._videoErrorRetryCount < MAX_CONSECUTIVE_VIDEO_ERRORS) {
      const resumeSec = errorAtSec + ERROR_RESUME_SKIP_SEC;
      // 跳过坏点后已经越过本次会话该播的范围，说明内容其实已经播完，按正常结束处理，
      // 不要再重载，也不该提示播放失败
      if (
        this._playerEndWallMs &&
        this._playerFileStartTimeMs + resumeSec * 1000 >= this._playerEndWallMs
      ) {
        this._stopPlayer();
        wx.showToast({ title: '播放结束', icon: 'none' });
        return;
      }

      this._isReloading = true;
      this._videoErrorRetryCount += 1;
      this._lastErrorTimeSec = errorAtSec;
      this._playerSeeked = false;
      this._playerOffsetSec = resumeSec;
      this._playerStartWallMs = this._playerFileStartTimeMs + resumeSec * 1000;
      this._playerEnteredSession = false;
      this._lastProgressTimeSec = 0;
      this._clearPendingSeekState();
      // 直接把同一个 src 再赋值一次不一定会触发 <video> 组件重新拉流，
      // 先清空再恢复，强制它重新加载。
      this.setData({ playerUrl: '', videoBuffering: true }, () => {
        this._videoReloadTimer = setTimeout(() => this._doReloadPlayer(url), VIDEO_RELOAD_DELAY_MS);
      });
      return;
    }

    this._videoErrorRetryCount = 0;
    wx.showToast({ title: '播放失败', icon: 'none' });
    this._stopPlayer();
  },

  /**
   * 播放出错时打印足够定位问题源的信息：录像文件地址、出错处在文件内的偏移、对应的墙钟
   * 时间、以及本次会话请求的播放区间。便于把地址与偏移交给 ffmpeg/ffprobe 复核这一段
   * 码流本身是否损坏（多个不同时间点反复出错时，基本可以判定是媒体源的问题）。
   */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  _logVideoErrorSource(detail: any, url: string, errorAtSec: number) {
    const fileStartMs = this._playerFileStartTimeMs;
    const errorWallMs = fileStartMs + errorAtSec * 1000;
    const isHls = url.indexOf('.m3u8') >= 0;
    console.warn('[cloud-storage] video error:', JSON.stringify(detail));
    console.warn(
      '[cloud-storage] failed source:',
      JSON.stringify({
        streamFormat: isHls ? 'HLS' : 'progressive',
        failedAtOffsetSec: Number(errorAtSec.toFixed(3)),
        failedAtClockTime: fileStartMs ? fmtTimeOfDay(errorWallMs) : '',
        fileStartClockTime: fileStartMs ? fmtTimeOfDay(fileStartMs) : '',
        sessionEndClockTime: this._playerEndWallMs ? fmtTimeOfDay(this._playerEndWallMs) : '',
        retriedTimes: this._videoErrorRetryCount,
      }),
    );
    console.warn('[cloud-storage] failed source url:', url);
  },

  _doReloadPlayer(url: string) {
    this._videoReloadTimer = 0;
    // 期间可能已经被停止播放或切到了别的录像，此时不该再把旧地址恢复回去
    if (!this._isReloading) return;
    this._playerSessionStartedAt = Date.now();
    this.setData({ playerUrl: url });
  },

  _clearVideoReloadTimer() {
    if (this._videoReloadTimer) {
      clearTimeout(this._videoReloadTimer);
      this._videoReloadTimer = 0;
    }
  },

  onToggleMute() {
    this.setData({ videoMuted: !this.data.videoMuted });
  },

  /** 暂停/继续播放，悬浮按钮驱动，对齐安卓端 iotPlayerFloatControls 的暂停按钮 */
  onTogglePause() {
    if (!this.data.playerUrl) return;
    const ctx = wx.createVideoContext ? wx.createVideoContext('cs-video-player', this) : null;
    const nextPaused = !this.data.videoPaused;
    try {
      if (ctx) {
        if (nextPaused) {
          ctx.pause();
        } else {
          ctx.play();
        }
      }
    } catch (err) {
      // 忽略
    }
    this.setData({ videoPaused: nextPaused });
  },

  /** <video> 原生播放事件：与悬浮暂停按钮的状态保持同步（例如系统控件触发的播放/暂停） */
  onVideoPlay() {
    if (this.data.videoPaused) {
      this.setData({ videoPaused: false });
    }
  },

  onVideoPause() {
    // 暂停后不会再有缓冲概念（缓冲动画只应出现在「正在等数据恢复播放」期间）
    if (!this.data.videoPaused || this.data.videoBuffering) {
      this.setData({ videoPaused: true, videoBuffering: false });
    }
  },

  /** 进入原生全屏（系统级真横屏，截屏/状态栏方向都正确）。
   *  明确传direction 而不是让基础库按视频宽高比自动判断：云存录像都是横屏视频，但自动
   *  判断依赖 metadata，实测存在判成竖屏的情况，这里固定按横屏进入。
   *  全屏内需要展示的自定义内容已放在 video 节点内部（见 wxml 的 cs-fs-overlay）。 */
  onToggleFullscreen() {
    const ctx = wx.createVideoContext ? wx.createVideoContext('cs-video-player', this) : null;
    try {
      ctx && ctx.requestFullScreen({ direction: FULLSCREEN_DIRECTION });
    } catch (err) {
      // 忽略
    }
  },

  /** 退出原生全屏：点击左上角返回按钮 / 右侧悬浮按钮触发 */
  onExitFullscreen() {
    const ctx = wx.createVideoContext ? wx.createVideoContext('cs-video-player', this) : null;
    try {
      ctx && ctx.exitFullScreen();
    } catch (err) {
      // 忽略
    }
  },

  /** <video> 全屏状态变化：进入/退出全屏都由该事件统一驱动 isFullscreen，这样用户通过
   *  系统返回手势退出全屏时状态也能正确同步 */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onVideoFullscreenChange(e: any) {
    const fullScreen = !!(e && e.detail && e.detail.fullScreen);
    if (fullScreen === this.data.isFullscreen) return;
    this.setData({ isFullscreen: fullScreen });
    if (fullScreen) {
      this._enterFullscreenTimeline();
    } else {
      this._exitFullscreenTimeline();
    }
  },

  /** 进入全屏时展示全屏内的录像带式进度条并开始自动隐藏倒计时。
   *
   *  视口宽度直接取「屏幕长边」，不做 selectorQuery 异步测量：全屏后视频铺满横屏，其宽度
   *  必然是屏幕长边，是确定值；而异步测量在全屏切换动画期间拿到的是非全屏的布局宽度（竖屏
   *  短边），一旦用它覆盖就会让几何计算误以为视口中心在屏幕短边的一半处，而指示线实际是
   *  CSS left:50% 固定在真实视口中心，两者错位会导致「气泡显示的时间」和「指示线停的位置」
   *  相差好几个小时。*/
  _enterFullscreenTimeline() {
    this._isFsTimelineDragging = false;
    this._fsDragLastClientX = null;
    this._clearFsTimelineIdleTimer();
    const width = this._getFullscreenViewportWidth();
    this.setData(
      {
        fsControlsVisible: true,
        fsTimelineViewportWidth: width,
        fsTimelineSidePadding: width / 2,
      },
      () => {
        this._rebuildFsTimelineGeometry();
        this._centerTimelineAtTime(this._timelineLastCenterMs || this._dayStartMs, false);
      },
    );
    this._scheduleFsHideTimer();
  },

  /** 全屏（横屏）下时间轴视口宽度 = 屏幕长边 */
  _getFullscreenViewportWidth(): number {
    const sys = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
    const longEdge = Math.max(
      sys.screenWidth || 0,
      sys.screenHeight || 0,
      sys.windowWidth || 0,
      sys.windowHeight || 0,
    );
    return longEdge || 667;
  },

  /** 退出全屏时清理相关定时器/拖拽状态 */
  _exitFullscreenTimeline() {
    this._clearFsHideTimer();
    this._clearFsTimelineIdleTimer();
    this._isFsTimelineDragging = false;
    this._fsDragLastClientX = null;
  },

  _scheduleFsHideTimer() {
    this._clearFsHideTimer();
    this._fsHideTimer = setTimeout(() => this._onFsHideTimerFired(), FS_CONTROLS_HIDE_MS);
  },

  _onFsHideTimerFired() {
    this._fsHideTimer = 0;
    if (!this.data.isFullscreen || this._isFsTimelineDragging) return;
    this.setData({ fsControlsVisible: false });
  },

  _clearFsHideTimer() {
    if (this._fsHideTimer) {
      clearTimeout(this._fsHideTimer);
      this._fsHideTimer = 0;
    }
  },

  /** 点击全屏内视频区域（时间轴以外）：显示/隐藏录像带式进度条，对齐常见播放器的点按呼出交互 */
  onVideoTap() {
    if (!this.data.isFullscreen) return;
    if (this.data.fsControlsVisible) {
      this._clearFsHideTimer();
      this.setData({ fsControlsVisible: false });
    } else {
      this.setData({ fsControlsVisible: true });
      this._scheduleFsHideTimer();
    }
  },

  /** 点击全屏内的时间轴区域：仅保持常显 + 重置自动隐藏倒计时，不触发显隐切换 */
  onFsTimelineTap() {
    if (!this.data.isFullscreen) return;
    this.setData({ fsControlsVisible: true });
    this._scheduleFsHideTimer();
  },
});

export {};
