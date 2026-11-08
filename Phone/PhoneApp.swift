import SwiftUI

@main
struct PixelPhoneApp: App {
    @StateObject private var store = PetStore()
    @StateObject private var nearby = Nearby()
    @StateObject private var health = HealthSignals()
    @Environment(\.scenePhase) private var phase
    @State private var moodDate = Date()

    var body: some Scene {
        WindowGroup {
            TabView {
                PhoneHome(store: store, health: health, active: phase == .active, now: moodDate)
                    .tabItem { Label("Habitat", systemImage: "drop.fill") }
                PhonePlayView(store: store, active: phase == .active)
                    .tabItem { Label("Play", systemImage: "gamecontroller") }
                BreedingView(store: store, nearby: nearby, active: phase == .active)
                    .tabItem { Label("Meet", systemImage: "heart") }
                PetSetupView(store: store)
                    .tabItem { Label("Setup", systemImage: "slider.horizontal.3") }
                AccountView(store: store, health: health)
                    .tabItem { Label("Account", systemImage: "person.crop.circle") }
            }
            .environment(\.ajoloInteractive, phase == .active)
            .petMoodFeedback(life: store.journal.life?.projected(at: moodDate), active: phase == .active)
            .task(id: phase == .active) {
                guard phase == .active else { return }
                while !Task.isCancelled {
                    moodDate = Date()
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                }
            }
            .tint(Color(rgb: 0x8FE6D2))
            .preferredColorScheme(.dark)
            .onAppear { activate(phase) }
            .onChange(of: phase) { activate($0) }
            .task(id: phase == .active && health.enabled) {
                guard phase == .active, health.enabled else { return }
                await health.observe(store)
            }
        }
    }

    private func activate(_ phase: ScenePhase) {
        store.setForeground(phase == .active)
        if phase == .background { nearby.stop() }
    }
}

struct PhoneHome: View {
    @ObservedObject var store: PetStore
    @ObservedObject var health: HealthSignals
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reaction: HabitatReaction?
    let now: Date

