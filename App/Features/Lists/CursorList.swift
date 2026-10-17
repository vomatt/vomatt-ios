import Observation
import SwiftUI
import VomattCore

/// A cursor-paged list (the web's `useCursorList`): the first page, more on demand,
/// duplicates dropped, failures kept apart from emptiness.
@Observable
final class CursorList<Item: Identifiable & Sendable> {
    enum Phase { case idle, loading, loaded, failed }

    private(set) var items: [Item] = []
    private(set) var nextCursor: String?
    private(set) var phase = Phase.idle
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailed = false
    @ObservationIgnored private let fetch: (String?) async throws -> CursorPage<Item>
    @ObservationIgnored private var generation = 0

    init(fetch: @escaping (String?) async throws -> CursorPage<Item>) {
        self.fetch = fetch
    }

    var hasMore: Bool { nextCursor != nil }

    /// Loads the first page again. Keeps what's shown while it loads.
    func reload() async {
        generation += 1
        let current = generation
        if items.isEmpty { phase = .loading }
        do {
            let page = try await fetch(nil)
            guard current == generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            phase = .loaded
            loadMoreFailed = false
        } catch {
            guard current == generation, !(error is CancellationError) else { return }
            if items.isEmpty { phase = .failed }
        }
    }

    func loadMore() async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        let current = generation
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await fetch(cursor)
            guard current == generation else { return }
            items = mergeById(items, page.items)
            nextCursor = page.nextCursor
        } catch {
            loadMoreFailed = true
        }
    }

    func update(_ change: (inout [Item]) -> Void) {
        change(&items)
    }
}

/// "Load more" at the end of a list; it also loads as soon as it scrolls into view.
struct LoadMoreFooter<Item: Identifiable & Sendable>: View {
    @Environment(AppModel.self) private var app
    let list: CursorList<Item>

    var body: some View {
        if list.hasMore {
            Group {
                if list.isLoadingMore {
                    ProgressView()
                } else {
                    Button(list.loadMoreFailed ? app.t("comments.retry") : app.t("common.loadMore")) {
                        Task { await list.loadMore() }
                    }
                    .buttonStyle(.vm(.outline))
                    .frame(minWidth: 128)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .onAppear {
                if !list.loadMoreFailed { Task { await list.loadMore() } }
            }
        }
    }
}
