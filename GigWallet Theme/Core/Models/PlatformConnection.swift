import SwiftData
import Foundation

@Model
final class PlatformConnection {
    var id: UUID = UUID()
    var platformRawValue: String = GigPlatformType.other.rawValue
    var connectionStatusRawValue: String = ConnectionStatus.disconnected.rawValue
    var lastSyncDate: Date?
    var accountDisplayName: String = ""
    var totalSyncedEntries: Int = 0
    var createdAt: Date = Date.now

    init(
        platform: GigPlatformType,
        status: ConnectionStatus = .disconnected,
        accountDisplayName: String = ""
    ) {
        self.id = UUID()
        self.platformRawValue = platform.rawValue
        self.connectionStatusRawValue = status.rawValue
        self.accountDisplayName = accountDisplayName
        self.createdAt = .now
    }

    var platform: GigPlatformType {
        get { GigPlatformType(rawValue: platformRawValue) ?? .other }
        set { platformRawValue = newValue.rawValue }
    }

    var connectionStatus: ConnectionStatus {
        get { ConnectionStatus(rawValue: connectionStatusRawValue) ?? .disconnected }
        set { connectionStatusRawValue = newValue.rawValue }
    }
}

enum ConnectionStatus: String, Codable {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case syncing = "Syncing"
    case error = "Error"

    var sfSymbol: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .disconnected: return "xmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .connected: return BrandColors.success
        case .disconnected: return BrandColors.textTertiary
        case .syncing: return BrandColors.primary
        case .error: return BrandColors.destructive
        }
    }
}

import SwiftUI
