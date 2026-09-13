import SwiftUI

struct SourceApplicationPicker: View {
    @Binding var bundleIdentifier: String
    var savedName: String?
    var emptyTitle = "Choose Application…"
    var onSelect: (InstalledApplication) -> Void = { _ in }
    @ObservedObject private var catalog = ApplicationCatalog.shared
    @State private var isPresented = false

    private var application: InstalledApplication? {
        catalog.applications.first { $0.id == bundleIdentifier }
    }

    var body: some View {
        Button { isPresented = true } label: {
            HStack(spacing: 8) {
                if let application {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                        .resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app.dashed").frame(width: 20, height: 20)
                }
                Text(bundleIdentifier.isEmpty ? emptyTitle : (application?.name ?? savedName ?? bundleIdentifier))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Source application")
        .help(bundleIdentifier.isEmpty ? "Search installed applications by name." : bundleIdentifier)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ApplicationSearchView(catalog: catalog) { app in
                bundleIdentifier = app.id
                onSelect(app)
                isPresented = false
            }
        }
        .onAppear { catalog.refresh() }
    }
}

private struct ApplicationSearchView: View {
    @ObservedObject var catalog: ApplicationCatalog
    let onSelect: (InstalledApplication) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    private var results: [InstalledApplication] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.applications.filter { $0.matches(search: query) }.sorted { lhs, rhs in
            let lhsNameMatches = lhs.name.localizedStandardContains(query)
            let rhsNameMatches = rhs.name.localizedStandardContains(query)
            if lhsNameMatches != rhsNameMatches { return lhsNameMatches }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose Application").font(.headline)
            TextField("Search applications…", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search applications")
                .focused($searchFocused)
                .onSubmit(chooseSelection)
                .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
            if results.isEmpty {
                ContentUnavailableView {
                    Label(catalog.isLoading ? "Finding applications…" : "No applications found", systemImage: "magnifyingglass")
                } description: {
                    Text("Search by application name or bundle identifier.")
                }
            } else {
                ScrollViewReader { proxy in
                    List(results, selection: $selectedID) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable().frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).lineLimit(1)
                                Text(app.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(app) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onSelect(app) }
                        .tag(app.id)
                        .id(app.id)
                    }
                    .listStyle(.inset)
                    .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                    .onKeyPress(.return) { chooseSelection(); return .handled }
                }
            }
            HStack {
                Text(results.count == 1 ? "1 application" : "\(results.count) applications")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Choose", action: chooseSelection).disabled(results.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 360, height: 380)
        .onAppear { searchFocused = true; catalog.refresh() }
        .onChange(of: search) { _, _ in selectedID = results.first?.id }
        .onExitCommand { dismiss() }
    }

    private func chooseSelection() {
        if let app = results.first(where: { $0.id == selectedID }) ?? results.first { onSelect(app) }
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (offset > 0 ? -1 : results.count)
        selectedID = results[min(max(current + offset, 0), results.count - 1)].id
    }
}
