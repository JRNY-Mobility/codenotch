import Foundation

/// The project gate's synthetic provider entry.
///
/// Not a real usage source — it exists so the gate can ride the same
/// `ProviderSnapshot` pipeline as the providers, drawing one ring in the fleet
/// in provider order. The snapshot itself is assembled in `UsageStore` so it
/// can read the live gate state.
enum ProjectGateProvider {
    static let id = "project-gate"
}
