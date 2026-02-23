import SwiftUI
import SwiftData

/// Interactive guide that helps gig workers understand W-2 withholding,
/// deductions (standard vs itemized), and tax credits through a simple questionnaire.
/// Features step-by-step navigation with back button support.
struct W2WithholdingGuideView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: GuideStep = .intro
    @State private var stepHistory: [GuideStep] = [] // For back navigation
    @State private var hasW2Job = false
    @State private var knowsWithholding = false
    @State private var withholdingAmount: Double = 0 // Exact withholding
    @State private var estimatedSalary: Double = 0 // For salary-based estimate
    @State private var estimatedRate: WithholdingRate = .typical
    @State private var deductionMethod: DeductionMethod = DeductionMethod.notSure
    @State private var estimatedItemizedAmount: Double = 0
    @State private var selectedCredits: Set<TaxCreditType> = []

    // MARK: - Types

    enum GuideStep: Int, CaseIterable {
        case intro
        case doYouHaveW2
        case doYouKnowAmount
        case enterAmount
        case estimateFromSalary
        case deductionType
        case credits
        case result
    }

    enum WithholdingRate: String, CaseIterable {
        case low = "Low (Single, no dependents)"
        case typical = "Typical (Standard deduction)"
        case high = "High (Extra withholding)"

        var percentage: Double {
            switch self {
            case .low: return 0.18
            case .typical: return 0.22
            case .high: return 0.28
            }
        }

        var description: String {
            switch self {
            case .low: return "~18% of salary"
            case .typical: return "~22% of salary"
            case .high: return "~28% of salary"
            }
        }
    }

    // DeductionMethod and TaxCreditType enums are defined in UserProfile.swift

    private var estimatedWithholding: Double {
        estimatedSalary * estimatedRate.percentage
    }

    private var standardDeductionAmount: Double {
        switch profile.filingStatus {
        case .single: return 15700
        case .marriedJoint: return 31400
        case .marriedSeparate: return 15700
        case .headOfHousehold: return 23500
        }
    }

    private var totalSteps: Int {
        hasW2Job ? 5 : 4
    }

    private var currentStepNumber: Int {
        switch currentStep {
        case .intro: return 0
        case .doYouHaveW2: return 1
        case .doYouKnowAmount, .enterAmount, .estimateFromSalary: return 2
        case .deductionType: return hasW2Job ? 3 : 2
        case .credits: return hasW2Job ? 4 : 3
        case .result: return totalSteps
        }
    }

    // MARK: - Navigation

    private func goTo(_ step: GuideStep) {
        stepHistory.append(currentStep)
        withAnimation(.easeInOut(duration: 0.3)) { currentStep = step }
    }

    private func goBack() {
        guard let previous = stepHistory.popLast() else {
            dismiss()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) { currentStep = previous }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                // Progress indicator (except intro & result)
                if currentStep != .intro && currentStep != .result {
                    progressBar
                }

                switch currentStep {
                case .intro:
                    introSection
                case .doYouHaveW2:
                    doYouHaveW2Section
                case .doYouKnowAmount:
                    doYouKnowAmountSection
                case .enterAmount:
                    enterAmountSection
                case .estimateFromSalary:
                    estimateFromSalarySection
                case .deductionType:
                    deductionTypeSection
                case .credits:
                    creditsSection
                case .result:
                    resultSection
                }
            }
            .padding(Spacing.lg)
            .padding(.top, Spacing.md)
        }
        .background(BrandColors.groupedBackground)
        .navigationTitle("Tax Profile Guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentStep != .intro {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        goBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16))
                        }
                        .foregroundStyle(BrandColors.primary)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(currentStep != .intro)
        .onAppear {
            // Pre-populate from existing profile data when reopening the guide
            deductionMethod = profile.deductionMethod
            estimatedItemizedAmount = profile.estimatedItemizedDeductions
            selectedCredits = profile.selectedTaxCredits
            withholdingAmount = profile.estimatedW2Withholding
            estimatedSalary = profile.estimatedW2Income
            hasW2Job = profile.gigWorkerType == .sideGig
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                Text("Step \(String(currentStepNumber)) of \(String(totalSteps))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BrandColors.primary)
                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(BrandColors.primary.opacity(0.12))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(BrandColors.primary)
                        .frame(width: geo.size.width * CGFloat(currentStepNumber) / CGFloat(totalSteps), height: 6)
                        .animation(.spring(response: 0.4), value: currentStepNumber)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Step: Intro

    private var introSection: some View {
        VStack(spacing: Spacing.xxl) {
            ZStack {
                Circle()
                    .fill(BrandColors.primary.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(BrandColors.primary)
            }

            VStack(spacing: Spacing.md) {
                Text("Let's Set Up Your Tax Profile")
                    .font(Typography.title)
                    .multilineTextAlignment(.center)

                Text("We'll help you figure out your W-2 withholding, deduction method, and any credits you may qualify for — so your tax estimates are accurate.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                guideInfoRow(
                    icon: "dollarsign.arrow.circlepath",
                    title: "W-2 Withholding",
                    detail: "If you have a regular job, your employer already pays some of your taxes"
                )
                guideInfoRow(
                    icon: "doc.text",
                    title: "Standard vs Itemized",
                    detail: "Choose the deduction method that saves you the most"
                )
                guideInfoRow(
                    icon: "star.fill",
                    title: "Tax Credits",
                    detail: "Credits directly reduce your tax bill dollar-for-dollar"
                )
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))

            GWButton("Let's Get Started", icon: "arrow.right") {
                goTo(.doYouHaveW2)
            }
        }
    }

    // MARK: - Step: Do you have a W-2 job?

    private var doYouHaveW2Section: some View {
        VStack(spacing: Spacing.xxl) {
            stepHeader(question: "Do you have a regular job that gives you a paycheck with taxes taken out?")

            VStack(spacing: Spacing.md) {
                questionCard(
                    icon: "checkmark.circle.fill",
                    title: "Yes, I have a W-2 job",
                    detail: "I get regular paychecks from an employer (full-time, part-time, or seasonal)",
                    color: BrandColors.success
                ) {
                    hasW2Job = true
                    goTo(.doYouKnowAmount)
                }

                questionCard(
                    icon: "xmark.circle.fill",
                    title: "No, gig work is my only income",
                    detail: "I'm fully self-employed — Uber, DoorDash, freelance, etc. are my only income sources",
                    color: BrandColors.textSecondary
                ) {
                    hasW2Job = false
                    profile.estimatedW2Withholding = 0
                    goTo(.deductionType)
                }
            }

            tipBox(text: "Not sure? If you receive a W-2 form at tax time (not a 1099), you have a W-2 job.")
        }
    }

    // MARK: - Step: Do you know your withholding amount?

    private var doYouKnowAmountSection: some View {
        VStack(spacing: Spacing.xxl) {
            stepHeader(question: "Do you know how much federal tax is withheld from your paychecks each year?")

            VStack(spacing: Spacing.md) {
                questionCard(
                    icon: "doc.text.magnifyingglass",
                    title: "Yes, I can look it up",
                    detail: "I can check my pay stub, W-2 form, or payroll app",
                    color: BrandColors.success
                ) {
                    knowsWithholding = true
                    goTo(.enterAmount)
                }

                questionCard(
                    icon: "questionmark.circle",
                    title: "No idea, help me estimate",
                    detail: "I'll enter my approximate salary and we'll estimate it",
                    color: BrandColors.primary
                ) {
                    knowsWithholding = false
                    goTo(.estimateFromSalary)
                }
            }

            tipBox(text: "Where to find it:\n\u{2022} Pay stub: Look for \"Federal Tax Withheld\" or \"FIT\"\n\u{2022} Last year's W-2: Box 2 (\"Federal income tax withheld\")\n\u{2022} Payroll app: ADP, Gusto, Paychex — check your tax summary")
        }
    }

    // MARK: - Step: Enter exact amount

    private var enterAmountSection: some View {
        VStack(spacing: Spacing.xxl) {
            stepHeader(question: "Enter your annual federal tax withholding")

            VStack(spacing: Spacing.md) {
                Text("Annual W-2 Withholding")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)

                TextField("$0", value: $withholdingAmount, format: .currency(code: "USD"))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)

                Text("Total federal tax withheld per year from your W-2 job")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.xxl)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Common ranges")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)

                HStack(spacing: Spacing.sm) {
                    ForEach([5000, 8000, 12000, 18000], id: \.self) { amount in
                        Button {
                            HapticManager.shared.tap()
                            withholdingAmount = Double(amount)
                        } label: {
                            Text("$\(amount / 1000)K")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(withholdingAmount == Double(amount) ? .white : BrandColors.primary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(withholdingAmount == Double(amount) ? BrandColors.primary : BrandColors.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            GWButton("Continue", icon: "arrow.right") {
                HapticManager.shared.tap()
                profile.estimatedW2Withholding = withholdingAmount
                goTo(.deductionType)
            }
            .opacity(withholdingAmount > 0 ? 1 : 0.5)
            .disabled(withholdingAmount <= 0)
        }
    }

    // MARK: - Step: Estimate from salary

    private var estimateFromSalarySection: some View {
        VStack(spacing: Spacing.xxl) {
            stepHeader(question: "Let's estimate your withholding from your salary")

            VStack(spacing: Spacing.md) {
                Text("Approximate Annual Salary")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)

                TextField("$0", value: $estimatedSalary, format: .currency(code: "USD"))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
            }
            .padding(Spacing.xxl)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))

            HStack(spacing: Spacing.sm) {
                ForEach([30000, 50000, 70000, 100000], id: \.self) { amount in
                    Button {
                        HapticManager.shared.tap()
                        estimatedSalary = Double(amount)
                    } label: {
                        Text("$\(amount / 1000)K")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(estimatedSalary == Double(amount) ? .white : BrandColors.primary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(estimatedSalary == Double(amount) ? BrandColors.primary : BrandColors.primary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Your tax situation")
                    .font(Typography.headline)

                ForEach(WithholdingRate.allCases, id: \.rawValue) { rate in
                    Button {
                        HapticManager.shared.select()
                        estimatedRate = rate
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: estimatedRate == rate ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(estimatedRate == rate ? BrandColors.primary : BrandColors.textTertiary)
                                .font(.system(size: 20))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(rate.rawValue)
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(BrandColors.textPrimary)
                                Text(rate.description)
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }

                            Spacer()
                        }
                        .padding(Spacing.md)
                        .background(estimatedRate == rate ? BrandColors.primary.opacity(0.06) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))

            if estimatedSalary > 0 {
                VStack(spacing: Spacing.sm) {
                    Text("Estimated Annual Withholding")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)

                    Text(CurrencyFormatter.format(estimatedWithholding))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColors.success)

                    Text("This is a rough estimate. Your actual W-2 or pay stub will be more accurate.")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(BrandColors.success.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            }

            GWButton("Continue", icon: "arrow.right") {
                HapticManager.shared.tap()
                profile.estimatedW2Withholding = estimatedWithholding
                goTo(.deductionType)
            }
            .opacity(estimatedSalary > 0 ? 1 : 0.5)
            .disabled(estimatedSalary <= 0)
        }
    }

    // MARK: - Step: Deduction Type (Standard vs Itemized)

    private var deductionTypeSection: some View {
        VStack(spacing: Spacing.xxl) {
            stepHeader(question: "How will you take your deductions?")

            Text("Everyone gets to reduce their taxable income. You choose whichever method saves you more:")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)

            // Standard deduction
            deductionCard(
                method: .standard,
                icon: "checkmark.shield.fill",
                title: "Standard Deduction",
                amount: standardDeductionAmount,
                bullets: [
                    "Flat amount — no receipts needed",
                    "Best for most gig workers",
                    "\(CurrencyFormatter.format(standardDeductionAmount)) for \(profile.filingStatus.rawValue.lowercased()) filers"
                ]
            )

            // Itemized
            deductionCard(
                method: .itemized,
                icon: "list.clipboard.fill",
                title: "Itemized Deductions",
                amount: nil,
                bullets: [
                    "Add up specific expenses (mortgage interest, medical, state taxes, charitable donations)",
                    "Only worth it if total exceeds the standard deduction",
                    "Requires keeping receipts and records"
                ]
            )

            // Not sure
            questionCard(
                icon: "questionmark.circle.fill",
                title: "Not sure yet",
                detail: "We'll use the standard deduction — you can change this later in Settings",
                color: BrandColors.primary
            ) {
                deductionMethod = .notSure
                goTo(.credits)
            }

            if deductionMethod == .itemized {
                VStack(spacing: Spacing.md) {
                    Text("Estimated Total Itemized Deductions")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)

                    TextField("$0", value: $estimatedItemizedAmount, format: .currency(code: "USD"))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .keyboardType(.decimalPad)

                    if estimatedItemizedAmount > 0 && estimatedItemizedAmount < standardDeductionAmount {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(BrandColors.warning)
                                .font(.system(size: 12))
                            Text("The standard deduction (\(CurrencyFormatter.format(standardDeductionAmount))) may save you more")
                                .font(Typography.caption2)
                                .foregroundStyle(BrandColors.warning)
                        }
                    }
                }
                .padding(Spacing.lg)
                .background(BrandColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))

                GWButton("Continue", icon: "arrow.right") {
                    HapticManager.shared.tap()
                    goTo(.credits)
                }
            }

            tipBox(text: "Important: Your gig work expenses (mileage, phone, supplies) are deducted on Schedule C separately from your personal deduction. This choice is for your personal tax return.")
        }
    }

    private func deductionCard(method: DeductionMethod, icon: String, title: String, amount: Double?, bullets: [String]) -> some View {
        Button {
            HapticManager.shared.tap()
            withAnimation(.easeInOut(duration: 0.2)) {
                deductionMethod = method
            }
            if method == .standard {
                goTo(.credits)
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(deductionMethod == method ? BrandColors.primary : BrandColors.textSecondary)

                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(BrandColors.textPrimary)

                    Spacer()

                    if deductionMethod == method {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BrandColors.primary)
                    }
                }

                if let amount {
                    Text(CurrencyFormatter.format(amount))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColors.primary)
                }

                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Text("•")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                        Text(bullet)
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                    }
                }
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                    .stroke(deductionMethod == method ? BrandColors.primary : Color.clear, lineWidth: 2)
            )
            .shadow(color: BrandColors.cardShadow, radius: 2, y: 1)
        }
        .buttonStyle(GWButtonPressStyle())
    }

    // MARK: - Step: Tax Credits

    private var creditsSection: some View {
        VStack(spacing: Spacing.xxl) {
            stepHeader(question: "Do any of these tax credits apply to you?")

            Text("Tax credits reduce your tax bill dollar-for-dollar — they're more valuable than deductions. Select any that apply.")
                .font(Typography.body)
                .foregroundStyle(BrandColors.textSecondary)

            VStack(spacing: Spacing.sm) {
                ForEach(TaxCreditType.allCases) { credit in
                    Button {
                        HapticManager.shared.select()
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if selectedCredits.contains(credit) {
                                selectedCredits.remove(credit)
                            } else {
                                selectedCredits.insert(credit)
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: selectedCredits.contains(credit) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedCredits.contains(credit) ? BrandColors.primary : BrandColors.textTertiary)
                                .font(.system(size: 20))

                            Image(systemName: credit.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(BrandColors.primary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.rawValue)
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(BrandColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                                Text(credit.shortDescription)
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }

                            Spacer()
                        }
                        .padding(Spacing.md)
                        .background(selectedCredits.contains(credit) ? BrandColors.primary.opacity(0.06) : BrandColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !selectedCredits.isEmpty {
                let totalCredits = selectedCredits.reduce(0.0) { $0 + $1.estimatedValue }
                VStack(spacing: Spacing.sm) {
                    Text("Potential Tax Savings from Credits")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                    Text("Up to \(CurrencyFormatter.format(totalCredits))")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(BrandColors.success)
                    Text("Actual amounts depend on your specific situation. Consult a tax professional for exact eligibility.")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity)
                .background(BrandColors.success.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            }

            GWButton(selectedCredits.isEmpty ? "Skip — No Credits" : "Continue", icon: "arrow.right") {
                HapticManager.shared.tap()
                goTo(.result)
            }

            tipBox(text: "Not sure about eligibility? That's okay — you can always come back and update this. These estimates help GigWallet give you more accurate quarterly tax payments.")
        }
    }

    // MARK: - Final: Result Summary

    private var resultSection: some View {
        VStack(spacing: Spacing.xxl) {
            ZStack {
                Circle()
                    .fill(BrandColors.success.opacity(0.1))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(BrandColors.success)
            }

            Text("Tax Profile Complete!")
                .font(Typography.title)

            // Summary card
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("YOUR TAX PROFILE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BrandColors.textTertiary)
                    .kerning(1)

                summaryRow(
                    icon: "building.2.fill",
                    label: "W-2 Withholding",
                    value: hasW2Job ? "\(CurrencyFormatter.format(profile.estimatedW2Withholding))/yr" : "None (gig only)",
                    color: hasW2Job ? BrandColors.primary : BrandColors.textSecondary
                )

                Divider()

                summaryRow(
                    icon: deductionMethod == .itemized ? "list.clipboard.fill" : "checkmark.shield.fill",
                    label: "Deduction Method",
                    value: deductionMethod == .itemized
                        ? "Itemized (\(CurrencyFormatter.format(estimatedItemizedAmount)))"
                        : "Standard (\(CurrencyFormatter.format(standardDeductionAmount)))",
                    color: BrandColors.primary
                )

                Divider()

                summaryRow(
                    icon: "star.fill",
                    label: "Tax Credits",
                    value: selectedCredits.isEmpty
                        ? "None selected"
                        : "\(String(selectedCredits.count)) credit\(selectedCredits.count > 1 ? "s" : "") selected",
                    color: selectedCredits.isEmpty ? BrandColors.textSecondary : BrandColors.success
                )

                if !selectedCredits.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Array(selectedCredits).sorted(by: { $0.rawValue < $1.rawValue })) { credit in
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: credit.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(BrandColors.primary)
                                    .frame(width: 16)
                                Text(credit.rawValue)
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textSecondary)
                            }
                        }
                    }
                    .padding(.leading, 36)
                }
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))

            VStack(alignment: .leading, spacing: Spacing.md) {
                resultInfoRow(
                    icon: "arrow.down.circle.fill",
                    text: hasW2Job
                        ? "Your quarterly estimated payments will account for W-2 withholding"
                        : "You'll need to pay quarterly estimated taxes on all gig income",
                    color: BrandColors.success
                )
                resultInfoRow(
                    icon: "calendar.badge.clock",
                    text: "You can update these settings anytime in Settings → Tax Profile",
                    color: BrandColors.primary
                )
                resultInfoRow(
                    icon: "person.fill.questionmark",
                    text: "For complex situations, consider consulting a tax professional",
                    color: BrandColors.textSecondary
                )
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))

            GWButton("Done", icon: "checkmark") {
                HapticManager.shared.success()
                // Persist all tax profile data to UserProfile
                profile.deductionMethod = deductionMethod
                profile.estimatedItemizedDeductions = estimatedItemizedAmount
                profile.selectedTaxCredits = selectedCredits
                if estimatedSalary > 0 {
                    profile.estimatedW2Income = estimatedSalary
                }
                profile.gigWorkerType = hasW2Job ? .sideGig : .fullTime
                dismiss()
            }
        }
    }

    // MARK: - Reusable Components

    private func stepHeader(question: String) -> some View {
        Text(question)
            .font(Typography.title)
            .multilineTextAlignment(.center)
    }

    private func summaryRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
                Text(value)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.textPrimary)
            }

            Spacer()
        }
    }

    private func questionCard(icon: String, title: String, detail: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.tap()
            action()
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BrandColors.textTertiary)
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
            .shadow(color: BrandColors.cardShadow, radius: 2, y: 1)
        }
        .buttonStyle(GWButtonPressStyle())
    }

    private func guideInfoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(BrandColors.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyMedium)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }
        }
    }

    private func resultInfoRow(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
        }
    }

    private func tipBox(text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(BrandColors.warning)

            Text(text)
                .font(Typography.caption)
                .foregroundStyle(BrandColors.textSecondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColors.warning.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
    }
}
