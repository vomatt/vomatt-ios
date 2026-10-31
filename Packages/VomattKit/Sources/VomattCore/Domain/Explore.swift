import Foundation

/// The query Explore sends, from the web's `toExploreQuery`: ended Polls take no sort, and a search
/// under `searchMinLength` is no search. Equal for keystrokes that don't change what is asked.
public struct ExploreQuery: Hashable, Sendable {
    public var status: VomattService.ListStatus
    public var sort: VomattService.ListSort?
    public var q: String?
    /// A topic's slug.
    public var tag: String?

    public init(query: String, status: VomattService.ListStatus, sort: VomattService.ListSort, tag: String? = nil) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.status = status
        self.sort = status == .open ? sort : nil
        self.q = q.count >= searchMinLength ? q : nil
        self.tag = tag
    }
}

/// Explore's topic row, from the web's `topicsFor` and `TopicPills`.
public enum ExploreTopics {
    /// Divisible by 2 and 3, so full pages fill the grid's rows.
    public static let pageSize = 24
    static let limit = 8

    /// The topics to offer from `topics` (most used first): those whose name or slug contains the
    /// search, or the most used ones without a search. `q` is already trimmed and long enough, or nil.
    public static func matching(_ topics: [Tag], q: String?) -> [Tag] {
        guard let needle = q?.lowercased() else { return Array(topics.prefix(limit)) }
        return Array(topics.filter { $0.name.lowercased().contains(needle) || $0.slug.contains(needle) }.prefix(limit))
    }

    /// The pills to show: the picked topic first, then the ones `matching` offers.
    public static func shown(_ topics: [Tag], q: String?, active slug: String?) -> [Tag] {
        let active = topics.first { $0.slug == slug }
        let rest = matching(topics, q: q).filter { $0 != active }
        return (active.map { [$0] } ?? []) + rest
    }
}
