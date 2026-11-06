import CoreLocation
import MapKit
import Observation
import WeatherKit
import os

struct DayForecast: Hashable {
    let date: Date
    let symbolName: String
    let high: String
    let low: String
    let condition: String
    var precipitation: String?
    var wind: String?
    var uvIndex: String?
    var sunrise: Date?
    var sunset: Date?
}

struct WeatherCredit: Hashable {
    var lightMark: URL?
    var darkMark: URL?
    var label = L.weatherAttribution
    let legalPage: URL
}

nonisolated private struct OpenMeteoResponse: Decodable, Sendable {
    struct Daily: Decodable, Sendable {
        let time: Array<String>
        let weatherCodes: Array<Int?>
        let highs: Array<Double?>
        let lows: Array<Double?>
        let precipitation: Array<Double?>
        let wind: Array<Double?>
        let uvIndex: Array<Double?>
        let sunrise: Array<String?>
        let sunset: Array<String?>

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCodes = "weather_code"
            case highs = "temperature_2m_max"
            case lows = "temperature_2m_min"
            case precipitation = "precipitation_probability_max"
            case wind = "wind_speed_10m_max"
            case uvIndex = "uv_index_max"
            case sunrise
            case sunset
        }
    }
    let timezone: String
    let daily: Daily
}

nonisolated private let weatherLog = Logger(subsystem: "com.firatciftci.Daybar", category: "weather")

