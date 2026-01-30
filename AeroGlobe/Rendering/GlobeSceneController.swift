import SwiftUI
import SceneKit
import QuartzCore
import CoreLocation

/// Main globe scene controller that manages the 3D Earth and flight paths
@MainActor
class GlobeSceneController: ObservableObject {
    let scene: SCNScene
    let cameraNode: SCNNode
    let earthNode: SCNNode
    let flightPathsNode: SCNNode
    
    @Published var isAutoRotating: Bool = false
    @Published var isTextureLoaded: Bool = false // Loading state
    
    // private var displayLink: CADisplayLink? // Removed as we use SCNAction now
    private let autoRotationSpeed: Float = 0.002
    
    // MARK: - Layered Earth Architecture ("The Onion")
    
    // Layer 1: earthNode (Base, existing)
    // Layer 2: heatmapNode (Density Overlay)
    // Layer 3: atmosphereNode (Rim Light)
    
    private let heatmapNode: SCNNode
    private let atmosphereNode: SCNNode
    
    // STRONG REFERENCES: Prevent ARC from deallocating textures before GPU uses them
    private var strongHeatmapTexture: UIImage?
    private var strongDataTexture: SCNMaterialProperty?
    
    init() {
        // Create empty scene with black background
        scene = SCNScene()
        scene.background.contents = UIColor.black
        
        // Create camera
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        cameraNode.position = SCNVector3(0, 0, 3.5)
        scene.rootNode.addChildNode(cameraNode)
        
        // --- Layer 1: Base Earth ---
        let earthGeometry = SCNSphere(radius: CGFloat(GeoMath.sphereRadius))
        earthGeometry.segmentCount = 96
        
        // Create Earth material
        // Create Earth material
        let earthMaterial = SCNMaterial()
        earthMaterial.lightingModel = .constant
        earthMaterial.isDoubleSided = false
        // Diffuse will be set on load (Black base)
        earthMaterial.diffuse.contents = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)
        
        earthGeometry.materials = [earthMaterial]
        
        earthNode = SCNNode(geometry: earthGeometry)
        earthNode.name = "earth"
        scene.rootNode.addChildNode(earthNode)
        
        // --- Layer 2: Heatmap Overlay ---
        // Radius 1.001 to sit just above surface
        let heatmapGeometry = SCNSphere(radius: CGFloat(GeoMath.sphereRadius) * 1.001)
        heatmapGeometry.segmentCount = 96
        
        let heatmapMaterial = SCNMaterial()
        heatmapMaterial.lightingModel = .constant
        heatmapMaterial.diffuse.contents = UIColor.clear // Base is transparent
        heatmapMaterial.transparent.contents = UIColor.black // Start invisible
        heatmapMaterial.transparencyMode = .rgbZero
        heatmapMaterial.blendMode = .add // Additive blending for glow
        heatmapMaterial.isDoubleSided = false
        heatmapMaterial.writesToDepthBuffer = false // FIX: Treat as 2D overlay
        
        heatmapGeometry.materials = [heatmapMaterial]
        heatmapNode = SCNNode(geometry: heatmapGeometry)
        heatmapNode.name = "heatmap"
        earthNode.addChildNode(heatmapNode) // Rotate with earth
        
        // --- Layer 3: Atmosphere Loop ---
        // Radius 1.025 to float above everything
        let atmosGeometry = SCNSphere(radius: CGFloat(GeoMath.sphereRadius) * 1.025)
        atmosGeometry.segmentCount = 96
        
        let atmosMaterial = SCNMaterial()
        atmosMaterial.lightingModel = .constant
        atmosMaterial.diffuse.contents = UIColor.clear
        atmosMaterial.transparent.contents = UIColor.white
        atmosMaterial.blendMode = .add
        atmosMaterial.writesToDepthBuffer = false
        
