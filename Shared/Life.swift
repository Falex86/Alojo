import CryptoKit
import Foundation

enum Stage: String, Codable {
    case egg = "Huevo", baby = "Cría", juvenile = "Joven", adult = "Adulto", elder = "Mayor", deceased = "Falleció"

    var label: String {
        switch self {
        case .egg: return "Egg"
        case .baby: return "Hatchling"
        case .juvenile: return "Juvenile"
        case .adult: return "Adult"
        case .elder: return "Elder"
        case .deceased: return "Passed away"
        }
    }

}

enum HabitatDisplay: String, Codable, CaseIterable, Identifiable {
    case automatic = "Auto", classic = "Classic", color = "Color"
    var id: Self { self }
}

enum PetSex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum PetSpecies: String, Codable, CaseIterable {
    case axolotl, turtle, pufferfish, seahorse

    var label: String { rawValue.capitalized }
    var mass: Double {
        switch self {
        case .axolotl: return 1
        case .turtle: return 1.5
        case .pufferfish: return 0.75
        case .seahorse: return 0.48
        }
    }

    var colors: [UInt32] {
        switch self {
        case .axolotl: return [0xFFB6C9, 0xF199BB, 0xE7A5CF]
        case .turtle: return [0x91D69A, 0xB2E083, 0x6DCBA2]
        case .pufferfish: return [0xFFC868, 0xF3AA58, 0xFFDF83]
        case .seahorse: return [0x83D7F4, 0x9AB4F6, 0xA3E5EC]
        }
    }
}

struct PetMorph: Codable {
    enum Size: Int, Codable, CaseIterable {
        case small, medium, large
        var label: String { ["Small", "Medium", "Large"][rawValue] }
        var mass: Double { [0.83, 1, 1.18][rawValue] }
    }
    enum Shape: Int, Codable, CaseIterable {
        case slim, balanced, round
        var label: String { ["Slim", "Balanced", "Round"][rawValue] }
        var mass: Double { [0.88, 1, 1.14][rawValue] }
    }

    let size: Size
    let shape: Shape

    static let standard = Self(size: .medium, shape: .balanced)

    static func random(for id: UUID) -> Self {
        let seed = Traits.bytes(id.uuidString)
        return Self(size: Size.allCases[Int(seed[3] % 3)], shape: Shape.allCases[Int(seed[4] % 3)])
    }
}

struct PetSettings: Codable, Equatable {
    static let lifeOptions = [14, 30, 60]
    static let incubationOptions = [15, 60, 180]
    var lifeDays = 30
    var incubationMinutes = 60
    var display: HabitatDisplay = .automatic

    var isValid: Bool {
        Self.lifeOptions.contains(lifeDays) && Self.incubationOptions.contains(incubationMinutes)
    }

    var milestones: [(TimeInterval, Stage)] {
        let day = 86_400.0
        let factor = Double(lifeDays) / 30
        return [
            (Double(incubationMinutes) * 60, .baby),
            ((2 * factor).rounded() * day, .juvenile),
            ((7 * factor).rounded() * day, .adult),
            ((24 * factor).rounded() * day, .elder),
            (Double(lifeDays) * day, .deceased)
        ]
    }
}

struct Hygiene: Codable {
    var cleanliness = 100.0
    var bathroomNeed = 0.0

    mutating func advance(hours: Double) {
        let hoursFull = max(0, hours - (100 - bathroomNeed) / 4)
        cleanliness = max(0, cleanliness - hours * 0.8 - hoursFull * 1.4)
        bathroomNeed = min(100, bathroomNeed + hours * 4)
    }
}

enum Care: String, CaseIterable, Codable {
    case feed = "Comer", play = "Jugar", rest = "Dormir", exercise = "Ejercicio", vaccine = "Vacuna"

    case playJunk = "Premio chatarra", nutritious = "Nutritivo", junk = "Chatarra"
    case bath, bathroom, wake, pushUps, run, swim, pet

    var label: String {
        switch self {
        case .feed: return "Feed"
        case .rest: return "Rest"
        case .wake: return "Wake early"
        case .pushUps: return "Push-ups"
        case .run: return "Run"
        case .swim: return "Swim"
        case .pet: return "Pet"
        case .exercise: return "Exercise"
        case .vaccine: return "Vaccine"
        case .bath: return "Bath"
        case .bathroom: return "Bathroom"
        case .nutritious, .play: return "Healthy snack"
        case .junk, .playJunk: return "Sweet treat"
        }
    }

