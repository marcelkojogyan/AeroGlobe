import SwiftUI

struct RankProgressCard: View {
    let totalMiles: Int
    
    var body: some View {
        let rank = UserRank.current(for: totalMiles)
        let progress = rank.progress(totalMiles: totalMiles)
        
        VStack(spacing: 12) {
            // 1. Rank Title
            HStack {
                Text(rank.rawValue.uppercased())
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(rank.color)
                
                Spacer()
                
                Text("\(formatMiles(totalMiles)) mi")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // 2. The "Nike-style" Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 8)
                    
                    // Fill (Animated)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [rank.color.opacity(0.7), rank.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * progress, 8), height: 8)
                        // Add a "Glow" shadow to the bar itself
                        .shadow(color: rank.color.opacity(0.8), radius: 6, x: 0, y: 0)
                        // Animate changes
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)
                }
            }
            .frame(height: 8)
            
            // 3. Next Milestone Text
            if let next = rank.nextMilestone {
                Text("NEXT: \(formatMiles(next)) MILES")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text("TOP AERO RANK ACHIEVED")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(rank.color)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding()
        .background(.ultraThinMaterial) // Frosted glass effect
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func formatMiles(_ miles: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: miles)) ?? "\(miles)"
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            RankProgressCard(totalMiles: 2000)   // Taxi
            RankProgressCard(totalMiles: 15000)  // Takeoff
            RankProgressCard(totalMiles: 50000)  // Stratosphere
            RankProgressCard(totalMiles: 150000) // Supersonic
            RankProgressCard(totalMiles: 300000) // Orbit
        }
        .padding()
    }
}
