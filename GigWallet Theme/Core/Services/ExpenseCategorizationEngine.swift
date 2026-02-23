import Foundation
import NaturalLanguage

/// On-device expense auto-categorization engine using keyword matching and the
/// NaturalLanguage framework for fuzzy fallback. Stateless — every method is
/// `static`, and the type is an `enum` with no cases so it cannot be
/// instantiated. Safe to call from any concurrency context.
///
/// Usage:
///     let prediction = ExpenseCategorizationEngine.categorize(
///         description: "SHELL OIL 04823",
///         merchantName: "Shell",
///         amount: 52.40
///     )
///     // prediction.category == "Gas & Fuel"
///     // prediction.confidence == 0.95
enum ExpenseCategorizationEngine: Sendable {

    // MARK: - Public Types

    /// Result of an auto-categorization attempt.
    struct CategoryPrediction: Sendable {
        /// Matches an `ExpenseCategory.rawValue` (e.g. "Gas & Fuel").
        let category: String
        /// 0-1 confidence score.
        let confidence: Double
        /// Whether the expense is generally deductible for a gig worker.
        let isDeductible: Bool
        /// Fraction that is deductible (0-1). For example 0.5 = 50 %.
        let deductionPercentage: Double
        /// Human-readable one-line explanation.
        let reasoning: String
    }

    // MARK: - Categorize

