import SwiftUI
import VomattCore

/// Write everything on one screen, then review it the way voters will see it (the web's `PollCreator`).
/// Full screen, like the web on phones.
struct PollCreatorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: AppModel.CreatorRequest

    /// Status and times are fixed on entering review; a Closing chip still counts down.
    private struct ReviewSnapshot {
        let status: PollStatus
        let startTime: Date
        let endTime: Date
    }

    private enum Focus: Hashable { case title, description, option(Int) }

    @State private var form: PollForm
    @State private var initial: PollForm
    @State private var review: ReviewSnapshot?
    @State private var showSettings = false
    @State private var showContext: Bool
    /// nil is Custom: the end (and opening) times are picked by hand
    @State private var endPreset: PollForm.EndPreset?
    @State private var errors: [PollForm.Field: String] = [:]
    @State private var submitError: String?
    @State private var confirmingClose = false
    @FocusState private var focus: Focus?

    private var isEdit: Bool { request.poll != nil }
    private static let visibilityOrder: [VoterVisibility] = [.owner, .signedIn, .nobody]

    init(request: AppModel.CreatorRequest) {
        self.request = request
        let form = request.poll.map(PollForm.init(poll:)) ?? request.draft?.form ?? .empty()
        _form = State(initialValue: form)
        _initial = State(initialValue: form)
        _showContext = State(initialValue: !form.description.isEmpty)
        _endPreset = State(initialValue: request.poll == nil && request.draft == nil ? .threeDays : nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let review { reviewStep(review) } else { write }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .canvas()
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle(app.t(review != nil ? "pollCreator.reviewTitle" : (isEdit ? "pollCreator.editTitle" : "pollCreator.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.t("common.cancel"), action: close)
                }
                if review == nil, !isEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Button(app.t("pollCreator.saveDraftLabel"), action: saveDraft)
                            .foregroundStyle(Tokens.mutedForeground)
                    }
                }
            }
        }
        .interactiveDismissDisabled(form != initial)
        .confirmationDialog(
            app.t(isEdit ? "pollCreator.discardEditTitle" : "ios.saveDraftTitle"),
            isPresented: $confirmingClose, titleVisibility: .visible
        ) {
            if isEdit {
                Button(app.t("pollCreator.discardEdit"), role: .destructive) { dismiss() }
                Button(app.t("pollCreator.keepEditing"), role: .cancel) {}
            } else {
                Button(app.t("pollCreator.saveDraftLabel"), action: saveDraft)
                Button(app.t("pollCreator.discardEdit"), role: .destructive) { dismiss() }
                Button(app.t("pollCreator.keepEditing"), role: .cancel) {}
            }
        } message: {
            Text(app.t(isEdit ? "pollCreator.discardEditBody" : "ios.saveDraftBody"))
        }
    }

    // MARK: Write

    private var write: some View {
        Group {
            question
            context
            options
            ends
            rules
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 8) {
            RailHeading(text: app.t("pollCreator.questionLabel"))
            TextField("", text: $form.title, prompt: Text(app.t("pollCreator.questionPlaceholder")).foregroundStyle(Tokens.mutedForeground),
                      axis: .vertical)
                .font(.vm(22, .medium, relativeTo: .title2))
                .tracking(-0.44)
                .lineLimit(2...6)
                .submitLabel(.next)
                .focused($focus, equals: .title)
                .padding(.vertical, 14)
                .fieldChrome(isFocused: focus == .title, isInvalid: errors[.title] != nil, minHeight: 96)
                .accessibilityLabel(app.t("pollCreator.questionPlaceholder"))
                .onChange(of: form.title) { old, value in
                    // The question is one line: Return moves on to the options. A pasted line break
                    // stays until publishing, which joins the lines
                    if value.count == old.count + 1, value.hasSuffix("\n") {
                        form.title = old
                        focus = .option(0)
                    } else if value.count > pollTitleMax {
                        form.title = String(value.prefix(pollTitleMax))
                    }
                    if errors[.title] != nil { errors = form.errors() }
                }
            HStack(alignment: .top) {
                if let error = errors[.title] {
                    Text(app.t(error)).foregroundStyle(Tokens.destructive)
                } else {
                    Text(app.t("pollCreator.questionNote"))
                }
                Spacer()
                Text("\(form.title.count)/\(pollTitleMax)").font(.vmMono(12)).monospacedDigit()
            }
            .font(.vm(12))
            .foregroundStyle(Tokens.mutedForeground)
        }
        .onAppear { if form.title.isEmpty { focus = .title } }
    }

    @ViewBuilder private var context: some View {
        if showContext {
            VStack(alignment: .leading, spacing: 8) {
                RailHeading(text: "\(app.t("pollCreator.descriptionLabel")) (\(app.t("common.optional")))")
                TextField("", text: $form.description, prompt: Text(app.t("pollCreator.descriptionPlaceholder")).foregroundStyle(Tokens.mutedForeground),
                          axis: .vertical)
                    .lineLimit(3...12)
                    .focused($focus, equals: .description)
                    .padding(.vertical, 12)
                    .fieldChrome(isFocused: focus == .description, minHeight: 80)
                    .accessibilityLabel(app.t("pollCreator.descriptionLabel"))
                    .onChange(of: form.description) { _, value in
                        if value.count > pollDescriptionMax { form.description = String(value.prefix(pollDescriptionMax)) }
                    }
            }
        } else {
            Button {
                showContext = true
                // The button goes away: carry focus into the field it opened
                focus = .description
            } label: { Label(app.t("pollCreator.addContext"), systemImage: "plus") }
                .buttonStyle(.vm(.link))
                .padding(.vertical, -10)
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            RailHeading(text: app.t("pollCreator.pollOptionsLabel"))
            ForEach(form.options.indices, id: \.self) { index in
                optionRow(index)
            }
            ForEach(PollForm.optionMessages(errors, count: form.options.count), id: \.self) { message in
                Text(app.t(message)).font(.vm(12)).foregroundStyle(Tokens.destructive)
            }
            if form.options.count < pollOptionsLimit {
                Button(action: addOption) {
                    Label(app.t("pollCreator.addOptionLabel"), systemImage: "plus")
                }
                .buttonStyle(.vm(.outline, fullWidth: true))
            }
        }
    }

    private func optionRow(_ index: Int) -> some View {
        let label = "\(app.t("pollCreator.optionsPlaceholder")) \(index + 1)"
        return HStack(spacing: 10) {
            Text("\(index + 1)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground).accessibilityHidden(true)
            TextField("", text: optionBinding(index), prompt: Text(label).foregroundStyle(Tokens.mutedForeground))
                .focused($focus, equals: .option(index))
                .submitLabel(index == form.options.count - 1 && !form.canAddOption ? .done : .next)
                .onSubmit {
                    // Return moves to the next option, or adds one, instead of submitting
                    if index < form.options.count - 1 {
                        focus = .option(index + 1)
                    } else if form.canAddOption {
                        form.options.append("")
                        focus = .option(index + 1)
                    }
                }
                .accessibilityLabel(label)
            if form.options.count > pollOptionsMin {
                Button {
                    form.options.remove(at: index)
                    if !errors.isEmpty { errors = form.errors() }
                    // The button leaves with its row: keep focus in the list
                    focus = .option(max(index - 1, 0))
                } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tokens.mutedForeground)
                }
                .buttonStyle(.vm(.ghost, size: .icon))
                .padding(.trailing, -8)
                .accessibilityLabel("\(app.t("pollCreator.removeOption")) \(index + 1)")
            }
        }
        .fieldChrome(isFocused: focus == .option(index), isInvalid: errors[.option(index)] != nil)
    }

    private func optionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { form.options.indices.contains(index) ? form.options[index] : "" },
            set: { value in
                guard form.options.indices.contains(index) else { return }
                form.options[index] = String(value.prefix(pollOptionMax))
                // An error clears as soon as it is fixed
                if errors[.option(index)] != nil { errors = form.errors() }
            }
        )
    }

    private func addOption() {
        // An empty option comes first: take the user there instead of adding another
        if let empty = form.firstEmptyOption {
            focus = .option(empty)
        } else {
            form.options.append("")
            focus = .option(form.options.count - 1)
        }
    }

    // MARK: Timing

    private var ends: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailHeading(text: app.t("pollCreator.endsLabel"))
            FlowLayout(spacing: 8) {
                ForEach(PollForm.EndPreset.allCases, id: \.self) { preset in
                    PillButton(title: app.t(preset.labelKey), isOn: endPreset == preset) { apply(preset) }
                }
                PillButton(title: app.t("pollCreator.presetCustom"), isOn: endPreset == nil) { endPreset = nil }
            }
            Text(timingSummary).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
            // A picked opening time stays in view after a preset is chosen, since presets count from it
            if endPreset == nil || form.startTime != nil { times.padding(.top, 6) }
        }
    }

    private var timingSummary: String {
        guard let end = form.endTime else { return app.t("pollCreator.summaryNoEnd") }
        if let start = form.startTime {
            return app.t("pollCreator.summaryOpensLater", ["start": app.dates.pollDate(start), "end": app.dates.pollDate(end)])
        }
        return app.t("pollCreator.summaryOpensNow", ["end": app.dates.pollDate(end)])
    }

    private var times: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(app.t("pollCreator.opensLabel")).font(.vm(14, .medium))
                if let start = form.startTime {
                    HStack {
                        DatePicker(app.t("pollCreator.opensLabel"), selection: Binding(get: { start }, set: { setStart($0) }),
                                   in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                        Spacer()
                        Button { setStart(nil) } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(Tokens.mutedForeground)
                            .accessibilityLabel(app.t("pollCreator.opensHint"))
                    }
                } else {
                    Button(app.t("ios.scheduleStart")) { setStart(.now.addingTimeInterval(3600)) }
                        .buttonStyle(.vm(.outline, size: .sm))
                }
                Text(app.t("pollCreator.opensHint")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(app.t("pollCreator.endsAtLabel")).font(.vm(14, .medium))
                DatePicker(app.t("pollCreator.endsAtLabel"), selection: Binding(
                    get: { form.endTime ?? (form.startTime ?? .now).addingTimeInterval(PollForm.EndPreset.threeDays.duration) },
                    set: {
                        form.endTime = $0
                        endPreset = nil
                        if errors[.endTime] != nil { errors = form.errors() }
                    }
                ), in: (form.startTime ?? .now)..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                fieldError(.endTime)
            }
        }
    }

    private func apply(_ preset: PollForm.EndPreset) {
        form.apply(preset)
        endPreset = preset
        if errors[.endTime] != nil { errors = form.errors() }
    }

    /// A preset keeps measuring from the opening time when that changes.
    private func setStart(_ start: Date?) {
        form.startTime = start
        if let endPreset { form.apply(endPreset) }
    }

    // MARK: Rules

    private var ruleList: [(systemImage: String, text: String)] {
        [
            ("person.2", app.t("pollCreator.ruleAudience.\(form.audience.rawValue)")),
            ("lock", app.t("pollCreator.ruleSealed")),
            ("eye", app.t.sentences(app.t("pollCreator.ruleVisibility.\(form.visibilityLevel.rawValue)"), app.t("pollCreator.ruleFixed"))),
        ]
    }

    /// The rules voters will see; Change opens Audience, Invitees and Voter Visibility.
    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            TideRules(rules: ruleList) {
                HStack {
                    Text(app.t("ios.rulesTitle")).font(.vm(14, .medium)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(app.t(showSettings ? "ios.rulesDone" : "ios.rulesChange")) {
                        withAnimation(.easeOut(duration: 0.2)) { showSettings.toggle() }
                    }
                    .font(.vm(14, .medium))
                    .underline()
                    .foregroundStyle(Tokens.tideForeground)
                    .frame(minHeight: Metrics.minTarget)
                    .padding(.vertical, -12)
                }
            }
            if showSettings {
                VStack(alignment: .leading, spacing: 24) {
                    PillGroup(
                        legend: app.t("pollCreator.audienceLabel"), note: app.t("pollCreator.audienceNote"),
                        hint: app.t("pollCreator.audienceHint.\(form.audience.rawValue)"),
                        selection: $form.audience,
                        options: Audience.allCases.map { ($0, app.t("pollCreator.audienceOption.\($0.rawValue)")) }
                    )
                    if form.audience == .inviteOnly { inviteesField }
                    PillGroup(
                        legend: app.t("pollCreator.visibilityLabel"), note: app.t("pollCreator.visibilityNote"),
                        hint: app.t("pollCreator.visibility.\(form.visibilityLevel.rawValue)Hint"),
                        selection: $form.voterVisibility,
                        options: Self.visibilityOrder.map {
                            ($0, app.t("pollCreator.visibility.\(PollForm.visibilityLevel($0, audience: form.audience).rawValue)"))
                        }
                    )
                }
                .card(padding: 20)
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var inviteesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.t("pollCreator.inviteesLabel")).font(.vm(14, .medium))
            if let invitees = form.invitees {
                InviteePicker(selection: Binding(get: { invitees }, set: { form.invitees = $0 }), withGroups: true,
                              isInvalid: errors[.invitees] != nil)
            } else {
                Text(app.t("pollCreator.inviteesManaged")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
            }
            if errors[.invitees] != nil {
                fieldError(.invitees)
            } else {
                Text(app.t("pollCreator.inviteesHint")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
            }
        }
    }

    @ViewBuilder private func fieldError(_ field: PollForm.Field) -> some View {
        if let key = errors[field] {
            Text(app.t(key)).font(.vm(12)).foregroundStyle(Tokens.destructive)
        }
    }

    // MARK: Review

    private func reviewStep(_ snapshot: ReviewSnapshot) -> some View {
        let description = form.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            Text(app.t("pollCreator.reviewPreview")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            VStack(alignment: .leading, spacing: 16) {
                StatusChip(status: snapshot.status, startTime: snapshot.startTime, endTime: snapshot.endTime)
                VStack(alignment: .leading, spacing: 8) {
                    Text(PollForm.singleLine(form.title)).pollTitle()
                    if !description.isEmpty {
                        Text(description).font(.vm(14)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
                    }
                }
                VStack(spacing: 8) {
                    ForEach(Array(form.options.enumerated()), id: \.offset) { _, option in
                        HStack(spacing: 12) {
                            BallotMark(checked: false)
                            Text(option.trimmingCharacters(in: .whitespacesAndNewlines)).font(.vm(16))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
                    }
                }
            }
            .card(padding: 20)
            TideRules(rules: ruleList + [("person", app.t("pollCreator.ruleOneVote"))])
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if review != nil, let submitError {
                Text(submitError).font(.vm(14)).foregroundStyle(Tokens.destructive)
            }
            if review != nil {
                // Edit beside Publish, within thumb reach
                HStack(spacing: 8) {
                    Button(app.t("common.edit"), action: backToWriting).buttonStyle(.vm(.outline, fullWidth: true))
                    LoadingButton(style: .vm(.default, fullWidth: true), action: publish) {
                        Text(app.t(isEdit ? "pollCreator.saveChanges" : "pollCreator.publish"))
                    }
                }
            } else {
                Button(action: goToReview) {
                    HStack(spacing: 6) {
                        Text(app.t("pollCreator.review"))
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).accessibilityHidden(true)
                    }
                }
                .buttonStyle(.vm(.default, fullWidth: true))
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Tokens.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: Actions

    private func close() {
        if form != initial { confirmingClose = true } else { dismiss() }
    }

    private func saveDraft() {
        app.drafts.save(form, id: request.draft?.id)
        app.showToast(app.t("pollCreator.draftSaved"))
        dismiss()
    }

    /// Takes the user to the first problem; one in a folded section unfolds it.
    private func revealErrors() {
        if errors[.endTime] != nil { endPreset = nil }
        if errors[.invitees] != nil { showSettings = true }
        if errors[.title] != nil {
            focus = .title
        } else if let index = form.options.indices.first(where: { errors[.option($0)] != nil }) {
            focus = .option(index)
        }
    }

    private func goToReview() {
        errors = form.errors()
        guard errors.isEmpty else { return revealErrors() }
        let now = Date.now
        let input = form.input(now: now)
        let status = Poll.status(active: true, votingActive: true, startTime: input.startTime, endTime: input.endTime, at: now)
        submitError = nil
        focus = nil
        withAnimation { review = ReviewSnapshot(status: status, startTime: input.startTime, endTime: input.endTime) }
    }

    private func backToWriting() {
        withAnimation { review = nil }
    }

    private func publish() async {
        errors = form.errors()
        guard errors.isEmpty else {
            // Something changed since review (e.g. the end passed): back to writing, errors visible
            review = nil
            revealErrors()
            return
        }
        do {
            let input = form.input()
            let poll = if let existing = request.poll {
                try await app.service.updatePoll(id: existing.id, input)
            } else {
                try await app.service.createPoll(input)
            }
            if let draft = request.draft { app.drafts.delete(draft.id) }
            app.didUpdate(poll)
            app.showToast(app.t(isEdit ? "pollCreator.saved" : "pollCreator.published"))
            request.onSaved?(poll)
            dismiss()
            // A new poll's first job is collecting votes: land on it, next to the share button
            if !isEdit { app.push(.poll(poll.id)) }
        } catch {
            submitError = app.t.message(for: error, fallback: "common.error")
        }
    }
}

/// One choice of a few, as toggle pills, with what the chosen one means under them (the web's `PillGroup`).
private struct PillGroup<Value: Hashable>: View {
    let legend: String
    let note: String
    let hint: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(legend).font(.vm(14, .medium)).accessibilityAddTraits(.isHeader)
            Text(note).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    PillButton(title: option.label, isOn: option.value == selection) { selection = option.value }
                }
            }
            .padding(.vertical, 8)
            Text(hint).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
        }
    }
}
