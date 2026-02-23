import SwiftUI
import MapKit

/// Renders a trip route on a SwiftUI Map with start/end pins.
/// Compact height (150pt) for embedding in trip review rows.
struct TripRouteMapView: View {
    let routeCoordinates: [CLLocationCoordinate2D]

    private var region: MKCoordinateRegion {
        guard !routeCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }

        let lats = routeCoordinates.map(\.latitude)
        let lons = routeCoordinates.map(\.longitude)
        let minLat = lats.min() ?? 37.7
        let maxLat = lats.max() ?? 37.8
        let minLon = lons.min() ?? -122.5
        let maxLon = lons.max() ?? -122.4

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.01)
        )

        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            // Route polyline
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(BrandColors.primary, lineWidth: 3)
            }

            // Start pin (green)
            if let start = routeCoordinates.first {
                Annotation("Start", coordinate: start) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.success)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(.white)
                            .frame(width: 6, height: 6)
                    }
                }
            }

            // End pin (red)
            if let end = routeCoordinates.last, routeCoordinates.count > 1 {
                Annotation("End", coordinate: end) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.destructive)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(.white)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusMd))
        .allowsHitTesting(false)
    }
}
