import SwiftUI
import VomattCore

/// Card state D: only for Ended Polls, so it never asks for sealed data.
struct ResultsView: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    let myOptionId: String?
    let turnout: Int?
    /// `/results` answered 403: the Poll is still sealed, so refetch it.
    let onSealed: () async -> Void
    /// Set when the viewer may see who voted.
    var onSelectOption: ((ResultRow) -> Void)?

    @State private var fetched: PollResults?
    @State private var failed = false
    @State private var revealed = false

    private var rows: [ResultRow]? {
        poll.inlineResults ?? fetched?.options.map { ResultRow(id: $0.id, text: $0.text, votes: $0.voteCount) }
    }

    var body: some View {
        Group {
            if let rows {
                content(rows)
            } else if failed {
                Text(app.t("poll.resultsFailed")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            } else {
                VStack(spacing: 6) {
                    ForEach(poll.options) { _ in Skeleton(height: 48, radius: Radius.xl) }
                }
            }
        }
        .task(id: poll.id) { await loadIfNeeded() }
    }

    private func content(_ rows: [ResultRow]) -> some View {
        let participants = turnout ?? fetched?.totalParticipants ?? rows.reduce(0) { $0 + $1.votes }
        let winners = Results.winners(rows)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    resultRow(row, percent: Results.support(votes: row.votes, participants: participants),
                              isWinner: winners.contains(row), delay: Double(index) * 0.08)
                }
            }
            (Text(caption(winners, participants: participants))
                + Text(onSelectOption != nil && !winners.isEmpty ? " · \(app.t("poll.votersHint"))" : ""))
                .font(.vmMeta)
                .foregroundStyle(Tokens.mutedForeground)
        }
        .onAppear { revealed = true }
    }

    private func resultRow(_ row: ResultRow, percent: Int, isWinner: Bool, delay: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl)
        let label = HStack(spacing: 10) {
            HStack(spacing: 6) {
                if isWinner { CrownShape().fill(Tokens.foreground).frame(width: 14, height: 14) }
                Text(row.text).font(.vm(15, isWinner ? .semibold : .regular)).multilineTextAlignment(.leading)
                if row.id == myOptionId {
                    Text(app.t("poll.yourVoteShort"))
                        .font(.vm(11, .semibold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(Tokens.highlight, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.2)))
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                CountUpText(value: revealed ? Double(percent) : 0)
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(delay), value: revealed)
                Text("\(row.votes)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
            }
            .font(.vmMono(13))
        }
        .foregroundStyle(Tokens.foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Tokens.foreground.opacity(isWinner ? 0.09 : 0.04))
                    .frame(width: proxy.size.width * (revealed ? CGFloat(percent) / 100 : 0))
                    .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.8).delay(delay), value: revealed)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(isWinner ? Tokens.foreground : Tokens.border, lineWidth: 1))

        return Group {
            if let onSelectOption, row.votes > 0 {
                Button { onSelectOption(row) } label: { label.contentShape(shape) }
                    .buttonStyle(.plain)
                    .accessibilityHint(app.t("poll.voters"))
            } else {
                label
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.text), \(percent)%, \(row.votes)")
    }

    private func caption(_ winners: [ResultRow], participants: Int) -> String {
        if winners.isEmpty { return app.t("poll.noVotes") }
        if winners.count > 1 { return app.t("poll.tie", ["options": winners.map(\.text).joined(separator: app.t("poll.and"))]) }
        return app.t("poll.won", ["option": winners[0].text, "count": participants])
    }

    private func loadIfNeeded() async {
        guard poll.inlineResults == nil, fetched == nil else { return }
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

/// The web's crown icon (viewBox 0 0 16 16).
nonisolated struct CrownShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        var path = Path()
        path.move(to: CGPoint(x: 2 * s, y: 5.5 * s))
        path.addLine(to: CGPoint(x: 5 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 8 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 11 * s, y: 8 * s))
        path.addLine(to: CGPoint(x: 14 * s, y: 5.5 * s))
        path.addLine(to: CGPoint(x: 12.8 * s, y: 12.5 * s))
        path.addLine(to: CGPoint(x: 3.2 * s, y: 12.5 * s))
        path.closeSubpath()
        return path
    }
}

/// Who chose one option, once the Poll has Ended (the web's `VotersDialog`).
struct VotersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pollId: String
    let option: ResultRow

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
                    // Choices are withheld for everyone while an Anonymous Ballot is in the Poll
                    let choicesHidden = voters.contains { $0.optionId == nil }
                    let chose = choicesHidden ? voters : voters.filter { $0.optionId == option.id }
                    if chose.isEmpty {
                        message(app.t("poll.votersNone"))
                    } else {
                        List {
                            if choicesHidden {
                                Text(app.t("ios.votersChoicesHidden"))
                                    .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                                    .listRowBackground(Color.clear)
                            }
                            ForEach(chose) { voter in
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
