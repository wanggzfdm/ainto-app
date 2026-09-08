import SwiftUI
import AppKit

@MainActor
final class PluginCenterModel: ObservableObject {
    struct ImportError: Equatable { let message: String }

    @Published private(set) var plugins: [PluginRegistration] = []
    @Published private(set) var importError: ImportError?
    let permissionStore: PluginPermissionStore
    private let registry: PluginRegistry
    private let installer: PluginInstaller
    private let logStore: PluginLogStore

    init(registry: PluginRegistry = PluginRegistry(), installer: PluginInstaller? = nil, permissionStore: PluginPermissionStore = PluginPermissionStore(), logStore: PluginLogStore = PluginLogStore()) {
        self.registry = registry
        self.installer = installer ?? PluginInstaller(paths: .applicationSupport, registry: registry)
        self.permissionStore = permissionStore
        self.logStore = logStore
        reload()
    }

    var installedPlugins: [PluginRegistration] { plugins.filter { $0.source == .installed } }
    var developmentPlugins: [PluginRegistration] { plugins.filter { $0.source == .development } }

    func reload() {
        do {
            try registry.load()
            try registry.refreshDevelopmentPlugins()
            synchronizePermissions()
            plugins = registry.plugins
        } catch { importError = ImportError(message: error.localizedDescription) }
    }

    @discardableResult func importPlugin(at url: URL) -> PluginRegistration? {
        do {
            let result = url.pathExtension.lowercased() == "zip" ? try installer.importArchive(url) : try installer.importDirectory(url)
            permissionStore.setDeclared(result.manifest.ainto?.permissions ?? [], for: result.id)
            logStore.append(pluginID: result.id, event: "imported", parameters: ["source": result.source.rawValue])
            reload()
            return result
        } catch {
            importError = ImportError(message: error.localizedDescription)
            return nil
        }
    }

    @discardableResult func addDevelopmentPlugin(at url: URL) -> PluginRegistration? {
        do {
            let result = try installer.registerDevelopmentDirectory(url)
            permissionStore.setDeclared(result.manifest.ainto?.permissions ?? [], for: result.id)
            logStore.append(pluginID: result.id, event: "development-reference-added")
            reload()
            return result
        } catch {
            importError = ImportError(message: error.localizedDescription)
            return nil
        }
    }

    func setEnabled(_ enabled: Bool, pluginID: String) {
        do {
            try registry.setEnabled(enabled, id: pluginID)
            logStore.append(pluginID: pluginID, event: enabled ? "enabled" : "disabled")
            reload()
        } catch { importError = ImportError(message: error.localizedDescription) }
    }

    func uninstall(pluginID: String) {
        do {
            try installer.uninstall(id: pluginID)
            logStore.append(pluginID: pluginID, event: "uninstalled")
            reload()
        } catch { importError = ImportError(message: error.localizedDescription) }
    }

    func removeDevelopmentPlugin(id: String) {
        do {
            try registry.remove(id: id)
            permissionStore.revokeAll(for: id)
            logStore.append(pluginID: id, event: "development-reference-removed")
            reload()
        } catch { importError = ImportError(message: error.localizedDescription) }
    }

    func pendingPermissions(for pluginID: String) -> [PluginPermission] { permissionStore.pending(for: pluginID) }
    func grantPending(_ permission: PluginPermission, pluginID: String) { _ = permissionStore.grant(permission, to: pluginID); objectWillChange.send() }
    func denyPending(_ permission: PluginPermission, pluginID: String) { permissionStore.deny(permission, for: pluginID); objectWillChange.send() }

    func revoke(_ permission: PluginPermission, pluginID: String) {
        permissionStore.revoke(permission, from: pluginID)
        logStore.append(pluginID: pluginID, event: "permission-revoked", parameters: ["permission": permission.rawValue])
        objectWillChange.send()
    }

