import SwiftUI
import VomattCore

/// Card states A (no Ballot), B (has Ballot) and C (Scheduled). Never shows counts.
struct BallotView: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    let status: PollStatus
    @Bindable var ballot: BallotModel
    let onPollChanged: (Poll) -> Void
    let onPollEnded: () async -> Void

    @State private var confirmingWithdraw = false
    @State private var shake = 0
    @Namespace private var selection

    private var isScheduled: Bool { status == .scheduled }
    private var hasBallot: Bool { ballot.myOptionId != nil }
    private var visibilityHint: String? { poll.visibilityLevel.map { app.t("poll.visibility.\($0.rawValue)") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                ForEach(poll.options) { option in optionRow(option) }
            }
            .modifier(ShakeEffect(shakes: CGFloat(shake)))
            .animation(.linear(duration: 0.4), value: shake)
            .disabled(isScheduled || ballot.isPending)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(poll.title)

            if hasBallot, let anonymous = ballot.anonymous, poll.allowsAnonymousBallot {
                Toggle(app.t("poll.anonymousToggle"), isOn: Binding(get: { anonymous }, set: { value in setAnonymous(value) }))
                    .font(.vmMeta)
                    .foregroundStyle(Tokens.mutedForeground)
                    .tint(Tokens.primary)
                    .frame(minHeight: 44)
                    .disabled(ballot.isPending)
            }

            if !hasBallot, !isScheduled, let visibilityHint {
                Text(visibilityHint).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }

            if hasBallot, let endTime = poll.endTime {
                sealedNotice(endTime).transition(.move(edge: .top).combined(with: .opacity))
            }

            actions
        }
        .animation(.easeOut(duration: 0.25), value: hasBallot)
        .sensoryFeedback(.impact(weight: .light), trigger: ballot.myOptionId) { _, new in new != nil }
    }

    private func optionRow(_ option: PollOption) -> some View {
        let isSelected = ballot.selected == option.id
        let isMine = ballot.myOptionId == option.id
        let dimmed = (hasBallot && !isSelected) || isScheduled
        return Button {
            ballot.selected = option.id
        } label: {
            HStack(spacing: 12) {
                BallotMark(checked: isSelected)
                Text(option.text)
                    .font(.vm(16, isSelected ? .medium : .regular))
                    .foregroundStyle(dimmed ? Tokens.mutedForeground : Tokens.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                if isMine {
                    VotedStamp(label: app.t("poll.stamp")).transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.xl).fill(Tokens.card)
                    RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border)
                    if isSelected {
                        RoundedRectangle(cornerRadius: Radius.xl).fill(Tokens.voltTint)
                            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.primary, lineWidth: 1.5))
                            .matchedGeometryEffect(id: "selection", in: selection)
                            .phaseAnimator([1, 0.45], trigger: ballot.isPending) { view, opacity in
                                view.opacity(ballot.isPending ? opacity : 1)
                            }
                    }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: ballot.selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.text)
        .accessibilityIdentifier("ballot-option")
        .accessibilityValue(isMine ? app.t("poll.yourVote") : "")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func sealedNotice(_ endTime: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            BallotBoxIcon().frame(width: 20, height: 20).foregroundStyle(Tokens.foreground).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.t("poll.sealed", ["date": app.dates.pollDate(endTime)]))
                if let visibilityHint { Text(visibilityHint) }
            }
        }
        .font(.vmMeta)
        .foregroundStyle(Tokens.mutedForeground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Tokens.surfaceSoft, in: RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Tokens.border))
    }

    @ViewBuilder private var actions: some View {
        if isScheduled {
            Text(app.t("poll.opensHint", ["distance": app.dates.fromNow(poll.startTime)]))
                .font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
        } else if confirmingWithdraw {
            ViewThatFits {
                HStack { withdrawConfirmText; Spacer(); withdrawConfirmButtons }
                VStack(alignment: .leading, spacing: 8) { withdrawConfirmText; withdrawConfirmButtons }
            }
        } else if hasBallot {
            HStack {
                Button(app.t("poll.withdrawVote")) { confirmingWithdraw = true }
                    .buttonStyle(.vm(.ghost, size: .sm))
                    .foregroundStyle(Tokens.mutedForeground)
                    .disabled(ballot.isPending)
                Spacer()
                Button {
                    cast()
                } label: {
                    HStack(spacing: 6) {
                        if ballot.isPending { BallotBoxIcon().frame(width: 16, height: 16) }
                        Text(app.t("poll.updateVote"))
                    }
                }
                .buttonStyle(.vm(.outline, size: .sm))
                .disabled(ballot.isPending || ballot.selected == nil || ballot.selected == ballot.myOptionId)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(app.t("poll.revealHint")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                Button {
                    cast()
                } label: {
                    HStack(spacing: 8) {
                        if ballot.isPending { BallotBoxIcon().frame(width: 16, height: 16) }
                        Text(app.t("poll.vote"))
                    }
                }
                .buttonStyle(.vm(.default, fullWidth: true))
                .disabled(ballot.isPending || ballot.selected == nil)
            }
        }
    }

    private var withdrawConfirmText: some View {
        Text(app.t("poll.withdrawConfirm")).font(.vmMeta).foregroundStyle(Tokens.foreground)
    }

    private var withdrawConfirmButtons: some View {
        HStack(spacing: 6) {
            Button(app.t("poll.keep")) { confirmingWithdraw = false }.buttonStyle(.vm(.ghost, size: .sm))
            Button(app.t("poll.withdraw")) { withdraw() }.buttonStyle(.vm(.destructive, size: .sm))
        }
    }

    private func cast() {
        guard let selected = ballot.selected else { return }
        app.requireAuth {
            Task {
                let outcome = await ballot.cast(selected, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
                if outcome == .saved { app.showToast(app.t("poll.voteCast")) }
                if outcome == .failed { shake += 1 }
            }
        }
    }

    private func setAnonymous(_ value: Bool) {
        Task {
            guard let optionId = ballot.myOptionId else { return }
            let outcome = await ballot.cast(optionId, anonymous: value, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
            if outcome == .failed { shake += 1 }
        }
    }

    private func withdraw() {
        confirmingWithdraw = false
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

/// The square on a paper ballot; a check is drawn in when marked.
struct BallotMark: View {
    let checked: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(checked ? Tokens.primary : Tokens.card)
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(checked ? Tokens.primary : Tokens.input, lineWidth: 1.5)
            CheckShape()
                .trim(from: 0, to: checked ? 1 : 0)
                .stroke(Tokens.volt, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
        }
        .frame(width: 18, height: 18)
        .animation(.easeOut(duration: 0.22), value: checked)
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
        .background(Tokens.volt, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.2)))
        .fixedSize()
        .onAppear { withAnimation(.easeOut(duration: 0.25).delay(0.1)) { drawn = true } }
    }
}

/// A ballot box (the web's `BallotBoxIcon`), with the ballot sliding into the slot once.
struct BallotBoxIcon: View {
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
        .onAppear { withAnimation(.timingCurve(0.5, 0, 0.75, 0, duration: 0.55).delay(0.1)) { dropped = true } }
        .accessibilityHidden(true)
    }
}
