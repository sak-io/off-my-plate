import OMPDomain
import OMPUI
import SwiftUI

/// Accessibility identifiers of the share screen.
public enum ShareAccessibilityID {
    public static let review = "share.review"
    public static let add = "share.add"
    public static let cancel = "share.cancel"
    public static let notText = "share.notText"
    public static let empty = "share.empty"
    public static let saved = "share.saved"
    public static let error = "share.error"
    public static let close = "share.close"
}

/// S-40: the Notes import review (docs/design/screens.md section 7). Shows nothing from the
/// household, the plan or safety.
public struct ShareImportView: View {
    @Bindable private var model: ShareImportModel
    private let onClose: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: ShareImportModel, onClose: @escaping @MainActor () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(ShareCopy.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ShareCopy.cancel) { onClose() }
                            .accessibilityIdentifier(ShareAccessibilityID.cancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if model.phase == .review || model.phase == .saving {
                            Button(ShareCopy.add(model.addCount)) {
                                Task { await model.confirm() }
                            }
                            .disabled(!model.canAdd)
                            .accessibilityIdentifier(ShareAccessibilityID.add)
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .parsing:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .notText:
            message(ShareCopy.notText, identifier: ShareAccessibilityID.notText, showsClose: true)
        case .empty:
            message(ShareCopy.empty, identifier: ShareAccessibilityID.empty, showsClose: true)
        case .saved:
            message(ShareCopy.saved, identifier: ShareAccessibilityID.saved, showsClose: false)
                .task { await closeAfterDelay() }
        case .review, .saving:
            review
        }
    }

    /// Announces C-172, then closes after about 1.5 s, or at once with Reduce Motion (screens.md S-40).
    private func closeAfterDelay() async {
        AccessibilityNotification.Announcement(ShareCopy.saved).post()
        if !reduceMotion { try? await Task.sleep(for: .milliseconds(1500)) }
        guard !Task.isCancelled else { return }
        onClose()
    }

    private func message(_ text: String, identifier: String, showsClose: Bool) -> some View {
        VStack(spacing: OMPSpacing.medium) {
            Text(text)
                .font(OMPFont.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
            if showsClose {
                Button(ShareCopy.close) { onClose() }
                    .buttonStyle(.ompPrimary)
                    .accessibilityIdentifier(ShareAccessibilityID.close)
            }
        }
        .padding(OMPSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var review: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OMPSpacing.medium) {
                Text(ShareCopy.destination)
                    .font(OMPFont.mealName)
                    .accessibilityAddTraits(.isHeader)
                Picker(ShareCopy.destination, selection: $model.destination) {
                    Text(ShareCopy.shoppingList).tag(InboxImport.Destination.shoppingList)
                    Text(ShareCopy.pantry).tag(InboxImport.Destination.pantry)
                }
                .pickerStyle(.segmented)

                ForEach($model.rows) { $row in
                    if !row.isUnsure {
                        ShareRowView(row: $row, onRemove: { model.remove(row.id) })
                    }
                }

                if model.rows.contains(where: \.isUnsure) {
                    Text(ShareCopy.unsureHeader)
                        .font(OMPFont.mealName)
                        .accessibilityAddTraits(.isHeader)
                    ForEach($model.rows) { $row in
                        if row.isUnsure {
                            ShareRowView(row: $row, onRemove: { model.remove(row.id) })
                        }
                    }
                }

                if model.saveFailed {
                    Label(ShareCopy.error, systemImage: OMPSymbol.warning)
                        .font(OMPFont.body)
                        .accessibilityIdentifier(ShareAccessibilityID.error)
                }
            }
            .padding(OMPSpacing.medium)
        }
        .accessibilityIdentifier(ShareAccessibilityID.review)
        .disabled(model.phase == .saving)
    }
}

/// One editable review row: include box (or Keep for odd lines), name, amount, unit, remove.
private struct ShareRowView: View {
    @Binding var row: ShareImportModel.Row
    let onRemove: () -> Void

    private static let units = MeasureUnit.allCases.filter(\.isQuantified)

    var body: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            HStack(spacing: OMPSpacing.small) {
                includeControl
                TextField(ShareCopy.namePrompt, text: $row.name)
                    .font(OMPFont.body)
                    .textFieldStyle(.roundedBorder)
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .accessibilityHidden(true)
                }
                .ompMinimumHitTarget()
                .accessibilityLabel(ShareCopy.remove(row.name))
            }
            HStack(spacing: OMPSpacing.small) {
                TextField(ShareCopy.quantityPrompt, text: $row.quantityText)
                    .font(OMPFont.body)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Menu {
                    Button(ShareCopy.noUnit) { row.unit = nil }
                    ForEach(Self.units, id: \.self) { unit in
                        Button(unit.rawValue) { row.unit = unit }
                    }
                } label: {
                    Text(row.unit?.rawValue ?? ShareCopy.unitPrompt)
                        .font(OMPFont.body)
                        .ompMinimumHitTarget()
                }
            }
        }
    }

    @ViewBuilder
    private var includeControl: some View {
        if row.isUnsure {
            Button(ShareCopy.keep) { row.isIncluded.toggle() }
                .font(OMPFont.body)
                .buttonStyle(.bordered)
                .accessibilityValue(row.isIncluded ? "1" : "0")
        } else {
            Button {
                row.isIncluded.toggle()
            } label: {
                Image(systemName: row.isIncluded ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
            .ompMinimumHitTarget()
            .accessibilityLabel(ShareCopy.include(row.name))
            .accessibilityAddTraits(row.isIncluded ? .isSelected : [])
        }
    }
}
