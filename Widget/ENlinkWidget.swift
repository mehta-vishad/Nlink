//
//  ENlinkWidget.swift
//  ENlink
//
//  The ENlink home screen widget (work order Phase 5): the car, its odometer,
//  fuel and lock state, a last-updated time, and lock / unlock / climate
//  buttons, on a dark glass card. systemMedium only.
//

import AppIntents
import BetterBlueKit
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Widget

struct ENlinkWidget: Widget {
    let kind = "ENlinkWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ENlinkWidgetIntent.self, provider: ENlinkTimelineProvider()) { entry in
            ENlinkWidgetView(entry: entry)
        }
        .configurationDisplayName("ENlink")
        .description("Your car at a glance, with lock, unlock and climate.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct ENlinkWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "ENlink"
    static let description = IntentDescription("Choose which car the widget shows.")

    @Parameter(title: "Vehicle", description: "Leave unset to follow your primary car")
    var vehicle: VehicleEntity?
}

// MARK: - Timeline

struct ENlinkEntry: TimelineEntry {
    let date: Date
    let vehicle: VehicleEntity?
}

struct ENlinkTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> ENlinkEntry {
        ENlinkEntry(date: .now, vehicle: .enlinkSample)
    }

    func snapshot(for configuration: ENlinkWidgetIntent, in _: Context) async -> ENlinkEntry {
        if let vehicle = configuration.vehicle {
            return ENlinkEntry(date: .now, vehicle: vehicle)
        }
        return ENlinkEntry(date: .now, vehicle: await VehicleQuery().defaultResult() ?? .enlinkSample)
    }

    func timeline(for configuration: ENlinkWidgetIntent, in _: Context) async -> Timeline<ENlinkEntry> {
        let refreshInterval = await MainActor.run { AppSettings.shared.widgetRefreshInterval.timeInterval }
        let vehicle = await VehicleTimelineProvider.loadVehicle(configuration.vehicle)
        let now = Date()

        // A second entry flips the card to its stale styling on time, even if
        // no refresh has happened by then.
        var entries = [ENlinkEntry(date: now, vehicle: vehicle)]
        if let updated = vehicle?.lastUpdated {
            let staleAt = updated.addingTimeInterval(ENlinkStyle.staleAfter)
            if staleAt > now, staleAt < now.addingTimeInterval(refreshInterval) {
                entries.append(ENlinkEntry(date: staleAt, vehicle: vehicle))
            }
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(refreshInterval)))
    }
}

// MARK: - Style

enum ENlinkStyle {
    /// Performance Blue as it reads on the car image's body panels.
    static let paint = Color(red: 0.502, green: 0.678, blue: 0.839)
    static let paintLight = Color(red: 0.702, green: 0.839, blue: 0.949)
    static let night = Color(red: 0.106, green: 0.145, blue: 0.196)
    static let ink = Color(red: 0.027, green: 0.035, blue: 0.055)
    static let unlocked = Color(red: 1.0, green: 0.690, blue: 0.290)

    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)

    /// Status older than this is flagged as stale (work order Phase 5).
    static let staleAfter: TimeInterval = 6 * 3600
    /// How long a widget-button command shows as "sent" before the status
    /// refresh that should confirm it. Phase 6 retunes this from the
    /// latencies measured in Phase 2.
    static let pendingWindow: TimeInterval = 30 * 60
}

/// The car image. A locally generated `ElantraNLocal` — git-ignored, because it
/// is a manufacturer render used privately on the owner's phone — wins over the
/// committed CC BY-SA `ElantraN`, so the public repo always builds and only
/// ever ships a licensed image. Either faces left, toward the text column.
enum ENlinkCarArt {
    static let name: String = UIImage(named: "ElantraNLocal") != nil ? "ElantraNLocal" : "ElantraN"

    static let aspectRatio: CGFloat = {
        guard let size = UIImage(named: name)?.size, size.height > 0 else { return 660.0 / 324.0 }
        return size.width / size.height
    }()
}

// MARK: - Views

struct ENlinkWidgetView: View {
    let entry: ENlinkEntry

    var body: some View {
        Group {
            if let vehicle = entry.vehicle {
                ENlinkCard(vehicle: vehicle, now: entry.date)
            } else {
                ENlinkEmptyCard()
            }
        }
        .containerBackground(for: .widget) { ENlinkBackground() }
    }
}

