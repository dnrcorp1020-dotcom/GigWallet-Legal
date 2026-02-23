import Foundation
import CoreLocation
import CoreMotion
import SwiftUI
import UserNotifications

/// Automatic GPS mileage tracking for gig workers.
///
/// Uses CoreMotion driving activity detection + CLLocationManager to
/// automatically detect trips and calculate distances. Battery-efficient:
/// only collects high-accuracy locations while driving is actively detected.
///
/// Key differentiators:
/// - Auto-detects driving activity (no manual start/stop required)
/// - IRS business vs commute classification built in
///
/// Flow:
/// 1. CMMotionActivityManager detects automotive activity
/// 2. CLLocationManager starts collecting locations
/// 3. Driving stops (5 min stationary) → trip ends
/// 4. Distance calculated, start/end reverse-geocoded
/// 5. PendingTrip created for user review
@MainActor @Observable
final class MileageTrackingService: NSObject, @unchecked Sendable {
    static let shared = MileageTrackingService()

    // MARK: - Types

    struct PendingTrip: Identifiable {
        let id = UUID()
        let startTime: Date
        let endTime: Date
        let distanceMiles: Double
        var startAddress: String
        var endAddress: String
        var platform: GigPlatformType
        var isBusinessMiles: Bool
        let routeLocations: [CLLocationCoordinate2D]
    }

    enum TrackingState: String {
        case idle = "Idle"
        case detecting = "Detecting"
        case tracking = "Tracking"
        case stopped = "Stopped"

        var sfSymbol: String {
            switch self {
            case .idle: return "location.slash"
            case .detecting: return "location.magnifyingglass"
            case .tracking: return "location.fill"
            case .stopped: return "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .idle: return BrandColors.textTertiary
            case .detecting: return BrandColors.info
            case .tracking: return BrandColors.success
            case .stopped: return BrandColors.primary
            }
        }
    }

    // MARK: - State

    var isEnabled = false
    var trackingState: TrackingState = .idle
    var pendingTrips: [PendingTrip] = []
    var currentTripDistance: Double = 0 // miles while tracking
    var locationAuthStatus: CLAuthorizationStatus = .notDetermined

    /// Whether location permissions allow tracking
    var hasLocationPermission: Bool {
        locationAuthStatus == .authorizedAlways || locationAuthStatus == .authorizedWhenInUse
    }

    /// Whether motion activity is available on this device
    var isMotionAvailable: Bool {
        CMMotionActivityManager.isActivityAvailable()
    }

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionActivityManager()
    private let geocoder = CLGeocoder()

    private var collectedLocations: [CLLocation] = []
    private var tripStartTime: Date?
    private var lastDrivingDetected: Date?
    private let stationaryTimeout: TimeInterval = 300 // 5 minutes

    private var stationaryTimer: Timer?

