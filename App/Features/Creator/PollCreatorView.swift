import SwiftUI
import VomattCore

/// Write everything on one screen, then review it the way voters will see it (the web's `PollCreator`).
/// Full screen, like the web on phones.
struct PollCreatorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: AppModel.CreatorRequest

    @State private var form: PollForm
    @State private var initial: PollForm
    @State private var reviewing = false
    @State private var showSettings = false
    @State private var showContext: Bool
    @State private var endPreset: String?
    @State private var errors: [PollForm.Field: String] = [:]
    @State private var submitError: String?
    @State private var isSubmitting = false
    @State private var confirmingClose = false
    @FocusState private var focusedOption: Int?

    private var isEdit: Bool { request.poll != nil }

    private static let presets: [(key: String, label: String, hours: Double)] = [
        ("1h", "pollCreator.preset1h", 1), ("24h", "pollCreator.preset24h", 24),
        ("3d", "pollCreator.preset3d", 72), ("1w", "pollCreator.preset1w", 168),
    ]

    init(request: AppModel.CreatorRequest) {
        self.request = request
        let form = request.poll.map(PollForm.init(poll:)) ?? request.draft?.form ?? .empty()
        _form = State(initialValue: form)
        _initial = State(initialValue: form)
        _showContext = State(initialValue: !form.description.isEmpty)
        _endPreset = State(initialValue: request.poll == nil && request.draft == nil ? "3d" : nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if reviewing { review } else { write }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .canvas()
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle(app.t(reviewing ? "pollCreator.reviewTitle" : (isEdit ? "pollCreator.editTitle" : "pollCreator.title")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if reviewing {
                        Button { reviewing = false } label: { Label(app.t("common.edit"), systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    } else {
                        Button(app.t("common.cancel"), action: close)
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
            VStack(alignment: .leading, spacing: 8) {
                Text(app.t("pollCreator.questionLabel")).font(.vm(14, .medium))
                VMTextEditor(placeholder: app.t("pollCreator.questionPlaceholder"), text: $form.title, minHeight: 96,
                             font: .vm(20), isInvalid: errors[.title] != nil, autoFocus: form.title.isEmpty)
                    .onChange(of: form.title) { _, value in
                        if value.count > pollTitleMax { form.title = String(value.prefix(pollTitleMax)) }
                    }
                HStack(alignment: .top) {
                    Text(app.t("pollCreator.questionNote"))
                    Spacer()
                    Text("\(form.title.count)/\(pollTitleMax)").font(.vmMono(13))
                }
                .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                fieldError(.title)
            }

            if showContext {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(app.t("pollCreator.descriptionLabel")) (\(app.t("common.optional")))").font(.vm(14, .medium))
                    VMTextEditor(placeholder: app.t("pollCreator.descriptionPlaceholder"), text: $form.description, minHeight: 80)
                        .onChange(of: form.description) { _, value in
                            if value.count > pollDescriptionMax { form.description = String(value.prefix(pollDescriptionMax)) }
                        }
                }
            } else {
                Button { showContext = true } label: { Label(app.t("pollCreator.addContext"), systemImage: "plus") }
                    .buttonStyle(.vm(.ghost))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -16)
            }

            options
            settings
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.t("pollCreator.pollOptionsLabel")).font(.vm(14, .medium)).padding(.bottom, 2)
            ForEach(form.options.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        BallotMark(checked: false)
                        TextField("", text: optionBinding(index),
                                  prompt: Text("\(app.t("pollCreator.optionsPlaceholder")) \(index + 1)").foregroundStyle(Tokens.mutedForeground))
                            .focused($focusedOption, equals: index)
                            .submitLabel(index == form.options.count - 1 && form.canAddOption ? .next : .done)
                            .onSubmit {
                                // Return adds the next option instead of submitting
                                if index == form.options.count - 1, form.canAddOption {
                                    form.options.append("")
                                    focusedOption = index + 1
                                } else if index < form.options.count - 1 {
                                    focusedOption = index + 1
                                }
                            }
                            .fieldChrome(isFocused: focusedOption == index, isInvalid: errors[.option(index)] != nil)
                            .accessibilityLabel("\(app.t("pollCreator.optionsPlaceholder")) \(index + 1)")
                        if form.options.count > pollOptionsMin {
                            Button { form.options.remove(at: index) } label: {
                                Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(Tokens.mutedForeground)
                            }
                            .buttonStyle(.vm(.ghost, size: .icon))
                            .accessibilityLabel(app.t("pollCreator.removeOption"))
                        }
                    }
                    fieldError(.option(index)).padding(.leading, 26)
                }
            }
            if form.options.count < pollOptionsLimit {
                Button {
                    form.options.append("")
                    focusedOption = form.options.count - 1
                } label: {
                    Label(app.t("pollCreator.addOptionLabel"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Tokens.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .font(.vm(15, .medium))
                .foregroundStyle(Tokens.foreground)
                .disabled(!form.canAddOption)
                .opacity(form.canAddOption ? 1 : 0.5)
                .padding(.leading, 26)
            }
        }
    }

    private func optionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { form.options.indices.contains(index) ? form.options[index] : "" },
            set: { value in
                guard form.options.indices.contains(index) else { return }
                form.options[index] = String(value.prefix(pollOptionMax))
            }
        )
    }

    private var settingsSummary: (top: String, bottom: String) {
        var top = app.t("pollCreator.summaryNoEnd")
        if let end = form.endTime {
            top = form.startTime.map { app.t("pollCreator.summaryOpensLater", ["start": app.dates.pollDate($0), "end": app.dates.pollDate(end)]) }
                ?? app.t("pollCreator.summaryOpensNow", ["end": app.dates.pollDate(end)])
        }
        let bottom = app.t("poll.audience.\(form.audience.rawValue)") + " · "
            + app.t("pollCreator.summaryVisibility", ["level": app.t("pollCreator.visibility.\(form.visibilityLevel.rawValue)")])
        return (top, bottom)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.easeOut(duration: 0.2)) { showSettings.toggle() } } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settingsSummary.top).font(.vm(15, .medium)).foregroundStyle(Tokens.foreground)
                        Text(settingsSummary.bottom).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    Text(app.t(showSettings ? "pollCreator.settingsDone" : "pollCreator.settingsChange"))
                        .font(.vm(15, .medium)).underline().foregroundStyle(Tokens.foreground)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .frame(minHeight: 64)
                .card(padding: 0)
            }
            .buttonStyle(.plain)
            .accessibilityHint(app.t("pollCreator.settingsTitle"))

            if showSettings {
                VStack(alignment: .leading, spacing: 24) {
                    timing
                    RadioCards(legend: app.t("pollCreator.audienceLabel"), note: app.t("pollCreator.audienceNote"),
                               selection: $form.audience, options: Audience.allCases.map {
                                   ($0, app.t("poll.audience.\($0.rawValue)"), app.t("pollCreator.audienceHint.\($0.rawValue)"))
                               })
                    if form.audience == .inviteOnly { inviteesField }
                    RadioCards(legend: app.t("pollCreator.visibilityLabel"), note: app.t("pollCreator.visibilityNote"),
                               selection: $form.voterVisibility, options: VoterVisibility.allCases.map {
                                   ($0, app.t("pollCreator.visibility.\($0.rawValue)"), app.t("pollCreator.visibility.\($0.rawValue)Hint"))
                               })
                }
                .padding(16)
                .background(Tokens.surfaceSoft, in: RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
                .transition(.opacity)
            }
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.t("pollCreator.opensLabel")).font(.vm(14, .medium))
                if let start = form.startTime {
                    HStack {
                        DatePicker("", selection: Binding(get: { start }, set: { form.startTime = $0 }), in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                        Spacer()
                        Button { form.startTime = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(Tokens.mutedForeground)
                            .accessibilityLabel(app.t("pollCreator.opensHint"))
                    }
                } else {
                    Button(app.t("ios.scheduleStart")) { form.startTime = Date.now.addingTimeInterval(3600) }
                        .buttonStyle(.vm(.outline, size: .sm))
                }
                Text(app.t("pollCreator.opensHint")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(app.t("pollCreator.endsLabel")).font(.vm(14, .medium))
                DatePicker("", selection: Binding(
                    get: { form.endTime ?? .now.addingTimeInterval(72 * 3600) },
                    set: { form.endTime = $0; endPreset = nil }
                ), in: (form.startTime ?? .now)..., displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.key) { preset in
                        PillButton(title: app.t(preset.label), isOn: endPreset == preset.key, pill: false) {
                            form.endTime = (form.startTime ?? .now).addingTimeInterval(preset.hours * 3600)
                            endPreset = preset.key
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                fieldError(.endTime)
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
                Text(app.t("pollCreator.inviteesManaged")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
            Text(app.t("pollCreator.inviteesHint")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            fieldError(.invitees)
        }
    }

    @ViewBuilder private func fieldError(_ field: PollForm.Field) -> some View {
        if let key = errors[field] {
            Text(app.t(key)).font(.vmMeta).foregroundStyle(Tokens.destructive)
        }
    }

    // MARK: Review

    private var review: some View {
        let input = form.input()
        let status = Poll.status(active: true, votingActive: true, startTime: input.startTime, endTime: input.endTime)
        return Group {
            VStack(alignment: .leading, spacing: 12) {
                Text(app.t("pollCreator.reviewPreview")).font(.vm(14, .medium))
                VStack(alignment: .leading, spacing: 16) {
                    StatusChip(status: status, startTime: input.startTime, endTime: input.endTime)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(input.title).pollTitle()
                        if let description = input.description {
                            Text(description).font(.vmBody).foregroundStyle(Tokens.mutedForeground)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(Array(input.options.enumerated()), id: \.offset) { _, option in
                            HStack(spacing: 12) {
                                BallotMark(checked: false)
                                Text(option).font(.vm(16)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
                        }
                    }
                }
                .card()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(app.t("pollCreator.ruleAudience.\(form.audience.rawValue)"))
                Text(app.t("pollCreator.ruleSealed"))
                Text(app.t("pollCreator.ruleVisibility.\(form.visibilityLevel.rawValue)") + " " + app.t("pollCreator.ruleFixed"))
                Text(app.t("pollCreator.ruleOneVote"))
            }
            .font(.vmBody)
            .foregroundStyle(Tokens.foreground)
            .lineSpacing(3)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            if reviewing, let submitError {
                Text(submitError).font(.vm(14)).foregroundStyle(Tokens.destructive)
            }
            HStack(spacing: 12) {
                if !reviewing, !isEdit {
                    Button(app.t("pollCreator.saveDraftLabel"), action: saveDraft).buttonStyle(.vm(.ghost))
                }
                if reviewing {
                    LoadingButton(style: .vm(.default, fullWidth: true), action: publish) {
                        Text(app.t(isEdit ? "pollCreator.saveChanges" : "pollCreator.publish"))
                    }
                } else {
                    Button(app.t("pollCreator.review"), action: goToReview).buttonStyle(.vm(.default, fullWidth: true))
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Tokens.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
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

    private func goToReview() {
        errors = form.errors()
        guard errors.isEmpty else {
            // Errors in the folded section stay hidden, so unfold it
            if errors[.endTime] != nil || errors[.invitees] != nil { showSettings = true }
            return
        }
        submitError = nil
        withAnimation { reviewing = true }
    }

    private func publish() async {
        errors = form.errors()
        guard errors.isEmpty else {
            // Something changed since review (e.g. the end passed): back to writing
            reviewing = false
            showSettings = true
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

/// A radio group of bordered cards, each a label and a hint.
struct RadioCards<Value: Hashable>: View {
    let legend: String
    let note: String
    @Binding var selection: Value
    let options: [(value: Value, label: String, hint: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(legend).font(.vm(14, .medium)).padding(.bottom, 2)
            ForEach(options, id: \.value) { option in
                let isOn = option.value == selection
                Button { selection = option.value } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isOn ? Tokens.foreground : Tokens.input)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label).font(.vm(15, .medium)).foregroundStyle(Tokens.foreground)
                            Text(option.hint).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 56)
                    .background(isOn ? Tokens.voltTint : Tokens.card, in: RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(isOn ? Tokens.foreground : Tokens.border))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
            Text(note).font(.vmMeta).foregroundStyle(Tokens.mutedForeground).padding(.top, 4)
        }
    }
}
