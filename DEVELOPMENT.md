# AeroGlobe Developer Documentation

## 1. Getting Started

### Prerequisites
- Xcode 15+
- iOS 17.0+ Simulator/Device
- Swift 5.9+

### Building the Project
1. Open `AeroGlobe.xcodeproj`.
2. Ensure you have the `earth_night_8k` assets in `Assets.xcassets`.
3. Select an iOS Simulator (e.g., iPhone 15 Pro).
4. Press `Cmd+R` to build and run.

> **Note**: The 8K texture is memory-intensive. For simulator builds, we use a resized 2K or 4K version.

## 2. Architecture Overview

AeroGlobe follows a **MVVM** pattern with a heavy SceneKit rendering layer.

### Key Components

- **Render Layer**:
    - `GlobeView.swift`: The SwiftUI wrapper for the SceneKit view.
    - `GlobeSceneController.swift`: Manages the 3D scene, camera, earth node, and flight path geometry.
    - `GeoMath.swift`: Pure math utilities for spherical coordinates and Bézier curves.

- **Data Layer**:
    - `Flight.swift`: SwiftData model for flight entries.
    - `AirportService.swift`: Singleton responsible for loading and querying the `airports.json` database.

- **Feature Layers**:
    - **AeroRank**: Gamification logic (`UserRank.swift`) and UI (`RankProgressCard.swift`).
    - **Calendar Import**: `CalendarImporter.swift` scans the user's `EKEventStore` for flight keywords.

## 3. AeroRank System (Gamification)

The app "levels up" users based on total miles flown.

**Logic**: See `UserRank.swift`. Rank is determined by `UserRank.current(for: miles)`.
- Taxi: 0 - 5k
- Takeoff: 5k - 25k
- Stratosphere: 25k - 100k
- Supersonic: 100k - 250k
- Orbit: 250k+

**Visuals**:
- The **RankProgressCard** changes color based on `UserRank.color`.
- The **3D Flight Paths** glow in the neon color of the current rank (passed to `GlobeSceneController`).

## 4. Flight Path Rendering (Bézier Polish)

Flight paths are not simple "Great Circle" arcs (which would clip through the earth) but **Quadratic Bézier Curves**.

- The **Control Point** is calculated to be strictly above the intersection of surface tangents at the start/end points.
- This ensures the curve launches "upward" and never clips the sphere.
- **Neon Glow**: Each path consists of two cylinders: a thin inner core (solid) and a thicker outer shell (transparent/glowing).

## 5. Adding New Features

1. **Models**: Update `Flight` schema if needed. SwiftData uses `@Model`.
2. **Views**: Add pure SwiftUI views in `Views/`.
3. **3D**: If changing the globe, edit `GlobeSceneController`. Ensure thread safety when calling SceneKit from SwiftUI (use `MainActor` or `DispatchQueue.main`).
