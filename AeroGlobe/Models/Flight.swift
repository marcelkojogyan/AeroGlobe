import Foundation
import SwiftData

@Model
final class Flight {
    var id: UUID
    var date: Date
    var flightNumber: String?
    var originCode: String
    var originLat: Double
    var originLong: Double
    var destCode: String
    var destLat: Double
    var destLong: Double
    var distance: Int  // Distance in miles
    
    init(
        id: UUID = UUID(),
        date: Date,
        flightNumber: String? = nil,
        originCode: String,
        originLat: Double,
        originLong: Double,
        destCode: String,
        destLat: Double,
        destLong: Double,
        distance: Int
    ) {
        self.id = id
        self.date = date
        self.flightNumber = flightNumber
        self.originCode = originCode
        self.originLat = originLat
        self.originLong = originLong
        self.destCode = destCode
        self.destLat = destLat
        self.destLong = destLong
        self.distance = distance
    }
}
