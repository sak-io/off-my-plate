import OMPDomain
import OMPUI
import SwiftUI

/// S-14: who takes lunch to school and on which days (AC-7.2). Children and Monday to Friday
/// are preselected; Save is off until at least one child and one day are chosen.
struct SchoolLunchesSheet: View {
    let viewModel: PlanViewModel
    @State private var children: Set<MemberID>
    @State private var days: Set<Weekday> = Weekday.schoolWeek

    init(viewModel: PlanViewModel) {
        self.viewModel = viewModel
        _children = State(initialValue: Set(viewModel.schoolChildren.map(\.id)))
    }

    private var canSave: Bool { !children.isEmpty && !days.isEmpty && !viewModel.isBusy }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(viewModel.schoolChildren) { child in
                        Toggle(
                            child.displayName,
                            isOn: Binding(
                                get: { children.contains(child.id) },
                                set: { isOn in
                                    if isOn { children.insert(child.id) } else { children.remove(child.id) }
                                })
                        )
                        .accessibilityIdentifier(AccessibilityID.schoolChild(child.id.rawValue))
                    }
                } header: {
                    Text(PlanCopy.whoTakesLunch)
                }
                Section {
                    ForEach(Weekday.allCases, id: \.self) { day in
                        Toggle(
                            PlanCopy.weekdayShort(day),
                            isOn: Binding(
                                get: { days.contains(day) },
                                set: { isOn in
                                    if isOn { days.insert(day) } else { days.remove(day) }
                                })
                        )
                        .accessibilityIdentifier(AccessibilityID.schoolDay(day.rawValue))
                    }
                } header: {
                    Text(PlanCopy.whichDays)
                } footer: {
                    if !canSave {
                        Text(PlanCopy.pickAtLeastOne)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
            .accessibilityIdentifier(AccessibilityID.schoolSheet)
            .navigationTitle(PlanCopy.schoolLunches)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PlanCopy.cancel) { viewModel.sheet = nil }
                        .accessibilityIdentifier(AccessibilityID.schoolCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(PlanCopy.save) {
                        Task { await viewModel.saveSchoolLunches(children: children, days: days) }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier(AccessibilityID.schoolSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