    // MARK: - Init

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.activityType = .automotiveNavigation
        locationAuthStatus = locationManager.authorizationStatus
    }

    // MARK: - Public API

    /// Request location permission (Always authorization for background tracking)
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Auto-start tracking if user previously enabled it.
    /// Called from MainTabView on app launch.
    func autoStartIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "mileageAutoTrackingEnabled") else { return }
        guard hasLocationPermission else { return }

        if !isEnabled {
            startTracking()
        }
    }

    /// Start auto-tracking — monitors for driving activity
    func startTracking() {
        guard hasLocationPermission else {
            requestPermission()
            return
        }
        isEnabled = true
        trackingState = .detecting

        // Start motion activity monitoring
        startMotionDetection()
    }

    /// Stop auto-tracking
    func stopTracking() {
        isEnabled = false
        trackingState = .idle
        motionManager.stopActivityUpdates()
        locationManager.stopUpdatingLocation()
        stationaryTimer?.invalidate()
        stationaryTimer = nil

        // If we have an active trip, finalize it
        if !collectedLocations.isEmpty {
            finalizeCurrentTrip()
        }
    }

    /// Confirm a pending trip — creates MileageTrip in SwiftData
    func confirmTrip(_ trip: PendingTrip) -> (MileageTrip, ExpenseEntry?) {
        let mileageTrip = MileageTrip(
            miles: trip.distanceMiles,
            purpose: trip.isBusinessMiles ? "Auto-detected trip" : "Commute",
            startLocation: trip.startAddress,
            endLocation: trip.endAddress,
            tripDate: trip.startTime,
            platform: trip.platform,
            isBusinessMiles: trip.isBusinessMiles
        )

        var expense: ExpenseEntry? = nil
        if trip.isBusinessMiles {
            expense = ExpenseEntry(
                amount: trip.distanceMiles * TaxEngine.TaxConstants.mileageRate,
                category: .mileage,
                vendor: "Mileage - \(String(format: "%.1f", trip.distanceMiles)) mi",
                description: "Auto-tracked trip",
                expenseDate: trip.startTime,
                deductionPercentage: 100,
                mileage: trip.distanceMiles
            )
        }

        // Remove from pending
        pendingTrips.removeAll { $0.id == trip.id }
        return (mileageTrip, expense)
    }

    /// Dismiss a pending trip
    func dismissTrip(_ trip: PendingTrip) {
        pendingTrips.removeAll { $0.id == trip.id }
    }

    /// Confirm all pending trips as business miles
    func confirmAllAsBusinessTrips() -> [(MileageTrip, ExpenseEntry?)] {
        // Snapshot trips before iterating — confirmTrip() removes from pendingTrips
        let tripsToConfirm = pendingTrips.map { trip -> PendingTrip in
            var mutableTrip = trip
            mutableTrip.isBusinessMiles = true
            return mutableTrip
        }
        var results: [(MileageTrip, ExpenseEntry?)] = []
        for trip in tripsToConfirm {
            results.append(confirmTrip(trip))
        }
        return results
    }

    // MARK: - Private — Motion Detection

    private func startMotionDetection() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            // Simulator doesn't support CoreMotion — use location-only tracking mode.
            // On real devices, CoreMotion driving detection triggers location collection.
            // Without motion data, we start location tracking immediately and
            // rely on significant distance changes to detect trip starts/stops.
            trackingState = .detecting
            locationManager.startUpdatingLocation()
            return
        }

        motionManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }

            Task { @MainActor in
                if activity.automotive {
                    self.onDrivingDetected()
                } else if activity.stationary || activity.walking {
                    self.onStationaryDetected()
                }
            }
        }
    }

    private func onDrivingDetected() {
        lastDrivingDetected = .now
        stationaryTimer?.invalidate()

        if trackingState != .tracking {
            // Start collecting locations
            trackingState = .tracking
            tripStartTime = .now
            collectedLocations = []
            currentTripDistance = 0
            locationManager.startUpdatingLocation()
        }
    }

    private func onStationaryDetected() {
        guard trackingState == .tracking else { return }

        // Start stationary timer — if still stationary after 5 min, end trip
        if stationaryTimer == nil {
            stationaryTimer = Timer.scheduledTimer(withTimeInterval: stationaryTimeout, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.finalizeCurrentTrip()
                }
            }
        }
    }

    private func finalizeCurrentTrip() {
        guard collectedLocations.count >= 2 else {
            resetTracking()
            return
        }

        let distance = calculateTotalDistance()
        let miles = distance / 1609.34

        // Only create trip if meaningful distance (> 0.5 mile)
        guard miles > 0.5 else {
            resetTracking()
            return
        }

        guard let firstLocation = collectedLocations.first,
              let lastLocation = collectedLocations.last else {
            resetTracking()
            return
        }
        let startTime = tripStartTime ?? firstLocation.timestamp
        let endTime = lastLocation.timestamp
        let coordinates = collectedLocations.map { $0.coordinate }

        // Commute detection: check if trip starts near home
        let commuteService = CommuteDetectionService.shared
        let isCommute = commuteService.isCommuteTrip(startLocation: firstLocation)

        // Teach home address from this trip
        commuteService.learnHomeAddress(from: firstLocation, tripStartTime: startTime)

        let roundedMiles = round(miles * 10) / 10

        var pendingTrip = PendingTrip(
            startTime: startTime,
            endTime: endTime,
            distanceMiles: roundedMiles,
            startAddress: "Resolving...",
            endAddress: "Resolving...",
            platform: .other,
            isBusinessMiles: !isCommute,
            routeLocations: coordinates
        )

        // Reverse geocode start and end
        if let firstLoc = collectedLocations.first,
           let lastLoc = collectedLocations.last {
            Task {
                pendingTrip.startAddress = await reverseGeocode(firstLoc) ?? "Unknown"
                pendingTrip.endAddress = await reverseGeocode(lastLoc) ?? "Unknown"

                // Find and update the trip in pendingTrips
                if let index = self.pendingTrips.firstIndex(where: { $0.id == pendingTrip.id }) {
                    self.pendingTrips[index] = pendingTrip
                }
            }
        }

        pendingTrips.append(pendingTrip)

        // Send local notification about the completed trip
        sendTripNotification(miles: roundedMiles, isCommute: isCommute)

        resetTracking()
    }

    private func calculateTotalDistance() -> Double {
        var total: Double = 0
        for i in 1..<collectedLocations.count {
            let prev = collectedLocations[i - 1]
            let curr = collectedLocations[i]
            total += curr.distance(from: prev)
        }
        return total
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let street = placemark.thoroughfare ?? ""
                let city = placemark.locality ?? ""
                if !street.isEmpty && !city.isEmpty {
                    return "\(street), \(city)"
                } else if !city.isEmpty {
                    return city
                } else if !street.isEmpty {
                    return street
                }
            }
        } catch {
            // Geocoding failed — return nil
        }
        return nil
    }

    private func sendTripNotification(miles: Double, isCommute: Bool) {
        let content = UNMutableNotificationContent()
        content.title = isCommute ? "Commute Trip Logged" : "Trip Recorded \u{1F697}"
        let deduction = miles * TaxEngine.TaxConstants.mileageRate
        if isCommute {
            content.body = "\(String(format: "%.1f", miles)) miles (commute \u{2014} not deductible)"
        } else {
            content.body = "\(String(format: "%.1f", miles)) miles \u{00B7} \(CurrencyFormatter.format(deduction)) deduction"
        }
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func resetTracking() {
        locationManager.stopUpdatingLocation()
        stationaryTimer?.invalidate()
        stationaryTimer = nil
        collectedLocations = []
        tripStartTime = nil
        currentTripDistance = 0
        trackingState = isEnabled ? .detecting : .idle
    }

    // MARK: - Mock Data (Development)

    /// Generate a mock pending trip for testing in the simulator.
    private func generateMockPendingTrip() {
        let calendar = Calendar.current
        let startTime = calendar.date(byAdding: .hour, value: -2, to: .now) ?? .now
        let endTime = calendar.date(byAdding: .hour, value: -1, to: .now) ?? .now

        let trip = PendingTrip(
            startTime: startTime,
            endTime: endTime,
            distanceMiles: 12.4,
            startAddress: "123 Main St, Downtown",
            endAddress: "456 Oak Ave, Midtown",
            platform: .uber,
            isBusinessMiles: true,
            routeLocations: []
        )

        let trip2 = PendingTrip(
            startTime: calendar.date(byAdding: .hour, value: -4, to: .now) ?? .now,
            endTime: calendar.date(byAdding: .hour, value: -3, to: .now) ?? .now,
            distanceMiles: 8.7,
            startAddress: "789 Park Blvd, Uptown",
            endAddress: "321 Elm St, Suburb",
            platform: .doordash,
            isBusinessMiles: true,
            routeLocations: []
        )

        pendingTrips = [trip, trip2]
        trackingState = .detecting
    }
}

// MARK: - CLLocationManagerDelegate

extension MileageTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                // Filter out inaccurate readings
                guard location.horizontalAccuracy < 50 else { continue }

                self.collectedLocations.append(location)

                // Update running distance
                if self.collectedLocations.count >= 2 {
                    let prev = self.collectedLocations[self.collectedLocations.count - 2]
                    let meters = location.distance(from: prev)
                    self.currentTripDistance += meters / 1609.34
                }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationAuthStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location errors are expected in some conditions; silently handle
    }
}
