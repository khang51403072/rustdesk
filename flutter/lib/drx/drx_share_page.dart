// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The share-screen tab of the new mobile UI. Replaces
// `lib/mobile/pages/server_page.dart` when the `ui` flag is on.
//
// Step 3 of the UI replacement plan.
//
// Rewritten here
// --------------
//   * The device card — id and one-time password. Upstream stacks an icon+
//     heading row above each value and indents the value by 39/40 px, which
//     leaves the two numbers floating away from their labels. Here each value
//     sits on its own row with its actions, and the identity blue marks what
//     is a machine identifier.
//   * The permissions card, as plain switch rows on one surface.
//
// Reused from the old page, deliberately
// --------------------------------------
//   * `ConnectionManager` — the per-client cards. These carry the accept /
//     dismiss flow for an unauthorised connection and a live permission
//     toggle per client. That is behaviour, not decoration, and copying it
//     would mean copying the bugs it has already had fixed.
//   * `ServiceNotRunningNotification` — the start-service prompt, including
//     the scam warning it has to show first.
//   * `checkService()` and `buildPresetPasswordWarningMobile()`.
//
// On the chat bubble
// ------------------
// Nothing to do here. `ChatModel.showChatIconOverlay()` bails out when the
// bottom bar sits on index 1, which under a three-tab shell would be exactly
// this screen — but the guard reads `navigationBarKey`, and `DrxHomePage`
// never attaches it. See the note in `drx_home_page.dart`.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../consts.dart';
import '../drx_brand.dart';
import '../mobile/pages/home_page.dart' show PageShape;
import '../mobile/pages/server_page.dart'
    show ConnectionManager, checkService, showScamWarning;
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'widgets/drx_button.dart';
import 'widgets/drx_card.dart';

class DrxSharePage extends StatefulWidget implements PageShape {
  DrxSharePage({Key? key}) : super(key: key);

  @override
  final icon = const Icon(Icons.mobile_screen_share_outlined);

  @override
  final title = translate('Share screen');

  @override
  final List<Widget> appBarActions = [];

  @override
  State<DrxSharePage> createState() => _DrxSharePageState();
}

class _DrxSharePageState extends State<DrxSharePage> {
  Timer? _idTimer;

