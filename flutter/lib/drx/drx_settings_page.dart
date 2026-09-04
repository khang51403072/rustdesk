// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The settings tab of the new mobile UI. Replaces
// `lib/mobile/pages/settings_page.dart` when the `ui` flag is on; that file is
// left exactly as upstream ships it and still serves the legacy shell.
//
// Regrouped by intent, not by module
// ----------------------------------
// Upstream's `Settings` section alone held twelve unrelated rows — the relay
// server, a proxy, UDP, the language, the light/dark toggle — so finding
// anything meant reading all of them. The six groups here follow what someone
// is trying to do.
//
// Hidden, not disabled
// --------------------
// 2FA and recording are gone from this screen at the product owner's request.
// Their stored options are untouched: a device already recording keeps
// recording, and nothing here can now turn that off. Locking those features off
// is a `custom_defaults.rs` job — set the value and pin it through
// `override-settings`.
//
// Every option key, guard and handler below is taken verbatim from
// `settings_page.dart`. Where a dialog exists there, it is called rather than
// reimplemented; only the private `_DisplayPage` had to be rebuilt, because a
// private class cannot be reached from another library.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../common.dart';
import '../common/formatter/id_formatter.dart';
import '../common/widgets/dialog.dart';
import '../common/widgets/login.dart';
import '../common/widgets/setting_widgets.dart';
import '../consts.dart';
import '../drx_brand.dart';
import '../mobile/pages/home_page.dart' show PageShape;
import '../desktop/pages/desktop_setting_page.dart' show changeSocks5Proxy;
import '../mobile/pages/settings_page.dart'
    show
        KeepScreenOn,
        ScanButton,
        optionToKeepScreenOn,
        showLanguageSettings,
        showThemeSettings,
        url;
import '../mobile/widgets/deploy_dialog.dart';
import '../mobile/widgets/dialog.dart';
import '../models/model.dart';
import '../models/platform_model.dart';
import 'widgets/drx_settings_row.dart';

/// Mirrors the private helper of the same shape in `settings_page.dart`.
String _keepScreenOnToOption(KeepScreenOn value) {
  switch (value) {
    case KeepScreenOn.never:
      return 'never';
    case KeepScreenOn.duringControlled:
      return 'during-controlled';
    case KeepScreenOn.serviceOn:
      return 'service-on';
  }
}

class DrxSettingsPage extends StatefulWidget implements PageShape {
  DrxSettingsPage({Key? key}) : super(key: key);

  @override
  final title = translate('Settings');

  @override
  final icon = const Icon(Icons.settings_outlined);

  @override
  final appBarActions = bind.isDisableSettings() ? <Widget>[] : [ScanButton()];

  @override
  State<DrxSettingsPage> createState() => _DrxSettingsPageState();
}

