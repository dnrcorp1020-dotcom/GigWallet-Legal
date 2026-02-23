import Foundation

/// Smart expense detection engine — automatically categorizes and identifies
/// deductible expenses from bank transactions and user descriptions.
///
/// Strategies:
/// 1. Bank transaction matching (from Plaid sync)
/// 2. Vendor name recognition (pattern matching)
/// 3. Category auto-suggestion based on keywords
/// 4. IRS deduction rules engine
@MainActor
@Observable
final class ExpenseDetectionService {
    static let shared = ExpenseDetectionService()

    // MARK: - Common Gig Worker Expense Patterns

    /// Known deductible vendors for gig workers, mapped to categories
    static let vendorPatterns: [(pattern: String, vendor: String, category: ExpenseCategory, deductionPct: Double)] = [
        // Gas & Fuel
        ("shell", "Shell", .gas, 100),
        ("chevron", "Chevron", .gas, 100),
        ("exxon", "ExxonMobil", .gas, 100),
        ("bp", "BP", .gas, 100),
        ("costco gas", "Costco Gas", .gas, 100),
        ("sam'?s.+fuel", "Sam's Club Fuel", .gas, 100),
        ("circle k", "Circle K", .gas, 100),
        ("marathon", "Marathon", .gas, 100),
        ("7.?eleven.*fuel", "7-Eleven", .gas, 100),
        ("wawa", "Wawa", .gas, 100),
        ("pilot", "Pilot", .gas, 100),
        ("loves", "Love's", .gas, 100),

        // Vehicle
        ("jiffy lube", "Jiffy Lube", .vehicleMaintenance, 100),
        ("autozone", "AutoZone", .vehicleMaintenance, 100),
        ("o'?reilly", "O'Reilly Auto Parts", .vehicleMaintenance, 100),
        ("advance auto", "Advance Auto Parts", .vehicleMaintenance, 100),
        ("pep boys", "Pep Boys", .vehicleMaintenance, 100),
        ("firestone", "Firestone", .vehicleMaintenance, 100),
        ("goodyear", "Goodyear", .vehicleMaintenance, 100),
        ("valvoline", "Valvoline", .vehicleMaintenance, 100),
        ("car wash", "Car Wash", .vehicleMaintenance, 100),

        // Phone & Internet
        ("t.?mobile", "T-Mobile", .phoneAndInternet, 50),
        ("at.?t", "AT&T", .phoneAndInternet, 50),
        ("verizon", "Verizon", .phoneAndInternet, 50),
        ("xfinity", "Xfinity", .phoneAndInternet, 25),
        ("comcast", "Comcast", .phoneAndInternet, 25),
        ("spectrum", "Spectrum", .phoneAndInternet, 25),
        ("google fi", "Google Fi", .phoneAndInternet, 50),
        ("mint mobile", "Mint Mobile", .phoneAndInternet, 50),

        // Insurance
        ("geico", "GEICO", .insurance, 50),
        ("state farm", "State Farm", .insurance, 50),
        ("progressive", "Progressive", .insurance, 50),
        ("allstate", "Allstate", .insurance, 50),
        ("liberty mutual", "Liberty Mutual", .insurance, 50),

        // Software & Apps
        ("spotify", "Spotify", .software, 0),
        ("apple.com/bill", "Apple (Subscription)", .software, 100),
        ("google.?storage", "Google Storage", .software, 50),
        ("dropbox", "Dropbox", .software, 50),
        ("quickbooks", "QuickBooks", .software, 100),
        ("turbotax", "TurboTax", .software, 100),
        ("adobe", "Adobe", .software, 50),
        ("canva", "Canva", .software, 50),
        ("microsoft", "Microsoft 365", .software, 50),
        ("zoom", "Zoom", .software, 50),

        // Meals (business)
        ("mcdonald", "McDonald's", .meals, 50),
        ("starbucks", "Starbucks", .meals, 50),
        ("chipotle", "Chipotle", .meals, 50),
        ("subway", "Subway", .meals, 50),
        ("chick.?fil", "Chick-fil-A", .meals, 50),
        ("dunkin", "Dunkin'", .meals, 50),

        // Parking
        ("parkwhiz", "ParkWhiz", .parking, 100),
        ("spothero", "SpotHero", .parking, 100),
        ("parking meter", "Parking Meter", .parking, 100),
        ("park.*lot", "Parking Lot", .parking, 100),
        ("toll", "Toll", .parking, 100),
        ("ezpass", "EZ-Pass", .parking, 100),
        ("fastrak", "FasTrak", .parking, 100),

        // Supplies
        ("amazon", "Amazon", .supplies, 100),
        ("walmart", "Walmart", .supplies, 100),
        ("target", "Target", .supplies, 100),
        ("staples", "Staples", .supplies, 100),
        ("office depot", "Office Depot", .supplies, 100),

        // Professional Services
        ("h.?r.?block", "H&R Block", .professionalServices, 100),
        ("turbotax", "TurboTax", .professionalServices, 100),
        ("legal.?zoom", "LegalZoom", .professionalServices, 100),
    ]

