import SwiftUI
import SwiftData

/// One stable list of drafts, with a session history of interpreted spoken requests.
struct VoiceSheet: View {
    @Bindable var viewModel: VoiceModeViewModel
    @State private var showsUnderstanding = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            if !dynamicTypeSize.isAccessibilitySize { listeningHero }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.provider == .apple {
                        Label(viewModel.appleProviderLabel, systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.maeusTextSecondary)
                        if viewModel.phase == .connecting {
                            Text(viewModel.stateLabel).font(.caption)
                                .foregroundStyle(Color.maeusTextSecondary)
                        }
                    }
                    Text(loc("VoiceYourDrafts"))
                        .font(.system(.headline, design: .rounded, weight: .heavy))

                    ForEach(viewModel.drafts) { draft in
                        VoiceExpenseDraftCard(draft: draft,
                            changedFields: viewModel.changedFieldsByExpenseID[draft.id] ?? [],
                            onRemove: { viewModel.removeDraft(draft) })
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity))
                    }
                    if !viewModel.clarificationQuestion.isEmpty {
                        Label(viewModel.clarificationQuestion, systemImage: "questionmark.bubble")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.maeusInputBackground, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("voice-clarification")
                    }
                    if !viewModel.understandingHistory.isEmpty {
                        understandingDetail
                    }
                    if viewModel.phase == .error {
                        Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(Color.maeusDestructive)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.maeusDestructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.maeusForeground)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: viewModel.drafts.map(\.id))
            footer
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .background(Color.maeusBackground.ignoresSafeArea())
        .interactiveDismissDisabled(true)
        .task { viewModel.startSession() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.cancelSession()
                dismiss()
            } label: {
                MaeuseCloseIcon().frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .background(Color.maeusSurface, in: Circle())
            .overlay(Circle().stroke(Color.maeusCardBorder, lineWidth: 2))
            .accessibilityLabel(loc("Close"))

            Spacer(minLength: 0)
            if dynamicTypeSize.isAccessibilitySize {
                connectionEmblem.frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            Button { endAndSave() } label: {
                Text(loc("Save"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 42)
            }
            .buttonStyle(StampedButtonStyle(fill: .maeusCheese, foreground: .maeusInk,
                cornerRadius: 20, borderColor: .maeusInk, shadow: 2.5))
            .opacity(canSave ? 1 : 0.4)
            .disabled(!canSave)
            .accessibilityIdentifier("voice-save")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var canSave: Bool { viewModel.canSaveDrafts && viewModel.canEndSession }

    private var connectionEmblem: some View {
        VoiceConnectionEmblem(isReady: viewModel.microphoneIsReady,
            hasError: viewModel.phase == .error,
            isProcessing: viewModel.isProcessingRequest,
            isSpeaking: viewModel.isUserSpeaking || viewModel.microphoneLevel > 0.12,
            level: viewModel.microphoneLevel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.stateLabel)
            .accessibilityIdentifier("voice-connection-emblem")
    }

    private var listeningHero: some View {
        connectionEmblem
            .frame(width: 128, height: 128)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
    }

    private var understandingDetail: some View {
        DisclosureGroup(isExpanded: $showsUnderstanding) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.understandingHistory) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(entry.text)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 22)
                            .padding(.bottom, entry.id == viewModel.understandingHistory.last?.id ? 0 : 18)
                            .overlay(alignment: .topLeading) {
                                GeometryReader { geometry in
                                    Path { path in
                                        path.move(to: CGPoint(x: 4, y: 10))
                                        path.addLine(to: CGPoint(x: 4, y: geometry.size.height + 10))
                                    }
                                    .stroke(Color.maeusTextSecondary.opacity(0.25), lineWidth: 1)
                                    .opacity(entry.id == viewModel.understandingHistory.last?.id ? 0 : 1)
                                    Circle()
                                        .fill(Color.maeusCheese)
                                        .overlay(Circle().stroke(Color.maeusCardBorder.opacity(0.5), lineWidth: 1))
                                        .frame(width: 8, height: 8)
                                        .offset(y: 6)
                                }
                                .accessibilityHidden(true)
                            }
                    }
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeIn(duration: 0.2), value: viewModel.understandingHistory.map(\.id))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Text(loc("VoiceWhatUnderstood"))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .frame(minHeight: 28)
        }
        .tint(Color.maeusForeground)
        .padding(14)
        .background(Color.maeusSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.maeusCardBorder, lineWidth: 1))
        .accessibilityIdentifier("voice-understanding")
    }

    private var footer: some View {
        Text(loc("TotalAmount", viewModel.totalAmount.euroFormatted))
            .font(.system(.subheadline, design: .rounded, weight: .heavy).monospacedDigit())
            .foregroundStyle(Color.maeusForeground)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
    }

    private func endAndSave() {
        guard canSave else { return }
        viewModel.phase = .finalizing
        for expense in viewModel.expensesForSaving() { modelContext.insert(expense) }
        do { try modelContext.save() }
        catch {
            modelContext.rollback()
            viewModel.phase = .error
            viewModel.errorMessage = loc("SaveExpensesFailed", error.localizedDescription)
            return
        }
        viewModel.finishAfterSave()
        dismiss()
    }
}

