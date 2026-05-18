import Foundation
import Observation
import os.log

private let log = Logger(subsystem: "dev.metadater", category: "save")

// Per-id save serialiser with trailing-edge dedup. A save request for an
// id that already has one in flight sets a `pending` bit instead of
// queueing another ExifTool spawn; when the in-flight save completes,
// the coordinator re-checks dirty[id] and fires exactly one follow-up
// save if anything is still dirty (catching any edits made during the
// flight). All save requests come from image-session boundaries -- never
// from field-blur within the same image.

@MainActor
final class SaveCoordinator {
    weak var state: AppState?

    private var inFlight: Set<String> = []
    private var pending: Set<String> = []

    private var savedRevertTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
    }

    // Public entry: a navigate-away / folder-change / quit happened for
    // this id. Fire a save if it has dirty fields; otherwise no-op.
    func requestSave(id: String) {
        guard let state else { return }
        let fields = state.edits.dirtyFields(id)
        guard !fields.isEmpty else { return }

        if inFlight.contains(id) {
            pending.insert(id)
            return
        }
        startSave(id: id)
    }

    // Wait for the given id's save chain to fully drain.
    func flush(id: String) async {
        while inFlight.contains(id) || pending.contains(id) {
            await Task.yield()
        }
    }

    // Trigger saves for every dirty id, then wait for all chains to drain.
    func flushAll() async {
        guard let state else { return }
        for id in state.edits.allDirtyIDs {
            requestSave(id: id)
        }
        while !inFlight.isEmpty || !pending.isEmpty {
            await Task.yield()
        }
    }

    // Called by AppState after every store mutation. Surfaces dirty count
    // as .unsaved on the status pill -- but only if we're not currently
    // in .saving / .saved / .failed (those have priority).
    func dirtyChanged() {
        guard let state else { return }
        switch state.status {
        case .idle, .unsaved:
            let n = state.edits.totalDirtyCount
            state.status = n == 0 ? .idle : .unsaved(count: n)
        default:
            break
        }
    }

    // MARK: - Private

    private func startSave(id: String) {
        guard let state, let record = state.edits.record(id) else { return }
        let fields = state.edits.dirtyFields(id)
        guard !fields.isEmpty else { return }

        inFlight.insert(id)
        savedRevertTask?.cancel()
        state.status = .saving

        let snapshot = record  // ImageRecord is a value type; this is a copy
        let snapFields = fields

        Task { [weak self] in
            let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let url = try ExifToolWriter.write(record: snapshot, fields: snapFields)
                    return .success(url)
                } catch {
                    return .failure(error)
                }
            }.value
            await self?.handleCompletion(id: id, result: result, snapshot: snapshot, fields: snapFields)
        }
    }

    private func handleCompletion(id: String,
                                  result: Result<URL, Error>,
                                  snapshot: ImageRecord,
                                  fields: Set<EditableField>) {
        guard let state else { return }
        inFlight.remove(id)

        switch result {
        case .success(let url):
            state.edits.markSaved(id, fields: fields, snapshot: snapshot)
            state.adoptSidecar(id: id, url: url)
            state.status = .saved
            scheduleSavedRevert()
            log.debug("save ok: \(id, privacy: .public)")
        case .failure(let err):
            state.status = .failed(errorMessage(err))
            log.error("save failed: \(id, privacy: .public) -- \(err.localizedDescription, privacy: .public)")
        }

        // Trailing-edge: if a follow-up was requested during the flight
        // AND dirty[id] is still non-empty after markSaved, fire one
        // more save with a fresh snapshot. If dirty is empty, the
        // pending requests were redundant -- drop them.
        if pending.remove(id) != nil {
            let stillDirty = state.edits.dirtyFields(id)
            if !stillDirty.isEmpty {
                startSave(id: id)
                return
            }
        }

        // No follow-up. If we're showing .saved, the revert task will
        // transition to .idle / .unsaved after 1.2s. If .failed, sticky.
        // Otherwise recompute dirty count -> idle / unsaved.
        if case .saved = state.status { return }
        if case .failed = state.status { return }
        dirtyChanged()
    }

    private func scheduleSavedRevert() {
        savedRevertTask?.cancel()
        savedRevertTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self else { return }
            guard let state = self.state else { return }
            if case .saved = state.status {
                let n = state.edits.totalDirtyCount
                state.status = n == 0 ? .idle : .unsaved(count: n)
            }
        }
    }

    private func errorMessage(_ err: Error) -> String {
        if let werr = err as? ExifToolWriter.WriteError {
            switch werr {
            case .exiftoolNotFound: return "ExifTool not found"
            case .processFailed(_, let stderr):
                let firstLine = stderr.split(separator: "\n").first.map(String.init) ?? "unknown"
                return String(firstLine.prefix(120))
            }
        }
        return err.localizedDescription
    }
}