/// Frosted glass over the car's own colors: a heavily blurred copy of the
/// photo tints a deep night-blue base, the text side is darkened for contrast,
/// and a sheen plus a light-catching rim give the card its glass edge. Only
/// drawn in full-color mode; on Tinted/Clear home screens the system supplies
/// its own glass in place of the container background.
struct ENlinkBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ENlinkStyle.night, ENlinkStyle.ink],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            GeometryReader { geo in
                Image(ENlinkCarArt.name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width * 0.95, height: geo.size.height * 1.3)
                    .offset(x: geo.size.width * 0.20, y: -geo.size.height * 0.05)
                    .blur(radius: 30)
                    .opacity(0.50)
            }
            LinearGradient(
                stops: [
                    .init(color: ENlinkStyle.ink.opacity(0.72), location: 0.25),
                    .init(color: ENlinkStyle.ink.opacity(0.08), location: 0.68)
                ],
                startPoint: .leading, endPoint: .trailing
            )
            RadialGradient(
                colors: [ENlinkStyle.paintLight.opacity(0.28), ENlinkStyle.paint.opacity(0)],
                center: UnitPoint(x: 0.72, y: 1.0), startRadius: 2, endRadius: 150
            )
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.13), location: 0),
                    .init(color: .white.opacity(0.03), location: 0.40),
                    .init(color: .clear, location: 0.58)
                ],
                startPoint: .top, endPoint: .bottom
            )
            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.06), .white.opacity(0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

struct ENlinkCard: View {
    let vehicle: VehicleEntity
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let car = ENlinkCar.size(in: geo.size)

            ZStack(alignment: .topLeading) {
                ENlinkCar(size: car)
                    .offset(x: width - car.width - width * 0.025, y: height - car.height - 10)

                ENlinkInfoColumn(vehicle: vehicle, now: now)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .padding(.leading, 16)
                    .frame(width: width * 0.47, height: height, alignment: .topLeading)

                ENlinkLockPill(isLocked: vehicle.isLocked)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                    .frame(width: width, alignment: .topTrailing)
            }
        }
    }
}

/// The car on a soft floor shadow. Kept in full color in accented mode: the
/// point of the image is that it matches the real paint.
struct ENlinkCar: View {
    /// The largest size that fits the car's slot: at most 57% of the card's
    /// width — so the nose stops short of the text column and its buttons —
    /// and 64% of its height, whichever binds first for this image's
    /// proportions (a three-quarter photo is height-bound, a side profile
    /// width-bound).
    static func size(in card: CGSize) -> CGSize {
        let ratio = ENlinkCarArt.aspectRatio
        let width = min(card.width * 0.57, card.height * 0.64 * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    let size: CGSize
    var opacity: Double = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(.black.opacity(0.65))
                .frame(width: size.width * 0.86, height: min(size.width * 0.07, size.height * 0.16))
                .blur(radius: 7)
                .offset(x: size.width * 0.02, y: -size.height * 0.01)
            Image(ENlinkCarArt.name)
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(.fullColor)
                .aspectRatio(contentMode: .fit)
                .opacity(opacity)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityLabel("Car")
    }
}

struct ENlinkInfoColumn: View {
    let vehicle: VehicleEntity
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(modelName)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.3)
                .foregroundStyle(ENlinkStyle.secondaryText)

            odometer
                .padding(.top, 3)

            fuel
                .padding(.top, 6)

            status
                .padding(.top, 6)

            Spacer(minLength: 4)

            ENlinkButtons(vehicle: vehicle)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private var modelName: String {
        let words = vehicle.displayName.split(separator: " ")
        if let first = words.first, first.count == 4, Int(first) != nil, words.count > 1 {
            return words.dropFirst().joined(separator: " ")
        }
        return vehicle.displayName
    }

