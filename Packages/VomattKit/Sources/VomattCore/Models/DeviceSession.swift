import Foundation

/// A device the signed-in user can still refresh a session on.
public struct DeviceSession: Identifiable, Equatable, Sendable {
    public let id: String
    /// The raw User-Agent of the latest sign-in or refresh; nil for a session from before devices
    /// were recorded that hasn't refreshed since.
    public var userAgent: String?
    public var createdAt: Date?
    /// Accurate to about 15 minutes.
    public var lastSeenAt: Date?
    /// The session making the request.
    public var isCurrent: Bool
    /// An admin console sign-in.
    public var isAdminScope: Bool

    public init(id: String, userAgent: String?, createdAt: Date?, lastSeenAt: Date?, isCurrent: Bool, isAdminScope: Bool) {
        self.id = id
        self.userAgent = userAgent
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.isCurrent = isCurrent
        self.isAdminScope = isAdminScope
    }

    /// nil when the User-Agent is missing or unrecognized: show "unknown device".
    public var deviceName: String? { userAgent.flatMap(DeviceName.init(userAgent:))?.text }
}

/// A readable "iPhone · Safari" from a raw User-Agent.
struct DeviceName: Equatable {
    var platform: String?
    var client: String?

    var text: String? {
        let parts = [platform, client].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    init?(userAgent: String) {
        // Order matters: iPads and iPhones also say "Mac OS X", Android says "Linux", Chrome says "Safari"
        let platforms = [
            ("iPhone", "iPhone"), ("iPad", "iPad"), ("Android", "Android"),
            ("Macintosh", "Mac"), ("Windows", "Windows"), ("CrOS", "ChromeOS"), ("Linux", "Linux"),
        ]
        let clients = [
            ("Edg", "Edge"), ("OPR", "Opera"), ("Firefox", "Firefox"), ("FxiOS", "Firefox"),
            ("CriOS", "Chrome"), ("Chrome", "Chrome"), ("Safari", "Safari"),
        ]
        platform = platforms.first { userAgent.contains($0.0) }?.1
        // The native app (URLSession's "Vomatt/1.0 CFNetwork/… Darwin/…") has no browser
        if userAgent.hasPrefix("Vomatt") {
            client = "Vomatt"
        } else {
            client = clients.first { userAgent.contains($0.0) }?.1
        }
        if platform == nil && client == nil { return nil }
    }
}
