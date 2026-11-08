import Combine
import Foundation
import WatchConnectivity

final class PetStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var journal: Journal
    @Published private(set) var connection = "Connecting…"
    @Published private(set) var syncing = false
    @Published private(set) var cloudStatus = "Link your account from iPhone"
    @Published private(set) var readyForPlay = false
    @Published private(set) var cloudConflict = false
    #if os(iOS)
    private var moodRefreshPending = false
    @Published private(set) var pendingPhoneActions: [PhonePetAction] = {
        guard let data = UserDefaults.standard.data(forKey: "ajolo-phone-actions-v1") else { return [] }
        return (try? JSONDecoder().decode([PhonePetAction].self, from: data)) ?? []
    }()
    #endif
    #if os(watchOS)
    private var cloudSession: CloudSession?
    private var cloudCache: CloudCache?
    private var cloudTask: Task<Void, Never>?
    private var cloudRun = UUID()
    private var accountID: UUID?
    private var useLocalOnConflict = false
    #endif

    private let storageKey = "pixel-pet-journal-v1"
    private var foreground = false

    override init() {
        let data = UserDefaults.standard.data(forKey: storageKey)
        let legacy = data.flatMap { try? JSONDecoder().decode(Journal.self, from: $0) } ?? Journal()
        #if os(watchOS)
        let session = CloudSession.stored
        let owner = session?.userID ?? UserDefaults.standard.string(forKey: "ajolo-current-account").flatMap(UUID.init(uuidString:))
        let cache = owner.flatMap(CloudCache.load)
        cloudSession = session
        accountID = owner
        cloudCache = cache
        journal = cache?.journal ?? (owner == nil ? legacy : Journal())
        readyForPlay = cache?.revision != nil || (owner == nil && legacy.life != nil)
        if session != nil { cloudStatus = "Waiting for cloud sync" }
        #else
        journal = legacy
        #endif
        super.init()
    }

    func setForeground(_ active: Bool) {
        foreground = active
        #if os(watchOS)
        restartCloudLoop()
        #endif
        guard active else {
            syncing = false
            #if os(iOS)
            requestID = nil
            moodRefreshPending = false
            let completion = pendingCompletion
            pendingCompletion = nil
            completion?(nil)
            #endif
            return
        }
        guard WCSession.isSupported() else {
            connection = "Connection unavailable"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        updateConnection()
        exchangePhoneActions()
    }

    private func exchangePhoneActions() {
        guard foreground, WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let session = WCSession.default
        #if os(watchOS)
        guard readyForPlay, let data = session.receivedApplicationContext["ajolo-actions"] as? Data,
              let pending = try? JSONDecoder().decode([PhonePetAction].self, from: data),
              pending.count <= 32, var life = journal.life else { return }
        var changed = false
        let now = Date()
        for action in pending where action.lifeID == life.id {
            if life.applyPhoneAction(action, at: now, zone: .autoupdatingCurrent) { changed = true }
        }
        if changed {
            journal.life = life
            save()
        }
        let archived = Set(journal.album.map(\.id))
        let processed = Set(life.appliedPhoneActions ?? [])
        let acknowledged = pending.filter {
            processed.contains($0.id) || archived.contains($0.lifeID)
        }.map { $0.id.uuidString }
        if !acknowledged.isEmpty, session.applicationContext["ajolo-ack"] as? [String] != acknowledged {
            try? session.updateApplicationContext(["ajolo-ack": acknowledged])
        }
        #else
        let ack = Set((session.receivedApplicationContext["ajolo-ack"] as? [String]) ?? [])
        if pendingPhoneActions.contains(where: { ack.contains($0.id.uuidString) }) {
            pendingPhoneActions.removeAll { ack.contains($0.id.uuidString) }
            persistPhoneActions()
            if session.isReachable, !syncing { sync() }
        }
        if let payload = try? JSONEncoder().encode(pendingPhoneActions),
           payload != session.applicationContext["ajolo-actions"] as? Data {
            try? session.updateApplicationContext(["ajolo-actions": payload])
        }
        #endif
    }

    #if os(watchOS)
    func notifyPhoneOfMoodChange() {
        guard foreground, WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["ajolo-mood-changed": true], replyHandler: nil, errorHandler: nil)
    }
    #else
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message["ajolo-mood-changed"] as? Bool == true else { return }
        DispatchQueue.main.async {
            guard self.foreground else { return }
            self.moodRefreshPending = true
            self.refreshMoodIfNeeded()
        }
    }

    private func refreshMoodIfNeeded() {
        guard foreground, moodRefreshPending, !syncing else { return }
        moodRefreshPending = false
        sync()
    }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { self.exchangePhoneActions() }
    }

    private func save() {
        #if os(watchOS)
        if let owner = accountID, var cache = cloudCache {
            cache.journal = journal
            cloudCache = cache
            cache.save(owner)
            return
        }
        #endif
        if let data = try? JSONEncoder().encode(journal) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func updateConnection() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        connection = WCSession.default.isReachable ? "Apple Watch connected" : "Open Ajoló on Apple Watch"
    }

    #if os(watchOS)
    func refresh(at date: Date = Date()) {
        guard foreground, readyForPlay else { return }
        journal.life?.advance(to: date, zone: .autoupdatingCurrent)
        save()
        exchangePhoneActions()
    }

    @discardableResult
    func start(name: String, settings: PetSettings, sex: PetSex) -> String {
        guard foreground, readyForPlay, settings.isValid else { return "Link your account before incubating." }
        refresh()
        guard journal.pendingEncounter == nil else { return "Keep Ajoló open to finish the pending encounter first." }
        let previous = journal.life
        guard previous == nil || previous?.stage == .deceased else { return "You already have an active axolotl." }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = journal.settingsLocked ? savedSettings : settings
        journal.preferences = chosen
        var next = Life(name: trimmed.isEmpty ? "Ajolí" : String(trimmed.prefix(20)),
                        now: Date(), zone: .autoupdatingCurrent, egg: previous?.offspring, settings: chosen, sex: sex)
        if let previous {
            if let origin = next.origin {
                next.events.append(LifeEvent("Descendiente de \(previous.name) y \(origin.partnerName)", at: next.born, zone: .autoupdatingCurrent))
            }
            journal.album.insert(previous, at: 0)
        }
        journal.life = next
        save()
        return "Incubation started."
    }

    private var savedSettings: PetSettings {
        var settings = journal.effectiveSettings
        if journal.preferences == nil, let legacy = UserDefaults.standard.string(forKey: "pixel-scene-style") {
            settings.display = legacy == "Clásico" ? .classic : .init(rawValue: legacy) ?? .automatic
        }
        return settings
    }

    @discardableResult
    func care(_ action: Care, lifeID: UUID) -> String {
        guard foreground, readyForPlay, journal.life?.id == lifeID else {
            return "Open this axolotl's habitat on Apple Watch."
        }
        let result = journal.life?.care(action, at: Date(), zone: .autoupdatingCurrent)
        save()
        return result ?? "Your axolotl is unavailable."
    }
    private func queueEncounter(_ intent: EncounterIntent) -> String {
        guard readyForPlay, cloudSession != nil, let life = journal.life,
              life.id == intent.ownID, intent.ownID != intent.partnerID,
              life.sex != nil else { return "Link your account and choose a sex in Setup first." }
        if journal.lastEncounter?.id == intent.id { return journal.lastEncounter?.message ?? "Encounter complete." }
        if journal.pendingEncounter == intent { return "Encounter queued. Keep Ajoló open on the watch." }
        guard journal.pendingEncounter == nil else { return "Finish your pending encounter first." }
        if let moves = intent.moves {
            guard moves.count == 3, life.sex == .male, life.canPlay else {
                return "Only healthy, hatched males can duel."
            }
        } else {
            guard life.canBreed else { return "Your pet must be an adult without an egg." }
        }
        journal.pendingEncounter = intent
        save()
        restartCloudLoop()
        return "Encounter queued. Keep Ajoló open on the watch."
    }

    private func applyEncounter(_ receipt: EncounterReceipt, intent: EncounterIntent) {
        guard receipt.id == intent.id, journal.pendingEncounter == intent, receipt.status != .waiting else { return }
        if receipt.status == .bred, let partner = receipt.partner, var life = journal.life, life.id == intent.ownID {
            _ = life.breed(with: partner, zone: .autoupdatingCurrent, approved: true)
            journal.life = life
        }
        journal.lastEncounter = receipt
        journal.pendingEncounter = nil
        save()
    }

    private func link(_ session: CloudSession) -> String {
        do { try session.save() } catch { return error.localizedDescription }
        cloudSession = session
        cloudConflict = false
        useLocalOnConflict = false
        if accountID != session.userID || cloudCache == nil {
            let legacyOwner = UserDefaults.standard.string(forKey: "ajolo-legacy-owner")
            let legacyData = UserDefaults.standard.data(forKey: storageKey)
            let legacy = legacyData.flatMap { try? JSONDecoder().decode(Journal.self, from: $0) }
            let canImport = legacyOwner == nil || legacyOwner == session.userID.uuidString
            if canImport && legacy?.life != nil {
                UserDefaults.standard.set(session.userID.uuidString, forKey: "ajolo-legacy-owner")
            }
            let cache = CloudCache.load(session.userID) ?? CloudCache(journal: canImport ? legacy ?? Journal() : Journal())
            accountID = session.userID
            UserDefaults.standard.set(session.userID.uuidString, forKey: "ajolo-current-account")
            cloudCache = cache
            journal = cache.journal
            readyForPlay = cache.revision != nil
            save()
        }
        cloudStatus = "Account linked. Connecting to the cloud…"
        restartCloudLoop()
        return "Watch linked. Keep Ajoló open to sync."
    }

    func resolveCloudConflict(keepLocal: Bool) {
        guard foreground, cloudConflict, let owner = accountID, let cache = cloudCache else { return }
        if keepLocal {
            useLocalOnConflict = true
        } else {
            if let copy = try? JSONEncoder().encode(cache) {
                UserDefaults.standard.set(copy, forKey: CloudCache.key(owner) + "-conflict-backup")
            }
            cloudCache?.pending = nil
            cloudCache?.revision = nil
            readyForPlay = false
            save()
        }
        cloudConflict = false
        restartCloudLoop()
    }

    private func restartCloudLoop() {
        cloudTask?.cancel()
        cloudRun = UUID()
        guard foreground, cloudSession != nil else { return }
        let run = cloudRun
        cloudTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.syncCloud(run: run)
                let interval = self?.journal.pendingEncounter == nil ? 60 : 12
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    @MainActor
    private func syncCloud(run: UUID) async {
        guard foreground, cloudRun == run, var session = cloudSession, cloudCache != nil else { return }
        do {
            let client = try CloudClient()
            if session.expiresAt.timeIntervalSinceNow < 90 {
                session = try await client.refresh(session)
                guard cloudRun == run else { return }
                try session.save()
                cloudSession = session
            }
            if useLocalOnConflict {
                let remote = try await client.read(session)
                guard cloudRun == run else { return }
                cloudCache?.revision = remote?.revision ?? 0
                cloudCache?.pending = nil
                useLocalOnConflict = false
                save()
            }
            if cloudCache?.revision == nil {
                let remote = try await client.read(session)
                guard cloudRun == run, var cache = cloudCache else { return }
                if let remote {
                    cache.journal = remote.journal
                    journal = remote.journal
                    cache.revision = remote.revision
                } else {
                    cache.revision = 0
                }
                cloudCache = cache
                readyForPlay = true
                refresh()
            }
            guard let cache = cloudCache, let revision = cache.revision else { return }
            let pending = cache.pending ?? CloudCache.Pending(id: UUID(), journal: journal)
            cloudCache?.pending = pending
            save()
            let next = try await client.write(pending.journal, session: session, revision: revision, operation: pending.id)
            guard cloudRun == run else { return }
            cloudCache?.revision = next
            cloudCache?.pending = nil
            save()
            cloudConflict = false
            cloudStatus = "Saved to Supabase"
            if let intent = pending.journal.pendingEncounter, journal.pendingEncounter == intent {
                let receipt = try await client.submitEncounter(intent, session: session)
                guard cloudRun == run else { return }
                applyEncounter(receipt, intent: intent)
            }
        } catch {
            guard cloudRun == run, !Task.isCancelled else { return }
            if let error = error as? CloudError {
                if case .conflict = error { cloudConflict = true }
                cloudStatus = error.localizedDescription
            } else {
                cloudStatus = "Offline. Changes are saved on your watch."
            }
        }
    }
    #else
    func queuePhoneAction(_ action: Care, for lifeID: UUID) -> String? {
        let pending = PhonePetAction(lifeID: lifeID, action: action)
        guard let life = journal.life, life.id == lifeID, life.stage != .deceased,
              pending.isSupported, !pending.isReward || life.projected(at: Date()).canPlay else { return nil }
        if pendingPhoneActions.contains(where: { $0.lifeID == lifeID && $0.isReward == pending.isReward }) {
            return "Already queued. Open Ajoló on your watch to collect it."
        }
        guard pendingPhoneActions.count < 32 else { return nil }
        pendingPhoneActions.append(pending)
        persistPhoneActions()
        exchangePhoneActions()
        return pending.isReward ? "Reward queued. Open Ajoló on your watch to collect it." : "Workout queued for your axolotl."
    }

    private func persistPhoneActions() {
        if let data = try? JSONEncoder().encode(pendingPhoneActions) {
            UserDefaults.standard.set(data, forKey: "ajolo-phone-actions-v1")
        }
    }

    private var requestID: UUID?
    private var pendingCompletion: ((PetReply?) -> Void)?

    func sync(_ request: PetRequest = .snapshot, completion: ((PetReply?) -> Void)? = nil) {
        guard foreground, !syncing else { completion?(nil); return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            connection = "Open Ajoló on Apple Watch"
            completion?(nil)
            return
        }
        guard let payload = try? JSONEncoder().encode(request) else { completion?(nil); return }
        syncing = true
        connection = "Syncing…"
        let id = UUID()
        requestID = id
        pendingCompletion = completion
        WCSession.default.sendMessageData(payload, replyHandler: { [weak self] data in
            DispatchQueue.main.async {
                guard let self, self.foreground, self.requestID == id else { return }
                self.syncing = false
                defer { self.refreshMoodIfNeeded() }
                self.requestID = nil
                self.pendingCompletion = nil
                guard let reply = try? JSONDecoder().decode(PetReply.self, from: data) else {
                    self.connection = "Keep Ajoló open on Apple Watch"
                    completion?(nil)
                    return
                }
                self.journal = reply.journal
                self.cloudConflict = reply.cloudConflict ?? false
                self.save()
                self.connection = reply.message
                completion?(reply)
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.foreground, self.requestID == id else { return }
                self.syncing = false
                defer { self.refreshMoodIfNeeded() }
                self.requestID = nil
                self.pendingCompletion = nil
                self.connection = "Open Ajoló on both devices and try again"
                completion?(nil)
            }
        })
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            if self.foreground { session.activate() }
        }
    }
    #endif

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            guard self.foreground else { return }
            if error == nil {
                self.updateConnection()
                self.exchangePhoneActions()
                #if os(iOS)
                if session.isReachable && !self.syncing { self.sync() }
                #endif
            }
            else { self.connection = "Connection unavailable" }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            if self.foreground && !self.syncing {
                self.updateConnection()
                self.exchangePhoneActions()
                #if os(iOS)
                if session.isReachable && !self.syncing { self.sync() }
                #endif
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            #if os(watchOS)
            if self.foreground, let request = try? JSONDecoder().decode(PetRequest.self, from: messageData) {
                self.refresh()
                var message = "Journal updated"
                switch request {
                case .snapshot:
                    break
                case .configure(let preferences):
                    if !self.readyForPlay {
                        message = "Link your account before changing settings."
                    } else if self.journal.configureFirstEgg(preferences, at: Date(), zone: .autoupdatingCurrent) {
                        self.save()
                        message = "Settings saved."
                    } else {
                        self.save()
                        message = "Settings lock when the first egg hatches."
                    }
                case .incubate(let name, let settings, let sex):
                    message = self.start(name: name, settings: settings, sex: sex)
                case .chooseSex(let lifeID, let sex):
                    if self.readyForPlay, let life = self.journal.life,
                       life.id == lifeID, life.sex == nil, life.stage != .deceased {
                        self.journal.life?.sex = sex
                        self.save()
                        message = "Sex saved."
                    } else {
                        message = "A pet's sex can only be set once."
                    }
                case .encounter(let intent):
                    message = self.queueEncounter(intent)
                case .resolveSave(let keepLocal):
                    self.resolveCloudConflict(keepLocal: keepLocal)
                    message = "Checking your selected save…"
                case .linkAccount(let session):
                    message = self.link(session)
                case .care(let action, let lifeID):
                    message = self.care(action, lifeID: lifeID)
                case .breed:
                    message = "Update both apps to use Supabase encounters."
                }
                var snapshot = self.journal
                snapshot.preferences = self.savedSettings
                snapshot.life?.appliedPhoneActions = nil
                snapshot.album = Array(snapshot.album.prefix(8)).map { previous in
                    var summary = previous
                    summary.appliedPhoneActions = nil
                    summary.events = summary.events.filter { event in
                        !Care.isRoutineEvent(event.title)
                    }
                    return summary
                }
                replyHandler((try? JSONEncoder().encode(PetReply(journal: snapshot, message: message, cloudConflict: self.cloudConflict))) ?? Data())
                return
            }
            #endif
            replyHandler(Data())
        }
    }
}