    var icon: String {
        switch self {
        case .feed: return "fish"
        case .play, .playJunk: return "sparkles"
        case .nutritious: return "leaf.fill"
        case .junk: return "birthday.cake.fill"
        case .rest: return "moon.stars.fill"
        case .wake: return "sun.max"
        case .pushUps: return "figure.strengthtraining.traditional"
        case .run: return "figure.run"
        case .swim: return "figure.pool.swim"
        case .pet: return "heart.fill"
        case .exercise: return "figure.walk"
        case .vaccine: return "cross.case"
        case .bath: return "bathtub"
        case .bathroom: return "toilet"
        }
    }

    static let workouts: [Care] = [.pushUps, .run, .swim]

    var workout: (strength: Double, energy: Double, food: Double, weight: Double)? {
        switch self {
        case .pushUps: return (18, 12, 6, 4)
        case .run: return (12, 14, 8, 8)
        case .exercise, .swim: return (15, 10, 6, 6)
        default: return nil
        }
    }

    static func isRoutineEvent(_ title: String) -> Bool {
        ["Jugó", "Descansó", Life.overcareEvent].contains(title) || allCases.contains { $0.event == title }
    }

    var event: String {
        switch self {
        case .feed: return "Comió"
        case .play: return "Jugó y ganó un bocado nutritivo"
        case .playJunk: return "Jugó y ganó un bocado chatarra"
        case .nutritious: return "Comió un bocado nutritivo"
        case .junk: return "Comió un bocado chatarra"
        case .rest: return "Fell asleep"
        case .wake: return "Woke early"
        case .pushUps: return "Did push-ups"
        case .run: return "Went for a run"
        case .swim: return "Went for a swim"
        case .pet: return "Was petted"
        case .exercise: return "Hizo ejercicio"
        case .vaccine: return "Recibió una vacuna"
        case .bath: return "Took a bath"
        case .bathroom: return "Used the bathroom"
        }
    }
}

struct LifeEvent: Codable, Identifiable {
    var id = UUID()
    let title: String
    let date: Date
    let zoneID: String
    let offset: Int

    init(_ title: String, at date: Date, zone: TimeZone) {
        self.title = title
        self.date = date
        zoneID = zone.identifier
        offset = zone.secondsFromGMT(for: date)
    }

    var displayTitle: String {
        switch title {
        case "Llegó el huevo": return "The egg arrived"
        case "Nació": return "Hatched"
        case "Murió de vejez": return "Passed away from old age"
        case "Murió por hambre": return "Passed away from hunger"
        case "Se recuperó": return "Recovered"
        case "Se enfermó de fiebre de burbujas": return "Caught bubble fever"
        case "Comió": return "Had a meal"
        case "Jugó": return "Played a game"
        case "Jugó y ganó un bocado nutritivo": return "Played and earned a healthy snack"
        case "Jugó y ganó un bocado chatarra": return "Played and earned a sweet treat"
        case "Comió un bocado nutritivo": return "Ate a healthy snack"
        case "Comió un bocado chatarra": return "Ate a sweet treat"
        case "Descansó": return "Rested"
        case "Hizo ejercicio": return "Exercised"
        case "Recibió una vacuna": return "Received a vaccine"
        default:
            for stage in [Stage.baby, .juvenile, .adult, .elder] where title == "Nueva etapa · \(stage.rawValue)" {
                return "New stage · \(stage.label)"
            }
            if title.hasPrefix("Tuvo un huevo con ") {
                return "Had an egg with " + title.dropFirst("Tuvo un huevo con ".count)
            }
            if title.hasPrefix("Descendiente de ") {
                return "Descendant of " + title.dropFirst("Descendiente de ".count).replacingOccurrences(of: " y ", with: " and ")
            }
            return title
        }
    }

    var localDate: String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = Locale(identifier: "en")
        style.timeZone = TimeZone(secondsFromGMT: offset) ?? .gmt
        return date.formatted(style)
    }
}

struct Pantry: Codable {
    var nutritious = 0
    var junk = 0
    var excessWeight = 0.0
}

struct SleepState: Codable {
    static let duration = 8 * 3_600.0
    static let irritabilityDelay = 24 * 3_600.0
    static let exhaustionDelay = 5 * 86_400.0

