# ADR 0001: Native Swift/SwiftUI universal app, iOS/iPadOS 18

- **Status:** Accepted (given by owner: tech §3, §1.6; spec G2)
- **Date:** 2026-10-12

## Context
OffMyPlate is an iPhone-first app that also has to work on iPad. The owner's technical spec chooses native Swift and SwiftUI, with UIKit only where SwiftUI can't do the job. Spec G2 sets the minimum OS to iOS/iPadOS 18 with no dependency on Apple Intelligence.

## Decision
One universal app target in Swift 6 and SwiftUI with adaptive layouts, deployment target iOS/iPadOS 18.0. Swift Concurrency (async/await, actors) throughout. No Apple Intelligence or Foundation Models APIs in v1.

## Alternatives considered
1. Cross-platform (React Native/Flutter). Rejected by the owner (tech §3). It would also put the safety-critical core in a second language, away from the Swift share extension.
2. Minimum iOS 17. Rejected: iOS 18 gives the SwiftData fixes we need (`#Index`, `deleteAllData`, better `#Predicate`) and the owner accepted G2.

## Consequences
- The app, the extension and the UI tests need Xcode on macOS. The pure core is kept buildable on Linux (ADR 0005).
- Any test that touches `UIKit`, `SwiftUI`, `SwiftData` or `Speech` runs only on the owner's Mac or the macOS CI runner.
