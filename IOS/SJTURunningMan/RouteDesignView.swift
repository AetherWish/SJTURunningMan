//
//  RouteDesignView.swift
//  SJTURunningMan
//
//  Created by Jie Tang on 2026/7/8.
//

import SwiftUI
import MapKit

struct RouteDesignView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var waypoints: [Waypoint] = []
    @State private var routeName = ""
    @State private var selectedWaypointId: UUID?

    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 31.031, longitude: 121.438),
        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
    ))

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                mapView
                toolbarView
                bottomDeleteButton
            }
            .navigationTitle("设计路线")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $camera, selection: $selectedWaypointId) {
                if waypoints.count >= 2 {
                    MapPolyline(coordinates: waypoints.map { $0.coord })
                        .stroke(.blue, lineWidth: 3)
                }
                ForEach(waypoints) { wp in
                    Annotation("", coordinate: wp.coord) {
                        waypointMarker(for: wp)
                    }
                    .tag(wp.id)
                }
            }
            .mapStyle(.standard)
            .onTapGesture { position in
                guard let coord = proxy.convert(position, from: .local) else { return }
                let newWp = Waypoint(index: waypoints.count + 1, coord: coord)
                waypoints.append(newWp)
                selectedWaypointId = nil
            }
        }
    }

    private func waypointMarker(for wp: Waypoint) -> some View {
        ZStack {
            Circle()
                .fill(wp.id == selectedWaypointId ? Color.red : Color.blue)
                .frame(width: 28, height: 28)
            Text("\(wp.index)")
                .font(.caption2)
                .bold()
                .foregroundColor(.white)
        }
        .shadow(radius: 2)
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("路线名称", text: $routeName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Text("\(waypoints.count) 个点")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial)
                    .cornerRadius(8)

                Spacer()

                Button(role: .destructive) {
                    waypoints.removeAll()
                    selectedWaypointId = nil
                } label: {
                    Label("清除", systemImage: "trash")
                        .font(.caption)
                }
                .disabled(waypoints.isEmpty)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .cornerRadius(8)

                Button {
                    saveRoute()
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .font(.caption)
                }
                .disabled(waypoints.count < 2 || routeName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .cornerRadius(8)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if waypoints.isEmpty {
                Text("点击地图添加路径点，至少需要 2 个点")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
            }

            Spacer()
        }
    }

    // MARK: - Bottom Delete

    @ViewBuilder
    private var bottomDeleteButton: some View {
        if let selectedId = selectedWaypointId {
            VStack {
                Spacer()
                HStack {
                    Button(role: .destructive) {
                        waypoints.removeAll { $0.id == selectedId }
                        selectedWaypointId = nil
                        reindexWaypoints()
                    } label: {
                        let idx = waypoints.first(where: { $0.id == selectedId })?.index ?? 0
                        Label("删除点 #\(idx)", systemImage: "xmark.circle.fill")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                    Button {
                        selectedWaypointId = nil
                    } label: {
                        Text("取消")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                    .cornerRadius(8)
                }
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Helpers

    private func reindexWaypoints() {
        for i in waypoints.indices {
            waypoints[i].index = i + 1
        }
    }

    private func saveRoute() {
        let name = routeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, waypoints.count >= 2 else { return }
        let coords = waypoints.map { Coord(lon: $0.coord.longitude, lat: $0.coord.latitude) }
        _ = RouteManager.shared.saveCustomRoute(name: name, coordinates: coords)
        dismiss()
    }
}

// MARK: - Waypoint Model

private struct Waypoint: Identifiable {
    let id = UUID()
    var index: Int
    let coord: CLLocationCoordinate2D
}
