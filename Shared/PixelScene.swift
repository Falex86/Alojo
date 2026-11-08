import SwiftUI
import AVFoundation
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

private struct AjoloInteractiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var ajoloInteractive: Bool {
        get { self[AjoloInteractiveKey.self] }
        set { self[AjoloInteractiveKey.self] = newValue }
    }
}

enum HabitatActivity {
    case idle, training, quiet
}

enum HabitatEffect: CaseIterable, Identifiable {
    case feed, rest, bath, bathroom, exercise, weigh, vaccine
    case wake, pushUps, run, swim, pet
    case toss, twirl, hop, dive, annoyed

    static let quickActions: [Self] = [.feed, .rest, .bath, .bathroom, .exercise, .weigh, .vaccine]

    static func matching(_ care: Care) -> Self? {
        if care == .exercise { return .swim }
        if care == .nutritious || care == .junk { return .feed }
        return allCases.first { $0.care == care }
    }

    static func matching(event title: String) -> Self? {
        if title == Life.overcareEvent { return .annoyed }
        return Care.allCases.first { $0.event == title }.flatMap { matching($0) }
    }

    var id: Self { self }

    var care: Care? {
        switch self {
        case .feed: return .feed
        case .rest: return .rest
        case .bath: return .bath
        case .bathroom: return .bathroom
        case .exercise: return .exercise
        case .weigh, .toss, .twirl, .hop, .dive, .annoyed: return nil
        case .vaccine: return .vaccine
        case .wake: return .wake
        case .pushUps: return .pushUps
        case .run: return .run
        case .swim: return .swim
        case .pet: return .pet
        }
    }

    var label: String { care?.label ?? "Weigh" }
    var icon: String { care?.icon ?? "scalemass" }
}

struct HabitatReaction: Identifiable {
    let id = UUID()
    let effect: HabitatEffect
    let started = Date()
    static let duration = 2.4
    var duration: TimeInterval = Self.duration
}

enum PetMood {
    case happy, hungry, sleepy, dirty, urgent, sick, bored, sleeping, irritated, annoyed

    init(life: Life) {
        if life.isSleeping { self = .sleeping }
        else if life.isSick { self = .sick }
        else if life.isIrritable { self = .irritated }
        else if life.isAnnoyed { self = .annoyed }
        else if life.hygiene.bathroomNeed >= 80 { self = .urgent }
        else if life.food < 30 { self = .hungry }
        else if life.energy < 30 { self = .sleepy }
        else if life.hygiene.cleanliness < 40 { self = .dirty }
        else if life.joy < 30 { self = .bored }
        else { self = .happy }
    }

    var label: String {
        switch self {
        case .happy: return "Happy"
        case .hungry: return "Hungry"
        case .sleepy: return "Sleepy"
        case .dirty: return "Needs a bath"
        case .urgent: return "Needs the bathroom"
        case .sick: return "Sick"
        case .bored: return "Wants to play"
        case .sleeping: return "Asleep"
        case .irritated: return "Exhausted and irritable"
        case .annoyed: return "Annoyed"
        }
    }

    var icon: String {
        switch self {
        case .happy: return "heart.fill"
        case .hungry: return "fish"
        case .sleepy: return "moon.zzz"
        case .dirty: return "drop"
        case .urgent: return "toilet"
        case .sick: return "cross.case"
        case .bored: return "gamecontroller"
        case .sleeping: return "moon.zzz"
        case .irritated, .annoyed: return "exclamationmark.circle.fill"
        }
    }
}

/// Watches mood transitions even when a different tab is open.
private struct PetMoodFeedback: ViewModifier {
    let mood: PetMood?
    let active: Bool
    let onChange: () -> Void
    @State private var player: AVAudioPlayer?

    func body(content: Content) -> some View {
        content
            .onChange(of: mood) { next in
                guard active, let next else { return }
                play(next)
                onChange()
            }
            .onChange(of: active) { awake in
                if !awake {
                    player?.stop()
                    player = nil
                }
            }
    }

    private func play(_ mood: PetMood) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(mood.watchHaptic)
        #else
        mood.playPhoneHaptic()
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        player?.stop()
        player = try? AVAudioPlayer(data: mood.sound)
        player?.play()
    }
}

extension View {
    func petMoodFeedback(life: Life?, active: Bool, onChange: @escaping () -> Void = {}) -> some View {
        modifier(PetMoodFeedback(mood: life.flatMap {
            $0.canReceiveCare ? PetMood(life: $0) : nil
        }, active: active, onChange: onChange))
    }
}

private extension PetMood {
    #if os(watchOS)
    var watchHaptic: WKHapticType {
        switch self {
        case .happy: return .success
        case .hungry: return .directionDown
        case .sleepy, .sleeping: return .stop
        case .dirty, .bored: return .click
        case .urgent, .sick: return .notification
        case .irritated, .annoyed: return .failure
        }
    }
    #else
    func playPhoneHaptic() {
        switch self {
        case .happy: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .urgent, .hungry: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .sick, .irritated: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .sleepy, .sleeping: UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .dirty: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .annoyed: UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .bored: UISelectionFeedbackGenerator().selectionChanged()
        }
    }
    #endif

    var notes: [Double] {
        switch self {
        case .happy: return [523, 659, 784]
        case .hungry: return [392, 330, 294]
        case .sleepy: return [440, 349]
        case .sleeping: return [349, 294, 262]
        case .dirty: return [294, 440, 330]
        case .urgent: return [587, 587, 784]
        case .sick: return [370, 311, 247]
        case .bored: return [330, 392, 330]
        case .irritated: return [247, 349, 247]
        case .annoyed: return [311, 277]
        }
    }

