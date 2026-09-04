// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The shell of the new mobile UI: app bar, bottom navigation, and the frame
// that holds whichever page is selected.
//
// This is step 1 of the UI replacement plan: THE SHELL IS OURS, THE CONTENTS
// ARE STILL THE OLD PAGES. The three tabs below point straight at
// `ConnectionPage`, `ServerPage` and `SettingsPage` from `lib/mobile/pages/`.
// Each tab gets replaced by a DRX page in a later step — one tab at a time,
// each a commit that runs.
//
// How this differs from the old `HomePage`
// ----------------------------------------
//   * Three tabs instead of four: the "Chat" tab is gone. Chat now uses the
//     floating bubble that `ChatModel.showChatIconOverlay()` already builds —
//     see the note above `DrxHomePage`.
//   * `navigationBarKey` is NOT attached. That is deliberate, not an omission;
//     again, see the note above `DrxHomePage`.
//   * The bottom bar is hand-built rather than a `BottomNavigationBar`, so the
//     icon can switch from outlined to filled when its tab is selected.
//
// See CUSTOM_CONFIG.md at the repo root.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../common.dart';
import '../mobile/pages/connection_page.dart';
import '../mobile/pages/home_page.dart' show PageShape;
import '../mobile/pages/server_page.dart';
import '../mobile/pages/settings_page.dart';

// ─────────────────────────────────────────────────────────────────────────
// WHY THERE IS NO CHAT TAB, AND WHY `navigationBarKey` IS LEFT UNATTACHED
// ─────────────────────────────────────────────────────────────────────────
//
// `ChatModel` already builds a draggable chat bubble
// (`showChatIconOverlay()`) that appears on the first incoming message. The
// tab and the bubble were already mutually exclusive in the old code:
// `showChatIconOverlay()` bails out early when the bottom bar sits on index 1,
// because in the old shell index 1 *was* the chat tab.
//
// That guard reads `navigationBarKey.currentWidget` and then **casts** it to
// `BottomNavigationBar`. Three things follow:
//
//   1. Do not attach `navigationBarKey` to the DRX bottom bar. Attaching it
//      would make that cast throw, because our bar is not a
//      `BottomNavigationBar`.
//   2. Leaving it unattached means `currentWidget` is null, the guard is
//      skipped, and the chat bubble shows on every tab. That is exactly what
//      we want.
//   3. No edit to `chat_model.dart` is needed here. Cleaning up that guard
//      belongs to the step that replaces the Share screen.
//
// Related: `chat_model.dart` also asks
// `HomePage.homeKey.currentState?.isChatPageCurrentTab` before bumping the
// unread counter. Under the DRX shell `HomePage` is never mounted, so
// `currentState` is null, the expression becomes `null != true` (true), and
// messages still count as unread. That is the correct behaviour when there is
// no chat tab.

class DrxHomePage extends StatefulWidget {
  const DrxHomePage({Key? key}) : super(key: key);

  /// Lets the old settings page ask for the tab list to be rebuilt after the
  /// user toggles an option that changes how many tabs exist. The old
  /// `HomePage.homeKey` serves the same purpose.
  static final drxKey = GlobalKey<DrxHomePageState>();

  @override
  State<DrxHomePage> createState() => DrxHomePageState();
}

class DrxHomePageState extends State<DrxHomePage> {
  final List<PageShape> _pages = [];
  final List<_NavItem> _navItems = [];
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _initPages();
  }

  /// Rebuild the tab list. Safe to call whenever the config changes.
  void refreshPages() => setState(_initPages);

  void _initPages() {
    _pages.clear();
    _navItems.clear();

    // Same conditions as the old `HomePage`, so outgoing-only and
    // incoming-only builds still end up with the right set of tabs.
    if (!bind.isIncomingOnly()) {
      _pages.add(ConnectionPage(appBarActions: []));
      _navItems.add(const _NavItem(
        label: 'Connection',
        outlined: Icons.desktop_windows_outlined,
        filled: Icons.desktop_windows,
      ));
    }
    if (isAndroid && !bind.isOutgoingOnly()) {
      _pages.add(ServerPage());
      _navItems.add(const _NavItem(
        label: 'Share screen',
        outlined: Icons.screen_share_outlined,
        filled: Icons.screen_share,
      ));
    }
    _pages.add(SettingsPage());
    _navItems.add(const _NavItem(
      label: 'Settings',
      outlined: Icons.settings_outlined,
      filled: Icons.settings,
    ));

    if (_selected >= _pages.length) _selected = 0;
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_selected];
    return WillPopScope(
      // Back returns to the first tab before it leaves the app, matching the
      // old `HomePage` behaviour.
      onWillPop: () async {
        if (_selected != 0) {
          setState(() => _selected = 0);
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(bind.mainGetAppNameSync()),
          actions: page.appBarActions,
        ),
        body: page,
        bottomNavigationBar: _buildNavBar(context),
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.appBarTheme.backgroundColor ?? theme.cardColor,
        border: Border(
          top: BorderSide(color: MyTheme.color(context).border ?? Colors.grey),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List.generate(_navItems.length, (i) {
              return Expanded(child: _buildNavItem(context, i));
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, int index) {
    final item = _navItems[index];
    final selected = index == _selected;
    // Outlined when idle, filled when selected: the current tab stays
    // recognisable at a glance and in glare, not by colour alone.
    final color = selected ? MyTheme.accent : MyTheme.darkGray;
    return InkWell(
      onTap: () => setState(() => _selected = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? item.filled : item.outlined, color: color, size: 22),
            const SizedBox(height: 3),
            Text(
              translate(item.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.outlined,
    required this.filled,
  });

  /// A translation key, not display text. Translated at build time so that
  /// changing the language in Settings updates the bar immediately.
  final String label;
  final IconData outlined;
  final IconData filled;
}
