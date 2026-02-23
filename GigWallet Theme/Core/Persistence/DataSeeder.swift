import SwiftData
import Foundation

enum DataSeeder {
    @MainActor
    static func seedPreviewData(context: ModelContext) {
        // User Profile — reuse existing or create new (avoids duplicate)
        let existingProfiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let profile: UserProfile
        if let existing = existingProfiles.first {
            profile = existing
        } else {
            profile = UserProfile(
                firstName: "Alex",
                lastName: "Rivera",
                email: "alex@email.com",
                filingStatus: FilingStatus.single,
                stateCode: "CA"
            )
            context.insert(profile)
        }
        profile.hasCompletedOnboarding = true
        if profile.selectedPlatforms.isEmpty {
            profile.selectedPlatforms = [
                GigPlatformType.uber.rawValue,
                GigPlatformType.doordash.rawValue,
                GigPlatformType.instacart.rawValue
            ]
        }

        // Platform Connections
        let uberConnection = PlatformConnection(platform: .uber, status: .connected, accountDisplayName: "alex.r@uber")
        let doordashConnection = PlatformConnection(platform: .doordash, status: .connected, accountDisplayName: "Alex R.")
        let instacartConnection = PlatformConnection(platform: .instacart, status: .connected, accountDisplayName: "alex_rivera")
        uberConnection.lastSyncDate = .now
        doordashConnection.lastSyncDate = .now
        instacartConnection.lastSyncDate = Date.daysAgo(1)

        context.insert(uberConnection)
        context.insert(doordashConnection)
        context.insert(instacartConnection)

        // Income entries - last 30 days, realistic gig patterns
        let incomeData: [(Double, Double, Double, GigPlatformType, Int)] = [
            // (amount, tips, fees, platform, daysAgo)
            (45.50, 12.00, 5.75, .uber, 0),
            (32.00, 8.50, 4.25, .doordash, 0),
            (67.25, 0, 8.50, .instacart, 1),
            (89.00, 22.00, 11.25, .uber, 1),
            (28.50, 6.00, 3.50, .doordash, 2),
            (52.75, 15.00, 6.75, .uber, 2),
            (41.00, 9.50, 5.00, .doordash, 3),
            (73.50, 0, 9.25, .instacart, 3),
            (95.25, 28.00, 12.00, .uber, 4),
            (38.00, 7.50, 4.75, .doordash, 4),
            (61.50, 18.00, 7.75, .uber, 5),
            (44.25, 10.00, 5.50, .doordash, 6),
            (82.00, 0, 10.25, .instacart, 6),
            (56.75, 14.00, 7.00, .uber, 7),
            (33.50, 8.00, 4.25, .doordash, 7),
            (71.00, 20.00, 9.00, .uber, 8),
            (47.25, 11.00, 6.00, .doordash, 9),
            (88.50, 0, 11.00, .instacart, 10),
            (62.00, 16.50, 7.75, .uber, 11),
            (39.75, 9.00, 5.00, .doordash, 12),
            (54.50, 13.00, 6.75, .uber, 13),
            (77.25, 0, 9.75, .instacart, 14),
            (43.00, 10.50, 5.50, .doordash, 15),
            (96.50, 25.00, 12.25, .uber, 16),
            (35.25, 7.00, 4.50, .doordash, 17),
            (68.00, 19.00, 8.50, .uber, 18),
            (51.50, 12.00, 6.50, .doordash, 20),
            (84.75, 0, 10.75, .instacart, 22),
            (59.25, 15.50, 7.50, .uber, 24),
            (42.00, 9.50, 5.25, .doordash, 26),
        ]

        for (amount, tips, fees, platform, daysAgo) in incomeData {
            let entry = IncomeEntry(
                amount: amount,
                tips: tips,
                platformFees: fees,
                platform: platform,
                entryMethod: .bankSync,
                entryDate: Date.daysAgo(daysAgo)
            )
            context.insert(entry)
        }

        // Expense entries
        let expenseData: [(Double, ExpenseCategory, String, String, Int)] = [
            (65.00, .gas, "Shell", "Weekly fill-up", 1),
            (12.99, .phoneAndInternet, "Verizon", "Phone plan (50% business)", 3),
            (8.50, .parking, "ParkMobile", "Downtown parking", 4),
            (45.00, .vehicleMaintenance, "Jiffy Lube", "Oil change", 7),
            (29.99, .software, "GigWallet", "Gig tracking app annual", 10),
            (15.75, .meals, "Subway", "Lunch during shift", 11),
            (58.00, .gas, "Chevron", "Weekly fill-up", 8),
            (125.00, .insurance, "GEICO", "Monthly rideshare coverage", 15),
            (9.99, .software, "MileTracker", "Mileage tracking app", 15),
            (22.50, .supplies, "Amazon", "Phone mount + charger", 18),
            (62.00, .gas, "Shell", "Weekly fill-up", 15),
            (18.00, .parking, "SpotHero", "Airport parking", 20),
            (55.00, .gas, "Costco", "Weekly fill-up", 22),
            (35.00, .meals, "Chipotle", "Dinner during evening shift", 25),
            (199.00, .equipment, "Best Buy", "Dash cam", 28),
        ]

        for (amount, category, vendor, description, daysAgo) in expenseData {
            let deductionPct: Double = (category == .phoneAndInternet || category == .meals) ? 50 : 100
            let expense = ExpenseEntry(
                amount: amount,
                category: category,
                vendor: vendor,
                description: description,
                expenseDate: Date.daysAgo(daysAgo),
                deductionPercentage: deductionPct
            )
            context.insert(expense)
        }

        // Mileage trips
        let mileageData: [(Double, String, Int, GigPlatformType)] = [
            (45.2, "Airport run + 3 rides", 0, .uber),
            (32.8, "Evening delivery shift", 1, .doordash),
            (28.5, "Instacart batch run", 2, .instacart),
            (52.1, "Morning rush rides", 3, .uber),
            (18.3, "Quick delivery run", 4, .doordash),
            (41.7, "Full day driving", 5, .uber),
            (25.9, "Grocery delivery", 6, .instacart),
            (38.4, "Evening rides", 7, .uber),
            (22.6, "Lunch delivery shift", 8, .doordash),
            (47.3, "Weekend grind", 9, .uber),
        ]

        for (miles, purpose, daysAgo, platform) in mileageData {
            let trip = MileageTrip(
                miles: miles,
                purpose: purpose,
                tripDate: Date.daysAgo(daysAgo),
                platform: platform
            )
            context.insert(trip)
        }
    }

