// SPDX-FileCopyrightText: 2026 Tahir Hashmi
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
//
// This file is part of Mantle, licensed under the PolyForm Noncommercial
// License 1.0.0 -- free for any noncommercial purpose, including
// modification. See the LICENSE file for the full text, or
// <https://polyformproject.org/licenses/noncommercial/1.0.0>.

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
    @State private var layout: ConeLayout?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapRepresentable(
                record: state.selectedRecord,
                mapStyle: state.mapStyle,
                recenterToken: state.mapRecenterTick,
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
            state.recenterMap()
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

        // Click-to-place: a single click on open map drops or relocates the
        // pin at the click point. Placement is deferred past the system
        // double-click interval and cancelled if a second click arrives, so
        // a double-click only zooms (it never drops a pin). NSClickGesture-
        // Recognizer auto-fails on movement, so pan still works. Clicks that
        // land on the pin go to it for dragging, and the delegate filters out
        // clicks on MKMapView's own subviews (zoom +/-, compass) -- both via
        // the gesture delegate's hit-test below.
        // Just the 1-click recognizer -- deliberately NO 2-click recognizer.
        // A custom double-click recognizer wins gesture arbitration over
        // MKMapView's own internal double-click recognizer, which kills the
        // map's built-in zoom. The 1-click recognizer, by contrast, coexists
        // with zoom (the map still got its double-click before). We suppress
        // placement on a double-click instead by reading the event's
        // clickCount in the gesture delegate (the reliable Apple signal),
        // cancelling the deferred single-click placement when a second click
        // lands. NSClickGestureRecognizer auto-fails on movement so click-drag
        // panning still works; the delegate's hit-test keeps the zoom +/- and
        // compass clicks away from us.
        let clickRecognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClickToPlace(_:))
        )
        clickRecognizer.numberOfClicksRequired = 1
        clickRecognizer.delegate = context.coordinator
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

private final class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {

    var onDrag: (Double, Double) -> Void
    var onLayout: (ConeLayout?) -> Void
    var log: (String) -> Void

    private var lastRecordID: String?
    private var pin: LocationPin?
    private var currentDirection: Double?
    private var lastRecenterToken: Int = 0
    // A single-click placement waiting out the double-click window. Cancelled
    // if a second click lands (double-click -> zoom, no placement).
    private var pendingPlace: DispatchWorkItem?

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

    // Don't intercept clicks that land on a map subview (zoom +/- controls,
    // compass). Hit-test from the window's contentView so the traversal
    // descends through MKMapView's full subview tree; only recognize when
    // the deepest hit is the map view itself.
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        // A second click within the double-click window cancels the pending
        // single-click placement, so a double-click only zooms. This runs on
        // the real NSEvent (clickCount is authoritative here), independent of
        // whether the recognizer's action re-fires on the second click.
        if event.clickCount > 1 {
            pendingPlace?.cancel()
            pendingPlace = nil
        }
        guard let map = gestureRecognizer.view,
              let contentView = event.window?.contentView else { return true }
        let hit = contentView.hitTest(event.locationInWindow)
        return hit === map
    }

    // Single click on open map drops or relocates the pin at the click
    // point -- no longer gated to a pinless map, so an existing pin jumps to
    // wherever you click instead of having to be dragged. Placement is
    // deferred by the system double-click interval; if a second click lands
    // first the gesture delegate cancels it, so a double-click only zooms.
    // Clicks on the pin itself reach it for dragging (the gesture delegate's
    // hit-test fails this recognizer there), so this only fires on open map.
    @objc func handleClickToPlace(_ recognizer: NSClickGestureRecognizer) {
        guard let map = recognizer.view as? MKMapView else { return }

        // Reset any in-flight placement window on a fresh click.
        pendingPlace?.cancel()

        // Belt-and-suspenders with the delegate's clickCount check: skip the
        // second click of a multi-click so a double-click never places.
        if let clicks = NSApp.currentEvent?.clickCount, clicks > 1 {
            pendingPlace = nil
            return
        }

        let point = recognizer.location(in: map)
        let coord = map.convert(point, toCoordinateFrom: map)
        let work = DispatchWorkItem { [weak self, weak map] in
            guard let self, let map else { return }
            self.pendingPlace = nil
            // Move the pin directly rather than waiting for the data round-
            // trip: ImageRecord's Equatable ignores lat/lon, so a coords-only
            // change can fail to re-drive sync and the annotation would stay
            // put. Updating the annotation here makes placement reliable and
            // instant; onDrag then persists the new coordinate.
            if let pin = self.pin {
                pin.coordinate = coord
            } else {
                self.installPin(at: coord, on: map)
            }
            self.publishLayout(on: map)
            self.onDrag(coord.latitude, coord.longitude)
        }
        pendingPlace = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
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