    var lastFullSleepAt: Date
    var startedAt: Date?

    var endsAt: Date? { startedAt?.addingTimeInterval(Self.duration) }

    var exhaustionAt: Date {
        let deadline = lastFullSleepAt.addingTimeInterval(Self.exhaustionDelay)
        if let endsAt, endsAt <= deadline { return endsAt.addingTimeInterval(Self.exhaustionDelay) }
        return deadline
    }
}

struct Health: Codable {
    static let strengthLossPerHour = 0.4
    var strength = 45.0
    // Untreated fever uses recoveryAt as its deadline so existing cloud match checks still see illness.
    var recoveryAt: Date?
    var untreatedFever: Bool?
    var lastPetting: Date?

    var feverDeadline: Date? { untreatedFever == true ? recoveryAt : nil }
    var protectedUntil: Date?
    var lastExercise: Date?
    var lastPlay: Date?

    var pantry: Pantry?
    var hygiene: Hygiene?
    var foodRewardDay: Int?
    var foodRewards: Int?
    var preventiveDose: Date?

    var dailyRisk: Double {
        5 + (100 - strength) * 0.15 + (pantry?.excessWeight ?? 0) * 0.15
            + (100 - (hygiene?.cleanliness ?? 100)) * 0.10
    }
    var foodPerHour: Double { 1.65 + strength * 0.009 }

    func foodUsed(over hours: Double) -> Double {
        // Integrate the extra food needed as strength gradually decays.
        let activeHours = min(hours, strength / Self.strengthLossPerHour)
        let strengthHours = (strength - Self.strengthLossPerHour * activeHours / 2) * activeHours
        return 1.65 * hours + 0.009 * strengthHours
    }

    func timeUntilEmpty(food: Double) -> TimeInterval {
        var lower = 0.0
        var upper = food / 1.65
        for _ in 0..<32 {
            let middle = (lower + upper) / 2
            if foodUsed(over: middle) < food {
                lower = middle
            } else {
                upper = middle
            }
        }
        return upper * 3_600
    }

    func protected(at date: Date) -> Bool {
        protectedUntil.map { $0 > date } ?? false
    }

    // The same pet and day always produce the same roll, even after reopening.
    static func roll(for id: UUID, day: Int) -> Double {
        let seed = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(UInt64(day)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        }
        let mixed = (seed ^ (seed >> 30)) &* 0xBF58476D1CE4E5B9
        return Double((mixed ^ (mixed >> 27)) % 10_000) / 100
    }
}

struct Life: Codable, Identifiable {
    var id = UUID()
    var name: String
    var born: Date
    var lastZoneID: String
    var updated: Date
    var stage: Stage = .egg
    var food = 95.0
    var joy = 95.0
    var energy = 95.0
    var events: [LifeEvent]
    var health: Health?
    var sleep: SleepState?
    var hungrySince: Date?
    var offspring: Egg?
    var origin: Egg?
    var genes: Traits?
    var generation: Int?
    var achievements: LifeTotals?
    var appliedPhoneActions: [UUID]?
    var sex: PetSex?
    var species: PetSpecies?
    var morph: PetMorph?
    var kind: PetSpecies { species ?? .axolotl }
    var bodyType: PetMorph { morph ?? .standard }
    var traits: Traits { genes ?? Traits.founder(id) }
    var totals: LifeTotals { achievements ?? LifeTotals() }
    var rules: PetSettings?
    var schedule: PetSettings {
        guard let rules, rules.isValid else { return PetSettings() }
        return rules
    }

    init(name: String, now: Date, zone: TimeZone, egg: Egg? = nil, settings: PetSettings = PetSettings(), sex: PetSex? = nil) {
        self.name = name
        born = now
        updated = now
        lastZoneID = zone.identifier
        if let eggID = egg?.id { id = eggID }
        origin = egg
        rules = settings
        sleep = SleepState(lastFullSleepAt: now.addingTimeInterval(Double(settings.incubationMinutes) * 60))
        self.sex = sex
        if sex != nil {
            let seed = Traits.bytes(id.uuidString)
            species = egg?.species ?? PetSpecies.allCases[Int(seed[5] % 4)]
            morph = PetMorph.random(for: id)
        }
        let inherited = egg?.traits ?? Traits.founder(id)
        genes = inherited
        generation = egg?.generation ?? 1
        health = Health(strength: Double(inherited.baseStrength))
        events = [LifeEvent("Llegó el huevo", at: now, zone: zone)]
    }