@Observable
final class WeatherModel: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherModel()

    private(set) var forecasts: [Date: DayForecast] = [:]
    private(set) var credit: WeatherCredit?
    private(set) var locationDenied = false
    private(set) var placeName: String?

    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastFetch: Date?
    @ObservationIgnored private var lastLocation: CLLocation?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func forecast(for day: Date) -> DayForecast? {
        guard prefs.showWeather else { return nil }
        return forecasts[day.startOfDay]
    }

    func refresh(force: Bool = false) {
        guard prefs.showWeather else {
            forecasts = [:]
            return
        }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 3_600, !forecasts.isEmpty {
            return
        }
        if prefs.useCurrentLocation {
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                locationDenied = true
            default:
                locationDenied = false
                manager.requestLocation()
            }
        } else if let place = prefs.weatherPlace {
            placeName = place.name
            fetch(for: CLLocation(latitude: place.latitude, longitude: place.longitude))
        }
    }

    func lookUp(city: String) async -> WeatherPlace? {
        guard let request = MKGeocodingRequest(addressString: city) else { return nil }
        guard let item = try? await request.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return WeatherPlace(name: item.name ?? city, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func fetch(for location: CLLocation) {
        lastLocation = location
        Task {
            do {
                let daily = try await WeatherService.shared.weather(for: location, including: .daily)
                var map: [Date: DayForecast] = [:]
                let style = Measurement<UnitTemperature>.FormatStyle(
                    width: .narrow,
                    usage: .weather,
                    numberFormatStyle: .number.precision(.fractionLength(0))
                )
                for day in daily {
                    map[day.date.startOfDay] = DayForecast(
                        date: day.date.startOfDay,
                        symbolName: day.symbolName,
                        high: day.highTemperature.formatted(style),
                        low: day.lowTemperature.formatted(style),
                        condition: day.condition.description,
                        precipitation: day.precipitationChance.formatted(Self.percentStyle),
                        wind: day.wind.speed.formatted(Self.windStyle),
                        uvIndex: Self.uvText(day.uvIndex.value),
                        sunrise: day.sun.sunrise,
                        sunset: day.sun.sunset
                    )
                }
                forecasts = map
                lastFetch = .now
                if credit == nil {
                    let attribution = try await WeatherService.shared.attribution
                    credit = WeatherCredit(
                        lightMark: attribution.combinedMarkLightURL,
                        darkMark: attribution.combinedMarkDarkURL,
                        legalPage: attribution.legalPageURL
                    )
                }
            } catch {
                weatherLog.error("WeatherKit failed, using Open-Meteo: \(error.localizedDescription, privacy: .public)")
                await fetchOpenMeteo(for: location)
            }
        }
    }

    private func fetchOpenMeteo(for location: CLLocation) async {
        let latitude = (location.coordinate.latitude * 100).rounded() / 100
        let longitude = (location.coordinate.longitude * 100).rounded() / 100
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(
                name: "daily",
                value:
                    "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,uv_index_max,sunrise,sunset"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "14"),
        ]
        guard let url = components?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let daily = response.daily
            let clock = DateFormatter()
            clock.locale = Locale(identifier: "en_US_POSIX")
            clock.dateFormat = "yyyy-MM-dd'T'HH:mm"
            clock.timeZone = TimeZone(identifier: response.timezone) ?? .current
            let style = Measurement<UnitTemperature>.FormatStyle(
                width: .narrow,
                usage: .weather,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
            let calendar = Calendar.current
            var map: [Date: DayForecast] = [:]
            for (index, stamp) in daily.time.enumerated() {
                let parts = stamp.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3,
                    let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                    let code = daily.weatherCodes[safe: index].flatMap(\.self),
                    let high = daily.highs[safe: index].flatMap(\.self),
                    let low = daily.lows[safe: index].flatMap(\.self)
                else { continue }
                let condition = Self.condition(for: code)
                map[date.startOfDay] = DayForecast(
                    date: date.startOfDay,
                    symbolName: condition.symbol,
                    high: Measurement(value: high, unit: UnitTemperature.celsius).formatted(style),
                    low: Measurement(value: low, unit: UnitTemperature.celsius).formatted(style),
                    condition: condition.name,
                    precipitation: daily.precipitation[safe: index].flatMap(\.self).map { ($0 / 100).formatted(Self.percentStyle) },
                    wind: daily.wind[safe: index].flatMap(\.self).map {
                        Measurement(value: $0, unit: UnitSpeed.kilometersPerHour).formatted(Self.windStyle)
                    },
                    uvIndex: daily.uvIndex[safe: index].flatMap(\.self).map { Self.uvText(Int($0.rounded())) },
                    sunrise: daily.sunrise[safe: index].flatMap(\.self).flatMap(clock.date(from:)),
                    sunset: daily.sunset[safe: index].flatMap(\.self).flatMap(clock.date(from:))
                )
            }
            forecasts = map
            lastFetch = .now
            if let legal = URL(string: "https://open-meteo.com/") {
                credit = WeatherCredit(label: L.openMeteoCredit, legalPage: legal)
            }
        } catch {
            lastFetch = nil
            weatherLog.error("Open-Meteo failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static let percentStyle = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))

    private static let windStyle = Measurement<UnitSpeed>.FormatStyle(
        width: .abbreviated,
        usage: .wind,
        numberFormatStyle: .number.precision(.fractionLength(0))
    )

    private static func uvText(_ value: Int) -> String {
        let category =
            switch value {
            case ..<3: L.uvLow
            case 3..<6: L.uvModerate
            case 6..<8: L.uvHigh
            case 8..<11: L.uvVeryHigh
            default: L.uvExtreme
            }
        return "\(value) \(category)"
    }

    private static func condition(for code: Int) -> (symbol: String, name: String) {
        switch code {
        case 0: ("sun.max.fill", L.conditionClear)
        case 1: ("sun.max.fill", L.conditionMostlyClear)
        case 2: ("cloud.sun.fill", L.conditionPartlyCloudy)
        case 3: ("cloud.fill", L.conditionCloudy)
        case 45, 48: ("cloud.fog.fill", L.conditionFog)
        case 51, 53, 55: ("cloud.drizzle.fill", L.conditionDrizzle)
        case 56, 57: ("cloud.sleet.fill", L.conditionFreezingDrizzle)
        case 61: ("cloud.drizzle.fill", L.conditionLightRain)
        case 63: ("cloud.rain.fill", L.conditionRain)
        case 65: ("cloud.heavyrain.fill", L.conditionHeavyRain)
        case 66, 67: ("cloud.sleet.fill", L.conditionFreezingRain)
        case 71, 73, 77: ("cloud.snow.fill", L.conditionSnow)
        case 75: ("snowflake", L.conditionHeavySnow)
        case 80, 81, 82: ("cloud.sun.rain.fill", L.conditionShowers)
        case 85, 86: ("cloud.snow.fill", L.conditionSnowShowers)
        case 95: ("cloud.bolt.rain.fill", L.conditionThunderstorms)
        case 96, 99: ("cloud.hail.fill", L.conditionHail)
        default: ("cloud.fill", L.conditionCloudy)
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: Array<CLLocation>) {
        guard let coordinate = locations.last?.coordinate else { return }
        MainActor.assumeIsolated {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if let lastLocation, lastLocation.distance(from: location) < 5_000, !forecasts.isEmpty, lastFetch != nil {
                return
            }
            fetch(for: location)
            Task {
                let request = MKReverseGeocodingRequest(location: location)
                placeName = try? await request?.mapItems.first?.addressRepresentations?.cityName
            }
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError error: any Error) {
        weatherLog.error("Location failed: \(error.localizedDescription, privacy: .public)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        MainActor.assumeIsolated {
            let status = self.manager.authorizationStatus
            locationDenied = [.denied, .restricted].contains(status)
            if !locationDenied, status != .notDetermined, prefs.useCurrentLocation, prefs.showWeather {
                self.manager.requestLocation()
            }
        }
    }
}
