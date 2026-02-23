import SwiftUI
import SwiftData

struct IncomeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \IncomeEntry.entryDate, order: .reverse) private var entries: [IncomeEntry]
    @Query private var profiles: [UserProfile]
    @State private var showingAddIncome = false
    @State private var showingCharts = false
    @State private var selectedPlatformFilter: GigPlatformType?
    @State private var entryToEdit: IncomeEntry?

    private var profile: UserProfile? { profiles.first }

    private var filteredEntries: [IncomeEntry] {
        if let filter = selectedPlatformFilter {
            return entries.filter { $0.platform == filter }
        }
        return entries
    }

    private var groupedEntries: [(String, [IncomeEntry])] {
        // Group by date string, but sort by actual date (not alphabetically)
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            entry.entryDate.shortDate
        }
        return grouped.sorted { group1, group2 in
            let date1 = group1.value.first?.entryDate ?? .distantPast
            let date2 = group2.value.first?.entryDate ?? .distantPast
            return date1 > date2
        }
    }

    private var activePlatforms: [GigPlatformType] {
        Array(Set(entries.map(\.platform))).sorted { $0.rawValue < $1.rawValue }
    }

    private var totalMonthlyIncome: Double {
        let startOfMonth = Date.now.startOfMonth
        return entries
            .filter { $0.entryDate >= startOfMonth }
            .reduce(0) { $0 + $1.netAmount }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("This Month")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text(CurrencyFormatter.format(totalMonthlyIncome))
                            .font(Typography.moneyMedium)
                            .foregroundStyle(BrandColors.primary)
                    }
                    Spacer()
                    Text("\(String(entries.count)) entries")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .listRowBackground(BrandColors.cardBackground)
            }

            if activePlatforms.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            PlatformFilterChip(
                                title: "All",
                                isSelected: selectedPlatformFilter == nil,
                                color: BrandColors.primary
                            ) {
                                selectedPlatformFilter = nil
                            }

                            ForEach(activePlatforms) { platform in
                                PlatformFilterChip(
                                    title: platform.displayName,
                                    isSelected: selectedPlatformFilter == platform,
                                    color: platform.brandColor
                                ) {
                                    selectedPlatformFilter = platform
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            if filteredEntries.isEmpty {
                Section {
                    GWEmptyState(
                        icon: "dollarsign.circle",
                        title: "No Income Yet",
                        message: "Add your first gig earnings to start tracking.",
                        buttonTitle: "Add Income"
                    ) {
                        showingAddIncome = true
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedEntries, id: \.0) { date, dayEntries in
                    Section(date) {
                        ForEach(dayEntries) { entry in
                            IncomeRowView(entry: entry)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        entryToEdit = entry
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(BrandColors.info)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelContext.delete(entry)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .onTapGesture {
                                    entryToEdit = entry
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .gwNavigationTitle("My ", accent: "Earnings", icon: "dollarsign.circle.fill")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingCharts = true
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(BrandColors.primary)
                }
                .accessibilityLabel("Earnings Charts")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddIncome = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(BrandColors.primary)
                }
            }
        }
        .sheet(isPresented: $showingAddIncome) {
            NavigationStack {
                AddIncomeView()
            }
        }
        .sheet(item: $entryToEdit) { entry in
            NavigationStack {
                EditIncomeView(entry: entry)
            }
        }
        .sheet(isPresented: $showingCharts) {
            NavigationStack {
                EarningsChartView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showingCharts = false }
                        }
                    }
            }
        }
    }
}

struct PlatformFilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? color : color.opacity(0.1))
                .foregroundStyle(isSelected ? .white : color)
                .clipShape(Capsule())
        }
    }
}
