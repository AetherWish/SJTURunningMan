//
//  MainView.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/5/4.
//


import SwiftUI

// MARK: - Glass Style
struct GlassCard: ViewModifier {
    let material: Material

    func body(content: Content) -> some View {
        content
            .padding()
            .background(material.opacity(0.55))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            )
    }
}

extension View {
    func glassCard(material: Material = .thinMaterial) -> some View {
        modifier(GlassCard(material: material))
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .purple.opacity(0.15)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct MainView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var showLogin = false

    // 参数状态
    @State private var days = 1
    @State private var showCustomDays = false
    @State private var customDaysText = ""

    @State private var hour = 8
    @State private var minute = 0
    @State private var showCustomTime = false

    @State private var startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    @State private var showDatePicker = false

    @State private var distanceKm = 5.0
    @State private var showRouteDesign = false
    @State private var showDeleteRouteAlert = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 参数卡片
                    VStack(alignment: .leading, spacing: 12) {
                        Text("任务参数").font(.headline)
                        Divider().overlay(.white.opacity(0.3))

                        // 路线选择
                        SettingRow(icon: "point.topleft.down.curvedto.point.bottomright.up", label: "跑步路线") {
                            HStack(spacing: 4) {
                                DropdownButton(
                                    items: viewModel.routes.map { route in
                                        "\(route.name) (\(route.pointCount)点)"
                                    } + ["设计新路线"],
                                    selected: viewModel.selectedRoute.map { "\($0.name) (\($0.pointCount)点)" } ?? "选择路线"
                                ) { item in
                                    if item == "设计新路线" {
                                        showRouteDesign = true
                                    } else {
                                        if let route = viewModel.routes.first(where: {
                                            "\($0.name) (\($0.pointCount)点)" == item
                                        }) {
                                            viewModel.selectRoute(route)
                                        }
                                    }
                                }

                                // Delete button for custom routes
                                if let route = viewModel.selectedRoute, !route.isDefault {
                                    Button(role: .destructive) {
                                        showDeleteRouteAlert = true
                                    } label: {
                                        Image(systemName: "trash.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.title3)
                                    }
                                }
                            }
                        }
                        SettingRow(icon: "calendar", label: "跑步天数") {
                            if !showCustomDays {
                                DropdownButton(items: ["1 天", "3 天", "5 天", "7 天", "10 天", "15 天", "30 天", "自定义"],
                                               selected: "\(days) 天") { item in
                                    if item == "自定义" { showCustomDays = true }
                                    else if let d = Int(item.replacingOccurrences(of: " 天", with: "")) {
                                        days = d
                                    }
                                }
                            } else {
                                HStack {
                                    TextField("天数", text: $customDaysText)
                                        #if os(iOS)
                                        .keyboardType(.numberPad)
                                        #endif
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Button("确定") {
                                        if let d = Int(customDaysText), d > 0 { days = d }
                                        showCustomDays = false
                                    }
                                }
                            }
                        }

                        // 时间
                        SettingRow(icon: "clock", label: "开始时间") {
                            if !showCustomTime {
                                DropdownButton(items: (6...22).map { String(format: "%02d:00", $0) } + ["自定义"],
                                               selected: String(format: "%02d:%02d", hour, minute)) { item in
                                    if item == "自定义" {
                                        showCustomTime = true
                                    } else {
                                        let parts = item.split(separator: ":")
                                        hour = Int(parts[0]) ?? 8
                                        minute = Int(parts[1]) ?? 0
                                    }
                                }
                            } else {
                                HStack {
                                    TextField("时", value: $hour, formatter: NumberFormatter())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 50)
                                    Text(":")
                                    TextField("分", value: $minute, formatter: NumberFormatter())
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 50)
                                    Button("确定") { showCustomTime = false }
                                }
                            }
                        }

                        // 日期
                        SettingRow(icon: "calendar.badge.clock", label: "起始日期") {
                            Button {
                                if !viewModel.isRunning { showDatePicker = true }
                            } label: {
                                Text(startDate, style: .date)
                                    .foregroundColor(.primary)
                            }
                            .disabled(viewModel.isRunning)
                        }

                        // 距离滑块
                        SettingRow(icon: "figure.run", label: "目标距离") {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(Int(distanceKm)) km").bold()
                                    .foregroundStyle(
                                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                    )
                                Slider(value: $distanceKm, in: 1...5, step: 1)
                                    .tint(.purple)
                                    .frame(width: 140)
                            }
                        }
                    }
                    .glassCard()

                    // 重新登录提示
                    if viewModel.needRelogin {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("检测到cookie过期，请重新登录")
                                .font(.callout)
                            Spacer()
                            Button("重新登录") {
                                showLogin = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }

                    // 按钮组
                    HStack(spacing: 12) {
                        Button {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd"
                            viewModel.startUpload(days: days,
                                                  distanceKm: Int(distanceKm),
                                                  hour: hour,
                                                  minute: minute,
                                                  dateString: formatter.string(from: startDate))
                        } label: {
                            Label("开始任务", systemImage: "play.fill")
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(viewModel.isRunning)

                        Button {
                            viewModel.stopUpload()
                        } label: {
                            Label("停止任务", systemImage: "stop.fill")
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(!viewModel.isRunning)
                    }

                    // 日志区域
                    VStack(alignment: .leading, spacing: 8) {
                        Text("运行日志")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                Text(viewModel.logText)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .id("logBottom")
                            }
                            .frame(height: 300)
                            .background(.thinMaterial)
                            .cornerRadius(12)
                            .onChange(of: viewModel.logText) { _ in
                                scrollProxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                    }
                    .glassCard()
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.28),
                        Color(red: 0.15, green: 0.06, blue: 0.25),
                        Color(red: 0.05, green: 0.10, blue: 0.20),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .scrollContentBackground(.hidden)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SJTURunningMan")
                        .font(.system(size: 22, weight: .semibold))
                        .italic()
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                }
            }
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .sheet(isPresented: $showLogin, onDismiss: {
                viewModel.reloginCompleted()
            }) {
                LoginView {
                    showLogin = false
                    viewModel.reloginCompleted()
                }
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $startDate, isPresented: $showDatePicker)
            }
            .sheet(isPresented: $showRouteDesign, onDismiss: {
                viewModel.refreshRoutes()
            }) {
                RouteDesignView()
            }
            .alert("删除路线", isPresented: $showDeleteRouteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    if let route = viewModel.selectedRoute {
                        viewModel.deleteRoute(route)
                    }
                }
            } message: {
                Text("确定要删除路线「\(viewModel.selectedRoute?.name ?? "")」吗？此操作不可撤销。")
            }
            .onAppear {
                viewModel.loadRoutes()
                checkLoginStatus()
            }
        }
    }

    private func checkLoginStatus() {
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://jaccount.sjtu.edu.cn")!) {
            if cookies.contains(where: { $0.name == "JAAuthCookie" }) {
                // 已登录，什么也不做
            } else {
                showLogin = true
            }
        } else {
            showLogin = true
        }
    }
}

// MARK: - 辅助组件

struct SettingRow<Content: View>: View {
    let icon: String
    let label: String
    let content: Content

    init(icon: String, label: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.secondary)
            Text(label)
                .frame(width: 72, alignment: .leading)
            Spacer()
            content
        }
    }
}

struct DropdownButton: View {
    let items: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button(action: { onSelect(item) }) {
                    Text(item)
                }
            }
        } label: {
            HStack {
                Text(selected)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial)
            .cornerRadius(8)
        }
    }
}

struct DatePickerSheet: View {
    @Binding var date: Date
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            DatePicker("选择日期", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("起始日期")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") { isPresented = false }
                    }
                }
        }
    }
}