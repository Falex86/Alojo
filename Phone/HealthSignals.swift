import HealthKit
import SwiftUI

@MainActor
final class HealthSignals: ObservableObject {
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "ajolo-health-enabled")
    @Published private(set) var activity: HabitatActivity = .idle
    @Published private(set) var status = ""
    private let store = HKHealthStore()
    private var hasSigningConfiguration: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AjoloHealthEntitlements") as? String else {
            return false
        }
        return !value.isEmpty && !value.hasPrefix("$(")
    }

    func connect() async {
        guard hasSigningConfiguration else {
            status = "Enable HealthKit for the Ajolo iPhone target in Xcode, then reinstall the app."
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            status = "Apple Health is unavailable on this device."
            return
        }
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            types.insert(exercise)
        }
        if #available(iOS 18, *) { types.insert(HKObjectType.stateOfMindType()) }
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            enabled = true
            UserDefaults.standard.set(true, forKey: "ajolo-health-enabled")
            status = "Using the Apple Health data you chose to share."
        } catch {
            status = "Health access is unavailable. Check the HealthKit capability in Xcode and your Health permissions."
        }
    }

    func disconnect() {
        enabled = false
        activity = .idle
        status = ""
        UserDefaults.standard.removeObject(forKey: "ajolo-health-enabled")
    }

    func observe(_ petStore: PetStore) async {
        guard enabled, hasSigningConfiguration else { return }
        let openedAt = Date()
        while !Task.isCancelled && enabled {
            await refresh(petStore, openedAt: openedAt)
            do { try await Task.sleep(for: .seconds(30)) } catch { break }
        }
    }

    private func refresh(_ petStore: PetStore, openedAt: Date) async {
        let now = Date()
        let recentExercise = now.addingTimeInterval(-8 * 60)
        var exercising = false
        if let type = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) {
            let data = await samples(type, since: recentExercise)
            exercising = data.contains { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: .minute()) ?? 0 > 0 }
        }
        var needsQuiet = false
        if #available(iOS 18, *) {
            let data = await samples(HKObjectType.stateOfMindType(), since: now.addingTimeInterval(-3 * 3_600), limit: 1)
            needsQuiet = (data.first as? HKStateOfMind)?.labels.contains(.stressed) == true
        }
        let workouts = await samples(HKObjectType.workoutType(), since: openedAt.addingTimeInterval(-120))
        guard !Task.isCancelled, enabled else { return }
        activity = exercising ? .training : (needsQuiet ? .quiet : .idle)
        guard let life = petStore.journal.life, life.stage != .egg, life.stage != .deceased,
              let workout = workouts.compactMap({ $0 as? HKWorkout }).first(where: { $0.duration >= 600 }),
              workout.endDate >= life.born,
              UserDefaults.standard.string(forKey: "ajolo-last-workout") != workout.uuid.uuidString else { return }
        if petStore.queuePhoneAction(.exercise, for: life.id) != nil {
            UserDefaults.standard.set(workout.uuid.uuidString, forKey: "ajolo-last-workout")
        }
    }

    private func samples(_ type: HKSampleType, since date: Date, limit: Int = 12) async -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: date, end: Date(), options: .strictEndDate)
        let latest = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [latest]) {
                _, result, _ in continuation.resume(returning: result ?? [])
            }
            store.execute(query)
        }
    }
}

struct HealthSettingsView: View {
    @ObservedObject var health: HealthSignals
    @State private var requesting = false

    var body: some View {
        Form {
            Section("Apple Health") {
                Text("Your axolotl can react to recent activity and to stress you log in State of Mind.")
                Text("Ajoló reads only the types you allow while the iPhone app is open. Health samples stay on your device.")
                    .foregroundStyle(.secondary)
                if health.enabled {
                    Button("Disconnect Apple Health", role: .destructive) { health.disconnect() }
                    Text("Manage access in the Health app.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("Connect Apple Health") {
                        requesting = true
                        Task { await health.connect(); requesting = false }
                    }
                    .disabled(requesting)
                }
                if !health.status.isEmpty { Text(health.status).font(.footnote) }
            }
        }
        .navigationTitle("Activity")
    }
}
