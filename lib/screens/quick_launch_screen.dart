import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_info.dart';
import '../models/tile.dart';
import '../models/tile_page.dart';
import '../state/app_state.dart';
import '../utils/actions.dart';
import '../utils/format.dart';
import '../utils/search.dart';
import '../utils/tile_layout.dart';
import '../widgets/app_icon.dart';
import '../widgets/category_editor.dart';
import 'app_detail_screen.dart';
import 'categories_tab.dart';

class QuickLaunchScreen extends StatefulWidget {
  const QuickLaunchScreen({super.key});

  @override
  State<QuickLaunchScreen> createState() => _QuickLaunchScreenState();
}

class _QuickLaunchScreenState extends State<QuickLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final editing = state.tileEditMode && _tabs.index == 0;

    final tabBar = TabBar(
      controller: _tabs,
      tabs: const [
        Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: '磁贴'),
        Tab(icon: Icon(Icons.category_outlined, size: 20), text: '分类'),
        Tab(icon: Icon(Icons.star_outline, size: 20), text: '收藏'),
        Tab(icon: Icon(Icons.history, size: 20), text: '最近'),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(editing ? '编辑磁贴' : '快速启动',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: _actions(context, state, editing),
        bottom: editing
            ? PreferredSize(
                preferredSize: tabBar.preferredSize,
                child: AbsorbPointer(child: tabBar),
              )
            : tabBar,
      ),
      body: TabBarView(
        controller: _tabs,
        physics: editing
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(),
        children: [
          _TilesTab(state: state),
          CategoriesTab(state: state),
          _FavoritesTab(state: state),
          _RecentTab(state: state),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context, AppState state, bool editing) {
    if (_tabs.index == 0 && editing) {
      return [
        TextButton.icon(
          onPressed: () => state.setTileEditMode(false),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('完成'),
        ),
        const SizedBox(width: 4),
      ];
    }
    switch (_tabs.index) {
      case 0:
        return [
          IconButton(
            tooltip: '编辑磁贴（拖动/缩放）',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () {
              final pages = state.tilePages;
              if (pages.isEmpty || state.tilesOnPage(pages[state.currentTilePageIndex.clamp(0, pages.length - 1)]).isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('当前磁贴页还没有应用，先点击 ➕ 置顶')),
                );
                return;
              }
              state.setTileEditMode(true);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  content: Text('编辑模式：长按磁贴拖动移动，拖动右下角缩放；完成后点右上角「完成」'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 4),
                ));
            },
          ),
          IconButton(
            tooltip: '置顶应用到磁贴',
            icon: const Icon(Icons.add),
            onPressed: () => showPinSheet(context, state),
          ),
        ];
      case 1:
        return [
          IconButton(
            tooltip: '新建分类',
            icon: const Icon(Icons.add),
            onPressed: () => showCategoryEditor(context, state, null),
          ),
        ];
      default:
        return const [];
    }
  }
}

// ---------------------------------------------------------------- 磁贴

class _TilesTab extends StatefulWidget {
  const _TilesTab({required this.state});
  final AppState state;

  @override
  State<_TilesTab> createState() => _TilesTabState();
}

class _TilesTabState extends State<_TilesTab> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = widget.state.currentTilePageIndex;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setIndex(int i) {
    setState(() => _index = i);
    widget.state.setCurrentTilePage(i);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pages = state.tilePages;
    if (pages.isEmpty) {
      return _hint(
        context,
        icon: Icons.grid_view_rounded,
        text: '还没有磁贴页',
      );
    }
    if (_index >= pages.length) _index = pages.length - 1;

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            physics: state.tileEditMode
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: pages.length,
            onPageChanged: _setIndex,
            itemBuilder: (context, i) =>
                _TileBoard(state: state, page: pages[i]),
          ),
        ),
        Opacity(
          opacity: state.tileEditMode ? 0.45 : 1,
          child: AbsorbPointer(
            absorbing: state.tileEditMode,
            child: _PageBar(
              state: state,
              currentIndex: _index,
              onSelect: (i) {
                _setIndex(i);
                _controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOut,
                );
              },
              onAdd: () async {
                final page = await _promptAddPage(context, state);
                if (page == null) return;
                final idx = state.tilePages.indexWhere((p) => p.id == page.id);
                if (idx < 0) return;
                _setIndex(idx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_controller.hasClients) _controller.jumpToPage(idx);
                });
              },
              onChanged: () {
                final idx = state.currentTilePageIndex.clamp(
                    0, state.tilePages.isEmpty ? 0 : state.tilePages.length - 1);
                setState(() => _index = idx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_controller.hasClients &&
                      (_controller.page?.round() ?? 0) != idx) {
                    _controller.jumpToPage(idx);
                  }
                });
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A scrollable 6-column board. Tiles can be freely positioned and sized
/// (1x1 up to 6x6); long-press to drag, tap the corner button for options.
class _TileBoard extends StatefulWidget {
  const _TileBoard({required this.state, required this.page});
  final AppState state;
  final TilePage page;

