import SwiftUI
import MapKit

/// 行程轨迹回放：把本次采样点连成折线画在地图上，支持缩放查看路线。
struct TrackReplayView: UIViewRepresentable {
    let points: [TrackPoint]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.showsUserLocation = false
        return map
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.delegate = context.coordinator
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations)

        guard !points.isEmpty else { return }

        let coords = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

        // 轨迹折线
        let polyline = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(polyline)

        // 起点 / 终点标注
        if let first = points.first {
            let start = MKPointAnnotation()
            start.coordinate = CLLocationCoordinate2D(latitude: first.latitude, longitude: first.longitude)
            start.title = "起点"
            map.addAnnotation(start)
        }
        if let last = points.last, points.count > 1 {
            let end = MKPointAnnotation()
            end.coordinate = CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude)
            end.title = "终点"
            map.addAnnotation(end)
        }

        // 自适应缩放
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        if let minLat = lats.min(), let maxLat = lats.max(),
           let minLon = lons.min(), let maxLon = lons.max() {
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
            let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
                                         longitudeDelta: max((maxLon - minLon) * 1.4, 0.01))
            map.region = MKCoordinateRegion(center: center, span: span)
        }
    }
}

extension TrackReplayView {
    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 5
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

/// 页面容器：标题 + 采样点数 + 地图
struct TrackReplayContainer: View {
    let points: [TrackPoint]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrackReplayView(points: points)
                .ignoresSafeArea()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("\(points.count) 个采样点")
                            .font(.caption)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
        }
    }
}
