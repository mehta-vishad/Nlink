//
//  VehicleTimelineProvider.swift
//  BetterBlueWidget
//
//  Created by Mark Schmidt on 8/29/25.
//

import BetterBlueKit
import SwiftData
import SwiftUI
import WidgetKit

struct VehicleWidgetEntry: TimelineEntry {
    let date: Date
    let vehicle: VehicleEntity?
    let configuration: VehicleWidgetIntent
}

struct VehicleTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> VehicleWidgetEntry {
        VehicleWidgetEntry(date: Date(), vehicle: nil, configuration: VehicleWidgetIntent())
    }

    func snapshot(for configuration: VehicleWidgetIntent, in _: Context) async -> VehicleWidgetEntry {
        if let vehicle = configuration.vehicle {
            return VehicleWidgetEntry(date: Date(), vehicle: vehicle, configuration: configuration)
        }

        // Fall back to the primary vehicle (real accounts before fake ones)
        let vehicle = await VehicleQuery().defaultResult()
        return VehicleWidgetEntry(date: Date(), vehicle: vehicle, configuration: configuration)
    }

    func timeline(for configuration: VehicleWidgetIntent, in _: Context) async -> Timeline<VehicleWidgetEntry> {
        let currentDate = Date()
        let refreshInterval = await MainActor.run {
            AppSettings.shared.widgetRefreshInterval.timeInterval
        }

        // Try to refresh vehicle data
        let updatedVehicle = await Self.loadVehicle(configuration.vehicle)

        // Create timeline entries
        var entries: [VehicleWidgetEntry] = []

        // Add current entry
        entries.append(VehicleWidgetEntry(
            date: currentDate,
            vehicle: updatedVehicle,
            configuration: configuration
        ))

        // Add next refresh entry
        let nextRefreshDate = currentDate.addingTimeInterval(refreshInterval)
        entries.append(VehicleWidgetEntry(
            date: nextRefreshDate,
            vehicle: updatedVehicle,
            configuration: configuration
        ))

        return Timeline(entries: entries, policy: .atEnd)
    }

    /// Loads the widget's vehicle — `configured` if the user picked one, the
    /// primary vehicle otherwise — refreshing it over HTTP when its cached
    /// status is stale and falling back to the cache on failure. Shared by
    /// every home-screen widget so they refresh the same way.
    static func loadVehicle(_ configured: VehicleEntity?) async -> VehicleEntity? {
        // Hoist the work that doesn't need SwiftData — `preferredUnit`
        // is a UserDefaults read, `allPresets` opens its *own* short-
        // lived container internally. Doing them outside our main
        // container scope means no overlap on SQLite handles while we
        // pump them.
        // Use the live UserDefaults read (not the cached singleton)
        // so changes the user just made in the main app are reflected
        // on this timeline reload, even if the widget extension's
        // process was reused. The cached singleton would otherwise
        // keep returning the value that was current when this widget
        // process first launched.
        let unit = AppSettings.liveDistanceUnit()
        let allPresets = (try? await ClimatePresetEntity.defaultQuery.suggestedEntities()) ?? []

        do {
            let modelContainer = try createSharedModelContainer()

            // Configure the HTTP log sink manager for widget — must
            // share the same container so log writes land in the
            // right store. Done once before the per-call scope opens.
            await MainActor.run {
                HTTPLogSinkManager.shared.configure(with: modelContainer, deviceType: .widget)
            }

            return try await refreshEntity(
                for: configured,
                container: modelContainer,
                unit: unit,
                allPresets: allPresets
            )
        } catch {
            BBLogger.error(.app, "Widget: Failed to refresh vehicle data: \(error)")

            // Fall back to cached data with a fresh container so the
            // failed one's open transactions (if any) are torn down.
            do {
                let modelContainer = try createSharedModelContainer()
                await MainActor.run {
                    HTTPLogSinkManager.shared.configure(with: modelContainer, deviceType: .widget)
                }
                return cachedEntity(
                    for: configured,
                    container: modelContainer,
                    unit: unit,
                    allPresets: allPresets
                )
            } catch {
                BBLogger.error(.app, "Widget: Failed to get cached vehicle data: \(error)")
                return nil
            }
        }
    }

    /// Per-timeline-call SwiftData scope. Opens a fresh `ModelContext`,
    /// fetches the configured vehicle, conditionally refreshes it via
    /// HTTP (if the cached status is older than 30 minutes), saves
    /// explicitly, and returns the assembled `VehicleEntity`. The
    /// context goes out of scope as soon as this returns so SwiftData
    /// drops its change-tracking state and SQLite's per-context locks
    /// release before WidgetKit measures our runtime budget.
    ///
    /// Holding the context across the HTTP boundary is unavoidable
    /// here because `BBAccount.fetchAndUpdateVehicleStatus` takes a
    /// `ModelContext` for HTTP logging + token persistence. Keeping
    /// the scope as tight as possible — one vehicle per call, explicit
    /// save at the end — minimises the RunningBoard 0xdead10cc risk
    /// when the widget process is yanked mid-fetch.
    private static func refreshEntity(
        for configured: VehicleEntity?,
        container: ModelContainer,
        unit: Distance.Units,
        allPresets: [ClimatePresetEntity]
    ) async throws -> VehicleEntity? {
        let context = ModelContext(container)

        guard let bbVehicle = fetchTargetVehicle(for: configured, context: context) else {
            BBLogger.info(.app, "Widget: No vehicle found for refresh")
            return nil
        }
        guard let account = bbVehicle.account else {
            BBLogger.info(.app, "Widget: Vehicle has no account, returning cached entity")
            return VehicleEntity(from: bbVehicle, with: unit, allPresets: allPresets)
        }

        let vehicleName = bbVehicle.displayName
        let lastUpdated = bbVehicle.lastUpdated ?? Date.distantPast
        let timeSinceLastUpdate = Date().timeIntervalSince(lastUpdated)
        let thirtyMinutesInSeconds: TimeInterval = 30 * 60

        if timeSinceLastUpdate < thirtyMinutesInSeconds {
            BBLogger.info(
                .app,
                "Widget: Using fresh data for \(vehicleName) (updated \(Int(timeSinceLastUpdate / 60))m ago)"
            )
        } else {
            BBLogger.info(
                .app,
                "Widget: Refreshing stale vehicle status for \(vehicleName) " +
                "(last updated \(Int(timeSinceLastUpdate / 60))m ago)"
            )

            try await account.fetchAndUpdateVehicleStatus(for: bbVehicle, modelContext: context)
            // `fetchAndUpdateVehicleStatus` saves internally, but be
            // belt-and-suspenders explicit so any side-effect writes
            // we made on `bbVehicle` flush before the context drops.
            try context.save()

            BBLogger.info(.app, "Widget: Successfully refreshed \(vehicleName)")
        }

        return VehicleEntity(from: bbVehicle, with: unit, allPresets: allPresets)
    }

    /// Cached-only path (no HTTP). Same tight-scope pattern as
    /// `refreshEntity` — fetch, build entity, drop context.
    private static func cachedEntity(
        for configured: VehicleEntity?,
        container: ModelContainer,
        unit: Distance.Units,
        allPresets: [ClimatePresetEntity]
    ) -> VehicleEntity? {
        let context = ModelContext(container)
        guard let bbVehicle = fetchTargetVehicle(for: configured, context: context) else {
            return nil
        }
        return VehicleEntity(from: bbVehicle, with: unit, allPresets: allPresets)
    }

    /// Shared lookup: configured vehicle by VIN if the user picked
    /// one, otherwise the primary vehicle (`BBVehicle.primary`).
    private static func fetchTargetVehicle(
        for configured: VehicleEntity?,
        context: ModelContext
    ) -> BBVehicle? {
        do {
            if let configured {
                let vehicles = try context.fetch(FetchDescriptor<BBVehicle>())
                return vehicles.first { $0.vin == configured.vin }
            }
            return try BBVehicle.primary(in: context)
        } catch {
            BBLogger.error(.app, "Widget: Failed to fetch vehicles from context: \(error)")
            return nil
        }
    }

}
