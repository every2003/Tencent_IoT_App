//
//  CloudStorageModels.swift
//  TXIoTDemo
//
//  云存储模块的数据模型与共享 DateFormatter。
//

import Foundation

// MARK: - 数据模型（SwiftUI 友好，值语义）

/// 单个云存视频文件（对应 TXIoTVideoFile）
///
/// - `startTimeMs`: 视频文件第一帧对应的墙上时间（毫秒，UTC）
/// - `durationMs`:  视频文件自身时长（毫秒）
///   因此该文件覆盖的墙上时间区间为 `[startTimeMs, startTimeMs + durationMs)`
struct CloudVideoFile: Identifiable, Hashable {
    let id = UUID()
    let videoUrl: String
    let vodAppId: String
    let vodFileId: String
    let vodPlaySign: String
    let startTimeMs: Int64
    let durationMs: Int64

    /// 文件结束墙上时间（毫秒，开区间）
    var endTimeMs: Int64 { startTimeMs + max(durationMs, 0) }
}

/// 单条云存事件（对应 TXIoTEvent）
///
/// - `eventTimeMs`: 事件触发的墙上时间（毫秒）。注意它**不一定**等于
///   `videoFiles.first.startTimeMs`，例如带预录的视频文件会比 eventTimeMs 早一段。
/// - `durationMs`:  事件本身的时长（毫秒），进度条以此为准，而非各视频文件时长之和。
struct CloudEventItem: Identifiable, Hashable {
    let id = UUID()
    let eventType: String
    let thumbnailUrl: String
    let eventTimeMs: Int64
    let durationMs: Int64
    let videoFiles: [CloudVideoFile]

    /// 事件发生时刻（eventTimeMs 对应的 Date）。
    /// 注意：不能用视频文件的 startTimeMs 代表事件起点 ——
    /// 一个视频文件可能横跨多个事件，一个事件也可能横跨多个视频文件。
    var eventDate: Date {
        Date(timeIntervalSince1970: TimeInterval(eventTimeMs) / 1000.0)
    }

    /// 按 startTimeMs 升序排序后的视频文件列表（播放队列）
    var sortedVideoFiles: [CloudVideoFile] {
        videoFiles.sorted { $0.startTimeMs < $1.startTimeMs }
    }

    /// 抓图事件：视频文件列表为空时，表示该事件仅有缩略图、没有视频
    var isSnapshot: Bool { videoFiles.isEmpty }

    /// TXIoTEvent.eventType 中文化（未知类型原样返回）
    /// 取值约定（与设备端 / 平台规范一致）：
    /// "1"  门铃呼叫事件 / "2"  运动检测事件 / "3"  人形检测事件
    /// "4"  区域入侵事件 / "5"  区域徘徊事件 / "6"  异常声音事件
    /// "100" 人脸识别抓拍 / "101" 开门状态抓拍
    var displayName: String {
        switch eventType {
        case "1": return L("Doorbell Call")
        case "2": return L("Motion Detection")
        case "3": return L("Human Detection")
        case "4": return L("Area Intrusion")
        case "5": return L("Area Loitering")
        case "6": return L("Abnormal Sound")
        case "100": return L("Face Recognition Snapshot")
        case "101": return L("Door Status Snapshot")
        default: return eventType.isEmpty ? L("Event") : eventType
        }
    }
}

// MARK: - 共享 DateFormatter（避免在列表/卡片中反复构造）

enum CloudDateFormatters {
    static let yyyyMMdd: DateFormatter = make("yyyy-MM-dd")
    static let dd: DateFormatter = make("dd")
    /// 月份缩写：随系统语言本地化（中文 "M月"，英文 "MMM"）
    static let month: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMM", options: 0, locale: .current)
        return df
    }()
    /// 星期缩写：使用当前系统语言，不再写死中文
    static let weekday: DateFormatter = make("EE")
    static let HHmmss: DateFormatter = make("HH:mm:ss")
    static let MMddHHmmss: DateFormatter = make("MM-dd HH:mm:ss")

    private static func make(_ fmt: String) -> DateFormatter {
        let df = DateFormatter()
        df.dateFormat = fmt
        return df
    }
}

extension Date {
    /// 当日内的秒数（0 ~ 86400，按本地时区）
    var secondsOfDay: Double {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: self)
        let hour = Double(comps.hour ?? 0) * 3600
        let minute = Double(comps.minute ?? 0) * 60
        let second = Double(comps.second ?? 0)
        return hour + minute + second
    }
}
