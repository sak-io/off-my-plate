import OMPDomain
import OMPUI
import SwiftUI

/// The List tab (screen S-25; task T25): the shopping list in aisle sections, "Check you have"
/// first, manual add, check-off, Bought everything and Share. Replaces the T21 placeholder.
public struct ShoppingTabView: View {
    @State private var viewModel: ShoppingViewModel
    private let goToPlan: @MainActor () -> Void

    /// - Parameter goToPlan: switches to the Plan tab (the "Go to plan" button of C-140).
    public init(model: AppModel, goToPlan: @escaping @MainActor () -> Void) {
        self.goToPlan = goToPlan
        _viewModel = State(initialValue: ShoppingViewModel(backend: model.shoppingBackend, clock: model.clock))
    }

    public var body: some View {
        NavigationStack {
            // The Bought everything bar sits BELOW the list in a stack, not over it as a safe-area
            // inset: rows scrolled under an inset stay in the accessibility tree and fail contrast.
            VStack(spacing: 0) {
                content
                bottomBar
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.tabRoot(.list))
            .navigationTitle(ShoppingCopy.title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: viewModel.shareText) {
                        Label(ShoppingCopy.share, systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier(AccessibilityID.shoppingShare)
                    Menu {
                        Button(ShoppingCopy.boughtEverything) { viewModel.requestBoughtEverything() }
                            .disabled(!viewModel.canBuyEverything)
                            .accessibilityIdentifier(AccessibilityID.shoppingMenuBought)
                        Button(ShoppingCopy.clearChecked) { Task { await viewModel.clearChecked() } }
                            .disabled(viewModel.checkedCount == 0)
                            .accessibilityIdentifier(AccessibilityID.shoppingMenuClear)
                    } label: {
                        Label(ShoppingCopy.menu, systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier(AccessibilityID.shoppingMenu)
                }
            }
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            ShoppingCopy.boughtConfirm(viewModel.checkedCount), isPresented: confirmBinding,
            titleVisibility: .visible
        ) {
            Button(ShoppingCopy.addToPantry) { Task { await viewModel.confirmBoughtEverything() } }
            Button(ShoppingCopy.cancel, role: .cancel) {}
        }
    }

    private var confirmBinding: Binding<Bool> {
        Binding(get: { viewModel.isConfirmingBought }, set: { viewModel.isConfirmingBought = $0 })
    }

    private var newItemBinding: Binding<String> {
        Binding(get: { viewModel.newItemName }, set: { viewModel.newItemName = $0 })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ShoppingLoadingView()
        case .failed:
            ShoppingFailedView(viewModel: viewModel)
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            Section {
                topArea
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            ForEach(viewModel.sections) { section in
                Section {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(section.headerID)
                    ForEach(section.items) { item in
                        ShoppingItemRow(viewModel: viewModel, item: item)
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.shoppingList)
    }

    /// Range, banners, the add field and the empty states, above the sections.
    private var topArea: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            if let range = viewModel.rangeText {
                Text(range)
                    .font(OMPFont.mealName)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.shoppingRange)
            }
            if viewModel.hasError {
                InlineCard(title: ShoppingCopy.saveFailed, systemImage: OMPSymbol.warning)
                    .accessibilityIdentifier(AccessibilityID.shoppingError)
            }
            if viewModel.showsPendingChanges {
                InlineCard(title: ShoppingCopy.pendingChanges, systemImage: OMPSymbol.draft)
                    .accessibilityIdentifier(AccessibilityID.shoppingPending)
            }
            if viewModel.showsNoPlan {
                InlineCard(title: ShoppingCopy.noPlan, systemImage: OMPSymbol.plan) {
                    Button(ShoppingCopy.goToPlan, action: goToPlan)
                        .buttonStyle(.bordered)
                        .tint(Color.primary)
                        .ompMinimumHitTarget()
                        .accessibilityIdentifier(AccessibilityID.shoppingGoToPlan)
                }
                .accessibilityIdentifier(AccessibilityID.shoppingNoPlan)
            }
            if viewModel.showsNothingToBuy {
                Text(ShoppingCopy.nothingToBuy)
                    .font(OMPFont.body)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.shoppingNothing)
            }
            TextField(ShoppingCopy.addField, text: newItemBinding)
                .font(OMPFont.body)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .disabled(viewModel.isBusy)
                .onSubmit { Task { await viewModel.addItem() } }
                .frame(minHeight: OMPMetrics.minimumHitTarget)
                .accessibilityIdentifier(AccessibilityID.shoppingAddField)
        }
        .padding(.horizontal, OMPSpacing.medium)
        .padding(.vertical, OMPSpacing.small)
    }

    /// The Bought everything bar (screens.md S-25): enabled when at least one item is checked.
    @ViewBuilder
    private var bottomBar: some View {
        if viewModel.phase == .loaded {
            Button(ShoppingCopy.boughtEverything) { viewModel.requestBoughtEverything() }
                .buttonStyle(.ompPrimary)
                .disabled(!viewModel.canBuyEverything)
                .accessibilityIdentifier(AccessibilityID.shoppingBought)
                .padding(OMPSpacing.medium)
                // Room above the floating tab bar (iOS 26 glass), as on the Plan tab.
                .padding(.bottom, OMPSpacing.large)
                .frame(maxWidth: .infinity)
                .planBarBackground()
        }
    }
}

// MARK: Phases

struct ShoppingLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                ProgressView()
                Text(ShoppingCopy.loading)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(AccessibilityID.shoppingLoading)
            }
            .frame(maxWidth: .infinity)
            .padding(OMPSpacing.large)
        }
    }
}

