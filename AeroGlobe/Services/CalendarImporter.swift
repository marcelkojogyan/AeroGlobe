import Foundation
import EventKit

/// Service for importing flights from calendar events
@MainActor
class CalendarImporter: ObservableObject {
    @Published var hasAccess: Bool = false
    @Published var foundFlights: [PotentialFlight] = []
    @Published var isScanning: Bool = false
    
    private let eventStore = EKEventStore()
    
    // Airlines and keywords to search for
    private let airlineKeywords = [
        "flight", "airline", "airways", "departs", "arrives",
        "boarding", "confirmation", "itinerary"
    ]
    
    private let airlineCodes = [
        "AA", "UA", "DL", "WN", "AS", "B6", "NK", "F9", "G4", "HA",  // US
        "BA", "LH", "AF", "KL", "IB", "AZ", "SN", "OS", "LX", "SK",  // Europe
        "EK", "QR", "EY", "TK", "SQ", "CX", "QF", "NZ", "JL", "NH"   // Int'l
    ]
    
    struct PotentialFlight: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let origin: String?
        let destination: String?
        let flightNumber: String?
        let calendarEvent: EKEvent
        var isSelected: Bool = true
    }
    
    /// Request calendar access
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            hasAccess = granted
            return granted
        } catch {
            print("Calendar access error: \(error)")
            hasAccess = false
            return false
        }
    }
    
    /// Scan calendar for flight events
    func scanForFlights() async {
        guard hasAccess else {
            let granted = await requestAccess()
            if !granted { return }
            // Continue if access was just granted
            return await scanForFlights()
        }
        
        isScanning = true
        foundFlights = []
        
        // Scan past 2 years
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .year, value: -2, to: endDate) else {
            isScanning = false
            return
        }
        
        // Get all calendars
        let calendars = eventStore.calendars(for: .event)
        
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )
        
        let events = eventStore.events(matching: predicate)
        
        // Filter for flight-related events
        var potentialFlights: [PotentialFlight] = []
        
        for event in events {
            guard let title = event.title else { continue }
            
            let titleLower = title.lowercased()
            
            // Check for airline keywords
            let hasKeyword = airlineKeywords.contains { titleLower.contains($0) }
            
            // Check for airline codes (e.g., "UA123", "AA 456")
            let hasAirlineCode = airlineCodes.contains { code in
                title.contains(code) && title.range(of: "\(code)\\s?\\d{1,4}", options: .regularExpression) != nil
            }
            
            // Check for IATA codes in title (e.g., "JFK to LHR" or "JFK → LHR")
            let iataPattern = "[A-Z]{3}\\s*(?:to|→|->|-)\\s*[A-Z]{3}"
            let hasIATACodes = title.range(of: iataPattern, options: .regularExpression) != nil
            
            if hasKeyword || hasAirlineCode || hasIATACodes {
                let parsed = parseFlightDetails(from: event)
                let potentialFlight = PotentialFlight(
                    date: event.startDate,
                    title: title,
                    origin: parsed.origin,
                    destination: parsed.destination,
                    flightNumber: parsed.flightNumber,
                    calendarEvent: event
                )
                potentialFlights.append(potentialFlight)
            }
        }
        
        // Sort by date descending
        foundFlights = potentialFlights.sorted { $0.date > $1.date }
        isScanning = false
    }
    
    /// Parse flight details from event
    private func parseFlightDetails(from event: EKEvent) -> (origin: String?, destination: String?, flightNumber: String?) {
        let title = event.title ?? ""
        let notes = event.notes ?? ""
        let location = event.location ?? ""
        let combined = "\(title) \(notes) \(location)"
        
        // Try to extract IATA codes
        var origin: String?
        var destination: String?
        
        // Pattern: "JFK to LHR" or "JFK → LHR" or "JFK - LHR"
        if let match = combined.range(of: "([A-Z]{3})\\s*(?:to|→|->|-)\\s*([A-Z]{3})", options: .regularExpression) {
            let matched = String(combined[match])
            let codes = matched.components(separatedBy: CharacterSet(charactersIn: "to→->- "))
                .filter { $0.count == 3 }
            if codes.count >= 2 {
                origin = codes[0]
                destination = codes[1]
            }
        }
        
        // Try to extract flight number
        var flightNumber: String?
        for code in airlineCodes {
            if let match = combined.range(of: "\(code)\\s?\\d{1,4}", options: .regularExpression) {
                flightNumber = String(combined[match]).replacingOccurrences(of: " ", with: "")
                break
            }
        }
        
        return (origin, destination, flightNumber)
    }
}
