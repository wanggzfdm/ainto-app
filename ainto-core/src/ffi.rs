//! C ABI FFI exports for Swift interop.
//!
//! All functions use C-compatible types. Strings are returned as null-terminated
//! C strings allocated by Rust; the caller must free them with `rc_free_string`.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::Mutex;

use crate::{config, discovery, search, snippets};

// ============================================================
// Global State
// ============================================================

static APP_INDEX: Mutex<Option<search::AppIndex>> = Mutex::new(None);

fn to_c_string(s: &str) -> *const c_char {
    CString::new(s)
        .map(|cs| cs.into_raw() as *const c_char)
        .unwrap_or(ptr::null())
}

fn from_c_str(s: *const c_char) -> Option<String> {
    if s.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(s) }.to_str().ok().map(|s| s.to_string())
}

// ============================================================
// Memory Management
// ============================================================

#[unsafe(no_mangle)]
pub extern "C" fn rc_free_string(s: *const c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s as *mut c_char));
        }
    }
}

// ============================================================
// Config
// ============================================================

#[unsafe(no_mangle)]
pub extern "C" fn rc_config_load() -> *const c_char {
    match config::Config::load() {
        Ok(cfg) => {
            let json = serde_json::to_string(&cfg).unwrap_or_default();
            to_c_string(&json)
        }
        Err(_) => {
            let json = serde_json::to_string(&config::Config::default()).unwrap_or_default();
            to_c_string(&json)
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_config_save(json: *const c_char) -> i32 {
    let Some(json_str) = from_c_str(json) else {
        return -1;
    };
    let Ok(cfg) = serde_json::from_str::<config::Config>(&json_str) else {
        return -1;
    };
    match cfg.save() {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

// ============================================================
// App Discovery & Search
// ============================================================

#[unsafe(no_mangle)]
pub extern "C" fn rc_discover_apps(store_icons: bool) -> *const c_char {
    let apps = discovery::get_installed_apps(store_icons);

    // Build JSON manually since AppEntry isn't Serialize (has icon bytes)
    let json_entries: Vec<serde_json::Value> = apps
        .iter()
        .map(|a| {
            serde_json::json!({
                "display_name": a.display_name,
                "search_name": a.search_name,
                "path": a.path,
                "has_icon": a.icon_png.is_some(),
                "ranking": a.ranking,
                "is_favourite": a.is_favourite,
            })
        })
        .collect();

    // Store in global index
    if let Ok(mut idx) = APP_INDEX.lock() {
        // Load rankings
        let rankings = if let Ok(cfg_dir) = config::config_dir() {
            crate::ranking::load_rankings(&cfg_dir.join("ranking.toml"))
        } else {
            std::collections::HashMap::new()
        };
        let mut index = search::AppIndex::new(apps);
        index.apply_rankings(&rankings);
        *idx = Some(index);
    }

    let json = serde_json::to_string(&json_entries).unwrap_or_else(|_| "[]".to_string());
    to_c_string(&json)
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_search_apps(query: *const c_char) -> *const c_char {
    let Some(q) = from_c_str(query) else {
        return to_c_string("[]");
    };

    let guard = APP_INDEX.lock().ok();
    let results = guard
        .as_ref()
        .and_then(|opt| opt.as_ref())
        .map(|idx| {
            idx.search(&q)
                .iter()
                .map(|a| {
                    serde_json::json!({
                        "display_name": a.display_name,
                        "path": a.path,
                        "ranking": a.ranking,
                        "is_favourite": a.is_favourite,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let json = serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string());
    to_c_string(&json)
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_get_top_apps(limit: u64) -> *const c_char {
    let guard = APP_INDEX.lock().ok();
    let results = guard
        .as_ref()
        .and_then(|opt| opt.as_ref())
        .map(|idx| {
            idx.get_top_ranked(limit as usize)
                .iter()
                .map(|a| {
                    serde_json::json!({
                        "display_name": a.display_name,
                        "path": a.path,
                        "ranking": a.ranking,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let json = serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string());
    to_c_string(&json)
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_get_all_apps() -> *const c_char {
    let guard = APP_INDEX.lock().ok();
    let results = guard
        .as_ref()
        .and_then(|opt| opt.as_ref())
        .map(|idx| {
            idx.get_all_sorted()
                .iter()
                .map(|a| {
                    serde_json::json!({
                        "display_name": a.display_name,
                        "path": a.path,
                        "ranking": a.ranking,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let json = serde_json::to_string(&results).unwrap_or_else(|_| "[]".to_string());
    to_c_string(&json)
}

/// Increment ranking for any key (app path or "cmd:name") and persist.
/// Returns the new frecency score.
#[unsafe(no_mangle)]
pub extern "C" fn rc_increment_ranking(key: *const c_char) -> i32 {
    let Some(k) = from_c_str(key) else { return -1 };
    let Ok(cfg_dir) = config::config_dir() else { return -1 };
    let path = cfg_dir.join("ranking.toml");
    let score = crate::ranking::increment_and_save(&path, &k);

    // Also update in-memory AppIndex if it's an app path
    if !k.starts_with("cmd:") {
        if let Ok(mut idx) = APP_INDEX.lock() {
            if let Some(ref mut index) = *idx {
                index.update_ranking(&k);
            }
        }
    }
    score
}

/// Get frecency score for any key.
#[unsafe(no_mangle)]
pub extern "C" fn rc_get_ranking(key: *const c_char) -> i32 {
    let Some(k) = from_c_str(key) else { return 0 };
    let Ok(cfg_dir) = config::config_dir() else { return 0 };
    let path = cfg_dir.join("ranking.toml");
    crate::ranking::get_score(&path, &k)
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_update_ranking(app_path: *const c_char) {
    let Some(key) = from_c_str(app_path) else {
        return;
    };
    let Ok(cfg_dir) = config::config_dir() else { return };
    let path = cfg_dir.join("ranking.toml");
    let score = crate::ranking::increment_and_save(&path, &key);

    // Update in-memory AppIndex
    if let Ok(mut idx) = APP_INDEX.lock() {
        if let Some(ref mut index) = *idx {
            index.update_ranking(&key);
            // Set the ranking to the frecency score
            if let Some(app) = index.apps_mut().iter_mut().find(|a| a.path == key) {
                app.ranking = score;
            }
        }
    }
}


// ============================================================
// Snippets
// ============================================================

#[unsafe(no_mangle)]
pub extern "C" fn rc_snippets_load() -> *const c_char {
    let path = config::config_dir()
        .map(|d| d.join("snippets.toml"))
        .unwrap_or_default();
    let snips = snippets::load_snippets(&path).unwrap_or_default();
    let json = serde_json::to_string(&snips).unwrap_or_else(|_| "[]".to_string());
    to_c_string(&json)
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_snippets_save(json: *const c_char) -> i32 {
    let Some(json_str) = from_c_str(json) else {
        return -1;
    };
    let Ok(snips) = serde_json::from_str::<Vec<snippets::Snippet>>(&json_str) else {
        return -1;
    };
    let path = match config::config_dir() {
        Ok(d) => d.join("snippets.toml"),
        Err(_) => return -1,
    };
    match snippets::save_snippets(&path, &snips) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_snippet_expand(
    expansion_text: *const c_char,
    clipboard_text: *const c_char,
) -> *const c_char {
    let Some(text) = from_c_str(expansion_text) else {
        return ptr::null();
    };
    let clip = from_c_str(clipboard_text);
    let result = snippets::resolve_placeholders(&text, clip.as_deref());
    to_c_string(&result)
}

// ============================================================
// AI Commands
// ============================================================

#[unsafe(no_mangle)]
pub extern "C" fn rc_ai_commands_load() -> *const c_char {
    let path = config::config_dir()
        .map(|d| d.join("ai-commands.toml"))
        .unwrap_or_default();
    let cmds = crate::ai_commands::load_commands(&path).unwrap_or_default();
    let json = serde_json::to_string(&cmds).unwrap_or_else(|_| "[]".to_string());
    to_c_string(&json)
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_ai_commands_save(json: *const c_char) -> i32 {
    let Some(json_str) = from_c_str(json) else {
        return -1;
    };
    let Ok(cmds) = serde_json::from_str::<Vec<crate::ai_commands::AiCommand>>(&json_str) else {
        return -1;
    };
    let path = match config::config_dir() {
        Ok(d) => d.join("ai-commands.toml"),
        Err(_) => return -1,
    };
    match crate::ai_commands::save_commands(&path, &cmds) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

// ============================================================
// Claude Code
// ============================================================

// Claude sessions are boxed and passed as opaque pointers
use crate::claude::ClaudeSession;

#[unsafe(no_mangle)]
pub extern "C" fn rc_claude_start(
    query: *const c_char,
    binary: *const c_char,
    resume_session_id: *const c_char,
) -> *mut std::ffi::c_void {
    let Some(q) = from_c_str(query) else {
        return ptr::null_mut();
    };
    let bin = from_c_str(binary).unwrap_or_else(|| "claude".to_string());
    let resume_id = from_c_str(resume_session_id);

    match ClaudeSession::start(&q, &bin, resume_id.as_deref()) {
        Ok(session) => Box::into_raw(Box::new(session)) as *mut std::ffi::c_void,
        Err(_) => ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_claude_get_session_id(session: *mut std::ffi::c_void) -> *const c_char {
    if session.is_null() {
        return ptr::null();
    }
    let session = unsafe { &*(session as *const ClaudeSession) };
    match &session.session_id {
        Some(id) => to_c_string(id),
        None => ptr::null(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_claude_next_chunk(session: *mut std::ffi::c_void) -> *const c_char {
    if session.is_null() {
        return ptr::null();
    }
    let session = unsafe { &mut *(session as *mut ClaudeSession) };

    match session.next_chunk() {
        Some(text) => to_c_string(&text),
        None => ptr::null(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_claude_get_response(session: *mut std::ffi::c_void) -> *const c_char {
    if session.is_null() {
        return to_c_string("");
    }
    let session = unsafe { &*(session as *const ClaudeSession) };
    to_c_string(&session.response)
}

#[unsafe(no_mangle)]
pub extern "C" fn rc_claude_get_stderr(session: *mut std::ffi::c_void) -> *const c_char {
    if session.is_null() {
        return to_c_string("");
    }
    let session = unsafe { &mut *(session as *mut ClaudeSession) };
    let error = session.get_error();
    to_c_string(&error)
}

/// Cancel the running session (kill child process).
/// Does NOT free memory — the background reader thread may still hold the pointer.
/// Call `rc_claude_free` after the reader thread has finished.
#[unsafe(no_mangle)]
pub extern "C" fn rc_claude_cancel(session: *mut std::ffi::c_void) {
    if !session.is_null() {
        let session = unsafe { &mut *(session as *mut ClaudeSession) };
        session.cancel();
    }
}

/// Free a Claude session. Must only be called after the reader thread has finished
/// (i.e., after `rc_claude_next_chunk` returned null).
#[unsafe(no_mangle)]
pub extern "C" fn rc_claude_free(session: *mut std::ffi::c_void) {
    if !session.is_null() {
        unsafe { drop(Box::from_raw(session as *mut ClaudeSession)) };
    }
}
