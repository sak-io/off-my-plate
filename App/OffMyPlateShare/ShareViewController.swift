import OMPDomain
import OMPShare
import OMPUI
import SwiftUI
import UIKit

/// Principal class of the share extension (Info.plist `NSExtensionPrincipalClass`).
///
/// Task T26 (S-40, flow F10, ADR 0011): reads the shared text, parses it, shows the review screen
/// and writes one inbox file into the App Group. It links only OMPDomain, OMPUI and OMPShare:
/// never the services, the store, the household or the plan.
final class ShareViewController: UIViewController {
    private var model: ShareImportModel?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = ShareImportModel(writer: Self.makeWriter())
        self.model = model
        let content = ShareImportView(
            model: model,
            onClose: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            })

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

        let providers = Self.providers(of: extensionContext?.inputItems ?? [])
        Task { @MainActor in
            if ShareTextDetection.containsText(typeIdentifiers: ShareTextLoader.typeIdentifiers(of: providers)),
                let text = await ShareTextLoader.text(from: providers)
            {
                model.load(text: text)
            } else {
                model.showNotText()
            }
        }
    }

    /// Every attachment of every shared item.
    static func providers(of inputItems: [Any]) -> [NSItemProvider] {
        inputItems.compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] }
    }

    /// The inbox writer for the App Group named in Info.plist (`OMPAppGroupIdentifier`). Without
    /// the group (an unsigned build) the write fails and the review shows C-173.
    private static func makeWriter() -> any ShareInboxWriting {
        let groupID = Bundle.main.object(forInfoDictionaryKey: "OMPAppGroupIdentifier") as? String ?? ""
        guard let root = ShareInbox.rootURL(appGroupID: groupID) else { return UnavailableInboxWriter() }
        return DirectoryShareInboxWriter(root: root)
    }
}

/// Used when the App Group container cannot be found: every write fails (C-173).
private struct UnavailableInboxWriter: ShareInboxWriting {
    struct Unavailable: Error {}
    func write(_ item: InboxImport) async throws { throw Unavailable() }
}
