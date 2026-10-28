import SwiftUI
import VomattCore

/// A small uppercase pill (`chipClassName`); pair it with a tint.
struct Chip: View {
    let text: String
    var tint: Color = Tokens.secondary
    var bordered = false

    var body: some View {
        Text(text.uppercased())
            .font(.vm(11, .semibold, relativeTo: .caption2))
            .tracking(0.55)
            .lineLimit(1)
            .foregroundStyle(Tokens.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .overlay(Capsule().strokeBorder(Tokens.foreground.opacity(bordered ? 0.2 : 0), lineWidth: 1))
            .fixedSize()
    }
}

/// The status of a Poll, always as text on its tint (`StatusChip`).
struct StatusChip: View {
    @Environment(AppModel.self) private var app
    let status: PollStatus
    let startTime: Date
    let endTime: Date?

    init(poll: Poll, now: Date = .now) {
        self.status = poll.status(at: now)
        self.startTime = poll.startTime
        self.endTime = poll.endTime
    }

    init(status: PollStatus, startTime: Date, endTime: Date?) {
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
    }

    var body: some View {
        if let label {
            Chip(text: label, tint: tint)
        }
    }

    private var tint: Color {
        switch status {
        case .scheduled: Tokens.statusScheduled
        case .open: Tokens.statusOpen
        case .closing: Tokens.statusClosing
        case .ended: Tokens.statusEnded
        }
    }

    private var label: String? {
        let t = app.t
        switch status {
        case .scheduled:
            return t("poll.chipOpens", ["date": app.dates.pollDate(startTime)])
        case .ended:
            return endTime.map { t("poll.chipEnded", ["date": app.dates.pollDate($0)]) } ?? t("poll.chipEndedShort")
        case .closing:
            return endTime.map { t("poll.chipEndsIn", ["distance": app.dates.fromNow($0)]) }
        case .open:
            return endTime.map { t("poll.chipEnds", ["date": app.dates.pollDate($0)]) }
        }
    }
}

/// The Alert dot that marks something unread (the web's `UnreadDot`).
struct UnreadDot: View {
    let label: String
    var body: some View {
        Circle()
            .fill(Tokens.alert)
            .frame(width: 8, height: 8)
            .accessibilityLabel(label)
    }
}

/// The unread count: white digits on Alert red (the sidebar's count on the web). `ring` separates it
/// from an icon it overlaps, in the color of what is behind it.
struct UnreadBadge: View {
    let count: String
    let label: String
    var ring: Color? = nil
    var body: some View {
        Text(count)
            .font(.vmMono(11, medium: true, relativeTo: .caption2))
            .foregroundStyle(Tokens.alertForeground)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(minWidth: 18)
            .frame(height: 18)
            .background(Tokens.alert, in: Capsule())
            .overlay(Capsule().strokeBorder(ring ?? .clear, lineWidth: 2).padding(-2))
            .accessibilityLabel(label)
    }
}

/// The Seal: a Tide ring around a Volt check. The ring is vomatt's promise, the check is your vote.
struct SealMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().strokeBorder(Tokens.tide, lineWidth: 2)
            Circle().strokeBorder(Tokens.tide, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .padding(size * 0.1)
            Circle().fill(Tokens.highlight).frame(width: size * 0.42, height: size * 0.42)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.2, weight: .heavy))
                .foregroundStyle(Tokens.highlightForeground)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The `empty-state` utility: a dashed `surface-soft` box.
struct EmptyState<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .font(.vmBody)
            .foregroundStyle(Tokens.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .background(Tokens.surfaceSoft, in: RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// A loading placeholder with the web's shimmer, still under Reduce Motion.
struct Skeleton: View {
    /// nil fills the proposed height, e.g. as an overlay on hidden text.
    var height: CGFloat? = 16
    var width: CGFloat? = nil
    var radius: CGFloat = Radius.md
    /// false when a parent runs one shimmer over several bars (`PollRowSkeleton`).
    var shimmers = true

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Tokens.muted)
            .frame(width: width, height: height)
            .overlay {
                if shimmers { Shimmer().clipShape(RoundedRectangle(cornerRadius: radius)) }
            }
            .accessibilityHidden(true)
    }
}

/// The light sweep across a `Skeleton`; nothing under Reduce Motion.
private struct Shimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        if !reduceMotion {
            GeometryReader { proxy in
                LinearGradient(colors: [.clear, Tokens.foreground.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: phase * proxy.size.width)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
            }
        }
    }
}

/// A Poll card's shape while it loads.
struct PollCardSkeleton: View {
    var options = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Skeleton(height: 24, width: 24, radius: 12)
                Skeleton(height: 12, width: 120)
                Spacer()
                Skeleton(height: 18, width: 90, radius: 9)
            }
            Skeleton(height: 22, width: 240)
            ForEach(0..<options, id: \.self) { _ in Skeleton(height: 56, radius: Radius.xl) }
        }
        .card()
    }
}

