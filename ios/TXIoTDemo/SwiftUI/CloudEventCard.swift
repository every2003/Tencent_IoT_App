//
//  CloudEventCard.swift
//  TXIoTDemo
//
//  云存日期 Chip 与事件卡片视图。
//

import SwiftUI

// MARK: - 日期 Chip

struct DayChip: View {
    let day: String  // "yyyy-MM-dd"
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(weekdayText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .textSecondary)
                Text(dayText)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : .textPrimary)
                Text(monthText)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .textDisabled)
            }
            .frame(width: 54, height: 64)
            .background(chipBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.borderColor, lineWidth: 1)
            )
            .cornerRadius(12)
            .shadow(
                color: isSelected ? Color.primaryColor.opacity(0.25) : .clear,
                radius: 6,
                x: 0,
                y: 3
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            LinearGradient(
                colors: [Color.primaryColor, Color.primaryColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.cardBg
        }
    }

    private var parsedDate: Date? {
        CloudDateFormatters.yyyyMMdd.date(from: day)
    }

    private var weekdayText: String {
        guard let d = parsedDate else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("Today") }
        if cal.isDateInYesterday(d) { return L("Yesterday") }
        return CloudDateFormatters.weekday.string(from: d)
    }

    private var dayText: String {
        guard let d = parsedDate else { return String(day.suffix(2)) }
        return CloudDateFormatters.dd.string(from: d)
    }

    private var monthText: String {
        guard let d = parsedDate else { return "" }
        return CloudDateFormatters.month.string(from: d)
    }
}

// MARK: - 事件卡片

struct CloudEventCard: View {
    let event: CloudEventItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                thumbnailView
                    .frame(width: 116, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.borderColor.opacity(0.6), lineWidth: 0.5)
                    )

                eventInfoContent
            }
            .padding(10)
            .background(Color.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.primaryColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(14)
            .shadow(
                color: isSelected ? Color.primaryColor.opacity(0.25) : Color.black.opacity(0.06),
                radius: isSelected ? 8 : 6,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var eventInfoContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            eventTitleRow
            Text(timeText)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.textPrimary)
            eventActionHint
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var eventTitleRow: some View {
        HStack(spacing: 6) {
            Text(event.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primaryColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primaryColor.opacity(0.12))
                .cornerRadius(6)

            Spacer()

            if !event.isSnapshot {
                Text(durationText)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var eventActionHint: some View {
        HStack(spacing: 4) {
            Image(systemName: event.isSnapshot ? "photo.fill" : "play.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.primaryColor)
            Text(event.isSnapshot ? L("Tap to view image") : L("Tap to play video"))
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack {
            thumbnailImage
            playIconOverlay
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let url = URL(string: event.thumbnailUrl), !event.thumbnailUrl.isEmpty {
            AsyncImage(url: url) { phase in
                thumbnailImageForPhase(phase)
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private func thumbnailImageForPhase(_ phase: AsyncImagePhase) -> some View {
        if case .success(let image) = phase {
            image.resizable().scaledToFill()
        } else {
            placeholder
        }
    }

    private var playIconOverlay: some View {
        Image(systemName: event.isSnapshot ? "photo.fill" : "play.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white)
            .padding(8)
            .background(Color.black.opacity(0.4))
            .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            Color.headerGradient
            Image(systemName: event.isSnapshot ? "photo.fill" : "video.fill")
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private var timeText: String {
        CloudDateFormatters.HHmmss.string(from: event.eventDate)
    }

    private var durationText: String {
        let sec = max(Int(event.durationMs / 1000), 0)
        if sec < 60 { return "\(sec)s" }
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}
