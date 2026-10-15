import Foundation
import OMPDomain
import Testing

@testable import OMPShare

private actor RecordingWriter: ShareInboxWriting {
    struct Failure: Error {}
    private(set) var written: [InboxImport] = []
    private var failuresLeft: Int

    init(failures: Int = 0) {
        failuresLeft = failures
    }

    func write(_ item: InboxImport) async throws {
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw Failure()
        }
        written.append(item)
    }
}

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func makeModel(writer: RecordingWriter = RecordingWriter(), id: String = "import-1") -> ShareImportModel {
    ShareImportModel(writer: writer, now: { fixedDate }, importId: InboxImportID(id))
}

@Suite("Share import review model")
@MainActor
struct ShareImportModelTests {
    private let note = """
        Groceries
        2 kg rice
        milk x2
        - [x] bread
        call mom re sunday
        curry leaves
        """

    @Test("starts parsing; non-text input gives the not-text state")
    func notText() {
        let model = makeModel()
        #expect(model.phase == .parsing)
        model.showNotText()
        #expect(model.phase == .notText)
        #expect(!model.canAdd)
    }

    @Test("a note with no list gives the empty state")
    func emptyNote() {
        let model = makeModel()
        model.load(text: "  \n \n")
        #expect(model.phase == .empty)
        #expect(model.rows.isEmpty)
    }

    @Test("items start selected; ticked and odd lines start unselected and odd lines are grouped as unsure")
    func parsedRows() {
        let model = makeModel()
        model.load(text: note)
        #expect(model.phase == .review)
        let byName = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.name, $0) })
        #expect(byName["rice"]?.isIncluded == true)
        #expect(byName["rice"]?.quantityText == "2")
        #expect(byName["rice"]?.unit == .kilogram)
        #expect(byName["curry leaves"]?.isIncluded == true)
        #expect(byName["bread"]?.isIncluded == false)
        let unsure = model.rows.filter(\.isUnsure)
        #expect(!unsure.isEmpty)
        #expect(unsure.allSatisfy { !$0.isIncluded })
        #expect(model.addCount == model.rows.filter { $0.isIncluded && !$0.name.isEmpty }.count)
    }

    @Test("removing and keeping rows changes what is added; removing the last row shows empty")
    func editing() {
        let model = makeModel()
        model.load(text: "rice\nmilk")
        #expect(model.addCount == 2)
        model.remove(model.rows[0].id)
        #expect(model.addCount == 1)
        model.toggle(model.rows[0].id)
        #expect(model.addCount == 0)
        #expect(!model.canAdd)
        model.remove(model.rows[0].id)
        #expect(model.phase == .empty)
    }

    @Test("confirm writes one inbox import with the edited rows and the chosen destination")
    func confirmWrites() async throws {
        let writer = RecordingWriter()
        let model = makeModel(writer: writer)
        model.load(text: "2 kg rice\nmilk\nsalt")
        model.destination = .pantry
        model.rows[1].name = "  Oat milk  "
        model.rows[1].quantityText = "1,5"
        model.rows[1].unit = .litre
        model.rows[2].quantityText = "not a number"
        model.rows[2].unit = .gram
        model.toggle(model.rows[0].id)

        await model.confirm()

        #expect(model.phase == .saved)
        let written = await writer.written
        try #require(written.count == 1)
        let item = written[0]
        #expect(item.importId == InboxImportID("import-1"))
        #expect(item.destination == .pantry)
        #expect(item.createdAt == fixedDate)
        #expect(
            item.items == [
                InboxImport.Item(name: "Oat milk", quantity: 1.5, unit: .litre),
                InboxImport.Item(name: "salt"),
            ])
        // The file contents round-trip through the Core format.
        #expect(try InboxImport.decode(item.encoded()) == item)
    }

    @Test("rows with an empty name are not written")
    func emptyNamesSkipped() async {
        let writer = RecordingWriter()
        let model = makeModel(writer: writer)
        model.load(text: "rice\nmilk")
        model.rows[0].name = "   "
        #expect(model.addCount == 1)
        await model.confirm()
        #expect(await writer.written.first?.items.map(\.name) == ["milk"])
    }

    @Test("a failed write keeps the review open with the error, and a retry reuses the same import id")
    func failureThenRetry() async {
        let writer = RecordingWriter(failures: 1)
        let model = makeModel(writer: writer)
        model.load(text: "rice")
        await model.confirm()
        #expect(model.phase == .review)
        #expect(model.saveFailed)
        #expect(await writer.written.isEmpty)

        await model.confirm()
        #expect(model.phase == .saved)
        #expect(!model.saveFailed)
        #expect(await writer.written.map(\.importId) == [InboxImportID("import-1")])
    }

    @Test("confirm does nothing before the review, with nothing selected, or after saving")
    func confirmGuards() async {
        let writer = RecordingWriter()
        let model = makeModel(writer: writer)
        await model.confirm()
        model.load(text: "rice")
        model.toggle(model.rows[0].id)
        await model.confirm()
        model.toggle(model.rows[0].id)
        await model.confirm()
        await model.confirm()
        #expect(await writer.written.count == 1)
    }

    @Test("quantity text: formatting and parsing")
    func quantityText() {
        #expect(ShareImportModel.format(nil) == "")
        #expect(ShareImportModel.format(2) == "2")
        #expect(ShareImportModel.format(1.5) == "1.5")
        #expect(ShareImportModel.format(1.0 / 3.0) == "0.33")
        #expect(ShareImportModel.parseQuantity("2") == 2)
        #expect(ShareImportModel.parseQuantity("0,5") == 0.5)
        #expect(ShareImportModel.parseQuantity("") == nil)
        #expect(ShareImportModel.parseQuantity("-1") == nil)
        #expect(ShareImportModel.parseQuantity("0") == nil)
        #expect(ShareImportModel.parseQuantity("nan") == nil)
        #expect(ShareImportModel.parseQuantity("two") == nil)
    }
}
