//
//  RouteInfo.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/7/8.
//

import Foundation

struct RouteInfo: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let filePath: String      // relative path in Documents/routes/, or "" for default
    let isDefault: Bool
    let pointCount: Int
    let createdAt: Date

    static func == (lhs: RouteInfo, rhs: RouteInfo) -> Bool {
        lhs.id == rhs.id
    }
}
