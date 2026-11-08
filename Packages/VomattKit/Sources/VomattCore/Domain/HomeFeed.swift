/// The home feeds, in the order their pills show (the web's `features/polls/feeds.ts`).
/// Every one but For you needs sign-in.
public enum HomeFeed: String, CaseIterable, Sendable {
    case forYou, following, resultsIn, closingSoon
}
