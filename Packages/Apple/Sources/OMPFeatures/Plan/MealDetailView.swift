import OMPDomain
import OMPUI
import SwiftUI

/// S-11: one meal. Who is eating, the recipe, Swap, Lock and (approved plans only) Mark cooked.
///
/// A draft shows C-066 instead of Mark cooked. With a pending revision it shows both the
/// approved and the proposed meal, and Mark cooked acts on the approved one.
/// Portion steppers (AC-6.1, AC-6.3) are not part of T23: portions are shown read-only because
/// the services expose no servings edit yet.
struct MealDetailView: View {
    let viewModel: PlanViewModel
    let mealID: PlannedMealID

    var body: some View {
        Group {
            if let meal = viewModel.meal(mealID) {
                detail(meal)
            } else {
                Color.clear
            }
        }
        .accessibilityIdentifier(AccessibilityID.mealDetail)
    }

    @ViewBuilder
    private func detail(_ meal: PlannedMeal) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                header(meal)
                if viewModel.lunchboxCardVisible {
                    lunchboxCard
                }
                if let change = viewModel.change(for: meal) {
                    changeBlock(change)
                }
                portions(meal)
                recipeBlock(meal)
                actions(meal)
                DisclaimerFooter(.plan)
            }
            .frame(maxWidth: OMPMetrics.readableMaxWidth, alignment: .leading)
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(PlanCopy.slotName(meal.slot))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(meal.locked ? PlanCopy.unlock : PlanCopy.lock) {
                    Task { await viewModel.toggleLock(meal) }
                }
                .disabled(viewModel.isBusy)
                .accessibilityValue(meal.locked ? PlanCopy.lockedValue : "")
                .accessibilityIdentifier(AccessibilityID.mealLock)
            }
        }
        .task(id: mealID) { await viewModel.mealOpened(meal) }
    }

    private func header(_ meal: PlannedMeal) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Text(PlanCopy.diffHeader(day: viewModel.dayTitle(meal.date), meal: PlanCopy.slotName(meal.slot)))
                .font(OMPFont.reason)
                .foregroundStyle(Color.primary.opacity(0.75))
            Text(meal.isEmpty ? PlanCopy.emptySlot : viewModel.title(of: meal))
                .font(OMPFont.sectionTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let line = detailLine(meal) {
                Text(line)
                    .font(OMPFont.reason)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if viewModel.isMealBlocked(meal) {
                StatusLabel(PlanCopy.mealNeedsReplacing, systemImage: OMPSymbol.warning)
                    .font(OMPFont.reason)
                    .accessibilityIdentifier(AccessibilityID.mealBlocked)
            }
            if meal.locked {
                StatusLabel(PlanCopy.locked, systemImage: OMPSymbol.locked)
                    .font(OMPFont.reason)
            }
        }
    }

    /// "45 min · Uses your rajma"
    private func detailLine(_ meal: PlannedMeal) -> String? {
        var parts: [String] = []
        if let recipe = viewModel.recipe(of: meal) {
            parts.append(PlanCopy.minutes(recipe.prepMinutes + recipe.cookMinutes))
        }
        if let reason = viewModel.reasonLine(of: meal) { parts.append(reason) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var lunchboxCard: some View {
        InlineCard(title: PlanCopy.lunchboxPrompt) {
            Button(PlanCopy.yes) { Task { await viewModel.answerLunchbox(.yes) } }
                .buttonStyle(.bordered)
                .tint(Color.primary)                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.lunchboxYes)
            Button(PlanCopy.no) { Task { await viewModel.answerLunchbox(.no) } }
                .buttonStyle(.bordered)
                .tint(Color.primary)                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.lunchboxNo)
            Button(PlanCopy.notNow) { Task { await viewModel.answerLunchbox(.notNow) } }
                .buttonStyle(.bordered)
                .tint(Color.primary)                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.lunchboxNotNow)
        }
        .accessibilityIdentifier(AccessibilityID.lunchboxCard)
    }

    private func changeBlock(_ change: PlanDiff.Change) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            StatusLabel(PlanCopy.changed, systemImage: OMPSymbol.draft)
                .font(OMPFont.reason.bold())
            if let was = change.was {
                Text(PlanCopy.approvedMeal(viewModel.title(ofRecipe: was.recipeId))).font(OMPFont.body)
            }
            if let now = change.now {
                Text(PlanCopy.proposedMeal(viewModel.title(ofRecipe: now.recipeId))).font(OMPFont.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OMPSpacing.medium)
        .ompCardBackground()
        .accessibilityElement(children: .combine)
    }

    private func portions(_ meal: PlannedMeal) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Text(PlanCopy.whosEating)
                .font(OMPFont.mealName)
                .accessibilityAddTraits(.isHeader)
            ForEach(meal.servings, id: \.memberId) { serving in
                AdaptiveStack {
                    Text(viewModel.memberName(serving.memberId)).font(OMPFont.body)
                    Text(serving.notEating ? PlanCopy.notEating : PlanCopy.portions(Self.portionText(serving.portion)))
                        .font(OMPFont.body)
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// 1, 0.6, 0.4: one decimal at most.
    static func portionText(_ portion: Double) -> String {
        portion.formatted(.number.precision(.fractionLength(0...1)))
    }

    @ViewBuilder
    private func recipeBlock(_ meal: PlannedMeal) -> some View {
        if let recipe = viewModel.recipe(of: meal) {
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                Text(PlanCopy.ingredientsHeader)
                    .font(OMPFont.mealName)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.ingredientNames(of: recipe).joined(separator: ", "))
                    .font(OMPFont.body)
                    .fixedSize(horizontal: false, vertical: true)
                if !recipe.steps.isEmpty {
                    Text(PlanCopy.stepsHeader)
                        .font(OMPFont.mealName)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(OMPFont.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actions(_ meal: PlannedMeal) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            AdaptiveStack {
                Button(PlanCopy.swap) { Task { await viewModel.openSwap(meal.id) } }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)                    .ompMinimumHitTarget()
                    .disabled(viewModel.isBlocked || viewModel.isBusy)
                    .accessibilityIdentifier(AccessibilityID.mealSwap)
                cookedControl(meal)
            }
            if viewModel.isBlocked {
                Text(PlanCopy.blockedHint(viewModel.blockingName))
                    .font(OMPFont.disclaimer)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if viewModel.isFirstDraft {
                Text(PlanCopy.draftCaption)
                    .font(OMPFont.disclaimer)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.mealDraftCaption)
            }
        }
    }

    @ViewBuilder
    private func cookedControl(_ meal: PlannedMeal) -> some View {
        if viewModel.isCooked(meal) {
            StatusLabel(PlanCopy.cooked, systemImage: OMPSymbol.cooked)
        } else if let target = viewModel.cookableMeal(for: meal) {
            Button(PlanCopy.markCooked) { viewModel.requestMarkCooked(meal) }
                .buttonStyle(.bordered)
                .tint(Color.primary)                .ompMinimumHitTarget()
                .accessibilityLabel(PlanCopy.markMealCooked(viewModel.title(ofRecipe: target.recipeId)))
                .accessibilityIdentifier(AccessibilityID.mealMarkCooked)
        }
    }
}

extension View {
    /// An inline navigation title on iOS; macOS has no such display mode.
    @ViewBuilder
    fileprivate func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
