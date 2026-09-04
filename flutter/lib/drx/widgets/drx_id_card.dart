// ============================================================================
// [DRX CUSTOM] — NOT PART OF UPSTREAM RUSTDESK
// ============================================================================
//
// The "remote ID" card at the top of the connect screen.
//
// What is different from the card in `lib/mobile/pages/connection_page.dart`
// ---------------------------------------------------------------------------
//   * The clear button and the go button sit on the SAME ROW AS THE DIGITS.
//     Upstream centres them against the whole 84px card, which floats them into
//     the gap between the label line and the number line.
//   * The clear button hugs the end of the number instead of being pushed to
//     the far right by an `Expanded` text field. It therefore has to be told
//     how wide the number is — see [_measureWidth].
//   * The go button has a background. Upstream renders a bare 45px grey
//     `Icons.arrow_forward`, the same colour as the clear icon next to it, so
//     the control that opens a remote session looks exactly like the one that
//     erases text.
//
// Kept from upstream on purpose
// -----------------------------
//   * The field's controller is registered with GetX as
//     `IDTextEditingController`. `common.connect()` looks it up by type to
//     write the resolved id back after alias and relay resolution; skipping the
//     registration silently breaks that sync. One controller serves both roles
//     because `IDTextEditingController` *is* a `TextEditingController`, which
//     avoids having to mirror text between two of them inside `build`.
//   * `IDTextInputFormatter` still does the 3-3-3 grouping, and it passes
//     non-numeric IDs through untouched.
//
// See CUSTOM_CONFIG.md at the repo root, section 12 (new mobile UI layer).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/autocomplete.dart';
import '../../drx_brand.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';

/// Height of the card. Same as upstream's `SizedBox(height: 84)`, so replacing
/// the card does not move anything below it.
const double _kCardHeight = 84;
const double _kCardRadius = 13;

/// Both action buttons. 44 clears Material's 48dp guidance once the
/// surrounding padding is counted, and keeps the row inside 84.
const double _kGoSize = 44;
const double _kClearSize = 36;

/// Gap between the last digit and the clear button. Close enough to read as one
/// unit, far enough not to be hit while tapping the end of the number.
const double _kDigitsToClear = 9;

/// Never let the number field grow into the buttons.
const double _kMinSpacer = 10;

/// Smallest tappable width for the number field. Sizing the field to its text
/// means an empty field measures near zero, which cannot be tapped and shows no
/// caret — so an empty field takes the whole free width instead, and a
/// non-empty one never shrinks below this.
const double _kMinFieldWidth = 56;

/// Gap between the label and the number row.
const double _kLabelToDigits = 3;

/// Line height multiplier on the label. Pinned rather than left to the font so
/// the block below stays a known height on every device.
const double _kLabelLineHeight = 1.2;
const double _kLabelFontSize = 11;

class DrxIdCard extends StatefulWidget {
  const DrxIdCard({Key? key, required this.onConnect}) : super(key: key);

  /// Called with the raw (unformatted) id when the user commits.
  final void Function(String id) onConnect;

  @override
  State<DrxIdCard> createState() => _DrxIdCardState();
}

class _DrxIdCardState extends State<DrxIdCard> {
  final _idController = IDTextEditingController();
  final _focusNode = FocusNode();
  final _peersLoader = AllPeersLoader();

  /// Held across builds because `optionsBuilder` runs during layout and
  /// `optionsViewBuilder` needs the same list.
  Iterable<Peer> _options = const [];

  @override
  void initState() {
    super.initState();
    _peersLoader.init(setState);
    _idController.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);

