import Foundation
import OMPDomain
import Testing

/// The resolver fixture plus everyday pantry items used in the spoken golden transcripts.
enum SpokenFixture {
    static let ingredients: [Ingredient] = ResolverFixture.ingredients + [
        ResolverFixture.ingredient("milk", "Milk", ["doodh", "dudh", "paal"]),
        ResolverFixture.ingredient("sugar", "Sugar", ["cheeni", "chini"]),
        ResolverFixture.ingredient("salt", "Salt", ["namak", "uppu"]),
        ResolverFixture.ingredient("potato", "Potato", ["aloo", "urulakizhangu"]),
        ResolverFixture.ingredient("toor-dal", "Toor dal", ["arhar dal", "tuvar dal", "thuvara parippu"]),
        ResolverFixture.ingredient("atta", "Atta", ["whole wheat flour", "gehun ka atta"]),
        ResolverFixture.ingredient("curd", "Curd", ["dahi", "yogurt", "thairu"]),
        ResolverFixture.ingredient("banana", "Banana", ["kela", "pazham"]),
        ResolverFixture.ingredient("bread", "Bread", ["pav"]),
        ResolverFixture.ingredient("ghee", "Ghee", ["neyyi"]),
        ResolverFixture.ingredient("paneer", "Paneer", ["cottage cheese"]),
        ResolverFixture.ingredient("garlic", "Garlic", ["lahsun", "veluthulli"]),
        ResolverFixture.ingredient("ginger", "Ginger", ["adrak", "inji"]),
        ResolverFixture.ingredient("apple", "Apple", ["seb"]),
    ]
    static let parser = SpokenCommandParser(resolver: IngredientResolver(ingredients: SpokenFixture.ingredients))

    static func amountText(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(value)
    }

    /// One line per item ("add rice 2 kg", "out egg", "add green-chilli?" when not confident),
    /// "approve" for `.openApprovalSheet`, then "? text" per unparsed piece.
    static func describe(_ result: SpokenCommandParseResult) -> [String] {
        var lines: [String] = []
        for command in result.commands {
            let verb: String
            let items: [SpokenPantryItem]
            switch command {
            case .add(let found):
                verb = "add"
                items = found
            case .markOut(let found):
                verb = "out"
                items = found
            case .remove(let found):
                verb = "remove"
                items = found
            case .openApprovalSheet:
                lines.append("approve")
                continue
            }
            for item in items {
                var line = "\(verb) \(item.match.ingredientId.rawValue)"
                if !item.isConfident { line += "?" }
                if let qty = item.qty { line += " " + amountText(qty) }
                if let unit = item.unit { line += " " + unit.rawValue }
                lines.append(line)
            }
        }
        return lines + result.unparsed.map { "? " + $0 }
    }
}

