import OMPDomain
import OMPUI
import SwiftUI

/// The Pantry tab (S-20; task T24): what is at home by place, stale and unrecognised items,
/// search, and the sheets S-21 to S-23. Replaces the T21 placeholder.
///
/// Plain layouts, not `ContentUnavailableView`, and custom group headers instead of default list
/// section headers: both failed the accessibility audit before (LESSONS).
public struct PantryTabView: View {
    private let model: AppModel
    @State private var viewModel: PantryViewModel

    public init(model: AppModel) {
        self.model = model
        _viewModel = State(
            initialValue: PantryViewModel(
                backend: model.pantryBackend, clock: model.clock, speech: model.speechCapture))
    }

    public var body: some View {
        NavigationStack {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.tabRoot(.pantry))
                .navigationTitle(PantryCopy.title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.openSpeak()
                        } label: {
                            Label(PantryCopy.speak, systemImage: OMPSymbol.mic)
                                .labelStyle(.iconOnly)
                        }
                        .tint(Color.primary)
                        .ompMinimumHitTarget()
                        .accessibilityIdentifier(AccessibilityID.pantrySpeak)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.openAdd()
                        } label: {
                            Label(PantryCopy.addItem, systemImage: "plus")
                                .labelStyle(.iconOnly)
                        }
                        .tint(Color.primary)
                        .ompMinimumHitTarget()
                        .accessibilityIdentifier(AccessibilityID.pantryAdd)
                    }
                }
        }
        .onAppear { Task { await viewModel.load() } }
        .sheet(item: $viewModel.sheet, onDismiss: { viewModel.sheetDismissed() }) { sheet in
            sheetContent(sheet)
        }
        .ompToast($viewModel.toast)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: PantrySheet) -> some View {
        if let backend = viewModel.pantryBackend {
            switch sheet {
            case .add(let prefill):
                PantryFormSheet(viewModel: viewModel, backend: backend, item: nil, prefill: prefill)
            case .edit(let id):
                PantryFormSheet(viewModel: viewModel, backend: backend, item: viewModel.item(id), prefill: nil)
            case .speak:
                PantryVoiceSheet(viewModel: viewModel, backend: backend)
            }
        } else {
            Text(PantryCopy.loadFailed).font(OMPFont.body).padding(OMPSpacing.large)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            PantryLoadingView()
        case .failed:
            PantryFailedView(viewModel: viewModel)
        case .loaded:
            if viewModel.isEmpty {
                PantryEmptyView(viewModel: viewModel)
            } else {
                PantryList(viewModel: viewModel)
            }
        }
    }
}

// MARK: Phases

struct PantryLoadingView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                ProgressView()
                Text(PantryCopy.loading)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(AccessibilityID.pantryLoading)
            }
            .frame(maxWidth: .infinity)
            .padding(OMPSpacing.large)
        }
    }
}

struct PantryFailedView: View {
    let viewModel: PantryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                Image(systemName: OMPSymbol.warning).font(.largeTitle).accessibilityHidden(true)
                Text(viewModel.errorMessage ?? PantryCopy.loadFailed)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.pantryError)
                Button(PantryCopy.tryAgain) { Task { await viewModel.retry() } }
                    .buttonStyle(.ompPrimary)
                    .accessibilityIdentifier(AccessibilityID.pantryErrorRetry)
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth)
            .padding(OMPSpacing.large)
            .frame(maxWidth: .infinity)
        }
    }
}

