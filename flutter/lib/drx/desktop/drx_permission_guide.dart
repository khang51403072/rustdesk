// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The three macOS permissions this app needs, and the dialog that walks a user
// through granting one.
//
// Why the dialog exists
// ---------------------
// Upstream's permission card offers `Help`, which opens rustdesk.com's docs:
// upstream's page, about upstream's app, in English. A user who has just been
// told this app cannot type on their Mac should not have to leave it, find the
// right paragraph on a website, and translate the app name in their head.
//
// Why `Configure` alone is not enough
// -----------------------------------
// It asks the SYSTEM to prompt, and macOS prompts once per permission. After
// the user dismisses that alert the API returns without showing anything, and
// the only way left is to grant it by hand — which is what the steps here
// describe, and what the button at the end opens.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new UI layer).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// `common.dart` exports a `Dialog` of its own (the CustomAlertDialog
// machinery); this file wants Material's.
import '../../common.dart' hide Dialog;
import '../../drx_brand.dart';
import '../../models/platform_model.dart';

/// Deep links into System Settings > Privacy & Security.
///
/// The scheme is the one the core already uses: `src/platform/macos.mm` opens
/// `?Privacy_ListenEvent` this way when input monitoring is denied. The app is
/// not sandboxed (macos/Runner/*.entitlements), so NSWorkspace will open it.
const String _kPaneScreen =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture';
const String _kPaneAccessibility =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility';
const String _kPaneInput =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent';

enum DrxPermissionKind { screen, accessibility, input }

/// One macOS permission: what it is called, whether it is granted, how to ask
/// for it, and where its settings pane lives.
class DrxPermission {
  const DrxPermission(this.kind);

  final DrxPermissionKind kind;

  /// In the order macOS itself wants them granted, which is the order upstream
  /// checks them in `buildHelpCards`.
  static const List<DrxPermission> all = [
    DrxPermission(DrxPermissionKind.screen),
    DrxPermission(DrxPermissionKind.accessibility),
    DrxPermission(DrxPermissionKind.input),
  ];

  /// The name as System Settings lists it.
  String get label {
    switch (kind) {
      case DrxPermissionKind.screen:
        return translate('Screen Recording');
      case DrxPermissionKind.accessibility:
        return translate('Accessibility');
      case DrxPermissionKind.input:
        return translate('Input Monitoring');
    }
  }

  /// One line on what this permission buys, for the row in the sidebar.
  /// Upstream has no short form — [why] is a full sentence built for a card
  /// with room to breathe, and it wraps to four lines in a 248px column.
  String get description {
    switch (kind) {
      case DrxPermissionKind.screen:
        return translate('Share what is on this screen');
      case DrxPermissionKind.accessibility:
        return translate('Let an operator control mouse and keyboard');
      case DrxPermissionKind.input:
        return translate('Deliver keystrokes to this computer');
    }
  }

  /// Upstream's own sentence explaining what breaks without it.
  String get why {
    switch (kind) {
      case DrxPermissionKind.screen:
        return translate('config_screen');
      case DrxPermissionKind.accessibility:
        return translate('config_acc');
      case DrxPermissionKind.input:
        return translate('config_input');
    }
  }

  String get pane {
    switch (kind) {
      case DrxPermissionKind.screen:
        return _kPaneScreen;
      case DrxPermissionKind.accessibility:
        return _kPaneAccessibility;
      case DrxPermissionKind.input:
        return _kPaneInput;
    }
  }

  /// Every one of these is a synchronous FFI read, cheap enough for a 1s poll.
  bool get granted {
    switch (kind) {
      case DrxPermissionKind.screen:
        return bind.mainIsCanScreenRecording(prompt: false);
      case DrxPermissionKind.accessibility:
        return bind.mainIsProcessTrusted(prompt: false);
      case DrxPermissionKind.input:
        return bind.mainIsCanInputMonitoring(prompt: false);
    }
  }

  /// Ask macOS to show its own prompt. Silently does nothing once the user has
  /// dismissed that prompt before — hence the guide.
  void prompt() {
    switch (kind) {
      case DrxPermissionKind.screen:
        bind.mainIsCanScreenRecording(prompt: true);
        break;
      case DrxPermissionKind.accessibility:
        bind.mainIsProcessTrusted(prompt: true);
        break;
      case DrxPermissionKind.input:
        bind.mainIsCanInputMonitoring(prompt: true);
        break;
    }
  }

  void openSettings() => launchUrl(Uri.parse(pane));
}

/// Signature of all three states, for a caller that polls and wants to know
/// whether anything changed before rebuilding.
String drxPermissionSignature() =>
    DrxPermission.all.map((p) => p.granted ? '1' : '0').join();

void showDrxPermissionGuide(BuildContext context, DrxPermission permission) {
  showDialog(
    context: context,
    builder: (context) => _DrxPermissionGuideDialog(permission: permission),
  );
}

class _DrxPermissionGuideDialog extends StatefulWidget {
  const _DrxPermissionGuideDialog({Key? key, required this.permission})
      : super(key: key);

  final DrxPermission permission;

  @override
  State<_DrxPermissionGuideDialog> createState() =>
      _DrxPermissionGuideDialogState();
}

class _DrxPermissionGuideDialogState extends State<_DrxPermissionGuideDialog> {
  int _step = 0;

  List<String> get _steps => [
        translate('Open System Settings, then Privacy & Security'),
        translate('Pick {${widget.permission.label}} from the list'),
        translate('Turn on the switch next to {${bind.mainGetAppNameSync()}}'),
      ];

