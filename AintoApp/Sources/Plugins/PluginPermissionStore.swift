import Foundation

final class PluginPermissionStore {
    private let url: URL?
    private var declaredPermissions: [String: Set<PluginPermission>] = [:]
    private var grantedPermissions: [String: Set<PluginPermission>] = [:]
    private var pendingPermissions: [String: Set<PluginPermission>] = [:]
    private var deniedPermissions: [String: Set<PluginPermission>] = [:]

    private struct Persisted: Codable {
        var granted: [String: [PluginPermission]]
        var pending: [String: [PluginPermission]]
        var denied: [String: [PluginPermission]]
    }

    init(paths: PluginPaths? = nil) {
        url = paths?.rootURL.appendingPathComponent("permissions.json")
        load()
    }

    func setDeclared(_ permissions: [PluginPermission], for pluginID: String) {
        declaredPermissions[pluginID] = Set(permissions)
        grantedPermissions[pluginID] = (grantedPermissions[pluginID] ?? []).intersection(permissions)
        pendingPermissions[pluginID] = (pendingPermissions[pluginID] ?? []).intersection(permissions)
        deniedPermissions[pluginID] = (deniedPermissions[pluginID] ?? []).intersection(permissions)
        save()
    }

    @discardableResult func request(_ permission: PluginPermission, for pluginID: String) -> Bool {
        guard isDeclared(permission, for: pluginID), !isGranted(permission, for: pluginID), !deniedPermissions[pluginID, default: []].contains(permission) else { return false }
        let inserted = pendingPermissions[pluginID, default: []].insert(permission).inserted
        if inserted { save() }
        return inserted
    }

    @discardableResult func grant(_ permission: PluginPermission, to pluginID: String) -> Bool {
        guard isDeclared(permission, for: pluginID) else { return false }
        grantedPermissions[pluginID, default: []].insert(permission)
        pendingPermissions[pluginID, default: []].remove(permission)
        deniedPermissions[pluginID, default: []].remove(permission)
        save()
        return true
    }

    func deny(_ permission: PluginPermission, for pluginID: String) { pendingPermissions[pluginID, default: []].remove(permission); deniedPermissions[pluginID, default: []].insert(permission); save() }
    func pending(for pluginID: String) -> [PluginPermission] { pendingPermissions[pluginID, default: []].sorted { $0.rawValue < $1.rawValue } }
    func revoke(_ permission: PluginPermission, from pluginID: String) { grantedPermissions[pluginID, default: []].remove(permission); pendingPermissions[pluginID, default: []].remove(permission); save() }
    func revokeAll(for pluginID: String) { grantedPermissions[pluginID] = []; pendingPermissions[pluginID] = []; deniedPermissions[pluginID] = []; save() }
    func isDeclared(_ permission: PluginPermission, for pluginID: String) -> Bool { declaredPermissions[pluginID, default: []].contains(permission) }
    func isGranted(_ permission: PluginPermission, for pluginID: String) -> Bool { grantedPermissions[pluginID, default: []].contains(permission) }
    func granted(for pluginID: String) -> Set<PluginPermission> { grantedPermissions[pluginID, default: []] }

    private func load() {
        guard let url, let data = try? Data(contentsOf: url), let persisted = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        grantedPermissions = persisted.granted.mapValues(Set.init)
        pendingPermissions = persisted.pending.mapValues(Set.init)
        deniedPermissions = persisted.denied.mapValues(Set.init)
    }
    private func save() {
        guard let url, let data = try? JSONEncoder().encode(Persisted(granted: grantedPermissions.mapValues(Array.init), pending: pendingPermissions.mapValues(Array.init), denied: deniedPermissions.mapValues(Array.init))) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
