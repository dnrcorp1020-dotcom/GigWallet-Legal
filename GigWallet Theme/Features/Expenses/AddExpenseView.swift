import SwiftUI
import SwiftData
import PhotosUI

/// Redesigned expense entry — smart, fast, minimal manual input.
/// Three modes:
/// 1. Quick Add — one-tap common expenses with smart defaults
/// 2. Auto-Detect — bank transaction scan and receipt OCR
/// 3. Manual — traditional form (available when needed)
struct AddExpenseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]

    @State private var selectedMode: ExpenseMode = .quick
    @State private var amount: Double = 0
    @State private var selectedCategory: ExpenseCategory = .gas
    @State private var vendor: String = ""
    @State private var expenseDescription: String = ""
    @State private var expenseDate: Date = .now
    @State private var isDeductible: Bool = true
    @State private var deductionPercentage: Double = 100
    @State private var mileage: String = ""
    @State private var showingAmountEntry = false
    @State private var autoCategorySuggestion: ExpenseCategorizationEngine.CategoryPrediction?
    @State private var showingAutoSuggestion = false

    // MARK: - Receipt Photo State
    @State private var receiptPhotoItem: PhotosPickerItem?
    @State private var receiptImageData: Data?
    @State private var receiptImage: Image?
    @State private var showingReceiptOptions = false
    @State private var showingCamera = false

    // MARK: - Receipt OCR State
    @State private var isProcessingReceipt = false
    @State private var receiptScanResult: ReceiptOCRService.ReceiptData?
    @State private var receiptScanError: String?

    private let detectionService = ExpenseDetectionService.shared
    private var profile: UserProfile? { profiles.first }

    enum ExpenseMode: String, CaseIterable {
        case quick = "Quick Add"
        case autoDetect = "Auto-Detect"
        case manual = "Manual"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Mode picker
                modePicker
                    .padding(.top, Spacing.sm)

                switch selectedMode {
                case .quick:
                    quickAddView
                case .autoDetect:
                    autoDetectView
                case .manual:
                    manualEntryView
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .background(BrandColors.groupedBackground)
        .scrollDismissesKeyboard(.interactively)
        .tint(BrandColors.primary)
        .gwNavigationTitle("Add ", accent: "Write-Off", icon: "creditcard.fill")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(ExpenseMode.allCases, id: \.rawValue) { mode in
                Button {
                    withAnimation(AnimationConstants.smooth) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(Typography.caption)
                        .fontWeight(selectedMode == mode ? .semibold : .regular)
                        .foregroundStyle(selectedMode == mode ? .white : BrandColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(selectedMode == mode ? BrandColors.primary : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                }
            }
        }
        .padding(3)
        .background(BrandColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
    }

    // MARK: - Quick Add (Smart Suggestions)

    private var quickAddView: some View {
        VStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Common Write-Offs")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                ForEach(detectionService.quickSuggestions) { suggestion in
                    QuickExpenseCard(suggestion: suggestion) {
                        selectedCategory = suggestion.category
                        deductionPercentage = suggestion.deductionPercentage
                        vendor = suggestion.title
                        isDeductible = true
                        withAnimation(AnimationConstants.smooth) {
                            showingAmountEntry = true
                        }
                    }
                }
            }

            // Amount entry (appears after selection)
            if showingAmountEntry {
                VStack(spacing: Spacing.md) {
                    Divider()

                    Text("Enter Amount")
                        .font(Typography.headline)

                    if selectedCategory == .mileage {
                        mileageInput
                    } else {
                        GWAmountField(title: "Amount", amount: $amount, placeholder: "0.00")
                    }

                    // Date
                    dateRow

                    // Deduction info
                    if isDeductible {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(BrandColors.success)
                            Text("\(Int(deductionPercentage))% tax deductible")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.success)
                            Spacer()
                        }
                    }

                    // Receipt photo
                    receiptSection

                    // Save button
                    GWButton("Save Write-Off", icon: "checkmark.circle.fill") {
                        saveExpense()
                    }
                    .disabled(amount <= 0 && Double(mileage) ?? 0 <= 0)
                    .opacity(amount > 0 || (Double(mileage) ?? 0) > 0 ? 1.0 : 0.5)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Auto-Detect View

    private var autoDetectView: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(BrandColors.info.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 32))
                        .foregroundStyle(BrandColors.info)
                }

                Text("Smart Write-Off Detection")
                    .font(Typography.title)

                Text("Connect your bank account and we'll automatically find deductible expenses like gas, phone bills, tolls, and more.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Spacing.lg)

            VStack(spacing: Spacing.md) {
                DetectionMethodCard(
                    icon: "building.columns.fill",
                    title: "Bank Transaction Scan",
                    subtitle: "Auto-detect expenses from linked bank",
                    badge: "Best",
                    badgeColor: BrandColors.success
                )

                Button {
                    showingCamera = true
                } label: {
                    DetectionMethodCard(
                        icon: "camera.fill",
                        title: "Receipt Scanner",
                        subtitle: "Snap a photo \u{2014} we'll fill in the rest",
                        badge: "NEW",
                        badgeColor: BrandColors.success
                    )
                }

                DetectionMethodCard(
                    icon: "envelope.fill",
                    title: "Email Receipt Parsing",
                    subtitle: "Import receipts from email",
                    badge: "Soon",
                    badgeColor: BrandColors.textTertiary
                )
            }

            // Info about connecting bank
            VStack(spacing: Spacing.sm) {
                HStack {
                    Text("How It Works")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Spacer()
                }

                Text("Connect your bank and we'll automatically scan transactions for deductible expenses like gas, phone, insurance, and more.")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
                    .lineSpacing(3)
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        }
    }

    // MARK: - Manual Entry

    private var manualEntryView: some View {
        VStack(spacing: Spacing.lg) {
            // Category
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Category")
                    .font(Typography.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                    ForEach(ExpenseCategory.allCases) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }

            // Amount
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Amount")
                    .font(Typography.headline)

                if selectedCategory == .mileage {
                    mileageInput
                } else {
                    GWAmountField(title: "Amount", amount: $amount, placeholder: "0.00")
                }
            }

            // Details
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Details")
                    .font(Typography.headline)

                TextField("Vendor", text: $vendor)
                    .padding(Spacing.md)
                    .background(BrandColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                    .onChange(of: vendor) { _, newValue in
                        runAutoCategorizaton(vendor: newValue)
                    }

                // AI Auto-Category Suggestion
                if showingAutoSuggestion, let suggestion = autoCategorySuggestion {
                    Button {
                        applySuggestion(suggestion)
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 14))
                                .foregroundStyle(BrandColors.info)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Auto-detected: \(suggestion.category)")
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textPrimary)
                                Text(suggestion.reasoning)
                                    .font(Typography.caption2)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }

                            Spacer()

                            Text("Apply")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 4)
                                .background(BrandColors.info)
                                .clipShape(Capsule())
                        }
                        .padding(Spacing.md)
                        .background(BrandColors.info.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                TextField("Description (optional)", text: $expenseDescription)
                    .padding(Spacing.md)
                    .background(BrandColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))

                dateRow
            }

            // Deduction
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Tax Deduction")
                    .font(Typography.headline)

                Toggle("Tax Deductible", isOn: $isDeductible)
                    .tint(BrandColors.primary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(BrandColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))

                if isDeductible {
                    HStack {
                        Text("Deduction %")
                            .font(Typography.body)
                        Spacer()
                        TextField("100", value: $deductionPercentage, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%")
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(BrandColors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                }
            }

            // Receipt
            receiptSection

            // Save
            GWButton("Save Write-Off", icon: "checkmark.circle.fill") {
                saveExpense()
            }
            .disabled(amount <= 0 && Double(mileage) ?? 0 <= 0)
            .opacity(amount > 0 || (Double(mileage) ?? 0) > 0 ? 1.0 : 0.5)
        }
    }

    // MARK: - Shared Components

    /// A shared receipt attachment row shown in both Quick Add and Manual modes.
    /// Uses `PhotosPicker` for library access and a camera sheet for live capture.
    @ViewBuilder
    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Receipt")
                .font(Typography.headline)

            if let receiptImage {
                // Thumbnail + remove button
                ZStack(alignment: .topTrailing) {
                    receiptImage
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))

                    Button {
                        withAnimation(AnimationConstants.quick) {
                            self.receiptImage = nil
                            self.receiptImageData = nil
                            self.receiptPhotoItem = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                            .padding(Spacing.sm)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Attachment options
                HStack(spacing: Spacing.sm) {
                    // Camera
                    Button {
                        showingCamera = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14))
                            Text("Camera")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(BrandColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(BrandColors.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    }

                    // Photo Library
                    PhotosPicker(
                        selection: $receiptPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 14))
                            Text("Library")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(BrandColors.info)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(BrandColors.info.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                    }
                }
            }

            // Free scan counter (shown for non-premium users when they have a photo)
            if let profile, !profile.isPremium, receiptImage != nil {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: profile.freeScansRemaining > 0 ? "sparkles" : "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(profile.freeScansRemaining > 0 ? BrandColors.secondary : BrandColors.textTertiary)

                    if profile.freeScansRemaining == 1 {
                        Text("receipt.lastFreeScan".localized)
                            .font(Typography.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(BrandColors.warning)
                    } else if profile.freeScansRemaining > 0 {
                        Text("receipt.freeScansRemaining".localized(with: String(profile.freeScansRemaining)))
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textSecondary)
                    } else {
                        Text("receipt.noFreeScans".localized)
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }

                    Spacer()

                    if profile.freeScansRemaining == 0 {
                        Button {
                            appState.showingPaywall = true
                        } label: {
                            Text("receipt.upgrade".localized)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 4)
                                .background(BrandColors.primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(BrandColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
            }

            // IRS tip
            HStack(spacing: Spacing.xs) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(BrandColors.textTertiary)
                Text("The IRS recommends keeping receipts for all business expenses.")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            // OCR processing indicator
            if isProcessingReceipt {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .tint(BrandColors.primary)
                    Text("Scanning receipt...")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.md)
                .background(BrandColors.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            }

            // OCR scan error
            if let error = receiptScanError {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BrandColors.warning)
                    Text(error)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Spacer()
                    Button {
                        withAnimation { receiptScanError = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
                .padding(Spacing.md)
                .background(BrandColors.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // OCR scan results
            if let scanResult = receiptScanResult {
                ReceiptScanResultView(
                    result: scanResult,
                    onApplyAmount: { value in
                        amount = value
                    },
                    onApplyVendor: { name in
                        vendor = name
                        runAutoCategorizaton(vendor: name)
                    },
                    onApplyDate: { date in
                        expenseDate = date
                    },
                    onApplyAll: {
                        applyAllScanResults(scanResult)
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // Load image data when a Photos item is selected
        .onChange(of: receiptPhotoItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { return }
                receiptImageData = uiImage.jpegData(compressionQuality: 0.75)
                receiptImage = Image(uiImage: uiImage)
                await processReceiptOCR(image: uiImage)
            }
        }
        // Camera sheet — uses UIImagePickerController via a thin wrapper
        .sheet(isPresented: $showingCamera) {
            CameraPickerView { uiImage in
                receiptImageData = uiImage.jpegData(compressionQuality: 0.75)
                receiptImage = Image(uiImage: uiImage)
                Task {
                    await processReceiptOCR(image: uiImage)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var mileageInput: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "road.lanes")
                    .foregroundStyle(BrandColors.primary)
                TextField("Miles driven", text: $mileage)
                    .keyboardType(.decimalPad)
                    .font(Typography.moneyMedium)
                Text("mi")
                    .foregroundStyle(BrandColors.textTertiary)
            }
            .padding(Spacing.md)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))

            if let miles = Double(mileage), miles > 0 {
                HStack {
                    Text("Deduction")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                    Spacer()
                    Text(CurrencyFormatter.format(miles * TaxEngine.TaxConstants.mileageRate))
                        .font(Typography.moneySmall)
                        .foregroundStyle(BrandColors.success)
                }
                .padding(.horizontal, Spacing.sm)

                Text("IRS rate: $\(String(format: "%.2f", TaxEngine.TaxConstants.mileageRate))/mi for \(DateHelper.currentTaxYear)")
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
    }

    private var dateRow: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundStyle(BrandColors.textTertiary)
            DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
                .labelsHidden()
            Spacer()
        }
        .padding(Spacing.sm)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
    }

    // MARK: - Auto-Categorization

    private func runAutoCategorizaton(vendor: String) {
        guard vendor.count >= 3 else {
            withAnimation(AnimationConstants.quick) {
                showingAutoSuggestion = false
            }
            return
        }

        let prediction = ExpenseCategorizationEngine.categorize(
            description: expenseDescription,
            merchantName: vendor,
            amount: amount
        )

        if prediction.confidence >= 0.5 {
            autoCategorySuggestion = prediction
            withAnimation(AnimationConstants.smooth) {
                showingAutoSuggestion = true
            }
        } else {
            withAnimation(AnimationConstants.quick) {
                showingAutoSuggestion = false
            }
        }
    }

    private func applySuggestion(_ suggestion: ExpenseCategorizationEngine.CategoryPrediction) {
        if let category = ExpenseCategory.allCases.first(where: { $0.rawValue == suggestion.category }) {
            selectedCategory = category
        }
        isDeductible = suggestion.isDeductible
        deductionPercentage = suggestion.deductionPercentage * 100
        HapticManager.shared.select()
        withAnimation(AnimationConstants.smooth) {
            showingAutoSuggestion = false
        }
    }

    // MARK: - Receipt OCR

    private func processReceiptOCR(image: UIImage) async {
        // Gate: check if user can scan
        guard let profile, profile.canScanReceipt else {
            // Out of free scans — show paywall
            appState.showingPaywall = true
            return
        }

        isProcessingReceipt = true
        receiptScanResult = nil
        receiptScanError = nil

        do {
            let result = try await ReceiptOCRService.extractReceiptData(from: image)
            // Record the scan for free users
            profile.recordReceiptScan()
            withAnimation(AnimationConstants.smooth) {
                receiptScanResult = result
                isProcessingReceipt = false
            }
        } catch {
            withAnimation(AnimationConstants.quick) {
                isProcessingReceipt = false
                receiptScanError = "Could not read receipt. Try a clearer photo or enter details manually."
            }
            HapticManager.shared.error()
        }
    }

    private func applyAllScanResults(_ result: ReceiptOCRService.ReceiptData) {
        if let totalAmount = result.totalAmount {
            amount = totalAmount
        }
        if let vendorName = result.vendor {
            vendor = vendorName
            // Also run auto-categorization on extracted vendor
            runAutoCategorizaton(vendor: vendorName)
        }
        if let date = result.date {
            expenseDate = date
        }
        HapticManager.shared.success()
        withAnimation(AnimationConstants.smooth) {
            receiptScanResult = nil
        }
    }

    // MARK: - Save

    private func saveExpense() {
        let finalAmount: Double
        if selectedCategory == .mileage, let miles = Double(mileage), miles > 0 {
            finalAmount = miles * TaxEngine.TaxConstants.mileageRate
        } else {
            finalAmount = amount
        }

        let clampedDeductionPercentage = min(max(deductionPercentage, 0), 100)

        let expense = ExpenseEntry(
            amount: finalAmount,
            category: selectedCategory,
            vendor: vendor,
            description: expenseDescription,
            expenseDate: expenseDate,
            isDeductible: isDeductible,
            deductionPercentage: clampedDeductionPercentage,
            mileage: Double(mileage),
            receiptImageData: receiptImageData
        )
        modelContext.insert(expense)
        dismiss()
    }
}

// MARK: - Quick Expense Card

struct QuickExpenseCard: View {
    let suggestion: ExpenseDetectionService.ExpenseSuggestion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(suggestion.category.color)
                    .frame(width: 44, height: 44)
                    .background(suggestion.category.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(Typography.bodyMedium)
                        .foregroundStyle(BrandColors.textPrimary)
                    Text(suggestion.subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textTertiary)
                }

                Spacer()

                if suggestion.deductionPercentage > 0 {
                    GWBadge("\(Int(suggestion.deductionPercentage))%", color: BrandColors.success)
                }

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(BrandColors.primary)
            }
            .padding(Spacing.md)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        }
    }
}

// MARK: - Detection Method Card

struct DetectionMethodCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String
    let badgeColor: Color

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(BrandColors.primary)
                .frame(width: 44, height: 44)
                .background(BrandColors.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.textPrimary)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }

            Spacer()

            GWBadge(badge, color: badgeColor)
        }
        .padding(Spacing.md)
        .background(BrandColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text(value)
                .font(Typography.moneySmall)
                .foregroundStyle(color)
            Text(label)
                .font(Typography.caption2)
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: ExpenseCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: category.sfSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? .white : category.color)

                Text(category.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .white : BrandColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? category.color : category.color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
        }
    }
}
// MARK: - Camera Picker

/// A thin SwiftUI wrapper around `UIImagePickerController` for camera capture.
/// Delivers the selected `UIImage` via `onCapture` and dismisses itself.
/// Falls back to the photo library on Simulator where the camera is unavailable.
struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

