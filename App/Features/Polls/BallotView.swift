import SwiftUI
import VomattCore

/// Card states A (no Ballot), B (has Ballot) and C (Scheduled). Never shows counts.
struct BallotView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let poll: Poll
    let status: PollStatus
    @Bindable var ballot: BallotModel
    let onPollChanged: (Poll) -> Void
    let onPollEnded: () async -> Void

    /// What the viewer is doing with a cast Ballot (the web's `SealedMode`). Without a Ballot the Vote row shows instead.
    enum SealedMode: Equatable {
        case sealed
        /// Choosing an option to replace `from`
        case updating(from: String)
    }

    /// The action row's states that swap in place (the web's `PANES`). They share one cell, so the card is as tall in each.
    private enum Stage: Hashable, CaseIterable { case vote, sealed, updating }

    @State private var mode = SealedMode.sealed
    /// An alert over the page, not a mode: the Seal stays put under it, so the card keeps its height
    @State private var confirmingWithdraw = false
    /// Counts casts saved here; each one pops the SealMark in
    @State private var casts = 0
    @State private var shake = 0
    @Namespace private var selection

    private var isScheduled: Bool { status == .scheduled }
    private var stage: Stage {
        // A first vote in flight already has a Ballot; its Vote button stays (busy) until it is in
        if ballot.myOptionId == nil || ballot.pendingAction == .vote { return .vote }
        return mode == .sealed ? .sealed : .updating
    }

    /// Signed out there is no Ballot to hide; on some Polls nobody else sees the voter list, so nothing to hide from.
    private var anonymous: Bool? {
        guard app.isSignedIn, !isScheduled, poll.canHideName(viewerId: app.userId) else { return nil }
        return ballot.anonymous(accountDefault: app.me?.anonymousBallotByDefault)
    }

    /// A pick waits on Vote or Update vote; that row stays on screen until it is pressed.
    private var awaitsConfirm: Bool { (stage == .vote && ballot.selected != nil) || stage == .updating }

    /// What the vote does: who sees the choice once the poll ends, or that it is counted unnamed.
    private func nameStatus(hidden: Bool) -> String {
        hidden ? app.t("poll.anonymousHidden") : poll.visibilityLevel.map { app.t("poll.visibility.\($0.rawValue)", ["name": poll.creatorName]) } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                ForEach(poll.options) { option in optionRow(option) }
            }
            .modifier(ShakeEffect(shakes: CGFloat(reduceMotion ? 0 : shake)))
            .animation(.linear(duration: 0.4), value: shake)
            .disabled(isScheduled || ballot.isPending)
            .accessibilityElement(children: .contain)
            // A short name: the question is the heading right above
            .accessibilityLabel(app.t("poll.options"))

            if isScheduled {
                Text(app.t("poll.opensHint", ["distance": app.dates.fromNow(poll.startTime)]))
                    .font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    .frame(minHeight: Metrics.minTarget)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .overlay(alignment: .top) { Hairline() }
            } else {
                // The name line rides in the confirm row too, so it stays in view while Vote does
                VStack(alignment: .leading, spacing: 12) {
                    // One line through voting, changing and withdrawing, so it never moves. Before a vote the
                    // choice rides along with it; after, it applies at once
                    if let anonymous {
                        nameLine(hidden: anonymous, status: nameStatus(hidden: anonymous))
                            .foregroundStyle(Tokens.mutedForeground)
                            .padding(.top, -4)
                    }
                    // Each pane is centered in the cell under the divider, which holds still through every state
                    ZStack {
                        ForEach(Stage.allCases, id: \.self) { pane in
                            actions(pane)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .opacity(pane == stage ? 1 : 0)
                                .allowsHitTesting(pane == stage)
                                .accessibilityHidden(pane != stage)
                        }
                    }
                    .padding(.top, 16)
                    .overlay(alignment: .top) { Hairline() }
                }
                .modifier(FollowsTabBar(isOn: awaitsConfirm))
            }
        }
        .coordinateSpace(.named(FollowsTabBar.space))
        .animation(.easeOut(duration: 0.2), value: stage)
        .sensoryFeedback(.impact(weight: .light), trigger: ballot.myOptionId) { _, new in new != nil }
        .alert(app.t("poll.withdrawTitle"), isPresented: $confirmingWithdraw) {
            Button(app.t("poll.keep"), role: .cancel) {}
            Button(app.t("poll.withdraw"), role: .destructive) { withdraw() }
        } message: {
            Text(app.t("poll.withdrawBody"))
        }
    }

    private func optionRow(_ option: PollOption) -> some View {
        let isSelected = ballot.selected == option.id
        // Waits for the cast to land, so it never shows on a vote that rolls back
        let isCast = ballot.savedOptionId == option.id
        return Button {
            choose(option.id)
        } label: {
            HStack(spacing: 14) {
                BallotMark(chosen: isSelected ? option.id : nil, cast: isCast)
                Text(option.text)
                    .font(.vm(16, .medium))
                    .foregroundStyle(isScheduled ? Tokens.mutedForeground : Tokens.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                if isCast {
                    VotedStamp(label: app.t("poll.votedPill")).transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xl).fill(Tokens.card)
                    RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border)
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.xl).fill(Tokens.highlightTint)
                            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.chosenLine, lineWidth: 1.5))
                            .matchedGeometryEffect(id: "selection", in: selection)
                            .opacity(ballot.isPending ? 0.55 : 1)
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: ballot.selected)
            .animation(.easeOut(duration: 0.15), value: ballot.isPending)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.text)
        .accessibilityIdentifier("ballot-option")
        .accessibilityValue(isCast ? app.t("poll.yourVote") : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Where the viewer's name stands on the voter list, with the one action that flips it (the web's `NameLine`).
    private func nameLine(hidden: Bool, status: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .font(.system(size: 14)).foregroundStyle(Tokens.tide).frame(width: 18)
                .accessibilityHidden(true)
            Text(status).font(.vmMeta).frame(maxWidth: .infinity, alignment: .leading)
            Button(app.t(hidden ? "poll.showMyName" : "poll.hideMyName")) { setAnonymous(!hidden) }
                .buttonStyle(.vm(.ghost, size: .sm))
                .fixedSize()
                .disabled(ballot.isPending)
        }
    }

    @ViewBuilder private func actions(_ pane: Stage) -> some View {
        switch pane {
        case .vote:
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text(app.t("poll.revealHint"))
                } icon: {
                    Image(systemName: "lock").font(.system(size: 15, weight: .medium)).foregroundStyle(Tokens.tide)
                }
                .font(.vm(14))
                .foregroundStyle(Tokens.tideForeground)
                Button(action: castSelected) {
                    HStack(spacing: 8) {
                        if ballot.pendingAction == .vote { BallotBoxIcon().frame(width: 16, height: 16) }
                        Text(app.t("poll.vote"))
                    }
                }
                .buttonStyle(.vm(.default, size: .lg, fullWidth: true))
                .disabled(ballot.isPending || ballot.selected == nil)
            }
        case .sealed:
            seal
        case .updating:
            updating
        }
    }

    /// What a cast Ballot becomes: the Seal, saying when the results open, with the vote's actions.
    /// Two lines, no more: every line the Seal has is room an unvoted card keeps empty above its divider.
    private var seal: some View {
        let lines = VStack(alignment: .leading, spacing: 2) {
            Text(poll.revealTime.map { app.t("poll.sealed", ["date": app.dates.pollMoment($0)]) } ?? app.t("poll.sealedNoEnd"))
                .font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
            Text(app.t("poll.changeHint")).font(.vmMeta)
        }
        // The negative padding keeps the 44pt target off the lines
        let withdraw = Button { confirmingWithdraw = true } label: {
            Text(app.t("poll.withdrawVote")).foregroundStyle(Tokens.tideForeground)
        }
        .buttonStyle(.vm(.ghost, size: .sm))
        .disabled(ballot.isPending)
        .padding(.vertical, -8)
        return ViewThatFits(in: .horizontal) {
            // A column of its own, so no line of text runs up against it
            HStack(spacing: 16) {
                sealMark(size: 40)
                lines
                Spacer(minLength: 0)
                withdraw
            }
            // Phones have no room for one: there it sits under the text
            HStack(spacing: 12) {
                sealMark(size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    lines
                    withdraw.padding(.leading, -12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .tidePanel()
        .accessibilityElement(children: .contain)
    }

    private func sealMark(size: CGFloat) -> some View {
        SealMark(size: size)
            .keyframeAnimator(initialValue: 1.0, trigger: casts) { mark, scale in
                mark.scaleEffect(scale)
            } keyframes: { _ in
                MoveKeyframe(reduceMotion ? 1 : 0.4)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
            }
    }

    private var updating: some View {
        // What an Update would replace: the vote being changed, or the current one
        let replacing = if case let .updating(from) = mode { from } else { ballot.myOptionId }
        let previous = poll.options.first { $0.id == replacing }?.text ?? ""
        let longest = poll.options.map(\.text).max { $0.count < $1.count } ?? ""
        return VStack(alignment: .leading, spacing: 14) {
            Label {
                // Sized by the longest option: a line that grew with the option would make the card taller
                // once it is the vote
                ZStack(alignment: .topLeading) {
                    Text(app.t("poll.updatingHint", ["option": previous]))
                    Text(app.t("poll.updatingHint", ["option": longest])).hidden()
                }
            } icon: {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 15)).foregroundStyle(Tokens.input)
            }
            .font(.vm(14))
            .foregroundStyle(Tokens.mutedForeground)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button { cancelUpdate() } label: {
                    Text(app.t("common.cancel")).foregroundStyle(Tokens.mutedForeground)
                }
                .buttonStyle(.vm(.ghost))
                .disabled(ballot.isPending)
                Button(action: castSelected) {
                    HStack(spacing: 8) {
                        if ballot.pendingAction == .update { BallotBoxIcon().frame(width: 16, height: 16) }
                        Text(app.t("poll.updateVote"))
                    }
                    .frame(minWidth: 108)
                }
                .buttonStyle(.vm(.default))
                .disabled(ballot.isPending || ballot.selected == nil || ballot.selected == replacing)
            }
        }
    }

    private func choose(_ optionId: String) {
        ballot.selected = optionId
        // Picking another option after voting starts replacing the vote
        if let mine = ballot.myOptionId, optionId != mine, stage != .updating {
            mode = .updating(from: mine)
        }
    }

    private func cancelUpdate() {
        ballot.selected = ballot.myOptionId
        mode = .sealed
    }

    private func castSelected() {
        guard let selected = ballot.selected else { return }
        app.requireAuth {
            Task {
                let outcome = await ballot.cast(selected, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
                if outcome == .saved {
                    mode = .sealed
                    casts += 1
                    announce(app.t(ballot.replacedBallot ? "poll.voteUpdated" : "poll.voteCast"))
                }
                if outcome == .failed { shake += 1 }
            }
        }
    }

    private func setAnonymous(_ value: Bool) {
        Task {
            let outcome = await ballot.setAnonymous(value, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
            if outcome == .saved { announce(nameStatus(hidden: value)) }
            if outcome == .failed { shake += 1 }
        }
    }

    private func withdraw() {
        mode = .sealed
        Task {
            let outcome = await ballot.retract(app: app, onPollEnded: onPollEnded)
            if outcome == .saved { announce(app.t("poll.voteWithdrawn")) }
            if outcome == .failed { shake += 1 }
        }
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}

/// Holds the confirm row at the bottom of the scroll view while the rest of the Ballot is on screen (the web's
/// `follow-tabbar`), so a pick never leaves Vote off-screen. It lets go once the Ballot scrolls past. Card-colored
/// to the card's edges; the bottom padding reaches into the card's own padding, so nothing moves.
private struct FollowsTabBar: ViewModifier {
    nonisolated static let space = "ballot"
    let isOn: Bool
    @State private var isStuck = false

    func body(content: Content) -> some View {
        content
            .padding(.bottom, 12)
            .background {
                Tokens.card
                    .padding(.horizontal, -20)
                    .overlay(alignment: .top) {
                        // Once stuck, fades into the options scrolling under it
                        LinearGradient(colors: [Tokens.card.opacity(0), Tokens.card], startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                            .offset(y: -24)
                            .opacity(isStuck ? 1 : 0)
                    }
            }
            .visualEffect { [isOn] content, proxy in content.offset(y: -Self.lift(proxy, isOn: isOn)) }
            .onGeometryChange(for: Bool.self) { [isOn] proxy in Self.lift(proxy, isOn: isOn) > 0 } action: { isStuck = $0 }
            .padding(.bottom, -12)
    }

    /// How far the row rises: up to the bottom of the visible scroll area, but never above the Ballot's top.
    nonisolated private static func lift(_ proxy: GeometryProxy, isOn: Bool) -> CGFloat {
        guard isOn, let visible = proxy.bounds(of: .scrollView) else { return 0 }
        let below = proxy.size.height - visible.maxY
        let room = proxy.frame(in: .named(space)).minY
        return max(0, min(below, room))
    }
}

/// The options recoil when a request is rolled back.
nonisolated struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(shakes * .pi * 4), y: 0))
    }
}