    var day: Int { Int(min(Double(schedule.lifeDays), max(0, updated.timeIntervalSince(born) / 86_400))) }
    var breedingDays: ClosedRange<Int> {
        let milestones = schedule.milestones
        return Int(milestones[2].0 / 86_400)...(Int(milestones[3].0 / 86_400) - 1)
    }
    var hatchDate: Date { born.addingTimeInterval(Double(schedule.incubationMinutes) * 60) }
    var canReceiveCare: Bool { stage != .egg && stage != .deceased }
    var canPlay: Bool { canReceiveCare && !isSick && !isSleeping }
    var isSleeping: Bool { canReceiveCare && sleep?.startedAt != nil }
    var isIrritable: Bool {
        guard canReceiveCare, let sleep else { return false }
        return updated.timeIntervalSince(sleep.lastFullSleepAt) >= SleepState.irritabilityDelay
    }

    func projected(at date: Date) -> Self {
        var copy = self
        copy.advance(to: date, zone: TimeZone(identifier: lastZoneID) ?? .autoupdatingCurrent)
        return copy
    }
    var hygiene: Hygiene { wellness.hygiene ?? Hygiene() }

    var referenceWeight: Double {
        let age = max(0, updated.timeIntervalSince(hatchDate))
        let growth = min(1, age / (Double(schedule.lifeDays) * 86_400 * 0.5))
        return (8 + 72 * growth) * kind.mass * bodyType.size.mass * bodyType.shape.mass
    }

    var weight: Double { referenceWeight * (1 + pantry.excessWeight * 0.004) }
    var canBreed: Bool { stage == .adult && offspring == nil }
    var wellness: Health { health ?? Health() }
    var pantry: Pantry { wellness.pantry ?? Pantry() }
    var isSick: Bool { wellness.recoveryAt != nil }
    static let overcareEvent = "Got annoyed by too much care"
    var isAnnoyed: Bool {
        events.last(where: { $0.title == Self.overcareEvent })
            .map { updated.timeIntervalSince($0.date) < 5 * 60 } ?? false
    }
    var needsCare: Bool { isAnnoyed || isIrritable || isSick || min(food, joy, energy, hygiene.cleanliness) < 30 || hygiene.bathroomNeed >= 80 }

    mutating func advance(to now: Date, zone: TimeZone) {
        defer { lastZoneID = zone.identifier }
        guard now > updated, stage != .deceased else { return }
        let hatch = hatchDate
        let death = born.addingTimeInterval(Double(schedule.lifeDays) * 86_400)
        let decayStart = max(updated, hatch)
        let state = wellness
        let elapsed = max(0, min(now, death).timeIntervalSince(decayStart)) / 3_600
        let emptyAt = hungrySince ?? (state.foodUsed(over: elapsed) >= food
            ? decayStart.addingTimeInterval(state.timeUntilEmpty(food: food))
            : nil)
        let hungerDeath = emptyAt?.addingTimeInterval(72 * 3_600)
        if sleep == nil, now >= hatch { sleep = SleepState(lastFullSleepAt: now) }
        let exhaustion = sleep?.exhaustionAt ?? .distantFuture
        let fatalLimit = min(death, hungerDeath ?? .distantFuture, exhaustion)
        let lastZone = TimeZone(identifier: lastZoneID) ?? zone
        let end = advanceHealth(from: decayStart, to: min(now, fatalLimit),
                                canStartAtLimit: now < fatalLimit, zone: lastZone)
        let hours = max(0, end.timeIntervalSince(decayStart)) / 3_600
        if let emptyAt, emptyAt <= end { hungrySince = emptyAt }
        food = hungrySince == nil ? max(0, food - state.foodUsed(over: hours)) : 0
        joy = max(0, joy - hours * 1.2)
        advanceSleep(from: decayStart, to: end, zone: lastZone)
        for (age, milestone) in schedule.milestones {
            let date = born.addingTimeInterval(age)
            guard updated < date, date <= end else { continue }
            stage = milestone
            let title: String
            switch milestone {
            case .baby: title = "Nació"
            case .deceased: title = "Murió de vejez"
            default: title = "Nueva etapa · \(milestone.rawValue)"
            }
            events.append(LifeEvent(title, at: date, zone: lastZone))
        }
        if end < death, end == fatalLimit || end == wellness.feverDeadline {
            stage = .deceased
            let reason: String
            if end == wellness.feverDeadline { reason = "Passed away from untreated illness" }
            else if end == exhaustion { reason = "Passed away from sleep deprivation" }
            else { reason = "Murió por hambre" }
            events.append(LifeEvent(reason, at: end, zone: lastZone))
        }
        events.sort { $0.date < $1.date }
        updated = end
    }

