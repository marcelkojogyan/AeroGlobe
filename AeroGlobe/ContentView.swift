import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Flight.date, order: .reverse) private var flights: [Flight]
    
    @StateObject private var globeController = GlobeSceneController()
    @State private var showingAddFlight = false
    @State private var showingPassport = false
    
    var body: some View {
        ZStack {
            // Full-screen globe
            GlobeView(controller: globeController)
                .ignoresSafeArea()
            
            // UI Overlay
            VStack {
                // Top bar with stats button
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
                    .padding(.top, 10)
                }
                
                Spacer()
                
                // Bottom stats bar
                if !flights.isEmpty {
                    HStack(spacing: 24) {
                        StatPill(icon: "airplane", value: "\(flights.count)", label: "Flights")
                        StatPill(icon: "globe.americas", value: "\(uniqueCountries)", label: "Countries")
                        StatPill(icon: "arrow.left.and.right", value: formatMiles(totalMiles), label: "Miles")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
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
        }
        .sheet(isPresented: $showingAddFlight) {
            AddFlightView()
        }
        .sheet(isPresented: $showingPassport) {
            PassportView()
        }
        .onAppear {
            globeController.refreshFlightPaths(flights: flights)
        }
        .onChange(of: flights.count) { _, _ in
            globeController.refreshFlightPaths(flights: flights)
        }
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
