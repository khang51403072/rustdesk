// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The switch that selects which mobile UI layer gets built.
//
// Why it exists
// -------------
// This fork is growing a new mobile UI under `lib/drx/` to replace
// `lib/mobile/pages/`. Both ship in the same binary; the flag below decides
// which one is mounted. Keeping both means there is always a way back when the
// new UI misbehaves on a real user's device.
//
// Where the flag comes from
// -------------------------
// The `ui` key sits at the TOP LEVEL of the custom-client config document, not
// inside `default-settings`. That is deliberate: a key under `default-settings`
// must already be registered in one of hbb_common's `KEYS_*` lists (a
// submodule), whereas an unrecognised top-level key is dropped straight into
// `HARD_SETTINGS` by `common::apply_custom_client_json`. This lets the fork add
// its own key without patching the submodule.
//
// How to change it
// ----------------
//   * for every build   -> edit BUILTIN_DEFAULTS in src/custom_defaults.rs
//   * for one device    -> put {"ui": "legacy"} in drx-defaults.json,
//                          no rebuild needed
//
// See CUSTOM_CONFIG.md at the repo root.
// ============================================================================

import 'package:flutter_hbb/models/platform_model.dart';

/// Value that forces the legacy UI under `lib/mobile/pages/`.
const String kUiLegacy = 'legacy';

bool? _useDrxUi;

/// Whether to mount the new UI layer under `lib/drx/`.
///
/// Read once and cached: this flag decides the root widget tree, so flipping it
/// mid-session would tear down every open page. Changing it requires an app
/// restart.
bool get useDrxUi {
  _useDrxUi ??= bind.mainGetHardOption(key: 'ui') != kUiLegacy;
  return _useDrxUi!;
}
