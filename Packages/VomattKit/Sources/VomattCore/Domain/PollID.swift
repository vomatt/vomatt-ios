import Foundation

/// The API serves only UUID poll ids. Signed out, it answers any other id with 401 instead of 404, so
/// a link with a malformed id is not-found before it reaches the API (the web's poll page `POLL_ID`).
public enum PollID {
    public static func isValid(_ id: String) -> Bool {
        id.wholeMatch(of: #/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/#.ignoresCase()) != nil
    }
}
