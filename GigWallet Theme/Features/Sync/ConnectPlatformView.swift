import SwiftUI
import SwiftData

/// View for connecting a specific gig platform
/// Shows available connection methods: deep link, OAuth, bank sync, manual
struct ConnectPlatformView: View {
    let platform: GigPlatformType
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @State private var linker = GigAppLinker.shared
    @State private var showingBankConnection = false
    @State private var showingArgyleConnection = false
    @State private var showingOAuthInfo = false

    private var profile: UserProfile? { profiles.first }

    private var linkInfo: GigAppLinker.PlatformLinkInfo? {
        linker.platformLinks[platform]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xxl) {
                    // Platform header
                    VStack(spacing: Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(platform.brandColor.opacity(0.12))
                                .frame(width: 80, height: 80)

                            Image(systemName: platform.sfSymbol)
                                .font(.system(size: 36))
                                .foregroundStyle(platform.brandColor)
                        }

                        Text("Connect \(platform.displayName)")
                            .font(Typography.title)
                    }
                    .padding(.top, Spacing.lg)

                    // Connection methods
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Choose how to track \(platform.displayName) earnings:")
                            .font(Typography.subheadline)
                            .foregroundStyle(BrandColors.textSecondary)
                            .padding(.horizontal, Spacing.lg)

                        let methods = linker.connectionMethods(for: platform)

                        ForEach(methods) { method in
                            ConnectionMethodCard(
                                method: method,
                                platform: platform,
                                isAppInstalled: method == .deepLink ? linker.isAppInstalled(platform) : true,
                                isPremium: (method == .bankSync || method == .argyleLink) && profile?.isPremium != true
                            ) {
                                handleMethod(method)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Info footer
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 24))
                            .foregroundStyle(BrandColors.textTertiary)

                        Text("Your data stays on your device. We never share your information with third parties.")
                            .font(Typography.caption)
                            .foregroundStyle(BrandColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Spacing.xxl)
                    .padding(.top, Spacing.lg)
                }
            }
            .background(BrandColors.groupedBackground)
            .gwNavigationTitle("", accent: platform.displayName, icon: platform.sfSymbol)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingBankConnection) {
                BankConnectionView()
            }
            .sheet(isPresented: $showingArgyleConnection) {
                ArgyleConnectionView()
            }
            .alert("API Connection", isPresented: $showingOAuthInfo) {
                Button("OK") { }
            } message: {
                Text("\(platform.displayName) API integration requires an OAuth developer account. Use Bank Sync or Manual Entry for now.")
            }
        }
    }

    private func handleMethod(_ method: GigAppLinker.ConnectionMethod) {
        switch method {
        case .argyleLink:
            // Argyle Link is a premium feature
            if profile?.isPremium == true {
                showingArgyleConnection = true
            } else {
                appState.showingPaywall = true
            }
        case .deepLink:
            linker.openEarningsPage(platform)
        case .oauthAPI:
            showingOAuthInfo = true
        case .bankSync:
            // Bank Sync is a premium feature
            if profile?.isPremium == true {
                showingBankConnection = true
            } else {
                appState.showingPaywall = true
            }
        case .manual:
            dismiss()
        }
    }
}

struct ConnectionMethodCard: View {
    let method: GigAppLinker.ConnectionMethod
    let platform: GigPlatformType
    let isAppInstalled: Bool
    var isPremium: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: method.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(platform.brandColor)
                    .frame(width: 44, height: 44)
                    .background(platform.brandColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.sm) {
                        Text(method.rawValue)
                            .font(Typography.headline)
                            .foregroundStyle(BrandColors.textPrimary)

                        if let badge = method.badgeText {
                            GWBadge(badge, color: BrandColors.primary)
                        }

                        if isPremium {
                            GWProBadge()
                        }

                        if method == .deepLink && !isAppInstalled {
                            GWBadge("Not Installed", color: BrandColors.textTertiary)
                        }
                    }

                    Text(method.description)
                        .font(Typography.caption)
                        .foregroundStyle(BrandColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BrandColors.textTertiary)
            }
            .padding(Spacing.lg)
            .background(BrandColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLg))
        }
        .disabled(method == .deepLink && !isAppInstalled)
        .opacity(method == .deepLink && !isAppInstalled ? 0.5 : 1.0)
    }
}