    /// Quick-add expense suggestions based on common gig worker patterns
    struct ExpenseSuggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let category: ExpenseCategory
        let estimatedAmount: Double?
        let deductionPercentage: Double
        let icon: String
    }

    /// Get smart suggestions for common gig expenses
    var quickSuggestions: [ExpenseSuggestion] {
        [
            ExpenseSuggestion(
                title: "Gas Fill-Up",
                subtitle: "Fuel for gig driving",
                category: .gas,
                estimatedAmount: nil,
                deductionPercentage: 100,
                icon: "fuelpump.fill"
            ),
            ExpenseSuggestion(
                title: "Phone Bill",
                subtitle: "Monthly cell service (50% deductible)",
                category: .phoneAndInternet,
                estimatedAmount: nil,
                deductionPercentage: 50,
                icon: "iphone"
            ),
            ExpenseSuggestion(
                title: "Car Wash",
                subtitle: "Vehicle appearance for gig work",
                category: .vehicleMaintenance,
                estimatedAmount: nil,
                deductionPercentage: 100,
                icon: "car.fill"
            ),
            ExpenseSuggestion(
                title: "Log Mileage",
                subtitle: "IRS rate: $0.70/mile",
                category: .mileage,
                estimatedAmount: nil,
                deductionPercentage: 100,
                icon: "road.lanes"
            ),
            ExpenseSuggestion(
                title: "Parking / Tolls",
                subtitle: "100% deductible for gig work",
                category: .parking,
                estimatedAmount: nil,
                deductionPercentage: 100,
                icon: "parkingsign"
            ),
            ExpenseSuggestion(
                title: "Car Insurance",
                subtitle: "Rideshare portion (~50%)",
                category: .insurance,
                estimatedAmount: nil,
                deductionPercentage: 50,
                icon: "shield.fill"
            ),
        ]
    }

    // MARK: - Auto-Detection

    /// Match a bank transaction description to an expense category
    func detectCategory(from description: String) -> (vendor: String, category: ExpenseCategory, deductionPct: Double)? {
        let lowered = description.lowercased()

        for pattern in Self.vendorPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern.pattern, options: .caseInsensitive) {
                let range = NSRange(lowered.startIndex..., in: lowered)
                if regex.firstMatch(in: lowered, range: range) != nil {
                    return (pattern.vendor, pattern.category, pattern.deductionPct)
                }
            }
        }

        return nil
    }

    /// Batch analyze transactions from bank sync
    func analyzeTransactions(_ transactions: [BankTransaction]) -> [DetectedExpense] {
        return transactions.compactMap { tx in
            guard let match = detectCategory(from: tx.name) else { return nil }
            return DetectedExpense(
                transactionId: tx.id,
                vendor: match.vendor,
                category: match.category,
                amount: abs(tx.amount),
                date: tx.date,
                deductionPercentage: match.deductionPct,
                confidence: 0.85,
                originalDescription: tx.name
            )
        }
    }
}

// MARK: - Types

struct BankTransaction: Identifiable {
    let id: String
    let name: String
    let amount: Double
    let date: Date
    let merchantName: String?
}

struct DetectedExpense: Identifiable {
    let id = UUID()
    let transactionId: String
    let vendor: String
    let category: ExpenseCategory
    let amount: Double
    let date: Date
    let deductionPercentage: Double
    let confidence: Double
    let originalDescription: String
}