/// C-122 and C-123: an empty pantry, with the two ways to fill it.
struct PantryEmptyView: View {
    let viewModel: PantryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: OMPSpacing.medium) {
                Image(systemName: OMPSymbol.pantry).font(.largeTitle).accessibilityHidden(true)
                Text(PantryCopy.emptyTitle)
                    .font(OMPFont.sectionTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.pantryEmpty)
                Text(PantryCopy.emptyBody)
                    .font(OMPFont.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(PantryCopy.addItem) { viewModel.openAdd() }
                    .buttonStyle(.ompPrimary)
                    .accessibilityIdentifier(AccessibilityID.pantryEmptyAdd)
                Button {
                    viewModel.openSpeak()
                } label: {
                    Label(PantryCopy.speak, systemImage: OMPSymbol.mic)
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
                .ompMinimumHitTarget()
                .accessibilityIdentifier(AccessibilityID.pantryEmptySpeak)
            }
            .frame(maxWidth: OMPMetrics.coverMaxWidth)
            .padding(OMPSpacing.large)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: The list

struct PantryList: View {
    @Bindable var viewModel: PantryViewModel

    var body: some View {
        List {
            Section {
                PantrySearchField(text: $viewModel.searchText)
                    .listRowBackground(Color.clear)
            }
            if let message = viewModel.errorMessage {
                Section {
                    InlineCard(title: message, systemImage: OMPSymbol.warning) {
                        Button(PantryCopy.tryAgain) { Task { await viewModel.retry() } }
                            .buttonStyle(.bordered)
                            .tint(Color.primary)
                            .ompMinimumHitTarget()
                            .accessibilityIdentifier(AccessibilityID.pantryErrorRetry)
                    }
                    .accessibilityIdentifier(AccessibilityID.pantryError)
                    .listRowBackground(Color.clear)
                }
            }
            if viewModel.hasNoSearchResults {
                Section {
                    Text(viewModel.noResultsText)
                        .font(OMPFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(AccessibilityID.pantryNoResults)
                }
            }
            ForEach(viewModel.groups) { group in
                Section {
                    Text(PantryCopy.location(group.location))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(AccessibilityID.pantryGroup(group.id))
                    ForEach(group.rows) { row in
                        PantryRowView(viewModel: viewModel, row: row)
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.pantryList)
    }
}

/// One pantry item (S-20): name, amount, use-by, the stale and unrecognised notes with their
/// buttons. Tap opens the edit form; swipe (or the context menu) deletes.
struct PantryRowView: View {
    let viewModel: PantryViewModel
    let row: PantryRow

    var body: some View {
        let id = row.id.rawValue
        VStack(alignment: .leading, spacing: OMPSpacing.small) {
            Button {
                viewModel.openEdit(row.id)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: OMPSpacing.small) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.isUnresolved ? "“\(row.name)”" : row.name)
                            .font(OMPFont.mealName)
                        Text(row.amountText)
                            .font(OMPFont.reason)
                            .foregroundStyle(Color.primary)
                        if let useBy = row.useByText {
                            Text(useBy)
                                .font(OMPFont.reason)
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.primary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.pantryRow(id))

            if row.isStale {
                StatusLabel(PantryCopy.stale, systemImage: OMPSymbol.warning)
                    .font(OMPFont.reason)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.pantryStale(id))
                Button(PantryCopy.stillHaveIt) { Task { await viewModel.reconfirm(row.id) } }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.pantryStillHaveIt(id))
            }
            if row.isUnresolved {
                StatusLabel(PantryCopy.notRecognised, systemImage: OMPSymbol.warning)
                    .font(OMPFont.reason)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.pantryUnresolved(id))
                Button(PantryCopy.matchIt) { viewModel.openEdit(row.id) }
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .ompMinimumHitTarget()
                    .accessibilityIdentifier(AccessibilityID.pantryMatch(id))
            }
        }
        .padding(.vertical, OMPSpacing.small)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task { await viewModel.delete(row.id) }
            } label: {
                Text(PantryCopy.delete)
            }
        }
        .contextMenu {
            Button(PantryCopy.editItem) { viewModel.openEdit(row.id) }
            Button(PantryCopy.delete, role: .destructive) { Task { await viewModel.delete(row.id) } }
        }
    }
}

/// An explicit search field (the system search bar failed the "Text clipped" audit): magnifier,
/// text-style font, a clear button, at least 44 pt tall.
struct PantrySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: OMPSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.primary)
                .accessibilityHidden(true)
            TextField(PantryCopy.search, text: $text)
                .font(OMPFont.body)
                .autocorrectionDisabled()
                .accessibilityLabel(PantryCopy.search)
                .accessibilityIdentifier(AccessibilityID.pantrySearch)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary)
                .ompMinimumHitTarget()
                .accessibilityLabel(PantryCopy.clearSearch)
                .accessibilityIdentifier(AccessibilityID.pantrySearchClear)
            }
        }
        .padding(.horizontal, OMPSpacing.medium)
        .frame(minHeight: OMPMetrics.minimumHitTarget)
        .ompCardBackground()
    }
}
