import SwiftUI

/// Drag-to-reorder sheet for dashboard cards within a section.
/// Presents a List with native iOS drag handles for intuitive rearrangement.
struct CardReorderSheet: View {
    let section: DashboardSection

    @Environment(\.dismiss) private var dismiss
    @State private var cards: [DashboardCardID] = []
    @State private var showingResetConfirmation = false

    private let orderManager = DashboardCardOrderManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(cards) { card in
                        cardRow(card)
                    }
                    .onMove(perform: moveCards)
                } header: {
                    Text("Drag to reorder \(section.rawValue) cards")
                        .font(.system(size: 13))
                        .foregroundStyle(BrandColors.textSecondary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Text("Reset")
                            .font(.system(size: 15))
                            .foregroundStyle(BrandColors.destructive)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        orderManager.updateOrder(for: section, cards: cards)
                        HapticManager.shared.success()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(BrandColors.primary)
                    }
                }
            }
            .alert("Reset Card Order", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) {
                    orderManager.resetOrder(for: section)
                    cards = DashboardCardID.defaultOrder(for: section)
                    HapticManager.shared.action()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Restore the default card order for the \(section.rawValue) section?")
            }
            .onAppear {
                cards = orderManager.orderedCards(for: section)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Card Row

    private func cardRow(_ card: DashboardCardID) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: card.icon)
                .font(.system(size: 16))
                .foregroundStyle(card.isPremium ? BrandColors.primary : BrandColors.textSecondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(spacing: Spacing.xs) {
                    Text(card.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(BrandColors.textPrimary)

                    if card.isPremium {
                        GWProBadge()
                    }
                }

                if card.isConditional {
                    Text("Shows when available")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColors.textTertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
        .deleteDisabled(true)
    }

    // MARK: - Actions

    private func moveCards(from source: IndexSet, to destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
        HapticManager.shared.select()
    }
}
