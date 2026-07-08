//
//  RouteManager.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/7/8.
//

import Foundation

@MainActor
class RouteManager {
    static let shared = RouteManager()

    private let fileManager = FileManager.default
    private let metadataKey = "route_metadata"

    private var routesDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("routes")
    }

    // MARK: - Default Route

    func getDefaultRoute() -> RouteInfo {
        let coords = GpsUtil.readCoordinates()
        return RouteInfo(
            id: "default",
            name: "思源湖路线",
            filePath: "",
            isDefault: true,
            pointCount: coords.count,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Custom Routes Metadata

    func getCustomRoutes() -> [RouteInfo] {
        guard let data = UserDefaults.standard.data(forKey: metadataKey) else {
            return []
        }
        do {
            let routes = try JSONDecoder().decode([RouteInfo].self, from: data)
            // Filter out routes whose files no longer exist
            return routes.filter { route in
                let url = routesDir.appendingPathComponent(route.filePath)
                return fileManager.fileExists(atPath: url.path)
            }
        } catch {
            print("❌ Failed to decode route metadata: \(error)")
            return []
        }
    }

    func getAllRoutes() -> [RouteInfo] {
        [getDefaultRoute()] + getCustomRoutes()
    }

    // MARK: - Save / Delete

    func saveCustomRoute(name: String, coordinates: [Coord]) -> RouteInfo? {
        // Ensure routes directory exists
        try? fileManager.createDirectory(at: routesDir, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let fileName = "\(id).txt"
        let fileURL = routesDir.appendingPathComponent(fileName)

        // Write coordinate file
        let content = coordinates.map { "\($0.lon),\($0.lat)" }.joined(separator: "\n")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("❌ Failed to write route file: \(error)")
            return nil
        }

        let route = RouteInfo(
            id: id,
            name: name,
            filePath: fileName,
            isDefault: false,
            pointCount: coordinates.count,
            createdAt: Date()
        )

        // Update metadata
        var routes = getCustomRoutes()
        routes.append(route)
        saveMetadata(routes)

        return route
    }

    func deleteRoute(id: String) {
        var routes = getCustomRoutes()
        guard let route = routes.first(where: { $0.id == id }) else { return }

        // Delete file
        let fileURL = routesDir.appendingPathComponent(route.filePath)
        try? fileManager.removeItem(at: fileURL)

        // Update metadata
        routes.removeAll { $0.id == id }
        saveMetadata(routes)
    }

    // MARK: - Read Coordinates

    func getRouteCoordinates(for route: RouteInfo) -> [Coord] {
        if route.isDefault {
            return GpsUtil.readCoordinates()
        } else {
            let fileURL = routesDir.appendingPathComponent(route.filePath)
            return GpsUtil.readCoordinates(from: fileURL)
        }
    }

    // MARK: - Private

    private func saveMetadata(_ routes: [RouteInfo]) {
        do {
            let data = try JSONEncoder().encode(routes)
            UserDefaults.standard.set(data, forKey: metadataKey)
        } catch {
            print("❌ Failed to encode route metadata: \(error)")
        }
    }
}
