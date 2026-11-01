import Foundation
import SwiftData

// Version 1 of the on-device store (ADR 0003, plan section 3.2).
//
// CloudKit-compatible rules (ADR 0003, ADR 0015), checked by `CloudKitRulesTests`:
// - no `@Attribute(.unique)` and no `#Unique`;
// - every stored property is optional or has a default value (one per line, so the test can
//   check it);
// - every relationship is optional;
// - ids are strings (lowercased UUIDs or seed ids), never `persistentModelID`.
// Enums are stored as raw `String`s and tag/day sets as sorted `[String]`. Every top-level
// record has a `sequence` (insertion order, which the repositories preserve like the in-memory
// ones) and the sync metadata `createdAt` / `updatedAt` / `deletedAt` (ADR 0003). Where the
// domain has those timestamps they are mapped; otherwise the optional columns are reserved for
// sync and left nil in v1. Repositories hard-delete in v1 (so "Delete all data" really deletes);
// `deletedAt` is reserved for sync tombstones, except `MemberRecord.deletedAt`, which stores the
// domain soft delete `Member.deletedAt`.
//
// Never change a stored property here once shipped: add `SchemaV2` and a migration stage in
// `OMPMigrationPlan` instead.

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            HouseholdRecord.self,
            MemberRecord.self,
            RuleRecord.self,
            MealPlanRecord.self,
            PantryItemRecord.self,
            ShoppingItemRecord.self,
            CookLogRecord.self,
            FactRecord.self,
            LearningEventRecord.self,
            PromptStateRecord.self,
            ProcessedImportRecord.self,
            CounterRecord.self,
        ]
    }

    /// The single household (the repository keeps at most one).
    @Model
    final class HouseholdRecord {
        var id: String = ""
        var snacksEnabled: Bool = false
        var weekStartsOn: String = "monday"
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        var deletedAt: Date? = nil
        @Relationship(deleteRule: .cascade, inverse: \MemberRecord.household)
        var members: [MemberRecord]? = []
        @Relationship(deleteRule: .cascade, inverse: \RuleRecord.household)
        var rules: [RuleRecord]? = []

        init(id: String) {
            self.id = id
        }
    }

    /// A household member. `sortIndex` keeps the domain order (relationships are unordered).
    @Model
    final class MemberRecord {
        var id: String = ""
        var sortIndex: Int = 0
        var labelRole: String = "adult"
        var labelNumber: Int = 1
        var name: String? = nil
        var ageBand: String? = nil
        /// Defaults to `unasked`, the state that blocks planning (fail closed).
        var safetyStatus: String = "unasked"
        var safetyConfirmedAt: Date? = nil
        var needsSchoolLunch: Bool = false
        var schoolDays: [String] = []
        var portionOverride: Double? = nil
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        /// The domain soft delete (`Member.deletedAt`).
        var deletedAt: Date? = nil
        var household: HouseholdRecord? = nil

        init(id: String) {
            self.id = id
        }
    }

    /// A hard rule. `scopeKind` defaults to `household`, which covers every eater (fail closed).
    @Model
    final class RuleRecord {
        var id: String = ""
        var sortIndex: Int = 0
        var kind: String = "hard"
        var scopeKind: String = "household"
        var scopeMemberId: String? = nil
        var restriction: String = ""
        var excludedTags: [String] = []
        var source: String = "user"
        var createdAt: Date = Date.distantPast
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil
        var household: HouseholdRecord? = nil

        init(id: String) {
            self.id = id
        }
    }

    /// One plan revision. The content (meals) is a `PlanContentDTO` JSON blob; the columns
    /// that are queried (series, revision, status, approval) are first-class.
    @Model
    final class MealPlanRecord {
        var id: String = ""
        var sequence: Int = 0
        var seriesId: String = ""
        var revision: Int = 1
        var basedOn: String? = nil
        /// ISO 8601 calendar date (`LocalDate.isoString`); sorts as text.
        var weekStart: String = ""
        var status: String = "draft"
        var approvalApprover: String? = nil
        var approvalApprovedAt: Date? = nil
        var approvalContentHash: String? = nil
        var contentVersion: String = ""
        /// `PlanContentDTO` JSON (its own `version` field is inside the blob).
        var content: Data = Data()
        var createdAt: Date = Date.distantPast
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(id: String) {
            self.id = id
        }
    }

    /// A pantry item: exactly one of `ingredientId` / `freeText` is set.
    @Model
    final class PantryItemRecord {
        var id: String = ""
        var sequence: Int = 0
        var ingredientId: String? = nil
        var freeText: String? = nil
        var quantity: Double = 0
        var unit: String = "piece"
        var location: String = "shelf"
        var purchasedAt: Date? = nil
        var expiresOn: String? = nil
        var lastConfirmedAt: Date = Date.distantPast
        var source: String = "manual"
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(id: String) {
            self.id = id
        }
    }

    @Model
    final class ShoppingItemRecord {
        var id: String = ""
        var sequence: Int = 0
        var key: String = ""
        var ingredientId: String? = nil
        var name: String = ""
        var quantity: Double? = nil
        var unit: String? = nil
        var aisle: String = "other"
        var checkedOff: Bool = false
        var origin: String = "manual"
        var group: String = "toBuy"
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(id: String) {
            self.id = id
        }
    }

    /// A cooked meal. `deductions` is a `PantryDeductionsDTO` JSON blob.
    @Model
    final class CookLogRecord {
        var id: String = ""
        var sequence: Int = 0
        var planId: String = ""
        var mealId: String = ""
        var recipeId: String = ""
        var cookedAt: Date = Date.distantPast
        var deductions: Data = Data()
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(id: String) {
            self.id = id
        }
    }

    /// A soft fact. Subject and statement are flattened into queryable columns.
    @Model
    final class FactRecord {
        var id: String = ""
        var sequence: Int = 0
        var subjectKind: String = "household"
        var subjectMemberId: String? = nil
        var statementKind: String = ""
        var statementRef: String? = nil
        var origin: String = "inferred"
        var confidence: Double = 0
        var status: String = "observing"
        var suppressed: Bool = false
        var forgottenAt: Date? = nil
        var createdAt: Date = Date.distantPast
        var updatedAt: Date = Date.distantPast
        var deletedAt: Date? = nil

        init(id: String) {
            self.id = id
        }
    }

    /// A learning signal. The event kind's payload is flattened into optional columns.
    @Model
    final class LearningEventRecord {
        var id: String = ""
        var sequence: Int = 0
        var at: Date = Date.distantPast
        var kind: String = ""
        var recipeId: String? = nil
        var fromRecipeId: String? = nil
        var toRecipeId: String? = nil
        var slot: String? = nil
        var rerollReason: String? = nil
        var ingredientId: String? = nil
        var factSubjectKind: String? = nil
        var factSubjectMemberId: String? = nil
        var factStatementKind: String? = nil
        var factStatementRef: String? = nil
        var answer: String? = nil
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(id: String) {
            self.id = id
        }
    }

    @Model
    final class PromptStateRecord {
        var promptId: String = ""
        var sequence: Int = 0
        var lastShownAt: Date? = nil
        var dismissedAt: Date? = nil
        var answeredAt: Date? = nil
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(promptId: String) {
            self.promptId = promptId
        }
    }

    /// A share-extension inbox file that was already imported (ADR 0011; used from T26).
    @Model
    final class ProcessedImportRecord {
        var id: String = ""
        var processedAt: Date = Date.distantPast
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(id: String) {
            self.id = id
        }
    }

    /// A named counter (for example weekly prompt counts); cleared by "Delete all data".
    @Model
    final class CounterRecord {
        var name: String = ""
        var count: Int = 0
        var createdAt: Date? = nil
        var updatedAt: Date? = nil
        var deletedAt: Date? = nil

        init(name: String) {
            self.name = name
        }
    }
}

typealias HouseholdRecord = SchemaV1.HouseholdRecord
typealias MemberRecord = SchemaV1.MemberRecord
typealias RuleRecord = SchemaV1.RuleRecord
typealias MealPlanRecord = SchemaV1.MealPlanRecord
typealias PantryItemRecord = SchemaV1.PantryItemRecord
typealias ShoppingItemRecord = SchemaV1.ShoppingItemRecord
typealias CookLogRecord = SchemaV1.CookLogRecord
typealias FactRecord = SchemaV1.FactRecord
typealias LearningEventRecord = SchemaV1.LearningEventRecord
typealias PromptStateRecord = SchemaV1.PromptStateRecord
typealias ProcessedImportRecord = SchemaV1.ProcessedImportRecord
typealias CounterRecord = SchemaV1.CounterRecord

/// The store's migration plan. V1 only; each later schema adds a stage (ADR 0003).
public enum OMPMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}
