import Foundation
import SwiftUI
import CoreLocation

/// Fetches and analyzes local events to predict gig demand surges.
/// Uses the Ticketmaster Discovery API (5000 calls/day, free tier).
/// Falls back to state-specific real venue data when API unavailable.
///
/// Events drive massive gig demand: concerts, sports, conferences near the user
/// boost rideshare/delivery demand by 25-200%.
@MainActor @Observable
final class EventAlertService: @unchecked Sendable {
    static let shared = EventAlertService()

    // MARK: - Types

    struct LocalEvent: Identifiable {
        let id: String
        let name: String
        let venue: String
        let date: Date
        let endDate: Date?
        let category: EventCategory
        let estimatedAttendance: Int
        let demandBoost: DemandBoost
        let imageURL: String?

        init(id: String, name: String, venue: String, date: Date, endDate: Date?,
             category: EventCategory, estimatedAttendance: Int, demandBoost: DemandBoost,
             imageURL: String? = nil) {
            self.id = id
            self.name = name
            self.venue = venue
            self.date = date
            self.endDate = endDate
            self.category = category
            self.estimatedAttendance = estimatedAttendance
            self.demandBoost = demandBoost
            self.imageURL = imageURL
        }

        var isToday: Bool {
            Calendar.current.isDateInToday(date)
        }

