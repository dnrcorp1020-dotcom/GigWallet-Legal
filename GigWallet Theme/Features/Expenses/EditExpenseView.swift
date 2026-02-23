import SwiftUI
import SwiftData
import PhotosUI

struct EditExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var expense: ExpenseEntry

    // Local editable copies — we only write back on Save
    @State private var amount: Double
    @State private var selectedCategory: ExpenseCategory
    @State private var vendor: String
    @State private var expenseDescription: String
    @State private var expenseDate: Date
    @State private var isDeductible: Bool
    @State private var deductionPercentage: Double
    @State private var mileage: String

    // Receipt photo
    @State private var receiptPhotoItem: PhotosPickerItem?
    @State private var receiptImageData: Data?
    @State private var receiptImage: Image?
    @State private var showingCamera = false

    init(expense: ExpenseEntry) {
        self.expense = expense
        _amount              = State(initialValue: expense.amount)
        _selectedCategory    = State(initialValue: expense.category)
        _vendor              = State(initialValue: expense.vendor)
        _expenseDescription  = State(initialValue: expense.expenseDescription)
        _expenseDate         = State(initialValue: expense.expenseDate)
        _isDeductible        = State(initialValue: expense.isDeductible)
        _deductionPercentage = State(initialValue: expense.deductionPercentage)
        _mileage             = State(initialValue: expense.mileage.map { String($0) } ?? "")
        _receiptImageData    = State(initialValue: expense.receiptImageData)
        if let data = expense.receiptImageData, let ui = UIImage(data: data) {
            _receiptImage = State(initialValue: Image(uiImage: ui))
        } else {
            _receiptImage = State(initialValue: nil)
        }
    }

    var body: some View {
        Form {
            // Category
            Section("Category") {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(ExpenseCategory.allCases) { cat in
                        HStack {
                            Image(systemName: cat.sfSymbol)
                            Text(cat.rawValue)
                        }
                        .tag(cat)
                    }
                }
                .pickerStyle(.menu)
            }

            // Amount / Mileage
            Section("Amount") {
                if selectedCategory == .mileage {
                    HStack {
                        Image(systemName: "road.lanes")
                            .foregroundStyle(BrandColors.primary)
                        TextField("Miles driven", text: $mileage)
                            .keyboardType(.decimalPad)
                        Text("mi")
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                    if let miles = Double(mileage), miles > 0 {
                        HStack {
                            Text("Deduction")
                                .foregroundStyle(BrandColors.textSecondary)
                            Spacer()
                            Text(CurrencyFormatter.format(miles * TaxEngine.TaxConstants.mileageRate))
                                .foregroundStyle(BrandColors.success)
                        }
                        .font(Typography.caption)
                    }
                } else {
                    GWAmountField(title: "Amount", amount: $amount, placeholder: "0.00")
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            // Details
            Section("Details") {
                TextField("Vendor", text: $vendor)
                TextField("Description (optional)", text: $expenseDescription)
                DatePicker("Date", selection: $expenseDate, displayedComponents: .date)
            }

            // Tax Deduction
            Section("Tax Deduction") {
                Toggle("Tax Deductible", isOn: $isDeductible)
                    .tint(BrandColors.primary)
                if isDeductible {
                    HStack {
                        Text("Deduction %")
                        Spacer()
                        TextField("100", value: $deductionPercentage, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%")
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }

            // Receipt
            Section("Receipt") {
                if let receiptImage {
                    ZStack(alignment: .topTrailing) {
                        receiptImage
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                            .listRowInsets(EdgeInsets())

                        Button {
                            self.receiptImage     = nil
                            self.receiptImageData = nil
                            self.receiptPhotoItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                                .padding(Spacing.sm)
                        }
                    }
                } else {
                    HStack(spacing: Spacing.sm) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Camera", systemImage: "camera.fill")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.sm)
                                .background(BrandColors.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                        }
                        .buttonStyle(.plain)

                        PhotosPicker(
                            selection: $receiptPhotoItem,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Label("Library", systemImage: "photo.on.rectangle")
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.info)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.sm)
                                .background(BrandColors.info.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .tint(BrandColors.primary)
        .navigationTitle("Edit Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { saveChanges() }
                    .fontWeight(.semibold)
                    .disabled(amount <= 0 && (Double(mileage) ?? 0) <= 0)
            }
        }
        .onChange(of: receiptPhotoItem) { _, newItem in
            Task {
                guard let newItem,
                      let data = try? await newItem.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: data) else { return }
                receiptImageData = uiImage.jpegData(compressionQuality: 0.75)
                receiptImage = Image(uiImage: uiImage)
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPickerView { uiImage in
                receiptImageData = uiImage.jpegData(compressionQuality: 0.75)
                receiptImage = Image(uiImage: uiImage)
            }
            .ignoresSafeArea()
        }
    }

    private func saveChanges() {
        if selectedCategory == .mileage, let miles = Double(mileage), miles > 0 {
            expense.amount  = miles * TaxEngine.TaxConstants.mileageRate
            expense.mileage = miles
        } else {
            expense.amount  = amount
            expense.mileage = nil
        }
        expense.categoryRawValue     = selectedCategory.rawValue
        expense.vendor               = vendor
        expense.expenseDescription   = expenseDescription
        expense.expenseDate          = expenseDate
        expense.isDeductible         = isDeductible
        expense.deductionPercentage  = deductionPercentage
        expense.receiptImageData     = receiptImageData
        expense.taxYear              = expenseDate.taxYear
        expense.quarterRawValue      = expenseDate.taxQuarter.rawValue
        expense.updatedAt            = .now
        dismiss()
    }
}