  @override
  void initState() {
    super.initState();
    // The id is assigned by the rendezvous server and can arrive late or
    // change; upstream polls on the same interval.
    _idTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
    });
    gFFI.serverModel.checkAndroidPermission();
  }

  @override
  void dispose() {
    _idTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    checkService();
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) => SingleChildScrollView(
          controller: gFFI.serverModel.controller,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: kMobilePageConstraints,
              // No horizontal padding: each card carries its own 12px
              // inset, because `ConnectionManager` brings upstream's
              // `PaddingCard` with a margin already baked in.
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildPresetPasswordWarningMobile(),
                  if (serverModel.isStart)
                    _DrxDeviceCard(serverModel: serverModel)
                  else
                    _DrxServiceOffCard(serverModel: serverModel),
                  const ConnectionManager(),
                  _DrxPermissionsCard(serverModel: serverModel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the device card while the service is stopped.
///
/// Replaces upstream's `ServiceNotRunningNotification`, which had three
/// contrast failures on a light card: a `redAccent` warning icon at 2.8, body
/// text in `MyTheme.darkGray` at 2.3, and white-on-`MyTheme.accent` on the
/// button at 2.9. Behaviour is unchanged — in particular the scam warning that
/// has to be shown before a signed-out user starts the service for the first
/// time.
class _DrxServiceOffCard extends StatelessWidget {
  const _DrxServiceOffCard({Key? key, required this.serverModel})
      : super(key: key);

  final ServerModel serverModel;

  void _start(BuildContext context) {
    if (gFFI.userModel.userName.value.isEmpty &&
        bind.mainGetLocalOption(key: 'show-scam-warning') != 'N') {
      showScamWarning(context, serverModel);
    } else {
      serverModel.toggleService();
    }
  }

  @override
  Widget build(BuildContext context) {
    final warning = DrxBrand.warningOf(context);
    return DrxCard(
      title: translate('Service is not running'),
      titleIcon: Icons.warning_amber_rounded,
      accent: warning,
      children: [
        const SizedBox(height: 2),
        Text(
          translate('android_start_service_tip'),
          style: TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: DrxBrand.mutedOf(context),
          ),
        ),
        const SizedBox(height: 14),
        DrxPrimaryButton(
          icon: Icons.play_arrow_rounded,
          label: translate('Start service'),
          onPressed: () => _start(context),
        ),
      ],
    );
  }
}

/// Id and one-time password, plus whether the rendezvous server can be reached.
class _DrxDeviceCard extends StatelessWidget {
  const _DrxDeviceCard({Key? key, required this.serverModel}) : super(key: key);

  final ServerModel serverModel;

  void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value.trim()));
    showToast(translate('Copied'));
  }

  @override
  Widget build(BuildContext context) {
    // Upstream hides the one-time password when the peer is expected to click
    // to accept, or when a permanent password is in use.
    final showOneTime = serverModel.approveMode != 'click' &&
        serverModel.verificationMethod != kUsePermanentPassword;
    // Some deployments ship without a way to stop the service at all.
    final showStopService = serverModel.mediaOk &&
        !(isAndroid &&
            bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y');

    return DrxCard(
      title: translate('Your Device'),
      children: [
        _DrxValueRow(
          icon: Icons.badge_outlined,
          label: translate('ID'),
          value: serverModel.serverId.text,
          actions: [
            _DrxIconAction(
              icon: Icons.content_copy_outlined,
              tooltip: translate('Copy'),
              onPressed: () => _copy(context, serverModel.serverId.text),
            ),
          ],
        ),
        const DrxCardDivider(),
        _DrxValueRow(
          icon: Icons.key_outlined,
          label: translate('One-time Password'),
          value: showOneTime ? serverModel.serverPasswd.text : '-',
          actions: showOneTime
              ? [
                  _DrxIconAction(
                    icon: Icons.refresh,
                    tooltip: translate('Refresh'),
                    onPressed: bind.mainUpdateTemporaryPassword,
                  ),
                  _DrxIconAction(
                    icon: Icons.content_copy_outlined,
                    tooltip: translate('Copy'),
                    onPressed: () =>
                        _copy(context, serverModel.serverPasswd.text),
                  ),
                ]
              : const [],
        ),
        const DrxCardDivider(),
        _DrxConnectStatus(
          status: serverModel.connectStatus,
          // Stop lives on the status row, not down in Permissions: this row is
          // the one that says the service is running, so it is where a reader
          // looks to turn it off. It also mirrors Start, which sits inside
          // `ServiceNotRunningNotification` — the card shown in this slot when
          // the service is off.
          trailing: showStopService
              ? _DrxStopServiceButton(onPressed: serverModel.toggleService)
              : null,
        ),
      ],
    );
  }
}

/// One label + big value + trailing actions.
class _DrxValueRow extends StatelessWidget {
  const _DrxValueRow({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
    required this.actions,
  }) : super(key: key);

  final IconData icon;
  final String label;
  final String value;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final muted = DrxBrand.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.4,
                    color: DrxBrand.identityOf(context),
                  ),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _DrxIconAction extends StatelessWidget {
  const _DrxIconAction({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  }) : super(key: key);

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      color: DrxBrand.mutedOf(context),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}

/// Whether the rendezvous server is reachable: -1 unreachable, 0 connecting,
/// anything else ready. Same three states upstream shows.
class _DrxConnectStatus extends StatelessWidget {
  const _DrxConnectStatus({Key? key, required this.status, this.trailing})
      : super(key: key);

  final int status;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    late final Widget leading;
    late final String text;
    late final Color color;