/// C-095 with Try again, when the list could not be loaded at all.
struct ShoppingFailedView: View {
    let viewModel: ShoppingViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                Image(systemName: OMPSymbol.warning).font(.largeTitle).accessibilityHidden(true)
                Text(ShoppingCopy.saveFailed)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.shoppingError)
                Button(ShoppingCopy.tryAgain) { Task { await viewModel.retry() } }
                    .buttonStyle(.ompPrimary)
                    .accessibilityIdentifier(AccessibilityID.shoppingErrorRetry)
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth)
            .padding(OMPSpacing.large)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Rows

/// One list line. A "to buy" line toggles on tap; a "Check you have" line has the two buttons
/// "I have it" and "Need it" (C-145).
struct ShoppingItemRow: View {
    let viewModel: ShoppingViewModel
    let item: ShoppingItem

    var body: some View {
        Group {
            switch item.group {
            case .toBuy: toBuyRow
            case .checkYouHave: checkRow
            }
        }
        .swipeActions(edge: .trailing) {
            if item.origin != .plan {
                Button(ShoppingCopy.remove, role: .destructive) { Task { await viewModel.remove(item) } }
            }
        }
    }

    private var toBuyRow: some View {
        Button {
            Task { await viewModel.toggle(item) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                Image(systemName: item.checkedOff ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.lineText(item))
                        .font(OMPFont.body)
                        .strikethrough(item.checkedOff)
                        .foregroundStyle(Color.primary)
                    if let origin = viewModel.originText(item) {
                        Text(origin).font(OMPFont.reason).foregroundStyle(Color.primary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: OMPMetrics.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.lineText(item))
        .accessibilityValue(item.checkedOff ? ShoppingCopy.checked : ShoppingCopy.notChecked)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(AccessibilityID.shoppingItem(item.id.rawValue))
    }

    private var checkRow: some View {
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Text(viewModel.lineText(item))
                .font(OMPFont.body)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(AccessibilityID.shoppingItem(item.id.rawValue))
            AdaptiveStack(spacing: OMPSpacing.small) {
                choice(ShoppingCopy.haveIt, selected: item.checkedOff, checked: true)
                    .accessibilityIdentifier(AccessibilityID.shoppingHaveIt(item.id.rawValue))
                choice(ShoppingCopy.needIt, selected: !item.checkedOff, checked: false)
                    .accessibilityIdentifier(AccessibilityID.shoppingNeedIt(item.id.rawValue))
            }
        }
        .padding(.vertical, OMPSpacing.small)
    }

    /// "I have it" checks the line (Bought everything then confirms the pantry); "Need it" keeps
    /// it unchecked. The chosen one shows a check mark, not colour alone.
    private func choice(_ title: String, selected: Bool, checked: Bool) -> some View {
        Button {
            Task { await viewModel.setChecked(item, checked) }
        } label: {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(.bordered)
        .tint(Color.primary)
        .ompMinimumHitTarget()
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}
