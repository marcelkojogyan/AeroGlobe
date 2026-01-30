import SwiftUI
import SwiftData
import MapKit
import Photos
import CoreLocation

// MARK: - Supporting Classes (Consolidated for Build Stability)

// PhotoService code will be appended at the bottom
// WorldMapView code will be appended at the bottom


struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flight.date, order: .reverse) private var flights: [Flight]
    
    @StateObject private var globeController = GlobeSceneController()
    @StateObject private var photoService = PhotoService() // NEW: Photo Service
    
    @State private var is3DMode = true // NEW: Toggle State
    
    @State private var showingAddFlight = false
    @State private var showingPassport = false
    @State private var currentRank: UserRank? = nil // Track rank change
    @State private var showingLevelUp = false
    @State private var levelUpRank: UserRank = .taxi // Rank to show in modal
    
    var body: some View {
        ZStack {
            // THE VIEWS
            Group {
                if is3DMode {
                    // 3D Globe Background
                    GlobeView(controller: globeController)
                        .transition(.opacity)
                } else {
                    // 2D MapKit View
                    WorldMapView(flights: flights, photoClusters: photoService.clusters)
                        .transition(.opacity)
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            // UI Overlay
            VStack {
                // Top bar with stats button
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        
                        Button(action: { showingPassport = true }) {
                            Image(systemName: "book.closed.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 10) // Small adjustment for safe area
                        .shadow(radius: 5)
                    }
                    
                    // AeroRank Card
                    if !flights.isEmpty {
                        RankProgressCard(totalMiles: totalMiles)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                
                Spacer()
                
                // Bottom stats bar
                if !flights.isEmpty {
                    // THE TOGGLE PILL (Above Stats)
                    HStack(spacing: 0) {
                        Button(action: { withAnimation { is3DMode = true } }) {
                            Text("3D Globe")
                                .fontWeight(.bold)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(is3DMode ? Color.white.opacity(0.3) : Color.clear)
                                .cornerRadius(16)
                        }
                        
                        Button(action: { withAnimation { is3DMode = false } }) {
                            Text("2D Map")
                                .fontWeight(.bold)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(!is3DMode ? Color.white.opacity(0.3) : Color.clear)
                                .cornerRadius(16)
                        }
                    }
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                    
                    HStack(spacing: 24) {
                        StatPill(icon: "airplane", value: "\(flights.count)", label: "Flights")
                        StatPill(icon: "globe.americas", value: "\(uniqueCountries)", label: "Countries")
                        StatPill(icon: "camera.fill", value: "\(photoService.clusters.count)", label: "Memories")
                        StatPill(icon: "arrow.left.and.right", value: formatMiles(totalMiles), label: "Miles")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
                    .shadow(radius: 10)
                }
                
                // Add flight button
                Button(action: { showingAddFlight = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Flight")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.cyan, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: .cyan.opacity(0.5), radius: 10, y: 5)
                }
                .padding(.bottom, 40)
            }
            
            // Level Up Overlay
            if showingLevelUp {
                LevelUpOverlay(rank: levelUpRank) {
                    showingLevelUp = false
                }
                .zIndex(100)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingAddFlight) {
            AddFlightView()
        }
        .sheet(isPresented: $showingPassport) {
            PassportView()
        }
        .onAppear {
            DispatchQueue.main.async {
                globeController.startAutoRotation()
                // Init rank without triggering modal on first load
                if currentRank == nil {
                    currentRank = UserRank.current(for: totalMiles)
                }
                updateGlobe()
                photoService.requestAccessAndFetch() // Start Photo Scan
            }
        }
        .onChange(of: flights.count) { _, _ in
            updateGlobe()
            checkForLevelUp()
        }
        .onChange(of: photoService.clusters.count) { _, _ in
            updateGlobe() // Update heatmap when photos are found
        }
        
        if !globeController.isTextureLoaded {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                Image("splash_icon")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .transition(.opacity) // Standard fade out
            .zIndex(200)
        }
    }
    
    private func checkForLevelUp() {
        let newRank = UserRank.current(for: totalMiles)
        if let prev = currentRank, newRank != prev {
            // Rank changed!
            // Wait a moment for SwiftData update visual then show
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                levelUpRank = newRank
                showingLevelUp = true
            }
        }
        currentRank = newRank
    }
    
    private func updateGlobe() {
        // Calculate current rank color
        let rank = UserRank.current(for: totalMiles)
        let uiColor = UIColor(rank.color)
        
        // Refresh globe paths with rank color
        globeController.refreshFlightPaths(flights: flights, color: uiColor, animate: false)
        
        // Also update Photo Heatmap
        globeController.updatePhotoHeatmap(clusters: photoService.clusters)
    }
    
    // MARK: - Computed Stats
    
    private var totalMiles: Int {
        flights.reduce(0) { $0 + $1.distance }
    }
    
    private var uniqueCountries: Int {
        // This will be calculated from airport country codes
        // For now, estimate based on unique airport codes
        let origins = Set(flights.map { $0.originCode })
        let destinations = Set(flights.map { $0.destCode })
        return origins.union(destinations).count / 2  // Rough estimate
    }
    
    private func formatMiles(_ miles: Int) -> String {
        if miles >= 1_000_000 {
            return String(format: "%.1fM", Double(miles) / 1_000_000)
        } else if miles >= 1_000 {
            return String(format: "%.0fK", Double(miles) / 1_000)
        }
        return "\(miles)"
    }
}

// MARK: - Supporting Views

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            .foregroundColor(.white)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Flight.self, inMemory: true)
}


// MARK: - Appended Services

import Foundation
import Photos
import CoreLocation
import SwiftUI

class PhotoService: ObservableObject {
    @Published var clusters: [PhotoCluster] = []
    
    // ... (Permission code remains the same) ...
    func requestAccessAndFetch() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            if status == .authorized || status == .limited {
                self.fetchLocations()
            }
        }
    }
    
    private func fetchLocations() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared]
        
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        var locations: [CLLocationCoordinate2D] = []
        
        assets.enumerateObjects { asset, _, _ in
            if let location = asset.location {
                locations.append(location.coordinate)
            }
        }
        
        // NEW: Cluster the raw locations into weighted groups
        let clustered = clusterLocations(locations, radiusInMeters: 25_000) // 25km radius
        
        DispatchQueue.main.async {
            self.clusters = clustered
            print("PhotoService: Found \(locations.count) photos, created \(clustered.count) clusters")
        }
    }
    
    // The "Bucketing" Algorithm
    private func clusterLocations(_ locations: [CLLocationCoordinate2D], radiusInMeters: Double) -> [PhotoCluster] {
        var result: [PhotoCluster] = []
        
        for loc in locations {
            let photoLocation = CLLocation(latitude: loc.latitude, longitude: loc.longitude)
            
            // Check if this photo belongs to an existing cluster
            if let index = result.firstIndex(where: { cluster in
                let clusterLocation = CLLocation(latitude: cluster.coordinate.latitude, longitude: cluster.coordinate.longitude)
                return clusterLocation.distance(from: photoLocation) < radiusInMeters
            }) {
                // It fits! Increment the count of the existing cluster
                result[index].count += 1
            } else {
                // New area found. Create a new cluster.
                result.append(PhotoCluster(coordinate: loc, count: 1))
            }
        }
        return result
    }
}