class _DrxSettingsPageState extends State<DrxSettingsPage>
    with WidgetsBindingObserver {
  // ── state, read once at construction like upstream does ──
  var _enableStartOnBoot = false;
  var _checkUpdateOnStartup = false;
  var _showTerminalExtraKeys = false;
  var _floatingWindowDisabled = false;
  var _keepScreenOn = KeepScreenOn.duringControlled;
  var _enableAbr = false;
  var _denyLANDiscovery = false;
  var _onlyWhiteList = false;
  var _onlyIdWhiteList = false;
  var _enableDirectIPAccess = false;
  var _enableHardwareCodec = false;
  var _allowWebSocket = false;
  var _allowAutoDisconnect = false;
  var _localIP = "";
  var _directAccessPort = "";
  var _fingerprint = "";
  var _buildDate = "";
  var _myId = "";
  var _autoDisconnectTimeout = "";
  var _hideServer = false;
  var _hideProxy = false;
  var _hideNetwork = false;
  var _hideWebSocket = false;
  var _enableUdpPunch = false;
  var _allowInsecureTlsFallback = false;
  var _disableUdp = false;
  var _enableIpv6Punch = false;
  var _isUsingPublicServer = false;
  var _allowAskForNoteAtEndOfConnection = false;
  var _preventSleepWhileConnected = true;

  _DrxSettingsPageState() {
    _enableAbr = option2bool(
        kOptionEnableAbr, bind.mainGetOptionSync(key: kOptionEnableAbr));
    _denyLANDiscovery = !option2bool(kOptionEnableLanDiscovery,
        bind.mainGetOptionSync(key: kOptionEnableLanDiscovery));
    _onlyWhiteList = whitelistNotEmpty();
    _onlyIdWhiteList = idWhitelistNotEmpty();
    _enableDirectIPAccess = option2bool(
        kOptionDirectServer, bind.mainGetOptionSync(key: kOptionDirectServer));
    _enableHardwareCodec = option2bool(kOptionEnableHwcodec,
        bind.mainGetOptionSync(key: kOptionEnableHwcodec));
    _allowWebSocket = mainGetBoolOptionSync(kOptionAllowWebSocket);
    _allowInsecureTlsFallback =
        mainGetBoolOptionSync(kOptionAllowInsecureTLSFallback);
    _disableUdp = bind.mainGetOptionSync(key: kOptionDisableUdp) == 'Y';
    _localIP = bind.mainGetOptionSync(key: 'local-ip-addr');
    _directAccessPort = bind.mainGetOptionSync(key: kOptionDirectAccessPort);
    _allowAutoDisconnect = option2bool(kOptionAllowAutoDisconnect,
        bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect));
    _autoDisconnectTimeout =
        bind.mainGetOptionSync(key: kOptionAutoDisconnectTimeout);
    _hideServer =
        bind.mainGetBuildinOption(key: kOptionHideServerSetting) == 'Y';
    _hideProxy = bind.mainGetBuildinOption(key: kOptionHideProxySetting) == 'Y';
    _hideNetwork =
        bind.mainGetBuildinOption(key: kOptionHideNetworkSetting) == 'Y';
    _hideWebSocket =
        bind.mainGetBuildinOption(key: kOptionHideWebSocketSetting) == 'Y' ||
            isWeb;
    _enableUdpPunch = mainGetLocalBoolOptionSync(kOptionEnableUdpPunch);
    _enableIpv6Punch = mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch);
    _allowAskForNoteAtEndOfConnection =
        mainGetLocalBoolOptionSync(kOptionAllowAskForNoteAtEndOfConnection);
    _preventSleepWhileConnected =
        mainGetLocalBoolOptionSync(kOptionKeepAwakeDuringOutgoingSessions);
    _showTerminalExtraKeys =
        mainGetLocalBoolOptionSync(kOptionEnableShowTerminalExtraKeys);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAsync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Permissions can be granted from the system settings while the app is in
    // the background, so re-read on the way back in.
    if (state == AppLifecycleState.resumed) {
      () async {
        if (await checkAndUpdateStartOnBoot()) setState(() {});
      }();
    }
  }

  /// Start-on-boot needs the overlay permission. Ported from the private
  /// helper of the same name in `settings_page.dart`; upstream also guards on
  /// battery optimisation, but that branch is dead there — `_hasIgnoreBattery`
  /// is hard-coded to false.
  Future<bool> canStartOnBoot() async =>
      AndroidPermissionManager.check(kSystemAlertWindow);

  /// Clears a stale start-on-boot flag when the permission was revoked from the
  /// system settings. Returns whether anything changed.
  Future<bool> checkAndUpdateStartOnBoot() async {
    if (!await canStartOnBoot() && _enableStartOnBoot) {
      _enableStartOnBoot = false;
      gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
      return true;
    }
    return false;
  }

  /// Values that can only be read asynchronously, or that the system may have
  /// changed behind the app's back.
  Future<void> _refreshAsync() async {
    var startOnBoot = await gFFI.invokeMethod(AndroidChannel.kGetStartOnBootOpt);
    // Start-on-boot needs the overlay permission; if that was revoked, the
    // stored value is a lie and upstream clears it here too.
    if (startOnBoot && !await canStartOnBoot()) {
      startOnBoot = false;
      gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, false);
    }
    final floatingWindowDisabled =
        bind.mainGetLocalOption(key: kOptionDisableFloatingWindow) == "Y" ||
            !await AndroidPermissionManager.check(kSystemAlertWindow);
    final keepScreenOn = floatingWindowDisabled
        ? KeepScreenOn.never
        : optionToKeepScreenOn(
            bind.mainGetLocalOption(key: kOptionKeepScreenOn));
    final fingerprint = await bind.mainGetFingerprint();
    final buildDate = await bind.mainGetBuildDate();
    final myId = await bind.mainGetMyId();
    final usingPublic = await bind.mainIsUsingPublicServer();
    if (!mounted) return;
    setState(() {
      _enableStartOnBoot = startOnBoot;
      _checkUpdateOnStartup =
          mainGetLocalBoolOptionSync(kOptionEnableCheckUpdate);
      _floatingWindowDisabled = floatingWindowDisabled;
      _keepScreenOn = keepScreenOn;
      _fingerprint = fingerprint;
      _buildDate = buildDate;
      _myId = myId;
      _isUsingPublicServer = usingPublic;
    });
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<FfiModel>(context);
    final outgoingOnly = bind.isOutgoingOnly();
    final incomingOnly = bind.isIncomingOnly();
    final disabled = bind.isDisableSettings();
    final hideSecurity =
        bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) == 'Y';
    final shareVisible =
        isAndroid && !disabled && !outgoingOnly && !hideSecurity;

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: kMobilePageConstraints,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _deviceHeader(),
            if (!bind.isDisableAccount()) _accountGroup(),
            _connectionGroup(disabled, incomingOnly),
            if (shareVisible) _shareGroup(),
            _applicationGroup(incomingOnly),
            if (!incomingOnly || isAndroid) _qualityGroup(incomingOnly),
            _advancedGroup(disabled, outgoingOnly, shareVisible),
            _aboutGroup(),
          ],
        ),
      ),
    );
  }

  // ── the machine's own id, which used to sit at the bottom of About ──
  Widget _deviceHeader() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: MyTheme.color(context).border ?? Colors.grey),
      ),
      child: Row(
        children: [
          ClipPath(
            clipper: _DrxChamfer(),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    DrxBrand.actionGradientStart,
                    DrxBrand.actionGradientEnd,
                  ],
                ),
              ),
              child: const Icon(Icons.mobile_screen_share_outlined,
                  size: 21, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translate('Your Device'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: DrxBrand.mutedOf(context),
                  ),
                ),
                Text(
                  _myId.isEmpty ? '-' : formatID(_myId),
                  style: TextStyle(
                    fontFamily: 'WorkSans',
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                    color: DrxBrand.identityOf(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.content_copy_outlined, size: 19),
            color: DrxBrand.mutedOf(context),
            tooltip: translate('Copy'),
            visualDensity: VisualDensity.compact,
            onPressed: _myId.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _myId));
                    showToast(translate('Copied'));
                  },
          ),
        ],
      ),
    );
  }

  Widget _accountGroup() {
    return Obx(() {
      final loggedIn = gFFI.userModel.userName.value.isNotEmpty;
      return DrxSettingsGroup(
        title: translate('Account'),
        rows: [
          DrxNavRow(
            icon: loggedIn ? Icons.account_circle_outlined : Icons.login,
            title: loggedIn ? translate('Logout') : translate('Login'),
            value: loggedIn ? gFFI.userModel.accountLabelWithHandle : null,
            onTap: () => loggedIn ? logOutConfirmDialog() : loginDialog(),
          ),
        ],
      );
    });
  }

  Widget _connectionGroup(bool disabled, bool incomingOnly) {
    return DrxSettingsGroup(
      title: translate('Connection'),
      rows: [
        if (!disabled && !_hideNetwork && !_hideServer)
          DrxNavRow(
            icon: Icons.dns_outlined,
            title: translate('ID/Relay Server'),
            value: _isUsingPublicServer ? translate('Default') : null,
            onTap: () => showServerSettings(gFFI.dialogManager, (cb) async {
              _isUsingPublicServer = await bind.mainIsUsingPublicServer();
              setState(cb);
            }),
          ),
        if (!_hideNetwork && !_hideProxy)
          DrxNavRow(
            icon: Icons.alt_route_outlined,
            title: translate('Socks5/Http(s) Proxy'),
            onTap: changeSocks5Proxy,
          ),
        if (isAndroid && !bind.isOutgoingOnly())
          DrxNavRow(
            icon: Icons.cloud_upload_outlined,
            title: translate('Deploy'),
            onTap: showDeployDialog,
          ),
        if (!incomingOnly)
          DrxSwitchRow(
            icon: Icons.wifi_tethering,
            title: translate('Enable UDP hole punching'),
            description: translate('drx-udp-punch-tip'),
            value: _enableUdpPunch,
            onChanged: (v) async {
              await mainSetLocalBoolOption(kOptionEnableUdpPunch, v);
              setState(() => _enableUdpPunch =
                  mainGetLocalBoolOptionSync(kOptionEnableUdpPunch));
            },
          ),
        if (!incomingOnly)
          DrxSwitchRow(
            icon: Icons.public,
            title: translate('Enable IPv6 P2P connection'),
            value: _enableIpv6Punch,
            onChanged: (v) async {
              await mainSetLocalBoolOption(kOptionEnableIpv6Punch, v);
              setState(() => _enableIpv6Punch =
                  mainGetLocalBoolOptionSync(kOptionEnableIpv6Punch));
            },
          ),
        if (!_isUsingPublicServer)
          DrxSwitchRow(
            icon: Icons.lock_outline,
            title: translate('Allow insecure TLS fallback'),
            risk: true,
            value: _allowInsecureTlsFallback,
            onChanged: isOptionFixed(kOptionAllowInsecureTLSFallback)
                ? null
                : (v) async {
                    await mainSetBoolOption(kOptionAllowInsecureTLSFallback, v);
                    setState(() => _allowInsecureTlsFallback =
                        mainGetBoolOptionSync(kOptionAllowInsecureTLSFallback));
                  },
          ),
      ],
    );
  }

  Widget _shareGroup() {
    return DrxSettingsGroup(
      title: translate('Share screen'),
      rows: [
        DrxSwitchRow(
          icon: Icons.travel_explore_outlined,
          title: translate('Deny LAN discovery'),
          value: _denyLANDiscovery,
          onChanged: isOptionFixed(kOptionEnableLanDiscovery)
              ? null
              : (v) async {
                  await bind.mainSetOption(
                      key: kOptionEnableLanDiscovery,
                      value: bool2option(kOptionEnableLanDiscovery, !v));
                  setState(() => _denyLANDiscovery = !option2bool(
                      kOptionEnableLanDiscovery,
                      bind.mainGetOptionSync(key: kOptionEnableLanDiscovery)));
                },
        ),
        DrxSwitchRow(
          icon: Icons.filter_alt_outlined,
          title: translate('Use IP Whitelisting'),
          value: _onlyWhiteList,
          onChanged: (_) async {
            changeWhiteList(callback: () {
              setState(() => _onlyWhiteList = whitelistNotEmpty());
            });
          },
        ),
        DrxSwitchRow(
          icon: Icons.badge_outlined,
          title: translate('Use ID whitelisting'),
          value: _onlyIdWhiteList,
          onChanged: (_) async {
            changeIdWhiteList(callback: () {
              setState(() => _onlyIdWhiteList = idWhitelistNotEmpty());
            });
          },
        ),
      ],
    );
  }

  Widget _applicationGroup(bool incomingOnly) {
    return DrxSettingsGroup(
      title: translate('Application'),
      rows: [
        DrxNavRow(
          icon: Icons.translate,
          title: translate('Language'),
          onTap: () => showLanguageSettings(gFFI.dialogManager),
        ),
        DrxNavRow(
          icon: Theme.of(context).brightness == Brightness.light
              ? Icons.dark_mode_outlined
              : Icons.light_mode_outlined,
          title: translate('Theme'),
          value: translate(Theme.of(context).brightness == Brightness.light
              ? 'Light Theme'
              : 'Dark Theme'),
          onTap: () => showThemeSettings(gFFI.dialogManager),
        ),
        if (isAndroid)
          DrxNavRow(
            icon: Icons.brightness_high_outlined,
            title: translate('Keep screen on'),
            value: translate(_keepScreenOnLabel()),
            onTap: _floatingWindowDisabled ? () {} : _pickKeepScreenOn,
            description: _floatingWindowDisabled
                ? translate('Floating window') // needs the floating window
                : null,
          ),
        if (isAndroid)
          DrxSwitchRow(
            icon: Icons.picture_in_picture_alt_outlined,
            title: translate('Floating window'),
            description: translate('floating_window_tip'),
            value: !_floatingWindowDisabled,
            onChanged: bind.mainIsOptionFixed(key: kOptionDisableFloatingWindow)
                ? null
                : _setFloatingWindow,
          ),
        if (isAndroid)
          DrxSwitchRow(
            icon: Icons.restart_alt,
            title: translate('Start on boot'),
            value: _enableStartOnBoot,
            onChanged: (v) async {
              if (v && !await canStartOnBoot()) return;
              await gFFI.invokeMethod(AndroidChannel.kSetStartOnBootOpt, v);
              setState(() => _enableStartOnBoot = v);
            },
          ),
        if (!bind.isCustomClient())
          DrxSwitchRow(
            icon: Icons.system_update_alt,
            title: translate('Check for software update on startup'),
            value: _checkUpdateOnStartup,
            onChanged: (v) async {
              await mainSetLocalBoolOption(kOptionEnableCheckUpdate, v);
              setState(() => _checkUpdateOnStartup = v);
            },
          ),
        if (!incomingOnly)
          DrxSwitchRow(
            icon: Icons.coffee_outlined,
            title: translate('keep-awake-during-outgoing-sessions-label'),
            value: _preventSleepWhileConnected,
            onChanged: (v) async {
              await mainSetLocalBoolOption(
                  kOptionKeepAwakeDuringOutgoingSessions, v);
              setState(() => _preventSleepWhileConnected = v);
            },
          ),
      ],
    );
  }

  Widget _qualityGroup(bool incomingOnly) {
    return DrxSettingsGroup(
      title: translate('Image quality'),
      rows: [
        if (!incomingOnly)
          DrxNavRow(
            icon: Icons.tune,
            title: translate('Display Settings'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DrxDisplayPage())),
          ),
        DrxSwitchRow(
          icon: Icons.network_check,
          title: translate('Adaptive bitrate'),
          value: _enableAbr,
          onChanged: isOptionFixed(kOptionEnableAbr)
              ? null
              : (v) async {
                  await mainSetBoolOption(kOptionEnableAbr, v);
                  // Read back rather than trusting `v`: the option may be
                  // pinned, in which case the write is ignored.
                  final nv = await mainGetBoolOption(kOptionEnableAbr);
                  setState(() => _enableAbr = nv);
                },
        ),
        if (isAndroid)
          DrxSwitchRow(
            icon: Icons.memory_outlined,
            title: translate('Enable hardware codec'),
            value: _enableHardwareCodec,
            onChanged: isOptionFixed(kOptionEnableHwcodec)
                ? null
                : (v) async {
                    await mainSetBoolOption(kOptionEnableHwcodec, v);
                    final nv = await mainGetBoolOption(kOptionEnableHwcodec);
                    setState(() => _enableHardwareCodec = nv);
                  },
          ),
      ],
    );
  }

  Widget _advancedGroup(bool disabled, bool outgoingOnly, bool shareVisible) {
    return DrxSettingsGroup(
      title: translate('Advanced'),
      rows: [
        if (!disabled && !_hideNetwork && !_hideWebSocket)
          DrxSwitchRow(
            icon: Icons.swap_horiz,
            title: translate('Use WebSocket'),
            value: _allowWebSocket,
            onChanged: isOptionFixed(kOptionAllowWebSocket)
                ? null
                : (v) async {
                    await mainSetBoolOption(kOptionAllowWebSocket, v);
                    final nv = await mainGetBoolOption(kOptionAllowWebSocket);
                    setState(() => _allowWebSocket = nv);
                  },
          ),
        if (isAndroid && !outgoingOnly && !_isUsingPublicServer)
          DrxSwitchRow(
            icon: Icons.block_outlined,
            title: translate('Disable UDP'),
            value: _disableUdp,
            onChanged: isOptionFixed(kOptionDisableUdp)
                ? null
                : (v) async {
                    await bind.mainSetOption(
                        key: kOptionDisableUdp, value: v ? 'Y' : 'N');
                    setState(() => _disableUdp =
                        bind.mainGetOptionSync(key: kOptionDisableUdp) == 'Y');
                  },
          ),
        if (shareVisible)
          DrxSwitchRow(
            icon: Icons.lan_outlined,
            title: translate('Direct IP Access'),
            description: _enableDirectIPAccess
                ? '${translate("Local Address")}: $_localIP'
                    '${_directAccessPort.isEmpty ? "" : ":$_directAccessPort"}'
                : null,
            value: _enableDirectIPAccess,
            onChanged: isOptionFixed(kOptionDirectServer)
                ? null
                : (v) async {
                    await bind.mainSetOption(
                        key: kOptionDirectServer,
                        value: bool2option(kOptionDirectServer, v));
                    setState(() => _enableDirectIPAccess = option2bool(
                        kOptionDirectServer,
                        bind.mainGetOptionSync(key: kOptionDirectServer)));
                  },
          ),
        if (shareVisible)
          DrxSwitchRow(
            icon: Icons.timer_outlined,
            title: translate('auto_disconnect_option_tip'),
            description: _allowAutoDisconnect
                ? '${_autoDisconnectTimeout.isEmpty ? '10' : _autoDisconnectTimeout} min'
                : null,
            value: _allowAutoDisconnect,
            onChanged: isOptionFixed(kOptionAllowAutoDisconnect)
                ? null
                : (v) async {
                    await bind.mainSetOption(
                        key: kOptionAllowAutoDisconnect,
                        value: bool2option(kOptionAllowAutoDisconnect, v));
                    setState(() => _allowAutoDisconnect = option2bool(
                        kOptionAllowAutoDisconnect,
                        bind.mainGetOptionSync(key: kOptionAllowAutoDisconnect)));
                  },
          ),
        if (isAndroid)
          DrxSwitchRow(
            icon: Icons.keyboard_outlined,
            title: translate('Show terminal extra keys'),
            value: _showTerminalExtraKeys,
            onChanged: (v) async {
              await mainSetLocalBoolOption(
                  kOptionEnableShowTerminalExtraKeys, v);
              setState(() => _showTerminalExtraKeys = v);
            },
          ),
        if (!bind.isDisableAccount())
          DrxSwitchRow(
            icon: Icons.edit_note_outlined,
            title: translate('note-at-conn-end-tip'),
            value: _allowAskForNoteAtEndOfConnection,
            onChanged: (v) async {
              if (v && !gFFI.userModel.isLogin) {
                if (await loginDialog() != true) return;
              }
              await mainSetLocalBoolOption(
                  kOptionAllowAskForNoteAtEndOfConnection, v);
              setState(() => _allowAskForNoteAtEndOfConnection =
                  mainGetLocalBoolOptionSync(
                      kOptionAllowAskForNoteAtEndOfConnection));
            },
          ),
      ],
    );
  }

  Widget _aboutGroup() {
    return DrxSettingsGroup(
      title: translate('About'),
      rows: [
        DrxNavRow(
          icon: Icons.info_outline,
          title: translate('Version'),
          value: version,
          onTap: _showAbout,
        ),
        DrxNavRow(
          icon: Icons.event_outlined,
          title: translate('Build Date'),
          value: _buildDate,
          onTap: () {},
        ),
        if (isAndroid)
          DrxNavRow(
            icon: Icons.fingerprint,
            title: translate('Fingerprint'),
            value: _fingerprint,
            onTap: () {
              Clipboard.setData(ClipboardData(text: _fingerprint));
              showToast(translate('Copied'));
            },
          ),
        DrxNavRow(
          icon: Icons.privacy_tip_outlined,
          title: translate('Privacy Statement'),
          onTap: () => launchUrlString('${url}privacy.html'),
        ),
      ],
    );
  }

  // ── helpers ──

  /// The about box.
  ///
  /// Not `showAbout` from `settings_page.dart`: that one hard-codes
  /// `https://rustdesk.com/` and the label `rustdesk.com`. The title is fine
  /// there because `translate()` swaps "RustDesk" for the app name, but a URL
  /// is not a translated string, so the rebrand never reached it. Here the link
  /// comes from the fork's own `url`, and its label is derived from that URL so
  /// the two can never drift apart again.
  void _showAbout() {
    final host = Uri.parse(url).host;
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Text(translate('About RustDesk')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${translate('Version')}: $version'),
            const SizedBox(height: 4),
            Text(
              '${translate('Build Date')}: $_buildDate',
              style: TextStyle(
                  fontSize: 12.5, color: DrxBrand.mutedOf(context)),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => launchUrlString(url),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  host,
                  style: TextStyle(
                    color: DrxBrand.accentOf(context),
                    decoration: TextDecoration.underline,
                    decorationColor: DrxBrand.accentOf(context),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [dialogButton('Close', onPressed: close, isOutline: true)],
      );
    }, clickMaskDismiss: true, backDismiss: true);
  }

  String _keepScreenOnLabel() {
    switch (_keepScreenOn) {
      case KeepScreenOn.never:
        return 'Never';
      case KeepScreenOn.duringControlled:
        return 'During controlled';
      case KeepScreenOn.serviceOn:
        return 'During service is on';
    }
  }

  Future<void> _setFloatingWindow(bool toValue) async {
    if (toValue &&
        !await AndroidPermissionManager.check(kSystemAlertWindow) &&
        !await AndroidPermissionManager.request(kSystemAlertWindow)) {
      return;
    }
    final disable = !toValue;
    bind.mainSetLocalOption(
        key: kOptionDisableFloatingWindow,
        value: disable ? 'Y' : defaultOptionNo);
    setState(() => _floatingWindowDisabled = disable);
    gFFI.serverModel.androidUpdatekeepScreenOn();
  }

  void _pickKeepScreenOn() {
    if (isOptionFixed(kOptionKeepScreenOn)) return;
    drxPickOption<KeepScreenOn>(
      context: context,
      title: translate('Keep screen on'),
      current: _keepScreenOn,
      options: const [
        (KeepScreenOn.never, 'Never'),
        (KeepScreenOn.duringControlled, 'During controlled'),
        (KeepScreenOn.serviceOn, 'During service is on'),
      ],
      onSelected: (v) async {
        await bind.mainSetLocalOption(
            key: kOptionKeepScreenOn, value: _keepScreenOnToOption(v));
        setState(() => _keepScreenOn = v);
        gFFI.serverModel.androidUpdatekeepScreenOn();
      },
    );
  }
}

