import SwiftUI
import MapKit

struct WorldMapView: UIViewRepresentable {
    var flights: [Flight]
    var photoLocations: [CLLocationCoordinate2D]
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.overrideUserInterfaceStyle = .dark // Force Dark Mode
        map.isPitchEnabled = false // Keep it strictly 2D
        map.delegate = context.coordinator
        
        // Optional: Set initial region to show the world
        // map.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100))
        
        return map
    }
    
    func updateUIView(_ map: MKMapView, context: Context) {
        // Optimization: Check if updates are actually needed?
        // For MVP, just clearing and rebuilding is safest but heavy.
        
        // 1. Clear old overlays
        map.removeOverlays(map.overlays)
        
        // 2. Add Flights (Geodesic Polyline = Curved line on flat map)
        for flight in flights {
            let coords = [
                CLLocationCoordinate2D(latitude: flight.originLat, longitude: flight.originLong),
                CLLocationCoordinate2D(latitude: flight.destLat, longitude: flight.destLong)
            ]
            // 'geodesic: true' makes the line curve like a real flight path
            let polyline = MKGeodesicPolyline(coordinates: coords, count: 2)
            map.addOverlay(polyline)
        }
        
        // 3. Add Photo Heatmap (as Circles)
        for loc in photoLocations {
            let circle = MKCircle(center: loc, radius: 50_000) // 50km radius glow
            map.addOverlay(circle)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: WorldMapView
        
        init(_ parent: WorldMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .cyan // Or use UserRank color
                renderer.lineWidth = 2
                return renderer
            }
            
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.orange.withAlphaComponent(0.2) // Soft heatmap glow
                renderer.strokeColor = .clear
                return renderer
            }
            
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
