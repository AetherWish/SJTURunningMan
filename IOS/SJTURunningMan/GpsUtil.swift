//
//  GpsUtil.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/5/4.
//


import Foundation

struct GpsUtil {
    static let earthRadius: Double = 6371000.0

    static func haversineDistance(lat1: Double, lon1: Double,
                                  lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1).degreesToRadians
        let dLon = (lon2 - lon1).degreesToRadians
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1.degreesToRadians) * cos(lat2.degreesToRadians) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    static func readCoordinates() -> [Coord] {
        guard let url = Bundle.main.url(forResource: "route_coordinates", withExtension: nil) else {
            print("❌ route_coordinates not found in bundle")
            return []
        }
        do {
            let text = try String(contentsOf: url)
            return text.split(separator: "\n").compactMap { line -> Coord? in
                let parts = line.split(separator: ",")
                guard parts.count == 2,
                      let lon = Double(parts[0]),
                      let lat = Double(parts[1]) else { return nil }
                return Coord(lon: lon, lat: lat)
            }
        } catch {
            print("❌ Cannot read route_coordinates: \(error)")
            return []
        }
    }
}

struct Coord {
    let lon: Double
    let lat: Double
}

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
}