    // `connect()` resolves aliases and relay ids, then writes the result back
    // through this registration.
    Get.put<IDTextEditingController>(_idController);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final last = await bind.mainGetLastRemoteId();
      if (!mounted || last.isEmpty || _idController.id.isNotEmpty) return;
      setState(() => _idController.id = last);
    });
  }

  @override
  void dispose() {
    _idController.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _peersLoader.clear();
    _focusNode.dispose();
    _idController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _peersLoader.needLoad) {
      _peersLoader.getAllPeers();
    }
    // Select all on focus so the next keystroke replaces the remembered id,
    // matching how a browser address bar behaves. Same as upstream.
    if (_focusNode.hasFocus) {
      _idController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _idController.text.length,
      );
    }
    setState(() {});
  }

  bool get _hasText => _idController.text.isNotEmpty;

  void _submit() {
    final id = _idController.id;
    if (id.isEmpty) return;
    FocusScope.of(context).unfocus();
    widget.onConnect(id);
  }

  void _clear() {
    setState(() {
      // Not `clear()`: that leaves `TextEditingValue.empty`, whose selection
      // sits at offset -1. The field then has no caret position and refuses
      // input until it is re-focused from scratch.
      _idController.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    });
    // Clearing is a step towards typing a different id, so keep the keyboard.
    _focusNode.requestFocus();
  }

  /// How wide the digits actually are.
  ///
  /// The clear button has to sit right after the last digit, which means the
  /// field cannot be `Expanded`. `IntrinsicWidth` around a `TextField` is
  /// unreliable — a text field reports an unbounded intrinsic width — so the
  /// text is measured directly and the field is given that width.
  double _measureWidth(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = DrxBrand.accentOf(context);
    final muted = DrxBrand.mutedOf(context);
    final idColor = DrxBrand.identityOf(context);

    final digitStyle = TextStyle(
      fontFamily: 'WorkSans',
      fontWeight: FontWeight.bold,
      fontSize: 26,
      height: 1.1,
      color: idColor,
    );

    return Container(
      height: _kCardHeight,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: _focusNode.hasFocus
            ? Border.all(color: accent, width: 1.5)
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      // The label and the number row form one block that is centred vertically
      // in the card. An `Expanded` row here would instead eat every pixel the
      // label did not use, pinning the label to the very top edge.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            translate('Remote ID'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _kLabelFontSize,
              height: _kLabelLineHeight,
              fontWeight: FontWeight.w600,
              color: _focusNode.hasFocus ? accent : muted,
            ),
          ),
          const SizedBox(height: _kLabelToDigits),
          // Fixed to the button height: the row's tallest child is the go
          // button, so this is what it would take anyway, stated up front so
          // the block height is predictable.
          SizedBox(height: _kGoSize, child: _buildRow(digitStyle, accent, muted)),
        ],
      ),
    );
  }

  Widget _buildRow(TextStyle digitStyle, Color accent, Color muted) {
    return LayoutBuilder(builder: (context, constraints) {
      // Everything the field is not allowed to occupy.
      final reserved = _kGoSize +
          _kMinSpacer +
          (_hasText ? _kClearSize + _kDigitsToClear : 0);
      final maxField = (constraints.maxWidth - reserved).clamp(0.0, 9999.0);
      // A caret's worth of slack so the cursor is never clipped at the end.
      final measured = _measureWidth(_idController.text, digitStyle) + 3;
      // An empty field spreads across the whole free width: there are no digits
      // for the clear button to hug, and the user needs somewhere to tap.
      final fieldWidth = _hasText
          ? measured.clamp(_kMinFieldWidth.clamp(0.0, maxField), maxField)
          : maxField;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: fieldWidth,
            child: _buildField(digitStyle, accent, muted),
          ),
          if (_hasText) ...[
            const SizedBox(width: _kDigitsToClear),
            _buildClearButton(muted),
          ],
          // The gap between the digits and the go button belongs to the field
          // as far as the user is concerned: tapping it puts the caret back.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focusNode.requestFocus,
              child: const SizedBox(height: _kGoSize),
            ),
          ),
          _buildGoButton(),
        ],
      );
    });
  }

  Widget _buildField(TextStyle digitStyle, Color accent, Color muted) {
    return RawAutocomplete<Peer>(
      focusNode: _focusNode,
      textEditingController: _idController,
      optionsBuilder: (value) {
        if (value.text.isEmpty) {
          _options = const [];
        } else {
          final needle = value.text.replaceAll(' ', '').toLowerCase();
          _options = _peersLoader.peers.where((p) =>
              p.id.toLowerCase().contains(needle) ||
              p.username.toLowerCase().contains(needle) ||
              p.hostname.toLowerCase().contains(needle) ||
              p.alias.toLowerCase().contains(needle));
          _peersLoader.queryOnlines(_options);
        }
        return _options;
      },
      onSelected: (peer) {
        setState(() => _idController.id = peer.id);
        FocusScope.of(context).unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        // `controller` is `_idController`; nothing to mirror.
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: digitStyle,
          cursorColor: accent,
          autocorrect: false,
          enableSuggestions: false,
          // Left as-is from upstream: a number pad would suit a 9-digit id but
          // would block the alphanumeric ids users can set for themselves.
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.go,
          inputFormatters: [IDTextInputFormatter()],
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            // Digit groups rather than a sentence: it shows the shape of an id
            // without needing a translation, and marks the field as tappable.
            hintText: '— — —',
            hintStyle: digitStyle.copyWith(
              color: muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          onSubmitted: (_) => _submit(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(_kCardRadius),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: _options
                    .map((peer) => AutocompletePeerTile(
                          onSelect: () => onSelected(peer),
                          peer: peer,
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildClearButton(Color muted) {
    return SizedBox(
      width: _kClearSize,
      height: _kClearSize,
      child: IconButton(
        padding: EdgeInsets.zero,
        splashRadius: 20,
        // Glyph chosen by the product owner. Note for whoever revisits this:
        // `backspace` conventionally means "delete one character", while this
        // button clears the whole field. `Icons.cancel` is the usual glyph for
        // clearing a text field on both Android and iOS.
        icon: const Icon(Icons.backspace_outlined, size: 19),
        color: muted,
        onPressed: _clear,
        tooltip: translate('Clear'),
      ),
    );
  }

  Widget _buildGoButton() {
    final enabled = _hasText;
    return _DrxGoButton(enabled: enabled, onTap: _submit);
  }
}

/// The gradient "go" button, with a highlight that sweeps left to right.
///
/// The sweep runs to 45% of the timeline and then rests, so it reads as an
/// occasional glint rather than a blinking light. It stops entirely when the
/// button is disabled, and when the platform asks for reduced motion.
class _DrxGoButton extends StatefulWidget {
  const _DrxGoButton({Key? key, required this.enabled, required this.onTap})
      : super(key: key);

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_DrxGoButton> createState() => _DrxGoButtonState();
}

class _DrxGoButtonState extends State<_DrxGoButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant _DrxGoButton old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.enabled && _sweep.isAnimating) {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animate =
        widget.enabled && !MediaQuery.of(context).disableAnimations;

    final Widget icon = Icon(
      Icons.arrow_forward,
      size: 21,
      color: widget.enabled ? Colors.white : DrxBrand.mutedOf(context),
    );

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: translate('Connect'),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          width: _kGoSize,
          height: _kGoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: widget.enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      DrxBrand.actionGradientStart,
                      DrxBrand.actionGradientEnd,
                    ],
                  )
                : null,
            border: widget.enabled
                ? null
                : Border.all(color: theme.dividerColor, width: 1.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: animate
              ? AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, child) => Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildGlint(_sweep.value),
                      Center(child: child),
                    ],
                  ),
                  child: icon,
                )
              : Center(child: icon),
        ),
      ),
    );
  }

  /// A soft diagonal band travelling across the button.
  Widget _buildGlint(double t) {
    // Travel over the first 45% of the cycle, then hold off-screen.
    final progress = (t / 0.45).clamp(0.0, 1.0);
    final dx = -1.6 + progress * 3.2;
    return FractionalTranslation(
      translation: Offset(dx, 0),
      child: Transform.rotate(
        angle: 0.32,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withOpacity(0),
                Colors.white.withOpacity(0.55),
                Colors.white.withOpacity(0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
