//! App search engine with fuzzy matching and ranking.

/// A discovered application entry.
#[derive(Debug, Clone)]
pub struct AppEntry {
    pub display_name: String,
    pub search_name: String,       // lowercase, for matching
    pub aliases: Vec<String>,      // localized names, for matching
    pub path: String,              // app bundle path
    pub bundle_id: Option<String>, // CFBundleIdentifier, for dedup
    pub icon_png: Option<Vec<u8>>, // PNG bytes for icon
    pub ranking: i32,
    pub is_favourite: bool,
}

/// In-memory index of all discovered applications.
pub struct AppIndex {
    apps: Vec<AppEntry>,
}

impl AppIndex {
    pub fn apps_mut(&mut self) -> &mut Vec<AppEntry> {
        &mut self.apps
    }

    pub fn new(apps: Vec<AppEntry>) -> Self {
        Self { apps }
    }

    /// Search apps with fuzzy matching. Results sorted by match quality + ranking.
    pub fn search(&self, query: &str) -> Vec<&AppEntry> {
        if query.is_empty() {
            return Vec::new();
        }
        let query_lc = query.to_lowercase();

        let mut scored: Vec<(&AppEntry, i32)> = self
            .apps
            .iter()
            .filter_map(|app| {
                let score = std::iter::once((&app.search_name, &app.display_name))
                    .chain(app.aliases.iter().map(|alias| (alias, alias)))
                    .map(|(search_name, display_name)| {
                        fuzzy_score(&query_lc, &search_name.to_lowercase(), display_name)
                    })
                    .max()
                    .unwrap_or_default();
                if score > 0 {
                    // Combine match score with ranking (ranking adds a small boost)
                    Some((app, score + app.ranking.min(50)))
                } else {
                    None
                }
            })
            .collect();

        scored.sort_by(|a, b| b.1.cmp(&a.1));
        scored.into_iter().map(|(app, _)| app).collect()
    }

    /// Get top-ranked apps (most frequently used).
    pub fn get_top_ranked(&self, limit: usize) -> Vec<&AppEntry> {
        let mut ranked: Vec<&AppEntry> = self.apps.iter().filter(|a| a.ranking > 0).collect();
        ranked.sort_by(|a, b| b.ranking.cmp(&a.ranking));
        ranked.truncate(limit);
        ranked
    }

    /// Get every discovered app sorted by display name, case-insensitively.
    pub fn get_all_sorted(&self) -> Vec<&AppEntry> {
        let mut apps: Vec<&AppEntry> = self.apps.iter().collect();
        apps.sort_by(|a, b| {
            a.display_name
                .to_lowercase()
                .cmp(&b.display_name.to_lowercase())
                .then_with(|| a.display_name.cmp(&b.display_name))
        });
        apps
    }

    /// Get all favourite apps.
    pub fn get_favourites(&self) -> Vec<&AppEntry> {
        self.apps.iter().filter(|a| a.is_favourite).collect()
    }

    /// Increment the ranking for an app by path.
    pub fn update_ranking(&mut self, path: &str) {
        if let Some(app) = self.apps.iter_mut().find(|a| a.path == path) {
            app.ranking = app.ranking.saturating_add(1);
        }
    }

    /// Set favourite status for an app by path.
    pub fn toggle_favourite(&mut self, path: &str) {
        if let Some(app) = self.apps.iter_mut().find(|a| a.path == path) {
            app.is_favourite = !app.is_favourite;
        }
    }

    /// Apply frecency rankings loaded from disk.
    pub fn apply_rankings(
        &mut self,
        rankings: &std::collections::HashMap<String, crate::ranking::RankingEntry>,
    ) {
        for app in &mut self.apps {
            if let Some(entry) = rankings.get(&app.path) {
                app.ranking = entry.frecency_score();
            }
        }
    }

    /// Get app paths that have been ranked (for in-memory lookup).
    pub fn get_ranked_paths(&self) -> Vec<(&str, i32)> {
        self.apps
            .iter()
            .filter(|a| a.ranking != 0)
            .map(|a| (a.path.as_str(), a.ranking))
            .collect()
    }
}

/// Fuzzy match scoring. Returns 0 if no match.
///
/// Scoring tiers:
///   200 — exact match
///   150 — prefix match ("orb" → "orbstack")
///   120 — word-boundary prefix ("vs" → "Visual Studio Code", matches V + S)
///   100 — contains as substring ("stack" → "orbstack")
///    80 — subsequence match ("os" → "OrbStack")
///    60 — subsequence on original casing with camelCase bonus ("os" → "OrbStack")
///     0 — no match
fn fuzzy_score(query: &str, search_name: &str, display_name: &str) -> i32 {
    // Exact match
    if search_name == query {
        return 200;
    }

    // Prefix match
    if search_name.starts_with(query) {
        return 150;
    }

    // Word-boundary initials match: "vs" matches "Visual Studio Code"
    // Also handles: "os" → "Orb Stack" if there's a word boundary
    if word_boundary_match(query, display_name) {
        return 120;
    }

    // Contains as substring
    if search_name.contains(query) {
        return 100;
    }

    // Subsequence match on lowercase
    // "obstack" → "orbstack" (o..b..s..t..a..c..k all present in order)
    if is_subsequence(query, search_name) {
        // Score based on how tight the match is (fewer gaps = higher score)
        let tightness = (query.len() as f32 / search_name.len() as f32 * 40.0) as i32;
        return 60 + tightness;
    }

    // CamelCase subsequence: "os" matches "OrbStack" via O + S at case boundaries
    if camel_case_match(query, display_name) {
        return 80;
    }

    0
}

