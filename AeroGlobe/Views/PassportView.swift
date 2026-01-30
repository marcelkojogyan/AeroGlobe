import SwiftUI
import SwiftData
import EventKit

struct PassportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Flight.date, order: .reverse) private var flights: [Flight]
    
    @StateObject private var calendarImporter = CalendarImporter()
    @State private var showingScanResults = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // Header Stats
                    StatsHeader(flights: flights)
                    
                    // Magic Scan Button
                    VStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await calendarImporter.scanForFlights()
                                if !calendarImporter.foundFlights.isEmpty {
                                    showingScanResults = true
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                Text("Scan Calendar for Flights")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .purple.opacity(0.4), radius: 8, y: 4)
                        }
                        
                        if calendarImporter.isScanning {
                            ProgressView("Scanning past 2 years...")
                                .tint(.indigo)
                        } else if !calendarImporter.hasAccess && calendarImporter.foundFlights.isEmpty {
                            Text("Finds flights from your calendar automatically.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Recent Flights
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Recent Flights")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        if flights.isEmpty {
                            ContentUnavailableView(
                                "No Flights Yet",
                                systemImage: "airplane",
                                description: Text("Add your first flight manually or scan your calendar.")
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(flights) { flight in
                                    FlightRow(flight: flight)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Top Countries (Simple Stat)
                    if !flights.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Stats")
                                .font(.title3)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            HStack {
                                Text("\(uniqueAirports) Airports Visited")
                                Spacer()
                            }
                            .padding(.horizontal)
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("My Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                // Debug Menu
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("Debug: Seed Data") {
                            Button("Rank: Taxi (2k)", action: { seed(.taxi) })
                            Button("Rank: Takeoff (15k)", action: { seed(.takeoff) })
                            Button("Rank: Stratosphere (50k)", action: { seed(.stratosphere) })
                            Button("Rank: Supersonic (150k)", action: { seed(.supersonic) })
                            Button("Rank: Orbit (300k)", action: { seed(.orbit) })
                            Button("Reset All", role: .destructive, action: { seed(nil) })
                        }
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .foregroundColor(.orange)
                    }
                }
            }
            .sheet(isPresented: $showingScanResults) {
                ScanResultsView(importer: calendarImporter)
            }
        }
    }
    
    // Debug Helper
    private func seed(_ rank: UserRank?) {
        Task { @MainActor in
            if let rank = rank {
                FlightSeeder.seed(rank: rank, modelContext: modelContext)
            } else {
                FlightSeeder.clearAll(modelContext: modelContext)
            }
            dismiss() // Close passport to refresh main view
        }
    }
    
    // MARK: - Computed Props
    
    private var uniqueAirports: Int {
        let origins = Set(flights.map { $0.originCode })
        let dests = Set(flights.map { $0.destCode })
        return origins.union(dests).count
    }
}

// MARK: - Subviews

struct StatsHeader: View {
    let flights: [Flight]
    
    var totalMiles: Int {
        flights.reduce(0) { $0 + $1.distance }
    }
    
    var countries: Int {
        let origins = Set(flights.map { $0.originCode })
        let dests = Set(flights.map { $0.destCode })
        return origins.union(dests).count / 2 // Rough estimate
    }
    
    var body: some View {
        HStack(spacing: 20) {
            StatBox(value: "\(flights.count)", label: "Flights", icon: "airplane")
            StatBox(value: "\(countries)", label: "Countries", icon: "globe")
            StatBox(value: formatMiles(totalMiles), label: "Miles", icon: "arrow.left.and.right")
        }
        .padding(.horizontal)
    }
    
    func formatMiles(_ miles: Int) -> String {
        if miles >= 1_000_000 {
            return String(format: "%.1fM", Double(miles) / 1_000_000)
        } else if miles >= 1_000 {
            return String(format: "%.0fK", Double(miles) / 1_000)
        }
        return "\(miles)"
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.cyan)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FlightRow: View {
    let flight: Flight
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(flight.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(flight.originCode)
                        .fontWeight(.bold)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(flight.destCode)
                        .fontWeight(.bold)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text("\(flight.distance) mi")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let num = flight.flightNumber {
                    Text(num)
                        .font(.caption)
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ScanResultsView: View {
    @ObservedObject var importer: CalendarImporter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                if importer.foundFlights.isEmpty {
                    ContentUnavailableView("No New Flights Found", systemImage: "magnifyingglass")
                }
                
                ForEach($importer.foundFlights) { $flight in
                    HStack {
                        Toggle(isOn: $flight.isSelected) {
                            VStack(alignment: .leading) {
                                Text(flight.title)
                                    .font(.headline)
                                Text(flight.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                if let orig = flight.origin, let dest = flight.destination {
                                    Text("\(orig) → \(dest)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.cyan)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Flights")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedCount)") {
                        importFlights()
                    }
                    .disabled(selectedCount == 0)
                }
            }
        }
    }
    
    var selectedCount: Int {
        importer.foundFlights.filter { $0.isSelected }.count
    }
    
    func importFlights() {
        // Find airports for the selected flights
        let service = AirportService.shared
        // Ensure airports are loaded
        if service.airports.isEmpty {
            Task {
                await service.loadAirports()
                processImport()
            }
        } else {
            processImport()
        }
    }
    
    func processImport() {
        let service = AirportService.shared
        let selected = importer.foundFlights.filter { $0.isSelected }
        
        for item in selected {
            // Need to lookup lat/long for codes
            guard let origCode = item.origin, let destCode = item.destination,
                  let origin = service.search(query: origCode).first(where: { $0.iata == origCode }),
                  let dest = service.search(query: destCode).first(where: { $0.iata == destCode })
            else { continue }
            
            let distance = GeoMath.haversineDistance(
                lat1: origin.latitude, lon1: origin.longitude,
                lat2: dest.latitude, lon2: dest.longitude
            )
            
            let flight = Flight(
                date: item.date,
                flightNumber: item.flightNumber,
                originCode: origin.iata,
                originLat: origin.latitude,
                originLong: origin.longitude,
                destCode: dest.iata,
                destLat: dest.latitude,
                destLong: dest.longitude,
                distance: distance
            )
            
            modelContext.insert(flight)
        }
        
        dismiss()
    }
}

#Preview {
    PassportView()
        .modelContainer(for: Flight.self, inMemory: true)
}
