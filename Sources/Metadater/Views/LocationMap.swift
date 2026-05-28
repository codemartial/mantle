import SwiftUI
import MapKit
import AppKit

// MKMapView wrapped for SwiftUI. AppKit (not SwiftUI Map) because:
// - draggable annotations come for free via MKAnnotationView.isDraggable
// - SwiftUI Map on macOS 14 doesn't expose draggable annotations cleanly
//
// The direction cone is rendered in a SwiftUI Canvas overlaid on top of
// the map (not as an MKOverlay). The coordinator computes the pin's
// screen position and the cone's radius in pixels on every region
// change, publishes that via a callback, and the Canvas draws a clipped
// radial gradient -- soft accent at the pin, fading to transparent at
// the arc. Doing it this way avoids the MKOverlayRenderer clipping path
// quirks that made the previous attempt leak across the whole bounding
// rect.

struct LocationMap: View {
    @Environment(AppState.self) private var state
    @State private var recenterToken: Int = 0
    @State private var layout: ConeLayout?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MapRepresentable(
                record: state.selectedRecord,
                mapStyle: state.mapStyle,
                recenterToken: recenterToken,
                onDrag: { lat, lon in
                    guard let id = state.selectedRecord?.id else { return }
                    state.updateLocation(id: id, lat: lat, lon: lon)
                },
                onLayout: { layout = $0 },
                log: { [weak state] line in state?.debugLog.append(line) }
            )

            if let layout, let dir = state.selectedRecord?.direction {
                Canvas { ctx, _ in
                    drawCone(in: ctx, at: layout, direction: dir)
                }
                .allowsHitTesting(false)
            }

            recenterButton
                .padding(8)
        }
    }

    private func drawCone(in ctx: GraphicsContext,
                          at layout: ConeLayout,
                          direction: Double) {
        let center = layout.center
        let radius = layout.radius
        let half: Double = 30   // half-angle (degrees) -- 60-degree wedge

        // SwiftUI/CG angle convention: 0deg points east (positive X), then
        // clockwise in y-down coords. Compass bearing: 0deg north,
        // clockwise. Convert: cgAngle = compass - 90.
        let startAngle = Angle(degrees: direction - half - 90)
        let endAngle   = Angle(degrees: direction + half - 90)

        var path = Path()
        path.move(to: center)
        path.addArc(center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: false)
        path.closeSubpath()

        ctx.fill(
            path,
            with: .radialGradient(
                Gradient(colors: [
                    Theme.accent.opacity(0.65),
                    Theme.accent.opacity(0.0),
                ]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )
    }

    private var hasCoord: Bool {
        state.selectedRecord?.latitude != nil &&
        state.selectedRecord?.longitude != nil
    }

    private var recenterButton: some View {
        Button {
            recenterToken &+= 1
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.fg)
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line1, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Recentre on pin")
        .disabled(!hasCoord)
        .opacity(hasCoord ? 1 : 0.35)
    }
}

// Pin's screen position (in MKMapView local coords) and the cone radius
// in pixels (distance, in pixels, from pin to a point `radiusMeters` away
// along the bearing axis at the current zoom).
struct ConeLayout: Equatable {
    let center: CGPoint
    let radius: CGFloat
}

// MARK: - NSViewRepresentable

private struct MapRepresentable: NSViewRepresentable {
    let record: ImageRecord?
    let mapStyle: MapStyleChoice
    let recenterToken: Int
    let onDrag: (Double, Double) -> Void
    let onLayout: (ConeLayout?) -> Void
    let log: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrag: onDrag, onLayout: onLayout, log: log)
    }

    func makeNSView(context: Context) -> MKMapView {
        let map = DragOnlyMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = false
        map.showsZoomControls = true
        map.pointOfInterestFilter = .excludingAll
        map.isPitchEnabled = false
        map.isRotateEnabled = true

        // Republish layout whenever AppKit resizes the map. The first call
        // from updateNSView fires before the view has its real bounds, so
        // without this notification the cone would render with stale
        // coords until the user pans/zooms.
        map.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.mapFrameChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: map
        )

        // Click-to-place: when the current image has no pin yet, a plain
        // click drops one at the click point. Once a pin exists the
        // recognizer no-ops (the user can drag the existing pin). NSClick-
        // GestureRecognizer auto-fails on movement, so pan still works.
        let clickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClickToPlace(_:))
        )
        clickRecognizer.numberOfClicksRequired = 1
        map.addGestureRecognizer(clickRecognizer)

        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.onDrag = onDrag
        context.coordinator.onLayout = onLayout
        context.coordinator.log = log
        map.mapType = (mapStyle == .hybrid) ? .hybrid : .standard
        context.coordinator.sync(record: record, on: map)
        context.coordinator.applyRecenterIfNeeded(token: recenterToken, on: map, record: record)
    }
}

