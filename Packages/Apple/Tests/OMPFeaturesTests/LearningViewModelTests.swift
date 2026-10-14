import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

@Suite("Learning screens (S-35, S-36, reflect-back card; AC-12.2 to AC-12.5)")
@MainActor
struct LearningViewModelTests {
    private let adult = member(.adult, 1, .confirmedNone)

    private func announced(_ env: SettingsEnv, _ log: Announcements) -> ReflectBackModel {
        ReflectBackModel(app: env.app, announce: { log.messages.append($0) })
    }

    // MARK: S-35

    @Test("Facts are grouped by origin: You told me, You confirmed, I noticed, Starting guesses")
    func sections() async {
        let env = await SettingsEnv.make(
            members: [adult],
            facts: [
                softFact(.cuisineAffinity("westIndian"), .appDefault),
                softFact(.prefersQuickWeekday, .inferred, status: .proposed, confidence: 0.8),
                softFact(.cuisineAffinity("northIndian"), .confirmed),
                softFact(.cuisineAffinity("southIndian"), .stated),
                softFact(.dislikesRecipe("old"), .stated, status: .forgotten),
            ])
        await env.learning.load()
        #expect(env.learning.phase == .loaded)
        #expect(env.learning.sections.map(\.section) == [.told, .confirmed, .noticed, .guesses])
        #expect(env.learning.sections.map(\.section.title) == [
            SettingsCopy.sectionTold, SettingsCopy.sectionConfirmed, SettingsCopy.sectionNoticed,
            SettingsCopy.sectionGuesses,
        ])
        // A forgotten fact is not listed (AC-12.5).
        #expect(env.learning.sections.flatMap(\.facts).count == 4)
    }

    @Test("Facts read as plain sentences with their origin")
    func sentences() async throws {
        let env = await SettingsEnv.make(
            members: [adult], facts: [softFact(.cuisineAffinity("southIndian"), .stated)])
        await env.learning.load()
        let fact = try #require(env.learning.facts.first)
        #expect(env.learning.sentence(fact) == "You cook South Indian food")
        #expect(env.learning.text.origin(of: fact) == SettingsCopy.originSaid)
        #expect(env.learning.text.sentence(.prefersQuickWeekday) == SettingsCopy.quickWeekday)
        let origins = [
            (softFact(.prefersQuickWeekday, .confirmed), SettingsCopy.originConfirmed),
            (softFact(.cuisineAffinity("northIndian"), .appDefault), SettingsCopy.originDefault),
            (softFact(.dislikesIngredient("okra"), .inferred), SettingsCopy.originSwaps),
            (softFact(.favouriteRecipe("dal"), .inferred), SettingsCopy.originCooked),
            (softFact(.staple("rice"), .inferred), SettingsCopy.originLists),
        ]
        for (fact, expected) in origins {
            #expect(env.learning.text.origin(of: fact) == expected)
        }
    }

    @Test("Noticed facts read Likely or Maybe; others show no confidence word (C-150b)")
    func confidenceWords() async {
        let env = await SettingsEnv.make(members: [adult])
        let strong = softFact(.prefersQuickWeekday, .inferred, status: .proposed, confidence: 0.9)
        let weak = softFact(.dislikesIngredient("okra"), .inferred, status: .proposed, confidence: 0.2)
        let said = softFact(.cuisineAffinity("southIndian"), .stated)
        #expect(env.learning.confidenceWord(strong) == SettingsCopy.likely)
        #expect(env.learning.confidenceWord(weak) == SettingsCopy.maybe)
        #expect(env.learning.confidenceWord(said) == nil)
        #expect(env.learning.canQuickConfirm(strong))
        #expect(!env.learning.canQuickConfirm(said))
    }

    @Test("Nothing learned yet is an empty list (C-152)")
    func empty() async {
        let env = await SettingsEnv.make(members: [adult])
        await env.learning.load()
        #expect(env.learning.phase == .loaded)
        #expect(env.learning.isEmpty)
    }

    @Test("Without services the list reports a load failure (C-095 path)")
    func loadFailure() async {
        let app = AppModel(repositories: .inMemory(), clock: FixedClock(now: fixtureNow, timeZone: utc))
        let learning = LearningViewModel(app: app)
        await learning.load()
        #expect(learning.phase == .failed)
    }

    @Test("Forget removes the fact from the list and stops it feeding scores (AC-12.5)")
    func forget() async throws {
        let fact = softFact(.cuisineAffinity("southIndian"), .stated)
        let env = await SettingsEnv.make(members: [adult], facts: [fact])
        await env.learning.load()
        env.learning.requestForget(fact)
        #expect(env.learning.pendingForget == fact)

        await env.learning.forget(fact)

        #expect(env.learning.isEmpty)
        let stored = try #require(try await env.repositories.facts.fetch(id: fact.id))
        #expect(stored.status == .forgotten)
        #expect(stored.forgottenAt == fixtureNow)
    }

    @Test("That's right confirms a noticed fact as a soft, active fact")
    func thatsRight() async throws {
        let fact = softFact(.prefersQuickWeekday, .inferred, status: .proposed, confidence: 0.8)
        let env = await SettingsEnv.make(members: [adult], facts: [fact])
        await env.learning.load()
        await env.learning.thatsRight(fact)
        let stored = try #require(try await env.repositories.facts.fetch(id: fact.id))
        #expect(stored.origin == .confirmed)
        #expect(stored.status == .active)
        #expect(stored.statement == .prefersQuickWeekday)
    }

    // MARK: S-36

    @Test("Editing a fact keeps it soft: who it applies to changes, it becomes stated")
    func editStaysSoft() async throws {
        let fact = softFact(.prefersQuickWeekday, .inferred, status: .proposed, confidence: 0.8)
        let env = await SettingsEnv.make(members: [adult], facts: [fact])
        await env.learning.load()
        let options = env.learning.subjects
        #expect(options.map(\.title) == [SettingsCopy.everyone, adult.displayName])

        await env.learning.save(fact, subject: .member(adult.id), statement: fact.statement)

        let all = try await env.repositories.facts.fetchAll()
        let edited = try #require(all.first { $0.subject == .member(adult.id) })
        #expect(edited.origin == .stated)
        #expect(edited.status == .active)
        #expect(edited.statement == .prefersQuickWeekday)
        // The old household-level key stays as a forgotten tombstone.
        #expect(all.first { $0.id == fact.id }?.status == .forgotten)
        // No hard rule appeared anywhere (AC-12.4).
        #expect(try await env.repositories.household.fetch()?.rules.isEmpty == true)
    }

    @Test("Recipe facts can be switched between Prefer and Avoid when possible; others have no strength")
    func strength() async throws {
        let avoid = softFact(.dislikesRecipe("dal"), .inferred, status: .proposed, confidence: 0.8)
        let pair = try #require(LearningViewModel.strengthOptions(for: avoid.statement))
        #expect(pair.prefer == .favouriteRecipe("dal"))
        #expect(pair.avoid == .dislikesRecipe("dal"))
        #expect(LearningViewModel.strengthOptions(for: .prefersQuickWeekday) == nil)
        #expect(LearningViewModel.strengthOptions(for: .cuisineAffinity("southIndian")) == nil)

        let env = await SettingsEnv.make(members: [adult], facts: [avoid])
        await env.learning.load()
        await env.learning.save(avoid, subject: .household, statement: pair.prefer)
        let all = try await env.repositories.facts.fetchAll()
        let liked = try #require(all.first { $0.statement == .favouriteRecipe("dal") })
        #expect(liked.origin == .stated)
        #expect(liked.status == .active)
    }

    // MARK: Reflect-back card

    @Test("Three weekday re-rolls in two weeks propose one card with the question (C-100)")
    func cardAppears() async throws {
        let env = await SettingsEnv.make(members: [adult], events: quickWeekdayEvents())
        let card = announced(env, Announcements())
        await card.load()
        #expect(card.fact?.statement == .prefersQuickWeekday)
        #expect(card.question == SettingsCopy.reflectQuestion(SettingsCopy.quickWeekday))
    }

    @Test("Yes confirms the soft fact and says so (C-101)")
    func answerYes() async throws {
        let env = await SettingsEnv.make(members: [adult], events: quickWeekdayEvents())
        let log = Announcements()
        let card = announced(env, log)
        await card.load()
        await card.answer(.yes)
        #expect(card.fact == nil)
        #expect(log.messages == [SettingsCopy.afterAnswer(.yes)])
        let learned = try await env.backend.learned()
        let confirmed = try #require(learned.first)
        #expect(confirmed.origin == .confirmed)
        #expect(confirmed.status == .active)
    }

    @Test("Not really dismisses it without planning around it (C-102)")
    func answerNotReally() async throws {
        let env = await SettingsEnv.make(members: [adult], events: quickWeekdayEvents())
        let log = Announcements()
        let card = announced(env, log)
        await card.load()
        await card.answer(.notReally)
        #expect(card.fact == nil)
        #expect(log.messages == [SettingsCopy.afterAnswer(.notReally)])
        #expect(try await env.backend.learned().isEmpty)
    }

    @Test("Don't ask again suppresses the fact for good (C-103)")
    func answerDontAsk() async throws {
        let env = await SettingsEnv.make(members: [adult], events: quickWeekdayEvents())
        let log = Announcements()
        let card = announced(env, log)
        await card.load()
        await card.answer(.dontAskAgain)
        #expect(log.messages == [SettingsCopy.afterAnswer(.dontAskAgain)])
        let stored = try await env.repositories.facts.fetchAll()
        #expect(stored.first?.suppressed == true)
        #expect(try await env.backend.learned().isEmpty)
        // Not offered again, now or on a later load.
        await card.load()
        #expect(card.fact == nil)
    }

    @Test("Only one card per week: after an answer the next load shows none")
    func oneCardAtATime() async {
        let env = await SettingsEnv.make(members: [adult], events: quickWeekdayEvents())
        let card = announced(env, Announcements())
        await card.load()
        await card.answer(.yes)
        await card.load()
        #expect(card.fact == nil)
    }

    @Test("A safety question waiting hides the card (safety cards win)")
    func safetyWins() async {
        let child = member(.child, 1, .unasked)
        let env = await SettingsEnv.make(members: [adult, child], events: quickWeekdayEvents())
        #expect(env.app.gateStatus.blocksPlanning)
        let card = announced(env, Announcements())
        await card.load()
        #expect(card.fact == nil)
        #expect(card.question == nil)
    }

    @Test("Learning never changes hard rules or safety answers (AC-12.4)")
    func learningIsSoftOnly() async throws {
        let rule = testRule("peanuts", for: .member(adult.id))
        let env = await SettingsEnv.make(members: [adult], rules: [rule], events: quickWeekdayEvents())
        let before = try #require(try await env.repositories.household.fetch())
        let card = announced(env, Announcements())
        await card.load()
        await card.answer(.yes)
        await env.learning.load()
        for fact in env.learning.facts { await env.learning.forget(fact) }
        let after = try #require(try await env.repositories.household.fetch())
        #expect(after.rules == before.rules)
        #expect(after.members == before.members)
    }
}
