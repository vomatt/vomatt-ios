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
        /// The Seal in full, right after a cast here
        case moment
        /// The Seal folded to a row, on later visits
        case row
        /// Choosing an option to replace `from`
        case updating(from: String)
        case withdrawing
    }

    /// The action row's state; each fades in as it takes over.
    private enum Stage: Hashable { case scheduled, vote, moment, row, updating, withdrawing }

    @State private var mode = SealedMode.row
    @State private var shake = 0
    @Namespace private var selection

    private var isScheduled: Bool { status == .scheduled }
    private var stage: Stage {
        if isScheduled { return .scheduled }
        // A first vote in flight already has a Ballot; its Vote button stays (busy) until it is in
        if ballot.myOptionId == nil || ballot.pendingAction == .vote { return .vote }
        switch mode {
        case .moment: return .moment
        case .row: return .row
        case .updating: return .updating
        case .withdrawing: return .withdrawing
        }
    }

    /// Signed out there is no Ballot to hide; nobody sees a "nobody" Poll's voter list, so nothing to hide from.
    private var anonymous: Bool? {
        guard app.isSignedIn, !isScheduled, poll.allowsAnonymousBallot else { return nil }
        return ballot.anonymous(accountDefault: app.me?.anonymousBallotByDefault)
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
            .accessibilityLabel(poll.title)

            if let anonymous, [.vote, .moment, .row].contains(stage) { anonymityToggle(anonymous) }

            VStack {
                actions
                    .id(stage)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .overlay(alignment: .top) { Hairline() }
        }
        .animation(.easeOut(duration: 0.2), value: stage)
        .sensoryFeedback(.impact(weight: .light), trigger: ballot.myOptionId) { _, new in new != nil }
    }

    private func optionRow(_ option: PollOption) -> some View {
        let isSelected = ballot.selected == option.id
        let isMine = ballot.myOptionId == option.id
        let dimmed = (ballot.myOptionId != nil && !isSelected) || isScheduled
        return Button {
            choose(option.id)
        } label: {
            HStack(spacing: 14) {
                BallotMark(checked: isSelected)
                Text(option.text)
                    .font(.vm(16, .medium))
                    .foregroundStyle(dimmed ? Tokens.mutedForeground : Tokens.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                if isMine {
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
                            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.primary, lineWidth: 1.5))
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
        .accessibilityValue(isMine ? app.t("poll.yourVote") : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Before a vote the choice rides along with it; once cast it applies at once.
    private func anonymityToggle(_ anonymous: Bool) -> some View {
        Toggle(isOn: Binding(get: { anonymous }, set: { setAnonymous($0) })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.t("poll.anonymousToggle")).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
                Text(anonymous ? app.t("poll.anonymousHidden") : poll.visibilityLevel.map { app.t("poll.visibility.\($0.rawValue)") } ?? "")
                    .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
        }
        .tint(Tokens.primary)
        .frame(minHeight: Metrics.minTarget)
        .disabled(ballot.isPending)
    }

    @ViewBuilder private var actions: some View {
        switch stage {
        case .scheduled:
            Text(app.t("poll.opensHint", ["distance": app.dates.fromNow(poll.startTime)]))
                .font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                .frame(minHeight: Metrics.minTarget)
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
        case .moment, .row:
            seal(full: stage == .moment)
        case .updating:
            updating
        case .withdrawing:
            withdrawing
        }
    }

    /// What a cast Ballot becomes: the Seal, saying when the results open, with the vote's actions.
    /// In full once per cast here, then a row. Neither who sees the choice nor the turnout: those live elsewhere.
    private func seal(full: Bool) -> some View {
        let line = Text(poll.endTime.map { app.t("poll.sealed", ["date": app.dates.pollMoment($0)]) } ?? app.t("poll.sealedNoEnd"))
        let title = Text(app.t("poll.sealedTitle")).foregroundStyle(Tokens.foreground)
        return VStack(spacing: 14) {
            if full {
                VStack(spacing: 10) {
                    SealMark(size: 72).padding(.bottom, 4)
                    title.font(.vm(21, .medium, relativeTo: .title3)).tracking(-0.42)
                    line.font(.vm(14))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            } else {
                HStack(spacing: 12) {
                    SealMark(size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        title.font(.vm(14, .medium))
                        line.font(.vmMeta)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 6) {
                Button { mode = .withdrawing } label: {
                    Text(app.t("poll.withdrawVote")).foregroundStyle(Tokens.tideForeground)
                }
                .buttonStyle(.vm(.ghost, fullWidth: true))
                Button(app.t("poll.updateVote")) { startUpdate() }
                    .buttonStyle(.vm(.outline, fullWidth: true))
            }
            .disabled(ballot.isPending)
        }
        .padding(14)
        .tidePanel()
        .accessibilityElement(children: .contain)
    }

    private var updating: some View {
        let from = if case let .updating(from) = mode { from } else { "" }
        let previous = poll.options.first { $0.id == from }?.text ?? ""
        return VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(app.t("poll.updatingHint", ["option": previous]))
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
                .disabled(ballot.isPending || ballot.selected == nil || ballot.selected == from)
            }
        }
    }

    private var withdrawing: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.t("poll.withdrawTitle")).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
                Text(app.t("poll.withdrawBody")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button(app.t("poll.keep")) { mode = .row }.buttonStyle(.vm(.outline))
                Button(app.t("poll.withdraw")) { withdraw() }.buttonStyle(.vm(.destructive))
            }
        }
        .padding(.leading, 20).padding(.trailing, 14).padding(.vertical, 14)
        .background(Tokens.surfaceSoft, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
    }

    private func choose(_ optionId: String) {
        ballot.selected = optionId
        // Picking another option after voting starts replacing the vote
        if let mine = ballot.myOptionId, optionId != mine, stage != .updating {
            mode = .updating(from: mine)
        }
    }

    private func startUpdate() {
        guard let mine = ballot.myOptionId else { return }
        mode = .updating(from: mine)
    }

    private func cancelUpdate() {
        ballot.selected = ballot.myOptionId
        mode = .row
    }

    private func castSelected() {
        guard let selected = ballot.selected else { return }
        app.requireAuth {
            Task {
                let outcome = await ballot.cast(selected, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
                if outcome == .saved {
                    // The Seal replaces the "Vote cast." toast
                    mode = .moment
                    AccessibilityNotification.Announcement(app.t("poll.sealedTitle")).post()
                }
                if outcome == .failed { shake += 1 }
            }
        }
    }

    private func setAnonymous(_ value: Bool) {
        Task {
            let outcome = await ballot.setAnonymous(value, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
            if outcome == .failed { shake += 1 }
        }
    }

    private func withdraw() {
        mode = .row
        Task {
            if await ballot.retract(app: app, onPollEnded: onPollEnded) == .failed { shake += 1 }
        }
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

/// The 22pt radio circle (the web's `BallotMark`): a 2pt `input` ring at rest; once chosen, ink
/// around an 8pt Volt dot.
struct BallotMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let checked: Bool

    var body: some View {
        ZStack {
            if checked {
                Circle().fill(Tokens.primary)
                Circle().fill(Tokens.highlight).frame(width: 8, height: 8)
                    .transition(reduceMotion ? .opacity : .scale)
            } else {
                Circle().fill(Tokens.card).overlay(Circle().strokeBorder(Tokens.input, lineWidth: 2))
            }
        }
        .frame(width: 22, height: 22)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 1), value: checked)
        .accessibilityHidden(true)
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
            Text(label.uppercased()).font(.vm(11, .semibold, relativeTo: .caption2)).tracking(0.55)
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
