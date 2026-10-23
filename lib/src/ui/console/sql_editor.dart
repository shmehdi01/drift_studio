import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../controllers/sql_editing_controller.dart';
import '../../core/sql_autocomplete.dart';
import '../studio_theme.dart';

/// A SQL code editor: syntax highlighting, caret-anchored autocomplete and
/// IDE-style shortcuts.
///
/// * Ctrl/⌘ + Enter — run
/// * Ctrl + Space — show suggestions
/// * ↑ / ↓, Enter / Tab, Esc — navigate, accept, dismiss suggestions
/// * Tab — indent when no suggestion is open
class SqlEditor extends StatefulWidget {
  /// Creates an editor.
  const SqlEditor({
    super.key,
    required this.controller,
    required this.autocomplete,
    required this.onRun,
  });

  /// Text controller (also provides highlighting).
  final SqlEditingController controller;

  /// Supplies a completer built from the current schema.
  final SqlAutocomplete Function() autocomplete;

  /// Runs the query.
  final VoidCallback onRun;

  @override
  State<SqlEditor> createState() => _SqlEditorState();
}

class _SqlEditorState extends State<SqlEditor> {
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _portal = OverlayPortalController();
  final _fieldKey = GlobalKey();
  final _list = ScrollController();

  List<SqlSuggestion> _suggestions = const [];
  int _highlighted = 0;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_onChanged);
    _focus.addListener(() {
      if (!_focus.hasFocus) _hide();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.dispose();
    _list.dispose();
    super.dispose();
  }

  void _onChanged() {
    final c = widget.controller;
    // Only typing re-triggers completion; moving the caret closes it.
    if (c.text == _lastText) {
      if (_portal.isShowing) _hide();
      return;
    }
    _lastText = c.text;
    _update();
  }

  void _update({bool force = false}) {
    final c = widget.controller;
    if (!c.selection.isValid || !c.selection.isCollapsed) return _hide();
    final next = widget.autocomplete().suggest(
          c.text,
          c.selection.baseOffset,
          force: force,
        );
    if (next.isEmpty) return _hide();
    setState(() {
      _suggestions = next;
      _highlighted = 0;
    });
    _portal.show();
  }

  void _hide() {
    if (_portal.isShowing) _portal.hide();
    if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
  }

  void _accept(SqlSuggestion s) {
    final c = widget.controller;
    final ctx = SqlAutocomplete.contextAt(c.text, c.selection.baseOffset);
    final text = c.text.replaceRange(ctx.start, ctx.end, s.insertText);
    _lastText = text;
    c.value = TextEditingValue(
      text: text,
      selection:
          TextSelection.collapsed(offset: ctx.start + s.insertText.length),
    );
    _hide();
  }

  void _insert(String text) {
    final c = widget.controller;
    final sel = c.selection.isValid
        ? c.selection
        : TextSelection.collapsed(offset: c.text.length);
    c.value = TextEditingValue(
      text: c.text.replaceRange(sel.start, sel.end, text),
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final mod = keys.isControlPressed || keys.isMetaPressed;
    final k = e.logicalKey;

    if (mod &&
        (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.numpadEnter)) {
      _hide();
      widget.onRun();
      return KeyEventResult.handled;
    }
    if (keys.isControlPressed && k == LogicalKeyboardKey.space) {
      _update(force: true);
      return KeyEventResult.handled;
    }
    if (_suggestions.isNotEmpty && _portal.isShowing) {
      if (k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.arrowUp) {
        final delta = k == LogicalKeyboardKey.arrowDown ? 1 : -1;
        setState(() {
          _highlighted = (_highlighted + delta) % _suggestions.length;
        });
        _scrollToHighlighted();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.tab) {
        _accept(_suggestions[_highlighted]);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        _hide();
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.tab && !keys.isShiftPressed) {
      _insert('  ');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollToHighlighted() {
    if (!_list.hasClients) return;
    const itemExtent = 30.0;
    final target = _highlighted * itemExtent;
    final pos = _list.position;
    if (target < pos.pixels) {
      _list.jumpTo(target);
    } else if (target + itemExtent > pos.pixels + pos.viewportDimension) {
      _list.jumpTo(target + itemExtent - pos.viewportDimension);
    }
  }

  /// TextField hides its [RenderEditable], but its caret geometry is what
  /// lets the popup follow the cursor like an IDE, so it's found by walking
  /// the field's render subtree.
  Rect? _caretRectGlobal() {
    final box = _fieldKey.currentContext?.findRenderObject();
    if (box == null) return null;
    RenderEditable? editable;
    void visit(RenderObject o) {
      if (editable != null) return;
      if (o is RenderEditable) {
        editable = o;
        return;
      }
      o.visitChildren(visit);
    }

    visit(box);
    final r = editable;
    final sel = widget.controller.selection;
    if (r == null || !sel.isValid) return null;
    final local = r.getLocalRectForCaret(TextPosition(offset: sel.baseOffset));
    return MatrixUtils.transformRect(r.getTransformTo(null), local);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    widget.controller.colors = SqlHighlightColors.fromScheme(scheme);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildPopup,
      child: Container(
        color: scheme.surfaceContainerLowest,
        child: TextField(
          key: _fieldKey,
          controller: widget.controller,
          focusNode: _focus,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
          smartQuotesType: SmartQuotesType.disabled,
          smartDashesType: SmartDashesType.disabled,
          textAlignVertical: TextAlignVertical.top,
          style: monoStyle(context, size: 13.5),
          cursorColor: scheme.primary,
          decoration: const InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.fromLTRB(16, 14, 16, 14),
          ),
        ),
      ),
    );
  }

  Widget _buildPopup(BuildContext context) {
    final caret = _caretRectGlobal();
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (caret == null || overlayBox == null || _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final size = overlayBox.size;
    final anchor = overlayBox.globalToLocal(caret.bottomLeft);
    const width = 340.0;
    final height = (_suggestions.length * 30.0 + 8).clamp(0.0, 248.0);
    final below = anchor.dy + 4 + height < size.height - 8;
    final top = below ? anchor.dy + 4 : anchor.dy - caret.height - 4 - height;
    final left = anchor.dx
        .clamp(8.0, (size.width - width - 8).clamp(8.0, double.infinity));
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: _SuggestionList(
        suggestions: _suggestions,
        highlighted: _highlighted,
        controller: _list,
        onTap: _accept,
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.highlighted,
    required this.controller,
    required this.onTap,
  });

  final List<SqlSuggestion> suggestions;
  final int highlighted;
  final ScrollController controller;
  final ValueChanged<SqlSuggestion> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemExtent: 30,
        itemCount: suggestions.length,
        itemBuilder: (context, i) {
          final s = suggestions[i];
          final active = i == highlighted;
          return InkWell(
            onTap: () => onTap(s),
            child: Container(
              color: active ? scheme.primaryContainer : null,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _KindIcon(kind: s.kind),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle(
                        context,
                        size: 12.5,
                        color: active ? scheme.onPrimaryContainer : null,
                      ),
                    ),
                  ),
                  if (s.detail != null)
                    Flexible(
                      child: Text(
                        s.detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});

  final SuggestionKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (kind) {
      SuggestionKind.table => ('T', scheme.primary),
      SuggestionKind.column => ('C', scheme.tertiary),
      SuggestionKind.keyword => ('K', scheme.secondary),
      SuggestionKind.function => ('ƒ', scheme.error),
    };
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }
}
