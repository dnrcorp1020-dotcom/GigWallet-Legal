import SwiftData
import Foundation

@Model
final class MileageTrip {
    var id: UUID = UUID()
    var miles: Double = 0
    var purpose: String = ""
    var startLocation: String = ""
    var endLocation: String = ""
    var tripDate: Date = Date.now
    var platformRawValue: String = GigPlatformType.other.rawValue
    var deductionAmount: Double = 0
    var taxYear: Int = 2026
    var quarterRawValue: String = TaxQuarter.q1.rawValue
    /// IRS distinguishes business miles (deductible) from commute miles (NOT deductible).
    /// Commute = home → first pickup. Business = between pickups/deliveries.
    var isBusinessMiles: Bool = true
    var createdAt: Date = Date.now

    init(
        miles: Double,
        purpose: String = "",
        startLocation: String = "",
        endLocation: String = "",
        tripDate: Date = .now,
        platform: GigPlatformType = .other,
        isBusinessMiles: Bool = true
    ) {
        self.id = UUID()
        self.miles = miles
        self.purpose = purpose
        self.startLocation = startLocation
        self.endLocation = endLocation
        self.tripDate = tripDate
        self.platformRawValue = platform.rawValue
        self.isBusinessMiles = isBusinessMiles
        self.deductionAmount = isBusinessMiles ? miles * TaxEngine.TaxConstants.mileageRate : 0
        self.taxYear = tripDate.taxYear
        self.quarterRawValue = tripDate.taxQuarter.rawValue
        self.createdAt = .now
    }

    var platform: GigPlatformType {
        get { GigPlatformType(rawValue: platformRawValue) ?? .other }
        set { platformRawValue = newValue.rawValue }
    }

    var quarter: TaxQuarter {
        get { TaxQuarter(rawValue: quarterRawValue) ?? .q1 }
        set { quarterRawValue = newValue.rawValue }
    }
}
