import Foundation

// In-flight edits for batch mode. Lives on AppState while batchOrder is
// non-empty. Reset to defaults on every batch entry -- blank fields here
// mean "do not modify the corresponding field on any image". Synthesis
// (AppState.synthesizeBatch) is the only consumer.
//
// The master's own date / timezone / location are NOT drafted here -- they
// are edited directly on the master's ImageRecord through the same path as
// single-mode editing. Only fields that need broadcasting across the whole
// batch live here.
struct BatchDraft {

    enum CaptionMode: Hashable { case replace, append }

    var headline: String = ""
    var captionMode: CaptionMode = .replace
    var captionReplace: String = ""
    var captionAppend: String = ""
    var dateShiftHours: Int = 0
    var dateShiftMinutes: Int = 0

    var hasDateShift: Bool { dateShiftHours != 0 || dateShiftMinutes != 0 }

    var dateShiftInterval: TimeInterval {
        TimeInterval(dateShiftHours * 3600 + dateShiftMinutes * 60)
    }
}
