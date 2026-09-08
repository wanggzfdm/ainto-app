import Foundation

final class PluginPermissionStore {
    private var declaredPermissions: [String: Set<PluginPermission>] = [:]
    private var grantedPermissions: [String: Set<PluginPermission>] = [:]

    func setDeclared(_ permissions: [PluginPermission], for pluginID: String) {
        declaredPermissions[pluginID] = Set(permissions)
        let declared = declaredPermissions[pluginID] ?? []
        grantedPermissions[pluginID] = (grantedPermissions[pluginID] ?? []).intersection(declared)
    }

    @discardableResult
    func grant(_ permission: PluginPermission, to pluginID: String) -> Bool {
        guard declaredPermissions[pluginID, default: []].contains(permission) else { return false }
        grantedPermissions[pluginID, default: []].insert(permission)
        return true
    }

    func revoke(_ permission: PluginPermission, from pluginID: String) {
        grantedPermissions[pluginID, default: []].remove(permission)
    }

    func revokeAll(for pluginID: String) {
        grantedPermissions[pluginID] = []
    }

    func isDeclared(_ permission: PluginPermission, for pluginID: String) -> Bool {
        declaredPermissions[pluginID, default: []].contains(permission)
    }

    func isGranted(_ permission: PluginPermission, for pluginID: String) -> Bool {
        grantedPermissions[pluginID, default: []].contains(permission)
    }

    func granted(for pluginID: String) -> Set<PluginPermission> {
        grantedPermissions[pluginID, default: []]
    }
}