    /// Primary entry point. Attempts keyword matching first, then falls back
    /// to NaturalLanguage embedding-based similarity, and finally to `.other`.
    static func categorize(
        description: String,
        merchantName: String? = nil,
        amount: Double
    ) -> CategoryPrediction {
        // Combine inputs into a single searchable string.
        let combined = [description, merchantName ?? ""]
            .joined(separator: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Keyword match (fast, high confidence).
        if let match = keywordMatch(combined, amount: amount) {
            return match
        }

        // 2. Amount-based heuristics for ambiguous entries.
        if let heuristic = amountHeuristic(combined, amount: amount) {
            return heuristic
        }

        // 3. NaturalLanguage embedding fallback (fuzzy).
        if let nlMatch = embeddingMatch(combined) {
            return nlMatch
        }

        // 4. Nothing matched.
        return CategoryPrediction(
            category: ExpenseCategory.other.rawValue,
            confidence: 0.0,
            isDeductible: false,
            deductionPercentage: 0.0,
            reasoning: "Unable to determine category automatically"
        )
    }

    // MARK: - Deductibility Reference

    /// Returns IRS-aligned deductibility information for a given category.
    /// - Parameters:
    ///   - category: An `ExpenseCategory` raw value string.
    ///   - forGigWorker: Pass `true` (the default) for self-employed / 1099
    ///     workers, which unlocks additional deductions.
    /// - Returns: A tuple of `(isDeductible, percentage, note)`.
    static func suggestDeductibility(
        category: String,
        forGigWorker: Bool = true
    ) -> (isDeductible: Bool, percentage: Double, note: String) {
        guard let mapped = ExpenseCategory(rawValue: category) else {
            return (false, 0.0, "Unknown category. Consult a tax professional.")
        }

        switch mapped {
        case .mileage:
            return (true, 1.0,
                    "IRS standard mileage rate ($0.70/mile for 2026). Cannot combine with actual vehicle expenses.")

        case .gas:
            if forGigWorker {
                return (true, 1.0,
                        "100% deductible if using the actual expense method. Not deductible if using the standard mileage rate.")
            }
            return (false, 0.0,
                    "Gas is not deductible for W-2 employees.")

        case .vehicleMaintenance:
            if forGigWorker {
                return (true, 1.0,
                        "Deductible under the actual expense method at your business-use percentage. Not deductible with the standard mileage rate.")
            }
            return (false, 0.0,
                    "Vehicle maintenance is not deductible for W-2 employees.")

        case .insurance:
            if forGigWorker {
                return (true, 0.5,
                        "Auto insurance is deductible at your business-use percentage (commonly ~50% for gig workers).")
            }
            return (false, 0.0,
                    "Auto insurance is generally not deductible for W-2 employees.")

        case .phoneAndInternet:
            if forGigWorker {
                return (true, 0.5,
                        "Deductible at your business-use percentage. IRS expects a reasonable split; 50% is commonly used for gig workers.")
            }
            return (false, 0.0,
                    "Phone and internet are no longer deductible for W-2 employees under TCJA.")

        case .supplies:
            if forGigWorker {
                return (true, 1.0,
                        "Business supplies are 100% deductible. Keep receipts and ensure items are primarily for business use.")
            }
            return (false, 0.0,
                    "Supplies are generally not deductible for W-2 employees under TCJA.")

        case .equipment:
            if forGigWorker {
                return (true, 1.0,
                        "Equipment can be fully deducted in the year of purchase under Section 179, or depreciated over time.")
            }
            return (false, 0.0,
                    "Equipment is not deductible for W-2 employees.")

        case .meals:
            return (true, 0.5,
                    "Business meals are 50% deductible. Must have a clear business purpose (meeting with client, while traveling for business).")

        case .homeOffice:
            if forGigWorker {
                return (true, 1.0,
                        "Simplified method: $5/sq ft, up to 300 sq ft ($1,500 max). Or use actual expenses pro-rated by home office percentage.")
            }
            return (false, 0.0,
                    "Home office deduction is not available for W-2 employees under TCJA.")

        case .software:
            if forGigWorker {
                return (true, 1.0,
                        "Business software and app subscriptions are 100% deductible. Personal-use apps are not deductible.")
            }
            return (false, 0.0,
                    "Software subscriptions are generally not deductible for W-2 employees.")

        case .advertising:
            if forGigWorker {
                return (true, 1.0,
                        "100% deductible. Includes business cards, website hosting, and paid promotion of your gig services.")
            }
            return (false, 0.0,
                    "Advertising is not a common W-2 deduction.")

        case .professionalServices:
            if forGigWorker {
                return (true, 1.0,
                        "100% deductible. Includes tax preparation, legal services, and accounting fees related to your gig business.")
            }
            return (false, 0.0,
                    "Professional services are generally not deductible for W-2 employees under TCJA.")

        case .healthInsurance:
            if forGigWorker {
                return (true, 1.0,
                        "Self-employed health insurance premiums are 100% deductible (above-the-line). Includes medical, dental, and vision.")
            }
            return (false, 0.0,
                    "Health insurance premiums may be deductible if itemizing and exceeding 7.5% of AGI.")

        case .retirement:
            if forGigWorker {
                return (true, 1.0,
                        "SEP IRA contributions up to 25% of net SE income (max $70,000 for 2026) are deductible. Solo 401(k) also available.")
            }
            return (true, 1.0,
                    "Traditional IRA and 401(k) contributions are deductible up to annual limits.")

        case .parking:
            if forGigWorker {
                return (true, 1.0,
                        "100% deductible when incurred during gig work. Includes parking meters, garages, and tolls.")
            }
            return (false, 0.0,
                    "Parking and tolls for commuting are not deductible for W-2 employees.")

        case .other:
            return (false, 0.0,
                    "Deductibility depends on the specific expense. Consult a tax professional for guidance.")
        }
    }

    // MARK: - Keyword Rule Definitions

    /// Each rule maps a set of lowercase keywords to a category, deduction
    /// info, and a reasoning template. Ordered so that more-specific rules
    /// (e.g. gas station brand names) are checked before broad ones
    /// (e.g. "amazon" -> supplies).
    private struct KeywordRule {
        let keywords: [String]
        let category: ExpenseCategory
        let confidence: Double
        let isDeductible: Bool
        let deductionPercentage: Double
        let reasoning: String
    }

    private static let keywordRules: [KeywordRule] = [
        // ---- Gas & Fuel ----
        KeywordRule(
            keywords: [
                "shell", "chevron", "bp ", "exxon", "mobil", "speedway", "wawa",
                "circle k", "76 ", "arco", "costco gas", "marathon", "valero",
                "sunoco", "phillips 66", "fuel", "gasoline", "petrol",
                "pilot", "loves travel", "racetrac", "quiktrip", "sam's fuel",
                "murphy usa", "7-eleven fuel", "citgo"
            ],
            category: .gas,
            confidence: 0.95,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Gas station purchase"
        ),
        // ---- Vehicle Maintenance ----
        KeywordRule(
            keywords: [
                "autozone", "oreilly", "o'reilly", "jiffy lube", "valvoline",
                "meineke", "firestone", "goodyear", "oil change", "tire",
                "brake", "carwash", "car wash", "pep boys", "advance auto",
                "midas", "maaco", "safelite", "napa auto", "repair shop"
            ],
            category: .vehicleMaintenance,
            confidence: 0.90,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Vehicle maintenance expense"
        ),
        // ---- Insurance ----
        KeywordRule(
            keywords: [
                "geico", "state farm", "allstate", "progressive",
                "liberty mutual", "usaa", "farmers", "nationwide",
                "travelers", "auto insurance", "car insurance"
            ],
            category: .insurance,
            confidence: 0.90,
            isDeductible: true,
            deductionPercentage: 0.5,
            reasoning: "Auto insurance payment"
        ),
        // ---- Phone & Internet ----
        KeywordRule(
            keywords: [
                "verizon", "t-mobile", "tmobile", "at&t", "att", "sprint",
                "comcast", "xfinity", "spectrum", "cox", "centurylink",
                "google fi", "mint mobile", "visible", "cricket",
                "boost mobile", "metro pcs", "metropcs"
            ],
            category: .phoneAndInternet,
            confidence: 0.90,
            isDeductible: true,
            deductionPercentage: 0.5,
            reasoning: "Phone or internet service"
        ),
        // ---- Parking & Tolls ----
        KeywordRule(
            keywords: [
                "parking", "meter", "garage", "toll", "ezpass", "fastrak",
                "sunpass", "parkwhiz", "spothero", "parkopedia", "ipark",
                "park mobile", "parkmobile"
            ],
            category: .parking,
            confidence: 0.90,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Parking or toll expense"
        ),
        // ---- Health Insurance ----
        KeywordRule(
            keywords: [
                "kaiser", "aetna", "cigna", "united health", "unitedhealthcare",
                "blue cross", "blue shield", "bcbs", "humana", "anthem",
                "molina", "centene", "health insurance", "medical insurance",
                "dental insurance", "vision insurance", "healthcare.gov"
            ],
            category: .healthInsurance,
            confidence: 0.90,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Health insurance premium"
        ),
        // ---- Meals (Business) ----
        KeywordRule(
            keywords: [
                "restaurant", "mcdonald", "starbucks", "chipotle", "subway",
                "wendys", "wendy's", "taco bell", "pizza", "uber eats",
                "doordash", "grubhub", "cafe", "diner", "burger",
                "coffee", "dunkin", "chick-fil-a", "chickfila", "panera",
                "panda express", "popeyes", "five guys", "wingstop",
                "ihop", "denny's", "applebee", "chili's", "olive garden"
            ],
            category: .meals,
            confidence: 0.85,
            isDeductible: true,
            deductionPercentage: 0.5,
            reasoning: "Meal or restaurant purchase"
        ),
        // ---- Software & Apps ----
        KeywordRule(
            keywords: [
                "apple.com", "google play", "adobe", "microsoft", "zoom",
                "slack", "quickbooks", "turbotax", "canva", "dropbox",
                "icloud", "subscript", "notion", "figma", "github",
                "aws", "heroku", "netlify", "openai", "chatgpt",
                "spotify", "gridwise", "everlance"
            ],
            category: .software,
            confidence: 0.85,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Software or app subscription"
        ),
        // ---- Home Office ----
        KeywordRule(
            keywords: [
                "ikea", "wayfair", "office furniture", "desk", "chair",
                "monitor", "standing desk", "ergonomic", "home depot desk",
                "office chair"
            ],
            category: .homeOffice,
            confidence: 0.80,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Home office furniture or equipment"
        ),
        // ---- Advertising ----
        KeywordRule(
            keywords: [
                "facebook ads", "google ads", "instagram ads", "tiktok ads",
                "vistaprint", "business cards", "flyer", "banner",
                "yelp ads", "promoted post", "social media ad"
            ],
            category: .advertising,
            confidence: 0.85,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Advertising or marketing expense"
        ),
        // ---- Professional Services ----
        KeywordRule(
            keywords: [
                "h&r block", "hrblock", "legalzoom", "legal zoom",
                "attorney", "lawyer", "accountant", "cpa", "bookkeeper",
                "tax prep", "tax preparation"
            ],
            category: .professionalServices,
            confidence: 0.85,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Professional or legal service"
        ),
        // ---- Retirement ----
        KeywordRule(
            keywords: [
                "sep ira", "solo 401k", "solo 401(k)", "roth ira",
                "traditional ira", "fidelity retirement", "vanguard retirement",
                "schwab retirement", "retirement contribution"
            ],
            category: .retirement,
            confidence: 0.85,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Retirement account contribution"
        ),
        // ---- Supplies (broad — checked last among specifics) ----
        KeywordRule(
            keywords: [
                "amazon", "walmart", "target", "costco", "home depot",
                "lowes", "lowe's", "staples", "office depot", "best buy",
                "dollar tree", "dollar general", "five below"
            ],
            category: .supplies,
            confidence: 0.60,
            isDeductible: true,
            deductionPercentage: 1.0,
            reasoning: "Retail purchase — likely supplies"
        ),
    ]

    // MARK: - Keyword Matching

    private static func keywordMatch(
        _ text: String,
        amount: Double
    ) -> CategoryPrediction? {
        for rule in keywordRules {
            for keyword in rule.keywords {
                if text.contains(keyword) {
                    return CategoryPrediction(
                        category: rule.category.rawValue,
                        confidence: rule.confidence,
                        isDeductible: rule.isDeductible,
                        deductionPercentage: rule.deductionPercentage,
                        reasoning: rule.reasoning
                    )
                }
            }
        }
        return nil
    }

    // MARK: - Amount Heuristics

    /// Some amounts strongly suggest a category even when the description is
    /// ambiguous. For example a $50-$90 charge from an unknown vendor might
    /// be a phone bill, while a $150-$400 charge might be insurance.
    private static func amountHeuristic(
        _ text: String,
        amount: Double
    ) -> CategoryPrediction? {
        // Monthly phone bill range with phone-related words.
        let phoneIndicators = ["wireless", "mobile", "cellular", "phone", "telecom"]
        if phoneIndicators.contains(where: { text.contains($0) }) && amount > 20 && amount < 200 {
            return CategoryPrediction(
                category: ExpenseCategory.phoneAndInternet.rawValue,
                confidence: 0.70,
                isDeductible: true,
                deductionPercentage: 0.5,
                reasoning: "Likely a phone/wireless charge based on description and amount"
            )
        }

        // Insurance-like payment range with insurance-related words.
        let insuranceIndicators = ["insurance", "premium", "policy", "coverage", "insur"]
        if insuranceIndicators.contains(where: { text.contains($0) }) && amount > 50 && amount < 500 {
            return CategoryPrediction(
                category: ExpenseCategory.insurance.rawValue,
                confidence: 0.70,
                isDeductible: true,
                deductionPercentage: 0.5,
                reasoning: "Likely an insurance premium based on description and amount"
            )
        }

        // Health-related keywords that didn't match the specific health
        // insurance vendors above.
        let healthIndicators = ["health", "medical", "dental", "vision", "rx", "pharmacy",
                                "cvs", "walgreens", "rite aid"]
        if healthIndicators.contains(where: { text.contains($0) }) {
            return CategoryPrediction(
                category: ExpenseCategory.healthInsurance.rawValue,
                confidence: 0.65,
                isDeductible: true,
                deductionPercentage: 1.0,
                reasoning: "Health or medical expense"
            )
        }

        return nil
    }

    // MARK: - NaturalLanguage Embedding Fallback

    /// Category anchor words used for embedding similarity. Each category maps
    /// to a handful of semantically representative words. When no keyword
    /// matches, the engine tokenises the input, obtains word embeddings, and
    /// finds the closest anchor. This is fully on-device — no network needed.
    private static let categoryAnchors: [(category: ExpenseCategory, anchors: [String], isDeductible: Bool, deductionPercentage: Double)] = [
        (.gas,                  ["gasoline", "fuel", "petrol", "diesel"],                         true,  1.0),
        (.vehicleMaintenance,   ["mechanic", "repair", "maintenance", "tire", "oil"],             true,  1.0),
        (.insurance,            ["insurance", "premium", "coverage", "policy"],                    true,  0.5),
        (.phoneAndInternet,     ["phone", "internet", "wireless", "broadband", "cellular"],       true,  0.5),
        (.parking,              ["parking", "toll", "meter", "garage"],                            true,  1.0),
        (.healthInsurance,      ["health", "medical", "dental", "hospital", "doctor"],            true,  1.0),
        (.meals,                ["restaurant", "food", "meal", "lunch", "dinner", "coffee"],      true,  0.5),
        (.software,             ["software", "app", "subscription", "digital", "cloud"],          true,  1.0),
        (.homeOffice,           ["furniture", "desk", "chair", "office", "ergonomic"],            true,  1.0),
        (.advertising,          ["advertising", "marketing", "promotion", "campaign"],            true,  1.0),
        (.professionalServices, ["lawyer", "accountant", "attorney", "consulting", "legal"],      true,  1.0),
        (.retirement,           ["retirement", "pension", "401k", "ira"],                         true,  1.0),
        (.supplies,             ["supplies", "stationery", "equipment", "tools"],                 true,  1.0),
    ]

    /// Minimum cosine similarity to accept an embedding match.
    private static let embeddingSimilarityThreshold: Double = 0.40

    private static func embeddingMatch(_ text: String) -> CategoryPrediction? {
        // NLEmbedding may not be available on all devices / OS versions.
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return nil
        }

        // Tokenise the input into words.
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var inputWords: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if word.count > 2 { // Skip very short tokens (articles, etc.)
                inputWords.append(word)
            }
            return true
        }

