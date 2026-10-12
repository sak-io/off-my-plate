import OMPData
import OMPFeatures
import SwiftUI

/// Composition root (ADR 0004). Walking skeleton: shows the placeholder root view.
/// Task T21 wires the repositories, services and the root safety-gate cover here.
@main
struct OffMyPlateApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
