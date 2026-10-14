import OMPCapture
import OMPDomain
import OMPUI
import SwiftUI

/// First launch (flow F1): S-01 Who's eating? -> S-02 safety question -> S-03 cuisines ->
/// S-04 making the plan. It replaces the tabs until the first plan exists, so there is no
/// way around the safety question: no skip, no close, no gesture that leaves it.
@MainActor
struct OnboardingFlowView: View {
    @State private var model: OnboardingModel

    init(
        services: SafetyServices, speech: (any SpeechCapture)?,
        onFinished: @escaping @MainActor () async -> Void
    ) {
        _model = State(initialValue: OnboardingModel(services: services, speech: speech, onFinished: onFinished))
    }

    var body: some View {
        Group {
            switch model.step {
            case .whoIsEating:
                WhoIsEatingView(model: model)
            case .safety:
                SafetyQuestionPage(model: model)
            case .cuisines:
                CuisinePage(model: model)
            case .planning:
                PlanningPage(model: model)
            }
        }
        .alert(SafetyCopy.saveFailed, isPresented: $model.saveFailed) {
            Button(SafetyCopy.tryAgain, role: .cancel) {}
        }
    }
}

/// A scrolling page with the readable width of the onboarding card (iPad: centred, ~600 pt).
private struct OnboardingPage<Content: View>: View {
    let identifier: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OMPSpacing.medium) {
                content
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth, alignment: .leading)
            .padding(OMPSpacing.large)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - S-01

struct WhoIsEatingView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        OnboardingPage(identifier: AccessibilityID.whoRoot) {
            Text(SafetyCopy.whoTitle)
                .font(OMPFont.screenTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(SafetyCopy.whoSubtitle)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)

            Stepper(value: $model.adults, in: 0...model.maxAdults) {
                Text(verbatim: "\(SafetyCopy.adults): \(model.adults)").font(OMPFont.body)
            }
            .accessibilityIdentifier(AccessibilityID.whoAdults)

            Stepper(value: $model.children, in: 0...model.maxChildren) {
                Text(verbatim: "\(SafetyCopy.children): \(model.children)").font(OMPFont.body)
            }
            .accessibilityIdentifier(AccessibilityID.whoChildren)

            Text(footnote)
                .font(OMPFont.disclaimer)
                .foregroundStyle(Color.primary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.whoFootnote)
        }
        .ompPrimaryBottomBar {
            Button(SafetyCopy.continueButton) { Task { await model.continueFromWho() } }
                .buttonStyle(.ompPrimary)
                .disabled(!model.canContinueFromWho)
                .accessibilityIdentifier(AccessibilityID.whoContinue)
        }
    }

    /// C-012 when empty, C-013 at the cap, else C-011c.
    private var footnote: String {
        if model.total < 1 { return SafetyCopy.addOnePerson }
        if model.atMemberLimit { return SafetyCopy.maxPeople }
        return SafetyCopy.teensNote
    }
}

// MARK: - S-02 (onboarding variant)

struct SafetyQuestionPage: View {
    let model: OnboardingModel

    var body: some View {
        if let answer = model.safetyModel {
            let isMemberPage = answer.subjectMember != nil
            OnboardingPage(identifier: AccessibilityID.safetyRoot + ".page") {
                // Back returns to S-01; the question stays unanswered. There is no skip or close.
                if !isMemberPage {
                    Button {
                        model.backToWho()
                    } label: {
                        Label(SafetyCopy.back, systemImage: "chevron.left")
                    }
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.safetyBack)
                }
                Text(
                    answer.subjectMember.map { SafetyGateCover.title(for: $0) } ?? SafetyCopy.safetyTitle
                )
                .font(OMPFont.screenTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                SafetyAnswerView(model: answer)
            }
            .interactiveDismissDisabled(true)
            .id(ObjectIdentifier(answer))
        }
    }
}

// MARK: - S-03

struct CuisinePage: View {
    let model: OnboardingModel

    var body: some View {
        OnboardingPage(identifier: AccessibilityID.cuisineRoot) {
            AdaptiveStack(spacing: OMPSpacing.small) {
                Button {
                    model.backFromCuisines()
                } label: {
                    Label(SafetyCopy.back, systemImage: "chevron.left")
                }
                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.cuisineBack)
                Spacer(minLength: 0)
                Button(SafetyCopy.skip) { Task { await model.continueFromCuisines(skip: true) } }
                    .ompMinimumHitTarget()
                    .disabled(model.isWorking)
                    .accessibilityIdentifier(AccessibilityID.cuisineSkip)
            }
            Text(SafetyCopy.cuisineTitle)
                .font(OMPFont.screenTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(SafetyCopy.cuisineSubtitle)
                .font(OMPFont.body)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout {
                ForEach(CuisineChoice.all) { choice in
                    ChipToggle(
                        title: choice.title,
                        isSelected: model.selectedCuisines.contains(choice.identifier),
                        identifier: AccessibilityID.cuisineChip(choice.identifier)
                    ) {
                        model.toggleCuisine(choice)
                    }
                }
            }
        }
        .ompPrimaryBottomBar {
            Button(SafetyCopy.makeMyPlan) { Task { await model.continueFromCuisines(skip: false) } }
                .buttonStyle(.ompPrimary)
                .disabled(model.isWorking)
                .accessibilityIdentifier(AccessibilityID.cuisineMakePlan)
        }
    }
}

// MARK: - S-04

struct PlanningPage: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: OMPSpacing.medium) {
            switch model.planningPhase {
            case .working:
                ProgressView()
                    .accessibilityHidden(true)
                Text(model.isSlow ? SafetyCopy.stillWorking : SafetyCopy.planning)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            case .failed:
                Image(systemName: OMPSymbol.warning)
                    .foregroundStyle(OMPColor.warning)
                    .accessibilityHidden(true)
                Text(SafetyCopy.planError)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(SafetyCopy.tryAgain) { Task { await model.makePlan() } }
                    .buttonStyle(.ompPrimary)
                    .accessibilityIdentifier(AccessibilityID.planningRetry)
            }
        }
        .padding(OMPSpacing.large)
        .frame(maxWidth: OMPMetrics.coverMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.planningRoot)
    }
}