struct PhotoCluster: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    var count: Int
}


import SwiftUI
import MapKit

// Custom MKCircle subclass to hold the count data
class CustomHeatmapCircle: MKCircle {
    var photoCount: Int = 1
}

struct WorldMapView: UIViewRepresentable {
    var flights: [Flight]
    var photoClusters: [PhotoCluster] // Changed from [CLLocationCoordinate2D]
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.overrideUserInterfaceStyle = .dark // Force Dark Mode
        map.isPitchEnabled = false // Keep it strictly 2D
        map.delegate = context.coordinator
        return map
    }
    
    func updateUIView(_ map: MKMapView, context: Context) {
        
        // 1. Clear old overlays
        map.removeOverlays(map.overlays)
        
        // 2. Add Flights (Geodesic Polyline = Curved line on flat map)
        for flight in flights {
            let coords = [
                CLLocationCoordinate2D(latitude: flight.originLat, longitude: flight.originLong),
                CLLocationCoordinate2D(latitude: flight.destLat, longitude: flight.destLong)
            ]
            let polyline = MKGeodesicPolyline(coordinates: coords, count: 2)
            map.addOverlay(polyline)
        }
        
        // 3. Add Photo Heatmap (as Weighted Custom Circles)
        for cluster in photoClusters {
            // Radius: 25km base? Or 50km visual?
            let circle = CustomHeatmapCircle(center: cluster.coordinate, radius: 50_000)
            circle.photoCount = cluster.count
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
                renderer.strokeColor = .cyan 
                renderer.lineWidth = 2
                return renderer
            }
            
            if let circle = overlay as? CustomHeatmapCircle {
                let renderer = MKCircleRenderer(circle: circle)
                
                // --- LOGIC: REUSE INTENSITY MATH ---
                let count = CGFloat(circle.photoCount)
                let baseline: CGFloat = 0.2
                let maxAlpha: CGFloat = 0.6 // Keep 2D maps subtler than 3D
                let saturation: CGFloat = 50.0
                
                let alpha = min(baseline + (count / saturation), maxAlpha)
                
                renderer.fillColor = UIColor.orange.withAlphaComponent(alpha) // Soft heatmap glow
                renderer.strokeColor = .clear
                return renderer
            }
            
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
