//
//  MainViewModel.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/5/4.
//


import SwiftUI
import Foundation
import Combine

@MainActor
class MainViewModel: ObservableObject {
    @Published var logText = "就绪。点击\"开始任务\"启动。"
    @Published var isRunning = false
    @Published var needRelogin = false
    
    private let api = ApiService()
    private var uploadTask: Task<Void, Never>?
    
    func startUpload(days: Int, distanceKm: Int, hour: Int, minute: Int, dateString: String?) {
        guard !isRunning else { return }
        isRunning = true
        logText = ""
        
        uploadTask = Task {
            await log("步骤1: 获取 UID...")
            guard let uid = await api.getUid() else {
                await log("UID 获取失败，可能需要重新登录")
                needRelogin = true
                isRunning = false
                return
            }
            await log("UID 获取成功: \(uid)")
            
            let coordinates = GpsUtil.readCoordinates()
            await log("路线点数量: \(coordinates.count)")
            let targetDistanceM = distanceKm * 1000
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let startDate: Date
            if let ds = dateString, let d = dateFormatter.date(from: ds) {
                startDate = d
            } else {
                startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            }
            
            for i in 0..<days {
                if Task.isCancelled { break }
                let date = Calendar.current.date(byAdding: .day, value: -i, to: startDate)!
                
                // 随机 -10～+10 分钟偏移
                let randomOffsetSec = Int.random(in: -600...600)
                var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                components.hour = hour
                components.minute = minute
                let baseTime = Calendar.current.date(from: components)!
                let startTime = baseTime.addingTimeInterval(TimeInterval(randomOffsetSec))
                let startTimeMs = Int64(startTime.timeIntervalSince1970 * 1000)
                
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "HH:mm:ss"
                let displayTime = displayFormatter.string(from: startTime)
                
                await log("生成第 \(i + 1)/\(days) 条数据 (\(dateFormatter.string(from: date)) \(displayTime))...")
                
                let result = await DataGenerator.generate(
                    coordinates: coordinates,
                    userId: uid,
                    targetDistanceM: targetDistanceM,
                    startTimeMs: startTimeMs,
                    intervalSeconds: 3
                ) { msg in
                    Task { await self.log(msg) }
                }
                
                let (payload, actualDist) = result
                await log("实际距离: \(String(format: "%.2f", actualDist)) m")
                
                await log("上传第 \(i + 1)/\(days) 条...")
                let uploadResult = await api.upload(authToken: uid, payload: payload)
                
                if uploadResult.success {
                    await log("第 \(i + 1) 条上传成功")
                } else {
                    if uploadResult.needRelogin {
                        await log("上传失败: \(uploadResult.message)，需要重新登录")
                        needRelogin = true
                        break
                    } else {
                        await log("失败: \(uploadResult.message)")
                    }
                }
            }
            await log("全部任务完成")
            isRunning = false
        }
    }
    
    func stopUpload() {
        uploadTask?.cancel()
        isRunning = false
    }
    
    func reloginCompleted() {
        needRelogin = false
    }
    
    private func log(_ message: String) async {
        let timeStr = DateFormatter.timeOnly.string(from: Date())
        logText += "\n\(timeStr) \(message)"
    }
}

extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
