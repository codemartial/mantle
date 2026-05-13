import Foundation

enum TZRule: Equatable, Hashable, Sendable {
    case unknown                                    // no TZ info available
    case auto                                       // resolved from GPS each render
    case fixed(offsetMinutes: Int, label: String)
}
