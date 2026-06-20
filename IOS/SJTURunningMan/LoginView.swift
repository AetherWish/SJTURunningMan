//
//  LoginView.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/5/5.
//


import SwiftUI
import WebKit

#if canImport(UIKit)
import UIKit

struct LoginView: UIViewControllerRepresentable {
    let onLoginComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoginComplete: onLoginComplete)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // 清除旧 cookie，确保干净登录
        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
            }
        }

        // 移动端 User-Agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/89.0.4389.72"

        if let url = URL(string: "https://jaccount.sjtu.edu.cn/oauth2/authorize?response_type=code&scope=profile&client_id=9mqzULSXYgUYj5fPOpyL&state=8&redirect_uri=https://pe.sjtu.edu.cn/oauth2Login") {
            webView.load(URLRequest(url: url))
        }

        let vc = UIViewController()
        vc.view = webView
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.webView = nil
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        let onLoginComplete: () -> Void

        init(onLoginComplete: @escaping () -> Void) {
            self.onLoginComplete = onLoginComplete
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "jaccount" {
                UIApplication.shared.open(url) { _ in }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            print("Login page finished: \(url.absoluteString)")

            let jsessionidCookie = HTTPCookieStorage.shared.cookies(for: URL(string: "https://pe.sjtu.edu.cn")!)?.first { $0.name == "JSESSIONID" }
            let isOauthCallback = url.absoluteString.hasPrefix("https://pe.sjtu.edu.cn/oauth2Login")
            let isMainPage = url.absoluteString.hasPrefix("https://pe.sjtu.edu.cn") &&
                             !url.absoluteString.contains("oauth2/authorize") &&
                             !url.absoluteString.contains("jaccount")

            if isOauthCallback || jsessionidCookie != nil || isMainPage {
                print("Login complete detected")
                ApiService.syncCookiesFromWebView {
                    DispatchQueue.main.async {
                        self.onLoginComplete()
                    }
                }
            }
        }
    }
}

#else
// MARK: - macOS AppKit fallback

import AppKit

struct LoginView: NSViewRepresentable {
    let onLoginComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoginComplete: onLoginComplete)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
            }
        }

        if let url = URL(string: "https://jaccount.sjtu.edu.cn/oauth2/authorize?response_type=code&scope=profile&client_id=9mqzULSXYgUYj5fPOpyL&state=8&redirect_uri=https://pe.sjtu.edu.cn/oauth2Login") {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        let onLoginComplete: () -> Void

        init(onLoginComplete: @escaping () -> Void) {
            self.onLoginComplete = onLoginComplete
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "jaccount" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            print("Login page finished: \(url.absoluteString)")

            let jsessionidCookie = HTTPCookieStorage.shared.cookies(for: URL(string: "https://pe.sjtu.edu.cn")!)?.first { $0.name == "JSESSIONID" }
            let isOauthCallback = url.absoluteString.hasPrefix("https://pe.sjtu.edu.cn/oauth2Login")
            let isMainPage = url.absoluteString.hasPrefix("https://pe.sjtu.edu.cn") &&
                             !url.absoluteString.contains("oauth2/authorize") &&
                             !url.absoluteString.contains("jaccount")

            if isOauthCallback || jsessionidCookie != nil || isMainPage {
                print("Login complete detected")
                ApiService.syncCookiesFromWebView {
                    DispatchQueue.main.async {
                        self.onLoginComplete()
                    }
                }
            }
        }
    }
}
#endif