    // MARK: - Rich Demo Data (DEBUG only)

    #if DEBUG
    /// Seeds 4 months of rich, realistic data that exercises every AI engine,
    /// dashboard card, and feature in the app. Wrapped in #if DEBUG so it's
    /// automatically stripped from release builds.
    @MainActor
    static func seedDemoData(context: ModelContext) {
        // ── Clear existing data to start fresh ──
        try? context.delete(model: IncomeEntry.self)
        try? context.delete(model: ExpenseEntry.self)
        try? context.delete(model: MileageTrip.self)
        try? context.delete(model: TaxPayment.self)
        try? context.delete(model: TaxVaultEntry.self)
        try? context.delete(model: PlatformConnection.self)
        try? context.delete(model: BudgetItem.self)

        // ── Profile ──
        let existingProfiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let profile: UserProfile
        if let existing = existingProfiles.first {
            profile = existing
        } else {
            profile = UserProfile(
                firstName: "Sarah",
                lastName: "Chen",
                email: "sarah.chen@email.com",
                filingStatus: FilingStatus.single,
                stateCode: "CA"
            )
            context.insert(profile)
        }
        profile.firstName = "Sarah"
        profile.lastName = "Chen"
        profile.email = "sarah.chen@email.com"
        profile.filingStatus = FilingStatus.single
        profile.stateCode = "CA"
        profile.hasCompletedOnboarding = true
        profile.hasCompletedRegistration = true
        profile.subscriptionTier = .premium
        profile.weeklyEarningsGoal = 1000
        profile.monthlyEarningsGoal = 4000
        profile.notificationsEnabled = true
        profile.priorYearTax = 8500
        profile.homeOfficeSquareFeet = 120
        profile.selectedPlatforms = [
            GigPlatformType.uber.rawValue,
            GigPlatformType.doordash.rawValue,
            GigPlatformType.instacart.rawValue,
            GigPlatformType.lyft.rawValue,
        ]

        // ── Platform Connections ──
        let connections: [(GigPlatformType, String)] = [
            (.uber, "sarah.c@uber"),
            (.doordash, "Sarah C."),
            (.instacart, "sarahchen"),
            (.lyft, "sarah_c@lyft"),
        ]
        for (platform, displayName) in connections {
            let conn = PlatformConnection(platform: platform, status: .connected, accountDisplayName: displayName)
            conn.lastSyncDate = Date.daysAgo(Int.random(in: 0...2))
            context.insert(conn)
        }

        // ── Income: 4 months of realistic multi-platform data ──
        // Uber: rideshare, higher amounts, good tips
        // DoorDash: delivery, moderate amounts, variable tips
        // Instacart: grocery delivery, no tips in base (tips separate), higher fees
        // Lyft: rideshare, slightly lower than Uber
        let calendar = Calendar.current
        let today = Date.now

        // Generate income for ~120 days back (4 months)
        for daysBack in 0..<120 {
            guard let date = calendar.date(byAdding: .day, value: -daysBack, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date) // 1=Sun, 7=Sat

            // Skip some days randomly (gig workers don't work every day)
            // Work 5-6 days/week, weekends are busiest
            let isWeekend = weekday == 1 || weekday == 6 || weekday == 7
            let workProbability: Double = isWeekend ? 0.90 : 0.65
            guard Double.random(in: 0...1) < workProbability else { continue }

            // How many gigs this day (1-4)
            let gigCount = isWeekend ? Int.random(in: 2...4) : Int.random(in: 1...3)

            for _ in 0..<gigCount {
                // Pick platform with weighted distribution
                let platformRoll = Double.random(in: 0...1)
                let platform: GigPlatformType
                let baseAmount: Double
                let tipRange: ClosedRange<Double>
                let feeRate: Double

                if platformRoll < 0.40 {
                    // Uber 40%
                    platform = .uber
                    baseAmount = Double.random(in: 18...95)
                    tipRange = 0...25
                    feeRate = Double.random(in: 0.10...0.15)
                } else if platformRoll < 0.70 {
                    // DoorDash 30%
                    platform = .doordash
                    baseAmount = Double.random(in: 12...55)
                    tipRange = 2...18
                    feeRate = Double.random(in: 0.11...0.16)
                } else if platformRoll < 0.88 {
                    // Instacart 18%
                    platform = .instacart
                    baseAmount = Double.random(in: 22...85)
                    tipRange = 0...5
                    feeRate = Double.random(in: 0.12...0.17)
                } else {
                    // Lyft 12%
                    platform = .lyft
                    baseAmount = Double.random(in: 15...80)
                    tipRange = 0...20
                    feeRate = Double.random(in: 0.10...0.14)
                }

                let tips = Double.random(in: tipRange)
                let fees = (baseAmount + tips) * feeRate

                // Round to cents
                let amount = (baseAmount * 100).rounded() / 100
                let tipsRounded = (tips * 100).rounded() / 100
                let feesRounded = (fees * 100).rounded() / 100

                let entry = IncomeEntry(
                    amount: amount,
                    tips: tipsRounded,
                    platformFees: feesRounded,
                    platform: platform,
                    entryMethod: daysBack < 30 ? .bankSync : .manual,
                    entryDate: date
                )
                context.insert(entry)
            }
        }

        // ── A few cash tips (via quick tip logger) ──
        let cashTipDays = [1, 3, 5, 8, 12, 15, 20, 25, 30]
        for day in cashTipDays {
            let entry = IncomeEntry(
                amount: 0,
                tips: Double([5, 10, 15, 20, 25].randomElement()!),
                platformFees: 0,
                platform: [GigPlatformType.uber, .doordash, .lyft].randomElement()!,
                entryMethod: .manual,
                entryDate: Date.daysAgo(day),
                notes: "Cash tip"
            )
            context.insert(entry)
        }

        // ── Expenses: realistic mix across many categories ──
        // Weekly gas fill-ups
        for week in 0..<16 {
            let daysAgo = week * 7 + Int.random(in: 0...2)
            let gasStation = ["Shell", "Chevron", "Costco", "76", "Arco"].randomElement()!
            let amount = Double.random(in: 48...72)
            let expense = ExpenseEntry(
                amount: (amount * 100).rounded() / 100,
                category: .gas,
                vendor: gasStation,
                description: "Weekly fill-up",
                expenseDate: Date.daysAgo(daysAgo)
            )
            context.insert(expense)
        }

        // Monthly insurance
        for month in 0..<4 {
            let expense = ExpenseEntry(
                amount: 125.00,
                category: .insurance,
                vendor: "GEICO",
                description: "Monthly rideshare insurance",
                expenseDate: Date.daysAgo(month * 30 + 15)
            )
            context.insert(expense)
        }

        // Monthly phone bill (50% deductible)
        for month in 0..<4 {
            let expense = ExpenseEntry(
                amount: 85.00,
                category: .phoneAndInternet,
                vendor: "T-Mobile",
                description: "Unlimited plan (50% business use)",
                expenseDate: Date.daysAgo(month * 30 + 5),
                deductionPercentage: 50
            )
            context.insert(expense)
        }

        // Occasional meals during shifts (50% deductible)
        let mealVendors = ["Chipotle", "Subway", "Panera", "McDonald's", "Chick-fil-A", "Taco Bell"]
        for i in 0..<12 {
            let expense = ExpenseEntry(
                amount: Double.random(in: 8...22).rounded(),
                category: .meals,
                vendor: mealVendors.randomElement()!,
                description: "Lunch during shift",
                expenseDate: Date.daysAgo(i * 10 + Int.random(in: 0...4)),
                deductionPercentage: 50
            )
            context.insert(expense)
        }

        // Vehicle maintenance
        let maintenanceItems: [(Double, String, String, Int)] = [
            (45.00, "Jiffy Lube", "Oil change", 7),
            (89.00, "Discount Tire", "Tire rotation", 35),
            (32.00, "AutoZone", "Wiper blades + fluid", 52),
            (285.00, "Firestone", "Brake pads replacement", 80),
            (155.00, "Midas", "Alignment + inspection", 95),
        ]
        for (amount, vendor, desc, daysAgo) in maintenanceItems {
            let expense = ExpenseEntry(
                amount: amount,
                category: .vehicleMaintenance,
                vendor: vendor,
                description: desc,
                expenseDate: Date.daysAgo(daysAgo)
            )
            context.insert(expense)
        }

        // Parking & tolls
        for i in 0..<8 {
            let expense = ExpenseEntry(
                amount: Double.random(in: 5...25).rounded(),
                category: .parking,
                vendor: ["ParkMobile", "SpotHero", "LAZ Parking", "FasTrak"].randomElement()!,
                description: ["Downtown parking", "Airport pickup area", "Bridge toll", "Event parking"].randomElement()!,
                expenseDate: Date.daysAgo(i * 14 + Int.random(in: 0...5))
            )
            context.insert(expense)
        }

        // Software/apps
        let softwareExpenses: [(Double, String, String, Int)] = [
            (9.99, "GigWallet Pro", "Tax tracking subscription", 10),
            (4.99, "Gridwise", "Earnings tracker", 10),
            (14.99, "TurboTax Self-Employed", "Tax prep software", 60),
        ]
        for (amount, vendor, desc, daysAgo) in softwareExpenses {
            let expense = ExpenseEntry(
                amount: amount,
                category: .software,
                vendor: vendor,
                description: desc,
                expenseDate: Date.daysAgo(daysAgo)
            )
            context.insert(expense)
        }

        // Equipment
        let equipmentExpenses: [(Double, String, String, Int)] = [
            (199.00, "Best Buy", "Dash cam (Vantrue N4)", 28),
            (34.99, "Amazon", "Phone mount + charger", 45),
            (24.99, "Amazon", "Insulated delivery bag", 62),
            (49.99, "Amazon", "Car organizer + cleaning kit", 90),
        ]
        for (amount, vendor, desc, daysAgo) in equipmentExpenses {
            let expense = ExpenseEntry(
                amount: amount,
                category: .equipment,
                vendor: vendor,
                description: desc,
                expenseDate: Date.daysAgo(daysAgo)
            )
            context.insert(expense)
        }

        // Supplies
        context.insert(ExpenseEntry(amount: 15.99, category: .supplies, vendor: "Costco", description: "Water bottles for passengers", expenseDate: Date.daysAgo(20)))
        context.insert(ExpenseEntry(amount: 8.49, category: .supplies, vendor: "Dollar Tree", description: "Air fresheners + wipes", expenseDate: Date.daysAgo(50)))

        // Health insurance (self-employed deduction)
        for month in 0..<4 {
            let expense = ExpenseEntry(
                amount: 385.00,
                category: .healthInsurance,
                vendor: "Covered California",
                description: "Marketplace health plan",
                expenseDate: Date.daysAgo(month * 30 + 1)
            )
            context.insert(expense)
        }

        // ── Mileage: daily driving data ──
        for daysBack in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: -daysBack, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = weekday == 1 || weekday == 6 || weekday == 7

            // Drive most work days
            let driveProbability: Double = isWeekend ? 0.85 : 0.60
            guard Double.random(in: 0...1) < driveProbability else { continue }

            let platform: GigPlatformType = [.uber, .doordash, .instacart, .lyft].randomElement()!
            let miles: Double
            let purpose: String

            if isWeekend {
                miles = Double.random(in: 35...75)
                purpose = ["Weekend grind", "Full day driving", "Airport runs + rides", "Long delivery shift"].randomElement()!
            } else {
                miles = Double.random(in: 15...50)
                purpose = ["Evening rides", "Lunch delivery run", "Morning rush", "After-work shift", "Quick delivery batch"].randomElement()!
            }

            let trip = MileageTrip(
                miles: (miles * 10).rounded() / 10,
                purpose: purpose,
                tripDate: date,
                platform: platform,
                isBusinessMiles: true
            )
            context.insert(trip)

            // ~10% of trips also have a commute leg (non-deductible)
            if Double.random(in: 0...1) < 0.10 {
                let commute = MileageTrip(
                    miles: Double.random(in: 5...15),
                    purpose: "Commute to first pickup",
                    tripDate: date,
                    platform: platform,
                    isBusinessMiles: false
                )
                context.insert(commute)
            }
        }

