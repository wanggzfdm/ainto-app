import Foundation

struct PluginSearchCandidate: Equatable {
    let pluginID: String
    let featureCode: String
    let title: String
    let subtitle: String
    let terms: [String]
}

struct PluginSearchProvider {
    func candidates(from registrations: [PluginRegistration]) -> [PluginSearchCandidate] {
        registrations.flatMap { registration -> [PluginSearchCandidate] in
            guard registration.isEnabled, registration.validationMessage == nil,
                  registration.compatibility == .webCompatible else { return [] }
            return registration.manifest.features.map { feature in
                PluginSearchCandidate(
                    pluginID: registration.id,
                    featureCode: feature.code,
                    title: feature.explain,
                    subtitle: registration.manifest.name,
                    terms: [feature.code, feature.explain] + feature.cmds
                )
            }
        }
    }

    func matches(query: String, candidate: PluginSearchCandidate) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return false }
        return candidate.terms.contains { term in
            let normalizedTerm = term.lowercased()
            return normalizedTerm.contains(normalizedQuery) || fuzzyMatch(normalizedQuery, normalizedTerm)
        }
    }
}