/// Golden transcripts (ADR 0012, AC-9.4, G9). Grow this table with real phrasings from testers.
let spokenGoldenTranscripts: [(String, [String])] = [
        ("I bought 2 kg rice and a dozen eggs", ["add rice 2 kg", "add egg 12"]),
        ("I bought 2 kg rice and a dozen eggs.", ["add rice 2 kg", "add egg 12"]),
        ("add 1 litre milk", ["add milk 1 l"]),
        ("Add two onions", ["add onion 2"]),
        ("I got half a kilo of tomatoes", ["add tomato 0.5 kg"]),
        ("bought one and a half kg sugar", ["add sugar 1.5 kg"]),
        ("I picked up 500 grams paneer", ["add paneer 500 g"]),
        ("I bought 500g paneer", ["add paneer 500 g"]),
        ("added a couple of coconuts", ["add coconut 2"]),
        ("we're out of milk", ["out milk"]),
        ("We are out of milk and eggs", ["out milk", "out egg"]),
        ("used up the curd", ["out curd"]),
        ("we ran out of salt", ["out salt"]),
        ("we've run out of atta", ["out atta"]),
        ("finished the bread", ["out bread"]),
        ("remove garlic", ["remove garlic"]),
        ("delete the bananas", ["remove banana"]),
        ("approve", ["approve"]),
        ("approve the plan", ["approve"]),
        ("Approve it.", ["approve"]),
        ("looks good", ["approve"]),
        ("That looks good to me!", ["approve"]),
        ("I bought twenty five eggs", ["add egg 25"]),
        ("I bought twelve bananas", ["add banana 12"]),
        ("add fifteen potatoes", ["add potato 15"]),
        ("I bought two hundred grams ginger", ["add ginger 200 g"]),
        ("I bought two hundred and fifty grams of garlic", ["add garlic 250 g"]),
        ("add a dozen bananas and half a dozen apples", ["add banana 12", "add apple 6"]),
        ("I bought 2 dozen eggs", ["add egg 24"]),
        ("I bought 1.5 kg chawal", ["add rice 1.5 kg"]),
        ("I bought 2 kg rice, 1 kg sugar and 500 g toor dal", ["add rice 2 kg", "add sugar 1 kg", "add toor-dal 500 g"]),
        ("add kappa", ["add tapioca"]),
        ("I bought 1 kilo mathi", ["add sardine 1 kg"]),
        ("I bought rice and we're out of milk", ["add rice", "out milk"]),
        ("I bought 2 kg rice. We're out of eggs. Approve the plan.", ["add rice 2 kg", "out egg", "approve"]),
        ("add a packet of salt", ["add salt 1 piece"]),
        ("I bought three litres of milk", ["add milk 3 l"]),
        ("add some ghee", ["add ghee"]),
        ("I bought an apple", ["add apple 1"]),
        ("bought a kilo of onions", ["add onion 1 kg"]),
        ("I bought 2 kg rice and some of that stuff", ["add rice 2 kg", "? some of that stuff"]),
        ("hello there", ["? hello there"]),
        ("um okay so I bought milk", ["add milk"]),
        ("add 2 kg", ["? add 2 kg"]),
        ("I bought quinoa", ["? I bought quinoa"]),
        ("add chilli", ["add green-chilli?"]),
        ("I bought 2 kg rice and approve", ["add rice 2 kg", "approve"]),
        ("approve the plan and add milk", ["approve", "add milk"]),
        ("please add 3 kg potatoes", ["add potato 3 kg"]),
        ("I bought 1 1/2 kg rice", ["add rice 1.5 kg"]),
        ("I bought ½ kg ginger", ["add ginger 0.5 kg"]),
        ("I bought a pinch of salt", ["add salt"]),
        ("add mutta", ["add egg"]),
        ("add 3 kg potatoes to the pantry", ["add potato 3 kg"]),
        ("I bought one kg rice plus two kg atta", ["add rice 1 kg", "add atta 2 kg"]),
        ("We are all out of eggs", ["out egg"]),
        ("I'm out of sugar", ["out sugar"]),
        ("no more bread", ["out bread"]),
        ("I bought 2 kilos onions, 1 kg tomatoes and a bunch of curry leaves", ["add onion 2 kg", "add tomato 1 kg", "add curry-leaves 1 piece"]),
        ("I've got 2.5 kg atta", ["add atta 2.5 kg"]),
        ("I bought a quarter kg ginger", ["add ginger 0.25 kg"]),
        ("I bought a hundred grams of ginger", ["add ginger 100 g"]),
        ("I bought ninety nine eggs", ["add egg 99"]),
        ("I bought rice and kiwi", ["add rice", "? kiwi"]),
        ("I bought milk, then we're out of sugar; remove salt", ["add milk", "out sugar", "remove salt"]),
        ("WE'RE OUT OF MILK", ["out milk"]),
        ("We’re out of milk", ["out milk"]),
        ("Approve. Approve the plan. Looks good.", ["approve"]),
        ("I bought 2 kg rice\nI bought 1 kg sugar", ["add rice 2 kg", "add sugar 1 kg"]),
        ("I bought two and a half kilos of potatoes", ["add potato 2.5 kg"]),
        ("I bought 2 kg", ["? I bought 2 kg"]),
        ("", []),
        ("um", []),
]

@Suite("SpokenCommandParser")
struct SpokenCommandParserTests {
    let parser = SpokenFixture.parser

    @Test("golden transcripts parse to the expected commands", arguments: spokenGoldenTranscripts)
    func golden(_ transcript: String, _ expected: [String]) {
        #expect(SpokenFixture.describe(parser.parse(transcript)) == expected)
    }

    @Test("the table has at least 40 transcripts")
    func tableSize() {
        #expect(spokenGoldenTranscripts.count >= 40)
    }

    @Test("AC-9.4: 'I bought 2 kg rice and a dozen eggs' gives rice 2 kg and eggs 12")
    func acceptanceExample() {
        let result = parser.parse("I bought 2 kg rice and a dozen eggs")
        guard case .add(let items)? = result.commands.first, result.commands.count == 1, items.count == 2 else {
            Issue.record("expected one add command with two items, got \(result.commands)")
            return
        }
        #expect(items[0].match.ingredientId == "rice")
        #expect(items[0].quantity == Quantity(2, .kilogram))
        #expect(items[0].isConfident)
        #expect(items[0].spokenText == "2 kg rice")
        #expect(items[1].match.ingredientId == "egg")
        #expect(items[1].qty == 12)
        #expect(items[1].unit == nil)
        #expect(items[1].quantity == Quantity(12, .piece))
        #expect(items[1].name == "eggs")
        #expect(result.unparsed.isEmpty)
        #expect(!result.wasTruncated)
    }

    @Test("what is not understood comes back as the unparsed remainder, in order, as heard")
    func unparsedRemainder() {
        let result = parser.parse("Hmm, the thing. I bought 2 kg rice and some of that stuff. Call Amma")
        #expect(result.pantryItems.map(\.match.ingredientId) == ["rice"])
        #expect(result.unparsed == ["Hmm the thing", "some of that stuff", "Call Amma"])
        #expect(result.unparsedText == "Hmm the thing some of that stuff Call Amma")
    }

