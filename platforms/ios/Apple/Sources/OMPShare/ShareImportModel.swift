import Foundation
import Observation
import OMPDomain

/// The state of the Notes import review (S-40, flow F10, AC-11.1 to 11.5).
///
/// It parses text with `ShoppingTextParser`, lets the user edit, remove and keep rows, and writes
/// one `InboxImport` file through `ShareInboxWriting`. It knows nothing about the household, the
/// plan, safety or the store: an import only ever becomes list or pantry rows plus staple events
/// in the app (AC-11.5).
@MainActor
@Observable
public final class ShareImportModel {
    public enum Phase: Sendable, Hashable {
        /// Reading and parsing the text.
        case parsing
        /// The shared content is not text (C-171).
        case notText
        /// The note has no list (C-170).
        case empty
        /// The review screen.
        case review
        /// Writing the inbox file.
        case saving
        /// Written (C-172); the view closes after a moment.
        case saved
    }

    /// One editable review row.
    public struct Row: Identifiable, Sendable, Hashable {
        /// The 0-based line number in the note.
        public let id: Int
        public var name: String
        /// As typed; empty means no quantity.
        public var quantityText: String
        public var unit: MeasureUnit?
        /// Selected rows are added. Ticked and odd lines start unselected (plan R7).
        public var isIncluded: Bool
        /// Odd lines are listed under "Not sure about these" (C-169b).
        public let isUnsure: Bool
    }

    public private(set) var phase: Phase = .parsing
    public var destination: InboxImport.Destination = .shoppingList
    public var rows: [Row] = []
    /// True after a failed write: the view shows C-173 and stays open (F10).
    public private(set) var saveFailed = false

    private let writer: any ShareInboxWriting
    private let now: @Sendable () -> Date
    /// One id per model: a retry after a failed write overwrites the same file, never adds a second.
    private let importId: InboxImportID

    public init(
        writer: any ShareInboxWriting, now: @escaping @Sendable () -> Date = { Date() },
        importId: InboxImportID = .generate()
    ) {
        self.writer = writer
        self.now = now
        self.importId = importId
    }

    // MARK: Loading

    /// The shared content has no text.
    public func showNotText() {
        phase = .notText
    }

    /// Parses `text` and shows the review (or the empty state).
    public func load(text: String) {
        let parsed = ShoppingTextParser.parse(text)
        rows = parsed.lines.map { line in
            Row(
                id: line.lineIndex, name: line.name, quantityText: Self.format(line.qty),
                unit: line.qty == nil ? nil : line.unit, isIncluded: line.isSelectedByDefault,
                isUnsure: line.confidence == .unsure)
        }
        phase = rows.isEmpty ? .empty : .review
    }

    // MARK: Editing

    public func remove(_ id: Int) {
        rows.removeAll { $0.id == id }
        if rows.isEmpty { phase = .empty }
    }

    public func toggle(_ id: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isIncluded.toggle()
    }

    // MARK: Confirming

    /// The rows that would be written: selected, with a name.
    public var selectedItems: [InboxImport.Item] {
        rows.compactMap { row in
            guard row.isIncluded else { return nil }
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let quantity = Self.parseQuantity(row.quantityText)
            return InboxImport.Item(name: name, quantity: quantity, unit: quantity == nil ? nil : row.unit)
        }
    }

    /// "Add {n}" (C-169).
    public var addCount: Int { selectedItems.count }

    public var canAdd: Bool { phase == .review && addCount > 0 }

    /// Writes the import. On failure the review stays open with `saveFailed` set.
    public func confirm() async {
        guard canAdd else { return }
        saveFailed = false
        phase = .saving
        do {
            let item = try InboxImport(
                importId: importId, createdAt: now(), destination: destination, items: selectedItems)
            try await writer.write(item)
            phase = .saved
        } catch {
            saveFailed = true
            phase = .review
        }
    }

    // MARK: Quantity text

    /// "2", "1.5", "0.33"; nil for no quantity. Rounded to two decimals for display.
    static func format(_ quantity: Double?) -> String {
        guard let quantity, quantity.isFinite, quantity > 0 else { return "" }
        let rounded = (quantity * 100).rounded() / 100
        if rounded == rounded.rounded(), rounded < 1_000_000 { return String(Int(rounded)) }
        return String(rounded)
    }

    /// A positive, finite number typed with "." or ","; nil otherwise.
    static func parseQuantity(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value > 0 else { return nil }
        return value
    }
}
