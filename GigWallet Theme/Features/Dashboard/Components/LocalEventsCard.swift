import SwiftUI

/// Dashboard card showing upcoming local events with demand impact badges.
/// Shows top 3 events with an expandable "See All" to view the full list.
struct LocalEventsCard: View {
    let events: [EventAlertService.LocalEvent]
    let weatherNote: String?

    @State private var isExpanded = false

    private var displayedEvents: [EventAlertService.LocalEvent] {
        isExpanded ? events : Array(events.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(BrandColors.primary)
                    .font(.system(size: 16))

                Text("Local Events")
                    .font(Typography.headline)

                Spacer()

                if events.count > 3 {
                    Button {
                        HapticManager.shared.tap()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Text(isExpanded ? "Show Less" : "See All \(String(events.count))")
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(BrandColors.primary)
                    }
                    .buttonStyle(.plain)
                } else if !events.isEmpty {
                    Text("\(String(events.count)) upcoming")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }

            // Weather boost note
            if let weatherNote, !weatherNote.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "cloud.rain.fill")
                        .foregroundStyle(BrandColors.info)
                        .font(.system(size: 14))

                    Text(weatherNote)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.info)
                }
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BrandColors.info.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
            }

            if events.isEmpty {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(BrandColors.textTertiary)
                    Text("No major events nearby")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(displayedEvents) { event in
                        eventRow(event)
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        .shadow(color: BrandColors.cardShadow, radius: 4, y: 2)
    }

    // MARK: - Event Row

    private func eventRow(_ event: EventAlertService.LocalEvent) -> some View {
        HStack(spacing: Spacing.md) {
            // Category icon
            ZStack {
                Circle()
                    .fill(event.category.color.opacity(0.1))
                    .frame(width: 36, height: 36)

                Image(systemName: event.category.sfSymbol)
                    .font(.system(size: 14))
                    .foregroundStyle(event.category.color)
            }

            // Event info
            VStack(alignment: .leading, spacing: 1) {
                Text(event.name)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    Text(event.venue)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                        .lineLimit(1)

                    Text("\u{00B7}")
                        .foregroundStyle(BrandColors.textTertiary)

                    Text(formatEventDate(event.date))
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }

            Spacer()

            // Demand boost badge
            if event.demandBoost >= .moderate {
                Text(event.demandBoost.multiplierText)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 3)
                    .background(event.demandBoost.color)
                    .clipShape(Capsule())
            }
        }
    }

    private func formatEventDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today \(date.formatted(date: .omitted, time: .shortened))"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
    }
}