        // ── Tax Payments: Q4 2025 paid, Q1 2026 partially paid ──
        context.insert(TaxPayment(
            taxYear: 2025,
            quarter: .q4,
            amount: 2200,
            paymentDate: Date.daysAgo(50),
            paymentType: .federal,
            confirmationNumber: "IRS-2025Q4-8847291",
            notes: "Q4 2025 estimated tax"
        ))
        context.insert(TaxPayment(
            taxYear: 2025,
            quarter: .q4,
            amount: 450,
            paymentDate: Date.daysAgo(50),
            paymentType: .state,
            confirmationNumber: "CA-FTB-2025Q4-33012",
            notes: "CA Q4 2025 estimated tax"
        ))
        context.insert(TaxPayment(
            taxYear: 2026,
            quarter: .q1,
            amount: 1800,
            paymentDate: Date.daysAgo(15),
            paymentType: .federal,
            confirmationNumber: "IRS-2026Q1-1129403",
            notes: "Q1 2026 estimated tax — partial payment"
        ))

        // ── Tax Vault Entries ──
        context.insert(TaxVaultEntry(amount: 500, type: .setAside, note: "January set-aside"))
        context.insert(TaxVaultEntry(amount: 750, type: .setAside, note: "February set-aside"))
        context.insert(TaxVaultEntry(amount: 1800, type: .taxPayment, note: "Q1 federal payment"))

