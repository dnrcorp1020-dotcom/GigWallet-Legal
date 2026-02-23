import SwiftUI
import SwiftData

/// Interactive "Tax Vault" — track money mentally set aside for taxes.
/// NOT a real bank account. A psychological commitment tracker that shows
/// what users SHOULD have saved vs what they actually owe.
struct TaxVaultView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaxVaultEntry.entryDate, order: .reverse) private var vaultEntries: [TaxVaultEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \IncomeEntry.entryDate) private var incomeEntries: [IncomeEntry]
    @Query(sort: \ExpenseEntry.expenseDate) private var expenseEntries: [ExpenseEntry]

    @State private var showingQuickSetAside = false
    @State private var showSetAsideSuccess = false

    private var profile: UserProfile? { profiles.first }

    // MARK: - Computed Properties

    private var vaultBalance: Double {
        vaultEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0.0) { total, entry in
                entry.type.isCredit ? total + entry.amount : total - entry.amount
            }
    }

    private var totalSetAside: Double {
        vaultEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear && $0.type == .setAside }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalPayments: Double {
        vaultEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear && $0.type == .taxPayment }
            .reduce(0) { $0 + $1.amount }
    }

    private var estimatedAnnualTax: Double {
        let yearlyIncome = incomeEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.netAmount }
        let yearlyDeductions = expenseEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.deductibleAmount }
        let engine = TaxEngine()
        let result = engine.calculateEstimate(
            grossIncome: yearlyIncome,
            totalDeductions: yearlyDeductions,
            filingStatus: profile?.filingStatus ?? FilingStatus.single,
            stateCode: profile?.stateCode ?? "CA",
            w2Withholding: profile?.estimatedW2Withholding ?? 0,
            w2Income: profile?.estimatedW2Income ?? 0,
            personalDeduction: profile?.effectivePersonalDeduction,
            taxCredits: profile?.estimatedTotalCredits ?? 0
        )
        return result.totalEstimatedTax
    }

    private var effectiveTaxRate: Double {
        let yearlyIncome = incomeEntries
            .filter { $0.taxYear == DateHelper.currentTaxYear }
            .reduce(0) { $0 + $1.netAmount }
        guard yearlyIncome > 0 else { return 0.25 }
        return min(estimatedAnnualTax / yearlyIncome, 0.5)
    }

    private var suggestedSetAside: Double {
        let todaysIncome = incomeEntries
            .filter { Calendar.current.isDateInToday($0.entryDate) }
            .reduce(0) { $0 + $1.netAmount }
        return todaysIncome * effectiveTaxRate
    }

    private var quarterlyTarget: Double {
        estimatedAnnualTax / 4
    }

    private var quarterlyProgress: Double {
        guard quarterlyTarget > 0 else {
            // No tax target yet — if they've set aside money, show 100% (target exceeded)
            return vaultBalance > 0 ? 1.0 : 0
        }
        return min(max(vaultBalance, 0) / quarterlyTarget, 1.0)
    }

    private var vaultStatusMessage: String {
        if vaultBalance <= 0 {
            return "Start setting aside for taxes"
        } else if quarterlyProgress >= 1.0 {
            return "Quarterly target reached!"
        } else if quarterlyProgress >= 0.75 {
            return "Almost there \u{2014} keep going!"
        } else if quarterlyProgress >= 0.5 {
            return "Halfway to your quarterly target"
        } else {
            return "Building your tax reserve"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // Hero: Progress Ring + Balance
                vaultHero

                // Quick Actions
                quickActionsSection

                // Stats Grid
                statsGrid

                // Ledger
                ledgerSection

                // Disclaimer
                Text("This doesn't move real money \u{2014} it tracks what you should save for taxes.")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BrandColors.groupedBackground)
        .gwNavigationTitle("Tax ", accent: "Vault", icon: "lock.shield.fill")
        .sheet(isPresented: $showingQuickSetAside) {
            QuickSetAsideView(
                suggestedAmount: suggestedSetAside,
                effectiveTaxRate: effectiveTaxRate
            )
        }
    }

    // MARK: - Hero Section (Progress Ring + Balance)

    private var vaultHero: some View {
        VStack(spacing: Spacing.lg) {
            // Progress ring with vault icon center
            ZStack {
                // Outer glow for emphasis
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BrandColors.success.opacity(0.08),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 50,
                            endRadius: 90
                        )
                    )
                    .frame(width: 180, height: 180)

                // Progress ring
                GWProgressRing(
                    progress: quarterlyProgress,
                    lineWidth: 10,
                    size: 140,
                    label: nil,
                    sublabel: nil
                )
                // Override the ring colors to use success green for vault
                .overlay {
                    ZStack {
                        // Background track
                        Circle()
                            .stroke(BrandColors.success.opacity(0.12), lineWidth: 10)
                            .frame(width: 140, height: 140)

                        // Progress arc
                        Circle()
                            .trim(from: 0, to: quarterlyProgress)
                            .stroke(
                                LinearGradient(
                                    colors: [BrandColors.success, BrandColors.success.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .frame(width: 140, height: 140)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 1.0).delay(0.2), value: quarterlyProgress)

                        // Center content
                        VStack(spacing: Spacing.xs) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(BrandColors.success)

                            Text("\(Int(quarterlyProgress * 100))%")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(BrandColors.textPrimary)
                                .contentTransition(.numericText())

                            Text("of target")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.textTertiary)
                        }
                    }
                }
                .frame(width: 140, height: 140)
            }

            // Balance
            VStack(spacing: Spacing.xs) {
                Text(CurrencyFormatter.format(max(vaultBalance, 0)))
                    .font(Typography.moneyLarge)
                    .foregroundStyle(vaultBalance >= 0 ? BrandColors.success : BrandColors.destructive)
                    .contentTransition(.numericText())

                Text(vaultStatusMessage)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            // Quarterly target info
            if estimatedAnnualTax > 0 {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "target")
                        .font(.system(size: 11))
                        .foregroundStyle(BrandColors.textTertiary)
                    Text("Quarterly target: \(CurrencyFormatter.format(quarterlyTarget))")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(BrandColors.success.opacity(0.06))
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: Spacing.md) {
            // Smart suggestion (one-tap)
            if suggestedSetAside > 0 {
                Button {
                    let entry = TaxVaultEntry(
                        amount: suggestedSetAside,
                        type: .setAside,
                        note: "Today's earnings \u{00D7} \(Int(effectiveTaxRate * 100))% tax rate"
                    )
                    modelContext.insert(entry)
                    HapticManager.shared.success()
                    withAnimation(.spring(response: 0.3)) {
                        showSetAsideSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { showSetAsideSuccess = false }
                    }
                } label: {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 40, height: 40)
                            Image(systemName: showSetAsideSuccess ? "checkmark" : "wand.and.stars")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(showSetAsideSuccess ? "Done!" : "Set aside \(CurrencyFormatter.format(suggestedSetAside))")
                                .font(Typography.bodyMedium)
                            Text("Based on today's earnings \u{00D7} \(Int(effectiveTaxRate * 100))% rate")
                                .font(Typography.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                        }

                        Spacer()

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .padding(Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [BrandColors.success, BrandColors.success.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                }
                .buttonStyle(GWButtonPressStyle())
            }

            // Custom amount
            Button {
                showingQuickSetAside = true
            } label: {
                HStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.primary.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(BrandColors.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Amount")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(BrandColors.textPrimary)
                        Text("Choose a specific amount to set aside")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BrandColors.textTertiary)
                }
                .padding(Spacing.md)
                .background(BrandColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            }
            .buttonStyle(GWButtonPressStyle())
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: Spacing.md) {
            statTile(
                icon: "arrow.up.circle.fill",
                iconColor: BrandColors.success,
                value: CurrencyFormatter.format(totalSetAside),
                label: "Set Aside"
            )

            statTile(
                icon: "arrow.down.circle.fill",
                iconColor: BrandColors.destructive,
                value: CurrencyFormatter.format(totalPayments),
                label: "Tax Paid"
            )

            statTile(
                icon: "banknote.fill",
                iconColor: BrandColors.primary,
                value: CurrencyFormatter.format(max(vaultBalance, 0)),
                label: "Balance"
            )
        }
    }

    private func statTile(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(iconColor)

            Text(value)
                .font(Typography.moneyCaption)
                .foregroundStyle(BrandColors.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label)
                .font(Typography.caption2)
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
    }

    // MARK: - Ledger

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("History")
                    .font(Typography.headline)
                Spacer()
                if !vaultEntries.isEmpty {
                    Text("\(String(vaultEntries.count)) entries")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)

            if vaultEntries.isEmpty {
                VStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.textTertiary.opacity(0.08))
                            .frame(width: 64, height: 64)
                        Image(systemName: "tray")
                            .font(.system(size: 24))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    Text("No entries yet")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(BrandColors.textSecondary)
                    Text("Set aside money to start building your tax reserve")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxl)
                .padding(.horizontal, Spacing.lg)
            } else {
                List {
                    ForEach(vaultEntries.prefix(20)) { entry in
                        HStack(spacing: Spacing.md) {
                            // Icon with colored background
                            ZStack {
                                Circle()
                                    .fill(entry.type.color.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: entry.type.sfSymbol)
                                    .foregroundStyle(entry.type.color)
                                    .font(.system(size: 15, weight: .medium))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.type.rawValue)
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(BrandColors.textPrimary)
                                HStack(spacing: Spacing.xs) {
                                    Text(entry.entryDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(Typography.caption2)
                                        .foregroundStyle(BrandColors.textTertiary)
                                    if !entry.note.isEmpty {
                                        Text("\u{00B7}")
                                            .foregroundStyle(BrandColors.textTertiary)
                                        Text(entry.note)
                                            .font(Typography.caption2)
                                            .foregroundStyle(BrandColors.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            Text("\(entry.type.isCredit ? "+" : "-")\(CurrencyFormatter.format(entry.amount))")
                                .font(Typography.moneyCaption)
                                .foregroundStyle(entry.type.isCredit ? BrandColors.success : BrandColors.destructive)
                        }
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(entry)
                                HapticManager.shared.success()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: CGFloat(min(vaultEntries.count, 20)) * 56)
                .scrollDisabled(true)
            }
        }
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
    }
}