// MARK: - MKMapView subclass

// Two changes from stock MKMapView:
// 1. Scroll-wheel / two-finger-scroll events bubble up to the enclosing
//    ScrollView so the metadata pane scrolls naturally; the map is panned
//    only by click-drag. Pinch (magnify) still zooms.
// 2. Open-hand cursor on hover, so the grab affordance is visible without
//    the user having to click first to discover panability.
private final class DragOnlyMapView: MKMapView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }
}

// MARK: - Annotation

private final class LocationPin: MKPointAnnotation {}

// MARK: - Coordinator

private final class Coordinator: NSObject, MKMapViewDelegate {

    var onDrag: (Double, Double) -> Void
    var onLayout: (ConeLayout?) -> Void
    var log: (String) -> Void

    private var lastRecordID: String?
    private var pin: LocationPin?
    private var currentDirection: Double?
    private var lastRecenterToken: Int = 0

    init(onDrag: @escaping (Double, Double) -> Void,
         onLayout: @escaping (ConeLayout?) -> Void,
         log: @escaping (String) -> Void) {
        self.onDrag = onDrag
        self.onLayout = onLayout
        self.log = log
        super.init()
    }

    func sync(record: ImageRecord?, on map: MKMapView) {
        let recID = record?.id
        let recCoord = coord(from: record)
        currentDirection = record?.direction

        if recID != lastRecordID {
            clearPin(on: map)
            lastRecordID = recID

            if let coord = recCoord {
                installPin(at: coord, on: map)
                let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                map.setRegion(MKCoordinateRegion(center: coord, span: span), animated: false)
            }
            logConeState(on: map, record: record)
            publishLayoutSoon(on: map)
            return
        }

        if let coord = recCoord {
            if let pin {
                if !equalCoord(pin.coordinate, coord) { pin.coordinate = coord }
            } else {
                installPin(at: coord, on: map)
            }
        } else {
            clearPin(on: map)
        }
        publishLayoutSoon(on: map)
    }

    // The synchronous call gets stale values on first load (bounds = .zero
    // before AppKit lays the view out, and setRegion's effect lags by a
    // runloop). The async re-fire lands after the layout pass has run.
    private func publishLayoutSoon(on map: MKMapView) {
        publishLayout(on: map)
        DispatchQueue.main.async { [weak self, weak map] in
            guard let self, let map else { return }
            self.publishLayout(on: map)
        }
    }

    @objc func mapFrameChanged(_ note: Notification) {
        guard let map = note.object as? MKMapView else { return }
        publishLayout(on: map)
    }

    // Click anywhere on a pinless map to drop a pin at the click point.
    // Gated to pin == nil so the gesture doesn't interfere with the normal
    // drag-existing-pin flow once a coordinate is set; to move an existing
    // pin the user drags it.
    @objc func handleClickToPlace(_ recognizer: NSClickGestureRecognizer) {
        guard pin == nil else { return }
        guard let map = recognizer.view as? MKMapView else { return }
        let point = recognizer.location(in: map)
        let coord = map.convert(point, toCoordinateFrom: map)
        onDrag(coord.latitude, coord.longitude)
    }

    func applyRecenterIfNeeded(token: Int, on map: MKMapView, record: ImageRecord?) {
        defer { lastRecenterToken = token }
        guard token != lastRecenterToken else { return }
        guard let record, let lat = record.latitude, let lon = record.longitude else { return }
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let region = MKCoordinateRegion(center: coord, span: map.region.span)
        map.setRegion(region, animated: true)
    }

    private func installPin(at coord: CLLocationCoordinate2D, on map: MKMapView) {
        let p = LocationPin()
        p.coordinate = coord
        map.addAnnotation(p)
        pin = p
    }

