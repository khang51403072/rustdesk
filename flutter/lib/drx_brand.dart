// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The Desk Remote X brand palette, in one place.
//
// Why it exists
// -------------
// Upstream scatters its brand colours as literals inside `MyTheme` in
// `lib/common.dart` — a file that changes often upstream. Re-theming by editing
// those literals in place means a merge conflict in the middle of `MyTheme` on
// every sync. Instead, `MyTheme` now *points at* the constants below, so the
// diff against upstream stays a handful of one-line substitutions and this file
// (which upstream has no counterpart for) can never conflict.
//
// How to re-brand
// ---------------
// Change the values here. Nothing else. Every screen already reads its colours
// from `MyTheme` / `ColorThemeExtension`, which are wired to these.
//
// What is deliberately NOT here
// -----------------------------
//   * Launcher icons and the splash logo — image assets, not theme values.
//     See `flutter/android/app/src/main/res/mipmap-*`.
//   * The app name — that lives in `res/values/strings.xml` on Android and in
//     `app-name` of the custom-client config on the Rust side.
//   * Semantic colours that are not brand-owned (success green, warning amber):
//     they carry meaning, so they stay recognisable rather than on-brand.
//
// See CUSTOM_CONFIG.md at the repo root, section "Theme".
// ============================================================================

import 'package:flutter/material.dart';

class DrxBrand {
  DrxBrand._();

  // ---------------------------------------------------------------- identity
  // Sampled from the XSOFTS mark and the product web app.

  /// The primary brand blue. This is the colour of the "X" in the logo and of
  /// every primary action in the product. Upstream's equivalent was 0xFF0071FF.
  static const Color primary = Color(0xFF2F9BFF);

  /// A darker shade of [primary], used where the bright blue would vibrate
  /// against a dark background (pressed states, gradients, the logo's shadow).
  static const Color primaryDeep = Color(0xFF0B5FD0);

  /// A lighter shade, for text and icons that sit *on* a dark surface and must
  /// stay legible at small sizes — the peer-ID text, mainly.
  static const Color primaryLight = Color(0xFF5FB4FF);

  // Translucent variants. Kept as explicit ARGB constants rather than
  // `primary.withOpacity(...)` because `MyTheme`'s fields are `const`.
  static const Color primary50 = Color(0x772F9BFF);
  static const Color primary80 = Color(0xAA2F9BFF);

  // ------------------------------------------------------------ dark surfaces
  // The product web app is dark-first, and so is this app (the shipped default
  // theme is "dark", set in src/custom_defaults.rs). These are a navy-leaning
  // neutral ramp: each step is a little lighter and a little bluer than the one
  // before, so elevation reads without needing shadows.

  /// Page background — the darkest surface. Upstream: 0xFF18191E (neutral grey).
  static const Color darkBg = Color(0xFF12161C);

  /// Cards, dialogs, input fills — one step up from [darkBg].
  /// Upstream: 0xFF24252B.
  static const Color darkSurface = Color(0xFF1A2029);

  /// Menus and popups, which must separate from a card already sitting on
  /// [darkSurface].
  static const Color darkSurfaceAlt = Color(0xFF222B36);

  /// Hover / pressed feedback on a dark surface. Upstream: rgb(45, 46, 53).
  static const Color darkHover = Color(0xFF263140);

  /// Selected row or tab — a blue-tinted surface, not a grey one, so selection
  /// reads as "brand" rather than as "disabled".
  static const Color darkSelected = Color(0xFF1B3350);

  /// App bar and bottom navigation. Chrome sits one step above the page but
  /// below a card, so it reads as a frame rather than as content.
  static const Color darkAppBar = Color(0xFF161D27);

  /// Hairlines between sections on dark. Upstream: 0xFF555555.
  static const Color darkBorder = Color(0xFF2C3543);

  // ----------------------------------------------------------- light surfaces
  // The light theme is kept close to upstream: it is a fallback for users who
  // opt out of dark, not the designed-for path.

  /// Panel / card background on light. Upstream: 0xFFEFEFF2.
  static const Color lightSurface = Color(0xFFEFF2F7);

  /// App bar and bottom navigation on light. Plain white so the chrome reads
  /// as a frame around the slightly tinted cards.
  static const Color lightAppBar = Color(0xFFFFFFFF);

  /// Hairlines on light. Upstream: 0xFFCCCCCC.
  static const Color lightBorder = Color(0xFFCFD6E0);

  // ------------------------------------------------------------------ neutral
  /// Secondary text and inactive icons, on either theme.
  static const Color muted = Color(0xFF94A3B3);

  // ------------------------------------------------------------- per-theme
  // These have no single value: the same hue has to sit at a different
  // lightness on white than it does on the dark ramp, or one of the two fails
  // contrast. `MyTheme.accent` cannot express that — it is a `static const`, so
  // it has no idea which theme is live. Until that is reworked, widgets that
  // need a theme-correct value pick from the pairs below via [onDark].

  /// Action blue: buttons, links, the selected tab. `MyTheme.accent` is a
  /// single value used on both grounds and only reaches 2.9 on white — below
  /// the 4.5 needed to read — so anything drawn by this fork uses [accentOf]
  /// instead. Replacing `MyTheme.accent` itself would touch ~87 call sites
  /// across mobile and desktop, so it is a separate job.
  static const Color accentOnLight = Color(0xFF1459C0); // 6.5 on white
  static const Color accentOnDark = Color(0xFF5FB8FF); // 7.9 on darkAppBar

  /// Secondary text and inactive icons. `muted` is likewise a single value and
  /// only reaches 2.6 on white.
  static const Color mutedOnLight = Color(0xFF606F82); // 5.1 on white
  static const Color mutedOnDark = Color(0xFF93A4B8); // 6.7 on darkAppBar

  /// Identity blue: the peer ID, QR codes, the platform badge. Deliberately
  /// distinct from the action blue — one says "which machine", the other says
  /// "tap me".
  static const Color identityOnLight = Color(0xFF0B6E8F); // 5.8 on white
  static const Color identityOnDark = Color(0xFF4FD3F5); // 10.6 on darkBg

  /// The primary-action gradient, taken from the darker half of the logo's
  /// sweep. The bright cyan end cannot carry white text — it only reaches 2.0 —
  /// so a gradient that sits under a label is built from these two instead.
  static const Color actionGradientStart = Color(0xFF2170CE); // white: 4.9
  static const Color actionGradientEnd = Color(0xFF16409E);

  /// Pick the dark-theme value when [dark] is true.
  static Color onDark(bool dark, Color light, Color darkValue) =>
      dark ? darkValue : light;

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Action blue for the live theme.
  static Color accentOf(BuildContext context) =>
      _isDark(context) ? accentOnDark : accentOnLight;

  /// Identity blue for the live theme.
  static Color identityOf(BuildContext context) =>
      _isDark(context) ? identityOnDark : identityOnLight;

  /// Secondary text / inactive icon colour for the live theme.
  static Color mutedOf(BuildContext context) =>
      _isDark(context) ? mutedOnDark : mutedOnLight;

  // ---------------------------------------------------------------- semantic
  // Not brand-owned on purpose — see the header note.

  /// Affirmative state: connected, service running, permission granted.
  static const Color success = Color(0xFF22C55E);

  /// Decorative gradient on the connection-manager header
  /// (`lib/mobile/pages/server_page.dart`). Upstream used a pink-to-coral pair
  /// that clashes with the brand blue.
  static const Color gradientStart = primaryDeep;
  static const Color gradientEnd = primary;
}
