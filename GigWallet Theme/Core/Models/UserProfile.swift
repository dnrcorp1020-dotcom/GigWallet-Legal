import SwiftData
import Foundation

@Model
final class UserProfile {
    var id: UUID = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""
    var phoneNumber: String = ""
    var profileImageURL: String = ""
    var authProviderRawValue: String = AuthProvider.anonymous.rawValue
    var authProviderUserId: String = ""
    var filingStatus: FilingStatus = FilingStatus.single
    var stateCode: String = "CA"
    var hasCompletedOnboarding: Bool = false
    var hasCompletedRegistration: Bool = false
    var selectedPlatforms: [String] = []
    var subscriptionTier: SubscriptionTier = SubscriptionTier.free
    var trialStartDate: Date?
    var weeklyEarningsGoal: Double = 0
    var monthlyEarningsGoal: Double = 0
    var notificationsEnabled: Bool = false
    /// Prior year total tax paid — used for safe harbor calculation.
    /// IRS safe harbor: pay 100% of prior year tax (or 110% if AGI > $150K) to avoid penalties.
    var priorYearTax: Double = 0
    /// Home office square footage — used for simplified home office deduction ($5/sq ft, max 300)
    var homeOfficeSquareFeet: Double = 0
    /// Whether user is full-time gig or has a W-2 job on the side.
    /// Affects quarterly tax estimates — side-gig workers may already have W-2 withholding.
    /// Stored as raw string to avoid SwiftData dynamic cast crash on existing NULL rows.
    var gigWorkerTypeRawValue: String = GigWorkerType.fullTime.rawValue
    /// Estimated annual W-2 withholding — if they have a day job, employer already withholds taxes.
    /// This offsets the estimated quarterly tax payment needed for gig income.
    var estimatedW2Withholding: Double = 0
    /// Deduction method chosen by user: standard, itemized, or not sure (defaults to standard).
    /// Stored as raw string for SwiftData compatibility with existing NULL rows.
    var deductionMethodRawValue: String = DeductionMethod.notSure.rawValue
    /// Estimated total itemized deductions (only relevant if deductionMethod == .itemized).
    var estimatedItemizedDeductions: Double = 0
    /// Tax credits the user indicated they may qualify for, stored as raw value strings.
    var selectedTaxCreditsRawValues: [String] = []
    /// Estimated annual W-2 income (gross salary) — used for SS wage base overlap calculation.
    var estimatedW2Income: Double = 0
    /// Additional states where user earns gig income (beyond primary stateCode).
    /// Used for multi-state tax estimation.
    var additionalStates: [String] = []
    /// Number of receipt OCR scans the user has performed.
    /// Free users get 5 lifetime scans, then upgrade to Pro for unlimited.
    var receiptScansUsed: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        firstName: String = "",
        lastName: String = "",
        email: String = "",
        phoneNumber: String = "",
        filingStatus: FilingStatus = .single,
        stateCode: String = "CA",
        authProvider: AuthProvider = .anonymous
    ) {
        self.id = UUID()
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phoneNumber = phoneNumber
        self.profileImageURL = ""
        self.authProviderRawValue = authProvider.rawValue
        self.authProviderUserId = ""
        self.filingStatus = filingStatus
        self.stateCode = stateCode
        self.hasCompletedOnboarding = false
        self.hasCompletedRegistration = false
        self.selectedPlatforms = []
        self.subscriptionTier = .free
        self.createdAt = .now
        self.updatedAt = .now
    }

    var authProvider: AuthProvider {
        get { AuthProvider(rawValue: authProviderRawValue) ?? .anonymous }
        set { authProviderRawValue = newValue.rawValue }
    }

    var gigWorkerType: GigWorkerType {
        get { GigWorkerType(rawValue: gigWorkerTypeRawValue) ?? .fullTime }
        set { gigWorkerTypeRawValue = newValue.rawValue }
    }

    var deductionMethod: DeductionMethod {
        get { DeductionMethod(rawValue: deductionMethodRawValue) ?? .notSure }
        set { deductionMethodRawValue = newValue.rawValue }
    }

    var selectedTaxCredits: Set<TaxCreditType> {
        get { Set(selectedTaxCreditsRawValues.compactMap { TaxCreditType(rawValue: $0) }) }
        set { selectedTaxCreditsRawValues = newValue.map(\.rawValue).sorted() }
    }

    /// Total estimated tax credit value based on selected credits
    var estimatedTotalCredits: Double {
        selectedTaxCredits.reduce(0) { $0 + $1.estimatedValue }
    }

    /// The personal deduction amount to use in tax calculations.
    /// Returns itemized amount if they chose itemized AND it exceeds standard; otherwise standard.
    var effectivePersonalDeduction: Double {
        let standard = TaxEngine.StandardDeductions.amount(for: filingStatus)
        switch deductionMethod {
        case .itemized:
            return max(estimatedItemizedDeductions, standard)  // Use whichever is larger
        case .standard, .notSure:
            return standard
        }
    }

    var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "" : full
    }

    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        let result = "\(f)\(l)"
        return result.isEmpty ? "GW" : result.uppercased()
    }

    var isTrialActive: Bool {
        guard let start = trialStartDate else { return false }
        let trialEnd = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        return Date.now < trialEnd
    }

    /// Premium access is gated ONLY by StoreKit subscription tier.
    /// `isTrialActive` is informational only (for UI display), NOT an access gate.
    /// StoreKit 2 manages trial periods via the subscription itself.
    var isPremium: Bool {
        subscriptionTier == .premium
    }

    var isLoggedIn: Bool {
        authProvider != .anonymous && !authProviderUserId.isEmpty
    }

    // MARK: - Receipt Scan Gating

    /// Maximum free receipt OCR scans before requiring Pro upgrade.
    static let freeReceiptScanLimit = 5

    /// Number of free receipt scans remaining.
    var freeScansRemaining: Int {
        max(Self.freeReceiptScanLimit - receiptScansUsed, 0)
    }

    /// Whether the user can perform a receipt OCR scan.
    /// Premium users always can; free users are limited to `freeReceiptScanLimit`.
    var canScanReceipt: Bool {
        isPremium || receiptScansUsed < Self.freeReceiptScanLimit
    }

    /// Record a successful receipt scan. Call after OCR completes.
    func recordReceiptScan() {
        guard !isPremium else { return }
        receiptScansUsed += 1
        updatedAt = .now
    }
}

