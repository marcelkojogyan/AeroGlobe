import SwiftUI

struct LevelUpOverlay: View {
    let rank: UserRank
    let onDismiss: () -> Void
    
    @State private var animateIn = false
    @State private var particleEffect = false
    
    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }
            
            VStack(spacing: 30) {
                // Rank Icon/Color Glow
                ZStack {
                    Circle()
                        .fill(rank.color.opacity(0.3))
                        .frame(width: 200, height: 200)
                        .blur(radius: 40)
                    
                    Circle()
                        .stroke(rank.color, lineWidth: 4)
                        .frame(width: 120, height: 120)
                        .shadow(color: rank.color, radius: 20)
                    
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 60))
                        .foregroundColor(rank.color)
                }
                .scaleEffect(animateIn ? 1.0 : 0.5)
                .opacity(animateIn ? 1.0 : 0.0)
                
                VStack(spacing: 10) {
                    Text("LEVEL UP!")
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(4)
                    
                    Text(rank.rawValue.uppercased())
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [rank.color, .white],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: rank.color.opacity(0.8), radius: 10)
                }
                .scaleEffect(animateIn ? 1.0 : 0.8)
                .opacity(animateIn ? 1.0 : 0.0)
                
                Text(rankDescription)
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(animateIn ? 1.0 : 0.0)
                
                Button(action: dismiss) {
                    Text("CONTINUE")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 16)
                        .background(rank.color)
                        .clipShape(Capsule())
                        .shadow(color: rank.color.opacity(0.5), radius: 10)
                }
                .padding(.top, 20)
                .opacity(animateIn ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateIn = true
            }
            // Trigger haptic feedback here if needed
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
    
    private func dismiss() {
        withAnimation {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
    
    private var rankDescription: String {
        switch rank {
        case .taxi: return "You're just getting started. Taxi to the runway!"
        case .takeoff: return "Wheels up! You're climbing fast."
        case .stratosphere: return "Cruising altitude reached. You're a serious traveler."
        case .supersonic: return "Faster than sound. You're covering serious ground."
        case .orbit: return "You've left the atmosphere. Truly elite status."
        }
    }
}

#Preview {
    LevelUpOverlay(rank: .supersonic, onDismiss: {})
}
