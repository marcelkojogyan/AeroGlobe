import SwiftUI

enum UserRank: String, CaseIterable {
    case taxi = "Taxi"
    case takeoff = "Takeoff"
    case stratosphere = "Stratosphere"
    case supersonic = "Supersonic"
    case orbit = "Orbit"
    
    // Logic: Determine Rank based on miles
    static func current(for miles: Int) -> UserRank {
        switch miles {
        case 0..<5_000: return .taxi
        case 5_000..<25_000: return .takeoff
        case 25_000..<100_000: return .stratosphere
        case 100_000..<250_000: return .supersonic
        default: return .orbit
        }
    }
    
    // The "Neon" Color for the 3D Globe
    var color: Color {
        switch self {
        case .taxi: return Color.cyan
        case .takeoff: return Color(red: 0.2, green: 1.0, blue: 0.2) // Neon Lime
        case .stratosphere: return Color(red: 1.0, green: 0.8, blue: 0.0) // Gold
        case .supersonic: return Color(red: 1.0, green: 0.4, blue: 0.0) // Safety Orange
        case .orbit: return Color(red: 0.8, green: 0.0, blue: 1.0) // Deep Purple
        }
    }
    
    // Helper for the Progress Bar (0.0 to 1.0)
    func progress(totalMiles: Int) -> Double {
        let (start, end) = range
        
        // Cap progress at 1.0 for Orbit (max rank)
        if self == .orbit {
            let relativeMiles = Double(totalMiles - start)
            let span = Double(1_000_000 - start) // Milestone to "beat the game"?
            return min(max(relativeMiles / span, 0.0), 1.0)
        }
        
        // For other ranks
        let relativeMiles = Double(totalMiles - start)
        let span = Double(end - start)
        return min(max(relativeMiles / span, 0.0), 1.0)
    }
    
    private var range: (Int, Int) {
        switch self {
        case .taxi: return (0, 5_000)
        case .takeoff: return (5_000, 25_000)
        case .stratosphere: return (25_000, 100_000)
        case .supersonic: return (100_000, 250_000)
        case .orbit: return (250_000, Int.max)
        }
    }
    
    var nextMilestone: Int? {
        switch self {
        case .orbit: return nil
        default: return range.1
        }
    }
}