    private mutating func advanceSleep(from start: Date, to end: Date, zone: TimeZone) {
        let firstAwakeEnd = min(end, sleep?.startedAt ?? end)
        energy = max(0, energy - max(0, firstAwakeEnd.timeIntervalSince(start)) / 3_600 * 1.8)
        if var state = sleep, let completion = state.endsAt, completion <= end,
           completion <= state.lastFullSleepAt.addingTimeInterval(SleepState.exhaustionDelay) {
            state.lastFullSleepAt = completion
            state.startedAt = nil
            sleep = state
            energy = min(100, energy + 60)
            energy = max(0, energy - max(0, end.timeIntervalSince(max(start, completion))) / 3_600 * 1.8)
            events.append(LifeEvent("Completed eight hours of sleep", at: completion, zone: zone))
        }
    }

    private mutating func advanceHealth(from start: Date, to limit: Date, canStartAtLimit: Bool, zone: TimeZone) -> Date {
        guard start < limit else { return limit }
        var state = wellness
        var cursor = start
        var end = min(limit, state.feverDeadline ?? .distantFuture)
        var cleanliness = hygiene

        func decay(to date: Date) {
            let hours = date.timeIntervalSince(cursor) / 3_600
            cleanliness.advance(hours: hours)
            state.hygiene = cleanliness
            state.strength = max(0, state.strength - hours * Health.strengthLossPerHour)
            if let excess = state.pantry?.excessWeight {
                state.pantry?.excessWeight = max(0, excess - hours * 0.35)
            }
            cursor = date
        }

        func recover(by date: Date) {
            guard state.feverDeadline == nil, let recovery = state.recoveryAt, recovery <= date else { return }
            state.recoveryAt = nil
            events.append(LifeEvent("Se recuperó", at: recovery, zone: zone))
        }

        var day = Int(start.timeIntervalSince(born) / 86_400) + 1
        var check = born.addingTimeInterval(Double(day) * 86_400)
        while check <= end && day < schedule.lifeDays {
            decay(to: check)
            recover(by: check)
            if (check < end || (end == limit && canStartAtLimit)), state.recoveryAt == nil,
               !state.protected(at: check), Health.roll(for: id, day: day) < state.dailyRisk {
                state.untreatedFever = true
                let deadline = check.addingTimeInterval(72 * 3_600)
                state.recoveryAt = deadline
                end = min(end, deadline)
                events.append(LifeEvent("Se enfermó de fiebre de burbujas", at: check, zone: zone))
            }
            day += 1
            check = born.addingTimeInterval(Double(day) * 86_400)
        }
        decay(to: end)
        recover(by: end)
        health = state
        return end
    }

    mutating func breed(with partner: Mate, zone: TimeZone, approved: Bool = false) -> String {
        guard id != partner.id, let sex, let partnerSex = partner.sex, sex != partnerSex else {
            return "Breeding requires one male and one female."
        }
        let parents = [id, partner.id].sorted { $0.uuidString < $1.uuidString }
        if offspring?.parents == parents { return "Egg saved!" }
        guard offspring == nil, approved || canBreed else { return "Your pet must be an adult without an egg." }
        guard origin?.parents.contains(partner.id) != true,
              partner.parents?.contains(id) != true,
              Set(origin?.parents ?? []).isDisjoint(with: partner.parents ?? []) else {
            return "Choose a partner from a different family."
        }
        let own = Mate(life: self)
        let pair = [own, partner].sorted { $0.id.uuidString < $1.id.uuidString }
        let family = parents.map(\.uuidString).joined(separator: ":")
        let seed = Traits.bytes(family + ":" + id.uuidString)
        let eggID = UUID(uuid: (seed[0], seed[1], seed[2], seed[3], seed[4], seed[5],
                                 seed[6], seed[7], seed[8], seed[9], seed[10], seed[11],
                                 seed[12], seed[13], seed[14], seed[15]))
        offspring = Egg(parents: parents, partnerName: partner.name, id: eggID,
                        traits: Traits.inherit(pair[0].appearance, pair[1].appearance, seed: seed),
                        family: family, parentNames: pair.map(\.name),
                        generation: max(generation ?? 1, partner.generation ?? 1) + 1,
                        species: pair[Int(seed[23] % 2)].kind)
        events.append(LifeEvent("Tuvo un huevo con \(partner.name)", at: updated, zone: zone))
        return "Egg saved!"
    }