/// A radio dialog. Replaces the private `_getPopupDialogRadioEntry` pattern in
/// `settings_page.dart`, which builds a `SettingsTile` this page cannot use.
void drxPickOption<T>({
  required BuildContext context,
  required String title,
  required T current,
  required List<(T, String)> options,
  required Future<void> Function(T) onSelected,
}) {
  gFFI.dialogManager.show((setState, close, context) {
    T selected = current;
    return CustomAlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: options
            .map((o) => RadioListTile<T>(
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(translate(o.$2)),
                  value: o.$1,
                  groupValue: selected,
                  onChanged: (v) async {
                    if (v == null) return;
                    selected = v;
                    setState(() {});
                    await onSelected(v);
                    close();
                  },
                ))
            .toList(),
      ),
      actions: [
        dialogButton('Close', onPressed: close, isOutline: true),
      ],
    );
  });
}

/// Rebuilt because upstream's `_DisplayPage` is private to `settings_page.dart`.
/// The option keys and value lists are the same.
class DrxDisplayPage extends StatefulWidget {
  const DrxDisplayPage({Key? key}) : super(key: key);

  @override
  State<DrxDisplayPage> createState() => _DrxDisplayPageState();
}

class _DrxDisplayPageState extends State<DrxDisplayPage> {
  @override
  Widget build(BuildContext context) {
    final Map codecs = jsonDecode(bind.mainSupportedHwdecodings());
    final h264 = codecs['h264'] ?? false;
    final h265 = codecs['h265'] ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(translate('Display Settings')),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          DrxSettingsGroup(
            title: translate('Display Settings'),
            rows: [
              _choice(
                icon: Icons.aspect_ratio,
                title: 'Default View Style',
                key: kOptionViewStyle,
                options: const [
                  (kRemoteViewStyleOriginal, 'Scale original'),
                  (kRemoteViewStyleAdaptive, 'Scale adaptive'),
                ],
              ),
              _choice(
                icon: Icons.high_quality_outlined,
                title: 'Default Image Quality',
                key: kOptionImageQuality,
                options: const [
                  (kRemoteImageQualityBest, 'Good image quality'),
                  (kRemoteImageQualityBalanced, 'Balanced'),
                  (kRemoteImageQualityLow, 'Optimize reaction time'),
                  (kRemoteImageQualityCustom, 'Custom'),
                ],
              ),
              _choice(
                icon: Icons.memory_outlined,
                title: 'Default Codec',
                key: kOptionCodecPreference,
                options: [
                  ('auto', 'Auto'),
                  ('vp8', 'VP8'),
                  ('vp9', 'VP9'),
                  ('av1', 'AV1'),
                  if (h264) ('h264', 'H264'),
                  if (h265) ('h265', 'H265'),
                ],
              ),
            ],
          ),
          DrxSettingsGroup(
            title: translate('Other Default Options'),
            rows: otherDefaultSettings()
                .map((e) => _otherRow(e.$1, e.$2))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _choice({
    required IconData icon,
    required String title,
    required String key,
    required List<(String, String)> options,
  }) {
    final value = bind.mainGetUserDefaultOption(key: key);
    final label = options.firstWhere((o) => o.$1 == value,
        orElse: () => options.first).$2;
    return DrxNavRow(
      icon: icon,
      title: translate(title),
      value: translate(label),
      onTap: isOptionFixed(key)
          ? () {}
          : () => drxPickOption<String>(
                context: context,
                title: translate(title),
                current: value,
                options: options,
                onSelected: (v) async {
                  await bind.mainSetUserDefaultOption(key: key, value: v);
                  setState(() {});
                },
              ),
    );
  }

  Widget _otherRow(String label, String key) {
    final value = bind.mainGetUserDefaultOption(key: key) == 'Y';
    return DrxSwitchRow(
      icon: Icons.tune,
      title: translate(label),
      value: value,
      onChanged: isOptionFixed(key)
          ? null
          : (v) async {
              await bind.mainSetUserDefaultOption(
                  key: key, value: v ? 'Y' : defaultOptionNo);
              setState(() {});
            },
    );
  }
}

/// The chamfer used on the device badge, matching the peer list.
class _DrxChamfer extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final cut = size.width * 0.34;
    const r = 10.0;
    return Path()
      ..moveTo(r, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(0, size.height - r),
          radius: const Radius.circular(r), clockwise: true)
      ..lineTo(0, r)
      ..arcToPoint(const Offset(r, 0),
          radius: const Radius.circular(r), clockwise: true)
      ..close();
  }

  @override
  bool shouldReclip(covariant _DrxChamfer oldClipper) => false;
}
