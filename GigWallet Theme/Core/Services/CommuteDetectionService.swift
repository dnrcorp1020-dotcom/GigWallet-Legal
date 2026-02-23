import Foundation
import CoreLocation

/// Detects commute trips by learning the user's home location over time.
/// After 3+ trips starting from the same area (within 200m) during morning hours (5-9 AM),
/// the location is cemented as "home." First trip of the day from home → commute (not deductible).
@MainActor @Observable
final class CommuteDetectionService: @unchecked Sendable {
    static let shared = CommuteDetectionService()

    // MARK: - State

    /// Learned home coordinate (nil until enough data collected)
    var homeLatitude: Double? {
        get { UserDefaults.standard.object(forKey: "commuteHome_lat") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "commuteHome_lat") }
    }

    var homeLongitude: Double? {
        get { UserDefaults.standard.object(forKey: "commuteHome_lon") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "commuteHome_lon") }
    }

    /// Reverse-geocoded home address for display
    var homeAddressString: String {
        get { UserDefaults.standard.string(forKey: "commuteHome_address") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "commuteHome_address") }
    }

    /// Has home been cemented (3+ morning trips from same location)?
    var hasLearnedHome: Bool {
        homeLatitude != nil && homeLongitude != nil
    }

    // MARK: - Private

    private let morningStartCandidatesKey = "commuteHome_morningCandidates"
    private let homeRadiusMeters: Double = 200
    private let requiredMorningTrips = 3

    private init() {}

    // MARK: - Public API

    /// Call after each trip to teach the service where "home" might be.
    /// If the trip started between 5-9 AM, we track that start location.
    /// After 3+ trips from the same cluster → cement as home.
    func learnHomeAddress(from startLocation: CLLocation, tripStartTime: Date) {
        let hour = Calendar.current.component(.hour, from: tripStartTime)
        guard hour >= 5 && hour < 9 else { return }

        // Add candidate
        var candidates = loadCandidates()
        candidates.append(LocationCandidate(
            latitude: startLocation.coordinate.latitude,
            longitude: startLocation.coordinate.longitude,
            timestamp: tripStartTime.timeIntervalSince1970
        ))
        saveCandidates(candidates)

        // Check if any cluster has 3+ entries
        let cluster = findLargestCluster(candidates)
        if cluster.count >= requiredMorningTrips {
            // Cement home location as centroid of cluster
            let avgLat = cluster.reduce(0.0) { $0 + $1.latitude } / Double(cluster.count)
            let avgLon = cluster.reduce(0.0) { $0 + $1.longitude } / Double(cluster.count)

            homeLatitude = avgLat
            homeLongitude = avgLon

            // Reverse geocode for display
            Task {
                let geocoder = CLGeocoder()
                let location = CLLocation(latitude: avgLat, longitude: avgLon)
                if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                    let street = placemark.thoroughfare ?? ""
                    let city = placemark.locality ?? ""
                    homeAddressString = [street, city].filter { !$0.isEmpty }.joined(separator: ", ")
                }
            }
        }
    }

    /// Check whether a trip starting at this location is a commute.
    /// Commute = within 200m of home AND first trip of the day.
    func isCommuteTrip(startLocation: CLLocation) -> Bool {
        guard let homeLat = homeLatitude, let homeLon = homeLongitude else {
            return false
        }

        let homeLocation = CLLocation(latitude: homeLat, longitude: homeLon)
        let distanceFromHome = startLocation.distance(from: homeLocation)

        // Must be within home radius
        guard distanceFromHome <= homeRadiusMeters else { return false }

        // Check if this is the first trip today
        let todayKey = "commuteHome_lastTripDate"
        let today = Calendar.current.startOfDay(for: .now)
        let lastTripDateInterval = UserDefaults.standard.double(forKey: todayKey)

        if lastTripDateInterval > 0 {
            let lastTripDate = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: lastTripDateInterval))
            if lastTripDate == today {
                return false // Already had a trip today — not commute
            }
        }

        // Mark today as having a trip
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: todayKey)
        return true
    }

    /// Reset learned home (for testing or user preference)
    func resetHome() {
        homeLatitude = nil
        homeLongitude = nil
        homeAddressString = ""
        UserDefaults.standard.removeObject(forKey: morningStartCandidatesKey)
    }

    // MARK: - Private Helpers

    private struct LocationCandidate: Codable {
        let latitude: Double
        let longitude: Double
        let timestamp: TimeInterval
    }

    private func loadCandidates() -> [LocationCandidate] {
        guard let data = UserDefaults.standard.data(forKey: morningStartCandidatesKey),
              let candidates = try? JSONDecoder().decode([LocationCandidate].self, from: data) else {
            return []
        }
        return candidates
    }

    private func saveCandidates(_ candidates: [LocationCandidate]) {
        if let data = try? JSONEncoder().encode(candidates) {
            UserDefaults.standard.set(data, forKey: morningStartCandidatesKey)
        }
    }

    /// Simple clustering: find the largest group of candidates within homeRadiusMeters of each other.
    private func findLargestCluster(_ candidates: [LocationCandidate]) -> [LocationCandidate] {
        var bestCluster: [LocationCandidate] = []

        for candidate in candidates {
            let center = CLLocation(latitude: candidate.latitude, longitude: candidate.longitude)
            let cluster = candidates.filter { other in
                let otherLoc = CLLocation(latitude: other.latitude, longitude: other.longitude)
                return center.distance(from: otherLoc) <= homeRadiusMeters
            }
            if cluster.count > bestCluster.count {
                bestCluster = cluster
            }
        }

        return bestCluster
    }
}
