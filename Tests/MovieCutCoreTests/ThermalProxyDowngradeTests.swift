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

    // MARK: - Export thermal gate (ExportEngine refuses under critical heat)

    @Test("only critical thermal state blocks export")
    func onlyCriticalBlocksExport() {
        // Export is refused ONLY at .critical — a thermal shutdown mid-write
        // would corrupt the output. .serious proceeds (throttled but safe);
        // .nominal/.fair are unrestricted.
        #expect(ThermalState.nominal.shouldBlockExport == false)
        #expect(ThermalState.fair.shouldBlockExport == false)
        #expect(ThermalState.serious.shouldBlockExport == false)
        #expect(ThermalState.critical.shouldBlockExport == true)
    }

    @Test("export blocking is more conservative than proxy downgrade")
    func exportMoreConservativeThanProxyDowngrade() {
        // Proxy downgrade (preview) is aggressive (.serious+): a dropped frame
        // is cheap. Export blocking is conservative (.critical only): refusing
        // a user's export is high-friction and a throttled export still
        // completes safely. These two policies are deliberately different — pin
        // the divergence so a future change can't silently collapse them.
        #expect(ThermalState.serious.shouldDowngradeToProxy == true)
        #expect(ThermalState.serious.shouldBlockExport == false)
        #expect(ThermalState.critical.shouldDowngradeToProxy == true)
        #expect(ThermalState.critical.shouldBlockExport == true)
    }

    // MARK: - Gradual degradation rung 1: .fair preview-quality clamp

    @Test("nominal honors the user's preview quality unchanged")
    func nominalKeepsUserQuality() {
        #expect(ProxyDowngradePolicy.effectivePreviewQuality(user: .full, thermalState: .nominal) == .full)
        #expect(ProxyDowngradePolicy.effectivePreviewQuality(user: .half, thermalState: .nominal) == .half)
        #expect(ProxyDowngradePolicy.effectivePreviewQuality(user: .quarter, thermalState: .nominal) == .quarter)
    }

    @Test("fair and above clamp full preview quality to half — never raise a lower choice")
    func fairClampsFullToHalf() {
        // The first gradual rung: at .fair the preview render size halves (a
        // pure render-size change, no encode pass). Users who already chose
        // 1/2 or 1/4 are never raised.
        for state in [ThermalState.fair, .serious, .critical] {
            #expect(ProxyDowngradePolicy.effectivePreviewQuality(user: .full, thermalState: state) == .half,
                    "\(state) should clamp .full to .half")
            #expect(ProxyDowngradePolicy.effectivePreviewQuality(user: .half, thermalState: state) == .half,
                    "\(state) must not raise .half")
            #expect(ProxyDowngradePolicy.effectivePreviewQuality(user: .quarter, thermalState: state) == .quarter,
                    "\(state) must not raise .quarter")
        }
    }

    @Test("fair does NOT flip the proxy — the rungs stay distinct")
    func fairDoesNotFlipProxy() {
        // .fair is render-scale only; the proxy flip remains .serious+. Pin
        // the ladder: fair=scale, serious=proxy, critical=export refused.
        #expect(ProxyDowngradePolicy.shouldAutoDowngrade(thermalState: .fair, autoProxyOnThermalPressure: true) == false)
        #expect(ThermalState.fair.shouldBlockExport == false)
    }

    @Test("the badge reports the thermal preview scale as its own cause")
    func badgeReportsThermalPreviewScale() {
        let state = ProxyBadgeState.resolve(
            proxy: nil,
            useProxyPlayback: false,
            autoDowngraded: false,
            previewQuality: .full,
            thermalPreviewScale: true
        )
        #expect(state.activeCauses == [.thermalPreviewScale])
        #expect(state.primaryState == .previewQualityReduced)

        // The proxy rung still outranks the scale rung when both are active.
        let both = ProxyBadgeState.resolve(
            proxy: ProxyInfo(proxyURL: URL(fileURLWithPath: "/tmp/proxy.mov")),
            useProxyPlayback: false,
            autoDowngraded: true,
            previewQuality: .full,
            thermalPreviewScale: true
        )
        #expect(both.activeCauses.first == .thermalDowngrade)
        #expect(both.primaryState == .thermalActive)

        // A user who picked 1/2 themselves at nominal heat is a MANUAL cause,
        // not the thermal one.
        let manual = ProxyBadgeState.resolve(
            proxy: nil,
            useProxyPlayback: false,
            autoDowngraded: false,
            previewQuality: .half,
            thermalPreviewScale: false
        )
        #expect(manual.activeCauses == [.manualPreviewQuality])
    }
}
