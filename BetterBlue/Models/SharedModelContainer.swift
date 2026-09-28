//
//  SharedModelContainer.swift
//  BetterBlue
//
//  Created by Mark Schmidt on 9/4/25.
//

import BetterBlueKit
import Foundation
import SwiftData

func getSimulatorStoreURL() -> URL {
    // In simulator, use a fixed shared location to work around App Group container isolation
    let sharedSimulatorPath = "/tmp/BetterBlue_Shared"
    try? FileManager.default.createDirectory(
        atPath: sharedSimulatorPath,
        withIntermediateDirectories: true,
        attributes: nil,
    )
    return URL(fileURLWithPath: sharedSimulatorPath).appendingPathComponent("BetterBlue.sqlite")
}

func getAppGroupStoreURL() -> URL? {
    let appGroupID = AppIdentifiers.appGroup
    guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    else {
        BBLogger.warning(.app, "BetterBlue: App Group container not accessible from current context")
        return nil
    }
    return appGroupURL.appendingPathComponent("BetterBlue.sqlite")
}

/// Per-process store, used when the App Group container is unavailable —
/// the widget extension then keeps its own cache instead of sharing the
/// app's. See Gate G1 in the work order.
func getLocalStoreURL() -> URL {
    let base = URL.applicationSupportDirectory
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base.appendingPathComponent("BetterBlue.sqlite")
}

func createContainer(storeURL: URL, schema: Schema) throws -> ModelContainer {
    do {
        let modelConfiguration = ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
        BBLogger.error(.app, "BetterBlue: Failed to create ModelContainer: \(error)")
        throw NSError(
            domain: "BetterBlue",
            code: 1002,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Failed to create data storage",
                NSLocalizedRecoverySuggestionErrorKey:
                    "Try restarting the app. If the problem persists, contact support."
            ],
        )
    }
}

/// Removes orphaned climate presets that have no vehicle relationship.
/// These are leftover from before the relationship was properly set during creation.
@MainActor
func cleanupOrphanedClimatePresets(container: ModelContainer) {
    let context = container.mainContext

    do {
        let presetDescriptor = FetchDescriptor<ClimatePreset>()
        let allPresets = try context.fetch(presetDescriptor)

        var deletedCount = 0
        for preset in allPresets where preset.vehicle == nil {
            context.delete(preset)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try context.save()
            BBLogger.info(.app, "Cleaned up \(deletedCount) orphaned climate preset(s)")
        }
    } catch {
        BBLogger.error(.app, "Failed to cleanup orphaned climate presets: \(error)")
    }
}

/// Removes "zombie" vehicles whose parent `BBAccount` no longer exists.
/// Normally `BBAccount` → `BBVehicle` is cascade-delete, but earlier schema
/// iterations can leave orphan vehicle rows that Siri/App Intents/widget
/// pickers would otherwise still list.
/// Their cascaded `climatePresets` are dropped by SwiftData automatically
/// once the vehicle goes away.
@MainActor
func cleanupOrphanedVehicles(container: ModelContainer) {
    let context = container.mainContext

    do {
        let vehicleDescriptor = FetchDescriptor<BBVehicle>()
        let allVehicles = try context.fetch(vehicleDescriptor)

        var deletedCount = 0
        for vehicle in allVehicles where vehicle.account == nil {
            BBLogger.info(.app, "Purging orphaned vehicle \(vehicle.vin) (\(vehicle.displayName))")
            context.delete(vehicle)
            deletedCount += 1
        }

        if deletedCount > 0 {
            try context.save()
            BBLogger.info(.app, "Cleaned up \(deletedCount) orphaned vehicle(s)")
        }
    } catch {
        BBLogger.error(.app, "Failed to cleanup orphaned vehicles: \(error)")
    }
}

/// Removes duplicate `BBVehicle` rows that share a VIN within one account.
/// `BBAccount.updateVehicles()` keys existing vehicles by VIN, so it never
/// creates a second row itself — but a store migrated from an iCloud-synced
/// build can carry one, and once two exist neither is ever swept up
/// because both match the fetched VIN. The duplicate is worse than
/// cosmetic: intents and widgets resolve vehicles by VIN and can land on
/// the wrong copy, running commands with that copy's presets. Keep the
/// visible row (then lowest sort order) and delete the rest; their
/// cascaded presets go with them.
@MainActor
func cleanupDuplicateVehicles(container: ModelContainer) {
    let context = container.mainContext

    do {
        let allVehicles = try context.fetch(FetchDescriptor<BBVehicle>())

        var groups: [String: [BBVehicle]] = [:]
        for vehicle in allVehicles {
            guard let account = vehicle.account else { continue }
            groups["\(account.id)|\(vehicle.vin)", default: []].append(vehicle)
        }

        var deletedCount = 0
        for (_, rows) in groups where rows.count > 1 {
            let ordered = rows.sorted {
                ($0.isHidden ? 1 : 0, $0.sortOrder) < ($1.isHidden ? 1 : 0, $1.sortOrder)
            }
            let keeper = ordered[0]
            for duplicate in ordered.dropFirst() {
                BBLogger.info(
                    .app,
                    "Purging duplicate vehicle \(duplicate.vin.suffix(6)) (\(duplicate.displayName)), keeping \(keeper.displayName)"
                )
                context.delete(duplicate)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            try context.save()
            BBLogger.info(.app, "Cleaned up \(deletedCount) duplicate vehicle(s)")
        }
    } catch {
        BBLogger.error(.app, "Failed to cleanup duplicate vehicles: \(error)")
    }
}

/// Creates the shared ModelContainer used by the app and the widget extension.
/// Storage is local-only: CloudKit needs an iCloud entitlement a Personal Team
/// cannot sign, so it was removed along with the push and Watch targets.
func createSharedModelContainer() throws -> ModelContainer {
    let schema = Schema([
        BBAccount.self,
        BBVehicle.self,
        BBHTTPLog.self,
        ClimatePreset.self
    ], version: .init(1, 0, 9))

    #if targetEnvironment(simulator)
        let storeURL = getSimulatorStoreURL()
    #else
        let storeURL = getAppGroupStoreURL() ?? getLocalStoreURL()
    #endif
    return try createContainer(storeURL: storeURL, schema: schema)
}