/// The 22pt radio mark (the web's `BallotMark`): a 2pt `input` ring at rest; once chosen, the red ballot stamp.
struct BallotMark: View {
    /// The chosen option's id, which seeds its stamp's angle; nil draws the empty ring.
    let chosen: String?
    /// The chosen option is the cast vote. One already cast when the mark appears is drawn still.
    var cast = false

    init(chosen: String?, cast: Bool = false) {
        self.chosen = chosen
        self.cast = cast
    }

    /// The empty ring, for options nobody can pick yet (the creator's review).
    init(checked: Bool) {
        self.init(chosen: checked ? "" : nil)
    }

    var body: some View {
        ZStack {
            if let chosen {
                PressedStamp(seed: chosen, pressed: !cast)
            } else {
                Circle().fill(Tokens.card).overlay(Circle().strokeBorder(Tokens.input, lineWidth: 2))
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// The angle each option was last pressed at this session, so a cast stamp redrawn after Cancel or on another
/// screen keeps it.
private var pressedAngles: [String: Double] = [:]

/// The ballot stamp at its own angle, picked once when it appears so it holds through the cast. A press lands at a
/// random angle and springs in; a vote already cast is drawn still, at the angle it was pressed at this session or
/// else one taken from `seed` (the web's `PressedStamp`).
private struct PressedStamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let seed: String
    @State private var angle: Double
    @State private var landed: Bool

    init(seed: String, pressed: Bool) {
        self.seed = seed
        _angle = State(initialValue: pressedAngles[seed] ?? StampAngle.seeded(seed))
        _landed = State(initialValue: !pressed)
    }

    var body: some View {
        ElectedStampShape()
            .stroke(Tokens.elected, lineWidth: 22 * 9.5 / 130)
            .rotationEffect(.degrees(angle))
            .scaleEffect(landed || reduceMotion ? 1 : 1.4)
            .opacity(landed ? 1 : 0)
            .onAppear {
                // Once per press: a stamp that scrolls back into view stays where it landed
                guard !landed else { return }
                angle = StampAngle.angle(Double.random(in: 0..<1))
                pressedAngles[seed] = angle
                // Critically damped, so it settles without overshoot
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 520, damping: 46)) { landed = true }
            }
    }
}

/// The check path of the web's `BallotMark` (viewBox 0 0 16 16).
nonisolated struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 16
        var path = Path()
        path.move(to: CGPoint(x: 3 * scale, y: 8.5 * scale))
        path.addLine(to: CGPoint(x: 6.5 * scale, y: 12 * scale))
        path.addLine(to: CGPoint(x: 13 * scale, y: 4.5 * scale))
        return path
    }
}

