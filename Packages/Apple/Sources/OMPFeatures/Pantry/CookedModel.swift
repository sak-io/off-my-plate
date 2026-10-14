import Foundation
import Observation
import OMPDomain
import OMPServices

/// One ingredient on the cooked sheet.
public struct CookedLine: Identifiable, Hashable, Sendable {
    public let ingredientId: IngredientID
    public let name: String
    public let unit: MeasureUnit
    /// What the pantry holds in `unit`, or nil when the ingredient is not in the pantry.
    public let have: Double?
    /// What will be taken out; starts at the recipe's amount and can be edited.
    public var amount: Double
    public var isEditing = false

    public var id: String { ingredientId.rawValue }

    /// Whether the pantry runs out (never below zero: the service stops at 0).
    public var willBeZero: Bool {
        guard let have else { return false }
        return have - amount <= have * Quantity.relativeEpsilon
    }
}

/// The cooked sheet (S-15; AC-9.6): proposes what the meal takes out of the pantry, lets the user
/// edit each amount, and updates the pantry through the service. The service refuses a plan that
/// is not approved, so this works on approved plans only (AC-5.3).
@MainActor
@Observable
public final class CookedModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case ready
        /// The proposal could not be made; the text is shown instead of the lines.
        case failed(String)
    }

    private let backend: (any PantryBackend)?
    private let planID: MealPlanID
    private let mealID: PlannedMealID

    public private(set) var phase: Phase = .loading
    public private(set) var mealTitle = ""
    public private(set) var lines: [CookedLine] = []
    public private(set) var isSaving = false
    /// C-095 text after a failed save, or nil.
    public private(set) var errorMessage: String?
    /// Set when the pantry was updated; the sheet then closes.
    public private(set) var didFinish = false

    public init(backend: (any PantryBackend)?, plan: MealPlanID, meal: PlannedMealID) {
        self.backend = backend
        self.planID = plan
        self.mealID = meal
    }

    public var canUpdate: Bool { phase == .ready && !isSaving }

    public func load() async {
        guard let backend else {
            phase = .failed(PantryCopy.saveFailed)
            return
        }
        do {
            let proposal = try await backend.cookProposal(plan: planID, meal: mealID)
            mealTitle = proposal.mealTitle
            lines = proposal.lines.map { line in
                CookedLine(
                    ingredientId: line.ingredientId, name: line.name, unit: line.proposed.unit,
                    have: line.have?.amount, amount: line.proposed.amount)
            }
            phase = .ready
        } catch {
            record(error)
            phase = .failed(Self.message(for: error))
        }
    }

    static func message(for error: any Error) -> String {
        if let service = error as? ServiceError, case .markCooked(let reason) = service {
            switch reason {
            case .planNotApproved: return PantryCopy.notApproved
            case .alreadyCooked: return PantryCopy.alreadyCooked
            case .mealNotFound, .blockedBySafety, .emptyMeal, .recipeMismatch: return PantryCopy.saveFailed
            }
        }
        return PantryCopy.saveFailed
    }

    // MARK: Editing

    private func index(of id: String) -> Int? { lines.firstIndex { $0.id == id } }

    public func toggleEditing(_ id: String) {
        guard let index = index(of: id), lines[index].have != nil else { return }
        lines[index].isEditing.toggle()
    }

    public func increase(_ id: String) {
        guard let index = index(of: id) else { return }
        lines[index].amount = min(lines[index].amount + PantryFormat.step(for: lines[index].unit), 1_000_000_000)
    }

    public func decrease(_ id: String) {
        guard let index = index(of: id) else { return }
        let next = lines[index].amount - PantryFormat.step(for: lines[index].unit)
        lines[index].amount = max(0, next)
    }

    /// A typed amount; ignored unless it is a valid number.
    public func setAmount(_ id: String, text: String) {
        guard let index = index(of: id), let value = PantryFormat.parseAmount(text) else { return }
        lines[index].amount = value
    }

    // MARK: Update

    /// "Update pantry": takes the (edited) amounts out of the pantry.
    public func update() async {
        guard canUpdate, let backend else { return }
        isSaving = true
        defer { isSaving = false }
        let amounts = lines.map {
            CookAmount(ingredientId: $0.ingredientId, quantity: Quantity($0.amount, $0.unit))
        }
        do {
            try await backend.markCooked(plan: planID, meal: mealID, amounts: amounts)
            errorMessage = nil
            didFinish = true
        } catch {
            record(error)
            errorMessage = Self.message(for: error)
        }
    }

    private func record(_ error: any Error) {
        let kind = OMPLog.errorKind(error)
        OMPLog.app.error("Mark cooked failed: \(kind, privacy: .public)")
    }
}