        // SHADER MODIFIER (Atmosphere Glow):
        // Applied to the SEPARATE Layer 3 sphere.
        let atmosphereShader = """
        // 1. Get the angle between the camera and the surface
        float dotProduct = max(0.0, dot(normalize(_surface.view), _surface.normal));

        // 2. Calculate Fresnel (Rim effect)
        float fresnel = 1.0 - dotProduct;

        // 3. THE FIX: SOFT BLEND (No Hard Cutoff)
        // We use smoothstep to gently fade the center to black.
        // 0.0 -> 0.5: Pure Black
        // 0.5 -> 1.0: Fades in
        float alpha = smoothstep(0.5, 1.0, fresnel);
        
        // 4. Rim Thinning
        // Power curve to shape the edge
        alpha = pow(alpha, 6.0);

        vec3 glowColor = vec3(0.0, 1.0, 1.0); // Cyan
        _output.color.rgb = glowColor * alpha * 1.5;
        """
        atmosMaterial.shaderModifiers = [.fragment: atmosphereShader]
        
        atmosGeometry.materials = [atmosMaterial]
        atmosphereNode = SCNNode(geometry: atmosGeometry)
        atmosphereNode.name = "atmosphere"
        earthNode.addChildNode(atmosphereNode)
        
        // Create container for flight paths
        flightPathsNode = SCNNode()
        flightPathsNode.name = "flightPaths"
        earthNode.addChildNode(flightPathsNode)
        
        // Add ambient light
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.intensity = 50
        ambientLight.light?.color = UIColor(white: 0.3, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        // Async Load Texture (Fixes 3s freeze)
        // Async Load Texture (Fixes 3s freeze)
        Task(priority: .userInitiated) {
            // FIX: No artificial delay
            // FIX: Set loaded = true immediately to bypass splash screen if desired, 
            // or ensure it sets true quickly.
            
            if let image = UIImage(named: "earth_night_8k") {
                await MainActor.run {
                    earthMaterial.diffuse.contents = UIColor.black
                    earthMaterial.emission.contents = image
                    earthMaterial.emission.intensity = 1.5 
                    
                    // Force UI update
                    self.isTextureLoaded = true
                }
            } else {
                await MainActor.run {
                    self.isTextureLoaded = true
                }
            }
        }
        
        // SHADER INITIALIZATION DISABLED
        /*
        // 4. SHADER INITIALIZATION: Bind Dummy Texture
        ...
        */
        
        // HOT SWAP STRATEGY: Do NOT attach shader here.
        // Let the globe render normally until PhotoService data is ready.
        // The shader will be attached in updatePhotoHeatmap() AFTER data is bound.
    }
    
    // MARK: - Auto Rotation using SCNAction (thread-safe)
    
