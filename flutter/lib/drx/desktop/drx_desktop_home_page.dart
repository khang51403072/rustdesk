// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The home tab of the new desktop UI. Replaces `DesktopHomePage` from
// `lib/desktop/pages/desktop_home_page.dart` when the `ui` flag is on.
//
// What is new and what is borrowed
// --------------------------------
//   * NEW: the sidebar. Upstream's left pane is a 200px column of loose rows
//     (logo, tip, id board, password board, help cards). Here it is a 248px
//     column of cards, all of which answer one question: what is THIS machine
//     and can anyone reach it.
//   * NEW: the connect bar. Upstream's is a fixed 320px box with the three
//     other session kinds hidden behind a dropdown; this one fills the pane
//     and puts them beside Connect.
//   * BORROWED AS-IS: `PeerTabPage` (so the machine list, its tabs, search and
//     sort are upstream's), `OnlineStatusWidget`, `buildPresetPasswordWarning`,
//     `setPasswordDialog`, and `connect()` — every bit of connect logic still
//     lives in `common.dart`.
//
// Deliberately NOT carried over
// -----------------------------
//   * `buildHelpCards` — the install / update / permission cards. They are
//     ~150 lines of platform branching bound to upstream's layout; they get
//     their own step rather than being dragged in half-done.
//   * The plugin entry (`buildPluginEntry`), which is behind a feature flag
//     this fork does not ship.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new UI layer).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../consts.dart';
import '../../desktop/pages/connection_page.dart' show OnlineStatusWidget;
import '../../desktop/pages/desktop_home_page.dart' show setPasswordDialog;
import '../../desktop/pages/desktop_setting_page.dart';
import '../../drx_brand.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'drx_permission_guide.dart';
import '../../utils/multi_window_manager.dart';

/// Width of the sidebar. Upstream's pane is 200 (280 for incoming-only); the
/// id digits at 23px need 248 before they wrap.
const double _kSidebarWidth = 248;

/// Card geometry, shared with the mobile cards in `drx/widgets/drx_card.dart`.
const double _kCardRadius = 13;
const double _kControlRadius = 11;

class DrxDesktopHomePage extends StatefulWidget {
  const DrxDesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DrxDesktopHomePage> createState() => _DrxDesktopHomePageState();
}

