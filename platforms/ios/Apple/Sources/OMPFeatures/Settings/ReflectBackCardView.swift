import OMPDomain
import OMPUI
import SwiftUI

/// The reflect-back card (C-100; AC-12.2, AC-12.3): "{observation}. Should I plan around that?"
/// with Yes, Not really and Don't ask again. It sits at the top of the Plan tab, one at a time,
/// and never while a safety card is showing.
struct ReflectBackCardView: View {
    let model: ReflectBackModel

    var body: some View {
        if let question = model.question {
            InlineCard(title: question) {
                VStack(alignment: .leading, spacing: OMPSpacing.small) {
                    button(SettingsCopy.yes, id: AccessibilityID.reflectYes, answer: .yes)
                    button(SettingsCopy.notReally, id: AccessibilityID.reflectNo, answer: .notReally)
                    button(SettingsCopy.dontAskAgain, id: AccessibilityID.reflectNever, answer: .dontAskAgain)
                }
            }
            .accessibilityIdentifier(AccessibilityID.reflectCard)
        }
    }

    private func button(_ title: String, id: String, answer: ReflectBackAnswer) -> some View {
        Button(title) { Task { await model.answer(answer) } }
            .buttonStyle(.bordered)
            .tint(Color.primary)
            .ompMinimumHitTarget()
            .disabled(model.isAnswering)
            .accessibilityIdentifier(id)
    }
}
