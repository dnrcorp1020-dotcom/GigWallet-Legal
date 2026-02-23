import SwiftUI
import SwiftData

/// One-tap receipt scanning flow with freemium gating.
/// Free users get 5 lifetime OCR scans, then must upgrade to Pro for unlimited.
/// Opens camera (or photo library on simulator) → OCR processes → pre-filled expense form → save → celebration.
struct ReceiptScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]

    @State private var phase: ScanPhase = .capture
    @State private var capturedImage: UIImage?

    // OCR results
    @State private var vendor: String = ""
    @State private var amount: String = ""
    @State private var expenseDate: Date = .now
    @State private var category: ExpenseCategory = .other
    @State private var ocrConfidence: String = ""

    // Celebration
    @State private var showCelebration = false
    @State private var taxSavings: Double = 0

    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var ocrTask: Task<Void, Never>?

    private var profile: UserProfile? { profiles.first }

    enum ScanPhase {
        case capture
        case processing
        case review
        case celebration
    }

    var body: some View {
        ZStack {
            switch phase {
            case .capture:
                captureView

            case .processing:
                processingView

            case .review:
                reviewView

            case .celebration:
                celebrationView
            }
        }
        .navigationTitle("Scan Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    ocrTask?.cancel()
                    dismiss()
                }
            }
        }
        // IMPORTANT: Sheet/cover modifiers live here on the body — NOT on captureView.
        // If they were on captureView, switching phase to .processing would remove captureView
        // from the hierarchy, causing SwiftUI to panic-dismiss the entire ReceiptScanView sheet.
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(image: $capturedImage)
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPickerView { photo in
                capturedImage = photo
            }
            .ignoresSafeArea()
        }
        .onChange(of: capturedImage) { _, newImage in
            if newImage != nil {
                processReceipt()
            }
        }
    }

    // MARK: - Capture Phase

    private var captureView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(BrandColors.secondary.opacity(0.12))
                        .frame(width: 80, height: 80)

                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 36))
                        .foregroundStyle(BrandColors.secondary)
                }

                Text("receipt.scanTitle".localized)
                    .font(Typography.title)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("receipt.scanSubtitle".localized)
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            // Free scan counter
            if let profile, !profile.isPremium {
                scanCounterBadge(remaining: profile.freeScansRemaining)
            }

            Spacer()

            if let profile, !profile.canScanReceipt {
                // Out of free scans — upgrade prompt
                upgradePrompt
            } else {
                // Can scan — show capture buttons
                VStack(spacing: Spacing.md) {
                    // Take Photo — opens camera (or library on simulator)
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showCameraPicker = true
                        } else {
                            // Camera unavailable (simulator) — fall back to library
                            showImagePicker = true
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 18))
                            Text("receipt.takePhoto".localized)
                                .font(Typography.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.lg)
                        .background(BrandColors.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
                    }

                    // Choose from Library — opens photo picker
                    Button {
                        showImagePicker = true
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 18))
                            Text("receipt.chooseLibrary".localized)
                                .font(Typography.headline)
                        }
                        .foregroundStyle(BrandColors.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.lg)
                        .background(BrandColors.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
                    }
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.bottom, Spacing.xxxl)
            }
        }
    }

    // MARK: - Scan Counter Badge

    private func scanCounterBadge(remaining: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: remaining > 0 ? "sparkles" : "lock.fill")
                .font(.system(size: 14))
                .foregroundStyle(remaining > 0 ? BrandColors.secondary : BrandColors.textTertiary)

            if remaining == 1 {
                Text("receipt.lastFreeScan".localized)
                    .font(Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(BrandColors.warning)
            } else if remaining > 0 {
                Text("receipt.freeScansRemaining".localized(with: String(remaining)))
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            } else {
                Text("receipt.noFreeScans".localized)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(BrandColors.secondaryBackground)
        .clipShape(Capsule())
    }

    // MARK: - Upgrade Prompt

    private var upgradePrompt: some View {
        VStack(spacing: Spacing.lg) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(BrandColors.primary)

                Text("receipt.upgradeTitle".localized)
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("receipt.upgradeSubtitle".localized)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            GWButton("receipt.upgradeCTA".localized, icon: "star.fill") {
                appState.showingPaywall = true
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.bottom, Spacing.xxxl)
    }

    // MARK: - Processing Phase

    private var processingView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(BrandColors.secondary)

                Text("receipt.scanning".localized)
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("receipt.extracting".localized)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Review Phase

    private var reviewView: some View {
        Form {
            // Receipt preview
            if let image = capturedImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                        .frame(maxWidth: .infinity)
                }
            }

            Section("Receipt Details") {
                HStack {
                    Label("Vendor", systemImage: "storefront")
                    Spacer()
                    TextField("Vendor name", text: $vendor)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Label("Amount", systemImage: "dollarsign.circle")
                    Spacer()
                    TextField("0.00", text: $amount)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }

                DatePicker(
                    selection: $expenseDate,
                    displayedComponents: .date
                ) {
                    Label("Date", systemImage: "calendar")
                }

                Picker(selection: $category) {
                    ForEach(ExpenseCategory.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                } label: {
                    Label("Category", systemImage: "tag")
                }
            }

            if !ocrConfidence.isEmpty {
                Section {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(BrandColors.secondary)
                        Text("OCR Confidence: \(ocrConfidence)")
                            .font(Typography.caption2)
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }

            Section {
                Button {
                    saveExpense()
                } label: {
                    HStack {
                        Spacer()
                        Label("Save Write-Off", systemImage: "checkmark.circle.fill")
                            .font(Typography.headline)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(BrandColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Celebration Phase

    private var celebrationView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(BrandColors.success)

                Text("Expense Saved!")
                    .font(Typography.title)
                    .foregroundStyle(BrandColors.textPrimary)

                if taxSavings > 0 {
                    VStack(spacing: Spacing.xs) {
                        Text("Estimated tax savings")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        Text(CurrencyFormatter.format(taxSavings))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(BrandColors.success)
                    }
                }
            }

            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Actions

    private func processReceipt() {
        // Cancel any previous OCR task (e.g., user re-picked a photo)
        ocrTask?.cancel()

        phase = .processing

        ocrTask = Task {
            guard let image = capturedImage else {
                phase = .capture
                return
            }

            do {
                let receiptData = try await ReceiptOCRService.extractReceiptData(from: image)

                // If the view was dismissed while OCR was running, bail out
                guard !Task.isCancelled else { return }

                // Record the scan for free users
                profile?.recordReceiptScan()

                // Populate fields from OCR
                vendor = receiptData.vendor ?? ""
                if let total = receiptData.totalAmount {
                    amount = String(format: "%.2f", total)
                }
                if let date = receiptData.date {
                    expenseDate = date
                }
                ocrConfidence = receiptData.confidence.displayName

                // Auto-categorize if we have vendor info
                if let vendorName = receiptData.vendor, !vendorName.isEmpty {
                    let prediction = ExpenseCategorizationEngine.categorize(
                        description: vendorName,
                        merchantName: vendorName,
                        amount: receiptData.totalAmount ?? 0
                    )
                    if prediction.confidence >= 0.5,
                       let matched = ExpenseCategory.allCases.first(where: { $0.rawValue == prediction.category }) {
                        category = matched
                    }
                }

                phase = .review
            } catch {
                guard !Task.isCancelled else { return }
                // OCR failed — still show form for manual entry (don't count as a scan)
                ocrConfidence = "Manual entry"
                phase = .review
            }
        }
    }

    private func saveExpense() {
        guard let amountValue = Double(amount), amountValue > 0 else { return }

        // Most gig expense categories are deductible
        let isDeductible = category != .other

        let expense = ExpenseEntry(
            amount: amountValue,
            category: category,
            vendor: vendor.isEmpty ? "Receipt Scan" : vendor,
            description: "Scanned receipt",
            expenseDate: expenseDate,
            isDeductible: isDeductible,
            deductionPercentage: isDeductible ? 100 : 0
        )
        modelContext.insert(expense)

        // Calculate tax savings estimate (rough: amount x 30% marginal rate)
        if isDeductible {
            taxSavings = amountValue * 0.30
        }

        HapticManager.shared.celebrate()

        withAnimation(AnimationConstants.spring) {
            phase = .celebration
        }

        // Auto-dismiss after 2 seconds (only if still on celebration screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if phase == .celebration {
                dismiss()
            }
        }
    }
}

// MARK: - Simple Image Picker (PHPickerViewController wrapper)

import PhotosUI

struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView

        init(_ parent: ImagePickerView) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // DO NOT call picker.dismiss(animated:) — let SwiftUI manage the sheet
            // lifecycle via the isPresented binding. Calling UIKit dismiss directly
            // races with SwiftUI's state management and can cascade to dismiss parent views.

            guard let result = results.first else {
                // User cancelled — just dismiss the sheet
                parent.dismiss()
                return
            }

            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                Task { @MainActor in
                    self.parent.image = image
                    // Dismiss AFTER setting the image, so the binding change
                    // triggers onChange before the sheet disappears
                    self.parent.dismiss()
                }
            }
        }
    }
}