  @override
  State<_TileBoard> createState() => _TileBoardState();
}

class _TileBoardState extends State<_TileBoard> {
  final GlobalKey _boardKey = GlobalKey();
  static const double _gap = 8;
  static const double _pad = 12;

  // Live resize preview (board-level so tiles re-layout while dragging).
  String? _resizeId;
  int _resizeW = 1;
  int _resizeH = 1;

  // Drag-to-move state with live target-cell highlight.
  String? _dragId;
  int _dragW = 1;
  int _dragH = 1;
  int _dragCol = 0;
  int _dragRow = 0;
  double _cellW = 60;

  void _startDrag(String tileId) {
    final t = widget.state.tileById(tileId);
    if (t == null) return;
    setState(() {
      _dragId = tileId;
      _dragW = t.w;
      _dragH = t.h;
      _dragCol = t.col < 0 ? 0 : t.col;
      _dragRow = t.row < 0 ? 0 : t.row;
    });
  }

  void _updateDrag(String tileId, Offset globalPosition) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final unit = _cellW + _gap;
    final col = ((local.dx - _pad) / unit)
        .round()
        .clamp(0, kTileCols - _dragW);
    final row = ((local.dy - _pad) / unit).round();
    if (row < 0) return;
    if (col != _dragCol || row != _dragRow) {
      setState(() {
        _dragCol = col;
        _dragRow = row;
      });
    }
  }

  void _endDrag(String tileId) {
    widget.state.moveTile(tileId, _dragCol, _dragRow);
    setState(() => _dragId = null);
  }

  void _cancelDrag() {
    if (_dragId == null) return;
    setState(() => _dragId = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final page = widget.page;
    final editable = state.tileEditMode;
    final pageTiles = state.tilesOnPage(page);
    if (pageTiles.isEmpty) {
      return _hint(
        context,
        icon: Icons.grid_view_rounded,
        text: '「${page.name}」还没有磁贴\n点击右上角 ➕ 选择要置顶的应用',
      );
    }

    final board = LayoutBuilder(builder: (context, constraints) {
      final cellW =
          (constraints.maxWidth - _pad * 2 - _gap * (kTileCols - 1)) / kTileCols;
      _cellW = cellW;
      final specs = pageTiles.map((t) {
        final resizing = t.id == _resizeId;
        return TileSpec(
          id: t.id,
          w: resizing ? _resizeW : t.w,
          h: resizing ? _resizeH : t.h,
          col: t.col,
          row: t.row,
        );
      }).toList();
      final layout = resolveTileLayout(specs);
      final rows = layout.rows;
      final boardHeight =
          _pad * 2 + rows * cellW + (rows > 1 ? (rows - 1) * _gap : 0.0);

      double x(int col) => _pad + col * (cellW + _gap);
      double y(int row) => _pad + row * (cellW + _gap);
      double w(int n) => n * cellW + (n - 1) * _gap;
      double h(int n) => n * cellW + (n - 1) * _gap;

      return SingleChildScrollView(
        child: SizedBox(
          key: _boardKey,
          height: boardHeight,
          width: double.infinity,
          child: Stack(
            children: [
              if (editable && _dragId != null)
                Positioned(
                  left: x(_dragCol),
                  top: y(_dragRow),
                  width: w(_dragW),
                  height: h(_dragH),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              for (final t in pageTiles)
                Builder(builder: (context) {
                  final app = state.appByPackage(t.packageName);
                  if (app == null) return const SizedBox.shrink();
                  final p = layout.placements[t.id]!;
                  return Positioned(
                    left: x(p.col),
                    top: y(p.row),
                    width: w(p.w),
                    height: h(p.h),
                    child: _Tile(
                      key: ValueKey(t.id),
                      tile: t,
                      app: app,
                      state: state,
                      cellW: cellW,
                      gap: _gap,
                      editable: editable,
                      onDragStart: () => _startDrag(t.id),
                      onDragUpdate: (pos) => _updateDrag(t.id, pos),
                      onDragEnd: () => _endDrag(t.id),
                      onDragCancel: _cancelDrag,
                    ),
                  );
                }),
              if (editable)
                for (final t in pageTiles)
                  Builder(builder: (context) {
                    final p = layout.placements[t.id]!;
                    return Positioned(
                      left: x(p.col) + w(p.w) - _kHandleSize,
                      top: y(p.row) + h(p.h) - _kHandleSize,
                      width: _kHandleSize,
                      height: _kHandleSize,
                      child: _ResizeHandle(
                        state: state,
                        tileId: t.id,
                        cellW: cellW,
                        gap: _gap,
                        onPreview: (pw, ph) => setState(() {
                          _resizeId = t.id;
                          _resizeW = pw;
                          _resizeH = ph;
                        }),
                        onEnd: () {
                          state.setTileSize(t.id, _resizeW, _resizeH);
                          setState(() => _resizeId = null);
                        },
                      ),
                    );
                  }),
            ],
          ),
        ),
      );
    });

    return board;
  }
}

const double _kHandleSize = 40;

/// A bottom-right grip that resizes a tile directly on the board.
///
/// Uses an immediate drag recognizer so the enclosing scroll view never steals
/// the gesture (which made vertical resizing scroll the board instead).
class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.state,
    required this.tileId,
    required this.cellW,
    required this.gap,
    required this.onPreview,
    required this.onEnd,
  });

  final AppState state;
  final String tileId;
  final double cellW;
  final double gap;
  final void Function(int w, int h) onPreview;
  final VoidCallback onEnd;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  double _startW = 1;
  double _startH = 1;
  double _accX = 0;
  double _accY = 0;
  int _w = 1;
  int _h = 1;
  bool _active = false;

  void _start(Offset _) {
    final t = widget.state.tileById(widget.tileId);
    if (t == null) return;
    _startW = t.w.toDouble();
    _startH = t.h.toDouble();
    _w = t.w;
    _h = t.h;
    _accX = 0;
    _accY = 0;
    setState(() => _active = true);
  }

  void _update(Offset delta) {
    final unit = widget.cellW + widget.gap;
    _accX += delta.dx;
    _accY += delta.dy;
    final gw = (_startW + _accX / unit).round().clamp(1, kTileCols);
    final gh = (_startH + _accY / unit).round().clamp(1, kTileMaxH);
    if (gw != _w || gh != _h) {
      setState(() {
        _w = gw;
        _h = gh;
      });
      widget.onPreview(gw, gh);
    }
  }

  void _end() {
    if (!_active) return;
    setState(() => _active = false);
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        ImmediateMultiDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
                ImmediateMultiDragGestureRecognizer>(
          () => ImmediateMultiDragGestureRecognizer(),
          (instance) {
            instance.onStart = (position) {
              _start(position);
              return _ResizeDrag(onUpdate: _update, onEnd: _end);
            };
          },
        ),
      },
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: CustomPaint(
            size: const Size(22, 22),
            painter: _CornerGripPainter(active: _active),
          ),
        ),
      ),
    );
  }
}