        guard !inputWords.isEmpty else { return nil }

        var bestCategory: ExpenseCategory?
        var bestSimilarity: Double = -1.0
        var bestDeductible = false
        var bestDeductionPct = 0.0

        for anchor in categoryAnchors {
            for anchorWord in anchor.anchors {
                for inputWord in inputWords {
                    let distance = embedding.distance(
                        between: inputWord,
                        and: anchorWord,
                        distanceType: .cosine
                    )
                    // NLEmbedding.distance returns cosine distance (0 = identical,
                    // 2 = opposite). Convert to similarity.
                    let similarity = 1.0 - distance

                    if similarity > bestSimilarity {
                        bestSimilarity = similarity
                        bestCategory = anchor.category
                        bestDeductible = anchor.isDeductible
                        bestDeductionPct = anchor.deductionPercentage
                    }
                }
            }
        }

        guard let category = bestCategory,
              bestSimilarity >= embeddingSimilarityThreshold else {
            return nil
        }

        // Scale confidence: threshold maps to ~0.40, perfect match maps to ~0.80.
        // We cap at 0.80 because embedding-only matches are inherently less
        // certain than keyword hits.
        let confidence = min(0.80, max(0.30, bestSimilarity * 0.85))

        return CategoryPrediction(
            category: category.rawValue,
            confidence: confidence,
            isDeductible: bestDeductible,
            deductionPercentage: bestDeductionPct,
            reasoning: "Auto-categorized via semantic similarity"
        )
    }
}
