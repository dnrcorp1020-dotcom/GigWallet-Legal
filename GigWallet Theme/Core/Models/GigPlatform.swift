import SwiftUI

enum GigPlatformType: String, Codable, CaseIterable, Identifiable {
    case uber = "Uber"
    case lyft = "Lyft"
    case doordash = "DoorDash"
    case instacart = "Instacart"
    case grubhub = "Grubhub"
    case ubereats = "Uber Eats"
    case etsy = "Etsy"
    case airbnb = "Airbnb"
    case taskrabbit = "TaskRabbit"
    case fiverr = "Fiverr"
    case upwork = "Upwork"
    case amazonFlex = "Amazon Flex"
    case shipt = "Shipt"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .uber, .lyft: return "car.fill"
        case .doordash, .grubhub, .ubereats, .instacart: return "bag.fill"
        case .etsy: return "storefront.fill"
        case .airbnb: return "house.fill"
        case .taskrabbit: return "wrench.and.screwdriver.fill"
        case .fiverr, .upwork: return "laptopcomputer"
        case .amazonFlex, .shipt: return "shippingbox.fill"
        case .other: return "briefcase.fill"
        }
    }

    var brandColor: Color {
        switch self {
        case .uber: return BrandColors.uber
        case .lyft: return BrandColors.lyft
        case .doordash: return BrandColors.doordash
        case .instacart: return BrandColors.instacart
        case .grubhub: return BrandColors.grubhub
        case .ubereats: return BrandColors.ubereats
        case .etsy: return BrandColors.etsy
        case .airbnb: return BrandColors.airbnb
        case .taskrabbit: return BrandColors.taskrabbit
        case .fiverr: return BrandColors.fiverr
        case .upwork: return BrandColors.upwork
        case .amazonFlex: return BrandColors.amazonFlex
        case .shipt: return BrandColors.shipt
        case .other: return BrandColors.textSecondary
        }
    }

    var category: PlatformCategory {
        switch self {
        case .uber, .lyft: return .rideshare
        case .doordash, .grubhub, .ubereats, .instacart: return .delivery
        case .etsy: return .marketplace
        case .airbnb: return .rental
        case .taskrabbit: return .services
        case .fiverr, .upwork: return .freelance
        case .amazonFlex, .shipt: return .delivery
        case .other: return .other
        }
    }

    var supportsAutoSync: Bool {
        switch self {
        case .etsy, .upwork, .fiverr: return true
        default: return false
        }
    }

    /// Estimated hours per income entry — used for real hourly rate calculation
    /// Based on industry averages: rideshare/delivery trips avg ~30-45min,
    /// freelance gigs avg ~2-4 hours, rental is passive
    var estimatedHoursPerEntry: Double {
        switch self {
        case .uber, .lyft: return 0.6           // ~35 min per trip
        case .doordash, .grubhub, .ubereats: return 0.5 // ~30 min per delivery
        case .instacart, .shipt: return 0.75     // ~45 min per shop
        case .amazonFlex: return 1.0             // ~1 hr per block
        case .etsy: return 0.0                   // Passive (product-based)
        case .airbnb: return 0.0                 // Passive (rental)
        case .taskrabbit: return 2.0             // ~2 hr per task
        case .fiverr: return 3.0                 // ~3 hr per gig
        case .upwork: return 4.0                 // ~4 hr per contract
        case .other: return 1.0
        }
    }
}

enum PlatformCategory: String, CaseIterable {
    case rideshare = "Rideshare"
    case delivery = "Delivery"
    case marketplace = "Marketplace"
    case rental = "Rental"
    case freelance = "Freelance"
    case services = "Services"
    case other = "Other"
}

enum EntryMethod: String, Codable, CaseIterable {
    case manual = "Manual"
    case bankSync = "Bank Sync"
    case apiSync = "API Sync"
    case emailImport = "Email Import"

    var sfSymbol: String {
        switch self {
        case .manual: return "pencil"
        case .bankSync: return "building.columns"
        case .apiSync: return "arrow.triangle.2.circlepath"
        case .emailImport: return "envelope"
        }
    }
}