/// The same fixed canvas carries the connection loop, readiness transition and live input.
private struct VoiceConnectionEmblem: View {
    let isReady: Bool
    let hasError: Bool
    let isProcessing: Bool
    let isSpeaking: Bool
    let level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var progress = 0.0
    @State private var orbitStart = Date.now
    @State private var settledAngle = 0.0

    private func orbitAngle(at date: Date) -> Double {
        date.timeIntervalSince(orbitStart) * .pi * 2 / 2.4 - .pi * 0.7
    }

    var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    VoiceEmblemDrawing(progress: 0, level: 0, orbitAngle: -.pi * 0.7, hasError: hasError)
                        .opacity(isReady ? 0 : 1)
                    VoiceEmblemDrawing(progress: 1, level: level, orbitAngle: 0, hasError: hasError,
                        processingVisibility: isProcessing ? 1 : 0,
                        processingExpansion: isSpeaking ? 1 : 0)
                        .opacity(isReady ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.15), value: isReady)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: hasError || scenePhase != .active)) { timeline in
                    VoiceEmblemDrawing(progress: progress, level: level,
                        orbitAngle: isReady || hasError ? settledAngle : orbitAngle(at: timeline.date),
                        hasError: hasError,
                        processingVisibility: isProcessing ? 1 : 0,
                        processingExpansion: isSpeaking ? 1 : 0,
                        processingAngle: timeline.date.timeIntervalSince(orbitStart) * .pi * 2 / 1.8,
                        listeningPhase: isReady && !hasError && scenePhase == .active
                            ? timeline.date.timeIntervalSince(orbitStart) * .pi * 2 / 2.8 : nil)
                        .animation(.easeOut(duration: 0.08), value: level)
                        .animation(.easeInOut(duration: 0.22), value: isProcessing)
                        .animation(.easeInOut(duration: 0.18), value: isSpeaking)
                }
            }
        }
        .onAppear {
            progress = isReady ? 1 : 0
            settledAngle = orbitAngle(at: .now)
        }
        .onChange(of: isReady) { _, ready in
            // Freeze the crumbs where they are before moving them into the ears.
            settledAngle = orbitAngle(at: .now)
            if ready {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.55)) { progress = 1 }
            } else {
                progress = 0
                orbitStart = .now
            }
        }
        .onChange(of: hasError) { _, failed in
            if failed { settledAngle = orbitAngle(at: .now) }
        }
    }
}