    var sound: Data {
        // Short PCM tones combine an arcade harmonic with a descending bubble chirp.
        let sampleRate = 16_000
        let samplesPerNote = 1_600
        let byteCount = notes.count * samplesPerNote * 2
        var wave = Data()
        func append<T: FixedWidthInteger>(_ number: T) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        wave.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + byteCount))
        wave.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        wave.append(contentsOf: "data".utf8)
        append(UInt32(byteCount))
        for note in notes {
            for sample in 0..<samplesPerNote {
                let t = Double(sample) / Double(sampleRate)
                let progress = Double(sample) / Double(samplesPerNote)
                let angle = 2 * Double.pi * note * t
                let tone = sin(angle) + 0.18 * sin(3 * angle) + 0.22 * sin(angle * (1.65 - progress * 0.45))
                let envelope = min(1, progress * 18) * pow(1 - progress, 1.8)
                let volume = self == .sleeping ? 3_600.0 : 5_800.0
                append(Int16(tone * envelope * volume))
            }
        }
        return wave
    }
}

struct PixelScene: View {
    @Environment(\.ajoloInteractive) private var interactive
    private var animating: Bool { animated && interactive }

    let stage: Stage
    let night: Bool
    let color: Bool
    let tired: Bool
    var animated = true
    var excessWeight = 0.0
    var traits: Traits?
    var coral = false
    var activity: HabitatActivity = .idle
    var species: PetSpecies = .axolotl
    var morph: PetMorph = .standard
    var immersive = false
    var verticalBias = 0.40
    var pocketLCD = false
    var mood: PetMood?
    var reaction: HabitatReaction?

