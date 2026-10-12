import OMPUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Principal class of the share extension (Info.plist `NSExtensionPrincipalClass`).
///
/// Walking skeleton (task T02): says "Hello" when the shared items contain text and shows
/// an "unsupported" message otherwise. Task T26 replaces the content with parse -> review
/// -> destination -> confirm -> inbox write (ADR 0011).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let inputItems = extensionContext?.inputItems ?? []
        let content = ShareSkeletonView(
            containsText: Self.containsText(inputItems),
            onDone: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        )

        let host = UIHostingController(rootView: content)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    /// True when any attachment of any shared item is plain text (or a subtype of it).
    /// Only checks the declared types; the text itself is not loaded until task T26.
    static func containsText(_ inputItems: [Any]) -> Bool {
        inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .contains { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
    }
}

/// The extension's only screen in the walking skeleton.
struct ShareSkeletonView: View {
    let containsText: Bool
    let onDone: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if containsText {
                    PlaceholderMessage(
                        title: "Hello",
                        message: "OffMyPlate will turn this text into a shopping or pantry list.",
                        titleIdentifier: "share.hello"
                    )
                } else {
                    PlaceholderMessage(
                        title: "Text only",
                        message: "OffMyPlate can only import shared text, such as a list from Notes.",
                        titleIdentifier: "share.unsupported"
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
    }
}
