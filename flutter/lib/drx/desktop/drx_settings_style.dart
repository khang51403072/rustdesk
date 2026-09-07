// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// How the desktop settings screen is drawn.
//
// Why it is shaped this way
// -------------------------
// `desktop_setting_page.dart` is 3200 lines, but almost all of its pixels come
// out of three functions: `_Card` (26 call sites), `_OptionCheckBox` (42) and
// `_listItem` (the nav rail). Restyling those three bodies repaints all eight
// tabs without touching a single call site — so that is what this file is: the
// three replacement bodies, with the upstream file keeping one `if (useDrxUi)`
// line apiece.
//
// Keeping them here rather than inline serves the merge: upstream changes that
// file often, and every line this fork adds to it is a line that can conflict.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new UI layer).
// ============================================================================

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../drx_brand.dart';

/// Card geometry, shared with the sidebar cards on the home screen and with
/// `drx/widgets/drx_card.dart` on mobile.
const double _kRadius = 13;

/// How wide a settings group is allowed to grow. Past this a row is mostly
/// empty space between a switch on the left and nothing on the right.
const double _kCardMaxWidth = 820;

/// Vertical room an option row gets. See the note in [DrxOptionSwitch].
const double _kSwitchRowHeight = 30;

/// A settings group.
///
/// Upstream wraps a Material `Card`, which on the dark theme renders as a
/// slightly lighter rectangle with an elevation shadow and no edge — on an OLED
/// panel the group boundaries disappear. This draws the border instead, the
/// same hairline every other surface in the fork uses.
///
/// [width] is upstream's `_kCardFixedWidth` — a hard 540 that leaves two
/// thirds of a maximised window empty. It becomes a floor here, not the width:
/// the card grows with the pane up to [_kCardMaxWidth] and then centres, so the
/// leftover space sits evenly on both sides instead of pooling on the right.
/// Horizontal padding is deliberately small: the children arrive with their own
/// left margins (`_kCheckBoxLeftMargin`, `_kContentHMargin`) baked in, so a
/// roomy padding here would indent everything twice.
Widget drxSettingsCard({
  required BuildContext context,
  required String title,
  required List<Widget> children,
  List<Widget>? titleSuffix,
  required double width,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final available =
          constraints.maxWidth.isFinite ? constraints.maxWidth : width;
      final cardWidth =
          min(max(available - 30, width), _kCardMaxWidth).toDouble();
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: cardWidth,
          margin: const EdgeInsets.only(top: 13),
          padding: const EdgeInsets.fromLTRB(2, 12, 12, 13),
          decoration: BoxDecoration(
            color: DrxBrand.cardOf(context),
            borderRadius: BorderRadius.circular(_kRadius),
            border: Border.all(
              color: MyTheme.color(context).border ?? Colors.grey,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      translate(title),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ).marginOnly(left: 13),
                  ),
                  ...?titleSuffix,
                ],
              ),
              const SizedBox(height: 4),
              // No per-child margin, on purpose. Upstream adds `top: 4` to
              // every child, which produces two different rhythms and a
              // phantom gap:
              //   * a card whose rows are direct children spaces them by
              //     row + margin, while a card that nests its rows in one
              //     Column child (Permissions) spaces them by row alone;
              //   * a child that renders nothing — `wallpaper()` is an
              //     `Offstage` off Windows, and several others are futures
              //     that resolve to one — still gets its margin, leaving a
              //     gap where no option is.
              // Letting the row own its height fixes both: invisible children
              // contribute nothing, and nested or not, every option row lands
              // on the same pitch. A ComboBox is the one child that needs air
              // of its own, and it is never the invisible kind.
              ...children.map(
                (e) => e is ComboBox ? e.marginOnly(top: 8, bottom: 4) : e,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The control on an option row.
///
/// Upstream uses a `Checkbox`. A switch says "this is on / this is off", which
/// is what every one of those 42 rows means; a checkbox says "this is selected",
/// which none of them do. Behaviour is untouched — the caller still owns the
/// value, the option key and the writes.
class DrxOptionSwitch extends StatelessWidget {
  const DrxOptionSwitch({
    Key? key,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  final bool value;

  /// Null when the option is disabled or fixed by the deployment's config.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final accent = DrxBrand.accentOf(context);
    final border = MyTheme.color(context).border ?? Colors.grey;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? () => onChanged!(!value) : null,
        // A Material `Checkbox` reserves a 48px tap target, and every option
        // row in this file leans on that for its height. A bare 20px track
        // collapses the rows into each other, so the box keeps a floor of its
        // own — smaller than 48, since these rows read better tighter, but
        // enough that ten of them in a card do not touch.
        child: Container(
          height: _kSwitchRowHeight,
          alignment: Alignment.center,
          child: Container(
            width: 36,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: value ? accent : Colors.transparent,
              border: Border.all(color: value ? accent : border),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? Colors.white : DrxBrand.mutedOf(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry in the settings nav rail.
///
/// Upstream marks the selected tab with a 4px bar down its left edge. This
/// fills the whole row instead, matching the peer tabs and the sidebar rows on
/// the home screen — one selection idiom across the window.
Widget drxSettingsNavItem({
  required BuildContext context,
  required String label,
  required IconData icon,
  required bool selected,
  required VoidCallback onTap,
  required double height,
}) {
  final accent = DrxBrand.accentOf(context);
  final muted = DrxBrand.mutedOf(context);
  final color = selected ? accent : muted;
  return Padding(
    padding: const EdgeInsets.fromLTRB(10, 1, 10, 1),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        height: height - 6,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: selected ? accent.withOpacity(0.14) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