/// Marks the option the viewer voted for: a Volt pill whose check draws in.
struct VotedStamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String
    @State private var drawn = false

    var body: some View {
        HStack(spacing: 4) {
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
            Text(label).font(.vm(11, .medium, relativeTo: .caption2))
        }
        // Volt stays light in dark mode, so its ink stays dark
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(Tokens.highlight, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.2)))
        .fixedSize()
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.1)) { drawn = true } }
    }
}

/// A ballot box (the web's `BallotBoxIcon`), with the ballot sliding into the slot once.
struct BallotBoxIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropped = false

    var body: some View {
        Canvas { context, size in
            let unit = size.width / 24
            var box = Path(roundedRect: CGRect(x: 3.5 * unit, y: 11 * unit, width: 17 * unit, height: 9.5 * unit), cornerRadius: 1.8 * unit)
            context.stroke(box, with: .foreground, lineWidth: 1.6 * unit)
            box = Path()
            box.move(to: CGPoint(x: 8 * unit, y: 11 * unit))
            box.addLine(to: CGPoint(x: 16 * unit, y: 11 * unit))
            context.stroke(box, with: .foreground, style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
        }
        .overlay(alignment: .top) {
            GeometryReader { proxy in
                let unit = proxy.size.width / 24
                RoundedRectangle(cornerRadius: unit)
                    .fill(.foreground.opacity(0.35))
                    .frame(width: 8 * unit, height: 9 * unit)
                    .offset(x: 8 * unit, y: (dropped ? 12 : -2) * unit)
                    .frame(width: proxy.size.width, height: 12 * unit, alignment: .topLeading)
                    .clipped()
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .timingCurve(0.5, 0, 0.75, 0, duration: 0.55).delay(0.1)) { dropped = true } }
        .accessibilityHidden(true)
    }
}
