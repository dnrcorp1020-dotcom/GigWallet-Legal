import SwiftUI
import SwiftData

/// Premium feature: Export tax data for TurboTax, H&R Block, Schedule C, or CSV
struct TaxExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \IncomeEntry.entryDate) private var incomeEntries: [IncomeEntry]
    @Query(sort: \ExpenseEntry.expenseDate) private var expenseEntries: [ExpenseEntry]
    @Query private var mileageTrips: [MileageTrip]
    @Query private var profiles: [UserProfile]

    @State private var selectedFormat: TaxExportService.ExportFormat = .scheduleC
    @State private var exportURL: URL?
    @State private var showingShareSheet = false
    @State private var showingPreview = false
    @State private var previewContent = ""

    private var profile: UserProfile? { profiles.first }

    private var exportData: TaxExportService.TaxExportData {
        let year = DateHelper.currentTaxYear
        return TaxExportService.TaxExportData(
            taxYear: year,
            filingStatus: profile?.filingStatus ?? .single,
            income: incomeEntries.filter { $0.taxYear == year },
            expenses: expenseEntries.filter { $0.taxYear == year },
            mileageTrips: mileageTrips.filter { $0.taxYear == year }
        )
    }

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            // Header
            VStack(spacing: Spacing.sm) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(BrandColors.primary)

                Text("Tax Export")
                    .font(Typography.title)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("Export your \(String(DateHelper.currentTaxYear)) tax data")
                    .font(Typography.callout)
                    .foregroundStyle(BrandColors.textSecondary)
            }
            .padding(.top, Spacing.lg)

            // Summary card
            VStack(spacing: Spacing.md) {
                summaryRow("Gross Income", value: exportData.totalGrossIncome)
                summaryRow("Total Expenses", value: exportData.totalExpenses, color: BrandColors.destructive)
                summaryRow("Mileage", value: exportData.mileageDeduction, subtitle: "\(String(format: "%.0f", exportData.totalMileage)) miles")
                Divider()
                summaryRow("Net Profit", value: exportData.netProfit, color: exportData.netProfit >= 0 ? BrandColors.success : BrandColors.destructive, bold: true)
            }
            .gwCard()

            // Format selection
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Export Format")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textTertiary)
                    .padding(.leading, Spacing.xs)

                ForEach(TaxExportService.ExportFormat.allCases) { format in
                    Button {
                        selectedFormat = format
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: format.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selectedFormat == format ? .white : BrandColors.primary)
                                .frame(width: 36, height: 36)
                                .background(
                                    selectedFormat == format
                                        ? BrandColors.primary
                                        : BrandColors.primary.opacity(0.1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(format.rawValue)
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(BrandColors.textPrimary)
                                Text(format.description)
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }

                            Spacer()

                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(BrandColors.primary)
                            }
                        }
                        .padding(Spacing.md)
                        .background(
                            selectedFormat == format
                                ? BrandColors.primary.opacity(0.06)
                                : BrandColors.cardBackground
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                                .stroke(
                                    selectedFormat == format ? BrandColors.primary : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                    }
                }
            }

            Spacer()

            // Action buttons
            VStack(spacing: Spacing.md) {
                Button {
                    previewExport()
                } label: {
                    HStack {
                        Image(systemName: "eye.fill")
                        Text("Preview")
                    }
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(BrandColors.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                }

                Button {
                    exportAndShare()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export & Share")
                    }
                    .font(Typography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                    .background(BrandColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .navigationTitle("Tax Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                ScrollView {
                    Text(previewContent)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .padding()
                }
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingPreview = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Helpers

    private func summaryRow(_ label: String, value: Double, color: Color = BrandColors.textPrimary, subtitle: String? = nil, bold: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(bold ? Typography.bodyMedium : Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }
            Spacer()
            Text(CurrencyFormatter.format(value))
                .font(bold ? Typography.moneySmall : Typography.moneyCaption)
                .foregroundStyle(color)
        }
    }

    private func previewExport() {
        switch selectedFormat {
        case .csv:
            previewContent = TaxExportService.generateCSV(from: exportData)
        case .txf:
            previewContent = TaxExportService.generateTXF(from: exportData)
        case .scheduleC:
            previewContent = TaxExportService.generateScheduleCSummary(from: exportData)
        }
        showingPreview = true
    }

    private func exportAndShare() {
        if let url = TaxExportService.exportToFile(data: exportData, format: selectedFormat) {
            exportURL = url
            showingShareSheet = true
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