private struct VoiceEmblemDrawing: View, Animatable {
    var progress: Double
    var level: Double
    let orbitAngle: Double
    let hasError: Bool
    var processingVisibility: Double = 0
    var processingExpansion: Double = 0
    var processingAngle: Double = -.pi / 2
    var listeningPhase: Double? = nil

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(progress, level), AnimatablePair(processingVisibility, processingExpansion)) }
        set {
            progress = newValue.first.first
            level = newValue.first.second
            processingVisibility = newValue.second.first
            processingExpansion = newValue.second.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let p = min(1, max(0, progress))
            let center = CGPoint(x: 50, y: 54)
            func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * p }
            func stamped(_ path: Path) {
                context.fill(path.offsetBy(dx: 2, dy: 3), with: .color(.maeusInk))
                context.fill(path, with: .color(.maeusCheese))
                context.stroke(path, with: .color(.maeusInk), lineWidth: 2.5)
            }

            // Orbit trails fade as the crumbs settle behind the mouse's face.
            if !hasError && p < 1 {
                for index in 0..<2 {
                    let angle = orbitAngle + Double(index) * .pi
                    var trail = Path()
                    trail.addArc(center: center, radius: 40,
                        startAngle: .radians(angle - 0.75), endAngle: .radians(angle - 0.25), clockwise: false)
                    context.stroke(trail, with: .color(Color.maeusInk.opacity(0.3 * (1 - p))),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
            for index in 0..<2 {
                let angle = orbitAngle + Double(index) * .pi
                let x = mix(50 + cos(angle) * 40, index == 0 ? 28 : 72)
                let y = mix(54 + sin(angle) * 40, 28)
                let radius = mix(index == 0 ? 5 : 4, 11)
                stamped(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                    width: radius * 2, height: radius * 2)))
            }

            // Fill the cheese's bite while its holes become the microphone waveform.
            let radius = 28.0
            let biteRadius = 11 * (1 - p)
            var face = Path()
            if biteRadius > 2 {
                let distance = radius + 2
                let x = (radius * radius + distance * distance - biteRadius * biteRadius) / (2 * distance)
                let y = sqrt(max(0, radius * radius - x * x))
                let angle = acos(x / radius)
                face.addArc(center: center, radius: radius, startAngle: .radians(angle),
                    endAngle: .radians(2 * .pi - angle), clockwise: false)
                face.addArc(center: CGPoint(x: center.x + distance, y: center.y), radius: biteRadius,
                    startAngle: .radians(atan2(-y, x - distance)),
                    endAngle: .radians(atan2(y, x - distance)), clockwise: true)
                face.closeSubpath()
            } else {
                face = Path(ellipseIn: CGRect(x: 22, y: 26, width: 56, height: 56))
            }
            stamped(face)

            if hasError {
                let mark = context.resolve(Text("!").font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.maeusInk))
                context.draw(mark, at: center)
            } else {
                let holes: [(Double, Double, Double)] = [(38, 41, 6), (54, 43, 9), (36, 57, 10), (64, 60, 6), (49, 69, 8)]
                let heights = [12.0, 19, 27, 19, 12]
                let strength = min(1, max(0, level))
                for index in holes.indices {
                    let (holeX, holeY, diameter) = holes[index]
                    let width = mix(diameter, 4.5)
                    // A quiet wave signals an open microphone even in silence. Actual
                    // input takes over as it gets louder; Reduce Motion omits the wave.
                    let idleWave = listeningPhase.map { sin($0 - Double(index) * 0.7) * 2 } ?? 0
                    let barHeight = heights[index] * (0.65 + strength) + idleWave * (1 - strength)
                    let height = mix(diameter, barHeight)
                    let x = mix(holeX, 36 + Double(index) * 7)
                    let y = mix(holeY, 54)
                    let hole = Path(roundedRect: CGRect(x: x - width / 2, y: y - height / 2,
                        width: width, height: height), cornerRadius: width / 2)
                    let waveformOpacity = 1 - processingVisibility * (1 - processingExpansion)
                    context.fill(hole, with: .color(Color.maeusInk.opacity(mix(0.4, 1) * waveformOpacity)))
                }
                if processingVisibility > 0 && p > 0 {
                    // Keep processing visible while speech takes back the face. The
                    // crumbs move to the rim, independently of the live microphone bars.
                    var crumbs = context
                    crumbs.opacity = processingVisibility * p
                    let orbitRadius = 12 + 25 * processingExpansion
                    for index in 0..<3 {
                        let angle = processingAngle + Double(index) * .pi * 2 / 3
                        let x = center.x + cos(angle) * orbitRadius
                        let y = center.y + sin(angle) * orbitRadius
                        let radius = 3.5 - Double(index) * 0.35
                        let crumb = Path(roundedRect: CGRect(x: x - radius, y: y - radius,
                            width: radius * 2, height: radius * 2), cornerRadius: 1.4)
                        crumbs.fill(crumb.offsetBy(dx: 0.8, dy: 1), with: .color(.maeusInk))
                        crumbs.fill(crumb, with: .color(.maeusCheese))
                        crumbs.stroke(crumb, with: .color(.maeusInk), lineWidth: 1.2)
                    }
                }
            }
        }
    }
}