    func permissions(for plugin: PluginRegistration) -> [PluginPermission] { plugin.manifest.ainto?.permissions ?? [] }
    func logs(for pluginID: String) -> [PluginLogEntry] { logStore.entries(for: pluginID) }

    private func synchronizePermissions() {
        for plugin in registry.plugins { permissionStore.setDeclared(plugin.manifest.ainto?.permissions ?? [], for: plugin.id) }
    }
}

struct PluginCenterView: View {
    @StateObject private var model: PluginCenterModel
    @State private var showImporter = false
    @State private var importDevelopmentDirectory = false

    init(model: PluginCenterModel = PluginCenterModel()) { _model = StateObject(wrappedValue: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: L("plugin.center.title"), icon: "puzzlepiece.extension")
            HStack {
                Button(L("plugin.import")) { showImporter = true }
                Button(L("plugin.development.add")) { importDevelopmentDirectory = true }
                Spacer()
                Button(L("plugin.reload")) { model.reload() }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder, .zip]) { handleImport($0, development: false) }
            .fileImporter(isPresented: $importDevelopmentDirectory, allowedContentTypes: [.folder]) { handleImport($0, development: true) }

            if let error = model.importError { Text(error.message).foregroundStyle(.red).font(.system(size: 12)) }
            pluginSection(title: L("plugin.installed"), plugins: model.installedPlugins)
            pluginSection(title: L("plugin.development"), plugins: model.developmentPlugins)
        }
        .onAppear { model.reload() }
    }

    @ViewBuilder private func pluginSection(title: String, plugins: [PluginRegistration]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if plugins.isEmpty { Text(L("plugin.empty")).foregroundStyle(.secondary).font(.system(size: 12)) }
            ForEach(plugins, id: \.id) { plugin in pluginCard(plugin) }
        }
    }

    private func pluginCard(_ plugin: PluginRegistration) -> some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack { VStack(alignment: .leading) { Text(plugin.manifest.name).font(.headline); Text(plugin.manifest.version).font(.caption).foregroundStyle(.secondary) }; Spacer(); Toggle(L("plugin.enabled"), isOn: Binding(get: { plugin.isEnabled }, set: { model.setEnabled($0, pluginID: plugin.id) })).labelsHidden().disabled(plugin.compatibility != .webCompatible) }
                if let message = plugin.validationMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                if plugin.compatibility != .webCompatible { Text(L("plugin.needsAdaptation")).font(.caption).foregroundStyle(.orange) }
                ForEach(model.permissions(for: plugin), id: \.self) { permission in
                    HStack { Text(permission.rawValue).font(.caption); Spacer(); if model.permissionStore.isGranted(permission, for: plugin.id) { Button(L("plugin.revoke")) { model.revoke(permission, pluginID: plugin.id) } } }
                }
                ForEach(model.pendingPermissions(for: plugin.id), id: \.self) { permission in
                    HStack {
                        Text(LocalizationManager.shared.format("plugin.permission.requests", plugin.manifest.name, L("plugin.permission.\(permission.rawValue)"))).font(.caption)
                        Spacer()
                        Button(L("plugin.permission.allow")) { model.grantPending(permission, pluginID: plugin.id) }
                        Button(L("plugin.permission.deny"), role: .destructive) { model.denyPending(permission, pluginID: plugin.id) }
                    }
                }
                let logs = model.logs(for: plugin.id)
                if !logs.isEmpty { Text(L("plugin.logs")).font(.caption.weight(.medium)); ForEach(logs.suffix(3)) { log in Text("\(log.event) · \(log.timestamp.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) } }
                HStack { Spacer(); Button(plugin.source == .development ? L("plugin.development.remove") : L("plugin.uninstall"), role: .destructive) { if plugin.source == .development { model.removeDevelopmentPlugin(id: plugin.id) } else { model.uninstall(pluginID: plugin.id) } } }
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>, development: Bool) {
        guard case let .success(url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if development { _ = model.addDevelopmentPlugin(at: url) } else { _ = model.importPlugin(at: url) }
    }
}
