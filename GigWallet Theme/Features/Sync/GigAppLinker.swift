import SwiftUI
import UIKit

/// Manages deep linking into gig platform apps and OAuth connections
///
/// Connection strategies by platform:
/// 1. **Deep Link** — Opens the platform's earnings page directly (Uber, DoorDash, Lyft)
/// 2. **OAuth API** — Full API integration with OAuth (Etsy, Upwork, Fiverr)
/// 3. **Bank Sync** — Detect deposits via Plaid (all platforms)
/// 4. **Manual Entry** — User enters amounts (universal fallback)
///
/// Deep linking lets users quickly verify their earnings by opening their gig app
/// directly to the earnings/payment section, then returning to GigWallet.
@Observable
final class GigAppLinker: @unchecked Sendable {
    static let shared = GigAppLinker()

    struct PlatformLinkInfo: Identifiable {
        let id = UUID()
        let platform: GigPlatformType
        let appScheme: String?              // URL scheme to open the app
        let earningsDeepLink: String?       // Deep link to earnings page
        let webEarningsURL: String?         // Fallback web URL for earnings
        let oauthAvailable: Bool            // Whether OAuth API integration is available
        let appStoreId: String?             // For "Install app" fallback
        let connectionMethods: [ConnectionMethod]
    }

    enum ConnectionMethod: String, CaseIterable, Identifiable {
        case argyleLink = "Connect Platform"
        case deepLink = "Open App"
        case oauthAPI = "Connect API"
        case bankSync = "Bank Sync"
        case manual = "Manual Entry"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .argyleLink: return "arrow.triangle.2.circlepath.circle.fill"
            case .deepLink: return "arrow.up.forward.app.fill"
            case .oauthAPI: return "link.circle.fill"
            case .bankSync: return "building.columns.fill"
            case .manual: return "pencil.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .argyleLink: return "Trip-level data with fees, tips & mileage"
            case .deepLink: return "Opens the app to your earnings page"
            case .oauthAPI: return "Automatic sync via official API"
            case .bankSync: return "Detects deposits from your bank"
            case .manual: return "Enter your earnings manually"
            }
        }

        var badgeText: String? {
            switch self {
            case .argyleLink: return "BEST"
            case .oauthAPI: return nil
            case .bankSync: return "AUTO"
            default: return nil
            }
        }
    }

    // Platform deep link configurations
    private(set) var platformLinks: [GigPlatformType: PlatformLinkInfo] = [:]

    init() {
        configurePlatformLinks()
    }

    private func configurePlatformLinks() {
        platformLinks = [
            .uber: PlatformLinkInfo(
                platform: .uber,
                appScheme: "uber://",
                earningsDeepLink: "uber://earnings",
                webEarningsURL: "https://drivers.uber.com/p3/payments/statements",
                oauthAvailable: false,
                appStoreId: "368677368",
                connectionMethods: [.argyleLink, .bankSync, .deepLink, .manual]
            ),
            .lyft: PlatformLinkInfo(
                platform: .lyft,
                appScheme: "lyft://",
                earningsDeepLink: "lyft://earnings",
                webEarningsURL: "https://www.lyft.com/driver/earnings",
                oauthAvailable: false,
                appStoreId: "529379082",
                connectionMethods: [.argyleLink, .bankSync, .deepLink, .manual]
            ),
            .doordash: PlatformLinkInfo(
                platform: .doordash,
                appScheme: "doordashdx://",
                earningsDeepLink: "doordashdx://earnings",
                webEarningsURL: "https://dasher.doordash.com/earnings",
                oauthAvailable: false,
                appStoreId: "1168070758",
                connectionMethods: [.argyleLink, .bankSync, .deepLink, .manual]
            ),
            .instacart: PlatformLinkInfo(
                platform: .instacart,
                appScheme: "instacart-shopper://",
                earningsDeepLink: nil,
                webEarningsURL: "https://shoppers.instacart.com/earnings",
                oauthAvailable: false,
                appStoreId: "1114758679",
                connectionMethods: [.argyleLink, .bankSync, .manual]
            ),
            .etsy: PlatformLinkInfo(
                platform: .etsy,
                appScheme: "etsy://",
                earningsDeepLink: nil,
                webEarningsURL: "https://www.etsy.com/your/shops/me/payment-account",
                oauthAvailable: true,
                appStoreId: "477128284",
                connectionMethods: [.argyleLink, .oauthAPI, .bankSync, .manual]
            ),
            .upwork: PlatformLinkInfo(
                platform: .upwork,
                appScheme: nil,
                earningsDeepLink: nil,
                webEarningsURL: "https://www.upwork.com/nx/payments/reports/transaction-history",
                oauthAvailable: true,
                appStoreId: "1500528070",
                connectionMethods: [.argyleLink, .oauthAPI, .bankSync, .manual]
            ),
            .fiverr: PlatformLinkInfo(
                platform: .fiverr,
                appScheme: nil,
                earningsDeepLink: nil,
                webEarningsURL: "https://www.fiverr.com/users/earnings",
                oauthAvailable: true,
                appStoreId: "1481480545",
                connectionMethods: [.argyleLink, .oauthAPI, .bankSync, .manual]
            ),
            .airbnb: PlatformLinkInfo(
                platform: .airbnb,
                appScheme: "airbnb://",
                earningsDeepLink: nil,
                webEarningsURL: "https://www.airbnb.com/progress/earnings",
                oauthAvailable: false,
                appStoreId: "401626263",
                connectionMethods: [.argyleLink, .bankSync, .deepLink, .manual]
            ),
            .grubhub: PlatformLinkInfo(
                platform: .grubhub,
                appScheme: nil,
                earningsDeepLink: nil,
                webEarningsURL: nil,
                oauthAvailable: false,
                appStoreId: "627272031",
                connectionMethods: [.argyleLink, .bankSync, .manual]
            ),
            .amazonFlex: PlatformLinkInfo(
                platform: .amazonFlex,
                appScheme: nil,
                earningsDeepLink: nil,
                webEarningsURL: "https://flex.amazon.com/earnings",
                oauthAvailable: false,
                appStoreId: "1454725674",
                connectionMethods: [.argyleLink, .bankSync, .manual]
            ),
            .shipt: PlatformLinkInfo(
                platform: .shipt,
                appScheme: nil,
                earningsDeepLink: nil,
                webEarningsURL: nil,
                oauthAvailable: false,
                appStoreId: "1222498749",
                connectionMethods: [.argyleLink, .bankSync, .manual]
            ),
            .taskrabbit: PlatformLinkInfo(
                platform: .taskrabbit,
                appScheme: nil,
                earningsDeepLink: nil,
                webEarningsURL: "https://www.taskrabbit.com/dashboard",
                oauthAvailable: false,
                appStoreId: "374165361",
                connectionMethods: [.argyleLink, .bankSync, .manual]
            ),
        ]
    }

    /// Check if a gig app is installed on the device
    func isAppInstalled(_ platform: GigPlatformType) -> Bool {
        guard let linkInfo = platformLinks[platform],
              let scheme = linkInfo.appScheme,
              let url = URL(string: scheme) else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Open the gig app to its earnings page
    func openEarningsPage(_ platform: GigPlatformType) {
        guard let linkInfo = platformLinks[platform] else { return }

        // Try deep link first
        if let deepLink = linkInfo.earningsDeepLink,
           let url = URL(string: deepLink),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        // Try app scheme
        if let scheme = linkInfo.appScheme,
           let url = URL(string: scheme),
           UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }

        // Fallback to web URL
        if let webURL = linkInfo.webEarningsURL,
           let url = URL(string: webURL) {
            UIApplication.shared.open(url)
        }
    }

    /// Get available connection methods for a platform
    func connectionMethods(for platform: GigPlatformType) -> [ConnectionMethod] {
        platformLinks[platform]?.connectionMethods ?? [.bankSync, .manual]
    }
}
