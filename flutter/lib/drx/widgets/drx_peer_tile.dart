// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// One row in the machine list, as drawn on mobile in portrait.
//
// `peer_card.dart` is shared with desktop, and its `makeChild()` lives on a
// private `State` class, so it can neither be subclassed nor overridden from
// outside. Rather than rework that method for two very different layouts, the
// mobile portrait branch hands off to this widget and everything upstream keeps
// its shape — the hook there is five lines.
//
// What changes against upstream's row
// -----------------------------------
//   * The badge carries the PLATFORM's colour. Upstream uses
//     `str2color(id + platform)`, a hash of the peer id: stable per machine but
//     meaningless, so two Windows boxes get two unrelated colours and the list
//     cannot be scanned. Offline peers go neutral, because a machine you cannot
//     reach should not look as inviting as one you can.
//   * The badge's bottom-right corner is chamfered, echoing the diagonal cut of
//     the logo's X. It is the one ornamental detail in the list, and it sits on
//     the element that identifies a machine.
//   * The online dot takes its colour from the theme. Upstream's `Colors.green`
//     reaches 2.6 on a light card, under the 3.0 a graphic needs.
//   * Tighter type: the name at 12.5 and the sub-line at 10.5, against
//     `titleSmall` (14) and unstyled body text.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../drx_brand.dart';
import '../../models/peer_model.dart';

/// Height of a row, and the radius upstream uses for the tile shape.
const double _kTileHeight = 46;
const double _kTileRadius = 5;

/// How far up the chamfer cuts, as a fraction of the badge. Shallow on purpose:
/// enough to read as deliberate, not enough to look damaged.
const double _kChamfer = 0.34;

class DrxPeerTile extends StatelessWidget {
  const DrxPeerTile({
    Key? key,
    required this.peer,
    required this.name,
    required this.hasPassword,
    required this.trailing,
    this.note,
  }) : super(key: key);

  final Peer peer;

  /// `username@hostname`, already assembled by the caller because whether the
  /// username is shown depends on a build option upstream reads.
  final String name;

  final bool hasPassword;

  /// The checkbox or the "more" button, built by the caller: both need state
  /// that lives on the peer card.
  final Widget trailing;

  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = DrxBrand.mutedOf(context);
    // An alias is what the user named the machine; fall back to the grouped id.
    final title = peer.alias.isEmpty ? formatID(peer.id) : peer.alias;
    final subtitle = [
      if (name.isNotEmpty) name,
      if (note != null && note!.isNotEmpty) note!,
    ].join(' · ');

    return SizedBox(
      height: _kTileHeight,
      child: Row(
        children: [
          _DrxPeerBadge(
            platform: peer.platform,
            online: peer.online,
            hasPassword: hasPassword,
          ),
          Expanded(
            child: Container(
              height: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.background,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(_kTileRadius),
                  bottomRight: Radius.circular(_kTileRadius),
                ),
              ),
              padding: const EdgeInsets.only(left: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _DrxOnlineDot(online: peer.online),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: muted),
                          ),
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrxPeerBadge extends StatelessWidget {
  const _DrxPeerBadge({
    Key? key,
    required this.platform,
    required this.online,
    required this.hasPassword,
  }) : super(key: key);

  final String platform;
  final bool online;
  final bool hasPassword;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _DrxChamferClipper(),
      child: Container(
        width: _kTileHeight,
        height: _kTileHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: DrxBrand.platformGradient(platform, online: online),
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The platform SVGs are solid white, so they read on any of the
            // gradients above without recolouring.
            getPlatformImage(platform, size: 22),
            if (hasPassword)
              const Positioned(
                top: 3,
                left: 3,
                child: Icon(Icons.key, size: 8, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rounds the left corners and cuts the bottom-right one on the diagonal.
class _DrxChamferClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final cut = size.width * _kChamfer;
    const r = _kTileRadius;
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
  bool shouldReclip(covariant _DrxChamferClipper oldClipper) => false;
}

class _DrxOnlineDot extends StatelessWidget {
  const _DrxOnlineDot({Key? key, required this.online}) : super(key: key);

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: translate(online ? 'Online' : 'Offline'),
      waitDuration: const Duration(seconds: 1),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Upstream's Colors.green reaches 2.6 on a light card.
          color: online
              ? DrxBrand.successOf(context)
              : DrxBrand.mutedOf(context).withOpacity(0.55),
        ),
      ),
    );
  }
}