    @Test("a command with no understood item returns the whole command as remainder")
    func wholeCommandUnparsed() {
        let result = parser.parse("We're out of quinoa")
        #expect(result.commands.isEmpty)
        #expect(result.unparsed == ["We're out of quinoa"])
    }

    @Test("filler words alone are not reported as unparsed")
    func fillersIgnored() {
        #expect(parser.parse("um, okay so").unparsed.isEmpty)
        #expect(parser.parse("   ").commands.isEmpty)
    }

    @Test(
        "AC-5.6: approve phrasings only open the approval sheet",
        arguments: [
            "approve", "Approve.", "approve it", "approve the plan", "Approve this week", "please approve the plan",
            "ok approve", "looks good", "Looks good to me", "that looks good", "the plan looks good", "approved",
            "Approve the plan. Approve it!", "go ahead and approve",
        ])
    func approveOpensSheetOnly(_ transcript: String) {
        let result = parser.parse(transcript)
        #expect(result.commands == [.openApprovalSheet])
        #expect(result.pantryItems.isEmpty)
    }

    @Test("AC-5.6: no transcript yields anything but pantry commands and at most one sheet request")
    func noApproveTransition() {
        // `SpokenCommand` has no approve case; this exhaustive switch fails to compile if one is added.
        func isAllowed(_ command: SpokenCommand) -> Bool {
            switch command {
            case .add, .markOut, .remove, .openApprovalSheet: return true
            }
        }
        for (transcript, _) in spokenGoldenTranscripts {
            let commands = parser.parse(transcript).commands
            #expect(commands.allSatisfy(isAllowed))
            #expect(commands.filter { $0 == .openApprovalSheet }.count <= 1, "\(transcript)")
        }
    }

    @Test("an item whose name matches no ingredient is not guessed")
    func unknownItem() {
        let result = parser.parse("I bought rice and kiwi")
        #expect(result.pantryItems.map(\.match.ingredientId) == ["rice"])
        #expect(result.unparsed == ["kiwi"])
    }

    @Test("a loose match is kept but marked not confident")
    func looseMatch() {
        let item = parser.parse("add chilli").pantryItems.first
        #expect(item?.match.ingredientId == "green-chilli")
        #expect(item?.isConfident == false)
    }

    @Test("number words: one to nineteen, tens, compounds, hundreds")
    func numberWords() {
        let cases: [(String, Double)] = [
            ("one", 1), ("seven", 7), ("thirteen", 13), ("nineteen", 19), ("twenty", 20), ("forty two", 42),
            ("ninety nine", 99), ("a hundred", 100), ("hundred", 100), ("three hundred", 300),
            ("two hundred and fifty", 250), ("a couple", 2), ("a couple of", 2), ("half a dozen", 6), ("a dozen", 12),
            ("one and a half", 1.5), ("two and half", 2.5), ("a quarter", 0.25), ("1 1/2", 1.5), ("½", 0.5),
            ("2.5", 2.5),
        ]
        for (words, value) in cases {
            let item = parser.parse("add \(words) eggs").pantryItems.first
            #expect(item?.qty == value, "\(words)")
            #expect(item?.match.ingredientId == "egg", "\(words)")
        }
    }

    @Test("a non-quantified unit keeps the item but drops the amount")
    func pinch() {
        let item = parser.parse("add a pinch of salt").pantryItems.first
        #expect(item?.match.ingredientId == "salt")
        #expect(item?.qty == nil)
        #expect(item?.unit == nil)
    }

    @Test("a transcript over the cap is cut and reported")
    func truncation() {
        let long = String(repeating: "add rice. ", count: 400)
        let result = parser.parse(long)
        #expect(result.wasTruncated)
        #expect(result.commands.count <= SpokenCommandParser.maxTranscriptLength / 10 + 1)
        #expect(!parser.parse("add rice").wasTruncated)
    }

    @Test("parsing is deterministic")
    func deterministic() {
        for (transcript, _) in spokenGoldenTranscripts {
            #expect(parser.parse(transcript) == parser.parse(transcript))
        }
    }

    @Test("a space followed by a combining mark does not break the grammar (macOS fuzz regression)")
    func orphanMarks() {
        #expect(SpokenFixture.describe(parser.parse("I bought \u{0301}2 kg rice")) == ["add rice 2 kg"])
        #expect(SpokenFixture.describe(parser.parse("add \u{0D57}rice and \u{0D3E}milk")) == ["add rice", "add milk"])
        #expect(parser.parse("approve \u{0301}").commands == [.openApprovalSheet])
        #expect(parser.parse("pinch \u{0949}muttahalf").commands.isEmpty)
    }
}
