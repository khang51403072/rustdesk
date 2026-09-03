// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// This whole module is fork-specific. Upstream RustDesk has no equivalent file.
//
// Why it exists
// -------------
// Upstream ships client-wide defaults in a `custom.txt` blob that is signed with
// RustDesk's own Ed25519 private key and verified in `common::read_custom_client`.
// A fork cannot produce a valid blob, so that whole mechanism is unusable for us.
//
// This module reuses the *same* document format and the *same* key-mapping code
// (`common::apply_custom_client_json`) but skips signature verification, because
// the documents come from sources we control: a constant compiled into the binary
// and, optionally, a file inside the app's private data directory.
//
// What it does NOT do
// -------------------
// It never forces a value on the user. Everything written here lands in the
// `DEFAULT_*` maps, which sit *below* the user's own config file in the lookup
// chain (see CUSTOM_CONFIG.md). Anything the user changes in Settings still wins.
// Values that must be locked go in `override-settings`, which we deliberately
// leave empty by default.
//
// Where to change things
// ----------------------
//   * to change shipped defaults for every build -> edit BUILTIN_DEFAULTS below
//   * to change defaults for one deployment      -> drop DEVICE_CONFIG_FILE_NAME
//                                                   into the app data dir
//
// See CUSTOM_CONFIG.md at the repo root for the full reference.
// ============================================================================

use hbb_common::{config, log};

/// Name of the optional per-deployment config file, looked up inside the app's
/// private data directory (`config::APP_DIR` on Android/iOS, the config dir
/// elsewhere). Absent file = only the built-in defaults apply.
pub const DEVICE_CONFIG_FILE_NAME: &str = "drx-defaults.json";

/// Defaults compiled into the binary.
///
/// Same document format as upstream's signed `custom.txt`, minus the signature:
///
/// ```json
/// {
///   "default-settings": { "<key>": "<value>" },
///   "override-settings": { "<key>": "<value>" }
/// }
/// ```
///
/// Keys are written in dash form; the loader matches them against
/// `KEYS_LOCAL_SETTINGS`, `KEYS_SETTINGS`, `KEYS_DISPLAY_SETTINGS` and
/// `KEYS_BUILDIN_SETTINGS` after normalising `_` to `-`.
///
/// The current set biases the client toward direct peer-to-peer connections.
/// Rationale for each key is in CUSTOM_CONFIG.md.
pub const BUILTIN_DEFAULTS: &str = r#"{
  "default-settings": {
    "enable-udp-punch": "Y",
    "enable-ipv6-punch": "Y",
    "allow-websocket": "N",
    "disable-udp": "N",
    "enable-lan-discovery": "Y",
    "enable-abr": "Y",
    "disable-floating-window": "N",
    "codec-preference": "auto"
  },
  "override-settings": {}
}"#;

/// Apply the fork's default settings.
///
/// Call order matters and is intentional:
///   1. `BUILTIN_DEFAULTS` — shipped with the binary.
///   2. `DEVICE_CONFIG_FILE_NAME` — per-deployment file, overwrites step 1.
///
/// Both only touch the `DEFAULT_*` maps (unless a document explicitly uses
/// `override-settings`), so a real signed upstream blob applied earlier would
/// be overwritten by ours. That is acceptable here because this fork never
/// loads a signed blob; if that ever changes, revisit the ordering in
/// `flutter_ffi::initialize`.
///
/// Safe to call more than once: applying the same document twice is idempotent.
pub fn load() {
    apply(BUILTIN_DEFAULTS.as_bytes(), "built-in DRX defaults");

    match device_config_path() {
        Some(path) => match std::fs::read(&path) {
            Ok(bytes) => {
                log::info!("Loading DRX device config from {}", path.display());
                apply(&bytes, "DRX device config file");
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                // Normal case: no per-deployment override on this device.
            }
            Err(err) => {
                log::warn!("Failed to read {}: {}", path.display(), err);
            }
        },
        None => {
            log::debug!("DRX device config path unavailable, skipping");
        }
    }
}

/// Resolve the absolute path of the per-deployment config file.
///
/// On Android and iOS `config::APP_DIR` is set by the host before the Rust side
/// starts; everywhere else we fall back to the directory that already holds the
/// app's own toml config so the file sits next to it.
fn device_config_path() -> Option<std::path::PathBuf> {
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let dir = config::APP_DIR.read().unwrap().clone();
        if dir.is_empty() {
            return None;
        }
        return Some(std::path::PathBuf::from(dir).join(DEVICE_CONFIG_FILE_NAME));
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        config::Config::path("")
            .parent()
            .map(|p| p.join(DEVICE_CONFIG_FILE_NAME))
    }
}

/// Hand one document to the shared upstream key-mapping code.
fn apply(bytes: &[u8], source: &str) {
    if bytes.is_empty() {
        return;
    }
    crate::common::apply_custom_client_json(bytes, source);
}
