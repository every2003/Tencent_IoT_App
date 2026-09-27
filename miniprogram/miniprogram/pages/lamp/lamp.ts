// pages/lamp/lamp.ts
// 智能吸顶灯控制页（对齐 iOS LampDetailView，测试用）。
//
// 物模型（lamp_data_model.json）：
//   - power_switch：bool，0 关 / 1 开
//   - brightness：int，1~100，单位 %
//   - color_temp：int，2700~6500，步进 100，单位 K
//   - light_mode：enum，0 手动 / 1 阅读 / 2 休闲 / 3 夜灯
//
// 入参（query）：
//   - productId   产品 ID（必填）
//   - deviceName  设备名（必填）
//   - name        设备别名（可选，作标题）
//
// 数据流：page → utils/iotEngine → tx-iot-sdk（getProperties / sendCommand）。
import { getDeviceProperties, sendDeviceCommand } from '../../utils/iotEngine';

interface LampData {
  title: string;
  powerOn: boolean;
  brightness: number;
  colorTemp: number;
  lightMode: number;
  loading: boolean;
  [key: string]: unknown;
}

/** 物模型属性值可能为 Int/Bool/Double/String，统一转 number（对齐 iOS intValue） */
function intValue(raw: unknown): number | null {
  if (typeof raw === 'number') return raw;
  if (typeof raw === 'boolean') return raw ? 1 : 0;
  if (typeof raw === 'string') {
    const n = parseInt(raw, 10);
    return isNaN(n) ? null : n;
  }
  return null;
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
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

Page<LampData, WechatMiniprogram.IAnyObject>({
  data: {
    title: '吸顶灯',
    powerOn: false,
    brightness: 80,
    colorTemp: 4000,
    lightMode: 0,
    loading: false,
  },

  productId: '',
  deviceName: '',

  onLoad(query: Record<string, string>) {
    this.productId = decodeParam(query.productId || '');
    this.deviceName = decodeParam(query.deviceName || '');
    const name = decodeParam(query.name || '') || this.deviceName || this.productId || '吸顶灯';
    wx.setNavigationBarTitle({ title: name });
    this.setData({ title: name });
    if (!this.productId || !this.deviceName) {
      wx.showToast({ title: '设备信息不完整', icon: 'none' });
      return;
    }
    this.loadProperties();
  },

  onPullDownRefresh() {
    this.loadProperties(() => wx.stopPullDownRefresh());
  },

  /** 拉取设备属性并同步到页面状态 */
  loadProperties(done?: () => void) {
    if (!this.productId || !this.deviceName) {
      if (done) done();
      return;
    }
    this.setData({ loading: true });
    getDeviceProperties(this.productId, this.deviceName)
      .then((result) => {
        this.setData({ loading: false });
        this.applyProperties(result);
        if (done) done();
      })
      .catch((err: Error) => {
        this.setData({ loading: false });
        console.error('[lamp] getProperties failed', err);
        wx.showToast({ title: err.message || '获取属性失败', icon: 'none' });
        if (done) done();
      });
  },

  /** 解析 getProperties 返回（兼容顶层平铺或 properties/data 嵌套，对齐 iOS applyProperties） */
  applyProperties(result: unknown) {
    if (!result || typeof result !== 'object') return;
    const root = result as Record<string, unknown>;
    const props =
      (root.properties && typeof root.properties === 'object' ? root.properties as Record<string, unknown> : null) ||
      (root.data && typeof root.data === 'object' ? root.data as Record<string, unknown> : null) ||
      root;
    const patch: Partial<LampData> = {};
    const power = intValue(props.power_switch);
    if (power !== null) patch.powerOn = power !== 0;
    const brightness = intValue(props.brightness);
    if (brightness !== null) patch.brightness = clamp(brightness, 1, 100);
    const colorTemp = intValue(props.color_temp);
    if (colorTemp !== null) patch.colorTemp = clamp(colorTemp, 2700, 6500);
    const lightMode = intValue(props.light_mode);
    if (lightMode !== null) patch.lightMode = clamp(lightMode, 0, 3);
    this.setData(patch);
  },

  /** 下发控制指令 */
  controlProperty(propertyId: string, value: number) {
    if (!this.productId || !this.deviceName) return;
    sendDeviceCommand(this.productId, this.deviceName, { [propertyId]: value })
      .then(() => {
        console.info('[lamp] sendCommand ok:', propertyId, '=', value);
      })
      .catch((err: Error) => {
        console.error('[lamp] sendCommand failed:', propertyId, value, err);
        wx.showToast({ title: err.message || '下发失败', icon: 'none' });
      });
  },

  // ---- 电源开关 ----
  onPowerChange(e: WechatMiniprogram.SwitchChange) {
    const on = !!e.detail.value;
    this.setData({ powerOn: on });
    this.controlProperty('power_switch', on ? 1 : 0);
  },

  // ---- 亮度（拖动只更新显示，松手才下发，对齐 iOS onBrightnessEdit）----
  onBrightnessChanging(e: WechatMiniprogram.SliderChange) {
    this.setData({ brightness: e.detail.value });
  },

  onBrightnessChange(e: WechatMiniprogram.SliderChange) {
    this.setData({ brightness: e.detail.value });
    this.controlProperty('brightness', e.detail.value);
  },

  // ---- 色温（同上，松手才下发）----
  onColorTempChanging(e: WechatMiniprogram.SliderChange) {
    this.setData({ colorTemp: e.detail.value });
  },

  onColorTempChange(e: WechatMiniprogram.SliderChange) {
    this.setData({ colorTemp: e.detail.value });
    this.controlProperty('color_temp', e.detail.value);
  },

  // ---- 场景模式 ----
  onModeSelect(e: WechatMiniprogram.TouchEvent) {
    const mode = Number((e.currentTarget.dataset as { mode: string }).mode);
    this.setData({ lightMode: mode });
    this.controlProperty('light_mode', mode);
  },
});
