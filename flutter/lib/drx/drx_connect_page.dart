// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The connect tab of the new mobile UI. Replaces
// `lib/mobile/pages/connection_page.dart` when the `ui` flag is on.
//
// Step 2 of the UI replacement plan. What is new and what is borrowed:
//
//   * NEW: the id card ([DrxIdCard]) — see that file for what changed.
//   * BORROWED AS-IS: `PeerTabPage`, and everything it drags in
//     (`peer_card`, `peers_view`, `address_book`, `my_group`). The machine
//     list therefore still looks like upstream's. Restyling it means editing
//     `peer_card.dart`, which desktop shares, so that is deliberately left to
//     a later step rather than bundled in here.
//   * BORROWED AS-IS: `connect()` from `common.dart`. All of the connect
//     logic — alias resolution, relay ids, password prompts — lives there, not
//     in the page.
//
// Deliberately NOT carried over from upstream's page
// --------------------------------------------------
// The "Download new version" banner. It is guarded by `!isCustomClient()`
// upstream, and this fork always reports as a custom client (APP_NAME is
// "Desk Remote X"), so the banner could never have shown.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../common/widgets/peer_tab_page.dart';
import '../consts.dart';
import '../mobile/pages/home_page.dart' show PageShape;
import '../models/model.dart';
import 'widgets/drx_id_card.dart';

class DrxConnectPage extends StatefulWidget implements PageShape {
  DrxConnectPage({Key? key}) : super(key: key);

  @override
  final icon = const Icon(Icons.desktop_windows_outlined);

  @override
  final title = translate('Connection');

  @override
  final List<Widget> appBarActions = [];

  @override
  State<DrxConnectPage> createState() => _DrxConnectPageState();
}

class _DrxConnectPageState extends State<DrxConnectPage> {
  StreamSubscription? _uniLinksSubscription;

  @override
  void initState() {
    super.initState();
    // Handles `rustdesk://` links that open the app straight into a session.
    if (!isWeb) _uniLinksSubscription = listenUniLinks();
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the connection state changes, same as upstream's page.
    Provider.of<FfiModel>(context);

    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        constraints: kMobilePageConstraints,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                child: DrxIdCard(onConnect: (id) => connect(context, id)),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: PeerTabPage(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
