// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The fork's own web addresses.
//
// Why they need a home
// --------------------
// `translate()` swaps the string "RustDesk" for the app name (`src/lang.rs`),
// so titles rebrand themselves. A URL is not a translated string, so every
// hard-coded `rustdesk.com` survived the rebrand and kept sending users to
// upstream's site. Collecting them here means the next rename touches one file.
//
// What is deliberately NOT here
// -----------------------------
//   * Documentation links (`rustdesk.com/docs/...`). They point at pages that
//     exist and are still correct for this client; repointing them at a site
//     that does not host those docs would turn working help into 404s.
//   * `admin.rustdesk.com`, `rs-ny.rustdesk.com` and the version-check API.
//     Those are infrastructure defaults, not branding — and `is_public()` in
//     `src/common.rs` recognises the public servers by that domain, so renaming
//     it would break the check that decides whether a deployment is self-hosted.
//   * Anything under `libs/hbb_common`: that is a submodule.
//   * The Sciter UI in `src/ui/`, which upstream marks deprecated.
//
// See CUSTOM_CONFIG.md at the repo root.
// ============================================================================

class DrxLinks {
  DrxLinks._();

  /// Product home page.
  static const String home = 'https://galaxyaccess.us';

  /// Privacy statement, shown in the installer and in Settings.
  static const String privacy = 'https://galaxyaccess.us/privacy.html';

  /// Where a user is sent to get a newer build.
  static const String download = 'https://galaxyaccess.us';
}