    private var currentLife: Life? { store.journal.life?.projected(at: now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let life = currentLife
                    PixelScene(stage: life?.stage ?? .egg, night: PixelScene.isNight(at: now),
                               color: true, tired: life?.needsCare ?? false, animated: active && !reduceMotion,
                               excessWeight: life?.pantry.excessWeight ?? 0, traits: life?.traits,
                               coral: store.journal.hasThreeGenerations, activity: health.activity,
                               species: life?.kind ?? .axolotl, morph: life?.bodyType ?? .standard, pocketLCD: true,
                               mood: life.flatMap { $0.canReceiveCare ? PetMood(life: $0) : nil }, reaction: reaction)
                        .aspectRatio(48.0 / 28, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            if store.journal.hasFamily {
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color(rgb: 0xF2C675), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                            } else {
                                RoundedRectangle(cornerRadius: 20)
                                    .strokeBorder(Color(rgb: 0x9CAF80), lineWidth: 1)
                            }
                        }
                    HStack(alignment: .firstTextBaseline) {
                        Text(life?.name ?? "Your first egg").font(.title.bold())
                        Spacer()
                        if let life {
                            Text("DAY \(life.day)").font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let life {
                        if life.stage == .egg {
                            Text("Hatches \(life.hatchDate, style: .relative)")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Text("\(life.stage.label) · \(life.kind.label)\(life.sex.map { " · " + $0.label } ?? "")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if life.stage != .egg && life.stage != .deceased {
                            if let wake = life.sleep?.endsAt, life.isSleeping {
                                Label("Asleep · wakes \(wake, style: .relative)", systemImage: "moon.zzz")
                                    .font(.subheadline)
                            } else if life.isIrritable {
                                Label("Exhausted · needs eight hours of sleep", systemImage: "exclamationmark.circle")
                                    .font(.subheadline)
                            } else {
                                activityBanner
                            }
                            CareMeters(life: life, pocketLCD: true)
                            HStack {
                                ForEach([Care.feed, .rest], id: \.self) { action in
                                    Button {
                                        store.sync(.care(action, lifeID: life.id))
                                    } label: {
                                        Label(action.label, systemImage: action.icon)
                                            .frame(maxWidth: .infinity, minHeight: 36)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(store.syncing || life.isSleeping)
                                }
                            }
                            NavigationLink {
                                phoneCare
                            } label: {
                                Label("Care & scale", systemImage: "heart")
                            }
                        }
                        NavigationLink {
                            List { EventRows(life: life) }.navigationTitle("Journal")
                        } label: {
                            Label("Journal", systemImage: "book")
                        }
                        NavigationLink {
                            LineageAlbum(journal: store.journal)
                        } label: {
                            Label("Family album", systemImage: "tree")
                        }
                    } else {
                        Text("Open Ajoló on your watch, then use Setup here to incubate an egg.")
                            .foregroundStyle(.secondary)
                    }
                    Text(store.connection).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .environment(\.colorScheme, .light)
                .foregroundStyle(Color(rgb: 0x263521))
                .tint(Color(rgb: 0x344B34))
            }
            .background(Color(rgb: 0xE4EBCC).ignoresSafeArea())
            .toolbarBackground(Color(rgb: 0xE4EBCC), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(Color(rgb: 0x344B34))
            .navigationTitle("Habitat")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.sync() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Sync with Apple Watch")
                        .disabled(store.syncing)
                }
            }
        }
        .onChange(of: store.journal.life?.events.last?.id) { _ in
            guard active, let event = store.journal.life?.events.last,
                  abs(Date().timeIntervalSince(event.date)) < HabitatReaction.duration,
                  let effect = HabitatEffect.matching(event: event.title) else { return }
            reaction = HabitatReaction(effect: effect)
        }
        .task(id: reaction?.id) {
            guard let id = reaction?.id else { return }
            do { try await Task.sleep(for: .seconds(HabitatReaction.duration)) } catch { return }
            if reaction?.id == id { reaction = nil }
        }
    }

    @ViewBuilder private var activityBanner: some View {
        switch health.activity {
        case .idle: EmptyView()
        case .training:
            Label("Swimming with you", systemImage: "figure.pool.swim")
                .font(.subheadline).foregroundStyle(.tint)
        case .quiet:
            Label("Taking a quiet moment with you", systemImage: "sparkle")
                .font(.subheadline).foregroundStyle(.tint)
        }
    }

    private var phoneCare: some View {
        ScrollView {
            if let life = currentLife, life.canReceiveCare {
                VStack(alignment: .leading, spacing: 12) {
                    PixelScene(stage: life.stage, night: PixelScene.isNight(at: Date()),
                               color: true, tired: life.needsCare, animated: active && !reduceMotion,
                               excessWeight: life.pantry.excessWeight, traits: life.traits,
                               species: life.kind, morph: life.bodyType, mood: PetMood(life: life), reaction: reaction)
                        .frame(height: 106)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    PetCareView(life: life, busy: store.syncing) { action, completion in
                        store.sync(.care(action, lifeID: life.id)) { completion($0?.message) }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Care & scale")
    }
}

struct PhonePlayView: View {
    @ObservedObject var store: PetStore
    let active: Bool
    @State private var now = Date()

    private var note: String {
        if store.pendingPhoneActions.contains(where: { $0.isReward && $0.lifeID == store.journal.life?.id }) {
            return "Reward waiting for your axolotl. Open Ajoló on Apple Watch to collect it."
        }
        return "Your Apple Watch collects rewards when you open Ajoló."
    }

    var body: some View {
        NavigationStack {
            PlayRoom(availability: store.journal.life?.projected(at: now).playAvailability ?? .noPet, note: note, life: store.journal.life) { action, completion in
                guard let life = store.journal.life, life.projected(at: Date()).canPlay else {
                    completion("Your axolotl is not ready to play.")
                    return
                }
                completion(store.queuePhoneAction(action, for: life.id) ?? "Open Ajoló on Apple Watch to sync rewards.")
            }
        }
        .task(id: active) {
            guard active else { return }
            while !Task.isCancelled {
                now = Date()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}

struct BreedingView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var nearby: Nearby
    let active: Bool
    @State private var own: Mate?
    @State private var nonce = UUID()
    @State private var moves: [DuelMove] = []
    @State private var result = ""

    private var matchID: UUID? {
        guard own != nil, let remote = nearby.courtship else { return nil }
        return EncounterIntent.matchID(first: nonce, second: remote.nonce)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Open Ajoló on both phones and watches. Introduce your pets to start.")
                    Button(nearby.running ? "End meeting" : "Find nearby players") {
                        if nearby.running { nearby.stop(); clear() } else { nearby.start() }
                    }
                }
                if nearby.running {
                    Section("Connection") {
                        Text(nearby.status)
                        if let incoming = nearby.incoming {
                            Text("Invitation from \(incoming.displayName)")
                            Button("Accept invitation") { nearby.answer(true) }
                            Button("Decline", role: .cancel) { nearby.answer(false) }
                        }
                        if nearby.partner == nil {
                            ForEach(nearby.devices, id: \.self) { device in
                                Button("Invite \(device.displayName)") { nearby.invite(device) }
                            }
                        } else {
                            Button("Introduce my pet") { introduce() }.disabled(store.syncing)
                            if let own, let mate = nearby.courtship?.sender, let matchID {
                                encounter(own, mate: mate, id: matchID)
                            }
                        }
                    }
                }
                if store.journal.pendingEncounter != nil {
                    Section("Pending encounter") {
                        Label("Waiting for both players in Supabase", systemImage: "icloud")
                        Text("Keep Ajoló open on your watch to send your choice and get the result.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let receipt = store.journal.lastEncounter {
                    Section("Last encounter") { Text(receipt.message) }
                }
                if !result.isEmpty { Section { Text(result) } }
            }
            .navigationTitle("Meet")
            .onChange(of: nearby.partner) { _ in clear() }
            .onChange(of: nearby.courtship?.nonce) { _ in moves = [] }
            .task(id: active && store.journal.pendingEncounter != nil) {
                guard active, store.journal.pendingEncounter != nil else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(6)) } catch { return }
                    if !store.syncing { store.sync() }
                }
            }
        }
    }

    @ViewBuilder
    private func encounter(_ own: Mate, mate: Mate, id: UUID) -> some View {
        Text("\(own.name) met \(mate.name) · \(mate.kind.label)")
        if let sex = own.sex, let mateSex = mate.sex {
            if sex != mateSex {
                Button("Breed with \(mate.name)") { submit(own: own, mate: mate, id: id, moves: nil) }
                    .disabled(store.syncing || store.journal.pendingEncounter != nil)
            } else if sex == .male {
                Text("Ripple Duel · choose three moves. Dash beats Splash, Splash beats Guard, Guard beats Dash.")
                    .font(.footnote)
                if !moves.isEmpty { Text(moves.map(\.label).joined(separator: " · ")) }
                HStack {
                    ForEach(DuelMove.allCases) { move in
                        Button(move.label) { if moves.count < 3 { moves.append(move) } }
                            .buttonStyle(.bordered)
                            .disabled(moves.count == 3 || store.journal.pendingEncounter != nil)
                    }
                }
                Button("Clear moves") { moves = [] }.disabled(moves.isEmpty)
                Button("Lock moves") { submit(own: own, mate: mate, id: id, moves: moves) }
                    .disabled(moves.count != 3 || store.syncing || store.journal.pendingEncounter != nil)
            } else {
                Text("These pets can meet. Breeding requires one male and one female.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Text("Choose a sex in Setup before entering an encounter.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if store.journal.lastEncounter?.id == id {
            Button("Start another round") {
                nonce = UUID()
                moves = []
                introduce()
            }
            .disabled(store.syncing || store.journal.pendingEncounter != nil)
        }
    }

    private func introduce() {
        guard let peer = nearby.partner else { return }
        store.sync { reply in
            guard nearby.partner == peer, let life = reply?.journal.life else {
                result = "Open Ajoló on your watch and sync your pet."
                return
            }
            let mate = Mate(life: life)
            if let own, own.id != mate.id { nonce = UUID() }
            guard nearby.send(Courtship(sender: mate, nonce: nonce)) else { return }
            own = mate
            result = "Introduction sent."
        }
    }

    private func submit(own: Mate, mate: Mate, id: UUID, moves: [DuelMove]?) {
        let intent = EncounterIntent(id: id, ownID: own.id, partnerID: mate.id, moves: moves)
        store.sync(.encounter(intent)) { reply in
            result = reply?.message ?? "Open Ajoló on your watch and try again."
        }
    }

    private func clear() {
        own = nil
        nonce = UUID()
        moves = []
        result = ""
    }
}

private struct PetSetupView: View {
    @ObservedObject var store: PetStore
    @State private var draft = PetSettings()
    @State private var baseline = PetSettings()
    @State private var name = ""
    @State private var selectedSex: PetSex?
    @State private var feedback = ""
    @State private var choosingSave = false
    @State private var now = Date()

    private var canIncubate: Bool { store.journal.life == nil || store.journal.life?.stage == .deceased }
    private var settingsLocked: Bool {
        if store.journal.settingsLocked { return true }
        return store.journal.life.map { now >= $0.hatchDate } ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Life cycle", selection: $draft.lifeDays) {
                        ForEach(PetSettings.lifeOptions, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    Picker("Incubation", selection: $draft.incubationMinutes) {
                        Text("15 minutes").tag(15)
                        Text("1 hour").tag(60)
                        Text("3 hours").tag(180)
                    }
                    Picker("Watch display", selection: $draft.display) {
                        ForEach(HabitatDisplay.allCases) { display in
                            Text(display.rawValue).tag(display)
                        }
                    }
                    Button("Save settings") { send(.configure(draft)) }
                        .disabled(store.syncing || draft == baseline)
                } header: {
                    Text("Basic settings")
                } footer: {
                    Text(settingsLocked
                         ? "These settings were locked when your first egg hatched."
                         : "Set these before your first egg hatches. They apply to every generation.")
                }
                .disabled(settingsLocked)

                if canIncubate {
                    Section("Next egg") {
                        TextField("Axolotl name", text: $name)
                        sexPicker
                        Button("Start incubation") {
                            if let selectedSex {
                                let settings = settingsLocked ? store.journal.effectiveSettings : draft
                                send(.incubate(name: name, settings: settings, sex: selectedSex))
                            }
                        }
                        .disabled(store.syncing || selectedSex == nil)
                    }
                }

                if let life = store.journal.life, life.stage != .deceased {
                    Section("Current pet") {
                        Label(life.kind.label, systemImage: "pawprint")
                        if let sex = life.sex {
                            Text(sex.label)
                        } else {
                            sexPicker
                            Button("Set sex") {
                                if let selectedSex { send(.chooseSex(lifeID: life.id, sex: selectedSex)) }
                            }
                            .disabled(store.syncing || selectedSex == nil)
                        }
                    }
                }

                if store.cloudConflict {
                    Section("Cloud save") {
                        Button("Choose a save") { choosingSave = true }
                    }
                }

                Section {
                    Text(feedback.isEmpty ? "Keep Ajoló open on your watch to save settings or start an egg." : feedback)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Setup")
            .onAppear {
                now = Date()
                load(store.journal.effectiveSettings)
            }
            .task(id: store.journal.life?.hatchDate) {
                guard let hatch = store.journal.life?.hatchDate, !settingsLocked else { return }
                do {
                    try await Task.sleep(for: .seconds(max(0, hatch.timeIntervalSinceNow)))
                    now = Date()
                } catch {}
            }
            .onChange(of: store.journal.life?.id) { _ in selectedSex = nil }
            .onChange(of: settingsLocked) { locked in
                if locked { load(store.journal.effectiveSettings) }
            }
            .onChange(of: store.journal.preferences) { settings in
                if draft == baseline { load(settings ?? PetSettings()) }
            }
            .confirmationDialog("Which save should Ajoló use?", isPresented: $choosingSave, titleVisibility: .visible) {
                Button("Use cloud save") { send(.resolveSave(keepLocal: false)) }
                Button("Upload this watch's save", role: .destructive) { send(.resolveSave(keepLocal: true)) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var sexPicker: some View {
        Picker("Sex", selection: $selectedSex) {
            Text("Choose").tag(nil as PetSex?)
            ForEach(PetSex.allCases) { sex in Text(sex.label).tag(Optional(sex)) }
        }
    }

    private func load(_ preferences: PetSettings) {
        baseline = preferences
        draft = preferences
    }

    private func send(_ request: PetRequest) {
        store.sync(request) { reply in
            feedback = reply?.message ?? store.connection
            if let settings = reply?.journal.preferences { load(settings) }
        }
    }
}

private struct AccountView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var health: HealthSignals
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message = ""
    @State private var verificationEmail: String?
    @State private var code = ""

    private var account: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                NavigationLink {
                    HealthSettingsView(health: health)
                } label: {
                    Label("Apple Health", systemImage: "heart.text.square")
                }
                Section("Ajoló account") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    Group {
                        Button("Sign in and link watch") { submit(create: false) }
                        Button("Create account") { submit(create: true) }
                    }
                    .disabled(busy || store.syncing || account.isEmpty || password.isEmpty)
                    if verificationEmail == nil {
                        Button("I have a code") {
                            verificationEmail = account
                            message = ""
                        }
                        .disabled(busy || account.isEmpty)
                    }
                }

                if let verificationEmail {
                    Section("Verify email") {
                        Text(verificationEmail).font(.caption)
                        TextField("Confirmation code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("Verify and link watch") { confirm(verificationEmail) }
                            .disabled(busy || store.syncing || !(6...10).contains(code.filter(\.isASCII).filter(\.isNumber).count))
                        Button("Resend code") { resend(verificationEmail) }
                            .disabled(busy)
                        Button("Cancel", role: .cancel) {
                            self.verificationEmail = nil
                            code = ""
                            message = ""
                        }
                        .disabled(busy)
                    }
                }

                Section {
                    Text("Open Ajoló on Apple Watch to link it. Each email has one active pet and its family history.")
                    if !message.isEmpty { Text(message) }
                }
            }
            .navigationTitle("Account")
        }
    }

    private func submit(create: Bool) {
        guard !busy else { return }
        busy = true
        let account = self.account
        let secret = password
        Task { @MainActor in
            do {
                let client = try CloudClient()
                let session = try await client.signIn(email: account, password: secret, create: create)
                if password == secret { password = "" }
                if let session {
                    link(session)
                } else {
                    verificationEmail = account
                    message = "Enter the code from your email."
                    busy = false
                }
            } catch {
                message = error.localizedDescription
                busy = false
            }
        }
    }

    private func confirm(_ email: String) {
        busy = true
        let token = code.filter(\.isASCII).filter(\.isNumber)
        Task { @MainActor in
            do {
                link(try await CloudClient().confirmSignup(email: email, code: token))
            } catch {
                message = error.localizedDescription
                busy = false
            }
        }
    }

    private func resend(_ email: String) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await CloudClient().resendSignup(email: email)
                code = ""
                message = "Check your inbox and use the latest code."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func link(_ session: CloudSession) {
        verificationEmail = nil
        code = ""
        store.sync(.linkAccount(session)) { reply in
            busy = false
            message = reply?.message ?? "Your account is ready. Open Ajoló on your watch and sign in again."
        }
    }
}