    static func isNight(at date: Date, zone: TimeZone = .autoupdatingCurrent) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        return hour < 7 || hour >= 20
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: reaction == nil ? 0.25 : 0.1, paused: !animating)) { frame in
            Canvas { context, size in
                let fitted = min(size.width / 48, size.height / 28)
                let pixel = max(1, immersive ? fitted : floor(fitted))
                let x = (size.width - 48 * pixel) / 2
                let y = (size.height - 28 * pixel) * (immersive ? verticalBias : 0.5)
                func draw(_ col: Int, _ row: Int, _ width: Int, _ height: Int, _ ink: Color) {
                    context.fill(Path(CGRect(x: x + Double(col) * pixel, y: y + Double(row) * pixel,
                                             width: Double(width) * pixel, height: Double(height) * pixel)), with: .color(ink))
                }
                let sleeping = mood == .sleeping
                let sky: Color
                let water: Color
                let stone: Color
                let light: Color
                if pocketLCD {
                    sky = Color(rgb: sleeping ? 0x9DAE9F : (night ? 0xB9C7BF : 0xE4EBCC))
                    water = Color(rgb: sleeping ? 0x81998C : (night ? 0xA5BAAE : 0xCEDCB1))
                    stone = Color(rgb: sleeping ? 0x718979 : (night ? 0x90A797 : 0xADC28E))
                    light = Color(rgb: sleeping || night ? 0x344D41 : 0x587153)
                } else {
                    sky = color ? (night ? Color(rgb: 0x1D2145) : Color(rgb: 0x164651)) : Color(rgb: 0xB4CB82)
                    water = color ? (night ? Color(rgb: 0x292E56) : Color(rgb: 0x205E62)) : Color(rgb: 0x9AB770)
                    stone = color ? Color(rgb: 0x286368) : Color(rgb: 0x779759)
                    light = color ? Color(rgb: 0xFFE1B3) : Color(rgb: 0x476345)
                }
                // The animation phases repeat after 312 ticks. Bound the value before
                // converting it to Int, which is 32-bit on some Apple Watches.
                let phase = (frame.date.timeIntervalSince1970 * 4).truncatingRemainder(dividingBy: 312)
                let tick = max(0, Int(phase))
                let elapsed = reaction.map { max(0, frame.date.timeIntervalSince($0.started)) } ?? 0
                let currentEffect = elapsed < (reaction?.duration ?? 0) ? reaction?.effect : nil
                let effect = currentEffect ?? (mood == .sleeping ? .rest : nil)
                let progress = !animating ? 0.5 : (currentEffect == nil ? Double(tick % 12) / 12 :
                    min(1, elapsed / (reaction?.duration ?? HabitatReaction.duration)))
                if immersive {
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(water))
                    if pocketLCD {
                        let floor = y + 25 * pixel
                        context.fill(Path(CGRect(x: 0, y: floor, width: size.width,
                                                 height: max(0, size.height - floor))), with: .color(stone))
                    }
                    let surface = max(0, y + 10 * pixel)
                    context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: surface)), with: .color(sky))
                }
                draw(0, 0, 48, 28, sky)
                draw(0, 10, 48, 18, water)
                draw(0, 25, 48, 3, stone)
                draw(0, 10, 48, 1, stone)
                Self.drawSky(night: night || sleeping, sleeping: sleeping, tick: tick,
                             animated: animating, colorful: color, pocketLCD: pocketLCD,
                             sky: sky, ink: light, draw: draw)
                if animating && !night && !sleeping {
                    Self.drawPassingFish(tick: tick, ink: stone, draw: draw)
                }
                for (a, b) in [(5, 20), (9, 17), (39, 18), (42, 21)] {
                    draw(a, b, 1, 25 - b, stone)
                    draw(a - 1, b + 2, 3, 1, stone)
                }
                for index in 0..<(color ? 5 : 2) {
                    let rise = (tick / 2 + index * 3) % 13
                    let a = [8, 39, 12, 31, 43][index]
                    draw(a, 24 - rise, 1, 1, light.opacity(0.55))
                }
                if color {
                    draw(12, 25, 7, 1, light.opacity(0.35))
                    draw(30, 26, 10, 1, light.opacity(0.25))
                }

                if coral {
                    let reef = color ? Color(rgb: 0xD38C9C) : light
                    for base in [3, 44] {
                        draw(base, 20, 1, 5, reef)
                        draw(base - 1, 21, 3, 1, reef)
                        draw(base + 1, 23, 2, 1, reef)
                    }
                }
                var sprite: [String]
                switch stage {
                case .egg: sprite = Self.egg
                case .deceased: sprite = Self.memorial
                default:
                    switch species {
                    case .axolotl: sprite = stage == .baby ? Self.baby : Self.axolotl
                    case .turtle: sprite = Self.turtle
                    case .pufferfish: sprite = Self.pufferfish
                    case .seahorse: sprite = Self.seahorse
                    }
                }
                if species == .axolotl, excessWeight >= 36 {
                    switch stage {
                    case .baby:
                        sprite[4] = "..#++++++#.*"
                        sprite[5] = "..#++++####."
                    case .juvenile, .adult, .elder:
                        sprite[7] = "...#+++++++##..*"
                        sprite[8] = "...#+++++++###*."
                        sprite[9] = "....##+++###...."
                    default:
                        break
                    }
                }
                let outline = color ? Color(rgb: 0x391E46) : Color(rgb: 0x253C32)
                let colors = species.colors
                let tone = traits?.tone ?? 0
                let hue = colors.indices.contains(tone) ? colors[tone] : colors[0]
                let body = color ? Color(rgb: hue) : Color(rgb: 0xDCE6A5)
                let accent = color ? Color(rgb: stage == .elder ? 0xBA95E5 : 0xF05C96) : Color(rgb: 0x607D4A)
                let shades: [Character: Color] = ["#": outline, "+": body, "*": accent, "@": light, "o": outline]
                let scale = immersive || stage == .adult || stage == .elder ? 2 : 1
                let moving = animating && stage != .deceased
                let wave = sin(progress * .pi * 6)
                let stride = Self.spriteStride(effect: effect, activity: activity, mood: mood,
                                               tick: tick, wave: wave, moving: moving)
                let left = (48 - (sprite.first?.count ?? 0) * scale) / 2 + stride
                let bob = Self.spriteBob(effect: effect, mood: mood, tick: tick, wave: wave, progress: progress, moving: moving)
                let top = 24 - sprite.count * scale - bob
                let showMorph = stage != .egg && stage != .deceased
                let sizeFactor: Double = showMorph ? [0.83, 1, 1.10][morph.size.rawValue] : 1
                let shapeFactor: Double = showMorph ? [0.82, 1, 1.16][morph.shape.rawValue] : 1
                let spin = effect == .twirl ? cos(progress * 4 * .pi) : 1
                let widthFactor = max(0.18, abs(spin)) * sizeFactor * shapeFactor * (immersive && showMorph ? 1.07 : 1)
                let heightFactor = min(sizeFactor, Double(24 - bob) / Double(sprite.count * scale))
                let center = 24 + stride
                let floor = 24 - bob

                func drawPet(_ col: Int, _ row: Int, _ width: Int, _ height: Int, _ ink: Color) {
                    let start = spin < 0 ? 2 * center - col - width : col
                    let x0 = center + Int((Double(start - center) * widthFactor).rounded())
                    let x1 = center + Int((Double(start + width - center) * widthFactor).rounded())
                    let y0 = floor + Int((Double(row - floor) * heightFactor).rounded())
                    let y1 = floor + Int((Double(row + height - floor) * heightFactor).rounded())
                    draw(x0, y0, max(1, x1 - x0), max(1, y1 - y0),
                         pocketLCD && sleeping ? ink.opacity(0.74) : ink)
                }

                for (row, line) in sprite.enumerated() {
                    for (col, symbol) in line.enumerated() {
                        if let ink = shades[symbol] {
                            let blinking = moving && tick % 24 == 0
                            let sleepyEye = ((night && !pocketLCD) || tired || blinking || mood == .sleepy || mood == .sleeping || effect == .rest) && symbol == "o"
                            let gill = species == .axolotl && symbol == "*" && row < 4
                            let stretch = gill && traits?.gills == 1 ? scale : 0
                            let lift = gill && traits?.gills == 2 ? scale : 0
                            drawPet(left + col * scale, top + row * scale - lift,
                                 scale + stretch, sleepyEye ? 1 : scale, ink)
                        }
                    }
                }
                if species == .axolotl, stage != .egg, stage != .deceased {
                    let spotX = left + 7 * scale
                    let spotY = top + (stage == .baby ? 1 : 3) * scale
                    switch traits?.markings {
                    case 1:
                        drawPet(spotX, spotY, scale, scale, accent)
                    case 2:
                        drawPet(spotX, spotY, 3 * scale, 1, accent)
                    case 3:
                        drawPet(spotX, spotY + 1, 3, 1, accent)
                        drawPet(spotX + 1, spotY, 1, 3, accent)
                    default:
                        break
                    }
                }
                if activity == .quiet && stage != .egg && stage != .deceased {
                    draw(38, 14, 3, 1, light)
                    draw(39, 13, 1, 3, light)
                }
                if stage == .elder {
                    drawPet(left + 15, top + 1, 4, 1, light)
                    drawPet(left + 16, top, 1, 1, light)
                    drawPet(left + 18, top, 1, 1, light)
                }
                if effect == .feed || mood == .hungry {
                    let chewing = effect == .feed ? Int(progress * 12).isMultiple(of: 2) : tick % 8 < 3
                    if chewing { drawPet(center - 1, floor - 5, 2, 2, outline) }
                }
                if let effect {
                    Self.drawReaction(effect, progress: progress, color: light, accent: accent, draw: draw)
                } else if let mood {
                    Self.drawMood(mood, tick: tick, color: light, draw: draw)
                }
            }
        }
        .background(color ? Color(rgb: 0x101B2B) : Color(rgb: 0xB4CB82))
        .accessibilityHidden(true)
    }

    private static func drawSky(night: Bool, sleeping: Bool, tick: Int, animated: Bool,
                                colorful: Bool, pocketLCD: Bool, sky: Color, ink: Color,
                                draw: (Int, Int, Int, Int, Color) -> Void) {
        if night {
            let moon = colorful ? Color(rgb: pocketLCD ? 0x4A645B : 0xFFE5B6) : ink
            draw(41, 1, 3, 1, moon)
            draw(40, 2, 5, 4, moon)
            draw(41, 6, 3, 1, moon)
            draw(43, 1, 3, 4, sky)
            draw(7, 2, 1, 1, moon)
            draw(22, 5, 1, 1, moon)
            draw(32, 2, 1, 1, moon.opacity(0.6))
            let streak = tick % 104
            if sleeping && animated && streak < 10 {
                let x = 7 + streak * 3
                let y = 1 + streak / 2
                draw(x, y, 2, 1, moon)
                draw(x - 2, y - 1, 2, 1, moon.opacity(0.65))
                draw(x - 4, max(0, y - 2), 2, 1, moon.opacity(0.35))
            }
        } else {
            let sun = colorful ? Color(rgb: pocketLCD ? 0xA86C25 : 0xFFE1B3) : ink
            draw(40, 3, 4, 4, sun)
            draw(41, 1, 2, 1, sun)
            draw(41, 8, 2, 1, sun)
            draw(37, 4, 2, 2, sun)
            draw(45, 4, 2, 2, sun)
            for (x, y) in [(38, 2), (45, 2), (38, 7), (45, 7)] {
                draw(x, y, 1, 1, sun)
            }
            let flight = tick % 156
            if animated && (12..<48).contains(flight) {
                let x = flight - 8
                let wing = flight % 4 < 2 ? 0 : 1
                for (offset, y) in [(0, 3), (-4, 5)] {
                    let col = x + offset
                    draw(col + 1, y, 2, 1, ink)
                    draw(col, y - wing, 1, 1, ink)
                    draw(col + 3, y - wing, 1, 1, ink)
                }
            }
        }
    }

    private static func drawPassingFish(tick: Int, ink: Color,
                                        draw: (Int, Int, Int, Int, Color) -> Void) {
        let crossing = (tick + 65) % 156
        guard (8..<51).contains(crossing) else { return }
        let x = 51 - crossing
        for (offset, y) in [(0, 13), (5, 16)] where x + offset < 44 {
            let col = x + offset
            draw(col, y, 3, 2, ink)
            draw(col + 3, y + crossing % 2, 1, 1, ink)
        }
    }

    private static func spriteStride(effect: HabitatEffect?, activity: HabitatActivity, mood: PetMood?,
                                     tick: Int, wave: Double, moving: Bool) -> Int {
        guard moving, effect != .rest, mood != .sleeping else { return 0 }
        if effect == .run { return Int(wave * 5) }
        if effect == .exercise || effect == .swim { return Int(wave * 3) }
        if effect == .bathroom || mood == .urgent || mood == .irritated || mood == .annoyed || effect == .annoyed { return tick.isMultiple(of: 2) ? 1 : -1 }
        if effect == .feed { return 2 }
        if activity == .training { return [0, 2, 4, 2, 0, -2, -4, -2][tick % 8] }
        return 0
    }

    private static func spriteBob(effect: HabitatEffect?, mood: PetMood?, tick: Int,
                                  wave: Double, progress: Double, moving: Bool) -> Int {
        guard moving else { return 0 }
        if effect == .rest || mood == .sleeping { return -2 }
        if effect == .weigh || mood == .sleepy || mood == .sick { return 0 }
        if effect == .hop || effect == .toss { return Int(sin(progress * .pi) * 5) }
        if effect == .dive || effect == .bath || effect == .bathroom { return -Int(abs(wave) * 3) }
        if effect == .pushUps { return -Int(abs(wave) * 3) }
        if effect == .exercise || effect == .run || effect == .swim || effect == .wake || effect == .vaccine {
            return Int(abs(wave) * 3)
        }
        return tick % 8 < 4 ? 1 : 0
    }

    private static func drawMood(_ mood: PetMood, tick: Int, color: Color,
                                 draw: (Int, Int, Int, Int, Color) -> Void) {
        let x = 39
        let pulse = tick % 8 < 4 ? 0 : 1
        switch mood {
        case .happy:
            draw(x, 12, 4, 2, color)
            draw(x + 1, 14, 2, 1, color)
        case .hungry:
            draw(x - pulse, 12 - pulse, 4, 2, color)
            draw(x + 4 - pulse, 11 - pulse, 1, 4, color)
        case .sleepy:
            draw(x, 10, 4, 1, color)
            draw(x + 1, 11, 2, 1, color)
            draw(x, 12, 4, 1, color)
        case .dirty:
            for index in 0..<3 {
                draw(x + index * 2, 11 + (tick + index * 3) % 7, 1, 2, color)
            }
        case .sick:
            draw(x, 12 - pulse, 5, 1, color)
            draw(x + 2, 10 - pulse, 1, 5, color)
        case .urgent:
            draw(x + 2, 10, 1, 3, color)
            draw(x + 2, 14, 1, 1, color)
        case .sleeping:
            break
        case .irritated, .annoyed:
            draw(x - pulse, 10, 2, 1, color)
            draw(x + 1, 11, 3, 1, color)
            draw(x + 3, 12, 2, 1, color)
            draw(x + 2, 13, 2, 1, color)
        case .bored:
            for index in 0..<3 { draw(x + index * 2, 13, 1, 1, color.opacity(tick % 3 == index ? 0.4 : 1)) }
        }
    }

    private static func drawReaction(_ effect: HabitatEffect, progress: Double, color: Color, accent: Color,
                                     draw: (Int, Int, Int, Int, Color) -> Void) {
        switch effect {
        case .feed:
            for index in 0..<3 { draw(45 - Int(progress * 14) + index * 2, 15 + index * 2, 2, 2, accent) }
        case .rest:
            for index in 0..<2 {
                let row = 12 - Int(progress * 6) + index * 4
                draw(36 + index * 5, row, 3, 1, color)
                draw(37 + index * 5, row + 1, 1, 1, color)
                draw(36 + index * 5, row + 2, 3, 1, color)
            }
        case .bath:
            for index in 0..<7 {
                let col = 9 + index * 5
                let row = 23 - (Int(progress * 16) + index * 3) % 14
                draw(col, row, 2, 2, color.opacity(0.8))
            }
        case .bathroom:
            let waste = Color(rgb: 0x644630)
            let row = 17 + Int(min(1, progress * 2) * 7)
            draw(38, row, 2, 1, waste)
            draw(37, row + 1, 4, 1, waste)
            draw(36, row + 2, 6, 1, waste)
        case .exercise, .swim:
            for index in 0..<4 { draw(36 + index * 2, 19 - Int(progress * 10) + index, 2, 2, color) }
        case .pushUps:
            draw(12, 26, 24, 1, color)
            draw(18, 25, 12, 1, accent)
        case .run:
            for index in 0..<3 { draw(3 + Int(progress * 4), 13 + index * 3, 4 + index, 1, color) }
        case .wake:
            draw(38, 8, 5, 1, color)
            draw(40, 6, 1, 5, color)
        case .pet:
            for index in 0..<3 {
                let col = 11 + index * 11
                let row = 15 - Int(progress * 8) + index % 2 * 3
                draw(col, row, 1, 1, accent)
                draw(col + 2, row, 1, 1, accent)
                draw(col, row + 1, 3, 1, accent)
                draw(col + 1, row + 2, 1, 1, accent)
            }
        case .weigh:
            draw(12, 24, 24, 2, color)
            draw(19, 26, 10, 1, accent)
            draw(21, 25, 1 + Int(progress * 5), 1, accent)
        case .vaccine:
            let x = 40 - Int(progress * 9)
            draw(x, 14, 5, 3, accent)
            draw(x - 3, 15, 3, 1, color)
            draw(x + 5, 15, 2, 1, color)
            draw(x + 7, 13, 1, 5, color)
        case .toss:
            let x = 43 - Int(progress * 28)
            let y = 17 - Int(sin(progress * .pi) * 10)
            draw(x + 1, y, 2, 4, color)
            draw(x, y + 1, 4, 2, accent)
        case .twirl, .hop, .dive:
            for index in 0..<3 {
                let x = 8 + index * 14
                let y = 22 - Int(progress * 10) + index
                draw(x, y, 2, 2, accent)
            }
        case .annoyed:
            Self.drawMood(.annoyed, tick: Int(progress * 24), color: color, draw: draw)
        }
    }

    private static let egg = [
        "...#####...", "..#+++++#..", ".#+++*+++#.", ".#+*+++++#.",
        "#+++++*+++#", "#++*++++++#", ".#+++++++#.", "..#######.."
    ]

    private static let baby = [
        ".*..####.*..", ".**#++++#**.", "..#+o++o+#..", "..#+*++*+#..",
        "...######..*", "....#++####.", "....####...."
    ]

    private static let turtle = [
        ".....######.....",
        "...##+*++*+##...",
        "..#+*++*++*++#..",
        ".##+*++++*+++###",
        "#+++++++++++++o#",
        ".#+++++++++++++#",
        "..####++++####..",
        "...##.####.##..."
    ]

    private static let pufferfish = [
        "....*.*.*.*.....",
        "...########.....",
        ".*#+*++++++##..*",
        ".#++++++o+++#**.",
        "*#++*++++++++###",
        ".#++++++++o+#**.",
        ".*#+*++++++##..*",
        "...########.....",
        "....*.*.*.*....."
    ]

    private static let seahorse = [
        "......*###......",
        ".....*#++###....",
        ".....*#+o+++#...",
        ".....*#++++##...",
        "....*#++###.....",
        "....*#+++#......",
        ".....#+++#......",
        "......#++#.#....",
        "......#+++##....",
        ".......###......"
    ]

    private static let axolotl = [
        ".*...........*..", ".**..#####..**..", "..*##+++++##*...",
        ".**#+++++++#**..", "...#+o+++++o+#..", "...#+*+##+*++#..",
        "....#+++++++#...", ".....##+++###..*", "......#++++###*.",
        ".....##+##+##...", ".....###.###...."
    ]

    private static let memorial = [
        ".....###.....", "....#@@@#....", "...#@@#@@#...", "...#@@#@@#...",
        "...#@@@@@#...", "...#@@@@@#...", "..#########..", ".**.......**."
    ]
}

extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

struct CareMeters: View {
    let life: Life
    var pocketLCD = false

    var body: some View {
        HStack(spacing: 8) {
            meter("Food", icon: "fish", value: life.food, tint: Color(rgb: pocketLCD ? 0x705325 : 0xEFB96D))
            meter("Mood", icon: "sparkle", value: life.joy, tint: Color(rgb: pocketLCD ? 0x794057 : 0xF59CC5))
            meter("Energy", icon: "moon.fill", value: life.energy, tint: Color(rgb: pocketLCD ? 0x315F55 : 0x91DED2))
            meter("Strength", icon: "bolt.fill", value: life.wellness.strength, tint: Color(rgb: pocketLCD ? 0x49622F : 0xB8DE94))
        }
    }

    private func meter(_ label: String, icon: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                Text("\(Int(value))").monospacedDigit()
            }
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            GeometryReader { proxy in
                Rectangle().fill(tint.opacity(0.22))
                Rectangle().fill(tint).frame(width: proxy.size.width * value / 100)
            }
            .frame(height: 3)
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value)) percent")
    }
}

struct EventRows: View {
    let life: Life

    var body: some View {
        ForEach(life.events.reversed()) { event in
            VStack(alignment: .leading, spacing: 3) {
                Text(event.displayTitle).font(.headline)
                Text(event.localDate).font(.caption).monospacedDigit()
                Text(event.zoneID).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}

struct PetCareView: View {
    let life: Life
    var busy = false
    let apply: (Care, @escaping (String?) -> Void) -> Void
    @State private var feedback = ""
    @State private var confirmingWake = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Care").font(.headline)
            CareMeters(life: life)
            HStack {
                careButton(.feed)
                careButton(life.isSleeping ? .wake : .rest)
            }
            HStack {
                careButton(.bath)
                careButton(.bathroom)
            }
            if let wake = life.sleep?.endsAt {
                Label("Asleep · wakes \(wake, style: .relative)", systemImage: "moon.zzz")
                    .font(.caption)
            } else if life.isIrritable {
                Label("Needs eight uninterrupted hours of sleep", systemImage: "exclamationmark.circle")
                    .font(.caption)
            }
            ScalePanel(life: life)
            WellnessPanel(life: life, busy: busy) { action, completion in
                apply(action) { result in
                    feedback = result ?? "Open Ajoló on both devices and try again."
                    completion?(result)
                }
            }
            if !feedback.isEmpty {
                Text(feedback).font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Wake your pet early?", isPresented: $confirmingWake, titleVisibility: .visible) {
            Button("Wake early", role: .destructive) { submit(.wake) }
            Button("Keep sleeping", role: .cancel) {}
        } message: {
            Text("Only eight uninterrupted hours count toward a full sleep.")
        }
    }

    private func submit(_ action: Care) {
        apply(action) { feedback = $0 ?? "Open Ajoló on both devices and try again." }
    }

    private func careButton(_ action: Care) -> some View {
        Button {
            if action == .wake { confirmingWake = true } else { submit(action) }
        } label: {
            Label(action.label, systemImage: action.icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .font(.caption2)
        .disabled(busy || (life.isSleeping && action != .wake))
    }
}

struct ScalePanel: View {
    let life: Life

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Scale", systemImage: "scalemass")
                Spacer()
                Text("\(life.weight.formatted(.number.precision(.fractionLength(1)))) g")
                    .monospacedDigit()
            }
            .font(.headline)
            Text("Typical for this age: \(Int(life.referenceWeight.rounded())) g")
                .font(.caption2).foregroundStyle(.secondary)
            Label("Cleanliness \(Int(life.hygiene.cleanliness))%", systemImage: "drop")
                .font(.caption2)
            ProgressView(value: life.hygiene.cleanliness, total: 100).tint(.mint)
            Label("Bathroom need \(Int(life.hygiene.bathroomNeed))%", systemImage: "toilet")
                .font(.caption2)
            ProgressView(value: life.hygiene.bathroomNeed, total: 100)
                .tint(life.hygiene.bathroomNeed >= 80 ? .orange : .cyan)
        }
        .padding(8)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct WellnessPanel: View {
    let life: Life
    var busy = false
    let apply: (Care, ((String?) -> Void)?) -> Void
    @State private var choosingWorkout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let deadline = life.wellness.feverDeadline {
                Label("Bubble fever · treat before \(deadline, style: .relative)", systemImage: "cross.case.fill")
                    .font(.caption).foregroundStyle(Color(rgb: 0xF5B486))
            } else if let recovery = life.wellness.recoveryAt {
                Label("Recovery \(recovery, style: .relative)", systemImage: "cross.case.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if life.wellness.protected(at: life.updated) {
                Label("Vaccine protection active", systemImage: "checkmark.shield")
                    .font(.caption)
            } else {
                Label("Daily risk · \(Int(life.wellness.dailyRisk.rounded()))%", systemImage: "heart")
                    .font(.caption)
            }

            Text("Food use · \(life.wellness.foodPerHour.formatted(.number.precision(.fractionLength(1)))) per hour")
                .font(.caption2)
            Text("Extra weight · \(Int(life.pantry.excessWeight.rounded()))/100")
                .font(.caption2)
            HStack {
                Button { choosingWorkout = true } label: {
                    Label(Care.exercise.label, systemImage: Care.exercise.icon)
                }
                .disabled(busy || life.isSick || life.isSleeping)
                Button { apply(.vaccine, nil) } label: {
                    Label(Care.vaccine.label, systemImage: Care.vaccine.icon)
                }
                .disabled(busy || (!life.isSick && life.wellness.protected(at: life.updated)))
            }
            .font(.caption2)
            .buttonStyle(.bordered)

            Text("Pantry").font(.caption.bold())
            ForEach([Care.nutritious, .junk], id: \.self) { treat in
                let count = treat == .nutritious ? life.pantry.nutritious : life.pantry.junk
                Button { apply(treat, nil) } label: {
                    Label("\(treat.label) · \(count)", systemImage: treat.icon)
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .disabled(busy || count == 0 || life.isSleeping)
            }
        }
        .confirmationDialog("Choose a workout", isPresented: $choosingWorkout, titleVisibility: .visible) {
            ForEach(Care.workouts, id: \.self) { action in
                Button(action.label) { apply(action, nil) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

enum PlayAvailability: Equatable {
    case ready, noPet, incubating, sick, sleeping, ended

    var message: String? {
        switch self {
        case .ready: return nil
        case .noPet: return "Start an egg on iPhone and sync your watch to unlock games."
        case .incubating: return "Games unlock when your egg hatches."
        case .sick: return "Let your axolotl recover before playing."
        case .sleeping: return "Games unlock when your pet wakes up."
        case .ended: return "Start your next egg on iPhone to play again."
        }
    }
}

extension Life {
    var playAvailability: PlayAvailability {
        if stage == .egg { return .incubating }
        if stage == .deceased { return .ended }
        if isSleeping { return .sleeping }
        return isSick ? .sick : .ready
    }
}

private enum PondGame: String, CaseIterable, Identifiable {
    case bubbles = "Bubbles", memory = "Echoes", shell = "Shells"
    var id: Self { self }

    var icon: String {
        switch self {
        case .bubbles: return "circle.dotted"
        case .memory: return "music.note"
        case .shell: return "sparkle.magnifyingglass"
        }
    }

    var instructions: String {
        switch self {
        case .bubbles: return "Pop numbered bubbles in order. The pattern changes each round."
        case .memory: return "Repeat the sequence. Each round adds another symbol."
        case .shell: return "Find the shell in three guesses. Distance clues help you narrow it down."
        }
    }
}

struct PlayRoom: View {
    var availability: PlayAvailability
    var note: String? = nil
    var life: Life? = nil
    let reward: (Care, @escaping (String?) -> Void) -> Void

    var body: some View {
        List {
            if let message = availability.message {
                Label(message, systemImage: "lock").font(.footnote)
            } else {
                if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                if let life {
                    NavigationLink {
                        AjoloMoves(life: life, available: availability == .ready, reward: reward)
                    } label: {
                        Label("Ajoló Says", systemImage: "figure.play").font(.headline)
                    }
                }
                ForEach(PondGame.allCases) { game in
                    NavigationLink {
                        if availability == .ready {
                            PondRound(game: game, reward: reward)
                        } else {
                            Text(availability.message ?? "Games are unavailable.")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(game.rawValue, systemImage: game.icon).font(.headline)
                            #if os(iOS)
                            Text(game.instructions).font(.caption).foregroundStyle(.secondary)
                            #endif
                        }
                    }
                }
            }
        }
        .navigationTitle("Play")
    }
}

private struct AjoloMoves: View {
    private enum Cue: CaseIterable {
        case toss, twirl, hop, dive

        var title: String {
            switch self {
            case .toss: return "Tap to toss the ball"
            case .twirl:
                #if os(watchOS)
                return "Turn the Digital Crown"
                #else
                return "Tap Spin to twirl"
                #endif
            case .hop: return "Swipe up to jump"
            case .dive: return "Swipe down to dive"
            }
        }

        var effect: HabitatEffect {
            switch self {
            case .toss: return .toss
            case .twirl: return .twirl
            case .hop: return .hop
            case .dive: return .dive
            }
        }
    }

    let life: Life
    let available: Bool
    let reward: (Care, @escaping (String?) -> Void) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ajoloInteractive) private var interactive
    @State private var cues = Cue.allCases.shuffled()
    @State private var step = 0
    @State private var reaction: HabitatReaction?
    @State private var hint: String?
    @State private var result: String?
    @State private var collecting = false
    @State private var collected = false
    #if os(watchOS)
    @State private var crown = 0.0
    @FocusState private var crownFocused: Bool
    #endif

    var body: some View {
        VStack(spacing: 5) {
            Text(step == cues.count ? "Nice teamwork!" : "\(step + 1) / \(cues.count)")
                .font(.caption.monospacedDigit())
            #if os(watchOS)
            playfield
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation($crown, from: -20, through: 20, by: 1,
                                      sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true)
                .onChange(of: crown) { _ in
                    if step < cues.count, cues[step] == .twirl { perform(.twirl) }
                }
                .onAppear { crownFocused = true }
            #else
            playfield
            #endif
            if step < cues.count {
                Text(available ? (hint ?? cues[step].title) : "Your pet needs a break.")
                    .font(.caption.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
                #if os(iOS)
                if cues[step] == .twirl {
                    Button("Spin") { perform(.twirl) }.buttonStyle(.bordered)
                }
                #endif
            } else {
                if let result {
                    Text(result).font(.caption).multilineTextAlignment(.center)
                }
                if !collected {
                    Button(collecting ? "Saving…" : "Collect reward") {
                        collecting = true
                        reward(.play) { message in
                            collecting = false
                            collected = message != nil
                            result = message ?? "Open Ajoló on Apple Watch to try again."
                        }
                    }
                    .disabled(collecting || !available || reaction != nil)
                }
            }
        }
        .padding(.horizontal, 4)
        .navigationTitle("Ajoló Says")
        .task(id: interactive ? reaction?.id : nil) {
            guard interactive, let reaction else { return }
            let remaining = max(0, reaction.duration - Date().timeIntervalSince(reaction.started))
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            if self.reaction?.id == reaction.id { self.reaction = nil }
        }
    }

    private var playfield: some View {
        PixelScene(stage: life.stage, night: false, color: true, tired: false,
                   animated: !reduceMotion, excessWeight: life.pantry.excessWeight, traits: life.traits,
                   species: life.kind, morph: life.bodyType, pocketLCD: true, reaction: reaction)
            .aspectRatio(48.0 / 28, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(false)
            .accessibilityLabel("Play with \(life.name)")
            .accessibilityAction(named: Text("Toss the ball")) { perform(.toss) }
            .accessibilityAction(named: Text("Twirl")) { perform(.twirl) }
            .accessibilityAction(named: Text("Jump")) { perform(.hop) }
            .accessibilityAction(named: Text("Dive")) { perform(.dive) }
            .contentShape(Rectangle())
            .onTapGesture { perform(.toss) }
            .gesture(DragGesture(minimumDistance: 14).onEnded { gesture in
                guard abs(gesture.translation.height) > abs(gesture.translation.width) else { return }
                perform(gesture.translation.height < 0 ? .hop : .dive)
            })
    }

    private func perform(_ cue: Cue) {
        guard interactive, available, reaction == nil, step < cues.count else { return }
        guard cues[step] == cue else {
            hint = "Try again: \(cues[step].title)"
            return
        }
        hint = nil
        reaction = HabitatReaction(effect: cue.effect, duration: 1)
        step += 1
    }
}

private struct PondRound: View {
    let game: PondGame
    let reward: (Care, @escaping (String?) -> Void) -> Void

    @State private var level = 1
    @State private var bubbles = Array(1...4).shuffled()
    @State private var step = 0
    @State private var sequence = (0..<3).shuffled()
    @State private var showingSequence = true
    @State private var stones = Set<Int>()
    @State private var hiddenShell = Int.random(in: 0..<6)
    #if os(watchOS)
    @State private var stoneSelection = 0.0
    #endif
    @State private var hint = ""
    @State private var collecting = false
    @State private var result: String?
    @State private var earned = false

    private let figures = ["heart.fill", "star.fill", "moon.fill"]
    private let names = ["Heart", "Star", "Moon"]
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 3) }

    private var targetHeight: CGFloat {
        #if os(iOS)
        return 54
        #else
        return 30
        #endif
    }

    private var bubbleOrder: [Int] {
        switch level {
        case 1: return [1, 2, 3, 4]
        case 2: return [5, 4, 3, 2, 1]
        default: return [1, 6, 2, 5, 3, 4]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                if level > 3 {
                    Label("Game complete!", systemImage: "sparkles").font(.headline)
                    if !earned {
                        rewardButton("Healthy snack", action: .play)
                        rewardButton("Sweet treat", action: .playJunk)
                    }
                    if let result { Text(result).font(.caption) }
                } else {
                    Text("Round \(level) of 3").font(.caption2.bold()).foregroundStyle(.secondary)
                    switch game {
                    case .bubbles: bubbleGrid
                    case .memory: memoryGame
                    case .shell: shellGame
                    }
                    if !hint.isEmpty { Text(hint).font(.caption2).foregroundStyle(.secondary) }
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(game.rawValue)
    }

    private func nextRound() {
        level += 1
        step = 0
        hint = ""
        if level <= 3 {
            bubbles = Array(1...(level + 3)).shuffled()
            sequence.append((0..<3).filter { $0 != sequence.last }.randomElement() ?? 0)
            showingSequence = true
            stones.removeAll()
            hiddenShell = Int.random(in: 0..<6)
        }
    }

    private func rewardButton(_ title: String, action: Care) -> some View {
        Button(collecting ? "Saving…" : title) {
            guard !collecting, !earned else { return }
            collecting = true
            reward(action) { message in
                collecting = false
                earned = message != nil
                result = message ?? "Open Ajoló on your watch and try again."
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(collecting)
    }

    private var bubbleGrid: some View {
        VStack(spacing: 5) {
            if level == 1 {
                Text("Pop \(bubbleOrder[min(step, bubbleOrder.count - 1)]) next").font(.caption)
            } else {
                Text(level == 2 ? "Highest to lowest" : "Alternate lowest, highest").font(.caption)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(bubbles, id: \.self) { number in
                    let popped = bubbleOrder.prefix(step).contains(number)
                    Button {
                        guard level <= 3, bubbleOrder.indices.contains(step) else { return }
                        if number == bubbleOrder[step] {
                            step += 1
                            hint = ""
                            if step == bubbles.count { nextRound() }
                        } else {
                            hint = "Try the next number in the pattern."
                        }
                    } label: {
                        Text(popped ? "✓" : String(number))
                            .frame(maxWidth: .infinity, minHeight: targetHeight)
                    }
                    .buttonStyle(.bordered)
                    .disabled(popped)
                    .accessibilityLabel("Bubble \(number)")
                }
            }
        }
    }

    private var memoryGame: some View {
        VStack(spacing: 7) {
            if showingSequence {
                HStack(spacing: 7) {
                    ForEach(sequence.indices, id: \.self) { index in
                        Image(systemName: figures[sequence[index]]).accessibilityLabel(names[sequence[index]])
                    }
                }
                Button("Ready") { hint = ""; showingSequence = false }
            } else {
                Text("\(step) of \(sequence.count)").font(.caption)
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Button {
                            guard level <= 3, sequence.indices.contains(step) else { return }
                            if sequence[step] == index {
                                step += 1
                                if step == sequence.count { nextRound() }
                            } else {
                                step = 0
                                showingSequence = true
                                hint = "Look at the sequence and try again."
                            }
                        } label: {
                            Image(systemName: figures[index]).frame(minHeight: targetHeight)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(names[index])
                    }
                }
            }
        }
    }

    private var shellGame: some View {
        VStack(spacing: 5) {
            if level == 1 { Text(hiddenShell < 3 ? "Look in the top row." : "Look in the bottom row.").font(.caption2) }
            Text("\((level == 3 ? 2 : 3) - stones.count) guesses left").font(.caption)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<6) { index in
                    Button { lift(index) } label: {
                        Image(systemName: stones.contains(index) ? "minus" : "seal.fill")
                            .frame(maxWidth: .infinity, minHeight: targetHeight)
                    }
                    .buttonStyle(.bordered)
                    .tint(stoneTint(index))
                    .disabled(stones.contains(index))
                    .accessibilityLabel("Stone \(index + 1)")
                }
            }
            #if os(watchOS)
            Button("Lift \(Int(stoneSelection) + 1)") { lift(Int(stoneSelection)) }
                .focusable()
                .digitalCrownRotation($stoneSelection, from: 0, through: 5, by: 1,
                                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .disabled(stones.contains(Int(stoneSelection)))
            #endif
        }
    }

    private func stoneTint(_ index: Int) -> Color {
        #if os(watchOS)
        if index == Int(stoneSelection) { return Color(rgb: 0xF2C675) }
        #endif
        return .accentColor
    }

    private func lift(_ index: Int) {
        guard level <= 3, (0..<6).contains(index), !stones.contains(index) else { return }
        if index == hiddenShell {
            nextRound()
        } else {
            stones.insert(index)
            let distance = abs(index / 3 - hiddenShell / 3) + abs(index % 3 - hiddenShell % 3)
            if stones.count >= (level == 3 ? 2 : 3) {
                stones.removeAll()
                hiddenShell = Int.random(in: 0..<6)
                hint = "New hiding spot. Try again!"
            } else {
                hint = "The shell is \(distance) spaces away."
            }
        }
    }
}

struct LineageCard: View {
    let life: Life

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Generation \(life.generation ?? 1) · \(life.name)").font(.headline)
            Text("\(life.kind.label) · \(life.bodyType.size.label) · \(life.bodyType.shape.label)")
            if let origin = life.origin {
                Text("Parents · \(origin.parentNames?.joined(separator: " and ") ?? origin.partnerName)")
            }
            Text("\(life.day) days · \(life.totals.games) games · \(life.totals.workouts) workouts")
            if life.stage == .deceased, let death = life.events.last(where: { $0.displayTitle.hasPrefix("Passed away") }) {
                Text(death.displayTitle)
            }
        }
        .font(.caption2)
    }
}

struct LineageAlbum: View {
    let journal: Journal

    var body: some View {
        List {
            Section("Family tree") {
                ForEach(journal.lives) { life in
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                PixelScene(stage: life.stage == .deceased ? .adult : life.stage,
                                           night: false, color: true, tired: false, animated: false, traits: life.traits,
                                           species: life.kind, morph: life.bodyType)
                                    .frame(height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                LineageCard(life: life)
                                EventRows(life: life)
                            }
                            .padding()
                        }
                        .navigationTitle(life.name)
                    } label: {
                        LineageCard(life: life)
                    }
                }
            }
            if journal.hasFamily {
                Section("Keepsakes") {
                    Label("First meeting · Shell frame", systemImage: "heart")
                    if journal.hasThreeGenerations {
                        Label("Three generations · Coral background", systemImage: "tree")
                    }
                    if journal.lives.contains(where: { $0.traits.markings == 3 }) {
                        Label("Star marking · Family badge", systemImage: "star")
                    }
                }
            }
        }
        .navigationTitle("Family album")
    }
}