    @ViewBuilder
    private var odometer: some View {
        if let value = vehicle.odometerValue {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Int(value.rounded()).formatted(.number))
                    .font(.system(size: 27, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(ENlinkStyle.primaryText)
                    .widgetAccentable()
                Text(vehicle.odometerUnit.abbreviation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ENlinkStyle.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Odometer \(Int(value.rounded())) \(vehicle.odometerUnit.displayName)")
        } else {
            Text("— mi")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(ENlinkStyle.tertiaryText)
        }
    }

    private var fuelPercent: Double? {
        vehicle.fuelType.hasElectricCapability ? vehicle.evBatteryPercentage : vehicle.gasFuelPercentage
    }

    private var rangeText: String? {
        vehicle.fuelType.hasElectricCapability ? vehicle.evRange : vehicle.gasRange
    }

    private var fuel: some View {
        HStack(spacing: 6) {
            ENlinkGauge(fraction: (fuelPercent ?? 0) / 100)
                .frame(width: 44, height: 5)
            Text(fuelPercent.map { "\(Int($0.rounded()))%" } ?? "—")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ENlinkStyle.primaryText)
            if let rangeText {
                Text(rangeText)
                    .font(.system(size: 11, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(ENlinkStyle.secondaryText)
            }
        }
    }

    /// Freshness, or the in-flight command while one is pending.
    @ViewBuilder
    private var status: some View {
        HStack(spacing: 4) {
            if let pending = pendingCommand {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(ENlinkStyle.paintLight)
                Text("\(pending.command) sent \(time(pending.date))")
                    .foregroundStyle(ENlinkStyle.secondaryText)
            } else {
                if isStale {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .foregroundStyle(ENlinkStyle.unlocked)
                    Text(time(vehicle.timestamp))
                        .foregroundStyle(ENlinkStyle.unlocked)
                } else {
                    Text("Updated \(time(vehicle.timestamp))")
                        .foregroundStyle(ENlinkStyle.tertiaryText)
                }
            }
        }
        .font(.system(size: 10, weight: .medium))
        .monospacedDigit()
    }

    private var isStale: Bool {
        now.timeIntervalSince(vehicle.lastUpdated ?? vehicle.timestamp) >= ENlinkStyle.staleAfter
    }

    /// A widget-button command newer than the last status refresh, while it
    /// is still recent enough to be in flight.
    private var pendingCommand: (command: String, date: Date)? {
        guard let latest = WidgetCommandStatus.latest(vin: vehicle.vin) else { return nil }
        guard latest.date > (vehicle.lastUpdated ?? .distantPast),
              now.timeIntervalSince(latest.date) < ENlinkStyle.pendingWindow else { return nil }
        return latest
    }

    private func time(_ date: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Lock state as a small glass capsule in the card's top-right corner.
struct ENlinkLockPill: View {
    let isLocked: Bool?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isLocked == false ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 9, weight: .bold))
            Text(isLocked == nil ? "Unknown" : isLocked == true ? "Locked" : "Unlocked")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(isLocked == false ? ENlinkStyle.unlocked : ENlinkStyle.primaryText)
        .widgetAccentable(isLocked == false)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.white.opacity(0.12)))
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.50), .white.opacity(0.06), .white.opacity(0.22)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
        }
        .accessibilityLabel(isLocked == nil ? "Lock state unknown" : isLocked == true ? "Locked" : "Unlocked")
    }
}

/// Thin glass capsule filled with Performance Blue.
struct ENlinkGauge: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(
                        colors: [ENlinkStyle.paint, ENlinkStyle.paintLight],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * min(max(fraction, 0), 1))
                    .widgetAccentable()
            }
        }
    }
}

struct ENlinkButtons: View {
    let vehicle: VehicleEntity

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: lockIntent) {
                ENlinkGlassButton(symbol: "lock.fill", active: vehicle.isLocked == true)
            }
            .accessibilityLabel("Lock")

            Button(intent: unlockIntent) {
                ENlinkGlassButton(symbol: "lock.open.fill", active: vehicle.isLocked == false,
                                  tint: ENlinkStyle.unlocked)
            }
            .accessibilityLabel("Unlock")

            climateButton
        }
        .buttonStyle(.plain)
    }

    private var lockIntent: LockVehicleControlIntent {
        let intent = LockVehicleControlIntent()
        intent.vehicle = vehicle
        return intent
    }

    private var unlockIntent: UnlockVehicleControlIntent {
        let intent = UnlockVehicleControlIntent()
        intent.vehicle = vehicle
        return intent
    }

    /// One button that starts climate with the selected preset, or stops it
    /// while it is running.
    @ViewBuilder
    private var climateButton: some View {
        if vehicle.isClimateOn == true {
            let intent = StopClimateControlIntent()
            let _ = intent.vehicle = vehicle
            Button(intent: intent) {
                ENlinkGlassButton(symbol: "fan.fill", active: true)
            }
            .accessibilityLabel("Stop climate")
        } else {
            let intent = StartClimateControlIntent()
            let _ = intent.preset = vehicle.selectedPreset
            Button(intent: intent) {
                ENlinkGlassButton(symbol: "fan.fill", active: false)
            }
            .accessibilityLabel("Start climate")
        }
    }
}

