// seed-review-sheet: prints the markdown sign-off sheet for the bundled seed library
// (ADR 0010, G1). Exits 1 and lists every issue when the seed content is invalid.
//
// Usage: swift run --package-path Packages/Core seed-review-sheet [OUTPUT.md]
//   With OUTPUT.md the sheet is written there; otherwise it goes to standard output.
import Foundation
import OMPRecipes

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("seed-review-sheet: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
if arguments.count > 1 || arguments.first == "-h" || arguments.first == "--help" {
    fail("usage: seed-review-sheet [OUTPUT.md]")
}

let files: SeedFiles
do {
    files = try SeedLoader.bundledFiles()
} catch {
    fail("\(error)")
}

let result = SeedValidator.validate(files)
guard let library = result.library else {
    fail("the seed content is invalid:\n" + result.issues.map { "  - \($0)" }.joined(separator: "\n"))
}

let sheet = SeedReviewSheet.markdown(for: library)
if let path = arguments.first {
    do {
        try Data(sheet.utf8).write(to: URL(fileURLWithPath: path))
    } catch {
        fail("could not write \(path): \(error)")
    }
} else {
    print(sheet, terminator: "")
}
