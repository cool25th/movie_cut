import Foundation
import Testing
@testable import MovieCutCore

/// S7 — thermal-state proxy downgrade.
///
/// Covers the pure policy (no device/GUI needed), the v2→v3 migration, the
/// PlaybackSettings Codable compatibility, and the badge reason distinction.
/// See S7 of `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.
@Suite("Thermal proxy downgrade")
struct ThermalProxyDowngradeTests {

    // MARK: - ThermalState mapping

    @Test("nominal and fair do not trigger a proxy downgrade")
    func nominalAndFairDoNotDowngrade() {
        #expect(ThermalState.nominal.shouldDowngradeToProxy == false)
        #expect(ThermalState.fair.shouldDowngradeToProxy == false)
    }

    @Test("serious and critical trigger a proxy downgrade")
    func seriousAndCriticalDowngrade() {
        #expect(ThermalState.serious.shouldDowngradeToProxy == true)
        #expect(ThermalState.critical.shouldDowngradeToProxy == true)
    }

    // MARK: - ProxyDowngradePolicy (pure)

    @Test("auto-downgrade is off when the user disabled it, even under critical heat")
    func disabledSettingIgnoresPressure() {
        #expect(ProxyDowngradePolicy.shouldAutoDowngrade(
            thermalState: .critical, autoProxyOnThermalPressure: false) == false)
    }

    @Test("auto-downgrade follows the thermal state when the setting is on")
    func enabledSettingFollowsPressure() {
        #expect(ProxyDowngradePolicy.shouldAutoDowngrade(
            thermalState: .nominal, autoProxyOnThermalPressure: true) == false)
        #expect(ProxyDowngradePolicy.shouldAutoDowngrade(
            thermalState: .serious, autoProxyOnThermalPressure: true) == true)
        #expect(ProxyDowngradePolicy.shouldAutoDowngrade(
            thermalState: .critical, autoProxyOnThermalPressure: true) == true)
    }

    // MARK: - PlaybackSettings Codable

    @Test("A v2 PlaybackSettings (no thermal key) decodes with auto-downgrade on")
    func v2SettingsDecodeWithDefaultOn() throws {
        // v2 projects carry no autoProxyOnThermalPressure key. Decoding must not
        // throw, and the safety net must default on.
        let v2JSON = """
        { "useProxyPlayback": false, "proxyResolution": "p540" }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(PlaybackSettings.self, from: v2JSON)
        #expect(settings.autoProxyOnThermalPressure == true)
        #expect(settings.useProxyPlayback == false)
        #expect(settings.proxyResolution == .p540)
    }

    @Test("auto-downgrade preference round-trips through JSON")
    func autoDowngradeRoundTrips() throws {
        let settings = PlaybackSettings(useProxyPlayback: true, proxyResolution: .p720, autoProxyOnThermalPressure: false)
        let decoded = try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.autoProxyOnThermalPressure == false)
    }

    // MARK: - Migration

    @Test("A schema v2 project migrates to current through the registered chain")
    func v2ProjectMigratesToCurrent() throws {
        var project = Project(name: "pre-thermal", schemaVersion: 2)
        try ProjectMigrationRunner.migrate(&project)
        #expect(project.schemaVersion == currentSchemaVersion)
        // The thermal field's v2→v3 default applies and survives later steps.
        #expect(project.playbackSettings.autoProxyOnThermalPressure == true)
    }

    @Test("The thermal migration is the v2→v3 step and is registered")
    func thermalMigrationRegistered() throws {
        let migrators = ProjectSchema.migrations
        #expect(migrators.count >= 2)
        let second = try #require(migrators.dropFirst().first)
        #expect(second.version == 3)
        #expect(second is AddAutoProxyOnThermalPressureMigration)
    }

    // MARK: - ProxyBadgeState reason distinction

    @Test("resolve distinguishes a thermal auto-downgrade from a user toggle")
    func badgeDistinguishesThermalReason() {
        let proxy = ProxyInfo(proxyURL: URL(fileURLWithPath: "/tmp/p.mp4"))
        // No proxy at all -> no badge.
        #expect(ProxyBadgeState.resolve(proxy: nil, useProxyPlayback: true, autoDowngraded: true) == nil)
        // User opted into proxy playback -> .active.
        #expect(ProxyBadgeState.resolve(proxy: proxy, useProxyPlayback: true, autoDowngraded: false) == .active)
        // Thermal dropped to proxy while the user toggle is off -> .thermalActive.
        #expect(ProxyBadgeState.resolve(proxy: proxy, useProxyPlayback: false, autoDowngraded: true) == .thermalActive)
        // Proxy ready, not used -> .idle.
        #expect(ProxyBadgeState.resolve(proxy: proxy, useProxyPlayback: false, autoDowngraded: false) == .idle)
    }

    @Test("The committed v1 fixture still loads and migrates to v3")
    func v1FixtureMigratesToV3() async throws {
        let store = ProjectStore(autosaveDirectory: nil)
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/project_v1.moviecut")
        let project = try await store.load(from: url)
        #expect(project.schemaVersion == currentSchemaVersion)
        #expect(project.playbackSettings.autoProxyOnThermalPressure == true)
    }
}
