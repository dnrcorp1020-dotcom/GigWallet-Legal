import SwiftUI

struct PlatformSelectionView: View {
    @Binding var selectedPlatforms: Set<GigPlatformType>

    private let columns = [
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
        GridItem(.flexible(), spacing: Spacing.md),
    ]

    /// Platforms organized by category for easier scanning
    private let categories: [(title: String, platforms: [GigPlatformType])] = [
        ("Rideshare", [.uber, .lyft]),
        ("Delivery", [.doordash, .ubereats, .grubhub, .instacart, .amazonFlex, .shipt]),
        ("Freelance & Other", [.upwork, .fiverr, .taskrabbit, .etsy, .airbnb]),
    ]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
                .frame(height: Spacing.lg)

            VStack(spacing: Spacing.sm) {
                Text("Which platforms\ndo you use?")
                    .font(Typography.largeTitle)
                    .multilineTextAlignment(.center)

                Text("Select all that apply. You can add more later.")
                    .font(Typography.body)
                    .foregroundStyle(BrandColors.textSecondary)
            }

            ScrollView {
                VStack(spacing: Spacing.xl) {
                    ForEach(categories, id: \.title) { category in
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text(category.title)
                                .font(Typography.caption)
                                .foregroundStyle(BrandColors.textTertiary)
                                .textCase(.uppercase)
                                .padding(.horizontal, Spacing.xs)

                            LazyVGrid(columns: columns, spacing: Spacing.md) {
                                ForEach(category.platforms) { platform in
                                    PlatformSelectCard(
                                        platform: platform,
                                        isSelected: selectedPlatforms.contains(platform)
                                    ) {
                                        withAnimation(AnimationConstants.quick) {
                                            if selectedPlatforms.contains(platform) {
                                                selectedPlatforms.remove(platform)
                                            } else {
                                                selectedPlatforms.insert(platform)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }

            if !selectedPlatforms.isEmpty {
                Text("\(String(selectedPlatforms.count)) platform\(selectedPlatforms.count == 1 ? "" : "s") selected")
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.primary)
                    .transition(.opacity)
            }

            Spacer()
                .frame(height: Spacing.huge)
        }
    }
}

struct PlatformSelectCard: View {
    let platform: GigPlatformType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(isSelected ? platform.brandColor : platform.brandColor.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: platform.sfSymbol)
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? .white : platform.brandColor)
                }

                Text(platform.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(BrandColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(isSelected ? platform.brandColor.opacity(0.08) : BrandColors.tertiaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd)
                    .stroke(isSelected ? platform.brandColor : .clear, lineWidth: 2)
            )
        }
    }
}
