import SwiftUI
import SceneKit
import UIKit

/// UIViewRepresentable wrapper for the SceneKit globe view
struct GlobeView: UIViewRepresentable {
    @ObservedObject var controller: GlobeSceneController
    var onInteractionBegan: (() -> Void)?
    var onInteractionEnded: (() -> Void)?
    
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = controller.scene
        scnView.pointOfView = controller.cameraNode
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false  // We handle gestures ourselves
        
        // Configure rendering
        scnView.preferredFramesPerSecond = 60
        scnView.isPlaying = true
        
        // Add gesture recognizers
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        scnView.addGestureRecognizer(panGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        scnView.addGestureRecognizer(pinchGesture)
        
        let rotationGesture = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotation(_:)))
        scnView.addGestureRecognizer(rotationGesture)
        
        // Allow simultaneous gestures
        panGesture.delegate = context.coordinator
        pinchGesture.delegate = context.coordinator
        rotationGesture.delegate = context.coordinator
        
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {
        // Update scene if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: GlobeView
        private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
        private var lastPanVelocity: CGFloat = 0
        private var hapticCooldown: Date = Date.distantPast
        private var resumeAutoRotationTimer: Timer?
        
        init(_ parent: GlobeView) {
            self.parent = parent
            super.init()
            hapticGenerator.prepare()
        }
        
        // MARK: - Gesture Handlers
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            switch gesture.state {
            case .began:
                parent.controller.stopAutoRotation()
                parent.onInteractionBegan?()
                
            case .changed:
                // Rotate earth based on pan
                let rotationSpeed: Float = 0.005
                parent.controller.earthNode.eulerAngles.y += Float(translation.x) * rotationSpeed
                parent.controller.earthNode.eulerAngles.x += Float(translation.y) * rotationSpeed
                
                // Clamp vertical rotation to prevent flipping
                parent.controller.earthNode.eulerAngles.x = max(-.pi/2, min(.pi/2, parent.controller.earthNode.eulerAngles.x))
                
                gesture.setTranslation(.zero, in: gesture.view)
                
                // Haptic feedback on fast spin
                let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if speed > 1500 && Date() > hapticCooldown {
                    hapticGenerator.impactOccurred(intensity: min(1.0, speed / 3000))
                    hapticCooldown = Date().addingTimeInterval(0.1)
                }
                
            case .ended, .cancelled:
                scheduleAutoRotationResume()
                parent.onInteractionEnded?()
                
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.controller.stopAutoRotation()
                parent.onInteractionBegan?()
                
            case .changed:
                // Zoom by moving camera
                let zoomSpeed: Float = 0.5
                let newZ = parent.controller.cameraNode.position.z - Float(gesture.scale - 1) * zoomSpeed
                
                // Clamp zoom level
                parent.controller.cameraNode.position.z = max(1.8, min(6.0, newZ))
                
                gesture.scale = 1.0
                
            case .ended, .cancelled:
                scheduleAutoRotationResume()
                parent.onInteractionEnded?()
                
            default:
                break
            }
        }
        
        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.controller.stopAutoRotation()
                parent.onInteractionBegan?()
                
            case .changed:
                // Tilt the earth (rotate around Z axis for "tilt" effect)
                parent.controller.earthNode.eulerAngles.z -= Float(gesture.rotation)
                gesture.rotation = 0
                
            case .ended, .cancelled:
                scheduleAutoRotationResume()
                parent.onInteractionEnded?()
                
            default:
                break
            }
        }
        
        private func scheduleAutoRotationResume() {
            resumeAutoRotationTimer?.invalidate()
            resumeAutoRotationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.parent.controller.startAutoRotation()
                }
            }
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow pinch and rotation to work together
            return true
        }
    }
}
