import SwiftUI
import SwiftData

/// List of all invoices with status badges, search, and quick actions.
/// Professional invoicing included in GigWallet premium.
struct InvoiceListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]

    @State private var showingCreateInvoice = false
    @State private var searchText = ""
    @State private var selectedFilter: InvoiceStatus? = nil

    private var filteredInvoices: [Invoice] {
        var result = invoices

        if let filter = selectedFilter {
            result = result.filter { $0.status == filter }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.clientName.localizedCaseInsensitiveContains(searchText) ||
                $0.invoiceNumber.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var totalOutstanding: Double {
        invoices
            .filter { $0.status == .sent || $0.status == .overdue }
            .reduce(0) { $0 + $1.total }
    }

    var body: some View {
        List {
            // Summary
            if !invoices.isEmpty {
                Section {
                    VStack(spacing: Spacing.sm) {
                        HStack {
                            StatColumn(
                                label: "Total Invoices",
                                value: "\(invoices.count)",
                                color: BrandColors.textPrimary
                            )

                            StatColumn(
                                label: "Outstanding",
                                value: CurrencyFormatter.format(totalOutstanding),
                                color: BrandColors.warning
                            )

                            StatColumn(
                                label: "Paid",
                                value: "\(invoices.filter { $0.status == .paid }.count)",
                                color: BrandColors.success
                            )
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }

                // Filter chips
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.sm) {
                            FilterChip(label: "All", isSelected: selectedFilter == nil) {
                                selectedFilter = nil
                            }
                            ForEach(InvoiceStatus.allCases, id: \.rawValue) { status in
                                FilterChip(
                                    label: status.rawValue,
                                    isSelected: selectedFilter == status,
                                    color: status.color
                                ) {
                                    selectedFilter = selectedFilter == status ? nil : status
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }

            // Invoice list
            if filteredInvoices.isEmpty {
                Section {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(BrandColors.textTertiary.opacity(0.5))

                        Text(invoices.isEmpty ? "No Invoices Yet" : "No Matching Invoices")
                            .font(Typography.headline)
                            .foregroundStyle(BrandColors.textPrimary)

                        Text(invoices.isEmpty
                             ? "Create professional invoices for your freelance work."
                             : "Try adjusting your search or filter.")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)
                            .multilineTextAlignment(.center)

                        if invoices.isEmpty {
                            Button {
                                showingCreateInvoice = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create First Invoice")
                                }
                                .font(Typography.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.xl)
                                .padding(.vertical, Spacing.md)
                                .background(BrandColors.primary)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xl)
                }
            } else {
                Section("Invoices") {
                    ForEach(filteredInvoices) { invoice in
                        InvoiceRow(invoice: invoice)
                            .swipeActions(edge: .trailing) {
                                if invoice.status != .paid {
                                    Button {
                                        markAsPaid(invoice)
                                    } label: {
                                        Label("Paid", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(BrandColors.success)
                                }

                                Button(role: .destructive) {
                                    modelContext.delete(invoice)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    shareInvoice(invoice)
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(BrandColors.info)
                            }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search invoices...")
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateInvoice = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(BrandColors.primary)
                }
            }
        }
        .sheet(isPresented: $showingCreateInvoice) {
            NavigationStack {
                CreateInvoiceView()
            }
        }
    }

    // MARK: - Actions

    private func markAsPaid(_ invoice: Invoice) {
        invoice.status = .paid
        HapticManager.shared.success()
    }

    private func shareInvoice(_ invoice: Invoice) {
        // Generate PDF if not cached
        if invoice.pdfData == nil {
            let snapshot = InvoiceService.UserProfileSnapshot(
                displayName: "GigWallet User",
                email: ""
            )
            invoice.pdfData = InvoiceService.generatePDF(for: invoice, profile: snapshot)
        }

        // Share via activity controller
        guard let pdfData = invoice.pdfData else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(invoice.invoiceNumber).pdf")

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

// MARK: - Invoice Row

struct InvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status icon
            ZStack {
                Circle()
                    .fill(invoice.status.color.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: invoice.status.sfSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(invoice.status.color)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.clientName)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(BrandColors.textPrimary)

                HStack(spacing: Spacing.xs) {
                    Text(invoice.invoiceNumber)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)

                    Text("\u{00B7}")
                        .foregroundStyle(BrandColors.textTertiary)

                    Text(invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }

            Spacer()

            // Amount + status
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.format(invoice.total))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(BrandColors.textPrimary)

                Text(invoice.status.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(invoice.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(invoice.status.color.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var color: Color = BrandColors.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .white : BrandColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : BrandColors.textTertiary.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Column

private struct StatColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(Typography.caption2)
                .foregroundStyle(BrandColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
