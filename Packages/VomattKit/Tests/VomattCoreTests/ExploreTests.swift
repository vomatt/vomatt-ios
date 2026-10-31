import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/app/explore-filter.test.ts`.
@Suite("Explore")
struct ExploreTests {
    @Test func sendsTheSortWithOpenPolls() {
        let query = ExploreQuery(query: "", status: .open, sort: .closing)
        #expect(query.status == .open && query.sort == .closing && query.q == nil && query.tag == nil)
    }

    @Test func dropsTheSortForEndedPollsWhichTheAPIRejects() {
        #expect(ExploreQuery(query: "", status: .ended, sort: .closing).sort == nil)
    }

    @Test func trimsTheSearchAndSkipsOneShorterThan2Characters() {
        #expect(ExploreQuery(query: "  side project ", status: .open, sort: .newest).q == "side project")
        #expect(ExploreQuery(query: " a ", status: .open, sort: .newest).q == nil)
        // Keystrokes that don't change what is asked don't refetch
        #expect(ExploreQuery(query: "a", status: .open, sort: .newest) == ExploreQuery(query: "", status: .open, sort: .newest))
    }

    @Test func sendsTheTopic() {
        #expect(ExploreQuery(query: "", status: .ended, sort: .newest, tag: "food").tag == "food")
    }

    private func tag(_ slug: String, _ name: String, _ usageCount: Int) -> VomattCore.Tag {
        VomattCore.Tag(id: slug, name: name, slug: slug, usageCount: usageCount)
    }

    // Most used first, as allTags() sends them
    private var topics: [VomattCore.Tag] { [tag("transport", "Transport", 9), tag("city", "城市", 5), tag("food", "Food", 3)] }

    @Test func offersTheFirstTopicsWithoutASearch() {
        #expect(ExploreTopics.matching(topics, q: nil).map(\.slug) == ["transport", "city", "food"])
    }

    @Test func matchesTheNameCaseInsensitivelyTheSlugAndCJKNames() {
        #expect(ExploreTopics.matching(topics, q: "FOO").map(\.slug) == ["food"])
        #expect(ExploreTopics.matching(topics, q: "city").map(\.slug) == ["city"])
        #expect(ExploreTopics.matching(topics, q: "城").map(\.slug) == ["city"])
    }

    @Test func offersNothingWhenNoTopicMatchesAndAtMost8() {
        #expect(ExploreTopics.matching(topics, q: "zzz").isEmpty)
        let many = (0..<12).map { tag("t\($0)", "T\($0)", $0) }
        #expect(ExploreTopics.matching(many, q: nil).count == 8)
    }

    // From ExploreView.test.tsx: the picked topic stays first while a search matches other topics
    @Test func keepsThePickedTopicFirst() {
        #expect(ExploreTopics.shown(topics, q: "foo", active: "city").map(\.slug) == ["city", "food"])
        #expect(ExploreTopics.shown(topics, q: nil, active: "food").map(\.slug) == ["food", "transport", "city"])
    }
}
