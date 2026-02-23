import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IncomeEntry.entryDate, order: .reverse) private var incomeEntries: [IncomeEntry]
    @Query(sort: \ExpenseEntry.expenseDate, order: .reverse) private var expenseEntries: [ExpenseEntry]
    @Query private var mileageTrips: [MileageTrip]
    @Query private var profiles: [UserProfile]

    @Query(sort: \TaxPayment.paymentDate, order: .reverse) private var taxPayments: [TaxPayment]
    @Query private var budgetItems: [BudgetItem]
    @Query(sort: \TaxVaultEntry.entryDate, order: .reverse) private var vaultEntries: [TaxVaultEntry]

    @State private var showingSettings = false
    @State private var showingFinancialPlanner = false
    @State private var showingAddIncome = false
    @State private var showingAddExpense = false
    @State private var showingAddMileage = false
    @State private var showingSetGoal = false
    @State private var showingCashTip = false
    @State private var showingReceiptScan = false
    @State private var showingTaxVault = false
    @State private var welcomeCardDismissed = UserDefaults.standard.bool(forKey: "welcomeCardDismissed")

    // Dashboard section picker
    @State private var selectedSection: DashboardSection = .action

    // AI Intelligence Coordinator
    @State private var aiCoordinator = GigIntelligenceCoordinator()

    // Event alerts + weather boost services
    @State private var eventAlertService = EventAlertService.shared
    @State private var weatherBoostService = WeatherBoostService.shared

    private var profile: UserProfile? { profiles.first }

    // Card reordering
    @State private var cardOrderManager = DashboardCardOrderManager.shared
    @State private var showingReorderSheet = false

    // MARK: - Computed Data

    private var monthlyIncome: Double {
        let startOfMonth = Date.now.startOfMonth
        return incomeEntries
            .filter { $0.entryDate >= startOfMonth }
            .reduce(0) { $0 + $1.netAmount }
    }

    private var monthlyExpenses: Double {
        let startOfMonth = Date.now.startOfMonth
        return expenseEntries
            .filter { $0.expenseDate >= startOfMonth }
            .reduce(0) { $0 + $1.amount }
    }

    private var todaysIncome: Double {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return incomeEntries
            .filter { $0.entryDate >= startOfDay }
            .reduce(0) { $0 + $1.netAmount }
    }

    private var todaysGrossIncome: Double {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        return incomeEntries
            .filter { $0.entryDate >= startOfDay }
            .reduce(0) { $0 + $1.grossAmount }
    }

    private var yearlyIncome: Double {
        incomeEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.netAmount }
    }

    private var yearlyDeductions: Double {
        expenseEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.deductibleAmount }
    }

    private var weeklyIncome: Double {
        let startOfWeek = Date.now.startOfWeek
        return incomeEntries
            .filter { $0.entryDate >= startOfWeek }
            .reduce(0) { $0 + $1.netAmount }
    }

    // MARK: - Earnings Pattern Analysis

    private var earningsPattern: EarningsPatternEngine.WeeklyInsight? {
        let snapshots = incomeEntries.map {
            EarningsPatternEngine.IncomeSnapshot(
                date: $0.entryDate,
                grossAmount: $0.grossAmount,
                netAmount: $0.netAmount,
                platform: $0.platform.displayName
            )
        }
        return EarningsPatternEngine.analyze(entries: snapshots)
    }

    // MARK: - Income Momentum

    private var lastWeekIncome: Double {
        let calendar = Calendar.current
        let startOfThisWeek = Date.now.startOfWeek
        guard let startOfLastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek) else { return 0 }
        return incomeEntries
            .filter { $0.entryDate >= startOfLastWeek && $0.entryDate < startOfThisWeek }
            .reduce(0) { $0 + $1.netAmount }
    }

    private var weekOverWeekChange: Double {
        guard lastWeekIncome > 0 else { return 0 }
        return (weeklyIncome - lastWeekIncome) / lastWeekIncome
    }

    private var currentEarningStreak: Int {
        earningsPattern?.currentStreak ?? 0
    }

    private var avgDailyIncome: Double {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let recent = incomeEntries.filter { $0.entryDate >= thirtyDaysAgo }
        let uniqueDays = Set(recent.map { Calendar.current.startOfDay(for: $0.entryDate) }).count
        guard uniqueDays > 0 else { return 0 }
        return recent.reduce(0) { $0 + $1.netAmount } / Double(uniqueDays)
    }

    private var lastIncomeDate: Date? {
        incomeEntries.first?.entryDate
    }

    // MARK: - Tax Countdown Data

    private var currentQuarterPayments: Double {
        let currentQ = TaxQuarter.current
        return taxPayments
            .filter { $0.taxYear == DateHelper.currentTaxYear && $0.quarter == currentQ }
            .reduce(0) { $0 + $1.amount }
    }

    private var yearlyTaxPaid: Double {
        taxPayments
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalVaultBalance: Double {
        vaultEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0.0) { total, entry in
                entry.type.isCredit ? total + entry.amount : total - entry.amount
            }
    }

    private var activePlatforms: [GigPlatformType] {
        let platforms = Set(incomeEntries.map { $0.platform })
        return platforms.isEmpty ? [.uber] : Array(platforms).sorted { $0.rawValue < $1.rawValue }
    }

    private var taxEstimate: TaxCalculationResult {
        let engine = TaxEngine()
        return engine.calculateEstimate(
            grossIncome: yearlyIncome,
            totalDeductions: yearlyDeductions,
            filingStatus: profile?.filingStatus ?? .single,
            stateCode: profile?.stateCode ?? "CA",
            w2Withholding: profile?.estimatedW2Withholding ?? 0,
            w2Income: profile?.estimatedW2Income ?? 0,
            personalDeduction: profile?.effectivePersonalDeduction,
            taxCredits: profile?.estimatedTotalCredits ?? 0
        )
    }

    // MARK: - Financial Health Score

    private var yearlyGrossIncome: Double {
        incomeEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.grossAmount }
    }

    private var yearlyExpenses: Double {
        expenseEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.amount }
    }

    private var yearlyMileage: Double {
        mileageTrips
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.miles }
    }

    private var expenseCategoryNames: Set<String> {
        Set(expenseEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .map { $0.category.rawValue })
    }

    private var monthlyIncomeValues: [Double] {
        let calendar = Calendar.current
        let now = Date.now
        return (0..<6).compactMap { monthsAgo -> Double? in
            guard let start = calendar.date(byAdding: .month, value: -monthsAgo, to: now.startOfMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            let total = incomeEntries
                .filter { $0.entryDate >= start && $0.entryDate < end }
                .reduce(0.0) { $0 + $1.netAmount }
            return total
        }.reversed()
    }

    private var weeklyIncomeValues: [Double] {
        let calendar = Calendar.current
        let now = Date.now
        return (0..<8).compactMap { weeksAgo -> Double? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now.startOfWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let total = incomeEntries
                .filter { $0.entryDate >= start && $0.entryDate < end }
                .reduce(0.0) { $0 + $1.netAmount }
            return total
        }.reversed()
    }

    private var financialHealthScore: FinancialHealthEngine.HealthScore {
        let snapshot = FinancialHealthEngine.FinancialSnapshot(
            yearlyGrossIncome: yearlyGrossIncome,
            yearlyNetIncome: yearlyIncome,
            yearlyExpenses: yearlyExpenses,
            yearlyDeductions: yearlyDeductions,
            yearlyMileage: yearlyMileage,
            estimatedTax: taxEstimate.totalEstimatedTax,
            taxPaid: yearlyTaxPaid,
            quarterlyPaymentDue: taxEstimate.quarterlyPaymentDue,
            safeHarborCompliant: taxEstimate.totalEstimatedTax < 1000 || yearlyTaxPaid >= taxEstimate.totalEstimatedTax * 0.9,
            deductionCategoriesUsed: expenseCategoryNames.count,
            totalDeductionCategories: 13,
            monthlyIncomeValues: monthlyIncomeValues,
            weeklyIncomeValues: weeklyIncomeValues,
            effectiveTaxRate: taxEstimate.effectiveTaxRate,
            hasHomeoOfficeDeduction: expenseCategoryNames.contains(ExpenseCategory.homeOffice.rawValue),
            hasMileageDeductions: yearlyMileage > 0,
            hasHealthInsurance: expenseCategoryNames.contains(ExpenseCategory.healthInsurance.rawValue),
            hasRetirementContributions: expenseCategoryNames.contains(ExpenseCategory.retirement.rawValue),
            priorYearTax: profile?.priorYearTax ?? 0,
            monthsActive: max(Calendar.current.component(.month, from: .now), 1)
        )
        return FinancialHealthEngine.calculate(snapshot: snapshot)
    }

    // MARK: - Gig Decision Engine

    private var workRecommendation: GigDecisionEngine.WorkRecommendation {
        let entries = incomeEntries.map {
            GigDecisionEngine.HistoricalEntry(
                date: $0.entryDate,
                grossAmount: $0.grossAmount,
                netAmount: $0.netAmount,
                fees: $0.platformFees,
                platform: $0.platform.displayName,
                estimatedHours: $0.platform.estimatedHoursPerEntry
            )
        }
        // Gas price: live from EIA API with safe fallback for offline/unavailable
        let market = GigDecisionEngine.MarketContext(
            gasPrice: MarketIntelligenceService.shared.gasPrices?.nationalAverage ?? 3.50,
            avgMilesPerGigHour: 15,
            vehicleMPG: 25
        )
        return GigDecisionEngine.recommend(
            entries: entries,
            weeklyGoal: profile?.weeklyEarningsGoal ?? 0,
            currentWeeklyIncome: weeklyIncome,
            market: market,
            effectiveTaxRate: taxEstimate.effectiveTaxRate
        )
    }

    // MARK: - Earnings Heatmap

    private var heatmapData: [[Double]] {
        let calendar = Calendar.current
        var grid = Array(repeating: Array(repeating: 0.0, count: 4), count: 7)
        var counts = Array(repeating: Array(repeating: 0, count: 4), count: 7)

        for entry in incomeEntries {
            let dow = calendar.component(.weekday, from: entry.entryDate) - 1
            let hour = calendar.component(.hour, from: entry.entryDate)
            let block: Int
            switch hour {
            case 5..<12: block = 0
            case 12..<17: block = 1
            case 17..<21: block = 2
            default: block = 3
            }
            guard dow >= 0, dow < 7, block >= 0, block < 4 else { continue }
            grid[dow][block] += entry.netAmount
            counts[dow][block] += 1
        }

        for row in 0..<7 {
            for col in 0..<4 {
                if counts[row][col] > 0 {
                    grid[row][col] /= Double(counts[row][col])
                }
            }
        }
        return grid
    }

    private var heatmapBestSlot: (day: Int, block: Int)? {
        var bestDay = 0, bestBlock = 0, bestVal = 0.0
        for row in 0..<heatmapData.count {
            for col in 0..<heatmapData[row].count {
                if heatmapData[row][col] > bestVal {
                    bestVal = heatmapData[row][col]
                    bestDay = row
                    bestBlock = col
                }
            }
        }
        return bestVal > 0 ? (bestDay, bestBlock) : nil
    }

    // MARK: - AI Insights

    private var aiInsights: [InsightsEngine.Insight] {
        let incomeSnapshots = incomeEntries.map {
            InsightsEngine.IncomeEntrySnapshot(
                date: $0.entryDate,
                grossAmount: $0.grossAmount,
                fees: $0.platformFees,
                netAmount: $0.netAmount,
                platform: $0.platform.displayName
            )
        }
        let expenseSnapshots = expenseEntries.map {
            InsightsEngine.ExpenseEntrySnapshot(
                date: $0.expenseDate,
                amount: $0.amount,
                category: $0.category.rawValue,
                isDeductible: $0.isDeductible
            )
        }
        let mileageSnapshots = mileageTrips.map {
            InsightsEngine.MileageTripSnapshot(date: $0.tripDate, miles: $0.miles)
        }
        return InsightsEngine.generateInsights(
            incomeEntries: incomeSnapshots,
            expenseEntries: expenseSnapshots,
            mileageTrips: mileageSnapshots,
            weeklyGoal: profile?.weeklyEarningsGoal ?? 0,
            filingStatus: profile?.filingStatus.rawValue ?? "Single",
            stateCode: profile?.stateCode ?? "CA"
        )
    }

    // MARK: - Financial Planner Data

    private var plannerMonthBudgetItems: [BudgetItem] {
        budgetItems.filter { $0.monthYear == BudgetItem.currentMonthYear }
    }

    private var plannerMonthlyBudgetExpenses: Double {
        plannerMonthBudgetItems
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.amount }
    }

    private var plannerOtherIncome: Double {
        plannerMonthBudgetItems
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.amount }
    }

    private var plannerSurplus: Double {
        (monthlyIncome + plannerOtherIncome) - (monthlyExpenses + plannerMonthlyBudgetExpenses)
    }

    private var hasBudgetItems: Bool {
        !plannerMonthBudgetItems.isEmpty
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {

                // ═══════════════════════════════════════════
                // ALWAYS VISIBLE: Identity + Status + Actions
                // ═══════════════════════════════════════════

                // Welcome card for brand-new users
                if !welcomeCardDismissed &&
                    cardOrderManager.experienceLevel == .newcomer &&
                    (incomeEntries.count + expenseEntries.count) < 3 {
                    DashboardWelcomeCard(
                        hasIncome: !incomeEntries.isEmpty,
                        hasExpense: !expenseEntries.isEmpty,
                        hasGoal: (profile?.weeklyEarningsGoal ?? 0) > 0,
                        onAddIncome: { showingAddIncome = true },
                        onAddExpense: { showingAddExpense = true },
                        onSetGoal: { showingSetGoal = true },
                        onDismiss: {
                            welcomeCardDismissed = true
                            UserDefaults.standard.set(true, forKey: "welcomeCardDismissed")
                        }
                    )
                }

                SmartGreetingHeader(
                    userName: profile?.displayName ?? "",
                    todaysIncome: todaysIncome,
                    weeklyIncome: weeklyIncome,
                    weeklyGoal: profile?.weeklyEarningsGoal ?? 0,
                    lastIncomeDate: lastIncomeDate,
                    topInsight: aiInsights.first,
                    profileImageURL: profile?.profileImageURL ?? "",
                    initials: profile?.initials ?? "GW"
                )
                .staggeredEntry(index: 0)

                EarningsSummaryCard(
                    monthlyEarnings: monthlyIncome,
                    monthlyExpenses: monthlyExpenses,
                    todaysEarnings: todaysIncome,
                    effectiveTaxRate: taxEstimate.effectiveTaxRate
                )
                .staggeredEntry(index: 1)

                QuickActionsRow(
                    onAddIncome: { showingAddIncome = true },
                    onAddExpense: { showingAddExpense = true },
                    onAddMileage: { showingAddMileage = true },
                    onAddCashTip: { showingCashTip = true },
                    onScanReceipt: { showingReceiptScan = true }
                )
                .staggeredEntry(index: 2)

                // ═══════════════════════════════════════════
                // SECTION PICKER — swipe between 3 focused views
                // ═══════════════════════════════════════════

                sectionPicker
                    .staggeredEntry(index: 3)

                // Section content — renders cards in user-customizable order
                ForEach(Array(cardOrderManager.orderedCards(for: selectedSection).enumerated()), id: \.element) { index, cardID in
                    cardView(for: cardID)
                        .staggeredEntry(index: index + 4)
                }
                .animation(.easeInOut(duration: 0.2), value: selectedSection)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BrandColors.groupedBackground)
        .task(id: incomeEntries.count + expenseEntries.count) {
            // Update progressive dashboard experience level
            cardOrderManager.updateExperienceLevel(
                profileCreatedAt: profile?.createdAt ?? .now,
                entryCount: incomeEntries.count + expenseEntries.count,
                isPremium: profile?.isPremium == true
            )

            // Push fresh data to widgets via App Group UserDefaults
            WidgetUpdateService.pushUpdate(
                incomeEntries: incomeEntries,
                expenseEntries: expenseEntries,
                taxPayments: taxPayments,
                profile: profile,
                taxEstimate: taxEstimate
            )

            // Auto-analyze deductions — proactively finds missing write-offs
            SmartDeductionService.shared.analyzeIfNeeded(context: modelContext, profile: profile)

            let stateCode = profile?.stateCode ?? "CA"

            await aiCoordinator.analyze(
                incomeEntries: incomeEntries,
                expenseEntries: expenseEntries,
                mileageTrips: mileageTrips,
                taxPayments: taxPayments,
                profile: profile,
                weeklyGoal: profile?.weeklyEarningsGoal ?? 0
            )
            // Fetch weather first so we can share GPS coordinates with events
            await weatherBoostService.fetchWeather(stateCode: stateCode)
            let lat = weatherBoostService.currentLocation?.coordinate.latitude
            let lon = weatherBoostService.currentLocation?.coordinate.longitude
            await eventAlertService.fetchEvents(stateCode: stateCode, latitude: lat, longitude: lon)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(BrandColors.primary)

                    (Text("Gig")
                        .foregroundStyle(BrandColors.textPrimary)
                    + Text("Wallet")
                        .foregroundStyle(BrandColors.primary))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.shared.tap()
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(BrandColors.textSecondary)
                        .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
            .environment(appState)
        }
        .sheet(isPresented: $showingAddIncome) {
            NavigationStack {
                AddIncomeView()
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            NavigationStack {
                AddExpenseView()
            }
        }
        .sheet(isPresented: $showingAddMileage) {
            NavigationStack {
                MileageEntryView()
            }
        }
        .sheet(isPresented: $showingSetGoal) {
            NavigationStack {
                SetGoalView()
            }
        }
        .sheet(isPresented: $showingCashTip) {
            NavigationStack {
                QuickCashTipView(platforms: activePlatforms)
            }
        }
        .sheet(isPresented: $showingFinancialPlanner) {
            NavigationStack {
                FinancialPlannerView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingFinancialPlanner = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingReorderSheet) {
            CardReorderSheet(section: selectedSection)
        }
        .sheet(isPresented: $showingReceiptScan) {
            NavigationStack {
                ReceiptScanView()
            }
        }
        .sheet(isPresented: $showingTaxVault) {
            NavigationStack {
                TaxVaultView()
            }
        }
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        HStack(spacing: Spacing.sm) {
            HStack(spacing: 0) {
                ForEach(DashboardSection.allCases) { section in
                    Button {
                        HapticManager.shared.select()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: section.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(section.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedSection == section
                                ? BrandColors.primary
                                : Color.clear
                        )
                        .foregroundStyle(
                            selectedSection == section
                                ? .white
                                : BrandColors.textSecondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .shadow(color: BrandColors.cardShadow, radius: 2, y: 1)

            // Reorder button
            Button {
                HapticManager.shared.tap()
                showingReorderSheet = true
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrandColors.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(BrandColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    .shadow(color: BrandColors.cardShadow, radius: 2, y: 1)
            }
            .accessibilityLabel("Reorder cards")
        }
    }

    // MARK: - Dynamic Card Dispatch

    /// Renders any dashboard card by ID. Used by the ForEach in the body
    /// so cards appear in the user's custom order.
    @ViewBuilder
    private func cardView(for cardID: DashboardCardID) -> some View {
        switch cardID {

        // ── Action Section ──

        case .workAdvisor:
            WorkAdvisorCard(
                recommendation: workRecommendation,
                weatherNote: weatherBoostService.topForecast?.message,
                weatherIcon: weatherBoostService.currentCondition.sfSymbol,
                topEventName: eventAlertService.topUpcomingEvent.map { "\($0.name) — \($0.demandBoost.label)" }
            )
            .premiumLocked(isPremium: profile?.isPremium == true, featureName: "Work Advisor") {
                appState.showingPaywall = true
            }

        case .taxCountdown:
            TaxCountdownCard(
                daysUntilDue: DateHelper.daysUntilDue(quarter: .current, year: DateHelper.currentTaxYear),
                quarterName: TaxQuarter.current.shortName + " " + String(DateHelper.currentTaxYear),
                estimatedPayment: taxEstimate.quarterlyPaymentDue,
                amountPaid: currentQuarterPayments,
                dueDate: TaxQuarter.current.dueDescription
            )

        case .earningsGoal:
            EarningsGoalCard(
                currentWeeklyEarnings: weeklyIncome,
                weeklyGoal: profile?.weeklyEarningsGoal ?? 0,
                onSetGoal: { showingSetGoal = true }
            )

        case .localEvents:
            if !eventAlertService.upcomingEvents.isEmpty {
                LocalEventsCard(
                    events: eventAlertService.upcomingEvents,
                    weatherNote: weatherBoostService.topForecast?.message
                )
            }

        case .financialPlanner:
            FinancialPlannerCard(
                isPremium: profile?.isPremium == true,
                hasBudgetItems: hasBudgetItems,
                monthlyIncome: monthlyIncome + plannerOtherIncome,
                monthlyExpenses: monthlyExpenses + plannerMonthlyBudgetExpenses,
                surplus: plannerSurplus,
                onTap: {
                    if profile?.isPremium == true {
                        showingFinancialPlanner = true
                    } else {
                        appState.showingPaywall = true
                    }
                }
            )

        // ── Insights Section ──

        case .financialHealth:
            FinancialHealthCard(
                healthScore: financialHealthScore
            )
            .premiumLocked(isPremium: profile?.isPremium == true, featureName: "Financial Health Score") {
                appState.showingPaywall = true
            }

        case .aiIntelligence:
            AIIntelligenceCard(
                insights: aiInsights,
                report: aiCoordinator.currentReport
            )
            .premiumLocked(isPremium: profile?.isPremium == true, featureName: "AI Intelligence") {
                appState.showingPaywall = true
            }

        case .incomeMomentum:
            IncomeMomentumCard(
                thisWeekIncome: weeklyIncome,
                lastWeekIncome: lastWeekIncome,
                weekOverWeekChange: weekOverWeekChange,
                currentStreak: currentEarningStreak,
                avgDailyIncome: avgDailyIncome,
                todaysIncome: todaysIncome
            )

        // ── Optimize Section ──

        case .earningsHeatmap:
            EarningsHeatmapCard(
                heatmapData: heatmapData,
                bestSlot: heatmapBestSlot
            )
            .premiumLocked(isPremium: profile?.isPremium == true, featureName: "Earnings Heatmap") {
                appState.showingPaywall = true
            }

        case .taxBite:
            TaxBiteCard(
                todaysGross: todaysGrossIncome,
                effectiveTaxRate: taxEstimate.effectiveTaxRate,
                yearlyTaxOwed: taxEstimate.totalEstimatedTax,
                yearlyTaxPaid: yearlyTaxPaid
            )

        case .taxVault:
            TaxReserveCard(
                yearlyNetIncome: yearlyIncome,
                yearlyTaxEstimate: taxEstimate.totalEstimatedTax,
                yearlyTaxPaid: yearlyTaxPaid,
                effectiveTaxRate: taxEstimate.effectiveTaxRate,
                vaultBalance: totalVaultBalance,
                onTap: { showingTaxVault = true }
            )
        }
    }

}
