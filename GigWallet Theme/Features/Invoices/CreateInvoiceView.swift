import SwiftUI
import SwiftData

/// Create a new professional invoice with dynamic line items.
/// Auto-generates sequential invoice number (INV-YYYY-NNN).
struct CreateInvoiceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingInvoices: [Invoice]
    @Query private var profiles: [UserProfile]

    // Client info
    @State private var clientName = ""
    @State private var clientEmail = ""
    @State private var clientAddress = ""

    // Dates
    @State private var issueDate = Date.now
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now

    // Line items
    @State private var lineItems: [EditableLineItem] = [EditableLineItem()]

    // Options
    @State private var includeTax = false
    @State private var taxRate = ""
    @State private var notes = ""
    @State private var selectedPlatform: GigPlatformType = .other

    // Preview
    @State private var showingPreview = false
    @State private var previewPDFData: Data?

    private var profile: UserProfile? { profiles.first }

    private var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.computedTotal }
    }

    private var taxAmount: Double {
        guard includeTax, let rate = Double(taxRate) else { return 0 }
        return subtotal * (rate / 100)
    }

    private var total: Double {
        subtotal + taxAmount
    }

    private var isValid: Bool {
        !clientName.isEmpty && lineItems.contains(where: { !$0.description.isEmpty && $0.computedTotal > 0 })
    }

    var body: some View {
        Form {
            // Invoice number preview
            Section {
                HStack {
                    Text("Invoice #")
                        .font(Typography.body)
                        .foregroundStyle(BrandColors.textSecondary)
                    Spacer()
                    Text(InvoiceService.nextInvoiceNumber(existingInvoices: existingInvoices))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(BrandColors.primary)
                }
            }

            // Client info
            Section("Client Information") {
                TextField("Client Name *", text: $clientName)
                TextField("Email", text: $clientEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                TextField("Address", text: $clientAddress, axis: .vertical)
                    .lineLimit(2...4)
            }

            // Dates
            Section("Dates") {
                DatePicker("Issue Date", selection: $issueDate, displayedComponents: .date)
                DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
            }

            // Line items
            Section("Line Items") {
                ForEach($lineItems) { $item in
                    VStack(spacing: Spacing.sm) {
                        TextField("Description *", text: $item.description)

                        HStack {
                            HStack {
                                Text("Qty")
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                                TextField("1", text: $item.quantity)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 50)
                            }

                            Spacer()

                            HStack {
                                Text("Rate")
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                                Text("$")
                                    .foregroundStyle(BrandColors.textTertiary)
                                TextField("0.00", text: $item.rate)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                            }

                            Spacer()

                            Text(CurrencyFormatter.format(item.computedTotal))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(BrandColors.textPrimary)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indices in
                    lineItems.remove(atOffsets: indices)
                    if lineItems.isEmpty {
                        lineItems.append(EditableLineItem())
                    }
                }

                Button {
                    lineItems.append(EditableLineItem())
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(BrandColors.primary)
                        Text("Add Line Item")
                            .foregroundStyle(BrandColors.primary)
                    }
                }
            }

            // Tax
            Section("Tax") {
                Toggle("Include Tax", isOn: $includeTax)
                    .tint(BrandColors.primary)

                if includeTax {
                    HStack {
                        Text("Tax Rate")
                        Spacer()
                        TextField("8.25", text: $taxRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                        Text("%")
                            .foregroundStyle(BrandColors.textTertiary)
                    }
                }
            }

            // Platform
            Section("Details") {
                Picker("Platform", selection: $selectedPlatform) {
                    ForEach(GigPlatformType.allCases) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }

                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            // Total summary
            Section {
                VStack(spacing: Spacing.sm) {
                    HStack {
                        Text("Subtotal")
                            .foregroundStyle(BrandColors.textSecondary)
                        Spacer()
                        Text(CurrencyFormatter.format(subtotal))
                            .fontWeight(.medium)
                    }

                    if includeTax && taxAmount > 0 {
                        HStack {
                            Text("Tax (\(taxRate)%)")
                                .foregroundStyle(BrandColors.textSecondary)
                            Spacer()
                            Text(CurrencyFormatter.format(taxAmount))
                                .fontWeight(.medium)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Total")
                            .font(Typography.headline)
                        Spacer()
                        Text(CurrencyFormatter.format(total))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(BrandColors.primary)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }

            // Actions
            Section {
                Button {
                    generatePreview()
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                        Text("Preview & Share PDF")
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(BrandColors.primary)
                    .fontWeight(.semibold)
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle("New Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    saveInvoice()
                }
                .fontWeight(.semibold)
                .disabled(!isValid)
            }
        }
        .sheet(isPresented: $showingPreview) {
            if let pdfData = previewPDFData {
                InvoicePDFPreviewView(pdfData: pdfData)
            }
        }
    }

    // MARK: - Actions

    private func saveInvoice() {
        let invoiceLineItems = lineItems
            .filter { !$0.description.isEmpty && $0.computedTotal > 0 }
            .map { InvoiceLineItem(description: $0.description, quantity: $0.computedQuantity, rate: $0.computedRate) }

        let invoice = Invoice(
            invoiceNumber: InvoiceService.nextInvoiceNumber(existingInvoices: existingInvoices),
            clientName: clientName,
            clientEmail: clientEmail,
            clientAddress: clientAddress,
            issueDate: issueDate,
            dueDate: dueDate,
            lineItems: invoiceLineItems,
            taxRate: includeTax ? (Double(taxRate) ?? 0) / 100 : 0,
            notes: notes,
            platform: selectedPlatform
        )

        // Generate and cache PDF
        let snapshot = InvoiceService.UserProfileSnapshot(
            displayName: profile?.displayName ?? "GigWallet User",
            email: profile?.email ?? ""
        )
        invoice.pdfData = InvoiceService.generatePDF(for: invoice, profile: snapshot)

        modelContext.insert(invoice)
        HapticManager.shared.success()
        dismiss()
    }

    private func generatePreview() {
        let invoiceLineItems = lineItems
            .filter { !$0.description.isEmpty }
            .map { InvoiceLineItem(description: $0.description, quantity: $0.computedQuantity, rate: $0.computedRate) }

        let invoice = Invoice(
            invoiceNumber: InvoiceService.nextInvoiceNumber(existingInvoices: existingInvoices),
            clientName: clientName,
            clientEmail: clientEmail,
            clientAddress: clientAddress,
            issueDate: issueDate,
            dueDate: dueDate,
            lineItems: invoiceLineItems,
            taxRate: includeTax ? (Double(taxRate) ?? 0) / 100 : 0,
            notes: notes,
            platform: selectedPlatform
        )

        let snapshot = InvoiceService.UserProfileSnapshot(
            displayName: profile?.displayName ?? "GigWallet User",
            email: profile?.email ?? ""
        )
        previewPDFData = InvoiceService.generatePDF(for: invoice, profile: snapshot)
        showingPreview = true
    }
}

// MARK: - Editable Line Item

struct EditableLineItem: Identifiable {
    let id = UUID()
    var description: String = ""
    var quantity: String = "1"
    var rate: String = ""

    var computedQuantity: Double { Double(quantity) ?? 1 }
    var computedRate: Double { Double(rate) ?? 0 }
    var computedTotal: Double { computedQuantity * computedRate }
}

// MARK: - PDF Preview

struct InvoicePDFPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let pdfData: Data

    var body: some View {
        NavigationStack {
            VStack {
                // Simple PDF preview using PDFKit would be ideal,
                // but for now show a success state with share option
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(BrandColors.primary)

                    Text("Invoice PDF Ready")
                        .font(Typography.title)
                        .foregroundStyle(BrandColors.textPrimary)

                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(pdfData.count), countStyle: .file))")
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)

                    Button {
                        sharePDF()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Invoice")
                        }
                        .font(Typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.xxl)
                        .padding(.vertical, Spacing.md)
                        .background(BrandColors.primary)
                        .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(BrandColors.groupedBackground)
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sharePDF() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("invoice.pdf")
        try? pdfData.write(to: tempURL)

        let activity = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activity, animated: true)
        }
    }
}
