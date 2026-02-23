import SwiftUI
import SwiftData

struct TaxCenterView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IncomeEntry.entryDate) private var incomeEntries: [IncomeEntry]
    @Query(sort: \ExpenseEntry.expenseDate) private var expenseEntries: [ExpenseEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \TaxPayment.paymentDate, order: .reverse) private var taxPayments: [TaxPayment]
    @Query(sort: \TaxVaultEntry.entryDate, order: .reverse) private var vaultEntries: [TaxVaultEntry]

    @State private var showingExport = false
    @State private var showingLogPayment = false
    @State private var showingDeductionFinder = false
    @State private var showingTaxVault = false
    @State private var showingMultiState = false

    // Collapsible section state — quarterly estimates expanded by default (most critical info)
    @State private var isQuarterlyExpanded = true
    @State private var isBreakdownExpanded = false
    @State private var isPaymentsExpanded = false

    private var profile: UserProfile? { profiles.first }

    private var taxEngine: TaxEngine { TaxEngine() }

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

    private var taxResult: TaxCalculationResult {
        taxEngine.calculateEstimate(
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

    // MARK: - Derived Rate Strings (shown in Tax Breakdown detail column)

    /// The marginal federal bracket rate the user lands in, formatted as a percent.
    private var federalRateDetail: String {
        let deductionAmount = profile?.effectivePersonalDeduction ?? TaxEngine.StandardDeductions.amount(for: profile?.filingStatus ?? .single)
        let taxableIncome = taxResult.netSelfEmploymentIncome > 0
            ? max(
                (taxResult.netSelfEmploymentIncome
                    - taxResult.selfEmploymentTax * TaxEngine.TaxConstants.seTaxDeductionRate
                    - deductionAmount),
                0)
            : 0
        let brackets: [(threshold: Double, rate: Double)]
        switch profile?.filingStatus ?? .single {
        case .single:          brackets = TaxEngine.federalBrackets2026Single
        case .marriedJoint:    brackets = TaxEngine.federalBrackets2026MarriedJoint
        case .marriedSeparate: brackets = TaxEngine.federalBrackets2026MarriedSeparate
        case .headOfHousehold: brackets = TaxEngine.federalBrackets2026HeadOfHousehold
        }
        let marginalRate = brackets.last(where: { taxableIncome >= $0.threshold })?.rate ?? 0.10
        return "\(Int(marginalRate * 100))% marginal bracket"
    }

    /// The state's effective flat rate, formatted as a percent with state code.
    /// Uses TaxEngine's canonical rate table to avoid duplication.
    private var stateRateDetail: String {
        let code = profile?.stateCode ?? "CA"
        let rate = taxEngine.stateEffectiveTaxRate(for: code)
        if rate == 0 { return "\(code) \u{00B7} No state income tax" }
        return "\(code) \u{00B7} \(String(format: "%.2f", rate * 100))% effective rate"
    }

    // MARK: - Tax Payment Tracking

    private var yearlyTaxPaid: Double {
        taxPayments
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.amount }
    }

    private var federalTaxPaid: Double {
        taxPayments
            .filter { $0.taxYear == DateHelper.currentTaxYear && $0.paymentType == .federal }
            .reduce(0) { $0 + $1.amount }
    }

    private var stateTaxPaid: Double {
        taxPayments
            .filter { $0.taxYear == DateHelper.currentTaxYear && $0.paymentType == .state }
            .reduce(0) { $0 + $1.amount }
    }

    private var taxBalance: Double {
        // Subtract W-2 withholding from total tax — employer already pays this portion
        let w2Withholding = profile?.estimatedW2Withholding ?? 0
        return max(taxResult.totalEstimatedTax - w2Withholding - yearlyTaxPaid, 0)
    }

    // MARK: - Safe Harbor

    private var safeHarborResult: SafeHarborCalculator.SafeHarborResult {
        SafeHarborCalculator.calculate(
            currentYearEstimatedTax: taxResult.totalEstimatedTax,
            priorYearTotalTax: profile?.priorYearTax ?? 0,
            totalPaymentsMadeSoFar: yearlyTaxPaid,
            currentQuarter: .current
        )
    }

    private func paymentsForQuarter(_ quarter: TaxQuarter) -> Double {
        taxPayments
            .filter { $0.taxYear == DateHelper.currentTaxYear && $0.quarter == quarter }
            .reduce(0) { $0 + $1.amount }
    }

    private func incomeForQuarter(_ quarter: TaxQuarter) -> Double {
        incomeEntries
            .filter { $0.quarter == quarter && $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.netAmount }
    }

    private func deductionsForQuarter(_ quarter: TaxQuarter) -> Double {
        expenseEntries
            .filter { $0.quarter == quarter && $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.deductibleAmount }
    }

    private func quarterlyTaxEstimate(for quarter: TaxQuarter) -> Double {
        let income = incomeForQuarter(quarter)
        guard income > 0 else { return 0 }
        // Calculate proportional tax for this quarter based on its share of annual income
        let quarterShare = yearlyIncome > 0 ? income / yearlyIncome : 0.25
        return taxResult.totalEstimatedTax * quarterShare
    }

    // MARK: - Tax Vault Computed

    private var vaultBalance: Double {
        vaultEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0.0) { total, entry in
                entry.type.isCredit ? total + entry.amount : total - entry.amount
            }
    }

    private var vaultTotalSetAside: Double {
        vaultEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear && $0.type == .setAside }
            .reduce(0) { $0 + $1.amount }
    }

    private var vaultQuarterlyTarget: Double {
        taxResult.totalEstimatedTax / 4
    }

    private var vaultProgress: Double {
        guard vaultQuarterlyTarget > 0 else {
            // No tax target yet — if they've set aside money, show 100% (target exceeded)
            return vaultBalance > 0 ? 1.0 : 0
        }
        return min(max(vaultBalance, 0) / vaultQuarterlyTarget, 1.0)
    }

    private var taxPrepCompleteness: Double {
        var score = 0.0
        let currentYear = DateHelper.currentTaxYear
        let yearEntries = incomeEntries.filter { $0.taxYear == currentYear }
        let yearExpenses = expenseEntries.filter { $0.taxYear == currentYear }

        if !yearEntries.isEmpty { score += 0.25 }
        if !yearExpenses.isEmpty { score += 0.25 }
        // Only count filing status if user has explicitly changed it from default
        if profile?.hasCompletedOnboarding == true { score += 0.15 }
        if profile?.stateCode != nil && profile?.stateCode != "CA" { score += 0.10 }
        if yearlyDeductions > 0 { score += 0.25 }
        return min(score, 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // MARK: - Payment Status Hero (always visible — most important)
                paymentStatusHero

                // MARK: - Annual Summary (always visible — key numbers at a glance)
                annualSummaryCard

                // MARK: - Safe Harbor (always visible if applicable)
                if taxResult.totalEstimatedTax > 200 {
                    safeHarborCard
                }

                // MARK: - Tax Vault Card (always visible — interactive)
                taxVaultCard

                // MARK: - Collapsible: Quarterly Estimates
                collapsibleSection(
                    title: "Quarterly Estimates",
                    icon: "calendar.badge.clock",
                    isExpanded: $isQuarterlyExpanded,
                    badge: TaxQuarter.current.shortName
                ) {
                    quarterlyEstimatesContent
                }

                // MARK: - Collapsible: Tax Breakdown
                collapsibleSection(
                    title: "Tax Breakdown",
                    icon: "chart.pie.fill",
                    isExpanded: $isBreakdownExpanded,
                    badge: CurrencyFormatter.formatPercent(taxResult.effectiveTaxRate)
                ) {
                    taxBreakdownContent
                }

                // MARK: - Collapsible: Recent Payments
                if !taxPayments.isEmpty {
                    collapsibleSection(
                        title: "Recent Payments",
                        icon: "checkmark.circle.fill",
                        isExpanded: $isPaymentsExpanded,
                        badge: "\(String(taxPayments.count))"
                    ) {
                        recentPaymentsContent
                    }
                }

                // MARK: - Action Buttons
                actionButtons

                // MARK: - 1099-K Alert
                if yearlyIncome > 2_500 {
                    Form1099KAlertCard(
                        grossIncome: yearlyIncome,
                        threshold: TaxEngine.TaxConstants.form1099KThreshold,
                        entryCount: incomeEntries.count
                    )
                }

                // Disclaimer
                Text("Estimates based on self-employment income only. Actual tax may differ. Consult a tax professional.")
                    .font(.system(size: 10))
                    .foregroundStyle(BrandColors.textTertiary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BrandColors.groupedBackground)
        .gwNavigationTitle("Tax ", accent: "HQ", icon: "building.columns.fill")
        .sheet(isPresented: $showingExport) {
            NavigationStack {
                TaxExportView()
            }
        }
        .sheet(isPresented: $showingLogPayment) {
            NavigationStack {
                LogTaxPaymentView(suggestedAmount: safeHarborResult.minimumQuarterlyPayment)
            }
        }
        .sheet(isPresented: $showingDeductionFinder) {
            NavigationStack {
                DeductionFinderView()
            }
        }
        .sheet(isPresented: $showingTaxVault) {
            NavigationStack {
                TaxVaultView()
            }
        }
        .sheet(isPresented: $showingMultiState) {
            NavigationStack {
                MultiStateTaxView()
            }
        }
    }

    // MARK: - Payment Status Hero

    private var paymentStatusHero: some View {
        GWCard {
            VStack(spacing: Spacing.md) {
                HStack {
                    Text("Payment Status")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    Text(String(DateHelper.currentTaxYear))
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                HStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.xxs) {
                        Text(CurrencyFormatter.format(yearlyTaxPaid))
                            .font(Typography.moneyMedium)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(BrandColors.success)
                        Text("Paid")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    // Visual separator
                    Rectangle()
                        .fill(BrandColors.textTertiary.opacity(0.2))
                        .frame(width: 1, height: 36)

                    VStack(spacing: Spacing.xxs) {
                        Text(CurrencyFormatter.format(taxResult.totalEstimatedTax))
                            .font(Typography.moneyMedium)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(BrandColors.textPrimary)
                        Text("Est. Owed")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(BrandColors.textTertiary.opacity(0.2))
                        .frame(width: 1, height: 36)

                    VStack(spacing: Spacing.xxs) {
                        Text(CurrencyFormatter.format(taxBalance))
                            .font(Typography.moneyMedium)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(taxBalance > 500 ? BrandColors.destructive : BrandColors.success)
                        Text("Est. Balance")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Progress bar — paid vs owed
                if taxResult.totalEstimatedTax > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(BrandColors.destructive.opacity(0.12))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.success, BrandColors.success.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * min(yearlyTaxPaid / taxResult.totalEstimatedTax, 1.0))
                        }
                    }
                    .frame(height: 8)
                }

                // Log payment button
                GWButton("Log Tax Payment", icon: "plus.circle.fill", style: .primary) {
                    showingLogPayment = true
                }
            }
        }
    }

    // MARK: - Annual Summary

    private var annualSummaryCard: some View {
        GWCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("\(String(DateHelper.currentTaxYear)) Tax Summary")
                        .font(Typography.headline)
                    Spacer()
                    // Tax Prep Progress as a compact indicator
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(taxPrepCompleteness >= 0.75 ? BrandColors.success : BrandColors.warning)
                            .frame(width: 8, height: 8)
                        Text("\(Int(taxPrepCompleteness * 100))% prepared")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                HStack(spacing: Spacing.xxl) {
                    SummaryItem(label: "Gross Income", value: yearlyIncome, color: BrandColors.primary)
                    SummaryItem(label: "Deductions", value: yearlyDeductions, color: BrandColors.success)
                }

                Divider()

                HStack(spacing: Spacing.xxl) {
                    SummaryItem(label: "Est. Total Tax", value: taxResult.totalEstimatedTax, color: BrandColors.destructive)
                    SummaryItem(label: "Effective Rate", value: nil, color: BrandColors.info, text: CurrencyFormatter.formatPercent(taxResult.effectiveTaxRate))
                }
            }
        }
    }

    // MARK: - Safe Harbor Card

    private var safeHarborCard: some View {
        GWCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14))
                        .foregroundStyle(BrandColors.success)
                    Text("Safe Harbor Optimizer")
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)
                    Spacer()
                    GWBadge("IRS Rule", color: BrandColors.info)
                }

                // Minimum payment info
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Minimum This Quarter")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text(CurrencyFormatter.format(safeHarborResult.minimumQuarterlyPayment))
                            .font(Typography.moneySmall)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundStyle(BrandColors.success)
                    }

                    Spacer()

                    if safeHarborResult.savings > 50 {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("You Save")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textSecondary)
                            Text(CurrencyFormatter.format(safeHarborResult.savings))
                                .font(Typography.moneySmall)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .foregroundStyle(BrandColors.primary)
                        }
                    }
                }

                Text(safeHarborResult.explanation)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .lineSpacing(2)

                // Show rule used
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(BrandColors.textTertiary)
                    Text("Rule: \(safeHarborResult.ruleUsed.rawValue)")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Tax Vault Card

    private var taxVaultCard: some View {
        Button {
            showingTaxVault = true
        } label: {
            VStack(spacing: Spacing.md) {
                // Header row
                HStack {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(BrandColors.success.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(BrandColors.success)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Tax Vault")
                                .font(Typography.headline)
                                .foregroundStyle(BrandColors.textPrimary)
                            Text("Set-aside tracker")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandColors.textTertiary)
                }

                // Balance & progress
                HStack(spacing: 0) {
                    VStack(spacing: Spacing.xxs) {
                        Text(CurrencyFormatter.format(max(vaultBalance, 0)))
                            .font(Typography.moneySmall)
                            .foregroundStyle(vaultBalance > 0 ? BrandColors.success : BrandColors.textSecondary)
                        Text("Vault Balance")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(BrandColors.textTertiary.opacity(0.2))
                        .frame(width: 1, height: 36)

                    VStack(spacing: Spacing.xxs) {
                        Text(CurrencyFormatter.format(vaultTotalSetAside))
                            .font(Typography.moneySmall)
                            .foregroundStyle(BrandColors.primary)
                        Text("Total Set Aside")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(BrandColors.textTertiary.opacity(0.2))
                        .frame(width: 1, height: 36)

                    VStack(spacing: Spacing.xxs) {
                        Text(CurrencyFormatter.format(vaultQuarterlyTarget))
                            .font(Typography.moneySmall)
                            .foregroundStyle(BrandColors.textSecondary)
                        Text("Quarterly Goal")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Progress bar toward quarterly target
                VStack(spacing: Spacing.xs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(BrandColors.success.opacity(0.12))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [BrandColors.success.opacity(0.7), BrandColors.success],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(geo.size.width * vaultProgress, 0), height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text(vaultBalance > 0
                             ? "\(Int(vaultProgress * 100))% of quarterly target"
                             : "Tap to start setting aside for taxes")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                        Spacer()
                    }
                }
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collapsible Section Builder

    private func collapsibleSection<Content: View>(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Header (tap to expand/collapse)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.wrappedValue.toggle()
                }
                HapticManager.shared.select()
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BrandColors.primary)
                        .frame(width: 24)

                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    if let badge {
                        Text(badge)
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(Spacing.lg)
                .background(BrandColors.cardBackground)
                .clipShape(
                    RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                )
            }
            .buttonStyle(.plain)

            // Content (animated expand/collapse)
            if isExpanded.wrappedValue {
                VStack(spacing: Spacing.md) {
                    content()
                }
                .padding(.top, Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Quarterly Estimates Content

    @ViewBuilder
    private var quarterlyEstimatesContent: some View {
        ForEach(TaxQuarter.allCases) { quarter in
            let paid = paymentsForQuarter(quarter)
            let estimated = quarterlyTaxEstimate(for: quarter)
            VStack(spacing: 0) {
                QuarterlyEstimateCard(
                    quarter: quarter,
                    estimatedPayment: estimated,
                    isCurrent: DateHelper.isCurrentQuarter(quarter),
                    daysUntilDue: DateHelper.daysUntilDue(quarter: quarter, year: DateHelper.currentTaxYear)
                )

                // Payment status for this quarter
                if paid > 0 || (DateHelper.isCurrentQuarter(quarter) && estimated > 0) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: paid >= estimated && estimated > 0 ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.system(size: 12))
                            .foregroundStyle(paid >= estimated && estimated > 0 ? BrandColors.success : BrandColors.warning)

                        Text(paid > 0 ? "Paid: \(CurrencyFormatter.format(paid))" : "Not yet paid")
                            .font(Typography.caption2)
                            .foregroundStyle(paid > 0 ? BrandColors.success : BrandColors.textTertiary)

                        Spacer()

                        if paid > 0 && paid < estimated {
                            Text("Remaining: \(CurrencyFormatter.format(estimated - paid))")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.warning)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(BrandColors.cardBackground.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                }
            }
        }
    }

    // MARK: - Tax Breakdown Content

    private var taxBreakdownContent: some View {
        GWCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if yearlyIncome == 0 {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(BrandColors.info)
                        Text("Add income entries to see your federal and state tax breakdown.")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Spacing.sm)
                    .background(BrandColors.info.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                }

                TaxBreakdownRow(label: "Self-Employment Tax", amount: taxResult.selfEmploymentTax, detail: "15.3% SE \u{00B7} SS capped at $\(Int(TaxEngine.TaxConstants.socialSecurityWageBase / 1000))K")
                TaxBreakdownRow(label: "Federal Income Tax", amount: taxResult.federalIncomeTax, detail: federalRateDetail)
                TaxBreakdownRow(label: "State Income Tax", amount: taxResult.stateIncomeTax, detail: stateRateDetail)

                // Show credits applied if user has selected any
                if let totalCredits = profile?.estimatedTotalCredits, totalCredits > 0 {
                    TaxBreakdownRow(
                        label: "Tax Credits Applied",
                        amount: -min(totalCredits, taxResult.federalIncomeTax + taxResult.stateIncomeTax),
                        detail: "\(String(profile?.selectedTaxCredits.count ?? 0)) credit(s) \u{00B7} reduces income tax"
                    )
                }

                // Show deduction method
                if let method = profile?.deductionMethod, method != .notSure {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(BrandColors.textTertiary)
                        Text("Personal deduction: \(method.shortName) (\(CurrencyFormatter.format(profile?.effectivePersonalDeduction ?? 0)))")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }

                Divider()

                HStack {
                    Text("Total Estimated Tax")
                        .font(Typography.headline)
                    Spacer()
                    Text(CurrencyFormatter.format(taxResult.totalEstimatedTax))
                        .font(Typography.moneyMedium)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(BrandColors.destructive)
                }
            }
        }
    }

    // MARK: - Recent Payments Content

    @ViewBuilder
    private var recentPaymentsContent: some View {
        ForEach(taxPayments.prefix(5)) { payment in
            HStack(spacing: Spacing.md) {
                Image(systemName: payment.paymentType.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(payment.paymentType == .federal ? BrandColors.info : BrandColors.primary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("\(payment.paymentType.rawValue) \u{2014} \(payment.quarter.shortName)")
                        .font(Typography.bodyMedium)
                    Text(payment.paymentDate.formatted(.dateTime.month().day().year()))
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                Spacer()

                Text(CurrencyFormatter.format(payment.amount))
                    .font(Typography.moneyCaption)
                    .foregroundStyle(BrandColors.success)
            }
            .gwCard()
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Spacing.md) {
            GWButton("Multi-State Taxes", icon: "map.fill", style: .secondary) {
                showingMultiState = true
            }

            GWButton("Find Missing Deductions", icon: "sparkle.magnifyingglass", style: .secondary) {
                if profile?.isPremium == true {
                    showingDeductionFinder = true
                } else {
                    appState.showingPaywall = true
                }
            }

            GWButton("Export Tax Summary", icon: "square.and.arrow.up", style: .secondary) {
                if profile?.isPremium == true {
                    showingExport = true
                } else {
                    appState.showingPaywall = true
                }
            }
        }
    }
}

struct SummaryItem: View {
    let label: String
    let value: Double?
    let color: Color
    var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
            Text(text ?? CurrencyFormatter.format(value ?? 0))
                .font(Typography.moneySmall)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundStyle(color)
        }
    }
}

struct TaxBreakdownRow: View {
    let label: String
    let amount: Double
    let detail: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(label)
                    .font(Typography.body)
                Text(detail)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.sm)
            Text(CurrencyFormatter.format(amount))
                .font(Typography.moneyCaption)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .foregroundStyle(BrandColors.textPrimary)
        }
    }
}
