import Foundation

/// Airport data model for local database
struct Airport: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let city: String
    let country: String
    let iata: String
    let icao: String
    let latitude: Double
    let longitude: Double
    
    // Custom decoding to handle OpenFlights CSV format
    init(from csvRow: String) throws {
        let columns = Airport.parseCSVRow(csvRow)
        guard columns.count >= 8 else {
            throw AirportParseError.insufficientColumns
        }
        
        self.id = Int(columns[0]) ?? 0
        self.name = columns[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        self.city = columns[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        self.country = columns[3].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        // IATA can be \N for unknown
        let iataRaw = columns[4].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        self.iata = iataRaw == "\\N" ? "" : iataRaw
        
        let icaoRaw = columns[5].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        self.icao = icaoRaw == "\\N" ? "" : icaoRaw
        
        self.latitude = Double(columns[6]) ?? 0
        self.longitude = Double(columns[7]) ?? 0
    }
    
    // For JSON decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        city = try container.decode(String.self, forKey: .city)
        country = try container.decode(String.self, forKey: .country)
        iata = try container.decode(String.self, forKey: .iata)
        icao = try container.decodeIfPresent(String.self, forKey: .icao) ?? ""
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, city, country, iata, icao, latitude, longitude
    }
    
    /// Display string for autocomplete
    var displayName: String {
        "\(iata) - \(city), \(country)"
    }
    
    // Parse CSV row handling quoted strings with commas
    private static func parseCSVRow(_ row: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false
        
        for char in row {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)
        return columns
    }
}

enum AirportParseError: Error {
    case insufficientColumns
    case invalidData
}

/// Service for loading and searching airports
@MainActor
class AirportService: ObservableObject {
    static let shared = AirportService()
    
    @Published private(set) var airports: [Airport] = []
    @Published private(set) var isLoaded = false
    
    private var airportsByIATA: [String: Airport] = [:]
    
    private init() {}
    
    /// Load airports from bundled JSON file
    func loadAirports() async {
        guard !isLoaded else { return }
        
        // Try loading from JSON first
        if let jsonURL = Bundle.main.url(forResource: "airports", withExtension: "json") {
            do {
                let data = try Data(contentsOf: jsonURL)
                let decoded = try JSONDecoder().decode([Airport].self, from: data)
                self.airports = decoded.filter { !$0.iata.isEmpty }
                self.buildIndex()
                self.isLoaded = true
                print("Loaded \(airports.count) airports from JSON")
                return
            } catch {
                print("Failed to load airports JSON: \(error)")
            }
        }
        
        // Fall back to CSV if JSON not available
        if let csvURL = Bundle.main.url(forResource: "airports", withExtension: "dat") {
            do {
                let content = try String(contentsOf: csvURL, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                
                var parsed: [Airport] = []
                for line in lines where !line.isEmpty {
                    if let airport = try? Airport(from: line), !airport.iata.isEmpty {
                        parsed.append(airport)
                    }
                }
                
                self.airports = parsed
                self.buildIndex()
                self.isLoaded = true
                print("Loaded \(airports.count) airports from CSV")
            } catch {
                print("Failed to load airports CSV: \(error)")
            }
        }
    }
    
    private func buildIndex() {
        airportsByIATA = Dictionary(uniqueKeysWithValues: airports.map { ($0.iata.uppercased(), $0) })
    }
    
    /// Look up airport by exact IATA code
    func airport(byIATA code: String) -> Airport? {
        airportsByIATA[code.uppercased()]
    }
    
    /// Search airports for autocomplete
    func search(query: String, limit: Int = 10) -> [Airport] {
        guard !query.isEmpty else { return [] }
        
        let uppercasedQuery = query.uppercased()
        
        // Prioritize exact IATA match
        var results: [Airport] = []
        
        // First: exact IATA matches
        if let exact = airportsByIATA[uppercasedQuery] {
            results.append(exact)
        }
        
        // Second: IATA starts with query
        let iataMatches = airports.filter {
            $0.iata.uppercased().hasPrefix(uppercasedQuery) && !results.contains($0)
        }.prefix(limit - results.count)
        results.append(contentsOf: iataMatches)
        
        // Third: city name contains query
        if results.count < limit {
            let cityMatches = airports.filter {
                $0.city.uppercased().contains(uppercasedQuery) && !results.contains($0)
            }.prefix(limit - results.count)
            results.append(contentsOf: cityMatches)
        }
        
        return results
    }
    
    /// Get country for an airport code
    func country(forIATA code: String) -> String? {
        airport(byIATA: code)?.country
    }
}
