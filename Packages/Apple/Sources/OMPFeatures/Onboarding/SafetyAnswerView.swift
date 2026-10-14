import OMPCapture
import OMPDomain
import OMPUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The safety question (S-02, S-02b and the gate-cover variant). It has no skip, close or
/// dismiss control of its own: the only ways forward are an explicit answer or, in the member
/// variant, removing the person that was added by mistake.
///
/// The parent supplies the title (onboarding: C-020, cover: C-030) so this view can sit under
/// either.
struct SafetyAnswerView: View {
    @Bindable var model: SafetyAnswerModel
    @Environment(\.openURL) private var openURL
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.medium) {
            switch model.phase {
            case .entry: entry
            case .summary: summary
            }
        }
        .alert(SafetyCopy.saveFailed, isPresented: $model.saveFailed) {
            Button(SafetyCopy.tryAgain, role: .cancel) {}
        }
        .alert(
            SafetyCopy.confirmRemoveTitle(model.subjectMember?.displayName ?? ""),
            isPresented: $model.isConfirmingRemoveMember
        ) {
            Button(SafetyCopy.remove, role: .destructive) { Task { await model.removeSubject() } }
            Button(SafetyCopy.cancel, role: .cancel) {}
        }
        .onDisappear { model.viewDisappeared() }
    }

    // MARK: Entry (S-02)

    @ViewBuilder
    private var entry: some View {
        Text(SafetyCopy.reason)
            .font(OMPFont.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(AccessibilityID.safetyRoot)

        nobodyButton

        Text(SafetyCopy.orTellMe)
            .font(OMPFont.reason)
            .foregroundStyle(Color.primary.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

        FlowLayout {
            ForEach(model.restrictions) { restriction in
                ChipToggle(
                    title: SafetyCopy.label(for: restriction),
                    isSelected: model.isChipSelected(restriction.id),
                    identifier: AccessibilityID.safetyChip(restriction.id.rawValue)
                ) {
                    model.toggleChip(restriction.id)
                }
            }
        }

        textEntry
        voiceNotice

        if !model.items.isEmpty { list }

        DisclaimerFooter(.safety)

        if !model.items.isEmpty {
            Button(SafetyCopy.continueButton) { model.continueToSummary() }
                .buttonStyle(.ompPrimary)
                .disabled(!model.canContinue)
                .accessibilityIdentifier(AccessibilityID.safetyContinue)
            if model.hasUnresolved {
                Text(SafetyCopy.sortOutItem)
                    .font(OMPFont.disclaimer)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.safetyContinueHint)
            }
        }

        if model.canRemoveSubject, let member = model.subjectMember {
            Button { model.isConfirmingRemoveMember = true } label: {
                Text(SafetyCopy.removeMember(member.displayName))
                    .font(OMPFont.reason)
                    .underline()
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.safetyRemoveMember)
        }
    }

    private var nobodyButton: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            let isGate = model.subjectMember != nil
            Button(isGate ? SafetyCopy.noNothing : SafetyCopy.noNobody) {
                Task { await model.chooseNobody() }
            }
            .buttonStyle(.ompPrimary)
            .disabled(!model.canChooseNobody)
            .accessibilityLabel(
                model.subjectMember.map { SafetyCopy.noNothingVoiceOver($0.displayName) }
                    ?? SafetyCopy.noNobodyVoiceOver
            )
            .accessibilityIdentifier(AccessibilityID.safetyNobody)
            if !model.items.isEmpty {
                Text(SafetyCopy.removeToChooseNobody)
                    .font(OMPFont.disclaimer)
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.safetyNobodyHint)
            }
        }
    }

    private var textEntry: some View {
        AdaptiveStack(spacing: OMPSpacing.small) {
            TextField(SafetyCopy.placeholder, text: $model.draftText, axis: .vertical)
                .lineLimit(1...4)
                .font(OMPFont.body)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .focused($textFocused)
                .onSubmit {
                    model.submitText()
                    textFocused = false
                }
                .onChange(of: model.draftText) { _, text in
                    let hadNewline = text.contains("\n")
                    model.draftTextChanged()
                    if hadNewline { textFocused = false }
                }
                .accessibilityIdentifier(AccessibilityID.safetyText)
            Button {
                textFocused = false
                Task { await model.micTapped() }
            } label: {
                Label(
                    model.voice == .listening ? SafetyCopy.done : SafetyCopy.speak,
                    systemImage: model.voice == .listening ? OMPSymbol.listening : OMPSymbol.mic)
            }
            .buttonStyle(SafetyOutlinedButtonStyle())
            .ompMinimumHitTarget()
            .accessibilityIdentifier(AccessibilityID.safetyMic)
        }
    }

    @ViewBuilder
    private var voiceNotice: some View {
        if model.voice == .listening {
            Text(SafetyCopy.listening)
                .font(OMPFont.reason)
                .accessibilityAddTraits(.updatesFrequently)
        } else if case .unavailable(let reason) = model.voice {
            VStack(alignment: .leading, spacing: OMPSpacing.small) {
                Text(reason == .permissionDenied ? SafetyCopy.voicePermissionDenied : SafetyCopy.voiceUnavailable)
                    .font(OMPFont.reason)
                    .fixedSize(horizontal: false, vertical: true)
                AdaptiveStack(spacing: OMPSpacing.small) {
                    #if canImport(UIKit)
                    if reason == .permissionDenied {
                        Button(SafetyCopy.openSettings) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(SafetyOutlinedButtonStyle())
                        .ompMinimumHitTarget()
                    }
                    #endif
                    Button(SafetyCopy.typeInstead) {
                        model.dismissVoiceNotice()
                        textFocused = true
                    }
                    .buttonStyle(SafetyOutlinedButtonStyle())
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.safetyVoiceTypeInstead)
                }
            }
            .padding(OMPSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ompCardBackground()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.safetyVoiceNotice)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Text(SafetyCopy.toAvoid)
                .font(OMPFont.mealName)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.items) { item in
                row(item)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: AvoidItem) -> some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            if let restriction = item.restrictionID {
                Text(model.label(for: restriction))
                    .font(OMPFont.mealName)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.whoOptions.isEmpty {
                    Picker(
                        SafetyCopy.who,
                        selection: Binding(
                            get: { item.scope }, set: { model.setScope($0, for: item.id) })
                    ) {
                        Text(SafetyCopy.notSureWho).tag(RuleScope.household)
                        ForEach(model.whoOptions) { member in
                            Text(member.displayName).tag(RuleScope.member(member.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier(AccessibilityID.safetyItemWho(item.id))
                }
            } else if case .unresolved(let text) = item.resolution {
                HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                    Image(systemName: OMPSymbol.warning)
                        .foregroundStyle(OMPColor.warning)
                        .accessibilityHidden(true)
                    Text(SafetyCopy.unrecognised(text))
                        .font(OMPFont.reason)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Menu {
                    ForEach(model.restrictions) { restriction in
                        Button(SafetyCopy.label(for: restriction)) {
                            model.resolve(item.id, to: restriction.id)
                        }
                    }
                } label: {
                    Text(SafetyCopy.pickClosest)
                        .font(OMPFont.body)
                        .ompMinimumHitTarget()
                }
                .accessibilityIdentifier(AccessibilityID.safetyItemPick(item.id))
            }
            Button(SafetyCopy.remove) { model.remove(item.id) }
                .buttonStyle(SafetyOutlinedButtonStyle())
                .ompMinimumHitTarget()
                .accessibilityLabel(removeLabel(item))
                .accessibilityIdentifier(AccessibilityID.safetyItemRemove(item.id))
        }
        .padding(OMPSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ompCardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.safetyItem(item.id))
    }

    private func removeLabel(_ item: AvoidItem) -> String {
        switch item.resolution {
        case .restriction(let id): return "\(SafetyCopy.remove) \(model.label(for: id))"
        case .unresolved(let text): return "\(SafetyCopy.remove) \(text)"
        }
    }

    // MARK: Summary (S-02b)

    @ViewBuilder
    private var summary: some View {
        Text(SafetyCopy.checkTitle)
            .font(OMPFont.sectionTitle.bold())
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(AccessibilityID.safetySummary)
        ForEach(model.summaryRows) { row in
            VStack(alignment: .leading, spacing: 2) {
                Text(row.who).font(OMPFont.mealName)
                Text(row.items.isEmpty ? SafetyCopy.nothingToAvoid : row.items.joined(separator: ", "))
                    .font(OMPFont.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        DisclaimerFooter(.safety)
        Button(SafetyCopy.yesSave) { Task { await model.confirmSummary() } }
            .buttonStyle(.ompPrimary)
            .disabled(model.isSaving)
            .accessibilityIdentifier(AccessibilityID.safetySummarySave)
        Button(SafetyCopy.change) { model.backToEntry() }
            .buttonStyle(SafetyOutlinedButtonStyle())
            .ompMinimumHitTarget()
            .accessibilityIdentifier(AccessibilityID.safetySummaryChange)
    }
}

/// A visible, high-contrast secondary button: primary-coloured label and outline on the plain
/// background (the default bordered style tints the label on a gray fill and fails the audit).
struct SafetyOutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OMPFont.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, OMPSpacing.medium)
            .padding(.vertical, OMPSpacing.small)
            .frame(minHeight: OMPMetrics.minimumHitTarget)
            .overlay(
                RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(RoundedRectangle(cornerRadius: OMPMetrics.cardCornerRadius, style: .continuous))
    }
}
