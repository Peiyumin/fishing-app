import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';

/// 表情数据：按主流 IM 习惯分组，「最近」由本地使用记录动态生成。
///
/// 为什么自己维护而不是引第三方包：钓鱼 App 只需要「常用表情 + 快捷短语」，
/// 引包会带上几百 KB 资源和不必要的依赖；自带的这 200 个覆盖了
/// 评论/聊天/发布场景的绝大多数表达。
class EmojiData {
  EmojiData._();

  static const List<String> recent = [];

  static const List<String> common = [
    '😀', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '😉', '😊',
    '😇', '🥰', '😍', '😘', '😋', '😜', '🤪', '🤨', '🧐', '🤓',
    '😎', '🥳', '😏', '😌', '😔', '😞', '😢', '😭', '😤', '😠',
    '🤯', '🤔', '🤗', '🤝', '👍', '👎', '🙏', '💪', '🎣', '🐟',
  ];

  static const List<String> faces = [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
    '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😋',
    '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔', '🤐',
    '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥', '😌',
    '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮', '🤧',
    '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '😎', '🤓', '🧐',
  ];

  static const List<String> hands = [
    '👋', '🤚', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟',
    '🤘', '🤙', '👈', '👉', '👆', '👇', '☝️', '👍', '👎', '👊',
    '✊', '🤛', '🤜', '🤞', '🤝', '🤲', '🙌', '👏', '🙏', '💪',
    '🦾', '✍️', '🖐️', '🖖', '👐', '🤲', '👊', '✊', '🤛', '🤜',
  ];

  static const List<String> animals = [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
    '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🦆', '🦅',
    '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌',
    '🐞', '🐜', '🐢', '🐍', '🦎', '🐙', '🦑', '🦐', '🦀', '🐡',
    '🐠', '🐟', '🐬', '🐳', '🐋', '🦈', '🐊', '🐅', '🦓', '🦍',
  ];

  static const List<String> food = [
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍈',
    '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🍆', '🥑', '🥦',
    '🥬', '🥒', '🌶️', '🌽', '🥕', '🧄', '🧅', '🥔', '🍠', '🥐',
    '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳', '🧈', '🥞', '🧇',
    '🥓', '🥩', '🍗', '🍖', '🌭', '🍔', '🍟', '🍕', '🥪', '🥙',
    '🧆', '🌮', '🌯', '🥗', '🥘', '🍝', '🍜', '🍲', '🍛', '🍣',
    '🍱', '🥟', '🍤', '🍙', '🍚', '🍘', '🥧', '🍰', '🎂', '🧁',
    '🍫', '🍬', '🍭', '🍮', '🍯', '🍺', '🍻', '🥂', '🍷', '🥃',
  ];

  static const List<String> activity = [
    '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
    '🏓', '🏸', '🥊', '🥋', '🎽', '🛹', '🚴', '🚵', '🧗', '🏇',
    '🏂', '🏌️', '🏄', '🏊', '🏋️', '🤼', '🤸', '🤺', '🤾', '⛳',
    '🏹', '🎣', '🤿', '🎽', '🎫', '🎟', '🎪', '🎭', '🎨', '🎬',
    '🎤', '🎧', '🎼', '🎹', '🥁', '🎷', '🎺', '🎸', '🪕', '🎻',
    '🎲', '♟️', '🎯', '🎳', '🎮', '🎰', '🧩', '🏆', '🥇', '🥈',
  ];

  static const List<String> symbols = [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💯', '💢',
    '💥', '💫', '💦', '💨', '💬', '💭', '🗯️', '♈', '♉', '♊',
    '♋', '♌', '♍', '♎', '♏', '♐', '♑', '♒', '✅', '❌',
    '❓', '❗', '⭕', '🚫', '💤', '🔔', '🔕', '🎵', '🎶', '🔥',
    '⭐', '🌟', '✨', '⚡', '☀️', '🌙', '☁️', '🌧️', '⛈️', '🌈',
  ];

  static const List<MapEntry<String, List<String>>> tabs = [
    MapEntry('最近', recent),
    MapEntry('常用', common),
    MapEntry('表情', faces),
    MapEntry('手势', hands),
    MapEntry('动物', animals),
    MapEntry('美食', food),
    MapEntry('活动', activity),
    MapEntry('符号', symbols),
  ];
}

/// 最近使用表情的本地存储（最多 24 个，倒序）
class EmojiRecentStore {
  EmojiRecentStore._();
  static const _key = 'emoji_recent_v1';
  static const _max = 24;

  static Future<List<String>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final list = (jsonDecode(raw) as List).cast<String>();
      return list.take(_max).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(String emoji) async {
    if (emoji.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = await load();
      list.remove(emoji);
      final next = [emoji, ...list].take(_max).toList();
      await p.setString(_key, jsonEncode(next));
    } catch (_) {}
  }
}

