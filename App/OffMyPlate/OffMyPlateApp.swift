import OMPFeatures
import SwiftUI

/// The app entry point. All wiring lives in `CompositionRoot` (ADR 0004).
@main
struct OffMyPlateApp: App {
    @State private var model: AppModel

    init() {
        _model = State(initialValue: CompositionRoot.makeAppModel(arguments: ProcessInfo.processInfo.arguments))
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(model: model)
        }
    }
}