        var isThisWeekend: Bool {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: date)
            let daysUntil = calendar.dateComponents([.day], from: .now, to: date).day ?? 99
            return (weekday == 1 || weekday == 6 || weekday == 7) && daysUntil <= 7 && daysUntil >= 0
        }
    }

    enum EventCategory: String, CaseIterable {
        case sports = "Sports"
        case concert = "Concert"
        case conference = "Conference"
        case festival = "Festival"
        case theater = "Theater"
        case other = "Event"

        var sfSymbol: String {
            switch self {
            case .sports: return "sportscourt.fill"
            case .concert: return "music.mic"
            case .conference: return "person.3.fill"
            case .festival: return "party.popper.fill"
            case .theater: return "theatermasks.fill"
            case .other: return "calendar.badge.clock"
            }
        }

        var color: Color {
            switch self {
            case .sports: return BrandColors.success
            case .concert: return BrandColors.info
            case .conference: return BrandColors.primary
            case .festival: return BrandColors.warning
            case .theater: return BrandColors.primaryLight
            case .other: return BrandColors.textSecondary
            }
        }
    }

    enum DemandBoost: Comparable {
        case low
        case moderate
        case high
        case extreme

        var label: String {
            switch self {
            case .low: return "Low Impact"
            case .moderate: return "Moderate Surge"
            case .high: return "High Surge"
            case .extreme: return "Massive Demand"
            }
        }

        var multiplierText: String {
            switch self {
            case .low: return "+10-20%"
            case .moderate: return "+25-50%"
            case .high: return "+50-100%"
            case .extreme: return "+100-200%"
            }
        }

        var color: Color {
            switch self {
            case .low: return BrandColors.textSecondary
            case .moderate: return BrandColors.warning
            case .high: return BrandColors.primary
            case .extreme: return BrandColors.destructive
            }
        }
    }

    // MARK: - Ticketmaster API

    // API key loaded from Secrets.xcconfig → Info.plist at build time
    private let ticketmasterAPIKey: String = Bundle.main.infoDictionary?["TICKETMASTER_API_KEY"] as? String ?? ""
    private let ticketmasterBaseURL = "https://app.ticketmaster.com/discovery/v2/events.json"

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // State-to-DMA mapping for Ticketmaster (major metros)
    private let stateToDMA: [String: String] = [
        "AZ": "753",  // Phoenix
        "CA": "803",  // Los Angeles
        "TX": "623",  // Dallas-Fort Worth
        "FL": "528",  // Miami
        "NY": "501",  // New York
        "IL": "602",  // Chicago
        "GA": "524",  // Atlanta
        "NV": "839",  // Las Vegas
        "CO": "751",  // Denver
        "WA": "819",  // Seattle
        "PA": "504",  // Philadelphia
        "OH": "510",  // Cleveland
        "MA": "506",  // Boston
        "MI": "505",  // Detroit
        "MN": "613",  // Minneapolis
        "MO": "609",  // St. Louis
        "TN": "659",  // Nashville
        "OR": "820",  // Portland
        "NC": "517",  // Charlotte
        "IN": "527",  // Indianapolis
    ]

    // MARK: - State

    var upcomingEvents: [LocalEvent] = []
    var isLoading = false
    var lastFetched: Date?
    var isUsingRealData = false

    // MARK: - Public API

    /// Fetch upcoming events for the user's metro area.
    /// Tries Ticketmaster Discovery API first, falls back to venue data.
    /// Pass latitude/longitude for GPS-based results; otherwise uses stateCode/DMA.
    func fetchEvents(stateCode: String, latitude: Double? = nil, longitude: Double? = nil) async {
        isLoading = true
        defer { isLoading = false }

        // Try Ticketmaster API first
        if let liveEvents = await fetchTicketmasterEvents(stateCode: stateCode, latitude: latitude, longitude: longitude), !liveEvents.isEmpty {
            upcomingEvents = liveEvents
            isUsingRealData = true
        } else {
            // Fallback to state-specific real venue data
            upcomingEvents = generateSmartFallback(stateCode: stateCode)
            isUsingRealData = false
        }
        lastFetched = .now
    }

    /// Filter events happening today or tonight.
    var todaysEvents: [LocalEvent] {
        upcomingEvents.filter { $0.isToday }
    }

    /// Filter events happening this weekend.
    var weekendEvents: [LocalEvent] {
        upcomingEvents.filter { $0.isThisWeekend && !$0.isToday }
    }

    /// The highest-demand event in the next 24 hours.
    var topUpcomingEvent: LocalEvent? {
        let next24h = upcomingEvents.filter {
            let hoursUntil = Calendar.current.dateComponents([.hour], from: .now, to: $0.date).hour ?? 99
            return hoursUntil >= 0 && hoursUntil <= 24
        }
        return next24h.max(by: { $0.demandBoost < $1.demandBoost })
    }

    // MARK: - Ticketmaster Discovery API

    /// Fetches real events from Ticketmaster Discovery API.
    /// API docs: https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/
    ///
    /// - Parameters:
    ///   - stateCode: Two-letter US state code (e.g. "AZ", "CA")
    ///   - latitude: Optional GPS latitude for location-based search
    ///   - longitude: Optional GPS longitude for location-based search
    /// - Returns: Array of LocalEvent parsed from Ticketmaster, or nil on failure
    private func fetchTicketmasterEvents(stateCode: String, latitude: Double? = nil, longitude: Double? = nil) async -> [LocalEvent]? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let startDate = dateFormatter.string(from: .now)
        let endDate: String
        if let sevenDaysOut = Calendar.current.date(byAdding: .day, value: 7, to: .now) {
            endDate = dateFormatter.string(from: sevenDaysOut)
        } else {
            return nil
        }

        var components = URLComponents(string: ticketmasterBaseURL)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "apikey", value: ticketmasterAPIKey),
            URLQueryItem(name: "startDateTime", value: startDate),
            URLQueryItem(name: "endDateTime", value: endDate),
            URLQueryItem(name: "size", value: "10"),
            URLQueryItem(name: "sort", value: "date,asc"),
            URLQueryItem(name: "classificationName", value: "Music,Sports,Arts & Theatre"),
        ]

        // Prefer GPS coordinates for precise location, fall back to stateCode/DMA
        if let lat = latitude, let lon = longitude {
            queryItems.append(URLQueryItem(name: "latlong", value: "\(lat),\(lon)"))
            queryItems.append(URLQueryItem(name: "radius", value: "30"))
            queryItems.append(URLQueryItem(name: "unit", value: "miles"))
        } else {
            queryItems.append(URLQueryItem(name: "stateCode", value: stateCode))
            // Add DMA (Designated Market Area) if we have one for this state
            if let dma = stateToDMA[stateCode] {
                queryItems.append(URLQueryItem(name: "dmaId", value: dma))
            }
        }

        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            return parseTicketmasterResponse(data: data)
        } catch {
            return nil
        }
    }

    /// Parse Ticketmaster Discovery API JSON response into LocalEvent array.
    ///
    /// Response shape:
    /// ```
    /// { "_embedded": { "events": [ { "id", "name", "dates": { "start": { "dateTime" } },
    ///   "classifications": [...], "_embedded": { "venues": [{ "name", "generalInfo": { "capacity" } }] },
    ///   "images": [{ "url" }] } ] } }
    /// ```
    private func parseTicketmasterResponse(data: Data) -> [LocalEvent]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedded = json["_embedded"] as? [String: Any],
              let events = embedded["events"] as? [[String: Any]] else {
            return nil
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        var parsedEvents: [LocalEvent] = []

        for event in events {
            guard let eventId = event["id"] as? String,
                  let name = event["name"] as? String else { continue }

            // Parse date
            var eventDate = Date.now
            if let dates = event["dates"] as? [String: Any],
               let start = dates["start"] as? [String: Any],
               let dateTimeStr = start["dateTime"] as? String,
               let parsed = dateFormatter.date(from: dateTimeStr) {
                eventDate = parsed
            }

            // Parse venue
            var venueName = "Venue TBA"
            var estimatedCapacity = 5_000 // Default estimate
            if let eventEmbedded = event["_embedded"] as? [String: Any],
               let venues = eventEmbedded["venues"] as? [[String: Any]],
               let firstVenue = venues.first {
                venueName = (firstVenue["name"] as? String) ?? "Venue TBA"

                // Try to get capacity from generalInfo
                if let generalInfo = firstVenue["generalInfo"] as? [String: Any],
                   let capacityStr = generalInfo["generalRule"] as? String {
                    // Ticketmaster sometimes embeds capacity in generalRule text
                    let numbers = capacityStr.components(separatedBy: CharacterSet.decimalDigits.inverted)
                        .compactMap { Int($0) }
                        .filter { $0 > 1000 && $0 < 200_000 }
                    if let cap = numbers.first {
                        estimatedCapacity = cap
                    }
                }

                // Also check upcomingEvents section
                if let upcomingEvents = firstVenue["upcomingEvents"] as? [String: Any],
                   let totalEvents = upcomingEvents["_total"] as? Int,
                   totalEvents > 100 {
                    // Highly active venue = larger capacity
                    estimatedCapacity = max(estimatedCapacity, 15_000)
                }
            }

            // Parse category from classifications
            var category: EventCategory = .other
            if let classifications = event["classifications"] as? [[String: Any]],
               let firstClassification = classifications.first {
                if let segment = firstClassification["segment"] as? [String: Any],
                   let segmentName = segment["name"] as? String {
                    switch segmentName.lowercased() {
                    case "sports": category = .sports
                    case "music": category = .concert
                    case "arts & theatre": category = .theater
                    default: category = .other
                    }
                }
                // Refine with genre
                if let genre = firstClassification["genre"] as? [String: Any],
                   let genreName = genre["name"] as? String {
                    if genreName.lowercased().contains("festival") { category = .festival }
                }
            }

            // Parse image
            var imageURL: String? = nil
            if let images = event["images"] as? [[String: Any]],
               let firstImage = images.first(where: { ($0["width"] as? Int ?? 0) >= 500 }) ?? images.first {
                imageURL = firstImage["url"] as? String
            }

            let demandBoost = boostFromAttendance(estimatedCapacity)

            parsedEvents.append(LocalEvent(
                id: eventId,
                name: name,
                venue: venueName,
                date: eventDate,
                endDate: nil,
                category: category,
                estimatedAttendance: estimatedCapacity,
                demandBoost: demandBoost,
                imageURL: imageURL
            ))
        }

        // Deduplicate: Ticketmaster often returns the same event multiple times
        // (different ticket types, resale listings, etc.). Keep highest attendance estimate.
        var seen: [String: Int] = [:] // dedup key → index in unique array
        var uniqueEvents: [LocalEvent] = []
        for event in parsedEvents {
            let dayString = Calendar.current.startOfDay(for: event.date).timeIntervalSince1970
            let key = "\(event.name.lowercased())|\(event.venue.lowercased())|\(Int(dayString))"
            if let existingIndex = seen[key] {
                // Keep the one with higher attendance estimate
                if event.estimatedAttendance > uniqueEvents[existingIndex].estimatedAttendance {
                    uniqueEvents[existingIndex] = event
                }
            } else {
                seen[key] = uniqueEvents.count
                uniqueEvents.append(event)
            }
        }

        return uniqueEvents.isEmpty ? nil : uniqueEvents
    }

    // MARK: - Smart Fallback (State-Specific Real Venues)

    private func generateSmartFallback(stateCode: String) -> [LocalEvent] {
        let calendar = Calendar.current
        let now = Date.now
        let venues = venueData(for: stateCode)

        return [
            LocalEvent(
                id: "ev-1", name: venues.sportTeam,
                venue: venues.arena,
                date: calendar.date(byAdding: .hour, value: 5, to: now) ?? now,
                endDate: calendar.date(byAdding: .hour, value: 8, to: now),
                category: .sports, estimatedAttendance: venues.arenaCapacity,
                demandBoost: boostFromAttendance(venues.arenaCapacity)
            ),
            LocalEvent(
                id: "ev-2", name: "Live Concert",
                venue: venues.concertVenue,
                date: calendar.date(byAdding: .day, value: 2, to: now) ?? now,
                endDate: nil, category: .concert,
                estimatedAttendance: venues.concertCapacity,
                demandBoost: boostFromAttendance(venues.concertCapacity)
            ),
            LocalEvent(
                id: "ev-3", name: venues.stadiumEvent,
                venue: venues.stadium,
                date: Self.nextWeekend(from: now),
                endDate: nil, category: .sports,
                estimatedAttendance: venues.stadiumCapacity,
                demandBoost: boostFromAttendance(venues.stadiumCapacity)
            ),
        ]
    }

    private func boostFromAttendance(_ attendance: Int) -> DemandBoost {
        switch attendance {
        case 50_000...: return .extreme
        case 20_000..<50_000: return .high
        case 5_000..<20_000: return .moderate
        default: return .low
        }
    }

    // MARK: - Real Venue Data by State

    private struct VenueData {
        let arena: String
        let arenaCapacity: Int
        let sportTeam: String
        let stadium: String
        let stadiumCapacity: Int
        let stadiumEvent: String
        let concertVenue: String
        let concertCapacity: Int
    }

    private func venueData(for stateCode: String) -> VenueData {
        switch stateCode {
        case "AZ": return VenueData(
            arena: "Footprint Center", arenaCapacity: 18_055, sportTeam: "Suns vs Lakers",
            stadium: "State Farm Stadium", stadiumCapacity: 63_400, stadiumEvent: "Cardinals Game",
            concertVenue: "Arizona Financial Theatre", concertCapacity: 5_000
        )
        case "CA": return VenueData(
            arena: "Crypto.com Arena", arenaCapacity: 20_000, sportTeam: "Lakers vs Warriors",
            stadium: "SoFi Stadium", stadiumCapacity: 70_000, stadiumEvent: "Rams Game",
            concertVenue: "The Greek Theatre", concertCapacity: 5_900
        )
        case "TX": return VenueData(
            arena: "American Airlines Center", arenaCapacity: 19_200, sportTeam: "Mavericks vs Spurs",
            stadium: "AT&T Stadium", stadiumCapacity: 80_000, stadiumEvent: "Cowboys Game",
            concertVenue: "The Factory in Deep Ellum", concertCapacity: 4_400
        )
        case "FL": return VenueData(
            arena: "Kaseya Center", arenaCapacity: 19_600, sportTeam: "Heat vs Celtics",
            stadium: "Hard Rock Stadium", stadiumCapacity: 65_000, stadiumEvent: "Dolphins Game",
            concertVenue: "The Fillmore Miami Beach", concertCapacity: 2_700
        )
        case "NY": return VenueData(
            arena: "Madison Square Garden", arenaCapacity: 20_789, sportTeam: "Knicks vs Nets",
            stadium: "MetLife Stadium", stadiumCapacity: 82_500, stadiumEvent: "Giants Game",
            concertVenue: "Brooklyn Steel", concertCapacity: 1_800
        )
        case "IL": return VenueData(
            arena: "United Center", arenaCapacity: 20_917, sportTeam: "Bulls vs Bucks",
            stadium: "Soldier Field", stadiumCapacity: 61_500, stadiumEvent: "Bears Game",
            concertVenue: "The Chicago Theatre", concertCapacity: 3_600
        )
        case "GA": return VenueData(
            arena: "State Farm Arena", arenaCapacity: 18_118, sportTeam: "Hawks vs Heat",
            stadium: "Mercedes-Benz Stadium", stadiumCapacity: 71_000, stadiumEvent: "Falcons Game",
            concertVenue: "Tabernacle", concertCapacity: 2_600
        )
        case "NV": return VenueData(
            arena: "T-Mobile Arena", arenaCapacity: 20_000, sportTeam: "Golden Knights Game",
            stadium: "Allegiant Stadium", stadiumCapacity: 65_000, stadiumEvent: "Raiders Game",
            concertVenue: "The Venetian Theatre", concertCapacity: 4_300
        )
        case "CO": return VenueData(
            arena: "Ball Arena", arenaCapacity: 19_520, sportTeam: "Nuggets vs Thunder",
            stadium: "Empower Field at Mile High", stadiumCapacity: 76_125, stadiumEvent: "Broncos Game",
            concertVenue: "Red Rocks Amphitheatre", concertCapacity: 9_525
        )
        case "WA": return VenueData(
            arena: "Climate Pledge Arena", arenaCapacity: 17_151, sportTeam: "Kraken vs Canucks",
            stadium: "Lumen Field", stadiumCapacity: 69_000, stadiumEvent: "Seahawks Game",
            concertVenue: "The Showbox", concertCapacity: 1_100
        )
        case "PA": return VenueData(
            arena: "Wells Fargo Center", arenaCapacity: 20_478, sportTeam: "76ers vs Celtics",
            stadium: "Lincoln Financial Field", stadiumCapacity: 69_176, stadiumEvent: "Eagles Game",
            concertVenue: "The Fillmore Philadelphia", concertCapacity: 2_500
        )
        case "OH": return VenueData(
            arena: "Rocket Mortgage FieldHouse", arenaCapacity: 20_562, sportTeam: "Cavaliers vs Bulls",
            stadium: "Cleveland Browns Stadium", stadiumCapacity: 67_431, stadiumEvent: "Browns Game",
            concertVenue: "House of Blues Cleveland", concertCapacity: 2_000
        )
        case "MA": return VenueData(
            arena: "TD Garden", arenaCapacity: 19_156, sportTeam: "Celtics vs 76ers",
            stadium: "Gillette Stadium", stadiumCapacity: 65_878, stadiumEvent: "Patriots Game",
            concertVenue: "House of Blues Boston", concertCapacity: 2_500
        )
        default: return VenueData(
            arena: "City Arena", arenaCapacity: 18_000, sportTeam: "Pro Basketball Game",
            stadium: "Metro Stadium", stadiumCapacity: 60_000, stadiumEvent: "Pro Football Game",
            concertVenue: "Downtown Music Hall", concertCapacity: 3_000
        )
        }
    }

    private static func nextWeekend(from date: Date) -> Date {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let daysToSat = (7 - weekday) % 7
        return calendar.date(byAdding: .day, value: daysToSat == 0 ? 7 : daysToSat, to: date) ?? date
    }
}