    if (status == -1) {
      leading = const Icon(Icons.warning_amber_rounded, size: 20);
      text = translate('not_ready_status');
      color = DrxBrand.dangerOf(context);
    } else if (status == 0) {
      leading = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      text = translate('connecting_status');
      color = DrxBrand.mutedOf(context);
    } else {
      leading = const Icon(Icons.check_circle_outline, size: 20);
      text = translate('Ready');
      // Not `DrxBrand.success`: that green only reaches 2.0 on a light card.
      color = DrxBrand.successOf(context);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconTheme(
            data: IconThemeData(color: color),
            child: SizedBox(width: 20, child: Center(child: leading)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: color)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The Android permissions the service needs, as switch rows.
class _DrxPermissionsCard extends StatelessWidget {
  const _DrxPermissionsCard({Key? key, required this.serverModel})
      : super(key: key);

  final ServerModel serverModel;

  @override
  Widget build(BuildContext context) {
    final hasAudioPermission = androidVersion >= 30;
    final hideStopService =
        isAndroid && bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';
    final allowPermChangeInAcceptWindow = option2bool(
      kOptionEnablePermChangeInAcceptWindow,
      bind.mainGetBuildinOption(key: kOptionEnablePermChangeInAcceptWindow),
    );
    // While someone is connected, flipping a permission mid-session would
    // change what they can do without them noticing, so upstream locks the
    // rows unless the build opts out.
    final locked = isAndroid &&
        serverModel.clients.any((c) => !c.disconnected) &&
        !allowPermChangeInAcceptWindow;

    final rows = <Widget>[];

    if (!hideStopService || !serverModel.mediaOk) {
      rows.add(_DrxSwitchRow(
        label: translate('Screen Capture'),
        value: serverModel.mediaOk,
        // Turning capture on for the first time is what actually starts the
        // service, so an unauthenticated user gets the scam warning first.
        onChanged: !serverModel.mediaOk &&
                gFFI.userModel.userName.value.isEmpty &&
                bind.mainGetLocalOption(key: 'show-scam-warning') != 'N'
            ? () => showScamWarning(context, serverModel)
            : serverModel.toggleService,
      ));
    }
    rows.add(_DrxSwitchRow(
      label: translate('Input Control'),
      value: serverModel.inputOk,
      onChanged: serverModel.toggleInput,
    ));
    rows.add(_DrxSwitchRow(
      label: translate('Transfer file'),
      value: serverModel.fileOk,
      onChanged: serverModel.toggleFile,
      enabled: !locked,
    ));
    if (hasAudioPermission) {
      rows.add(_DrxSwitchRow(
        label: translate('Audio Capture'),
        value: serverModel.audioOk,
        onChanged: serverModel.toggleAudio,
        enabled: !locked,
      ));
    } else {
      rows.add(_DrxNoteRow(text: translate('android_version_audio_tip')));
    }
    rows.add(_DrxSwitchRow(
      label: translate('Enable clipboard'),
      value: serverModel.clipboardOk,
      onChanged: serverModel.toggleClipboard,
      enabled: !locked,
    ));

    return DrxCard(
      title: translate('Permissions'),
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const DrxCardDivider(),
          rows[i],
        ],
      ],
    );
  }
}

class _DrxSwitchRow extends StatelessWidget {
  const _DrxSwitchRow({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  }) : super(key: key);

  final String label;
  final bool value;
  final VoidCallback onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                color: enabled
                    ? Theme.of(context).textTheme.bodyMedium?.color
                    : DrxBrand.mutedOf(context),
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: DrxBrand.accentOf(context),
            onChanged: enabled ? (_) => onChanged() : null,
          ),
        ],
      ),
    );
  }
}

class _DrxNoteRow extends StatelessWidget {
  const _DrxNoteRow({Key? key, required this.text}) : super(key: key);

  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = DrxBrand.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: muted)),
          ),
        ],
      ),
    );
  }
}

/// Outlined and compact rather than a solid red slab. Stopping the service is a
/// real action but not what the screen is about, and a filled red block on a
/// short row outweighs everything around it.
class _DrxStopServiceButton extends StatelessWidget {
  const _DrxStopServiceButton({Key? key, required this.onPressed})
      : super(key: key);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final danger = DrxBrand.dangerOf(context);
    return OutlinedButton.icon(
      icon: Icon(Icons.stop_circle_outlined, size: 17, color: danger),
      label: Text(
        translate('Stop service'),
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: danger),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
    );
  }
}