    mutating func applyPhoneAction(_ pending: PhonePetAction, at now: Date, zone: TimeZone) -> Bool {
        guard pending.lifeID == id, pending.isSupported, stage != .egg, !isSleeping else { return false }
        if pending.isReward && stage != .deceased {
            guard canPlay else { return false }
            if let lastPlay = wellness.lastPlay, now.timeIntervalSince(lastPlay) < 30 * 60 { return false }
        }
        let seen = appliedPhoneActions ?? []
        guard !seen.contains(pending.id) else { return false }
        care(pending.action, at: now, zone: zone)
        appliedPhoneActions = Array((seen + [pending.id]).suffix(128))
        return true
    }

    @discardableResult
    mutating func care(_ action: Care, at now: Date, zone: TimeZone) -> String {
        advance(to: now, zone: zone)
        guard stage != .egg, stage != .deceased, now >= updated else {
            return "Your axolotl cannot receive care right now."
        }
        if isSleeping && action != .wake && action != .vaccine && action != .rest {
            return "Your pet is asleep. Let it finish or wake it early."
        }
        var state = wellness
        var treats = pantry
        var cleanliness = hygiene
        var event = action.event
        var message = LifeEvent(event, at: now, zone: zone).displayTitle
        let unnecessary: String?
        switch action {
        case .feed, .nutritious, .junk: unnecessary = food >= 99 ? "Already full." : nil
        case .play, .playJunk, .pet: unnecessary = joy >= 99 ? "Already happy." : nil
        case .exercise, .pushUps, .run, .swim: unnecessary = !isSick && state.strength >= 99 ? "Already at full strength." : nil
        case .bath: unnecessary = cleanliness.cleanliness >= 99 ? "Already clean." : nil
        case .bathroom: unnecessary = cleanliness.bathroomNeed < 15 ? "Does not need the bathroom yet." : nil
        case .rest: unnecessary = !isSleeping && !isIrritable && energy >= 99
            && (sleep.map { now.timeIntervalSince($0.lastFullSleepAt) < 16 * 3_600 } ?? false)
            ? "Already rested." : nil
        case .vaccine: unnecessary = state.protected(at: now) && !isSick ? "Already protected." : nil
        case .wake: unnecessary = nil
        }
        if let unnecessary {
            joy = max(0, joy - 8)
            energy = max(0, energy - 5)
            recordCareEvent(Self.overcareEvent, at: now, zone: zone)
            return "\(unnecessary) Annoyed: mood −8, energy −5."
        }
        switch action {
        case .feed:
            cleanliness.bathroomNeed = min(100, cleanliness.bathroomNeed + 8)
            food = min(100, food + 52)
            hungrySince = nil
        case .play, .playJunk:
            guard canPlay else { return "Let your axolotl recover before playing." }
            if let last = state.lastPlay, now.timeIntervalSince(last) < 30 * 60 {
                return "You can claim a reward every 30 minutes."
            }
            state.lastPlay = now
            joy = min(100, joy + 18)
            var counters = totals
            counters.games += 1
            achievements = counters
            if state.foodRewardDay != day {
                state.foodRewardDay = day
                state.foodRewards = 0
            }
            let claimed = state.foodRewards ?? 0
            if claimed < 2 {
                state.foodRewards = claimed + 1
                if action == .play {
                    treats.nutritious += 1
                    message = "Mood +18 and a healthy snack."
                } else {
                    treats.junk += 1
                    message = "Mood +18 and a sweet treat."
                }
            } else {
                event = "Jugó"
                message = "Mood +18. You already earned both snacks today."
            }
        case .nutritious:
            guard treats.nutritious > 0 else { return "No healthy snacks in the pantry." }
            treats.nutritious -= 1
            cleanliness.bathroomNeed = min(100, cleanliness.bathroomNeed + 8)
            food = min(100, food + 60)
            hungrySince = nil
            message = "Food +60, up to 100."
        case .junk:
            guard treats.junk > 0 else { return "No sweet treats in the pantry." }
            treats.junk -= 1
            cleanliness.bathroomNeed = min(100, cleanliness.bathroomNeed + 12)
            food = min(100, food + 70)
            joy = min(100, joy + 8)
            hungrySince = nil
            treats.excessWeight = min(100, treats.excessWeight + 12)
            message = "Food +70, mood +8, and extra weight +12."
        case .rest:
            guard !isSleeping else { return "Your pet is already asleep." }
            if sleep == nil { sleep = SleepState(lastFullSleepAt: now) }
            sleep?.startedAt = now
            message = "Asleep for eight hours."
        case .wake:
            guard isSleeping else { return "Your pet is already awake." }
            sleep?.startedAt = nil
            message = "Woke early. This sleep does not count toward eight hours."
        case .pet:
            if let last = state.lastPetting, now.timeIntervalSince(last) < 10 * 60 {
                return "Your pet can earn a petting bonus every 10 minutes."
            }
            state.lastPetting = now
            joy = min(100, joy + 8)
            message = "Mood +8, up to 100."
        case .exercise, .pushUps, .run, .swim:
            guard let workout = action.workout, !isSick else { return "Let your pet recover before training." }
            guard energy >= 30, food >= 25 else { return "Feed your pet or let it rest before training." }
            if let last = state.lastExercise, now.timeIntervalSince(last) < 4 * 3_600 {
                return "Training is available every 4 hours."
            }
            state.lastExercise = now
            state.strength = min(100, state.strength + workout.strength)
            treats.excessWeight = max(0, treats.excessWeight - workout.weight)
            energy -= workout.energy
            food -= workout.food
            var counters = totals
            counters.workouts += 1
            achievements = counters
            message = "Workout complete. Strength +\(Int(workout.strength)), up to 100."
        case .bath:
            cleanliness.cleanliness = min(100, cleanliness.cleanliness + 70)
            message = "Bath complete."
        case .bathroom:
            cleanliness.bathroomNeed = 0
            message = "Bathroom break complete."
        case .vaccine:
            if let recovery = state.recoveryAt {
                let treated = now.addingTimeInterval(3_600)
                guard state.feverDeadline != nil || treated < recovery else {
                    return "Recovery is already due within an hour."
                }
                state.untreatedFever = nil
                state.recoveryAt = treated
                message = "Treatment given. Recovery takes one hour."
            } else {
                if state.protected(at: now) ||
                    state.preventiveDose.map({ now.timeIntervalSince($0) < 4 * 86_400 }) == true {
                    return "Preventive vaccines are available every 96 hours."
                }
                state.preventiveDose = now
                state.protectedUntil = now.addingTimeInterval(2 * 86_400)
                message = "Vaccinated. Protected for 48 hours."
            }
        }
        state.pantry = treats
        state.hygiene = cleanliness
        health = state
        recordCareEvent(event, at: now, zone: zone)
        return message
    }

