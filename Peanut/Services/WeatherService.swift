import Combine
import CoreLocation
import Foundation

/// Weather via one-shot CoreLocation + Open-Meteo (no API key required).
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Snapshot: Equatable {
        var temperature: Int
        var conditionSymbol: String
        var conditionText: String
        var high: Int
        var low: Int
    }

    @Published var snapshot: Snapshot?
    @Published var place: String?
    @Published var state: LoadState = .idle

    enum LoadState: Equatable {
        case idle, locating, loading, ready, denied, failed
    }

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard snapshot == nil else { return }
        state = .locating
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            state = .denied
        }
    }

    func retry() {
        snapshot = nil
        start()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if snapshot == nil, state != .loading {
                state = .locating
                manager.requestLocation()
            }
        case .denied, .restricted:
            state = .denied
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        state = .loading
        fetchWeather(for: location)
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let name = placemarks?.first.map { [$0.locality, $0.administrativeArea].compactMap { $0 }.joined(separator: " · ") }
            DispatchQueue.main.async {
                self?.place = (name?.isEmpty == false ? name : nil) ?? "当前位置"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.state = .failed }
    }

    // MARK: - Open-Meteo

    private func fetchWeather(for location: CLLocation) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", location.coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.3f", location.coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
        ]
        let url = components.url!

        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
            struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
            let current: Current
            let daily: Daily
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let decoded = data.flatMap { try? JSONDecoder().decode(Response.self, from: $0) }
            DispatchQueue.main.async {
                guard let self else { return }
                if let decoded {
                    let code = decoded.current.weather_code
                    self.snapshot = Snapshot(
                        temperature: Int(decoded.current.temperature_2m.rounded()),
                        conditionSymbol: Self.symbol(for: code),
                        conditionText: Self.conditionText(for: code),
                        high: Int((decoded.daily.temperature_2m_max.first ?? 0).rounded()),
                        low: Int((decoded.daily.temperature_2m_min.first ?? 0).rounded())
                    )
                    self.state = .ready
                } else {
                    self.state = .failed
                }
            }
        }.resume()
    }

    /// WMO weather interpretation codes → SF Symbol + 中文描述.
    private static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 65, 66, 67: return "cloud.rain"
        case 71, 73, 75, 77: return "cloud.snow"
        case 80, 81, 82: return "cloud.heavyrain"
        case 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }

    private static func conditionText(for code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1, 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67: return "雨"
        case 71, 73, 75, 77: return "雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95, 96, 99: return "雷雨"
        default: return "—"
        }
    }
}
