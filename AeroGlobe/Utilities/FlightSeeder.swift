import Foundation
import SwiftData
import CoreLocation

/// Helper to seed test data for testing AeroRank levels
enum FlightSeeder {
    
    @MainActor
    static func clearAll(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: Flight.self)
        } catch {
            print("Failed to clear flights: \(error)")
        }
    }
    
    @MainActor
    static func seed(rank: UserRank, modelContext: ModelContext) {
        // Clear first
        clearAll(modelContext: modelContext)
        
        // Generate flights based on rank target miles
        let targetMiles: Int
        switch rank {
        case .taxi:         targetMiles = 2_000
        case .takeoff:      targetMiles = 15_000
        case .stratosphere: targetMiles = 50_000
        case .supersonic:   targetMiles = 150_000
        case .orbit:        targetMiles = 300_000
        }
        
        let flights = generateFlights(for: targetMiles)
        for flight in flights {
            modelContext.insert(flight)
        }
        
        print("Seeded \(flights.count) flights for \(rank.rawValue) (\(targetMiles) miles)")
    }
    
    // Verified Hub Coordinates (Lat, Lon)
    private static let hubs: [(code: String, lat: Double, lon: Double)] = [
        ("LHR", 51.4700, -0.4543),    // London
        ("JFK", 40.6413, -73.7781),   // New York
        ("HND", 35.5494, 139.7798),   // Tokyo
        ("DXB", 25.2532, 55.3657),    // Dubai
        ("SYD", -33.9399, 151.1753),  // Sydney
        ("LAX", 33.9416, -118.4085),  // Los Angeles
        ("SIN", 1.3644, 103.9915),    // Singapore
        ("CDG", 49.0097, 2.5479),     // Paris
        ("GRU", -23.4356, -46.4731),  // Sao Paulo
        ("JNB", -26.1367, 28.2411)    // Johannesburg
    ]
    
    private static func generateFlights(for miles: Int) -> [Flight] {
        var createdFlights: [Flight] = []
        var currentMiles = 0
        
        var index = 0
        
        // Generate random flights until we hit the target mileage
        while currentMiles < miles {
            
            // Pick two distinct hubs
            guard let origin = hubs.randomElement(),
                  let dest = hubs.randomElement(),
                  origin.code != dest.code else { continue }
            
            // Calculate actual distance
            let dist = GeoMath.haversineDistance(lat1: origin.lat, lon1: origin.lon, lat2: dest.lat, lon2: dest.lon)
            
            // Adjust date back in time randomly within last year
            let daysAgo = Int.random(in: 1...365)
            let flightDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            
            let flight = Flight(
                date: flightDate,
                flightNumber: "TEST-\(String(format: "%03d", index))",
                originCode: origin.code,
                originLat: origin.lat,
                originLong: origin.lon,
                destCode: dest.code,
                destLat: dest.lat,
                destLong: dest.lon,
                distance: dist
            )
            
            createdFlights.append(flight)
            currentMiles += dist
            index += 1
        }
        
        return createdFlights
    }
}