    func startAutoRotation() {
        guard !isAutoRotating else { return }
        isAutoRotating = true
        
        // Use SCNAction for rotation - this is thread-safe
        let rotation = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 60)
        let repeatAction = SCNAction.repeatForever(rotation)
        earthNode.runAction(repeatAction, forKey: "autoRotation")
    }
    
    func stopAutoRotation() {
        isAutoRotating = false
        earthNode.removeAction(forKey: "autoRotation")
    }
    
    // MARK: - Flight Path Rendering
    
    /// Add a flight path with a specific color (based on Rank)
    func addFlightPath(flight: Flight, color: UIColor = .cyan, animate: Bool = false) {
        
        // Note: Individual city lights are now handled by the Heatmap Layer (Layer 2)
        // We no longer add flickering dots here. The heatmap aggregates densities.
        
        // 2. Generate Path Points
        let points = GeoMath.greatCircleArcPoints(
            startLat: flight.originLat,
            startLon: flight.originLong,
            endLat: flight.destLat,
            endLon: flight.destLong
        )
        
        guard points.count > 1 else { return }
        
        let pathNode = createGlowingPathNode(from: points, color: color)
        pathNode.name = flight.id.uuidString
        flightPathsNode.addChildNode(pathNode)
        
        // Add Physical Markers (Coupled to success)
        addCityMarker(lat: flight.originLat, lon: flight.originLong, color: color)
        addCityMarker(lat: flight.destLat, lon: flight.destLong, color: color)
        
        if animate {
            // Hide all children initially
            pathNode.opacity = 0
            pathNode.runAction(SCNAction.fadeIn(duration: 0.5))
        }
    }
    
    // MARK: - Heatmap Generation (Layer 2)
    
    // State Caching to allow separate updates
    private var cachedFlights: [Flight] = []
    
    // MARK: - Metal Shader Definitions
    
    // 1. SDF HEATMAP (Metaballs) - TEXTURE VERSION
    // WORKING VERSION: No #pragma arguments at all
    private let hardcodedMetaballsShaderNoArgs = """
    #pragma body
    
    // Hardcoded Points
    vec3 p1 = vec3(0.5, 0.2, 0.8);
    vec3 p2 = vec3(0.4, 0.3, 0.7);
    vec3 p3 = vec3(-0.5, 0.5, 0.0);
    
    vec3 p = normalize(_surface.position);
    
    float d1 = length(p - p1);
    float d2 = length(p - p2);
    float d3 = length(p - p3);
    
    float k = 0.15;
    float h = max(k - abs(d1 - d2), 0.0) / k;
    float m1 = min(d1, d2) - h * h * k * 0.25;
    h = max(k - abs(m1 - d3), 0.0) / k;
    float mFinal = min(m1, d3) - h * h * k * 0.25;
    
    float intensity = 1.0 - smoothstep(0.0, 0.3, mFinal);
    vec3 heatColor = vec3(0.0, 1.0, 1.0);
    _output.color.rgb += heatColor * intensity * 2.0;
    """
    
    // MARK: - SLOT HIJACK SHADER (Test)
    // Reads from _surface.ambientOcclusion instead of custom uniform
    private let slotHijackShader = """
    #pragma body
    _output.color.rgb = vec3(0.0, 1.0, 0.0);
    """
    
    // MARK: - FLOAT UNIFORM SDF SHADER (Working Approach)
    // Uses float uniforms instead of texture2d (which is broken on this platform)
    private let floatUniformShader = """
    #pragma arguments
    float3 cluster0;
    float3 cluster1;
    float3 cluster2;
    float3 cluster3;
    float3 cluster4;
    float3 cluster5;
    float3 cluster6;
    float3 cluster7;
    int clusterCount;
    
    #pragma body
    
    // Fragment Position on Sphere
    vec3 p = normalize(_surface.position);
    
    // SDF Smooth Minimum Function
    float k = 0.15;
    float minDist = 10.0; // Start far
    
    // Unroll the loop for max 8 clusters
    if (clusterCount > 0) {
        float d = length(p - cluster0);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    if (clusterCount > 1) {
        float d = length(p - cluster1);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    if (clusterCount > 2) {
        float d = length(p - cluster2);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    if (clusterCount > 3) {
        float d = length(p - cluster3);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    if (clusterCount > 4) {
        float d = length(p - cluster4);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    if (clusterCount > 5) {
        float d = length(p - cluster5);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    if (clusterCount > 6) {
        float d = length(p - cluster6);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    if (clusterCount > 7) {
        float d = length(p - cluster7);
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    
    // Visualize
    float intensity = 1.0 - smoothstep(0.0, 0.25, minDist);
    
    // Color: Cyan (matching brand)
    vec3 heatColor = vec3(0.0, 1.0, 1.0);
    
    // Additive Blending
    _output.color.rgb += heatColor * intensity * 2.0;
    """
    
    func updatePhotoHeatmap(clusters: [PhotoCluster]) {
        // SDF SHADER APPROACH with STRONG REFERENCE
        // The texture must be kept alive by the class to prevent ARC deallocation
        
        guard let liveMaterial = earthNode.geometry?.firstMaterial else { return }
        
        // FALLBACK: If no clusters, use test data
        let effectiveClusters: [PhotoCluster]
        if clusters.isEmpty {
            effectiveClusters = [
                PhotoCluster(coordinate: CLLocationCoordinate2D(latitude: 20.0, longitude: 78.0), count: 10),
                PhotoCluster(coordinate: CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0), count: 8),
                PhotoCluster(coordinate: CLLocationCoordinate2D(latitude: 35.7, longitude: 139.7), count: 5),
            ]
            print("SDF: Using 3 TEST clusters")
        } else {
            effectiveClusters = clusters
        }
        
        // Step 1: Generate the data texture
        let dataTexture = generateClusterDataTexture(clusters: effectiveClusters)
        
        // Step 2: CRITICAL - Create SCNMaterialProperty and STORE STRONG REFERENCE
        let prop = SCNMaterialProperty(contents: dataTexture)
        prop.magnificationFilter = .nearest
        prop.minificationFilter = .nearest
        prop.mipFilter = .none
        prop.wrapS = .clampToBorder
        prop.wrapT = .clampToBorder
        
        // STRONG REFERENCE - Keep alive for GPU
        self.strongDataTexture = prop
        
        // Step 3: Bind the property to the material
        liveMaterial.setValue(self.strongDataTexture, forKey: "customDataMap")
        
        // Step 4: NOW attach the shader (data is ready and retained)
        liveMaterial.shaderModifiers = [.fragment: sdfTextureShader]
        
        print("SDF Strong Ref: Attached shader with \(effectiveClusters.count) clusters")
    }
    
    // SDF shader that reads cluster positions from a texture
    private let sdfTextureShader = """
    #pragma arguments
    texture2d<float, access::sample> customDataMap;
    
    #pragma body
    
    // Create sampler
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    
    // Fragment Position on Sphere
    vec3 p = normalize(_surface.position);
    
    // SDF Smooth Minimum Function
    float k = 0.15;
    float minDist = 10.0;
    
    // Read up to 8 clusters from texture
    for (int i = 0; i < 8; i++) {
        float u = (float(i) + 0.5) / 64.0;
        float4 data = customDataMap.sample(s, float2(u, 0.5));
        
        // Skip if alpha is 0 (no data)
        if (data.a < 0.01) break;
        
        // Decode position from RGB (0-1 -> -1 to 1)
        vec3 clusterPos = data.rgb * 2.0 - 1.0;
        
        // Calculate distance
        float d = length(p - clusterPos);
        
        // Smooth min
        float h = max(k - abs(minDist - d), 0.0) / k;
        minDist = min(minDist, d) - h * h * k * 0.25;
    }
    
    // Visualize
    float intensity = 1.0 - smoothstep(0.0, 0.25, minDist);
    
    // Color: Cyan
    vec3 heatColor = vec3(0.0, 1.0, 1.0);
    
    // Additive Blending
    _output.color.rgb += heatColor * intensity * 2.0;
    """
    
    private func generateCPUHeatmapTexture(clusters: [PhotoCluster]) -> UIImage {
        // Generate an equirectangular heatmap texture (2:1 aspect ratio)
        let width = 1024
        let height = 512
        let size = CGSize(width: width, height: height)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Start with transparent black
            cgContext.setFillColor(UIColor.clear.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: size))
            
            // Convert clusters to UV coordinates
            let clusterUVs: [(x: CGFloat, y: CGFloat, intensity: CGFloat)] = clusters.map { cluster in
                // Equirectangular projection: lon -> x (0-1), lat -> y (0-1)
                let u = CGFloat((cluster.coordinate.longitude + 180.0) / 360.0)
                let v = CGFloat((90.0 - cluster.coordinate.latitude) / 180.0)
                let intensity = CGFloat(min(cluster.count, 20)) / 20.0  // Normalize intensity
                return (x: u * CGFloat(width), y: v * CGFloat(height), intensity: intensity)
            }
            
            // Draw soft radial gradients for each cluster (metaball-like)
            for cluster in clusterUVs {
                let radius: CGFloat = 60.0 + cluster.intensity * 40.0  // Bigger spots for more photos
                
                // Create radial gradient
                let colors = [
                    UIColor(red: 0, green: 1, blue: 1, alpha: 0.8 * cluster.intensity).cgColor,
                    UIColor(red: 0, green: 1, blue: 1, alpha: 0.0).cgColor
                ]
                let locations: [CGFloat] = [0.0, 1.0]
                
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                              colors: colors as CFArray,
                                              locations: locations) {
                    cgContext.saveGState()
                    cgContext.setBlendMode(.plusLighter)  // Additive for glow
                    cgContext.drawRadialGradient(gradient,
                                                  startCenter: CGPoint(x: cluster.x, y: cluster.y),
                                                  startRadius: 0,
                                                  endCenter: CGPoint(x: cluster.x, y: cluster.y),
                                                  endRadius: radius,
                                                  options: [])
                    cgContext.restoreGState()
                }
            }
        }
    }
    
    private func generateClusterDataTexture(clusters: [PhotoCluster]) -> UIImage {
        let size = CGSize(width: 64, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Fill Cleanly with 0
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // We only write the first pixel for this test, but let's implement the loop
            // assuming we might have more. Shader only reads index 0 though.
            
            let sorted = clusters.sorted { $0.count > $1.count }
            let count = min(sorted.count, 64)
            
            // Sort by Latitude (Y) to keep similar clusters together? No, arbitrary is fine.
            let topClusters = Array(sorted.prefix(count))
            
            for (i, cluster) in topClusters.enumerated() {
                let pos = GeoMath.latLongToCartesian(latitude: cluster.coordinate.latitude, longitude: cluster.coordinate.longitude, radius: 1.0)
                
                // MAP: [-1...1] -> [0...1] for Texture Storage
                // x' = (x + 1) / 2
                let r = CGFloat((pos.x + 1.0) / 2.0)
                let g = CGFloat((pos.y + 1.0) / 2.0)
                let b = CGFloat((pos.z + 1.0) / 2.0)
                let a = CGFloat(1.0) // Intensity
                
                let color = UIColor(red: r, green: g, blue: b, alpha: a)
                color.setFill()
                
                // Draw 1x1 pixel at (i, 0)
                // Note: CG Context origin is top-left usually, but for 1px height it doesn't matter.
                context.fill(CGRect(x: i, y: 0, width: 1, height: 1))
            }
        }
    }
    
    // OLD attachShaders() REMOVED - Now using floatUniformShader in init()
    
    private func generateSoftDotTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Radial Gradient
            let colors = [
                UIColor.white.cgColor,          // Center: White (Hot)
                UIColor.white.withAlphaComponent(0.5).cgColor, // Mid
                UIColor.white.withAlphaComponent(0.0).cgColor  // Edge: Transparent
            ] as CFArray
            
            let locations: [CGFloat] = [0.0, 0.4, 1.0]
            
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
            
            let center = CGPoint(x: 64, y: 64)
            cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 64, options: .drawsAfterEndLocation)
        }
    }
    
    // MARK: - Metal Shader Definitions (DISABLED)
    /*
    private let sdfHeatmapShader = ...
    */
    
    // MARK: - Heatmap Updates
    
    /// Updates the heatmap texture based on current flights
    /// This runs in background to avoid freezing the UI
    func updateHeatmap(flights: [Flight], color: UIColor = .cyan) {
        self.cachedFlights = flights
        triggerHeatmapRebuild()
    }
    
    private func triggerHeatmapRebuild() {
        // Capture current state
        let flights = self.cachedFlights
        
        Task(priority: .background) {
            let texture = generateHeatmapTexture(flights: flights) // Removed await
            
            await MainActor.run {
                // Update Layer 2 Texture
                if let material = heatmapNode.geometry?.materials.first {
                     material.diffuse.contents = texture
                     material.emission.contents = texture
                     material.emission.intensity = 2.0
                     material.transparent.contents = UIColor.white
                     material.transparencyMode = .aOne
                     material.writesToDepthBuffer = false
                }
            }
        }
    }
    
    private func generateHeatmapTexture(flights: [Flight]) -> UIImage {
        // High Res for crispness (2048x1024 matches 2:1 aspect ratio of Equirectangular projection)
        let width = 2048
        let height = 1024
        let size = CGSize(width: width, height: height)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // 1. Fill CLEAR (Transparent) - critical for diffuse alpha
            cgContext.clear(CGRect(origin: .zero, size: size))
            
            // 2. Set Blend Mode to Screen/Lighten to accumulate "heat"
            cgContext.setBlendMode(.screen)
            
            // 3. Draw FLIGHT Puffs (Cyan/Rank Color) ONLY
            let puffSize: CGFloat = 15.0 // Adjust for "City Size"
            
            // Optimization: Consolidate unique locations to avoid drawing millions of puffs if many duplicates
            let flightColor = UIColor.cyan // Default, can be improved to use passed color if we store it
            
            for flight in flights {
                drawPuff(lat: flight.originLat, lon: flight.originLong, in: cgContext, width: CGFloat(width), height: CGFloat(height), size: puffSize, color: flightColor, intensity: 1.0)
                drawPuff(lat: flight.destLat, lon: flight.destLong, in: cgContext, width: CGFloat(width), height: CGFloat(height), size: puffSize, color: flightColor, intensity: 1.0)
            }
        }
    }
        
    private func drawPuff(lat: Double, lon: Double, in context: CGContext, width: CGFloat, height: CGFloat, size: CGFloat, color: UIColor, intensity: CGFloat = 1.0) {
        // Map Lat/Long to X/Y
        // Lon: -180...180 -> 0...Width
        let x = (lon + 180) / 360 * width
        
        // Lat: -90...90 -> Height...0 (CG coords are flipped Y relative to map usually)
        // Map lat -90 (South) to Height, +90 (North) to 0
        let normalizedLat = (lat + 90) / 180.0
        let y = height - (normalizedLat * height)
        
        let rect = CGRect(x: x - size/2, y: y - size/2, width: size, height: size)
        
        // Draw Soft Circle
        // We manually simulate a gradient or just a soft alpha circle
        // BOOSTED BRIGHTNESS: Make base puff more visible (Alpha 0.3)
        // Use the Rank Color but with low alpha
        context.setFillColor(color.withAlphaComponent(0.3 * intensity).cgColor) 
        context.fillEllipse(in: rect)
        
        // Inner core (hotter)
        let coreSize = size / 3
        let coreRect = CGRect(x: x - coreSize/2, y: y - coreSize/2, width: coreSize, height: coreSize)
        // SUPER BRIGHT CORE (Alpha 1.0)
        // Core is usually white (hottest part) or very light version of color
        // Let's stick to White for the "Bulb" look, or slight tint? White is best for core.
        context.setFillColor(UIColor(white: 1.0, alpha: 1.0 * intensity).cgColor)
        context.fillEllipse(in: coreRect)
    }
    
    func removeFlightPath(flightId: UUID) {
        if let node = flightPathsNode.childNode(withName: flightId.uuidString, recursively: false) {
            node.removeFromParentNode()
        }
    }
    
    func clearAllFlightPaths() {
        flightPathsNode.childNodes.forEach { $0.removeFromParentNode() }
        // Heatmap clear implicitly happens on next updateHeatmap call with empty array
    }
    
    func refreshFlightPaths(flights: [Flight], color: UIColor = .cyan, animate: Bool = false) {
        clearAllFlightPaths()
        
        // 1. Rebuild Path Lines (TUBES now, for glow)
        for flight in flights {
            addFlightPath(flight: flight, color: color, animate: false)
        }
        
        // 2. Rebuild Density Heatmap (For the "Aura" effect only)
        updateHeatmap(flights: flights, color: color)
    }
    
    // MARK: - City Marker (Physical Node)
    // Ensures lines always connect to a visible anchor
    private func addCityMarker(lat: Double, lon: Double, color: UIColor) {
        // FIX: Raise radius to 1.005 to sit ON TOP of the earth, not inside it.
        // This solves "Lines with no nodes" (buried nodes).
        let position = GeoMath.latLongToCartesian(latitude: lat, longitude: lon, radius: GeoMath.sphereRadius * 1.005)
        
        // Check if node already exists (simple dedupe by distance or name?)
        // For MVP, just creating them is fine, SceneKit handles thousands easily.
        // Or we can name them coordinates.
        let name = "City-\(Int(lat*100))-\(Int(lon*100))"
        if flightPathsNode.childNode(withName: name, recursively: false) != nil { return }
        
        let dotGeo = SCNSphere(radius: 0.003) // Small bead
        dotGeo.segmentCount = 8
        
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        material.emission.contents = color
        material.emission.intensity = 2.0
        material.writesToDepthBuffer = false // Overlay style
        // material.readsFromDepthBuffer = false // Optional: Always on top? No, we want them behind earth if rotated.
        
        dotGeo.materials = [material]
        
        let node = SCNNode(geometry: dotGeo)
        node.name = name
        node.position = position
        flightPathsNode.addChildNode(node)
    }
    
    // MARK: - Path Geometry Creation
    
    private func createGlowingPathNode(from points: [SCNVector3], color: UIColor) -> SCNNode {
        // TUBE UPGRADE: Use cylinders/tubes instead of hairline
        // We will create a single flattened shape or multiple segments?
        // Multiple segments is easier for correct curvature.
        
        // Parent node for the segments
        let pathContainer = SCNNode()
        
        // Radius for the tube
        let pathRadius: CGFloat = 0.0015
        
        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i+1]
            
            // 1. The Tube Segment
            let segment = createSegment(from: start, to: end, radius: pathRadius, color: color, isGlow: false)
            pathContainer.addChildNode(segment)
            
            // 2. The Joint Sphere (The "Knee Cap")
            // This fills the wedge gap between two angled cylinders.
            // We place it at 'start' (which is the joint between prev and curr).
            // We don't need one at the very end because the City Marker covers it.
            let jointGeo = SCNSphere(radius: pathRadius) // Same size as tube
            jointGeo.segmentCount = 6
            let jointMat = SCNMaterial()
            jointMat.lightingModel = .constant
            jointMat.diffuse.contents = color
            jointMat.emission.contents = color
            jointMat.emission.intensity = 3.0
            jointGeo.materials = [jointMat]
            
            let jointNode = SCNNode(geometry: jointGeo)
            jointNode.position = start
            pathContainer.addChildNode(jointNode)
        }
        
        return pathContainer
    }
    
    private func createSegment(from start: SCNVector3, to end: SCNVector3, radius: CGFloat, color: UIColor, isGlow: Bool = false) -> SCNNode {
        // ... (Standard Geometry)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dz = end.z - start.z
        let length = sqrt(dx*dx + dy*dy + dz*dz)
        
        guard length > 0.0001 else { return SCNNode() }
        
        let cylinder = SCNCylinder(radius: radius, height: CGFloat(length))
        cylinder.radialSegmentCount = 4
        
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.emission.contents = color
        material.emission.intensity = 2.0 // Standard Glow
        material.writesToDepthBuffer = false 
        
        // PULSE SHADER DISABLED
        /*
        let pulseShader = ...
        material.shaderModifiers = [.surface: pulseShader]
        */
        
        cylinder.materials = [material]
        
        let node = SCNNode(geometry: cylinder)
        
        node.position = SCNVector3(
            (start.x + end.x) / 2,
            (start.y + end.y) / 2,
            (start.z + end.z) / 2
        )
        // ... (Orientation logic remains)
        let direction = SCNVector3(dx, dy, dz)
        let up = SCNVector3(0, 1, 0)
        let axis = SCNVector3(
            up.y * direction.z - up.z * direction.y,
            up.z * direction.x - up.x * direction.z,
            up.x * direction.y - up.y * direction.x
        )
        let dot = up.x * direction.x + up.y * direction.y + up.z * direction.z
        let angle = acos(min(max(dot/Float(length), -1), 1))
        
        let axisLen = sqrt(axis.x*axis.x + axis.y*axis.y + axis.z*axis.z)
        
        if axisLen > 0.0001 {
            node.rotation = SCNVector4(axis.x / axisLen, axis.y / axisLen, axis.z / axisLen, angle)
        }
        
        return node
    }
}