  bool get _isLast => _step == _steps.length - 1;

  @override
  Widget build(BuildContext context) {
    final warning = DrxBrand.warningOf(context);
    final muted = DrxBrand.mutedOf(context);
    return Dialog(
      backgroundColor: DrxBrand.cardOf(context),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: MyTheme.color(context).border ?? Colors.grey),
      ),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: warning.withOpacity(0.14),
                    ),
                    alignment: Alignment.center,
                    child:
                        Icon(Icons.shield_outlined, size: 17, color: warning),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate('Grant {${widget.permission.label}}'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.permission.why,
                          style: TextStyle(
                              fontSize: 11.5, height: 1.4, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close, size: 17, color: muted),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _DrxGuideIllustration(step: _step),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: List.generate(
                  _steps.length,
                  (i) => _buildStep(context, i),
                ),
              ),
            ),
            // macOS caches an app's accessibility trust for the life of the
            // process, so on some machines the switch goes on and this app
            // keeps reporting the permission as missing until it is reopened.
            // There is no way to tell that case apart from a permission that
            // really is off, so say it here rather than leave the user
            // staring at a card that will not change.
            if (_isLast)
              Padding(
                padding: const EdgeInsets.fromLTRB(25, 6, 16, 0),
                child: Text(
                  translate('Reopen {${bind.mainGetAppNameSync()}} to finish'),
                  style: TextStyle(fontSize: 10.5, height: 1.4, color: muted),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Row(
                children: [
                  Row(
                    children: List.generate(
                      _steps.length,
                      (i) => Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _step
                              ? DrxBrand.accentOf(context)
                              : MyTheme.color(context).border,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_step > 0)
                    _DrxGuideButton(
                      label: translate('Back'),
                      onPressed: () => setState(() => _step -= 1),
                    ),
                  if (_step > 0) const SizedBox(width: 8),
                  _DrxGuideButton(
                    label: _isLast
                        ? translate('Open System Setting')
                        : translate('Next'),
                    primary: true,
                    onPressed: () {
                      if (_isLast) {
                        widget.permission.openSettings();
                        Navigator.of(context).pop();
                      } else {
                        setState(() => _step += 1);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, int index) {
    final selected = index == _step;
    final accent = DrxBrand.accentOf(context);
    final muted = DrxBrand.mutedOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => setState(() => _step = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: selected ? accent.withOpacity(0.14) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? accent
                      : MyTheme.color(context).border ?? Colors.grey,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: selected ? DrxBrand.groundOf(context) : muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _steps[index],
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: selected
                      ? Theme.of(context).textTheme.titleLarge?.color
                      : muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A schematic of the settings pane, drawn rather than recorded.
///
/// A screen recording would be truer to what the user sees, but it can only be
/// captured on a real Mac and it goes stale the next time Apple rearranges
/// System Settings. This costs nothing to ship, is right in both themes, and
/// carries the one thing a user needs: where in the window to look, and what
/// changes when they get it right.
class _DrxGuideIllustration extends StatelessWidget {
  const _DrxGuideIllustration({Key? key, required this.step}) : super(key: key);

  final int step;

  @override
  Widget build(BuildContext context) {
    final ground = DrxBrand.groundOf(context);
    final card = DrxBrand.cardOf(context);
    final border = MyTheme.color(context).border ?? Colors.grey;
    final accent = DrxBrand.accentOf(context);
    final muted = DrxBrand.mutedOf(context);
    final bar = muted.withOpacity(0.28);

    Widget line(double widthFactor, {Color? color}) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: color ?? bar,
            ),
          ),
        );

    Widget appRow({required bool highlighted, required bool on}) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: highlighted ? accent.withOpacity(0.14) : card,
            border: Border.all(color: highlighted ? accent : border),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      DrxBrand.actionGradientStart,
                      DrxBrand.actionGradientEnd,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  bind.mainGetAppNameSync(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                width: 28,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: on ? DrxBrand.successOf(context) : border,
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

    Widget otherRow(Color chip) => Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: card,
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: chip,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(child: line(1, color: bar)),
              const SizedBox(width: 9),
              Container(
                width: 28,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: border,
                ),
              ),
            ],
          ),
        );

    return Container(
      height: 208,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: ground,
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: card,
              border: Border(right: BorderSide(color: border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                line(0.7),
                const SizedBox(height: 7),
                line(0.84),
                const SizedBox(height: 7),
                line(0.6),
                const SizedBox(height: 7),
                // Step 2 is "pick it from the list", so the list entry lights
                // up from step 2 onward.
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: step >= 1 ? accent.withOpacity(0.16) : null,
                  ),
                  child: line(0.62, color: step >= 1 ? accent : bar),
                ),
                const SizedBox(height: 7),
                line(0.66),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  line(0.45),
                  const SizedBox(height: 8),
                  otherRow(const Color(0xFF2C7FD8)),
                  const SizedBox(height: 8),
                  // Step 3 is the switch itself.
                  appRow(highlighted: step >= 2, on: step >= 2),
                  const SizedBox(height: 8),
                  otherRow(const Color(0xFF7A8794)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrxGuideButton extends StatelessWidget {
  const _DrxGuideButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  }) : super(key: key);

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onPressed,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: primary
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    DrxBrand.actionGradientStart,
                    DrxBrand.actionGradientEnd,
                  ],
                )
              : null,
          border: primary
              ? null
              : Border.all(color: MyTheme.color(context).border ?? Colors.grey),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
            color: primary ? Colors.white : DrxBrand.mutedOf(context),
          ),
        ),
      ),
    );
  }
}