/// Check if `query` chars appear in order in `target`.
/// "obstack" is subsequence of "orbstack": o-r-b-s-t-a-c-k contains o-b-s-t-a-c-k in order.
fn is_subsequence(query: &str, target: &str) -> bool {
    let mut query_chars = query.chars();
    let mut current = match query_chars.next() {
        Some(c) => c,
        None => return true,
    };

    for tc in target.chars() {
        if tc == current {
            current = match query_chars.next() {
                Some(c) => c,
                None => return true,
            };
        }
    }
    false
}

/// Check if query matches the first letter of each word.
/// "vsc" matches "Visual Studio Code" (V, S, C).
/// "os" matches "Orb Stack" (O, S) — but also handles camelCase.
fn word_boundary_match(query: &str, display_name: &str) -> bool {
    let initials: Vec<char> = extract_word_boundaries(display_name);
    let query_chars: Vec<char> = query.to_lowercase().chars().collect();

    if query_chars.is_empty() || initials.is_empty() {
        return false;
    }

    // Check if query is a subsequence of the initials
    let initials_lower: Vec<char> = initials
        .iter()
        .map(|c| c.to_lowercase().next().unwrap_or(*c))
        .collect();
    let mut qi = 0;
    for &ic in &initials_lower {
        if qi < query_chars.len() && ic == query_chars[qi] {
            qi += 1;
        }
    }
    qi == query_chars.len()
}

/// Extract word boundary characters: first char + chars after space/hyphen + uppercase in camelCase.
/// "OrbStack" → ['O', 'S']
/// "Visual Studio Code" → ['V', 'S', 'C']
/// "IntelliJ IDEA" → ['I', 'J', 'I', 'D', 'E', 'A']
fn extract_word_boundaries(name: &str) -> Vec<char> {
    let mut boundaries = Vec::new();
    let chars: Vec<char> = name.chars().collect();

    for (i, &c) in chars.iter().enumerate() {
        if i == 0 && c.is_alphanumeric() {
            boundaries.push(c);
        } else if c.is_uppercase() && i > 0 && chars[i - 1].is_lowercase() {
            // camelCase boundary: "OrbStack" → S
            boundaries.push(c);
        } else if i > 0
            && (chars[i - 1] == ' ' || chars[i - 1] == '-' || chars[i - 1] == '_')
            && c.is_alphanumeric()
        {
            // Word boundary after separator
            boundaries.push(c);
        }
    }
    boundaries
}

/// CamelCase aware subsequence: query chars match at case-change boundaries.
fn camel_case_match(query: &str, display_name: &str) -> bool {
    let boundaries = extract_word_boundaries(display_name);
    let boundary_str: String = boundaries
        .iter()
        .map(|c| c.to_lowercase().next().unwrap_or(*c))
        .collect();
    let query_lc = query.to_lowercase();
    is_subsequence(&query_lc, &boundary_str)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_apps_are_sorted_by_display_name_case_insensitively() {
        let index = AppIndex::new(vec![
            app("zoom", "Zoom"),
            app("arc", "arc"),
            app("safari", "Safari"),
        ]);

        let names: Vec<&str> = index
            .get_all_sorted()
            .into_iter()
            .map(|app| app.display_name.as_str())
            .collect();

        assert_eq!(names, vec!["arc", "Safari", "Zoom"]);
    }

    fn app(search_name: &str, display_name: &str) -> AppEntry {
        AppEntry {
            display_name: display_name.to_string(),
            search_name: search_name.to_string(),
            aliases: Vec::new(),
            path: format!("/Applications/{display_name}.app"),
            bundle_id: None,
            icon_png: None,
            ranking: 0,
            is_favourite: false,
        }
    }

    #[test]
    fn searches_localized_application_aliases() {
        let mut netease = app("neteasemusic", "NetEaseMusic");
        netease.aliases = vec!["网易云音乐".to_string()];

        let index = AppIndex::new(vec![netease]);
        let results = index.search("网易云音乐");

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].display_name, "NetEaseMusic");
    }

    #[test]
    fn test_exact_match() {
        assert_eq!(fuzzy_score("safari", "safari", "Safari"), 200);
    }

    #[test]
    fn test_prefix_match() {
        assert!(fuzzy_score("orb", "orbstack", "OrbStack") >= 150);
    }

    #[test]
    fn test_word_boundary_match() {
        // "os" → OrbStack (O + S at camelCase boundary)
        assert!(fuzzy_score("os", "orbstack", "OrbStack") > 0);
    }

    #[test]
    fn test_vsc_visual_studio_code() {
        assert!(fuzzy_score("vsc", "visual studio code", "Visual Studio Code") > 0);
    }

    #[test]
    fn test_subsequence_match() {
        // "obstack" is subsequence of "orbstack"
        assert!(fuzzy_score("obstack", "orbstack", "OrbStack") > 0);
    }

    #[test]
    fn test_contains_match() {
        assert!(fuzzy_score("stack", "orbstack", "OrbStack") >= 100);
    }

    #[test]
    fn test_no_match() {
        assert_eq!(fuzzy_score("xyz", "safari", "Safari"), 0);
    }

    #[test]
    fn test_prefix_beats_subsequence() {
        let prefix = fuzzy_score("orb", "orbstack", "OrbStack");
        let subseq = fuzzy_score("obstack", "orbstack", "OrbStack");
        assert!(prefix > subseq);
    }

    #[test]
    fn test_ij_intellij() {
        // "ij" → IntelliJ IDEA
        assert!(fuzzy_score("ij", "intellij idea", "IntelliJ IDEA") > 0);
    }
}
