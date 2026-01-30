import Foundation
import SceneKit

/// Geographic math utilities for globe rendering
enum GeoMath {
    /// Earth radius in miles (for distance calculations)
    static let earthRadiusMiles: Double = 3958.8
    
    /// Sphere radius used in SceneKit scene
    static let sphereRadius: Float = 1.0
    
    /// Convert latitude/longitude to 3D cartesian coordinates on a sphere
    /// - Parameters:
    ///   - latitude: Latitude in degrees (-90 to 90)
    ///   - longitude: Longitude in degrees (-180 to 180)
    ///   - radius: Radius of the sphere (default: 1.0)
    /// - Returns: SCNVector3 position on the sphere surface
    static func latLongToCartesian(latitude: Double, longitude: Double, radius: Float = sphereRadius) -> SCNVector3 {
        // Convert degrees to radians
        let latRad = latitude * .pi / 180.0
        let lonRad = longitude * .pi / 180.0
        
        // Convert spherical to cartesian coordinates
        // Note: In SceneKit, Y is up.
        // FIX: Coordinate rotation to match SceneKit's default UV mapping.
        // Lat 0, Lon 0 (Africa) should be at [0, 0, 1] (Front/+Z), not [1, 0, 0] (Right/+X).
        
        let x = Float(cos(latRad) * sin(lonRad)) * radius
        let y = Float(sin(latRad)) * radius
        let z = Float(cos(latRad) * cos(lonRad)) * radius
        
        return SCNVector3(x, y, z)
    }
    
    /// Calculate the great circle distance between two points using the Haversine formula
    /// - Parameters:
    ///   - lat1: Latitude of point 1 in degrees
    ///   - lon1: Longitude of point 1 in degrees
    ///   - lat2: Latitude of point 2 in degrees
    ///   - lon2: Longitude of point 2 in degrees
    /// - Returns: Distance in miles
    static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Int {
        let lat1Rad = lat1 * .pi / 180.0
        let lat2Rad = lat2 * .pi / 180.0
        let deltaLat = (lat2 - lat1) * .pi / 180.0
        let deltaLon = (lon2 - lon1) * .pi / 180.0
        
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return Int(earthRadiusMiles * c)
    }
    
    /// Generate points along a great circle arc between two positions
    /// The arc is elevated above the sphere surface for visual effect
    /// - Parameters:
    ///   - start: Starting lat/long
    ///   - end: Ending lat/long
    ///   - segments: Number of segments for the arc (more = smoother)
    ///   - arcHeight: How high the arc peaks above the sphere (multiplier)
    /// - Returns: Array of SCNVector3 positions forming the arc
    /// Generate points along a Quadratic Bézier curve for a smooth flight path
    /// The curve is calculated to clear the sphere surface based on arc length
    /// - Parameters:
    ///   - start: Starting lat/long
    ///   - end: Ending lat/long
    ///   - segments: Number of segments for the arc (more = smoother)
    ///   - arcHeight: Tuning for the curve height (default 0.15)
    /// - Returns: Array of SCNVector3 positions forming the arc
        // Generate points along a Quadratic Bézier curve for a smooth flight path
    /// The curve is calculated to clear the sphere surface based on arc length
    /// - Parameters:
    ///   - start: Starting lat/long
    ///   - end: Ending lat/long
    ///   - segments: Number of segments for the arc (more = smoother)
    ///   - arcHeight: Tuning for the curve height (User formula overrides this if needed)
    /// - Returns: Array of SCNVector3 positions forming the arc
    static func greatCircleArcPoints(
        startLat: Double, startLon: Double,
        endLat: Double, endLon: Double,
        segments: Int = 128,
        arcHeight: Float = 0.15 // Kept for API compatibility, but logic updated per user request
    ) -> [SCNVector3] {
        var points: [SCNVector3] = []
        
        // Convert to Cartesian
        let startPos = latLongToCartesian(latitude: startLat, longitude: startLon)
        let endPos = latLongToCartesian(latitude: endLat, longitude: endLon)
        
        // Calculate Chord Distance (Euclidean distance between start and end on unit sphere)
        let dx = endPos.x - startPos.x
        let dy = endPos.y - startPos.y
        let dz = endPos.z - startPos.z
        let chordDistance = sqrt(dx*dx + dy*dy + dz*dz)
        
        // Quadratic Bezier Control Point Calculation
        // Vector to midpoint
        var midX = startPos.x + endPos.x
        var midY = startPos.y + endPos.y
        var midZ = startPos.z + endPos.z
        
        // Normalize mid vector
        let midLen = sqrt(midX*midX + midY*midY + midZ*midZ)
        if midLen < 0.001 {
            // Antipodal: Needs arbitrary perpendicular
            midX = 0; midY = 1; midZ = 0
        } else {
            midX /= midLen
            midY /= midLen
            midZ /= midLen
        }
        
        // -------------------------------------------------------------------------
        // USER REQUEST LOGIC: Variable Altitude + Jitter
        // "Short flights hug the earth (1.05), Long flights go high (1.3)"
        // "Add a tiny random jitter so two identical routes don't z-fight"
        // Formula: 1.05 + (distance * 0.2) + jitter
        // -------------------------------------------------------------------------
        
        let jitter = Float.random(in: 0.001...0.005)
        let altitude = 1.05 + (chordDistance * 0.2) + jitter
        
        // Control Point C is along the midpoint vector at distance `altitude`.
        // Note: For a Quadratic Bezier, the peak is at t=0.5.
        // Peak(0.5) = 0.25*P0 + 0.5*C + 0.25*P1
        // Since P0, P1 are on surface (dist 1.0) and symmetric:
        // P0+P1 = 2 * cos(halfAngle) * MidVector
        // Peak(0.5) = 0.5 * cos(halfAngle) * MidVector + 0.5 * C
        // If C = H_c * MidVector, then Peak Height = 0.5 * (cos(halfAngle) + H_c)
        // User's `altitude` likely refers to the Control Point height directly (as per their snippet).
        // "push it OUTWARDS to the calculated altitude" -> C = Mid * altitude.
        // We will follow the user's snippet logic exactly.
        
        let cX = midX * altitude
        let cY = midY * altitude
        let cZ = midZ * altitude
        
        // Generate Bezier Points
        for i in 0...segments {
            let t = Float(i) / Float(segments)
            let omt = 1.0 - t
            let omt2 = omt * omt
            let t2 = t * t
            let two_omt_t = 2.0 * omt * t
            
            let pX = omt2 * startPos.x + two_omt_t * cX + t2 * endPos.x
            let pY = omt2 * startPos.y + two_omt_t * cY + t2 * endPos.y
            let pZ = omt2 * startPos.z + two_omt_t * cZ + t2 * endPos.z
            
            points.append(SCNVector3(pX, pY, pZ))
        }
        
        return points
    }
}
