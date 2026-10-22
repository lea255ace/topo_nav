import CoreLocation
import Foundation

/// A driving route returned by the Mapbox Directions API.
struct Route: Equatable {
    var coordinates: [CLLocationCoordinate2D]
    /// Meters.
    var distance: Double
    /// Seconds.
    var duration: Double

    static func == (lhs: Route, rhs: Route) -> Bool {
        lhs.distance == rhs.distance && lhs.duration == rhs.duration
            && lhs.coordinates.elementsEqual(rhs.coordinates) {
                $0.latitude == $1.latitude && $0.longitude == $1.longitude
            }
    }
}

enum DirectionsError: LocalizedError {
    case missingToken
    case network(URLError)
    case noRoute
    case unauthorized
    case rateLimited
    case server(status: Int, message: String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingToken:
            "No Mapbox access token is configured."
        case .network(let error) where error.code == .notConnectedToInternet:
            "You're offline. Check your connection and try again."
        case .network:
            "Couldn't reach Mapbox. Check your connection and try again."
        case .noRoute:
            "No driving route found to that spot. Try a point on or near a road."
        case .unauthorized:
            "Mapbox rejected the access token. Check MAPBOX_ACCESS_TOKEN in Secrets.xcconfig."
        case .rateLimited:
            "Too many route requests. Wait a moment and try again."
        case .server(let status, let message):
            message ?? "Mapbox returned an error (HTTP \(status))."
        case .invalidResponse:
            "Mapbox returned a route the app couldn't read."
        }
    }
}

/// Fetches driving routes from the Mapbox Directions API v5 using URLSession.
struct DirectionsClient {
    var session: URLSession = .shared

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) async throws -> Route {
        guard let token = MapboxToken.value else { throw DirectionsError.missingToken }

        let coordinates = [origin, destination]
            .map { "\($0.longitude),\($0.latitude)" }
            .joined(separator: ";")
        var components = URLComponents(string: "https://api.mapbox.com/directions/v5/mapbox/driving-traffic/\(coordinates)")!
        components.queryItems = [
            URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "access_token", value: token),
        ]

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: components.url!)
        } catch let error as URLError {
            throw DirectionsError.network(error)
        }

        let body = try? JSONDecoder().decode(ResponseBody.self, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            break
        case 401, 403:
            throw DirectionsError.unauthorized
        case 429:
            throw DirectionsError.rateLimited
        default:
            if let code = body?.code, Self.noRouteCodes.contains(code) {
                throw DirectionsError.noRoute
            }
            throw DirectionsError.server(status: status, message: body?.message)
        }

        guard let body else { throw DirectionsError.invalidResponse }
        if Self.noRouteCodes.contains(body.code) { throw DirectionsError.noRoute }
        guard body.code == "Ok", let first = body.routes?.first else {
            throw DirectionsError.server(status: status, message: body.message)
        }
        let points = first.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
        guard points.count >= 2 else { throw DirectionsError.invalidResponse }
        return Route(coordinates: points, distance: first.distance, duration: first.duration)
    }

    /// Directions API codes meaning no route connects the two points.
    private static let noRouteCodes: Set<String> = ["NoRoute", "NoSegment"]

    private struct ResponseBody: Decodable {
        var code: String
        var message: String?
        var routes: [RouteBody]?
    }

    private struct RouteBody: Decodable {
        var distance: Double
        var duration: Double
        var geometry: Geometry
    }

    private struct Geometry: Decodable {
        var coordinates: [[Double]]
    }
}
