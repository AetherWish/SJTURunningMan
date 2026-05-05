//
//  MainView.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/5/4.
//


import SwiftUI

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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // 参数卡片
                    Group {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("任务参数").font(.headline)
                            Divider()
                            
                            // 天数
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
                                            .keyboardType(.numberPad)
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
                            VStack(alignment: .leading) {
                                HStack {
                                    Image(systemName: "figure.run").foregroundColor(.secondary)
                                    Text("目标距离")
                                    Spacer()
                                    Text("\(Int(distanceKm)) km").bold().foregroundColor(.accentColor)
                                }
                                Slider(value: $distanceKm, in: 1...5, step: 1) {
                                    Text("distance")
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.05), radius: 10)
                    }
                    
                    // 重新登录提示
                    if viewModel.needRelogin {
                        VStack {
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
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
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
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isRunning)
                        
                        Button {
                            viewModel.stopUpload()
                        } label: {
                            Label("停止任务", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
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
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .onChange(of: viewModel.logText) { _ in
                                scrollProxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("交我润")
            .navigationBarTitleDisplayMode(.inline)
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
            .onAppear {
                checkLoginStatus()
            }
        }
    }
    
    private func checkLoginStatus() {
        // 简单的 cookie 检查，注意启动时可能没有 session cookie，但我们仍需检查 jAccount 主域 cookie
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
            Spacer()
            content
        }
    }
}

struct DropdownButton: View {
    let items: [String]
    @State var selected: String
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
            .background(Color(.tertiarySystemFill))
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
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("确定") { isPresented = false }
                    }
                }
        }
    }
}