    private func clearPin(on map: MKMapView) {
        if let pin { map.removeAnnotation(pin); self.pin = nil }
    }

    // Compute pin's screen point + cone radius in pixels at the current
    // zoom. Cone radius is 22% of the visible span (matches old wedge
    // sizing) so the cone visually shrinks/grows with zoom.
    private func publishLayout(on map: MKMapView) {
        guard let p = pin, let dir = currentDirection else {
            onLayout(nil)
            return
        }
        let degSpan = max(map.region.span.latitudeDelta, map.region.span.longitudeDelta)
        let metersSpan = degSpan * 111_000.0
        let radiusMeters = max(metersSpan * 0.22, 5.0)
        let edgeCoord = destination(from: p.coordinate,
                                    bearingDegrees: dir,
                                    distanceMeters: radiusMeters)
        let pinPoint = map.convert(p.coordinate, toPointTo: map)
        let edgePoint = map.convert(edgeCoord, toPointTo: map)
        let dx = edgePoint.x - pinPoint.x
        let dy = edgePoint.y - pinPoint.y
        let radius = sqrt(dx * dx + dy * dy)
        onLayout(ConeLayout(center: pinPoint, radius: radius))
    }

    private func logConeState(on map: MKMapView, record: ImageRecord?) {
        let lat = record?.latitude.map { String(format: "%.5f", $0) } ?? "nil"
        let lon = record?.longitude.map { String(format: "%.5f", $0) } ?? "nil"
        let dir = record?.direction.map { String(format: "%.2f deg", $0) } ?? "nil"
        log("[cone] lat=\(lat) lon=\(lon) direction=\(dir)")
    }

    private func coord(from record: ImageRecord?) -> CLLocationCoordinate2D? {
        guard let record, let lat = record.latitude, let lon = record.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func equalCoord(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is LocationPin else { return nil }
        let id = "LocationPin"
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
            ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
        view.annotation = annotation
        view.image = Coordinator.pinImage
        view.centerOffset = .zero
        view.isDraggable = true
        view.canShowCallout = false
        return view
    }

    func mapView(_ mapView: MKMapView,
                 annotationView view: MKAnnotationView,
                 didChange newState: MKAnnotationView.DragState,
                 fromOldState oldState: MKAnnotationView.DragState) {
        guard let pin = view.annotation as? LocationPin else { return }
        switch newState {
        case .ending:
            onDrag(pin.coordinate.latitude, pin.coordinate.longitude)
            publishLayout(on: mapView)
            view.dragState = .none
        case .canceling:
            view.dragState = .none
        default:
            break
        }
    }

    // Pin moves around the map's screen rect as the user pans/zooms; the
    // SwiftUI Canvas overlay needs the latest screen-space layout on
    // every region change, including the live updates during a pan.
    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        publishLayout(on: mapView)
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        publishLayout(on: mapView)
    }

    // MARK: - Pin image

    static let pinImage: NSImage = {
        let size = NSSize(width: 22, height: 22)
        let img = NSImage(size: size)
        img.lockFocus()
        let accent = NSColor(Theme.accent)

        accent.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 22, height: 22)).fill()

        accent.setFill()
        let core = NSBezierPath(ovalIn: NSRect(x: 6, y: 6, width: 10, height: 10))
        core.fill()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        core.lineWidth = 1.5
        core.stroke()

        img.unlockFocus()
        return img
    }()
}

// MARK: - Geometry

// Spherical-Earth forward formula. R = 6371km is good to ~0.5% at any
// latitude -- far better than we need for a visual cone.
private func destination(from origin: CLLocationCoordinate2D,
                         bearingDegrees: Double,
                         distanceMeters: Double) -> CLLocationCoordinate2D {
    let R = 6_371_000.0
    let phi1 = origin.latitude * .pi / 180.0
    let lam1 = origin.longitude * .pi / 180.0
    let theta = bearingDegrees * .pi / 180.0
    let delta = distanceMeters / R

    let phi2 = asin(sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta))
    let lam2 = lam1 + atan2(sin(theta) * sin(delta) * cos(phi1),
                            cos(delta) - sin(phi1) * sin(phi2))
    return CLLocationCoordinate2D(latitude: phi2 * 180.0 / .pi,
                                  longitude: lam2 * 180.0 / .pi)
}
