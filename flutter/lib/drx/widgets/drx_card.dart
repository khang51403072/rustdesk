// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The card the new mobile screens are built from.
//
// Upstream has `PaddingCard` in `server_page.dart`, but it is private to that
// file's layout in practice: it hard-codes a 12/10/12/0 margin because it is
// always used inside a full-bleed `Column`, and it draws no border, which the
// dark palette needs to separate a card from the page behind it. This one takes
// its margin from the caller instead.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'package:flutter/material.dart';

import '../../common.dart';

const double kDrxCardRadius = 13;

class DrxCard extends StatelessWidget {
  const DrxCard({
    Key? key,
    this.title,
    this.titleIcon,
    this.accent,
    required this.children,
  }) : super(key: key);

  final String? title;
  final IconData? titleIcon;

  /// Tints the border and the title icon. Use it when the card itself is the
  /// message — a missing permission, a stopped service — so the card reads as
  /// needing attention without shouting in a filled colour.
  final Color? accent;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      // Matches `PaddingCard`'s 12px inset from `server_page.dart`. The share
      // screen mixes both kinds of card — `ConnectionManager` still uses
      // upstream's — and a different inset would make the column look ragged.
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(kDrxCardRadius),
        border: Border.all(
          color: accent ?? MyTheme.color(context).border ?? Colors.grey,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (titleIcon != null) ...[
                  Icon(titleIcon, size: 19, color: accent),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    title!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// Hairline between rows inside a [DrxCard].
class DrxCardDivider extends StatelessWidget {
  const DrxCardDivider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: MyTheme.color(context).border,
    );
  }
}