/// 表情选择面板（内嵌式，供输入栏上方展开）
class EmojiPanel extends StatefulWidget {
  final void Function(String emoji) onPick;
  final VoidCallback? onBackspace;
  final double height;

  const EmojiPanel({
    super.key,
    required this.onPick,
    this.onBackspace,
    this.height = 236,
  });

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final list = await EmojiRecentStore.load();
    if (!mounted) return;
    setState(() => _recent = list);
  }

  Future<void> _pick(String e) async {
    widget.onPick(e);
    await EmojiRecentStore.add(e);
    if (!mounted) return;
    final list = await EmojiRecentStore.load();
    if (!mounted) return;
    setState(() => _recent = list);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <MapEntry<String, List<String>>>[
      MapEntry('最近', _recent.isEmpty ? EmojiData.common : _recent),
      ...EmojiData.tabs.where((t) => t.key != '最近'),
    ];

    return SizedBox(
      height: widget.height,
      child: DefaultTabController(
        length: tabs.length,
        child: Column(
          children: [
            Container(
              color: AppTheme.surface,
              constraints: const BoxConstraints(maxHeight: 40),
              child: TabBar(
                isScrollable: true,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
                tabs: [for (final t in tabs) Tab(text: t.key)],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final t in tabs)
                    GridView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: t.value.length + 1,
                      itemBuilder: (_, i) {
                        // 最后一格放退格键
                        if (i == t.value.length) {
                          return GestureDetector(
                            onTap: widget.onBackspace,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.primarySoft,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                  Icons.backspace_outlined,
                                  size: 18,
                                  color: AppTheme.primary),
                            ),
                          );
                        }
                        final e = t.value[i];
                        return GestureDetector(
                          onTap: () => _pick(e),
                          child: Container(
                            alignment: Alignment.center,
                            child: Text(e,
                                style: const TextStyle(fontSize: 24)),
                          ),
                        );
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
}

/// 在输入框光标处插入文本（表情或快捷短语）
void insertAtCursor(TextEditingController controller, String text) {
  if (text.isEmpty) return;
  final sel = controller.selection;
  final start = sel.isValid ? sel.start : controller.text.length;
  final end = sel.isValid ? sel.end : controller.text.length;
  final newText =
      controller.text.replaceRange(start, end, text);
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(
        offset: (start + text.length).clamp(0, newText.length)),
  );
}

/// 快捷表情短语栏（图四底部那排「早上好 / 比心 / 困 / 捂脸 / 赞」）
class QuickEmojiBar extends StatelessWidget {
  final void Function(String text) onPick;

  /// 可自定义；默认给聊天场景的招呼短语
  final List<MapEntry<String, String>> items;

  const QuickEmojiBar({
    super.key,
    required this.onPick,
    this.items = defaultItems,
  });

  static const List<MapEntry<String, String>> defaultItems = [
    MapEntry('👋', '早上好'),
    MapEntry('❤️', '比心'),
    MapEntry('😪', '困'),
    MapEntry('🤭', '捂脸'),
    MapEntry('👍', '赞'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final it = items[i];
          return GestureDetector(
            onTap: () => onPick(it.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Text(it.key, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 3),
                  Text(it.value,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryDark)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 弹出式表情选择（bottom sheet），供发布/评论类页面使用
///
/// 与内嵌式 [EmojiPanel] 的区别：不占输入栏空间，点表情图标才滑出，
/// 适合表单类页面（发布动态、活动、文章、签名）。
Future<void> showEmojiSheet(
  BuildContext context,
  TextEditingController controller,
) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.emoji_emotions_outlined,
                    size: 16, color: AppTheme.primary),
                SizedBox(width: 6),
                Text('选择表情',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ],
            ),
          ),
          EmojiPanel(
            height: 260,
            onPick: (e) => insertAtCursor(controller, e),
            onBackspace: () => backspaceAtCursor(controller),
          ),
        ],
      ),
    ),
  );
}

/// 退格一个字符（正确处理 emoji 的代理对，不会劈出乱码半截）
void backspaceAtCursor(TextEditingController controller) {
  final text = controller.text;
  if (text.isEmpty) return;
  final sel = controller.selection;
  if (sel.isValid && sel.start != sel.end) {
    final newText = text.replaceRange(sel.start, sel.end, '');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start),
    );
    return;
  }
  // 逐字符删除（emoji 按 code point 删一个）
  final runes = text.runes.toList();
  if (runes.isEmpty) return;
  final cut = runes.length >= 2 &&
          (runes[runes.length - 2] & 0xFFFF) >= 0xD800 &&
          (runes[runes.length - 2] & 0xFC00) == 0xD800 &&
          (runes[runes.length - 1] & 0xFC00) == 0xDC00
      ? 2
      : 1;
  final newText = String.fromCharCodes(runes.sublist(0, runes.length - cut));
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newText.length),
  );
}
