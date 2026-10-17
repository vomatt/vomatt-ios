import Foundation

/// The API clamps `limit` to 1–50; clamp here too so callers can't ask for more.
public let maxPageSize = 50

public func clampedPageSize(_ limit: Int) -> Int32 {
    Int32(min(max(1, limit), maxPageSize))
}

/// Appends `next` to `previous`, dropping items whose id is already present (in either).
public func mergeById<Item: Identifiable>(_ previous: [Item], _ next: [Item]) -> [Item] {
    var seen = Set(previous.map(\.id))
    return previous + next.filter { seen.insert($0.id).inserted }
}

/// Reads pages from `cursor` until the last page, `until(items)` holds, or `maxPages` were read.
/// A non-nil `nextCursor` in the result means more pages remain.
public func collectPages<Item: Sendable>(
    from cursor: String? = nil,
    maxPages: Int,
    until: (([Item]) -> Bool)? = nil,
    // Runs on the caller's actor, so a main-actor caller can pass a main-actor closure
    isolation: isolated (any Actor)? = #isolation,
    fetchPage: (String?) async throws -> CursorPage<Item>
) async throws -> (page: CursorPage<Item>, pages: Int) {
    var items: [Item] = []
    var next = cursor
    var pages = 0
    while pages < maxPages {
        let page = try await fetchPage(next)
        items += page.items
        next = page.nextCursor
        pages += 1
        if next == nil || until?(items) == true { break }
    }
    return (CursorPage(items: items, nextCursor: next), pages)
}
