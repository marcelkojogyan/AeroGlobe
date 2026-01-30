import SwiftUI
import SwiftData

struct AddFlightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var airportService = AirportService.shared
    
    @State private var date = Date()
    @State private var flightNumber = ""
    @State private var originQuery = ""
    @State private var destQuery = ""
    @State private var selectedOrigin: Airport?
    @State private var selectedDest: Airport?
    @State private var showOriginSuggestions = false
    @State private var showDestSuggestions = false
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            Form {
                // Date Section
                Section("Flight Date") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(.cyan)
                }
                
                // Flight Number (Optional)
                Section("Flight Number (Optional)") {
                    TextField("e.g. AA100", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                }
                
                // Origin Airport
                Section("Origin") {
                    AirportSearchField(
                        query: $originQuery,
                        selectedAirport: $selectedOrigin,
                        showSuggestions: $showOriginSuggestions,
                        placeholder: "Search airport (e.g. JFK)"
                    )
                }
                
                // Destination Airport
                Section("Destination") {
                    AirportSearchField(
                        query: $destQuery,
                        selectedAirport: $selectedDest,
                        showSuggestions: $showDestSuggestions,
                        placeholder: "Search airport (e.g. LHR)"
                    )
                }
                
                // Distance Preview
                if let origin = selectedOrigin, let dest = selectedDest {
                    Section("Flight Info") {
                        let distance = GeoMath.haversineDistance(
                            lat1: origin.latitude, lon1: origin.longitude,
                            lat2: dest.latitude, lon2: dest.longitude
                        )
                        
                        HStack {
                            Label("\(origin.iata)", systemImage: "airplane.departure")
                            Spacer()
                            Image(systemName: "arrow.right")
                                .foregroundColor(.secondary)
                            Spacer()
                            Label("\(dest.iata)", systemImage: "airplane.arrival")
                        }
                        .font(.headline)
                        
                        HStack {
                            Text("Distance")
                            Spacer()
                            Text("\(distance.formatted()) miles")
                                .foregroundColor(.cyan)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .navigationTitle("Add Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveFlight()
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
            .task {
                await airportService.loadAirports()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private var canSave: Bool {
        selectedOrigin != nil && selectedDest != nil && selectedOrigin?.iata != selectedDest?.iata
    }
    
    private func saveFlight() {
        guard let origin = selectedOrigin, let dest = selectedDest else { return }
        
        let distance = GeoMath.haversineDistance(
            lat1: origin.latitude, lon1: origin.longitude,
            lat2: dest.latitude, lon2: dest.longitude
        )
        
        let flight = Flight(
            date: date,
            flightNumber: flightNumber.isEmpty ? nil : flightNumber.uppercased(),
            originCode: origin.iata,
            originLat: origin.latitude,
            originLong: origin.longitude,
            destCode: dest.iata,
            destLat: dest.latitude,
            destLong: dest.longitude,
            distance: distance
        )
        
        modelContext.insert(flight)
        
        // Haptic feedback on save
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        dismiss()
    }
}

// MARK: - Airport Search Field

struct AirportSearchField: View {
    @Binding var query: String
    @Binding var selectedAirport: Airport?
    @Binding var showSuggestions: Bool
    let placeholder: String
    
    @StateObject private var airportService = AirportService.shared
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Text field
            HStack {
                TextField(placeholder, text: $query)
                    .textInputAutocapitalization(.characters)
                    .focused($isFocused)
                    .onChange(of: query) { _, newValue in
                        if newValue != selectedAirport?.displayName {
                            selectedAirport = nil
                            showSuggestions = !newValue.isEmpty
                        }
                    }
                
                if selectedAirport != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            // Suggestions
            if showSuggestions && isFocused {
                let suggestions = airportService.search(query: query)
                
                if !suggestions.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(suggestions) { airport in
                                Button {
                                    selectAirport(airport)
                                } label: {
                                    HStack {
                                        Text(airport.iata)
                                            .font(.headline)
                                            .foregroundColor(.cyan)
                                            .frame(width: 50, alignment: .leading)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(airport.city)
                                                .font(.subheadline)
                                            Text(airport.country)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                
                                if airport.id != suggestions.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }
    
    private func selectAirport(_ airport: Airport) {
        selectedAirport = airport
        query = airport.displayName
        showSuggestions = false
        isFocused = false
    }
}

#Preview {
    AddFlightView()
        .modelContainer(for: Flight.self, inMemory: true)
}