private struct VoiceExpenseDraftCard: View {
    let draft: VoiceExpenseDraft
    let changedFields: Set<VoiceExpenseMissingField>
    let onRemove: () -> Void
    @State private var highlightsUpdate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(draft.normalizedTitle)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .background(fieldHighlight(.title))
                    .padding(.top, 8)
                Spacer(minLength: 0)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc("VoiceRemoveNamed", draft.normalizedTitle))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    metadata
                    Spacer(minLength: 4)
                    amount
                }
                VStack(alignment: .leading, spacing: 8) {
                    amount
                    metadata
                }
            }
            if !draft.isReadyForSaving {
                Text(loc("VoiceNeedsDetails"))
                    .font(.caption)
                    .foregroundStyle(Color.maeusDestructive)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(Color.maeusForeground)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                shape.fill(Color.maeusInk).offset(x: 3, y: 4)
                shape.fill(Color.maeusSurface)
                shape.stroke(Color.maeusCardBorder, lineWidth: 2)
            }
        }
        .task(id: draft.lastChangedAt) {
            highlightsUpdate = !changedFields.isEmpty
            guard highlightsUpdate else { return }
            do { try await Task.sleep(for: .seconds(1.8)) } catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { highlightsUpdate = false }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("voice-draft-\(draft.id)")
    }

    private func fieldHighlight(_ field: VoiceExpenseMissingField) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.maeusCheese.opacity(highlightsUpdate && changedFields.contains(field) ? 0.45 : 0))
            .padding(.horizontal, -4)
            .padding(.vertical, -2)
    }

    private var amount: some View {
        Text(draft.amount == nil ? "—" : draft.normalizedAmount.euroFormatted)
            .font(.system(.title3, design: .rounded, weight: .heavy).monospacedDigit())
            .fixedSize()
            .background(fieldHighlight(.amount))
            .accessibilityLabel(draft.amount == nil ? loc("VoiceAmountMissing") : draft.normalizedAmount.euroFormatted)
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { dateChip; splitChip }
            VStack(alignment: .leading, spacing: 6) { dateChip; splitChip }
        }
    }
    private var dateChip: some View { chip(formatDate(draft.dateISO), field: .date) }
    private var splitChip: some View { chip(loc("VoicePartnerShare", splitText), field: .split) }
    private func chip(_ title: String, field: VoiceExpenseMissingField) -> some View {
        Text(title)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(highlightsUpdate && changedFields.contains(field) ? Color.maeusCheese : Color.maeusInputBackground, in: Capsule())
    }
    private var splitText: String {
        switch draft.normalizedSplitMode {
        case .percent: return "\(Int(draft.normalizedSplitValue))%"
        case .fixed: return draft.normalizedSplitValue.euroFormatted
        }
    }
    private func formatDate(_ iso: String?) -> String {
        guard let iso, let date = Expense.dateFromISO(iso) else { return loc("Today") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return loc("Today") }
        if calendar.isDateInYesterday(date) { return loc("Yesterday") }
        if calendar.isDateInTomorrow(date) { return loc("Tomorrow") }
        let formatter = DateFormatter()
        formatter.dateFormat = LanguageManager.shared.activeLanguageCode == "de" ? "d. MMM" : "d MMM"
        formatter.locale = LanguageManager.shared.activeLocale
        return formatter.string(from: date)
    }
}
