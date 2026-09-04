// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// Rows for the settings screen.
//
// Upstream builds its list with the `settings_ui` package. That package cannot
// draw what the design calls for: its Android sections are full-width bands
// with no radius, and rounded cards only come with `DevicePlatform.iOS`, which
// also swaps in `CupertinoSwitch` and iOS chevrons. On an Android app the
// Material controls matter more than the card corners, so neither of its two
// looks fits — hence these.
//
// What they add over a `SettingsTile`
// -----------------------------------
//   * A value on the right of a navigation row, so the current server, language
//     or quality is readable without opening anything.
//   * A one-line description under a title, for the rows whose names do not
//     explain themselves.
//   * A `risk` flag, for the one toggle that lowers security when enabled.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../drx_brand.dart';

const double _kRadius = 13;
const double _kRowMinHeight = 48;

/// A titled group of rows, drawn as one rounded card.
class DrxSettingsGroup extends StatelessWidget {
  const DrxSettingsGroup({Key? key, required this.title, required this.rows})
      : super(key: key);

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final line = MyTheme.color(context).border ?? Colors.grey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 7),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: DrxBrand.accentOf(context),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(color: line),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: line),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared skeleton: leading icon, title (+ description), trailing widget.
class DrxSettingsRow extends StatelessWidget {
  const DrxSettingsRow({
    Key? key,
    required this.icon,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.risk = false,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// Marks a switch that weakens security when turned on. The badge is the
  /// only thing that separates it from the toggles around it.
  final bool risk;

  @override
  Widget build(BuildContext context) {
    final muted = DrxBrand.mutedOf(context);
    final warn = DrxBrand.warningOf(context);
    final body = Theme.of(context).textTheme.bodyMedium?.color;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _kRowMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 19, color: muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: enabled ? body : muted,
                            ),
                          ),
                        ),
                        if (risk) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: warn.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              translate('Risky'),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: warn,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (description != null && description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description!,
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A row that opens something: shows the current value and a chevron.
class DrxNavRow extends StatelessWidget {
  const DrxNavRow({
    Key? key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.description,
    this.value,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String? description;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = DrxBrand.mutedOf(context);
    return DrxSettingsRow(
      icon: icon,
      title: title,
      description: description,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 19, color: muted.withOpacity(0.7)),
        ],
      ),
    );
  }
}

/// A row that flips an option.
///
/// [onChanged] is null when the option is pinned by the deployment, which is
/// how upstream disables a tile; the row then reads as inactive rather than
/// disappearing, so the value is still visible.
class DrxSwitchRow extends StatelessWidget {
  const DrxSwitchRow({
    Key? key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.risk = false,
  }) : super(key: key);

  final IconData icon;
  final String title;
  final String? description;
  final bool value;
  final Future<void> Function(bool)? onChanged;
  final bool risk;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return DrxSettingsRow(
      icon: icon,
      title: title,
      description: description,
      enabled: enabled,
      risk: risk,
      onTap: enabled ? () => onChanged!(!value) : null,
      trailing: Switch(
        value: value,
        activeColor: DrxBrand.accentOf(context),
        onChanged: enabled ? (v) => onChanged!(v) : null,
      ),
    );
  }
}
