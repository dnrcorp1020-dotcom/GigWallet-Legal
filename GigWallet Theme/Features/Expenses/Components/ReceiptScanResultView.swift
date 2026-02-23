import SwiftUI

/// Inline result card shown after receipt OCR scan completes.
/// Displays extracted vendor, amount, and date with confidence indicators
/// and an "Apply All" button to auto-fill the expense form.
struct ReceiptScanResultView: View {
    let result: ReceiptOCRService.ReceiptData
    let onApplyAmount: (Double) -> Void
    let onApplyVendor: (String) -> Void
    let onApplyDate: (Date) -> Void
    let onApplyAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with confidence badge
            HStack {
                Image(systemName: "doc.text.viewfinder")
                    .foregroundStyle(BrandColors.success)
                    .font(.system(size: 16))

                Text("Receipt Scanned")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                Spacer()

                confidenceBadge
            }

            Divider()

            // Extracted fields
            VStack(spacing: Spacing.sm) {
                if let vendor = result.vendor {
                    extractedField(
                        icon: "storefront.fill",
                        label: "Vendor",
                        value: vendor,
                        color: BrandColors.info
                    ) {
                        onApplyVendor(vendor)
                    }
                }

                if let amount = result.totalAmount {
                    extractedField(
                        icon: "dollarsign.circle.fill",
                        label: "Amount",
                        value: CurrencyFormatter.format(amount),
                        color: BrandColors.success
                    ) {
                        onApplyAmount(amount)
                    }
                }

                if let date = result.date {
                    extractedField(
                        icon: "calendar.circle.fill",
                        label: "Date",
                        value: date.formatted(date: .abbreviated, time: .omitted),
                        color: BrandColors.primary
                    ) {
                        onApplyDate(date)
                    }
                }

                // Line items count
                if !result.lineItems.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(BrandColors.textTertiary)
                            .font(.system(size: 14))
                            .frame(width: 24)

                        Text("\(result.lineItems.count) item\(result.lineItems.count == 1 ? "" : "s") detected")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textSecondary)

                        Spacer()
                    }
                }
            }

            // Low confidence warning
            if result.confidence == .low {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BrandColors.warning)
                        .font(.system(size: 12))
                    Text("Low confidence \u{2014} please review values carefully")
                        .font(Typography.caption2)
                        .foregroundStyle(BrandColors.warning)
                }
            }

            // Apply All button
            if result.totalAmount != nil || result.vendor != nil {
                Button(action: onApplyAll) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                        Text("Apply All to Expense")
                            .font(Typography.bodyMedium)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(BrandColors.success)
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
                }
            }
        }
        .padding(Spacing.lg)
        .background(BrandColors.success.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg)
                .stroke(BrandColors.success.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Subviews

    private var confidenceBadge: some View {
        Text(result.confidence.displayName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 3)
            .background(confidenceColor)
            .clipShape(Capsule())
    }

    private var confidenceColor: Color {
        switch result.confidence {
        case .high: return BrandColors.success
        case .medium: return BrandColors.warning
        case .low: return BrandColors.destructive
        }
    }

    private func extractedField(
        icon: String,
        label: String,
        value: String,
        color: Color,
        onApply: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Typography.caption2)
                    .foregroundStyle(BrandColors.textTertiary)
                Text(value)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(BrandColors.textPrimary)
            }

            Spacer()

            Button(action: onApply) {
                Text("Apply")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
