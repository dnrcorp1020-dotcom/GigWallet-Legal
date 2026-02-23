import Foundation
import SwiftUI
import CoreLocation

/// Detects weather conditions that create earning opportunities for gig workers.
/// Rain = delivery demand up. Snow = rideshare surge. Extreme heat = everyone orders in.
///
/// Uses the free National Weather Service (NWS) API — no API key required, US-only.
/// Falls back to season-based estimates when location or network unavailable.
///
/// Integrates weather directly into the Work Advisor AI recommendation engine.
@MainActor @Observable
final class WeatherBoostService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WeatherBoostService()

    // MARK: - Types

    struct WeatherForecast: Identifiable {
        let id = UUID()
        let condition: WeatherCondition
        let temperature: Int // Fahrenheit
        let timeRange: String // e.g. "Tonight"
        let demandImpact: DemandImpact
        let message: String
    }

    enum WeatherCondition: String {
        case clear = "Clear"
        case cloudy = "Cloudy"
        case rain = "Rain"
        case heavyRain = "Heavy Rain"
        case snow = "Snow"
        case extremeHeat = "Extreme Heat"
        case extremeCold = "Extreme Cold"
        case storm = "Storm"
        case windy = "Windy"
        case fog = "Fog"

        var sfSymbol: String {
            switch self {
            case .clear: return "sun.max.fill"
            case .cloudy: return "cloud.fill"
            case .rain: return "cloud.rain.fill"
            case .heavyRain: return "cloud.heavyrain.fill"
            case .snow: return "cloud.snow.fill"
            case .extremeHeat: return "thermometer.sun.fill"
            case .extremeCold: return "thermometer.snowflake"
            case .storm: return "cloud.bolt.rain.fill"
            case .windy: return "wind"
            case .fog: return "cloud.fog.fill"
            }
        }

        var color: Color {
            switch self {
            case .clear: return BrandColors.warning
            case .cloudy: return BrandColors.textSecondary
            case .rain, .heavyRain: return BrandColors.info
            case .snow: return Color(hex: "87CEEB")
            case .extremeHeat: return BrandColors.destructive
            case .extremeCold: return BrandColors.info
            case .storm: return BrandColors.destructive
            case .windy: return BrandColors.textSecondary
            case .fog: return BrandColors.textTertiary
            }
        }
    }

    enum DemandImpact: String {
        case noChange = "Normal"
        case slightIncrease = "Slightly Up"
        case increase = "Up"
        case surge = "Surge"

        var color: Color {
            switch self {
            case .noChange: return BrandColors.textSecondary
            case .slightIncrease: return BrandColors.success
            case .increase: return BrandColors.primary
            case .surge: return BrandColors.destructive
            }
        }

        var percentageText: String {
            switch self {
            case .noChange: return ""
            case .slightIncrease: return "+15%"
            case .increase: return "+30-40%"
            case .surge: return "+50-100%"
            }
        }
    }

    // MARK: - State

    var currentCondition: WeatherCondition = .clear
    var currentTemperature: Int = 72
    var forecasts: [WeatherForecast] = []
    var isLoading = false
    var lastFetched: Date?
    var locationName: String = ""
    var isUsingRealData = false

    private let locationManager = CLLocationManager()
    private(set) var currentLocation: CLLocation?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    /// The most impactful weather condition in the next 12 hours.
    var topForecast: WeatherForecast? {
        forecasts.first(where: { $0.demandImpact != .noChange }) ?? forecasts.first
    }

    /// Whether current weather is boosting gig demand.
    var hasActiveBoost: Bool {
        topForecast?.demandImpact != .noChange && topForecast?.demandImpact != nil
    }

    /// Short recommendation string for the Work Advisor.
    var workAdvisorNote: String? {
        guard let top = topForecast else { return nil }
        return top.message
    }

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }

    // MARK: - Public API

    /// Request location permission if not yet determined.
    func requestLocationPermissionIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Fetch weather forecast for the user's area.
    /// Uses NWS API with real location, falls back to state-based estimates.
    func fetchWeather(stateCode: String) async {
        isLoading = true
        defer { isLoading = false }

        // Try to get location
        if currentLocation == nil {
            let status = locationManager.authorizationStatus
            if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
                // Give a moment for the permission dialog
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            if locationManager.authorizationStatus == .authorizedWhenInUse
                || locationManager.authorizationStatus == .authorizedAlways {
                let loc = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
                    self.locationContinuation = continuation
                    self.locationManager.requestLocation()
                }
                if let loc { currentLocation = loc }
            }
        }

        // Try NWS API with real location
        if let location = currentLocation {
            do {
                try await fetchFromNWS(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                isUsingRealData = true
                lastFetched = .now
                return
            } catch {
                // Fall through to fallback
            }
        }

        // Fallback: season + state based estimates
        generateFallbackForecasts(season: currentSeason(), stateCode: stateCode)
        isUsingRealData = false
        lastFetched = .now
    }

    // MARK: - NWS API (Free, No Key Required)

    private func fetchFromNWS(latitude: Double, longitude: Double) async throws {
        // Step 1: Get grid point from lat/lon
        let lat = String(format: "%.4f", latitude)
        let lon = String(format: "%.4f", longitude)
        guard let pointURL = URL(string: "https://api.weather.gov/points/\(lat),\(lon)") else {
            throw WeatherError.apiError
        }

        var pointRequest = URLRequest(url: pointURL)
        pointRequest.setValue("GigWallet/1.0 (support@gigwallet.app)", forHTTPHeaderField: "User-Agent")
        pointRequest.timeoutInterval = 10

        let (pointData, pointResponse) = try await URLSession.shared.data(for: pointRequest)
        guard let httpResponse = pointResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherError.apiError
        }

        guard let pointJSON = try? JSONSerialization.jsonObject(with: pointData) as? [String: Any],
              let properties = pointJSON["properties"] as? [String: Any],
              let forecastURLString = properties["forecast"] as? String,
              let forecastURL = URL(string: forecastURLString) else {
            throw WeatherError.parseError
        }

        // Extract location name
        if let relativeLocation = properties["relativeLocation"] as? [String: Any],
           let locProps = relativeLocation["properties"] as? [String: Any],
           let city = locProps["city"] as? String,
           let state = locProps["state"] as? String {
            locationName = "\(city), \(state)"
        }

        // Step 2: Get forecast
        var forecastRequest = URLRequest(url: forecastURL)
        forecastRequest.setValue("GigWallet/1.0 (support@gigwallet.app)", forHTTPHeaderField: "User-Agent")
        forecastRequest.timeoutInterval = 10

        let (forecastData, forecastResponse) = try await URLSession.shared.data(for: forecastRequest)
        guard let fResp = forecastResponse as? HTTPURLResponse, fResp.statusCode == 200 else {
            throw WeatherError.apiError
        }

        guard let forecastJSON = try? JSONSerialization.jsonObject(with: forecastData) as? [String: Any],
              let forecastProps = forecastJSON["properties"] as? [String: Any],
              let periods = forecastProps["periods"] as? [[String: Any]] else {
            throw WeatherError.parseError
        }

        parseNWSPeriods(periods)
    }

    private func parseNWSPeriods(_ periods: [[String: Any]]) {
        var newForecasts: [WeatherForecast] = []

        for (index, period) in periods.prefix(4).enumerated() {
            guard let temp = period["temperature"] as? Int,
                  let shortForecast = period["shortForecast"] as? String,
                  let periodName = period["name"] as? String else { continue }

            let windSpeed = period["windSpeed"] as? String ?? ""
            let condition = parseCondition(from: shortForecast, temperature: temp, windSpeed: windSpeed)
            let impact = assessDemandImpact(condition: condition, temperature: temp)
            let message = generateMessage(condition: condition, temperature: temp, impact: impact, periodName: periodName)

            if index == 0 {
                currentCondition = condition
                currentTemperature = temp
            }

            newForecasts.append(WeatherForecast(
                condition: condition,
                temperature: temp,
                timeRange: periodName,
                demandImpact: impact,
                message: message
            ))
        }

        forecasts = newForecasts
    }

    private func parseCondition(from forecast: String, temperature: Int, windSpeed: String) -> WeatherCondition {
        let lower = forecast.lowercased()

        if lower.contains("thunderstorm") || lower.contains("severe") || lower.contains("tornado") { return .storm }
        if lower.contains("snow") || lower.contains("blizzard") || lower.contains("ice") || lower.contains("sleet") { return .snow }
        if lower.contains("heavy rain") || lower.contains("flood") { return .heavyRain }
        if lower.contains("rain") || lower.contains("drizzle") || lower.contains("shower") { return .rain }
        if lower.contains("fog") || lower.contains("mist") || lower.contains("haze") { return .fog }

        let windNum = Int(windSpeed.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        if windNum > 30 { return .windy }

        if temperature >= 100 { return .extremeHeat }
        if temperature <= 20 { return .extremeCold }
        if lower.contains("cloudy") || lower.contains("overcast") { return .cloudy }

        return .clear
    }

    private func assessDemandImpact(condition: WeatherCondition, temperature: Int) -> DemandImpact {
        switch condition {
        case .storm, .heavyRain: return .surge
        case .snow: return .surge
        case .extremeHeat: return temperature >= 110 ? .surge : .increase
        case .extremeCold: return .increase
        case .rain: return .increase
        case .windy: return .slightIncrease
        case .fog: return .slightIncrease
        case .cloudy, .clear: return .noChange
        }
    }

    private func generateMessage(condition: WeatherCondition, temperature: Int, impact: DemandImpact, periodName: String) -> String {
        let loc = locationName.isEmpty ? "" : " in \(locationName)"
        switch condition {
        case .storm: return "\(periodName): Storms expected\(loc) \u{2014} surge pricing likely"
        case .heavyRain: return "\(periodName): Heavy rain\(loc) \u{2014} delivery demand +50-100%"
        case .snow: return "\(periodName): Snow\(loc) \u{2014} massive demand, fewer drivers"
        case .rain: return "\(periodName): Rain expected\(loc) \u{2014} delivery demand +30-40%"
        case .extremeHeat: return "\(periodName): \(temperature)\u{00B0}F\(loc) \u{2014} everyone's ordering in"
        case .extremeCold: return "\(periodName): \(temperature)\u{00B0}F\(loc) \u{2014} demand up, fewer drivers"
        case .windy: return "\(periodName): Windy\(loc) \u{2014} bikes off road, cars benefit"
        case .fog: return "\(periodName): Fog\(loc) \u{2014} slightly fewer drivers"
        case .cloudy: return "\(periodName): Cloudy, \(temperature)\u{00B0}F\(loc) \u{2014} normal demand"
        case .clear: return "\(periodName): Clear, \(temperature)\u{00B0}F\(loc) \u{2014} normal demand"
        }
    }

    // MARK: - Fallback

    private func currentSeason() -> String {
        let month = Calendar.current.component(.month, from: .now)
        switch month {
        case 12, 1, 2: return "winter"
        case 3, 4, 5: return "spring"
        case 6, 7, 8: return "summer"
        default: return "fall"
        }
    }

    private func generateFallbackForecasts(season: String, stateCode: String) {
        switch season {
        case "winter":
            let hasSnow = ["NY", "IL", "MA", "MN", "CO", "MI", "WI", "OH", "PA", "CT"].contains(stateCode)
            if hasSnow {
                currentCondition = .snow; currentTemperature = 28
                forecasts = [
                    WeatherForecast(condition: .snow, temperature: 25, timeRange: "Evening", demandImpact: .surge,
                                    message: "Snow forecasted \u{2014} rideshare surge expected"),
                    WeatherForecast(condition: .extremeCold, temperature: 18, timeRange: "Tonight", demandImpact: .increase,
                                    message: "Bitter cold \u{2014} delivery demand up, fewer drivers")
                ]
            } else {
                currentCondition = .cloudy; currentTemperature = 55
                forecasts = [
                    WeatherForecast(condition: .cloudy, temperature: 52, timeRange: "Today", demandImpact: .noChange,
                                    message: "Cool and cloudy \u{2014} normal demand")
                ]
            }
        case "summer":
            let isHotState = ["TX", "AZ", "FL", "NV", "GA", "LA", "MS", "AL", "SC", "NM"].contains(stateCode)
            if isHotState {
                currentCondition = .extremeHeat; currentTemperature = 108
                forecasts = [
                    WeatherForecast(condition: .extremeHeat, temperature: 110, timeRange: "Afternoon", demandImpact: .surge,
                                    message: "Extreme heat \u{2014} everyone's ordering delivery")
                ]
            } else {
                currentCondition = .clear; currentTemperature = 82
                forecasts = [
                    WeatherForecast(condition: .clear, temperature: 82, timeRange: "All Day", demandImpact: .noChange,
                                    message: "Nice weather \u{2014} normal demand expected")
                ]
            }
        default:
            currentCondition = .cloudy; currentTemperature = 65
            forecasts = [
                WeatherForecast(condition: .cloudy, temperature: 65, timeRange: "Today", demandImpact: .noChange,
                                message: "Partly cloudy \u{2014} normal demand")
            ]
        }
    }

    enum WeatherError: Error {
        case apiError
        case parseError
    }
}
