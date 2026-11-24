import SwiftUI
import VomattCore

/// Card state D: only for Ended Polls, and until `sealedUntil` passes it shows when the counts come out
/// instead, so it never asks for sealed data.
struct ResultsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let poll: Poll
    let myOptionId: String?
    let turnout: Int?
    /// From the card's status clock: when an Ended Poll's counts come out, while they are still sealed.
    let sealedUntil: Date?
    /// `/results` answered 403: the Poll is still sealed, so refetch it.
    let onSealed: () async -> Void
    /// Set when the viewer may see who voted.
    var onSelectOption: ((VotersSelection) -> Void)?
    /// The Poll ended while on screen: fill the bars and count up. A card that loads ended shows them still.
    var reveal = false

    @State private var fetched: PollResults?
    @State private var failed = false
    @State private var revealed = false

    private struct TaskKey: Hashable {
        let id: String
        let sealedUntil: Date?
    }

    private static let barDuration = 0.3
    private static let stagger = 0.05
    private static let barEase = Animation.timingCurve(0.23, 1, 0.32, 1, duration: barDuration)

    /// Bars and percentages at their final values: drawn still unless the Poll ended on screen.
    private var filled: Bool { revealed || !reveal || reduceMotion }

    private var rows: [ResultRow]? {
        poll.inlineResults ?? fetched?.options.map { ResultRow(id: $0.id, text: $0.text, votes: $0.voteCount) }
    }

    var body: some View {
        Group {
            if let sealedUntil {
                sealedUntilReveal(sealedUntil)
            } else if let rows {
                content(rows)
            } else if failed {
                Text(app.t("poll.resultsFailed")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            } else {
                VStack(spacing: 10) {
                    ForEach(poll.options) { _ in Skeleton(height: 56, radius: Radius.xl) }
                }
            }
        }
        // Runs again once the counts come out
        .task(id: TaskKey(id: poll.id, sealedUntil: sealedUntil)) { await loadIfNeeded() }
    }

    /// An Ended Poll whose counts stay sealed until its `revealAt`, for every viewer (the web's
    /// `SealedUntilReveal`); Turnout shows in the footer.
    private func sealedUntilReveal(_ date: Date) -> some View {
        HStack(spacing: 12) {
            // A Tide lock, not the SealMark: its Volt check means the viewer's own vote
            Image(systemName: "lock").font(.system(size: 15, weight: .medium)).foregroundStyle(Tokens.tide)
                .accessibilityHidden(true)
            Text(app.t("poll.sealedUntilReveal", ["date": app.dates.pollMoment(date)]))
                .font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 14)
        .tidePanel()
    }

    private func content(_ rows: [ResultRow]) -> some View {
        let participants = turnout ?? fetched?.totalParticipants ?? rows.reduce(0) { $0 + $1.votes }
        let winners = Results.winners(rows)
        return VStack(alignment: .leading, spacing: 10) {
            summary(rows, participants: participants)
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultRow(row, participants: participants, isWinner: winners.contains(row), delay: Double(index) * Self.stagger)
                }
            }
            if onSelectOption != nil, !winners.isEmpty {
                Text(app.t("poll.votersHint")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
        }
        .onAppear { revealed = true }
    }

    /// What the Poll decided and, for a voter, how their pick fared. Said in words; the Volt only marks a win.
    private func summary(_ rows: [ResultRow], participants: Int) -> some View {
        let decided = switch Results.summary(rows) {
        case let .won(option): app.t.count("poll.won", participants, ["option": option])
        case let .tie(options): app.t("poll.tie", ["options": options.joined(separator: app.t("poll.and"))])
        case .none: app.t("poll.noVotes")
        }
        let outcome = Results.outcome(of: myOptionId, in: rows)
        let won = outcome == .won
        let shape = RoundedRectangle(cornerRadius: 14)
        return HStack(spacing: 12) {
            if won {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Tokens.highlightForeground)
                    .frame(width: 32, height: 32)
                    .background(Tokens.highlight, in: Circle())
                    .overlay(Circle().strokeBorder(Tokens.foreground))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if let outcome {
                    Text(app.t("myPolls.outcome.\(outcome.rawValue)")).font(.vm(15, .semibold))
                    Text(decided).font(.vmMeta)
                } else {
                    Text(decided).font(.vm(15, .medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Tokens.foreground)
        .padding(14)
        .background(won ? Tokens.highlightTint : Tokens.surfaceSoft, in: shape)
        .overlay(shape.strokeBorder(won ? Tokens.foreground : Tokens.border))
        .accessibilityElement(children: .combine)
    }

    private func resultRow(_ row: ResultRow, participants: Int, isWinner: Bool, delay: Double) -> some View {
        let percent = Results.support(votes: row.votes, participants: participants)
        let shape = RoundedRectangle(cornerRadius: Radius.xl)
        let isMine = row.id == myOptionId
        let bar = reduceMotion || !reveal ? nil : Self.barEase.delay(delay)
        let label = HStack(spacing: 12) {
            if isWinner { ElectedStamp(label: app.t("poll.elected"), pressesIn: reveal) }
            Text(row.text)
                .font(.vm(16, isWinner ? .medium : .regular))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isMine {
                Text(app.t("poll.yourVoteShort"))
                    .font(.vm(11, .semibold))
                    .foregroundStyle(Tokens.highlightForeground)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Tokens.highlight, in: Capsule())
                    .overlay(Capsule().strokeBorder(Tokens.highlightForeground))
                    .fixedSize()
            }
            CountUpText(value: filled ? Double(percent) : 0)
                .animation(bar, value: revealed)
                .font(.vmMono(14))
                .foregroundStyle(isWinner ? Tokens.foreground : Tokens.mutedForeground)
        }
        .foregroundStyle(Tokens.foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        // One neutral for every bar: the winner is marked by its stamp, not its fill
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Tokens.muted)
                    .frame(width: proxy.size.width * (filled ? CGFloat(percent) / 100 : 0))
                    .animation(bar, value: revealed)
            }
        }
        .background(Tokens.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(isMine ? Tokens.chosenLine : Tokens.border, lineWidth: isMine ? 1.5 : 1))

        return Group {
            if let onSelectOption, row.votes > 0 {
                Button { onSelectOption(VotersSelection(option: row, participants: participants)) } label: { label.contentShape(shape) }
                    .buttonStyle(.plain)
                    .accessibilityHint(app.t("poll.voters"))
            } else {
                label
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel([row.text, isWinner ? app.t("poll.elected") : nil, isMine ? app.t("poll.yourVoteShort") : nil, "\(percent)%"]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func loadIfNeeded() async {
        guard sealedUntil == nil, poll.inlineResults == nil, fetched == nil else { return }
        do {
            fetched = try await app.service.results(pollId: poll.id)
        } catch let error as APIError where error.isSealed {
            // Still sealed means the card's status is wrong; refetch it
            failed = true
            await onSealed()
        } catch {
            failed = true
        }
    }
}

/// Counts up to `value` alongside its bar.
struct CountUpText: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))%").monospacedDigit()
    }
}

