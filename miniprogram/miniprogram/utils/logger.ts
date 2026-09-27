// 插件统一日志模块。
// - 业务侧可通过 setLogLevel('silent' | 'error' | 'warn' | 'info' | 'debug') 调整级别
// - 默认 'warn'：避免真机生产环境输出大量噪声 / 隐私数据
// - 插件内部模块（utils/iotEngine 等）一律通过此模块打日志，禁止裸写 console.log
//
// 设计要点：
//  1. 仅作开关。日志格式由调用方决定，本模块只追加 [tx-iot-sdk] 前缀。
//  2. 不持久化日志。小程序里 `console.*` 真机会进 vConsole / 日志文件，本模块只控制是否调用。
//  3. 不引入第三方依赖，纯函数 + 模块级 currentLevel，方便 wasm/胶水层共享。

export type LogLevel = 'silent' | 'error' | 'warn' | 'info' | 'debug';

const LEVEL_WEIGHT: Record<LogLevel, number> = {
  silent: 0,
  error: 1,
  warn: 2,
  info: 3,
  debug: 4,
};

let currentLevel: LogLevel = 'warn';
const TAG = '[tx-iot-sdk]';

export function setLogLevel(level: LogLevel): void {
  if (!(level in LEVEL_WEIGHT)) {
    // 非法 level 时静默忽略，避免破坏业务调用链
    return;
  }
  currentLevel = level;
}

export function getLogLevel(): LogLevel {
  return currentLevel;
}

function enabled(level: LogLevel): boolean {
  return LEVEL_WEIGHT[level] <= LEVEL_WEIGHT[currentLevel];
}

/* eslint-disable @typescript-eslint/no-explicit-any */
export function error(...args: any[]): void {
  if (enabled('error')) console.error(TAG, ...args);
}

export function warn(...args: any[]): void {
  if (enabled('warn')) console.warn(TAG, ...args);
}

export function info(...args: any[]): void {
  if (enabled('info')) console.info(TAG, ...args);
}

export function debug(...args: any[]): void {
  if (enabled('debug')) console.log(TAG, ...args);
}
/* eslint-enable @typescript-eslint/no-explicit-any */

export const logger = { setLogLevel, getLogLevel, error, warn, info, debug };
