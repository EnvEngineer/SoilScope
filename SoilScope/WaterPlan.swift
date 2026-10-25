import CoreLocation
import Foundation

enum Crop: String, CaseIterable, Identifiable {
    case lettuce, tomato, pepper, cucumber, strawberry, grape, other
    var id: String { rawValue }
    var title: String { self == .other ? "General" : rawValue.capitalized }
    var rootM: Double {
        switch self {
        case .lettuce: 0.25
        case .tomato: 0.60
        case .pepper: 0.45
        case .cucumber: 0.50
        case .strawberry: 0.30
        case .grape: 0.80
        case .other: 0.35
        }
    }
    var depletion: Double {
        switch self {
        case .lettuce, .strawberry: 0.30
        case .tomato, .pepper: 0.40
        case .cucumber, .other: 0.45
        case .grape: 0.50
        }
    }
    var coefficient: Double {
        switch self {
        case .lettuce, .cucumber, .other: 1.0
        case .tomato: 1.15
        case .pepper, .strawberry: 1.05
        case .grape: 0.85
        }
    }
}

enum Soil: String, CaseIterable, Identifiable {
    case sand, sandyLoam, loam, siltLoam, clayLoam, clay, raisedBedMix
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sandyLoam: "Sandy loam"
        case .siltLoam: "Silt loam"
        case .clayLoam: "Clay loam"
        case .raisedBedMix: "Raised-bed mix"
        default: rawValue.capitalized
        }
    }
    var capacity: Double {
        switch self {
        case .sand: 12
        case .sandyLoam: 25
        case .loam: 32
        case .siltLoam: 38
        case .clayLoam: 40
        case .clay: 45
        case .raisedBedMix: 35
        }
    }
    var wilting: Double {
        switch self {
        case .sand: 5
        case .sandyLoam: 10
        case .loam: 14
        case .siltLoam: 16
        case .clayLoam: 22
        case .clay: 30
        case .raisedBedMix: 15
        }
    }
}

struct Forecast {
    let rainMM: Double
    let highC: Double
    let et0MM: Double
    let fetchedAt: Date
}

private struct ForecastPayload: Decodable {
    struct Daily: Decodable {
        let rain_sum: [Double?]
        let temperature_2m_max: [Double?]
        let et0_fao_evapotranspiration: [Double?]
    }
    let daily: Daily
}

enum ForecastService {
    static func load(at location: CLLocation) async throws -> Forecast {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(location.coordinate.longitude)),
            URLQueryItem(name: "daily", value: "rain_sum,temperature_2m_max,et0_fao_evapotranspiration"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let daily = try JSONDecoder().decode(ForecastPayload.self, from: data).daily
        guard let rain = daily.rain_sum.first ?? nil,
              let high = daily.temperature_2m_max.first ?? nil,
              let et0 = daily.et0_fao_evapotranspiration.first ?? nil else {
            throw URLError(.cannotParseResponse)
        }
        return Forecast(rainMM: max(0, rain), highC: high, et0MM: max(0, et0), fetchedAt: Date())
    }
}

@MainActor
final class ForecastModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var forecast: Forecast?
    @Published var status = "Forecast not loaded"
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func refresh() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            status = "Waiting for location permission…"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            status = "Finding your location…"
            locationManager.requestLocation()
        case .restricted, .denied:
            status = "Enable location access in Settings to load local weather."
        @unknown default:
            status = "Location unavailable"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            refresh()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        status = "Loading local weather…"
        Task {
            do {
                forecast = try await ForecastService.load(at: location)
                status = "Forecast updated"
            } catch {
                forecast = nil
                status = "Weather unavailable: \(error.localizedDescription)"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Location unavailable: \(error.localizedDescription)"
    }
}

struct WaterAdvice {
    let litres: Double
    let lowLitres: Double
    let highLitres: Double
    let depthMM: Double
    let trigger: Double
    let target: Double
}

enum WaterPlanner {
    // Conservative first-pass decision support; not a calibrated irrigation controller.
    static func calculate(vwc: Double, forecast: Forecast, crop: Crop,
                          soil: Soil, areaM2: Double, efficiency: Double) -> WaterAdvice? {
        guard vwc.isFinite, (0...80).contains(vwc), areaM2 > 0,
              (0.5...1).contains(efficiency) else { return nil }
        let trigger = soil.capacity - crop.depletion * (soil.capacity - soil.wilting)
        let target = soil.capacity - 0.15 * (soil.capacity - soil.wilting)
        let demand = forecast.et0MM * crop.coefficient
        let rainCredit = min(demand, forecast.rainMM * 0.8)
        func volume(_ moisture: Double, _ demandScale: Double) -> Double {
            if moisture >= soil.capacity { return 0 }
            let gradualCorrection = crop.rootM * 1000 * (target - moisture) / 100 / 3
            let netMM = max(0, demand * demandScale - rainCredit + gradualCorrection)
            return areaM2 * min(12, netMM / efficiency)
        }
        let central = volume(vwc, 1)
        // ±5 VWC points is a what-if scenario, not a model confidence interval.
        let low = volume(min(80, vwc + 5), 0.8)
        let high = volume(max(0, vwc - 5), 1.2)
        return WaterAdvice(litres: central, lowLitres: min(low, high),
                           highLitres: max(low, high), depthMM: central / areaM2,
                           trigger: trigger, target: target)
    }
}