    private mutating func recordCareEvent(_ event: String, at now: Date, zone: TimeZone) {
        events.append(LifeEvent(event, at: now, zone: zone))
        let careEvents = events.indices.filter { index in
            Care.isRoutineEvent(events[index].title)
        }
        if careEvents.count > 120 { events.remove(at: careEvents[0]) }
    }
}

struct Journal: Codable {
    var life: Life?
    var album: [Life] = []
    var preferences: PetSettings?
    var pendingEncounter: EncounterIntent?
    var lastEncounter: EncounterReceipt?

    var settingsLocked: Bool {
        !album.isEmpty || (life.map { $0.stage != .egg } ?? false)
    }

    var effectiveSettings: PetSettings { preferences ?? life?.schedule ?? PetSettings() }

    @discardableResult
    mutating func configureFirstEgg(_ settings: PetSettings, at now: Date, zone: TimeZone) -> Bool {
        life?.advance(to: now, zone: zone)
        guard !settingsLocked, settings.isValid else { return false }
        preferences = settings
        if var egg = life {
            // An egg has not spent any time in a care stage, so its incubation can be recalculated.
            egg.rules = settings
            egg.sleep = SleepState(lastFullSleepAt: egg.hatchDate)
            egg.updated = egg.born
            egg.advance(to: now, zone: zone)
            life = egg
        }
        return true
    }

