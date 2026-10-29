import SwiftUI
import VomattCore

/// A screen's empty or missing state (the web's `EmptyCard`, drawn flat as on iOS): an icon disc,
/// a title, one line of body and an optional action.
struct EmptyCard<Action: View>: View {
    var systemImage = "minus.circle"
    let title: String
    var message: String?
    @ViewBuilder var action: () -> Action

    init(systemImage: String = "minus.circle", title: String, body: String? = nil, @ViewBuilder action: @escaping () -> Action) {
        self.systemImage = systemImage
        self.title = title
        self.message = body
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(Tokens.foreground)
                .frame(width: 64, height: 64)
                .background(Tokens.field, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.vm(20, .medium, relativeTo: .title3))
                .foregroundStyle(Tokens.foreground)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            if let message {
                Text(message).font(.vmBody).foregroundStyle(Tokens.mutedForeground)
            }
            action().padding(.top, 10)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 56)
    }
}

extension EmptyCard where Action == EmptyView {
    init(systemImage: String = "minus.circle", title: String, body: String? = nil) {
        self.init(systemImage: systemImage, title: title, body: body) { EmptyView() }
    }
}

/// A Poll card's status (`StatusChip onCard`): one taking votes is the pink tint without a mark;
/// Scheduled and Ended carry an ink dot. The words always say the state.
struct CardStatusChip: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    let status: PollStatus
    var now: Date = .now

    var body: some View {
        let label = PollTiming(startTime: poll.startTime, endTime: poll.endTime, status: status, now: now, t: app.t, dates: app.dates).chip
        HStack(spacing: 5) {
            if status == .scheduled || status == .ended {
                Circle().fill(Tokens.foreground).frame(width: 6, height: 6).accessibilityHidden(true)
            }
            Text(label.uppercased())
        }
        .cardChip(tint: tint)
    }

    private var tint: Color {
        switch status {
        case .scheduled: Tokens.statusScheduled
        case .open, .closing: Tokens.statusOpenEnds
        case .ended: Tokens.statusEnded
        }
    }
}

/// "Voted" beside the status on a Poll the viewer holds a Ballot in: Volt, the viewer's own choice.
struct VotedPill: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).accessibilityHidden(true)
            Text(app.t("poll.votedPill").uppercased())
        }
        .cardChip(tint: Tokens.highlight, foreground: Tokens.highlightForeground)
    }
}

private extension View {
    /// `chipClassName` at a card's 10pt.
    func cardChip(tint: Color, foreground: Color = Tokens.foreground) -> some View {
        font(.vm(10, .semibold, relativeTo: .caption2))
            .tracking(0.5)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .fixedSize()
    }
}

/// What vomatt guarantees, as a list on the Tide surface (the web's `TideRules`); each rule leads with its icon.
struct TideRules<Header: View>: View {
    let rules: [(systemImage: String, text: String)]
    @ViewBuilder var header: () -> Header

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header()
            ForEach(rules, id: \.text) { rule in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: rule.systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Tokens.tide)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    Text(rule.text).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.vm(14))
        .lineSpacing(3)
        .foregroundStyle(Tokens.tideForeground)
        .padding(16)
        .background(Tokens.tideTint, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.tideLine))
    }
}

extension TideRules where Header == EmptyView {
    init(rules: [(systemImage: String, text: String)]) {
        self.init(rules: rules) { EmptyView() }
    }
}
