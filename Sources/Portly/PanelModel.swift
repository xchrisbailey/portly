import Foundation
import Observation
import PortlyCore

@MainActor
@Observable
final class PanelModel {
    private(set) var rows: [Row] = []
    private(set) var errorMessage: String?

    private let portly = Portly(processSource: SystemProcessSource())

    /// Runs a fresh Scan off the main thread. Called every time the panel opens.
    func refresh() async {
        let portly = portly
        do {
            rows = try await Task.detached { try portly.scan() }.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
