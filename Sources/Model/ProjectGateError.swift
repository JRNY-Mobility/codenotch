import Foundation

/// Why a gate command could not be carried out.
enum ProjectGateError: Error, Equatable {
    /// The WIP cap is reached; complete or defer a project first.
    case capReached
    /// No project matches the id or title given.
    case notFound
    /// The defer date was not a usable future date.
    case invalidDate
    /// The project title was blank after trimming.
    case invalidTitle
}
