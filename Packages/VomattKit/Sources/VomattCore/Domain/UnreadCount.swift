/// The API stops counting unread at 100, meaning "100 or more" (vomatt-api #45).
public func formatUnreadCount(_ count: Int) -> String {
    count > 99 ? "99+" : String(count)
}
