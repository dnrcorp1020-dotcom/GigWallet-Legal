import SwiftUI

/// Onboarding page for quick tax profile setup.
/// Asks filing status in plain language and collects state,
/// mapping user-friendly labels to `FilingStatus` enum values.
struct TaxProfileView: View {
    @Binding var filingStatus: FilingStatus
    @Binding var stateCode: String

    @State private var isAnimated = false
    @State private var searchText = ""

    private let filingOptions: [(status: FilingStatus, label: String, icon: String)] = [
        (.single, "Just me", "person.fill"),
        (.marriedJoint, "Married, filing together", "person.2.fill"),
        (.marriedSeparate, "Married, filing separate", "person.line.dotted.person.fill"),
        (.headOfHousehold, "Head of household", "house.fill")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md)
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
                .frame(height: Spacing.lg)

            // Header
            VStack(spacing: Spacing.md) {
                Text("Quick Tax\nSetup")
                    .font(Typography.largeTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandColors.textPrimary)

                Text("Takes 10 seconds \u{2014} saves you hundreds")
                    .font(Typography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BrandColors.textSecondary)
            }
            .opacity(isAnimated ? 1 : 0)
            .offset(y: isAnimated ? 0 : 20)
            .animation(AnimationConstants.smooth.delay(0.1), value: isAnimated)

            // Filing status grid
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("How do you file?")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)
                    .padding(.horizontal, Spacing.xs)

                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(filingOptions, id: \.status) { option in
                        FilingStatusCard(
                            icon: option.icon,
                            label: option.label,
                            isSelected: filingStatus == option.status,
                            accentColor: BrandColors.primary
                        ) {
                            withAnimation(AnimationConstants.quick) {
                                filingStatus = option.status
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .scaleEffect(isAnimated ? 1.0 : 0.95)
            .opacity(isAnimated ? 1 : 0)
            .animation(AnimationConstants.bouncy.delay(0.2), value: isAnimated)

            // State picker
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("What state do you live in?")
                    .font(Typography.headline)
                    .foregroundStyle(BrandColors.textPrimary)
                    .padding(.horizontal, Spacing.xs)

                statePickerSection
            }
            .padding(.horizontal, Spacing.lg)
            .opacity(isAnimated ? 1 : 0)
            .animation(AnimationConstants.smooth.delay(0.3), value: isAnimated)

            Spacer()
            Spacer()
        }
        .onAppear { isAnimated = true }
        .onDisappear { isAnimated = false }
    }

    private var statePickerSection: some View {
        VStack(spacing: Spacing.sm) {
            // Search field
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(BrandColors.textTertiary)
                    .font(.system(size: 14))

                TextField("Search state...", text: $searchText)
                    .font(Typography.body)
                    .textInputAutocapitalization(.words)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(BrandColors.textTertiary)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(Spacing.md)
            .background(BrandColors.tertiaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))

            // Scrollable state list
            ScrollView {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(filteredStates, id: \.code) { state in
                        Button {
                            withAnimation(AnimationConstants.quick) {
                                stateCode = state.code
                            }
                        } label: {
                            HStack {
                                Text(state.name)
                                    .font(Typography.body)
                                    .foregroundStyle(BrandColors.textPrimary)

                                Spacer()

                                if stateCode == state.code {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(BrandColors.primary)
                                        .font(.system(size: 18))
                                }

                                Text(state.code)
                                    .font(Typography.caption)
                                    .foregroundStyle(BrandColors.textTertiary)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                stateCode == state.code
                                    ? BrandColors.primary.opacity(0.06)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusSm))
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }

    private var filteredStates: [USStateInfo] {
        if searchText.isEmpty { return Self.usStates }
        let query = searchText.lowercased()
        return Self.usStates.filter {
            $0.name.lowercased().contains(query) || $0.code.lowercased().contains(query)
        }
    }
}

// MARK: - Filing Status Selection Card

private struct FilingStatusCard: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentColor : accentColor.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? .white : accentColor)
                }

                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.sm)
            .background(isSelected ? accentColor.opacity(0.08) : BrandColors.tertiaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                    .stroke(isSelected ? accentColor : .clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - US States Data (shared)

struct USStateInfo {
    let code: String
    let name: String
}

extension TaxProfileView {
    static let usStates: [USStateInfo] = [
        USStateInfo(code: "AL", name: "Alabama"), USStateInfo(code: "AK", name: "Alaska"),
        USStateInfo(code: "AZ", name: "Arizona"), USStateInfo(code: "AR", name: "Arkansas"),
        USStateInfo(code: "CA", name: "California"), USStateInfo(code: "CO", name: "Colorado"),
        USStateInfo(code: "CT", name: "Connecticut"), USStateInfo(code: "DE", name: "Delaware"),
        USStateInfo(code: "DC", name: "District of Columbia"), USStateInfo(code: "FL", name: "Florida"),
        USStateInfo(code: "GA", name: "Georgia"), USStateInfo(code: "HI", name: "Hawaii"),
        USStateInfo(code: "ID", name: "Idaho"), USStateInfo(code: "IL", name: "Illinois"),
        USStateInfo(code: "IN", name: "Indiana"), USStateInfo(code: "IA", name: "Iowa"),
        USStateInfo(code: "KS", name: "Kansas"), USStateInfo(code: "KY", name: "Kentucky"),
        USStateInfo(code: "LA", name: "Louisiana"), USStateInfo(code: "ME", name: "Maine"),
        USStateInfo(code: "MD", name: "Maryland"), USStateInfo(code: "MA", name: "Massachusetts"),
        USStateInfo(code: "MI", name: "Michigan"), USStateInfo(code: "MN", name: "Minnesota"),
        USStateInfo(code: "MS", name: "Mississippi"), USStateInfo(code: "MO", name: "Missouri"),
        USStateInfo(code: "MT", name: "Montana"), USStateInfo(code: "NE", name: "Nebraska"),
        USStateInfo(code: "NV", name: "Nevada"), USStateInfo(code: "NH", name: "New Hampshire"),
        USStateInfo(code: "NJ", name: "New Jersey"), USStateInfo(code: "NM", name: "New Mexico"),
        USStateInfo(code: "NY", name: "New York"), USStateInfo(code: "NC", name: "North Carolina"),
        USStateInfo(code: "ND", name: "North Dakota"), USStateInfo(code: "OH", name: "Ohio"),
        USStateInfo(code: "OK", name: "Oklahoma"), USStateInfo(code: "OR", name: "Oregon"),
        USStateInfo(code: "PA", name: "Pennsylvania"), USStateInfo(code: "RI", name: "Rhode Island"),
        USStateInfo(code: "SC", name: "South Carolina"), USStateInfo(code: "SD", name: "South Dakota"),
        USStateInfo(code: "TN", name: "Tennessee"), USStateInfo(code: "TX", name: "Texas"),
        USStateInfo(code: "UT", name: "Utah"), USStateInfo(code: "VT", name: "Vermont"),
        USStateInfo(code: "VA", name: "Virginia"), USStateInfo(code: "WA", name: "Washington"),
        USStateInfo(code: "WV", name: "West Virginia"), USStateInfo(code: "WI", name: "Wisconsin"),
        USStateInfo(code: "WY", name: "Wyoming"),
    ]
}
