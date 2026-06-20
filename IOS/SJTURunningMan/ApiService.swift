//
//  ApiService.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/5/4.
//


import Foundation
import WebKit  // 需要用来访问 WKWebsiteDataStore

class ApiService {
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    
    // 同步 WebView 的 cookie 到 HTTPCookieStorage
    static func syncCookiesFromWebView(completion: @escaping () -> Void) {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            completion()
        }
    }
    
    // 清除所有 cookie
    func clearCookies() {
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
    }
    
    private func isJAccountLoginPage(_ content: String) -> Bool {
        return content.contains("Login jAccount") ||
               content.contains("jaccount.sjtu.edu.cn") ||
               content.contains("扫码登录") ||
               content.contains("Scan QR code") ||
               content.contains("统一身份认证")
    }
    
    func getUid() async -> String? {
        guard let url = URL(string: "https://pe.sjtu.edu.cn/sports/my/uid") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("okhttp/4.10.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }
            let body = String(data: data, encoding: .utf8) ?? ""
            print("DEBUG: UID response code \(httpResponse.statusCode)")
            print("DEBUG: UID response body: \(body.prefix(300))")
            
            if isJAccountLoginPage(body) || httpResponse.statusCode == 302 || httpResponse.statusCode == 403 {
                print("DEBUG: 需要重新登录")
                return nil
            }
            
            // 尝试解析 JSON
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let code = json["code"] as? Double, code == 0,
                   let dataObj = json["data"] as? [String: Any],
                   let uid = dataObj["uid"] as? String {
                    return uid
                } else {
                    print("DEBUG: API返回错误: \(json)")
                    return nil
                }
            } else {
                // 可能直接返回纯文本 uid
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && trimmed.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil {
                    return trimmed
                }
                return nil
            }
        } catch {
            print("获取 UID 失败: \(error)")
            return nil
        }
    }
    
    func upload(authToken: String, payload: [[String: Any]]) async -> (success: Bool, message: String, needRelogin: Bool) {
        guard let url = URL(string: "https://pe.sjtu.edu.cn/api/running/result/upload") else {
            return (false, "URL error", false)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData
        } catch {
            return (false, "Payload serialization error", false)
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "No response", false)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            print("UPLOAD response code: \(httpResponse.statusCode)")
            print("UPLOAD body: \(body.prefix(200))")
            
            if isJAccountLoginPage(body) || httpResponse.statusCode == 403 || httpResponse.statusCode == 401 {
                return (false, "cookie已过期，需要重新登录", true)
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["code"] as? Int, code == 0 {
                return (true, json["message"] as? String ?? "成功", false)
            } else {
                return (false, body, false)
            }
        } catch {
            return (false, "网络错误: \(error.localizedDescription)", false)
        }
    }
}