/// The red ballot stamp (a ring with a 卜 mark) on the winning option. When `pressesIn`, it is pressed down once its
/// bar fills; otherwise it is drawn still.
struct ElectedStamp: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: String
    var pressesIn = false
    @State private var pressed = false

    var body: some View {
        let still = pressed || !pressesIn || reduceMotion
        ElectedStampShape()
            .stroke(Tokens.elected, lineWidth: 18 * 9.5 / 130)
            .frame(width: 18, height: 18)
            .scaleEffect(still ? 1 : 1.6)
            .opacity(still ? 1 : 0)
            .onAppear {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.3).delay(0.3)) { pressed = true }
            }
            .accessibilityLabel(label)
    }
}

/// An option of an Ended Poll whose voters to list, with the Poll's Turnout: the total a list of everyone falls short of.
struct VotersSelection: Identifiable, Hashable {
    let option: ResultRow
    let participants: Int
    var id: String { option.id }
}

/// The stamp's ring and 卜 (viewBox 0 0 130 130).
nonisolated struct ElectedStampShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 130
        var path = Path()
        path.addEllipse(in: CGRect(x: 4.7 * s, y: 4.7 * s, width: 120.6 * s, height: 120.6 * s))
        path.move(to: CGPoint(x: 65 * s, y: 2 * s))
        path.addLine(to: CGPoint(x: 65 * s, y: 128 * s))
        path.move(to: CGPoint(x: 63.5 * s, y: 63.5 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 108 * s))
        return path
    }
}

