import SwiftUI
import WatchKit
import Darwin
import CoreMotion

@main
struct PixelWatchApp: App {
    @StateObject private var store = PetStore()
    var body: some Scene {
        WindowGroup { WatchSession(store: store) }
    }
}

private struct WatchSession: View {
    @ObservedObject var store: PetStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.isLuminanceReduced) private var reducedLuminance

    private var active: Bool { phase == .active && !reducedLuminance }

    var body: some View {
        WatchHome(store: store, active: active)
            .environment(\.ajoloInteractive, active)
            .petMoodFeedback(life: store.journal.life, active: active) {
                store.notifyPhoneOfMoodChange()
            }
            .overlay {
                if reducedLuminance {
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear { activate(active) }
            .onChange(of: active) { activate($0) }
    }

    private func activate(_ active: Bool) {
        store.setForeground(active)
        if active { store.refresh() }
    }
}

struct WatchHome: View {
    @ObservedObject var store: PetStore
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("pixel-scene-style") private var style = "Auto"
    @State private var page: Page = .habitat
    @State private var crownIndex = 0.0
    @FocusState private var crownFocused: Bool
    @State private var reaction: HabitatReaction?
    @State private var feedback: Feedback?
    @State private var careDialog: CareDialog?

    private enum CareDialog {
        case workout, wake
        var title: String { self == .workout ? "Choose a workout" : "Wake your pet early?" }
    }
    @StateObject private var wrist = WristPetting()

    private enum Page: Hashable { case clock, habitat, stats, games }

    private struct Feedback: Identifiable {
        let id = UUID()
        let text: String
    }

    private let actions = HabitatEffect.quickActions
    private var selected: HabitatEffect { actions[min(actions.count - 1, max(0, Int(crownIndex.rounded())))] }

    private static let modernWatch: Bool = {
        #if targetEnvironment(simulator)
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var info = utsname()
        guard uname(&info) == 0 else { return false }
        let model = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
        let numbers = model.dropFirst(5).split(separator: ",").compactMap { Int($0) }
        guard numbers.count == 2 else { return false }
        return numbers[0] >= 8 || (numbers[0] == 7 && ((1...5).contains(numbers[1]) || (8...11).contains(numbers[1])))
    }()

    private var color: Bool {
        switch store.journal.preferences?.display {
        case .color: return true
        case .classic: return false
        case .automatic: return Self.modernWatch
        case nil: return style == "Color" || (style == "Auto" && Self.modernWatch)
        }
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                clockPage.tag(Page.clock)
                habitat.tag(Page.habitat)
                statsPage.tag(Page.stats)
                gamesPage.tag(Page.games)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: page) { current in
                crownFocused = current == .habitat
                if current != .habitat { wrist.stop() }
            }
            .onChange(of: active) { if !$0 { wrist.stop() } }
            .onChange(of: store.journal.life?.events.last?.id) { _ in animateLatestCare() }
            .confirmationDialog(careDialog?.title ?? "", isPresented: Binding(
                get: { careDialog != nil },
                set: { if !$0 { careDialog = nil } }
            ), titleVisibility: .visible, presenting: careDialog) { dialog in
                switch dialog {
                case .workout:
                    ForEach(Care.workouts, id: \.self) { action in
                        Button(action.label) {
                            if let life = store.journal.life, let effect = HabitatEffect.matching(action) {
                                run(effect, for: life)
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                case .wake:
                    Button("Wake early", role: .destructive) {
                        if let life = store.journal.life { run(.wake, for: life) }
                    }
                    Button("Keep sleeping", role: .cancel) {}
                }
            } message: { dialog in
                if dialog == .wake {
                    Text("Only eight uninterrupted hours count toward a full sleep.")
                }
            }
            .task(id: active) {
                guard active else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    store.refresh()
                }
            }
            .task(id: feedback?.id) {
                guard let id = feedback?.id else { return }
                do { try await Task.sleep(for: .seconds(HabitatReaction.duration)) } catch { return }
                if feedback?.id == id {
                    feedback = nil
                    reaction = nil
                }
            }
        }
    }

    private func scene(life: Life?, at date: Date, interactive: Bool) -> some View {
        PixelScene(stage: life?.stage ?? .egg, night: PixelScene.isNight(at: date),
                   color: color, tired: interactive && (life?.needsCare ?? false),
                   animated: active && !reduceMotion && page == (interactive ? .habitat : .clock),
                   excessWeight: life?.pantry.excessWeight ?? 0, traits: life?.traits,
                   coral: store.journal.hasThreeGenerations,
                   species: life?.kind ?? .axolotl, morph: life?.bodyType ?? .standard,
                   immersive: true, verticalBias: interactive ? 0.42 : 0.76, pocketLCD: true,
                   mood: life.flatMap { $0.canReceiveCare && (interactive || $0.isSleeping) ? PetMood(life: $0) : nil },
                   reaction: interactive ? reaction : nil)
            .ignoresSafeArea()
    }

    private var habitat: some View {
        let life = store.journal.life
        return ZStack {
            scene(life: life, at: Date(), interactive: true)
            if let life, life.canReceiveCare {
                VStack(spacing: 2) {
                    identity(life)
                    careRow(actions.prefix(4), for: life)
                    if life.isSleeping {
                        Spacer(minLength: 0)
                    } else {
                        Button { beginPetting(life) } label: {
                            Color.clear.contentShape(Rectangle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Pet \(life.name)")
                        .accessibilityHint("Tap the pet, then gently move your wrist back and forth.")
                    }
                    careStatus(for: life)
                    careRow(actions.dropFirst(4), for: life, includeGames: true)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation($crownIndex, from: 0, through: Double(actions.count - 1), by: 1,
                                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .onAppear { if page == .habitat { crownFocused = true } }
            } else {
                VStack {
                    identity(life)
                    Spacer()
                    Text(life.map(status(for:)) ?? (store.readyForPlay ? "Start an egg on iPhone." : store.cloudStatus))
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
            }
        }
        .foregroundStyle(.black)
    }

    private func identity(_ life: Life?) -> some View {
        HStack {
            Text(life?.name ?? "Ajoló").lineLimit(1)
            Spacer(minLength: 4)
            if let life { Text("DAY \(life.day)") }
        }
        .font(.system(.caption2, design: .monospaced, weight: .bold))
    }

    private func careStatus(for life: Life) -> some View {
        let mood = PetMood(life: life)
        return HStack(spacing: 4) {
            Image(systemName: feedback == nil ? mood.icon : (reaction?.effect.icon ?? "info.circle"))
                .accessibilityHidden(true)
            Text(wrist.isActive ? "Gently move your wrist" : (feedback?.text ?? mood.label))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
        }
        .font(.system(.caption2, design: .monospaced, weight: .semibold))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func careRow(_ effects: ArraySlice<HabitatEffect>, for life: Life, includeGames: Bool = false) -> some View {
        HStack(spacing: 2) {
            ForEach(effects) { effect in
                let wakesPet = effect == .rest && life.isSleeping
                Button {
                    if let index = actions.firstIndex(of: effect) { crownIndex = Double(index) }
                    run(effect, for: life)
                } label: {
                    careIcon(wakesPet ? Care.wake.icon : effect.icon, selected: effect == selected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(wakesPet ? Care.wake.label : effect.label)
                .accessibilityAddTraits(effect == selected ? .isSelected : [])
            }
            if includeGames {
                Button { page = .games } label: {
                    careIcon("gamecontroller")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Games")
            }
        }
    }

    private func careIcon(_ icon: String, selected: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 32)
            .overlay(alignment: .bottom) {
                if selected {
                    Capsule().frame(width: 10, height: 2).padding(.bottom, 3)
                }
            }
            .contentShape(Rectangle())
    }

    private func run(_ effect: HabitatEffect, for life: Life) {
        guard store.journal.life?.id == life.id else { return }
        if effect != .pet { wrist.stop() }
        if effect == .exercise {
            if life.isSleeping || life.isSick {
                feedback = Feedback(text: life.isSleeping ? "Let your pet sleep." : "Let your pet recover.")
            } else {
                careDialog = .workout
            }
            return
        }
        if effect == .rest && life.isSleeping {
            careDialog = .wake
            return
        }
        if let action = effect.care {
            let previousEvent = store.journal.life?.events.last?.id
            let previousMood = PetMood(life: life)
            let message = store.care(action, lifeID: life.id)
            let event = store.journal.life?.events.last
            let performed = event?.id != previousEvent && event?.title == action.event
            let annoyed = event?.id != previousEvent && event?.title == Life.overcareEvent
            reaction = performed ? HabitatReaction(effect: effect) : (annoyed ? HabitatReaction(effect: .annoyed) : nil)
            feedback = Feedback(text: message)
            if store.journal.life.map(PetMood.init(life:)) == previousMood {
                WKInterfaceDevice.current().play(performed ? .click : .failure)
            }
        } else {
            store.refresh()
            guard let current = store.journal.life, current.id == life.id, current.canReceiveCare else { return }
            feedback = Feedback(text: "\(current.weight.formatted(.number.precision(.fractionLength(1)))) g")
            reaction = HabitatReaction(effect: .weigh)
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func beginPetting(_ life: Life) {
        guard active, page == .habitat, !life.isSleeping else { return }
        let started = wrist.start {
            guard active, page == .habitat, store.journal.life?.id == life.id else { return }
            run(.pet, for: life)
        }
        if !started { feedback = Feedback(text: "Wrist motion is unavailable.") }
    }

    private func animateLatestCare() {
        guard active, page == .habitat, let event = store.journal.life?.events.last,
              abs(Date().timeIntervalSince(event.date)) < HabitatReaction.duration,
              let effect = HabitatEffect.matching(event: event.title), reaction?.effect != effect else { return }
        reaction = HabitatReaction(effect: effect)
        feedback = Feedback(text: effect == .annoyed ? "Annoyed" : effect.label)
    }

    private var clockPage: some View {
        TimelineView(.periodic(from: .now, by: active ? 15 : 60)) { frame in
            let life = store.journal.life
            ZStack(alignment: .top) {
                scene(life: life, at: frame.date, interactive: false)
                VStack(spacing: 2) {
                    Text(frame.date, style: .time)
                        .font(.system(size: 33, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                    Text(frame.date.formatted(Date.FormatStyle().weekday(.wide).month(.wide).day().year()
                        .locale(Locale(identifier: "en"))))
                        .font(.caption2)
                        .lineLimit(2)
                    Text(life.map { "\($0.name) · DAY \($0.day)" } ?? "Ajoló")
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
            }
        }
    }

    private var statsPage: some View {
        ScrollView {
            if let life = store.journal.life {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Stats").font(.headline)
                    Text("\(life.stage.label) · \(life.kind.label)").font(.caption2)
                    if life.canReceiveCare {
                        CareMeters(life: life)
                        ScalePanel(life: life)
                        Label("Daily illness risk · \(Int(life.wellness.dailyRisk.rounded()))%", systemImage: "heart")
                            .font(.caption2)
                        if let wake = life.sleep?.endsAt, life.isSleeping {
                            Text("Wakes \(wake, style: .relative)").font(.caption2)
                        } else if life.isIrritable {
                            Text("Needs eight uninterrupted hours of sleep.").font(.caption2)
                        }
                        if let deadline = life.wellness.feverDeadline {
                            Text("Treat fever \(deadline, style: .relative)").font(.caption2)
                        } else if let recovery = life.wellness.recoveryAt {
                            Text("Recovery \(recovery, style: .relative)").font(.caption2)
                        } else if life.wellness.protected(at: life.updated) {
                            Label("Vaccine protection active", systemImage: "checkmark.shield").font(.caption2)
                        }
                        NavigationLink("Pantry") { pantryPage }
                        Text("To pet, tap your pet in the habitat and gently move your wrist back and forth.")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(status(for: life)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 5)
            } else {
                Text("Stats appear after starting an egg on iPhone.").font(.caption).padding()
            }
        }
    }

    private var pantryPage: some View {
        List {
            if let life = store.journal.life, life.canReceiveCare {
                ForEach([Care.nutritious, .junk], id: \.self) { snack in
                    let count = snack == .nutritious ? life.pantry.nutritious : life.pantry.junk
                    Button {
                        feedback = Feedback(text: store.care(snack, lifeID: life.id))
                    } label: {
                        Label("\(snack.label) · \(count)", systemImage: snack.icon)
                    }
                    .disabled(count == 0 || life.isSleeping)
                }
                if let feedback { Text(feedback.text).font(.caption2) }
            }
        }
        .navigationTitle("Pantry")
    }

    private var gamesPage: some View {
        Group {
            if let life = store.journal.life {
                PlayRoom(availability: life.playAvailability, life: life) { action, completion in
                    completion(store.care(action, lifeID: life.id))
                }
            } else {
                PlayRoom(availability: .noPet) { _, completion in completion(nil) }
            }
        }
    }

    private func status(for life: Life) -> String {
        if life.stage == .egg { return "Hatches \(life.hatchDate.formatted(.relative(presentation: .numeric)))" }
        if life.stage == .deceased { return life.events.last?.displayTitle ?? life.stage.label }
        if life.isSleeping { return "Asleep" }
        if life.isSick { return "Sick · needs care" }
        if life.isIrritable { return "Exhausted and irritable" }
        if life.hygiene.bathroomNeed >= 80 { return "Needs the bathroom" }
        if life.hygiene.cleanliness < 40 { return "Needs a bath" }
        if life.offspring != nil { return "\(life.stage.label) · Egg saved" }
        if life.needsCare { return "\(life.stage.label) · Needs care" }
        return life.stage.label
    }
}


@MainActor
private final class WristPetting: ObservableObject {
    @Published private(set) var isActive = false

    private let motion = CMMotionManager()
    private var timeout: Task<Void, Never>?
    private var onPet: (() -> Void)?
    private var gesture = WristStrokeSequence()

    func start(onPet: @escaping () -> Void) -> Bool {
        if isActive { return true }
        guard motion.isDeviceMotionAvailable else { return false }
        gesture = WristStrokeSequence()
        isActive = true
        self.onPet = onPet
        motion.deviceMotionUpdateInterval = 0.05
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, error in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                guard error == nil, let sample else {
                    self.stop()
                    return
                }
                let a = sample.userAcceleration
                if self.gesture.record(x: a.x, y: a.y, z: a.z, at: sample.timestamp) {
                    let finished = self.onPet
                    self.stop()
                    finished?()
                }
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            self?.stop()
        }
        return true
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        motion.stopDeviceMotionUpdates()
        isActive = false
        onPet = nil
    }
}

private struct WristStrokeSequence {
    private var axis: Int?
    private var lastDirection: Double = 0
    private var lastTime: TimeInterval = 0
    private var strokes = 0

    mutating func record(x: Double, y: Double, z: Double, at timestamp: TimeInterval) -> Bool {
        let values = [x, y, z]
        if axis == nil || timestamp - lastTime > 1.25 {
            axis = values.indices.max { abs(values[$0]) < abs(values[$1]) }
            lastDirection = 0
            strokes = 0
        }
        guard let axis else { return false }
        let amplitude = values[axis]
        guard (0.12...1.25).contains(abs(amplitude)) else { return false }
        let direction = amplitude > 0 ? 1.0 : -1.0
        guard direction != lastDirection, strokes == 0 || timestamp - lastTime >= 0.14 else { return false }
        lastTime = timestamp
        lastDirection = direction
        strokes += 1
        return strokes >= 4
    }
}