/// A `PollRow` while it loads: the same chrome and text line heights (Dynamic Type included),
/// so the real rows land where the placeholders were.
struct PollRowSkeleton: View {
    var body: some View {
        // One shimmer for the row, masked to its bars
        bars.overlay { Shimmer() }.mask { bars }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .accessibilityHidden(true)
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: 6) {
            bar(Chip(text: "Ends"), width: 110, radius: 999)
            bar(Text(verbatim: "Title").font(.vm(17, relativeTo: .headline)), width: 240)
            bar(Text(verbatim: "Meta").font(.vmMeta), width: 90)
        }
    }

    /// A bar exactly as tall as `line` renders.
    private func bar(_ line: some View, width: CGFloat, radius: CGFloat = Radius.md) -> some View {
        line.hidden().frame(width: width, alignment: .leading)
            .overlay { Skeleton(height: nil, radius: radius, shimmers: false) }
    }
}

/// A person's bot in its tinted circle (`UserAvatar`).
struct AvatarView: View {
    let username: String
    let avatarUrl: String?
    var size: CGFloat = 32

    var body: some View {
        if Avatars.isNone(avatarUrl) {
            Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.25)
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Tokens.avatarStone, in: Circle())
                .accessibilityHidden(true)
        } else {
            let kind = Avatars.resolve(username: username, avatarUrl: avatarUrl)
            Image("bot-\(kind)")
                .resizable()
                .scaledToFit()
                .padding(size * 0.06)
                .frame(width: size, height: size)
                .background(tint(Avatars.tints[kind] ?? .stone), in: Circle())
                .clipShape(Circle())
                .accessibilityHidden(true)
        }
    }

    private func tint(_ tint: Avatars.Tint) -> Color {
        switch tint {
        case .sand: Tokens.avatarSand
        case .stone: Tokens.avatarStone
        case .green: Tokens.avatarGreen
        case .sky: Tokens.avatarSky
        case .peach: Tokens.avatarPeach
        case .lavender: Tokens.avatarLavender
        }
    }
}

/// Avatar and username as one unit, linking to the profile (`UserChip`).
struct UserChip: View {
    @Environment(AppModel.self) private var app
    let username: String
    let avatarUrl: String?
    var label: String?
    var avatarSize: CGFloat = 24
    var link = true

    var body: some View {
        let content = HStack(spacing: 6) {
            AvatarView(username: username, avatarUrl: avatarUrl, size: avatarSize)
            Text(label ?? username).lineLimit(1).truncationMode(.tail)
        }
        if link {
            Button { app.push(.profile(username)) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(label ?? username)
                .accessibilityHint(app.t("ios.openProfile"))
        } else {
            content
        }
    }
}

/// Underlined tabs (`TabsList variant="line"`).
struct LineTabs<Value: Hashable>: View {
    let items: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                let isActive = item.value == selection
                // Instant: tab switches are too frequent to animate
                Button { selection = item.value } label: {
                    Text(item.label)
                        .font(.vm(15, .medium))
                        .foregroundStyle(isActive ? Tokens.foreground : Tokens.foreground.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: Metrics.minTarget)
                        .overlay(alignment: .bottom) {
                            if isActive { Rectangle().fill(Tokens.foreground).frame(height: 2) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
            }
        }
        // Behind the tabs, so the active underline covers it
        .background(alignment: .bottom) { Rectangle().fill(Tokens.border).frame(height: 1) }
    }
}

/// A plain heading for a section.
struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.vm(16, .medium)).foregroundStyle(Tokens.foreground)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "Couldn't load" with a retry, used by every list.
struct LoadFailed: View {
    @Environment(AppModel.self) private var app
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message).font(.vmBody).foregroundStyle(Tokens.mutedForeground).multilineTextAlignment(.center)
            LoadingButton(style: .vm(.outline), action: retry) { Text(app.t("comments.retry")) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// The toast at the bottom of the screen (the web's sonner).
struct ToastView: View {
    let toast: Toast
    var body: some View {
        HStack(spacing: 8) {
            if toast.isError { Image(systemName: "exclamationmark.circle") }
            Text(toast.text).multilineTextAlignment(.leading)
        }
        .font(.vm(14, .medium))
        .foregroundStyle(toast.isError ? Tokens.destructive : Tokens.primaryForeground)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(toast.isError ? Tokens.card : Tokens.primary, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(toast.isError ? Tokens.border : .clear))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, Metrics.gutter)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Shows `app.toast` for a few seconds and announces it to VoiceOver.
    func toastHost(_ app: AppModel) -> some View {
        modifier(ToastHost(app: app))
    }
}

private struct ToastHost: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let app: AppModel

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = app.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 80)
                    .transition(.vmEnterExit(reduceMotion: reduceMotion))
                    .id(toast.id)
                    .task(id: toast.id) {
                        AccessibilityNotification.Announcement(toast.text).post()
                        try? await Task.sleep(for: .seconds(2.8))
                        withAnimation { if app.toast?.id == toast.id { app.toast = nil } }
                    }
                    .onTapGesture { withAnimation { app.toast = nil } }
            }
        }
        .animation(.spring(duration: 0.3), value: app.toast)
    }
}