/// Who chose one option, once the Poll has Ended (the web's `VotersDialog`).
struct VotersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pollId: String
    let selection: VotersSelection
    /// The viewer's option when their own Ballot is anonymous, so it is counted among the unlisted.
    let myAnonymousOptionId: String?
    private var option: ResultRow { selection.option }

    enum Phase { case loading, ready([Voter], capped: Bool), hidden, failed }
    @State private var state = Phase.loading
    /// 50 per page, so up to 1,000 voters.
    private let maxPages = 20

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .hidden:
                    message(app.t("poll.votersHidden"))
                case .failed:
                    LoadFailed(message: app.t("poll.votersFailed")) { await load() }
                case let .ready(voters, capped):
                    let list = VoterList(
                        voters: voters, optionId: option.id, votes: option.votes, participants: selection.participants,
                        complete: !capped, myAnonymousOptionId: myAnonymousOptionId
                    )
                    if list.listed.isEmpty, list.unlisted == 0, !capped {
                        message(app.t("poll.votersNone"))
                    } else {
                        List {
                            // Choices are withheld for everyone while an Anonymous Ballot is in the Poll
                            if list.choicesHidden {
                                Text(app.t("ios.votersChoicesHidden"))
                                    .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                                    .listRowBackground(Color.clear)
                            }
                            ForEach(list.listed) { voter in
                                Button {
                                    dismiss()
                                    app.push(.profile(voter.username))
                                } label: {
                                    UserChip(username: voter.username, avatarUrl: voter.avatarUrl, avatarSize: 32, link: false)
                                        .font(.vmBody)
                                        .foregroundStyle(Tokens.foreground)
                                }
                                .listRowBackground(Tokens.card)
                            }
                            if list.unlisted > 0 {
                                unlistedRow(list).listRowBackground(Tokens.card)
                            }
                            if capped {
                                Text(app.t("poll.votersTruncated", ["count": maxPages * maxPageSize]))
                                    .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .canvas()
            .navigationTitle(option.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(app.t("common.close")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    /// Anonymous Ballots and removed accounts: counted, never listed. Says when the viewer's own is among them.
    private func unlistedRow(_ list: VoterList) -> some View {
        let title = list.includesMine && list.unlisted == 1
            ? app.t("poll.votersUnlistedYou")
            : app.t.count(list.listed.isEmpty ? "poll.votersUnlistedAll" : "poll.votersUnlisted", list.unlisted)
        let why = !list.includesMine ? "poll.votersUnlistedWhy"
            : list.unlisted == 1 ? "poll.votersUnlistedYouWhy" : "poll.votersUnlistedMine"
        return HStack(spacing: 12) {
            Text("+\(list.unlisted)")
                .font(.vm(11)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 32, height: 32)
                .background(Tokens.muted, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.vmBody)
                Text(app.t(why)).font(.vmMeta)
            }
        }
        .foregroundStyle(Tokens.mutedForeground)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.vmBody).foregroundStyle(Tokens.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }

    private func load() async {
        state = .loading
        do {
            let result = try await collectPages(maxPages: maxPages) { try await app.service.voters(pollId: pollId, cursor: $0) }
            state = .ready(result.page.items, capped: result.page.nextCursor != nil)
        } catch let error as APIError where error.status == 403 {
            state = .hidden
        } catch {
            state = .failed
        }
    }
}
