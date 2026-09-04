// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The primary action button.
//
// Upstream reaches for `ElevatedButton`, which picks up `MyTheme.accent`
// (#2F9BFF) as its fill. White text on that only reaches 2.9 — under the 4.5
// needed to read. This one uses the action gradient, whose lighter stop is
// still dark enough to carry white text at 4.9.
//
// The gradient is the brand's signature, so it is spent on the one primary
// action of a screen and nothing else.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'package:flutter/material.dart';

import '../../drx_brand.dart';

class DrxPrimaryButton extends StatelessWidget {
  const DrxPrimaryButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  }) : super(key: key);

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  /// Stretch to the full width of the parent instead of hugging the label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            DrxBrand.actionGradientStart,
            DrxBrand.actionGradientEnd,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: DrxBrand.actionGradientStart.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return expand ? button : Align(alignment: Alignment.centerLeft, child: button);
  }
}