/// A glass bead: translucent body, a top specular highlight and a rim that
/// catches light from the upper left. `active` fills it with the tint to show
/// the car's current state.
///
/// On Clear and Tinted home screens the system draws everything in one tint,
/// so a dark icon on a filled bead would vanish; there the active bead is a
/// brighter glass disc and the icon carries the accent instead.
struct ENlinkGlassButton: View {
    let symbol: String
    var active = false
    var tint: Color = ENlinkStyle.paint

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var fullColor: Bool { renderingMode == .fullColor }

    private var fill: AnyShapeStyle {
        if fullColor {
            return active ? AnyShapeStyle(tint.opacity(0.92)) : AnyShapeStyle(.white.opacity(0.10))
        }
        return AnyShapeStyle(.white.opacity(active ? 0.36 : 0.12))
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active && fullColor ? ENlinkStyle.ink : ENlinkStyle.primaryText)
            .widgetAccentable(active && !fullColor)
            .frame(width: 34, height: 34)
            .background {
                Circle().fill(fill)
            }
            .overlay {
                Circle()
                    .fill(LinearGradient(
                        colors: [.white.opacity(active ? 0.35 : 0.22), .white.opacity(0)],
                        startPoint: .top, endPoint: .center
                    ))
                    .padding(1.5)
                    .allowsHitTesting(false)
            }
            .overlay {
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.60), .white.opacity(0.08), .white.opacity(0.28)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

struct ENlinkEmptyCard: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                let car = ENlinkCar.size(in: geo.size)
                ENlinkCar(size: car, opacity: 0.35)
                    .offset(x: geo.size.width - car.width - geo.size.width * 0.025,
                            y: geo.size.height - car.height - 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Elantra N")
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.3)
                        .foregroundStyle(ENlinkStyle.secondaryText)
                    Text("No car yet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ENlinkStyle.primaryText)
                    Text("Open the app and add your Bluelink account.")
                        .font(.system(size: 11))
                        .foregroundStyle(ENlinkStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)
                .padding(.leading, 16)
                .frame(width: geo.size.width * 0.47, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Sample data

extension VehicleEntity {
    /// Gallery and preview stand-in when no account is set up.
    static var enlinkSample: VehicleEntity {
        let vehicle = VehicleEntity(
            id: UUID(uuidString: "5E1A0000-0000-4000-8000-000000000001")!,
            displayName: "2025 ELANTRA N",
            vin: "sample",
            fuelType: .gas,
            rangeText: "280 mi",
            batteryPercentage: 62,
            timestamp: .now
        )
        var sample = vehicle
        sample.gasRange = "280 mi"
        sample.gasFuelPercentage = 62
        sample.isLocked = true
        sample.isClimateOn = false
        sample.lastUpdated = .now
        sample.odometerValue = 11071
        return sample
    }
}

// MARK: - Previews

#Preview("Locked", as: .systemMedium) {
    ENlinkWidget()
} timeline: {
    ENlinkEntry(date: .now, vehicle: .enlinkSample)
}

#Preview("Unlocked, stale", as: .systemMedium) {
    ENlinkWidget()
} timeline: {
    var vehicle = VehicleEntity.enlinkSample
    let _ = vehicle.isLocked = false
    let _ = vehicle.lastUpdated = Date.now.addingTimeInterval(-7 * 3600)
    let _ = vehicle.timestamp = Date.now.addingTimeInterval(-7 * 3600)
    ENlinkEntry(date: .now, vehicle: vehicle)
}

#Preview("No car", as: .systemMedium) {
    ENlinkWidget()
} timeline: {
    ENlinkEntry(date: .now, vehicle: nil)
}