enum AuthProvider: String, Codable, CaseIterable, Identifiable {
    case anonymous = "anonymous"
    case apple = "apple"
    case google = "google"
    case email = "email"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anonymous: return "Anonymous"
        case .apple: return "Apple"
        case .google: return "Google"
        case .email: return "Email"
        }
    }
}

enum FilingStatus: String, Codable, CaseIterable, Identifiable {
    case single = "Single"
    case marriedJoint = "Married Filing Jointly"
    case marriedSeparate = "Married Filing Separately"
    case headOfHousehold = "Head of Household"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .single: return "Single"
        case .marriedJoint: return "Joint"
        case .marriedSeparate: return "Separate"
        case .headOfHousehold: return "HoH"
        }
    }
}

enum SubscriptionTier: String, Codable {
    case free
    case premium
}

/// Distinguishes full-time gig workers from those who gig on the side.
/// This fundamentally changes how we calculate quarterly estimated tax payments:
/// - Full-time: No W-2 withholding → must pay full estimated quarterly tax
/// - Side gig: W-2 employer already withholds income tax → quarterly estimates reduced
enum GigWorkerType: String, Codable, CaseIterable, Identifiable {
    case fullTime = "Full-Time Gig Worker"
    case sideGig = "Side Gig (Also Have W-2 Job)"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .fullTime: return "Full-Time"
        case .sideGig: return "Side Gig"
        }
    }

    var description: String {
        switch self {
        case .fullTime: return "Gig work is my primary income source"
        case .sideGig: return "I also have a W-2 job with tax withholding"
        }
    }
}

/// Personal tax return deduction method.
/// Note: Schedule C business deductions (mileage, supplies, phone) are separate from this.
/// This is for the personal 1040 deduction (standard vs itemized).
enum DeductionMethod: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard Deduction"
    case itemized = "Itemized Deductions"
    case notSure = "Not Sure Yet"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .standard: return "Standard"
        case .itemized: return "Itemized"
        case .notSure: return "Not Sure"
        }
    }
}

/// Tax credits that reduce tax liability dollar-for-dollar.
/// These are separate from deductions and applied after tax is calculated.
enum TaxCreditType: String, Codable, CaseIterable, Identifiable {
    case eitc = "Earned Income Tax Credit (EITC)"
    case childTax = "Child Tax Credit"
    case childCare = "Child & Dependent Care Credit"
    case education = "Education Credits (AOC/LLC)"
    case retirement = "Retirement Savings Credit"
    case healthPremium = "Health Insurance Premium Credit"

    var id: String { rawValue }

    var estimatedValue: Double {
        switch self {
        case .eitc: return 2500
        case .childTax: return 2000
        case .childCare: return 1200
        case .education: return 2000
        case .retirement: return 1000
        case .healthPremium: return 1800
        }
    }

    var icon: String {
        switch self {
        case .eitc: return "dollarsign.circle.fill"
        case .childTax: return "figure.and.child.holdinghands"
        case .childCare: return "building.fill"
        case .education: return "graduationcap.fill"
        case .retirement: return "chart.line.uptrend.xyaxis"
        case .healthPremium: return "heart.text.square.fill"
        }
    }

    var shortDescription: String {
        switch self {
        case .eitc: return "For low-to-moderate income workers"
        case .childTax: return "Up to $2,000 per qualifying child"
        case .childCare: return "If you pay for daycare/childcare"
        case .education: return "For tuition and education expenses"
        case .retirement: return "If you contributed to an IRA/401k"
        case .healthPremium: return "If you bought marketplace insurance"
        }
    }
}