class _ResizeDrag extends Drag {
  _ResizeDrag({required this.onUpdate, required this.onEnd});

  final void Function(Offset delta) onUpdate;
  final VoidCallback onEnd;

  @override
  void update(DragUpdateDetails details) => onUpdate(details.delta);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

/// Draws a small rounded corner border in the bottom-right corner.
class _CornerGripPainter extends CustomPainter {
  _CornerGripPainter({required this.active});

  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 2.0;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: active ? 1.0 : 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = active ? 3.5 : 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final r = size.width * 0.38;
    final path = Path()
      ..moveTo(inset, size.height - inset)
      ..lineTo(size.width - r, size.height - inset)
      ..quadraticBezierTo(
          size.width - inset, size.height - inset, size.width - inset, size.height - r)
      ..lineTo(size.width - inset, inset);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerGripPainter oldDelegate) =>
      oldDelegate.active != active;
}

/// Bottom page switcher (put at the very bottom, like a tab bar).
class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.state,
    required this.currentIndex,
    required this.onSelect,
    required this.onChanged,
    required this.onAdd,
  });

  final AppState state;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = state.tilePages;
    if (pages.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 54,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: pages.length,
              itemBuilder: (context, i) {
                final page = pages[i];
                final selected = i == currentIndex;
                final count = state.pinCountOnPage(page);
                final fg = selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: GestureDetector(
                    onTap: () => onSelect(i),
                    onLongPress: () => _pageMenu(context, state, i, onChanged),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            page.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: fg,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              color: fg.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '新建磁贴页',
            icon: const Icon(Icons.add),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

Future<TilePage?> _promptAddPage(BuildContext context, AppState state) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新建磁贴页'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '页面名称'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('创建')),
      ],
    ),
  );
  if (name == null) return null;
  return state.addTilePage(name);
}

