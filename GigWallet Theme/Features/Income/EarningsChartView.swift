import SwiftUI
import SwiftData
import Charts

/// Premium earnings visualization with weekly bars, monthly trend line, and platform breakdown
struct EarningsChartView: View {
    @Query(sort: \IncomeEntry.entryDate, order: .reverse) private var incomeEntries: [IncomeEntry]
    @Query(sort: \ExpenseEntry.expenseDate, order: .reverse) private var expenseEntries: [ExpenseEntry]

    @State private var selectedTimeRange: TimeRange = .month
    @State private var selectedChartType: ChartType = .earnings
    @State private var selectedDataPoint: DailyEarning?

    enum TimeRange: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
        case year = "YTD"
    }

    enum ChartType: String, CaseIterable {
        case earnings = "Earnings"
        case profit = "Net Profit"
        case platforms = "Platforms"
    }

    // MARK: - Data Computation

    private var filteredEntries: [IncomeEntry] {
        let cutoff = cutoffDate(for: selectedTimeRange)
        return incomeEntries.filter { $0.entryDate >= cutoff }
    }

    private var filteredExpenses: [ExpenseEntry] {
        let cutoff = cutoffDate(for: selectedTimeRange)
        return expenseEntries.filter { $0.expenseDate >= cutoff }
    }

    private var dailyEarnings: [DailyEarning] {
        let calendar = Calendar.current
        let cutoff = cutoffDate(for: selectedTimeRange)
        let days = calendar.dateComponents([.day], from: cutoff, to: .now).day ?? 1

        var result: [DailyEarning] = []
        for dayOffset in 0...days {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: cutoff) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }

            let dayIncome = incomeEntries
                .filter { $0.entryDate >= startOfDay && $0.entryDate < endOfDay }
                .reduce(0) { $0 + $1.netAmount }

            let dayExpenses = expenseEntries
                .filter { $0.expenseDate >= startOfDay && $0.expenseDate < endOfDay }
                .reduce(0) { $0 + $1.amount }

            result.append(DailyEarning(date: startOfDay, earnings: dayIncome, expenses: dayExpenses))
        }
        return result
    }

    private var weeklyEarnings: [WeeklyEarning] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: dailyEarnings) { earning in
            calendar.dateInterval(of: .weekOfYear, for: earning.date)?.start ?? earning.date
        }
        return grouped.map { (weekStart, days) in
            WeeklyEarning(
                weekStart: weekStart,
                earnings: days.reduce(0) { $0 + $1.earnings },
                expenses: days.reduce(0) { $0 + $1.expenses }
            )
        }.sorted { $0.weekStart < $1.weekStart }
    }

    private var platformBreakdown: [PlatformEarning] {
        let grouped = Dictionary(grouping: filteredEntries) { $0.platform }
        return grouped.map { platform, entries in
            PlatformEarning(
                platform: platform,
                total: entries.reduce(0) { $0 + $1.netAmount },
                count: entries.count
            )
        }.sorted { $0.total > $1.total }
    }

    private var totalEarnings: Double {
        filteredEntries.reduce(0) { $0 + $1.netAmount }
    }

    private var totalExpenses: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }

    private var avgDailyEarnings: Double {
        let count = max(dailyEarnings.count, 1)
        return totalEarnings / Double(count)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Summary header
                summaryHeader

                // Time range picker
                timeRangePicker

                // Chart type picker
                chartTypePicker

                // Chart
                chartContent

                // Stats grid
                statsGrid
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BrandColors.groupedBackground)
        .gwNavigationTitle("Earnings ", accent: "Insights", icon: "chart.line.uptrend.xyaxis")
    }

    // MARK: - Components

    private var summaryHeader: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(selectedTimeRange == .year ? "Year to Date" : "Last \(selectedTimeRange.rawValue)")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)

                    Text(CurrencyFormatter.format(totalEarnings))
                        .font(Typography.moneyLarge)
                        .foregroundStyle(BrandColors.textPrimary)
                }
                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text("Net Profit")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)

                    let netProfit = totalEarnings - totalExpenses
                    Text(CurrencyFormatter.format(netProfit))
                        .font(Typography.moneyMedium)
                        .foregroundStyle(netProfit >= 0 ? BrandColors.success : BrandColors.destructive)
                }
            }
        }
        .gwCard()
    }

    private var timeRangePicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(AnimationConstants.smooth) {
                        selectedTimeRange = range
                        selectedDataPoint = nil
                    }
                } label: {
                    Text(range.rawValue)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(selectedTimeRange == range ? .white : BrandColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            selectedTimeRange == range
                                ? BrandColors.primary
                                : BrandColors.primary.opacity(0.06)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                }
            }
        }
    }

    private var chartTypePicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(ChartType.allCases, id: \.self) { type in
                Button {
                    withAnimation(AnimationConstants.smooth) {
                        selectedChartType = type
                    }
                } label: {
                    Text(type.rawValue)
                        .font(Typography.caption)
                        .foregroundStyle(selectedChartType == type ? BrandColors.primary : BrandColors.textTertiary)
                        .padding(.vertical, Spacing.xs)
                        .padding(.horizontal, Spacing.md)
                        .background(
                            selectedChartType == type
                                ? BrandColors.primary.opacity(0.12)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        switch selectedChartType {
        case .earnings:
            earningsChart
        case .profit:
            profitChart
        case .platforms:
            platformChart
        }
    }

    private var earningsChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let selected = selectedDataPoint {
                HStack {
                    VStack(alignment: .leading) {
                        Text(selected.date.shortDate)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text(CurrencyFormatter.format(selected.earnings))
                            .font(Typography.moneySmall)
                            .foregroundStyle(BrandColors.primary)
                    }
                    Spacer()
                }
                .padding(.bottom, Spacing.xs)
            }

            Chart {
                if selectedTimeRange == .week || selectedTimeRange == .month {
                    ForEach(dailyEarnings) { day in
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Earnings", day.earnings)
                        )
                        .foregroundStyle(BrandColors.primary.gradient)
                        .cornerRadius(3)
                    }
                } else {
                    ForEach(weeklyEarnings) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Earnings", week.earnings)
                        )
                        .foregroundStyle(BrandColors.primary.gradient)
                        .cornerRadius(3)
                    }
                }

                // Average line
                if avgDailyEarnings > 0 {
                    let avgValue = selectedTimeRange == .week || selectedTimeRange == .month
                        ? avgDailyEarnings
                        : avgDailyEarnings * 7

                    RuleMark(y: .value("Average", avgValue))
                        .foregroundStyle(BrandColors.textTertiary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Avg \(CurrencyFormatter.formatCompact(avgValue))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(BrandColors.textTertiary.opacity(0.3))
                    AxisValueLabel()
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(BrandColors.textTertiary.opacity(0.3))
                    AxisValueLabel {
                        if let doubleVal = value.as(Double.self) {
                            Text(CurrencyFormatter.formatCompact(doubleVal))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .gwCard()
    }

    private var profitChart: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Chart {
                if selectedTimeRange == .week || selectedTimeRange == .month {
                    ForEach(dailyEarnings) { day in
                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Income", day.earnings)
                        )
                        .foregroundStyle(BrandColors.success.gradient)
                        .cornerRadius(3)
                        .position(by: .value("Type", "Income"))

                        BarMark(
                            x: .value("Date", day.date, unit: .day),
                            y: .value("Expenses", day.expenses)
                        )
                        .foregroundStyle(BrandColors.destructive.gradient)
                        .cornerRadius(3)
                        .position(by: .value("Type", "Expenses"))
                    }
                } else {
                    ForEach(weeklyEarnings) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Income", week.earnings)
                        )
                        .foregroundStyle(BrandColors.success.gradient)
                        .cornerRadius(3)
                        .position(by: .value("Type", "Income"))

                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Expenses", week.expenses)
                        )
                        .foregroundStyle(BrandColors.destructive.gradient)
                        .cornerRadius(3)
                        .position(by: .value("Type", "Expenses"))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Income": BrandColors.success,
                "Expenses": BrandColors.destructive
            ])
            .chartLegend(position: .top, alignment: .leading, spacing: Spacing.sm)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(BrandColors.textTertiary.opacity(0.3))
                    AxisValueLabel()
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(BrandColors.textTertiary.opacity(0.3))
                    AxisValueLabel {
                        if let doubleVal = value.as(Double.self) {
                            Text(CurrencyFormatter.formatCompact(doubleVal))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 220)
        }
        .gwCard()
    }

    private var platformChart: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if platformBreakdown.isEmpty {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 40))
                        .foregroundStyle(BrandColors.textTertiary)
                    Text("No earnings data yet")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else {
                Chart(platformBreakdown) { item in
                    SectorMark(
                        angle: .value("Earnings", item.total),
                        innerRadius: .ratio(0.6),
                        angularInset: 2
                    )
                    .foregroundStyle(item.platform.brandColor)
                    .cornerRadius(4)
                }
                .frame(height: 200)

                // Legend
                VStack(spacing: Spacing.sm) {
                    ForEach(platformBreakdown) { item in
                        HStack(spacing: Spacing.md) {
                            Circle()
                                .fill(item.platform.brandColor)
                                .frame(width: 10, height: 10)

                            Text(item.platform.displayName)
                                .font(Typography.bodyMedium)
                                .foregroundStyle(BrandColors.textPrimary)

                            Spacer()

                            Text("\(String(item.count)) trips")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)

                            Text(CurrencyFormatter.format(item.total))
                                .font(Typography.moneyCaption)
                                .foregroundStyle(BrandColors.textPrimary)
                        }
                    }
                }
            }
        }
        .gwCard()
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
            StatBox(
                icon: "dollarsign.circle.fill",
                title: "Avg/Day",
                value: CurrencyFormatter.format(avgDailyEarnings),
                color: BrandColors.primary
            )

            StatBox(
                icon: "number.circle.fill",
                title: "Trips",
                value: "\(filteredEntries.count)",
                color: BrandColors.info
            )

            StatBox(
                icon: "arrow.up.circle.fill",
                title: "Best Day",
                value: CurrencyFormatter.format(dailyEarnings.map(\.earnings).max() ?? 0),
                color: BrandColors.success
            )

            StatBox(
                icon: "percent",
                title: "Expense Ratio",
                value: totalEarnings > 0
                    ? CurrencyFormatter.formatPercent(totalExpenses / totalEarnings)
                    : "0%",
                color: BrandColors.warning
            )
        }
    }

    // MARK: - Helpers

    private func cutoffDate(for range: TimeRange) -> Date {
        let calendar = Calendar.current
        switch range {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        case .month:
            return calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
        case .quarter:
            return calendar.date(byAdding: .day, value: -90, to: .now) ?? .now
        case .year:
            let components = calendar.dateComponents([.year], from: .now)
            return calendar.date(from: components) ?? .now
        }
    }
}

// MARK: - Data Models

struct DailyEarning: Identifiable {
    let id = UUID()
    let date: Date
    let earnings: Double
    let expenses: Double
}

struct WeeklyEarning: Identifiable {
    let id = UUID()
    let weekStart: Date
    let earnings: Double
    let expenses: Double
}

struct PlatformEarning: Identifiable {
    let id = UUID()
    let platform: GigPlatformType
    let total: Double
    let count: Int
}

// MARK: - Stat Box

struct StatBox: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)

            Text(value)
                .font(Typography.moneySmall)
                .foregroundStyle(BrandColors.textPrimary)

            Text(title)
                .font(Typography.caption2)
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
    }
}