        // ── Budget Items (Financial Planner) ──
        let currentMonth = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            return formatter.string(from: Date.now)
        }()

        let budgetItems: [(String, Double, String, String, Bool)] = [
            // (name, amount, category raw, type raw, isFixed)
            ("Rent", 1800, "Housing", "expense", true),
            ("Car Payment", 425, "Transportation", "expense", true),
            ("Car Insurance", 180, "Transportation", "expense", true),
            ("Health Insurance", 385, "Health", "expense", true),
            ("Phone Bill", 85, "Utilities", "expense", true),
            ("Internet", 65, "Utilities", "expense", true),
            ("Groceries", 400, "Food", "expense", false),
            ("Gas (Personal)", 120, "Transportation", "expense", false),
            ("Streaming Services", 45, "Entertainment", "expense", true),
            ("Gym", 35, "Health", "expense", true),
            ("Freelance Web Design", 800, "Freelance", "income", false),
        ]

        for (name, amount, _, typeRaw, isFixed) in budgetItems {
            let item = BudgetItem(
                name: name,
                amount: amount,
                category: .other,
                type: BudgetItemType(rawValue: typeRaw) ?? .expense,
                isFixed: isFixed,
                monthYear: currentMonth
            )
            context.insert(item)
        }

        // Save everything
        try? context.save()

        #if DEBUG
        print("[DataSeeder] Demo data seeded: 4 months of income, expenses, mileage, tax payments, budget items")
        #endif
    }
    #endif
}