    var lives: [Life] { [life].compactMap { $0 } + album }
    var hasFamily: Bool { lives.contains { $0.offspring != nil || $0.origin != nil } }
    var hasThreeGenerations: Bool { lives.contains { ($0.generation ?? 1) >= 3 } }
}

struct LifeTotals: Codable {
    var games = 0
    var workouts = 0
}

struct Traits: Codable, Equatable {
    let gills: Int
    let markings: Int
    let tone: Int
    let baseStrength: Int

    static func bytes(_ value: String) -> [UInt8] {
        Array(SHA256.hash(data: Data(value.utf8)))
    }

    static func founder(_ id: UUID) -> Traits {
        let seed = bytes(id.uuidString)
        return Traits(gills: Int(seed[0] % 3), markings: Int(seed[1] % 3),
                      tone: Int(seed[2] % 3), baseStrength: 45)
    }

    static func inherit(_ first: Traits, _ second: Traits, seed: [UInt8]) -> Traits {
        let variation = Int(seed[20] % 5) - 2
        let rare = (Int(seed[21]) * 256 + Int(seed[22])) < 3_277
        return Traits(gills: seed[16].isMultiple(of: 2) ? first.gills : second.gills,
                      markings: rare ? 3 : (seed[17].isMultiple(of: 2) ? first.markings : second.markings),
                      tone: seed[18].isMultiple(of: 2) ? first.tone : second.tone,
                      baseStrength: min(50, max(40, (first.baseStrength + second.baseStrength) / 2 + variation)))
    }
}

struct Egg: Codable {
    let parents: [UUID]
    let partnerName: String
    var id: UUID?
    var traits: Traits?
    var family: String?
    var parentNames: [String]?
    var generation: Int?
    var species: PetSpecies?
}

struct Mate: Codable, Equatable {
    let id: UUID
    let name: String
    var traits: Traits?
    var parents: [UUID]?
    var generation: Int?

    var sex: PetSex?
    var species: PetSpecies?
    var kind: PetSpecies { species ?? .axolotl }

    var appearance: Traits { traits ?? Traits.founder(id) }

    init(life: Life) {
        id = life.id
        name = life.name
        traits = life.traits
        parents = life.origin?.parents
        generation = life.generation
        sex = life.sex
        species = life.species
    }
}

enum PetRequest: Codable {
    case snapshot
    case configure(PetSettings)
    case resolveSave(keepLocal: Bool)
    case incubate(name: String, settings: PetSettings, sex: PetSex)
    case chooseSex(lifeID: UUID, sex: PetSex)
    case encounter(EncounterIntent)
    case linkAccount(CloudSession)
    case care(Care, lifeID: UUID)
    case breed(ownID: UUID, partner: Mate)
}

struct PetReply: Codable {
    let journal: Journal
    var message = "Journal updated"
    var cloudConflict: Bool?
}

struct PhonePetAction: Codable, Identifiable {
    var id = UUID()
    let lifeID: UUID
    let action: Care

    var isSupported: Bool { isReward || action == .exercise }
    var isReward: Bool { action == .play || action == .playJunk }
}

enum DuelMove: String, Codable, CaseIterable, Identifiable {
    case dash, guardMove = "guard", splash
    var id: Self { self }
    var label: String { rawValue.capitalized }
}

struct EncounterIntent: Codable, Equatable {
    let id: UUID
    let ownID: UUID
    let partnerID: UUID
    let moves: [DuelMove]?

    static func matchID(first: UUID, second: UUID) -> UUID {
        let bytes = Traits.bytes([first.uuidString, second.uuidString].sorted().joined(separator: ":"))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5],
                           bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

struct EncounterReceipt: Codable, Equatable {
    enum Status: String, Codable {
        case waiting, bred, won, lost, draw, unavailable
    }

    let id: UUID
    let status: Status
    var partner: Mate?
    var score: Int?
    var opponentScore: Int?

    var message: String {
        switch status {
        case .waiting: return "Waiting for the other player in Supabase."
        case .bred: return "Pair confirmed. Each player gets an egg."
        case .unavailable: return "This match is unavailable. Start a new meeting."
        case .won, .lost, .draw:
            let title = status == .won ? "You won" : (status == .lost ? "They won" : "Draw")
            return "\(title) · \(score ?? 0)–\(opponentScore ?? 0)"
        }
    }
}