void _pageMenu(
  BuildContext context,
  AppState state,
  int index,
  VoidCallback onChanged,
) {
  final page = state.tilePages[index];
  final canLeft = index > 0;
  final canRight = index < state.tilePages.length - 1;
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(page.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Text('第 ${index + 1} / ${state.tilePages.length} 页',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.arrow_back),
            title: const Text('左移（手动排序）'),
            enabled: canLeft,
            onTap: canLeft
                ? () async {
                    Navigator.pop(ctx);
                    await state.moveTilePage(index, -1);
                    onChanged();
                  }
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.arrow_forward),
            title: const Text('右移（手动排序）'),
            enabled: canRight,
            onTap: canRight
                ? () async {
                    Navigator.pop(ctx);
                    await state.moveTilePage(index, 1);
                    onChanged();
                  }
                : null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('重命名页面'),
            onTap: () async {
              Navigator.pop(ctx);
              final controller = TextEditingController(text: page.name);
              final name = await showDialog<String>(
                context: context,
                builder: (dctx) => AlertDialog(
                  title: const Text('重命名页面'),
                  content: TextField(controller: controller, autofocus: true),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dctx),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () =>
                            Navigator.pop(dctx, controller.text.trim()),
                        child: const Text('保存')),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty) {
                await state.renameTilePage(page.id, name);
                onChanged();
              }
            },
          ),
          if (state.tilePages.length > 1)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除页面'),
              subtitle: const Text('页面上的磁贴会移回第一个页面'),
              onTap: () async {
                Navigator.pop(ctx);
                await state.deleteTilePage(page.id);
                onChanged();
              },
            ),
        ],
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.tile,
    required this.app,
    required this.state,
    required this.cellW,
    required this.gap,
    required this.editable,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  final Tile tile;
  final AppInfo app;
  final AppState state;
  final double cellW;
  final double gap;
  final bool editable;
  final VoidCallback onDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    final width = tile.w * cellW + (tile.w - 1) * gap;
    final height = tile.h * cellW + (tile.h - 1) * gap;
    final shortest = width < height ? width : height;
    final iconSize = (shortest * 0.42).clamp(24.0, 96.0);
    final fontScale = (shortest / 56).clamp(0.85, 1.9);

    final content = _content(context, iconSize, fontScale, editable);

    if (!editable) return content;

    return LongPressDraggable<String>(
      data: tile.id,
      delay: const Duration(milliseconds: 180),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _feedback(width, height, content),
      childWhenDragging: Opacity(opacity: 0.3, child: content),
      onDragStarted: () {
        HapticFeedback.selectionClick();
        onDragStart();
      },
      onDragUpdate: (d) => onDragUpdate(d.globalPosition),
      onDragEnd: (d) => onDragEnd(),
      onDraggableCanceled: (v, o) => onDragCancel(),
      child: content,
    );
  }

  Widget _content(
      BuildContext context, double iconSize, double fontScale, bool editable) {
    final color = _tileColor(app.appName);
    final tappable = Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: editable
            ? () => _showTileMenu(context)
            : () => launchApp(context, app.packageName),
        onLongPress: editable ? null : () => _showTileMenu(context),
        child: Stack(
          children: [
            Positioned(
              left: 10,
              top: 10,
              right: 26,
              child: AppIcon(
                packageName: app.packageName,
                label: app.appName,
                size: iconSize,
              ),
            ),
            Positioned(
              left: 10,
              right: 8,
              bottom: 8,
              child: Text(
                app.appName,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (12 * fontScale).clamp(11.0, 20.0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (editable) {
      return Stack(
        children: [
          Positioned.fill(child: tappable),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // No visible overflow button: the menu is opened by long-pressing (browse
    // mode) or tapping (edit mode).
    return tappable;
  }

  Widget _feedback(double width, double height, Widget child) {
    return SizedBox(
      width: width,
      height: height,
      child: Transform.scale(
        scale: 1.04,
        child: Material(
          color: Colors.transparent,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: Opacity(opacity: 0.92, child: child),
        ),
      ),
    );
  }

  void _showTileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('应用详情'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AppDetailScreen(packageName: app.packageName),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('移除该磁贴'),
                onTap: () {
                  Navigator.pop(ctx);
                  state.removeTile(tile.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _tileColor(String label) {
    final hash = label.codeUnits.fold<int>(0, (p, c) => p * 31 + c);
    final hue = (hash % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.5, 0.42).toColor();
  }
}

// ---------------------------------------------------------------- 收藏

class _FavoritesTab extends StatefulWidget {
  const _FavoritesTab({required this.state});
  final AppState state;

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final favorites = state.favorites;

    final results = _query.trim().isEmpty
        ? <AppInfo>[]
        : AppSearch.rank(state.apps, _query, limit: 12);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(
              hintText: '搜索任意应用并立即启动',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_query.trim().isNotEmpty)
          Expanded(child: _resultList(state, results))
        else
          Expanded(child: _favoritesGrid(state, favorites)),
      ],
    );
  }

  Widget _resultList(AppState state, List<AppInfo> results) {
    if (results.isEmpty) {
      return const Center(child: Text('没有找到匹配的应用'));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: results.length,
      itemBuilder: (context, i) {
        final app = results[i];
        return ListTile(
          leading: AppIcon(packageName: app.packageName, label: app.appName),
          title: Text(app.appName),
          subtitle:
              Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.rocket_launch_outlined),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            launchApp(context, app.packageName);
          },
        );
      },
    );
  }

  Widget _favoritesGrid(AppState state, List<AppInfo> favorites) {
    if (favorites.isEmpty) {
      return _hint(
        context,
        icon: Icons.star_outline,
        text: '还没有收藏的应用\n在应用列表点击 ⭐ 收藏，即可在这里一键启动',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, i) {
        final app = favorites[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => launchApp(context, app.packageName),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AppDetailScreen(packageName: app.packageName),
            ),
          ),
          child: Column(
            children: [
              AppIcon(packageName: app.packageName, label: app.appName, size: 56),
              const SizedBox(height: 8),
              Text(
                app.appName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 最近

class _RecentTab extends StatelessWidget {
  const _RecentTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final apps = state.recentApps;
    if (apps.isEmpty) {
      return _hint(
        context,
        icon: Icons.history,
        text: '还没有启动记录\n从囤囤里启动应用后会出现在这里',
      );
    }
    return ListView.builder(
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final app = apps[i];
        final meta = state.metaFor(app.packageName);
        return ListTile(
          leading: AppIcon(packageName: app.packageName, label: app.appName),
          title: Text(app.appName),
          subtitle: Text('上次启动 ${Fmt.relative(meta.lastLaunchedAt)}'),
          trailing: const Icon(Icons.rocket_launch_outlined, size: 20),
          onTap: () => launchApp(context, app.packageName),
          onLongPress: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AppDetailScreen(packageName: app.packageName),
            ),
          ),
        );
      },
    );
  }
}

Widget _hint(BuildContext context,
    {required IconData icon, required String text}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    ),
  );
}
