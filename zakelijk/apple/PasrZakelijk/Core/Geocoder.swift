import Foundation
import MapKit

/// Adres → plek (lat/lng) via Apple Maps, voor "In de buurt" in Pasr. Niets wordt bewaard behalve wat je opslaat.
enum Geocoder {
    static func locate(_ address: String) async -> CLLocationCoordinate2D? {
        let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 4 else { return nil }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        if #available(iOS 26.0, *) {
            return (item.location as CLLocation?)?.coordinate
        } else {
            return item.placemark.coordinate
        }
    }
}