class _DrxDesktopHomePageState extends State<DrxDesktopHomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Upstream's `_DesktopHomePageState` owns both of these, and other pages
  // depend on them: `OnlineStatusWidget` and the Security settings tab both do
  // `Get.find<RxBool>(tag: 'stop-service')`, and the id stays on "Generating"
  // until something calls `fetchID()`. Replacing the page means inheriting the
  // housekeeping, not just the layout.
  final _svcStopped = false.obs;
  Timer? _updateTimer;

  /// Last error the core reported, shown as a card. Upstream keeps the same
  /// string on its state and refreshes it from the same 1s timer.
  String _systemError = '';

  /// Which help card is currently due. Recomputed every tick; the page is only
  /// rebuilt when it changes, so the timer does not repaint the window once a
  /// second for nothing.
  String _helpKey = '';

  /// Which permissions are granted, as a signature the tick compares.
  String _permissions = '';

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<RxBool>(tag: 'stop-service')) {
      Get.put<RxBool>(_svcStopped, tag: 'stop-service');
    }
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final stopped = await mainGetBoolOption(kOptionStopService);
      if (stopped != _svcStopped.value) {
        _svcStopped.value = stopped;
      }
      final error = await bind.mainGetError();
      final help = drxHelpCardKey(svcStopped: stopped, systemError: error);
      final permissions = isMacOS ? drxPermissionSignature() : '';
      if (mounted &&
          (error != _systemError ||
              help != _helpKey ||
              permissions != _permissions)) {
        setState(() {
          _systemError = error;
          _helpKey = help;
          _permissions = permissions;
        });
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrxSidebar(
            helpKey: _helpKey,
            systemError: _systemError,
            permissions: _permissions,
          ),
          if (!isIncomingOnly) const Expanded(child: _DrxConnectPane()),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── sidebar

class _DrxSidebar extends StatelessWidget {
  const _DrxSidebar({
    Key? key,
    required this.helpKey,
    required this.systemError,
    required this.permissions,
  }) : super(key: key);

  /// Which help card to draw, as decided by [drxHelpCardKey].
  final String helpKey;
  final String systemError;

  /// Which permissions are granted, from [drxPermissionSignature]. Passed in
  /// rather than read inside the card: a `const` widget whose inputs never
  /// change is one Flutter skips rebuilding, so a card that read the binds
  /// itself would keep showing whatever it found the first time.
  final String permissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = MyTheme.color(context).border ?? theme.dividerColor;
    return Container(
      width: _kSidebarWidth,
      decoration: BoxDecoration(
        color: DrxBrand.chromeOf(context),
        border: Border(right: BorderSide(color: border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DrxBrandRow(),
          const SizedBox(height: 14),
          // The cards scroll and the footer stays put. How many cards there
          // are depends on the machine — a missing permission, a preset
          // password, a Wayland session each add one — so the column cannot
          // be sized to fit a short window, and a `Spacer` only overflows
          // when it runs out of room.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Upstream shows this whenever the build ships a preset
                  // password.
                  buildPresetPasswordWarning(),
                  if (!bind.isOutgoingOnly()) ...[
                    const _DrxIdentityCard(),
                    const SizedBox(height: 10),
                    const _DrxServiceCard(),
                    const _DrxPermanentPasswordCard(),
                  ],
                  if (isMacOS) _DrxPermissionsCard(signature: permissions),
                  _DrxHelpCard(helpKey: helpKey, systemError: systemError),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _DrxSidebarFooter(),
        ],
      ),
    );
  }
}

class _DrxBrandRow extends StatelessWidget {
  const _DrxBrandRow({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                DrxBrand.actionGradientStart,
                DrxBrand.actionGradientEnd,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            bind.mainGetAppNameSync(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// The card that carries this machine's id and its one-time password.
///
/// Upstream draws these as two separate boards, each a label above a read-only
/// `TextFormField` with an accent bar down its left edge. They are one thing —
/// the credentials someone needs to reach this machine — so they are one card.
class _DrxIdentityCard extends StatefulWidget {
  const _DrxIdentityCard({Key? key}) : super(key: key);

  @override
  State<_DrxIdentityCard> createState() => _DrxIdentityCardState();
}

class _DrxIdentityCardState extends State<_DrxIdentityCard> {
  bool _revealed = false;

  void _copy(String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value.trim()));
    showToast(translate('Copied'));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        // Upstream hides the one-time password when the peer is expected to
        // click to accept, or when a permanent password is in use.
        final showOneTime = model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;
        final password = model.serverPasswd.text;
        return _DrxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DrxFieldLabel(label: translate('ID')),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      model.serverId.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.4,
                        color: DrxBrand.identityOf(context),
                      ),
                    ),
                  ),
                  _DrxMiniAction(
                    icon: Icons.content_copy_outlined,
                    tooltip: translate('Copy'),
                    filled: true,
                    onPressed: () => _copy(model.serverId.text),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 1,
                color: MyTheme.color(context).border,
              ),
              const SizedBox(height: 11),
              _DrxFieldLabel(label: translate('One-time Password')),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      !showOneTime
                          ? '-'
                          : (_revealed ? password : '•' * password.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  if (showOneTime) ...[
                    _DrxMiniAction(
                      icon: _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      tooltip: translate('Show'),
                      filled: !_revealed,
                      onPressed: () => setState(() => _revealed = !_revealed),
                    ),
                    _DrxMiniAction(
                      icon: Icons.refresh,
                      tooltip: translate('Refresh Password'),
                      onPressed: bind.mainUpdateTemporaryPassword,
                    ),
                    _DrxMiniAction(
                      icon: Icons.content_copy_outlined,
                      tooltip: translate('Copy'),
                      onPressed: () => _copy(password),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Whether the service accepts incoming connections, and the switch for it.
class _DrxServiceCard extends StatelessWidget {
  const _DrxServiceCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerModel>(
      builder: (context, model, child) {
        final running = model.isStart;
        final tint =
            running ? DrxBrand.successOf(context) : DrxBrand.mutedOf(context);
        return _DrxCard(
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      translate(running
                          ? 'Service is running'
                          : 'Service is not running'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      model.connectStatus > 0
                          ? translate('Ready')
                          : translate('not_ready_status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: DrxBrand.mutedOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: running,
                  onChanged: (_) => model.toggleService(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Offers to set a permanent password while none is set: without one there is
/// no unattended access, which is the reason most of this fork's users install
/// it in the first place.
class _DrxPermanentPasswordCard extends StatelessWidget {
  const _DrxPermanentPasswordCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (bind.isDisableSettings()) return const Offstage();
    return FutureBuilder<String>(
      future: bind.mainGetCommon(key: 'permanent-password-set'),
      builder: (context, snapshot) {
        if (snapshot.data == null || snapshot.data == 'true') {
          return const Offstage();
        }
        final warning = DrxBrand.warningOf(context);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _DrxCard(
            accent: warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: warning),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        translate('Set permanent password'),
                        maxLines: 2,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => setPasswordDialog(),
                    child: Text(
                      translate('Set'),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: DrxBrand.accentOf(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DrxSidebarFooter extends StatelessWidget {
  const _DrxSidebarFooter({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final muted = DrxBrand.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSettingsRow(context, muted),
      ],
    );
  }

  Widget _buildSettingsRow(BuildContext context, Color muted) {
    return Row(
      children: [
        if (!bind.isDisableSettings())
          Expanded(
            child: InkWell(
              onTap: () {
                if (DesktopSettingPage.tabKeys.isNotEmpty) {
                  DesktopSettingPage.switch2page(DesktopSettingPage.tabKeys[0]);
                }
              },
              child: Row(
                children: [
                  Icon(Icons.settings_outlined, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Text(
                    translate('Settings'),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          )
        else
          const Spacer(),
        FutureBuilder<String>(
          future: bind.mainGetVersion(),
          builder: (context, snapshot) => Text(
            snapshot.data ?? '',
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────────────────────────────────────── connect pane

class _DrxConnectPane extends StatefulWidget {
  const _DrxConnectPane({Key? key}) : super(key: key);

  @override
  State<_DrxConnectPane> createState() => _DrxConnectPaneState();
}

class _DrxConnectPaneState extends State<_DrxConnectPane> {
  final _idController = TextEditingController();
  final _idFocusNode = FocusNode();

  @override
  void dispose() {
    _idController.dispose();
    _idFocusNode.dispose();
    super.dispose();
  }

  void _connect({
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTerminal = false,
  }) {
    final id = _idController.text.trim().replaceAll(' ', '');
    if (id.isEmpty) {
      _idFocusNode.requestFocus();
      return;
    }
    connect(
      context,
      id,
      isFileTransfer: isFileTransfer,
      isViewCamera: isViewCamera,
      isTerminal: isTerminal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DrxBrand.groundOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
            child: _buildConnectBar(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: PeerTabPage(),
            ),
          ),
          if (!bind.isOutgoingOnly()) ...[
            const Divider(height: 1),
            OnlineStatusWidget(),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectBar(BuildContext context) {
    return _DrxCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            translate('Control Remote Desktop').toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: DrxBrand.mutedOf(context),
            ),
          ),
          const SizedBox(height: 9),
          // Two limits, at the two ends of the range this row has to survive.
          // Below ~470 the secondary session kinds are dropped rather than
          // allowed to squeeze the id field: the field is what the row is for.
          // Above ~880 the row stops growing — an id is nine digits, and a
          // field stretched across a 1900px screen to hold them reads as a
          // mistake.
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 470;
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: _buildIdField(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _DrxConnectButton(onPressed: () => _connect()),
                  if (wide) ...[
                    const SizedBox(width: 10),
                    Container(
                      width: 1,
                      height: 26,
                      color: MyTheme.color(context).border,
                    ),
                    const SizedBox(width: 10),
                    // Upstream hides these in a dropdown glued to Connect;
                    // `connect()` takes each as a flag, so they cost one call
                    // apiece.
                    _DrxSessionKindButton(
                      icon: Icons.folder_outlined,
                      tooltip: translate('Transfer file'),
                      onPressed: () => _connect(isFileTransfer: true),
                    ),
                    const SizedBox(width: 6),
                    _DrxSessionKindButton(
                      icon: Icons.videocam_outlined,
                      tooltip: translate('View camera'),
                      onPressed: () => _connect(isViewCamera: true),
                    ),
                    const SizedBox(width: 6),
                    _DrxSessionKindButton(
                      icon: Icons.terminal_outlined,
                      tooltip: '${translate('Terminal')} (beta)',
                      onPressed: () => _connect(isTerminal: true),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIdField(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: DrxBrand.groundOf(context),
        borderRadius: BorderRadius.circular(_kControlRadius),
        border: Border.all(color: MyTheme.color(context).border ?? Colors.grey),
      ),
      padding: const EdgeInsets.only(left: 13, right: 10),
      child: Row(
        children: [
          Icon(Icons.search, size: 17, color: DrxBrand.mutedOf(context)),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _idController,
              focusNode: _idFocusNode,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              keyboardType: TextInputType.visiblePassword,
              inputFormatters: [IDTextInputFormatter()],
              onSubmitted: (_) => _connect(),
              style: const TextStyle(
                fontFamily: 'WorkSans',
                fontSize: 20,
                height: 1.2,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: translate('Enter Remote ID'),
                hintStyle: TextStyle(
                  fontSize: 20,
                  color: DrxBrand.mutedOf(context).withOpacity(0.7),
                ),
              ),
            ).workaroundFreezeLinuxMint(),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────── pieces

/// A surface in the sidebar or the connect pane. Same geometry as `DrxCard` on
/// mobile, minus that one's baked-in 12px column margin.
class _DrxCard extends StatelessWidget {
  const _DrxCard({
    Key? key,
    required this.child,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(14, 13, 14, 13),
  }) : super(key: key);

  final Widget child;
  final Color? accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DrxBrand.cardOf(context),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(
          color: accent ?? MyTheme.color(context).border ?? Colors.grey,
        ),
      ),
      child: child,
    );
  }
}

/// The small caps label above a value, with its actions on the right.
class _DrxFieldLabel extends StatelessWidget {
  const _DrxFieldLabel({Key? key, required this.label}) : super(key: key);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: DrxBrand.mutedOf(context),
      ),
    );
  }
}

class _DrxMiniAction extends StatelessWidget {
  const _DrxMiniAction({
    Key? key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.filled = false,
  }) : super(key: key);

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Draws a filled chip behind the icon. Used for the one action in a row
  /// that a reader is most likely to want.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(seconds: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onPressed,
        child: Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: filled ? DrxBrand.groundOf(context) : null,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 13, color: DrxBrand.mutedOf(context)),
        ),
      ),
    );
  }
}

/// The one primary action of the window, so it gets the brand gradient.
class _DrxConnectButton extends StatelessWidget {
  const _DrxConnectButton({Key? key, required this.onPressed})
      : super(key: key);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_kControlRadius),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [DrxBrand.actionGradientStart, DrxBrand.actionGradientEnd],
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
        borderRadius: BorderRadius.circular(_kControlRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kControlRadius),
          onTap: onPressed,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.desktop_windows_outlined,
                    size: 17, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  translate('Connect'),
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
  }
}

class _DrxSessionKindButton extends StatelessWidget {
  const _DrxSessionKindButton({
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
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kControlRadius),
        onTap: onPressed,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kControlRadius),
            border:
                Border.all(color: MyTheme.color(context).border ?? Colors.grey),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: DrxBrand.mutedOf(context)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── help cards

// The card that asks the user to fix something before this machine can be
// reached: a macOS permission, a Windows installation, a Linux display-server
// caveat. Upstream builds these in `_DesktopHomePageState.buildHelpCards`.
//
// The CONDITIONS below are upstream's, call for call — `mainIsCanScreenRecording`
// before `mainIsProcessTrusted` before `mainIsCanInputMonitoring`, one card at a
// time, in that order — because that order is the order macOS itself wants the
// permissions granted in. Only the drawing is this fork's.
//
// Two of upstream's cards are deliberately not here:
//   * the "new version available" banner, which is guarded by
//     `!bind.isCustomClient()` and can never show in this fork;
//   * the Quit button for incoming-only builds, which belongs to that build's
//     very different single-pane layout.

/// Keys for the help cards, in the order upstream checks them.
const String _kHelpNone = '';
const String _kHelpSystemError = 'system-error';
const String _kHelpWinInstall = 'win-install';
const String _kHelpWinUpgrade = 'win-upgrade';
const String _kHelpMacDaemon = 'mac-daemon';
const String _kHelpLinuxSelinux = 'linux-selinux';
const String _kHelpLinuxWayland = 'linux-wayland';
const String _kHelpLinuxWaylandLogin = 'linux-wayland-login';

/// Local option upstream uses to let the user dismiss the SELinux tip.
const String _kShowSelinuxHelpTip = 'show-selinux-help-tip';

/// Decides which help card is due, or [_kHelpNone].
///
/// Pure and synchronous so the 1s timer can call it and compare the result
/// with the last one; every bind below is a sync FFI read.
String drxHelpCardKey({required bool svcStopped, required String systemError}) {
  if (systemError.isNotEmpty) return _kHelpSystemError;

  final isOutgoingOnly = bind.isOutgoingOnly();

  if (isWindows && !bind.isDisableInstallation()) {
    if (!bind.mainIsInstalled()) return _kHelpWinInstall;
    if (bind.mainIsInstalledLowerVersion()) return _kHelpWinUpgrade;
  } else if (isMacOS) {
    // The three permissions are gone from here: they have a card of their own
    // that shows all three at once instead of one at a time. This is what is
    // left of upstream's macOS branch.
    if (!isOutgoingOnly &&
        !svcStopped &&
        bind.mainIsInstalled() &&
        !bind.mainIsInstalledDaemon(prompt: false)) {
      return _kHelpMacDaemon;
    }
  } else if (isLinux && !isOutgoingOnly) {
    if (bind.isSelinuxEnforcing() &&
        bind.mainGetLocalOption(key: _kShowSelinuxHelpTip) != 'N') {
      return _kHelpLinuxSelinux;
    }
    if (bind.mainCurrentIsWayland()) return _kHelpLinuxWayland;
    if (bind.mainIsLoginWayland()) return _kHelpLinuxWaylandLogin;
  }
  return _kHelpNone;
}

class _DrxHelpCard extends StatelessWidget {
  const _DrxHelpCard({
    Key? key,
    required this.helpKey,
    required this.systemError,
  }) : super(key: key);

  final String helpKey;
  final String systemError;

  @override
  Widget build(BuildContext context) {
    switch (helpKey) {
      case _kHelpSystemError:
        return _card(context, title: translate('Status'), body: systemError);

      case _kHelpWinInstall:
        return _card(
          context,
          title: translate('Install'),
          body: bind.isOutgoingOnly() ? '' : translate('install_tip'),
          action: translate('Install'),
          onAction: () async {
            await rustDeskWinManager.closeAllSubWindows();
            bind.mainGotoInstall();
          },
        );

      case _kHelpWinUpgrade:
        return _card(
          context,
          title: translate('Status'),
          body: translate('Your installation is lower version.'),
          action: translate('Click to upgrade'),
          onAction: () async {
            await rustDeskWinManager.closeAllSubWindows();
            bind.mainUpdateMe();
          },
        );

      case _kHelpMacDaemon:
        return _card(
          context,
          title: translate('Install'),
          body: translate('install_daemon_tip'),
          action: translate('Install'),
          onAction: () => bind.mainIsInstalledDaemon(prompt: true),
        );

      case _kHelpLinuxSelinux:
        return _card(
          context,
          title: translate('Warning'),
          body: translate('selinux_tip'),
          helpLink:
              'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
          onDismiss: () =>
              bind.mainSetLocalOption(key: _kShowSelinuxHelpTip, value: 'N'),
        );

      case _kHelpLinuxWayland:
        return _card(
          context,
          title: translate('Warning'),
          body: translate('wayland_experiment_tip'),
          helpLink: 'https://rustdesk.com/docs/en/client/linux/#x11-required',
        );

      case _kHelpLinuxWaylandLogin:
        return _card(
          context,
          title: translate('Warning'),
          body: translate('Login screen using Wayland is not supported'),
          helpLink: 'https://rustdesk.com/docs/en/client/linux/#login-screen',
        );

      default:
        return const Offstage();
    }
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required String body,
    String? action,
    VoidCallback? onAction,
    String? helpLink,
    VoidCallback? onDismiss,
  }) {
    final warning = DrxBrand.warningOf(context);
    final muted = DrxBrand.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _DrxCard(
        accent: warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: warning),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                if (onDismiss != null)
                  _DrxMiniAction(
                    icon: Icons.close,
                    tooltip: translate('Close'),
                    onPressed: onDismiss,
                  ),
              ],
            ),
            if (body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 25),
                child: Text(
                  body,
                  style: TextStyle(fontSize: 11, height: 1.4, color: muted),
                ),
              ),
            const SizedBox(height: 10),
            // Stacked, not laid side by side: three actions never fit one
            // 248px line, and wrapping them left the primary action alone on
            // a second row looking like an afterthought. Full-width rows also
            // survive a translation of any length.
            if (action != null)
              _DrxCardAction(
                label: action,
                onPressed: onAction,
                primary: true,
              ),
            if (helpLink != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: InkWell(
                    onTap: () => launchUrl(Uri.parse(helpLink)),
                    child: Text(
                      translate('Help'),
                      style: TextStyle(fontSize: 11.5, color: muted),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A full-width action inside a help card. [primary] fills it in the action
/// blue; the rest are outlined, so a card can carry more than one without two
/// buttons competing to be pressed.
class _DrxCardAction extends StatelessWidget {
  const _DrxCardAction({
    Key? key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  }) : super(key: key);

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final accent = DrxBrand.accentOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onPressed,
      child: Container(
        height: 30,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: primary ? accent.withOpacity(0.14) : null,
          border: Border.all(
            color: primary
                ? accent.withOpacity(0.55)
                : MyTheme.color(context).border ?? Colors.grey,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
            color: primary ? accent : DrxBrand.mutedOf(context),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────── permissions card

/// All three macOS permissions in one card: what is granted, and what to do
/// about what is not.
///
/// It replaces two things upstream and this fork had separately — a help card
/// that named ONE missing permission at a time, and a menu at the foot of the
/// sidebar that listed all three. Neither answered the whole question on its
/// own: the card never said what was already granted, and the menu never said
/// anything was wrong.
///
/// The card stays after everything is granted, collapsed to its header. That
/// is deliberate: a permission can be revoked in System Settings at any time,
/// and the moment a user wants to check or change one is exactly the moment
/// upstream's card has disappeared.
class _DrxPermissionsCard extends StatefulWidget {
  const _DrxPermissionsCard({Key? key, required this.signature})
      : super(key: key);

  /// Not read — it is what makes this widget differ from the last one, so the
  /// card rebuilds when a permission is granted or revoked.
  final String signature;

  @override
  State<_DrxPermissionsCard> createState() => _DrxPermissionsCardState();
}

class _DrxPermissionsCardState extends State<_DrxPermissionsCard> {
  /// Null until the user opens or closes it by hand; before that the card
  /// opens itself when something is missing and stays shut when nothing is.
  bool? _open;

  @override
  Widget build(BuildContext context) {
    final missing =
        DrxPermission.all.where((p) => !p.granted).toList(growable: false);
    final allGranted = missing.isEmpty;
    final open = _open ?? !allGranted;
    final warning = DrxBrand.warningOf(context);
    final muted = DrxBrand.mutedOf(context);
    final tint = allGranted ? DrxBrand.successOf(context) : warning;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _DrxCard(
        accent: allGranted ? null : warning,
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !open),
              child: Row(
                children: [
                  Icon(
                    allGranted ? Icons.verified_user : Icons.gpp_maybe,
                    size: 16,
                    color: tint,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      translate('Permissions'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    allGranted
                        ? translate('All granted')
                        : translate('{${missing.length}} missing'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: tint,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    size: 15,
                    color: muted,
                  ),
                ],
              ),
            ),
            if (open) ...[
              const SizedBox(height: 4),
              ...DrxPermission.all.map((p) => _buildRow(context, p)),
              const SizedBox(height: 7),
              Divider(
                height: 1,
                thickness: 1,
                color: MyTheme.color(context).border,
              ),
              InkWell(
                // The guide opens on the first missing permission, or on the
                // first one of the three when there is nothing to fix and the
                // user is only reading.
                onTap: () => showDrxPermissionGuide(
                  context,
                  missing.isEmpty ? DrxPermission.all.first : missing.first,
                ),
                child: SizedBox(
                  height: 30,
                  child: Row(
                    children: [
                      Icon(Icons.help_outline, size: 15, color: muted),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          translate('How to grant permissions'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: muted),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 15, color: muted),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, DrxPermission permission) {
    final granted = permission.granted;
    final muted = DrxBrand.mutedOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              granted ? Icons.check_circle_outline : Icons.error_outline,
              size: 15,
              color: granted
                  ? DrxBrand.successOf(context)
                  : DrxBrand.warningOf(context),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permission.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    // A granted row is settled, so it goes quiet and the eye
                    // lands on the ones still to do.
                    color: granted
                        ? muted
                        : Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  permission.description,
                  style: TextStyle(fontSize: 10, height: 1.3, color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!granted)
            _DrxEnableButton(
              onPressed: () {
                // Ask the system first: on a machine that has never been asked
                // this is one click and done. The guide is for the machines
                // where that prompt no longer appears.
                permission.prompt();
                showDrxPermissionGuide(context, permission);
              },
            ),
        ],
      ),
    );
  }
}

class _DrxEnableButton extends StatelessWidget {
  const _DrxEnableButton({Key? key, required this.onPressed}) : super(key: key);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = DrxBrand.accentOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: accent.withOpacity(0.14),
          border: Border.all(color: accent.withOpacity(0.55)),
        ),
        child: Text(
          translate('Enable'),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
      ),
    );
  }
}
