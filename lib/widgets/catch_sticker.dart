import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 渔报表情（快捷回复用）
///
/// ★ 正文里存的是「[好鱼！]」这种中括号中文，不是私有 token：
///   老版本 App / 网页后台 / 没联网的其它端不认识表情图，看到的也是能读懂的
///   中文短语，不会出现乱码或「看不懂的代码」；新版本解析到中括号才换成图。
class CatchSticker {
  /// 文件名（assets/stickers/{id}.png）
  final String id;

  /// 中文标签，同时也是写进评论正文的文字
  final String label;

  /// 解析时接受的写法（全角/半角问号、感叹号各一份）
  final List<String> aliases;

  const CatchSticker(this.id, this.label, this.aliases);

  String get asset => 'assets/stickers/$id.png';

  String get token => '[$label]';
}

/// 顺序＝快捷回复栏里的顺序
const kCatchStickers = <CatchSticker>[
  CatchSticker('haoyu', '好鱼！', ['好鱼！', '好鱼!']),
  CatchSticker('baohu', '爆护了', ['爆护了']),
  CatchSticker('zhemeda', '这么大？', ['这么大？', '这么大?']),
  CatchSticker('qiudian', '求钓点', ['求钓点']),
];

/// 表情解析：把评论正文拆成「文字 + 表情」两段
class StickerCodec {
  static final RegExp _pattern = RegExp(
    r'\[(' +
        kCatchStickers
            .expand((s) => s.aliases.map(RegExp.escape))
            .join('|') +
        r')\]',
  );

  static CatchSticker? _of(String inner) {
    for (final s in kCatchStickers) {
      if (s.aliases.contains(inner)) return s;
    }
    return null;
  }

  /// 正文里是否含表情标记
  static bool has(String text) => text.contains('[') && _pattern.hasMatch(text);

  /// 整条评论是否只是一个表情（这种居中放大显示）
  static CatchSticker? single(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    return m.start == 0 && m.end == text.trim().length ? _of(m.group(1)!) : null;
  }

  /// 拆成 TextSpan 片段：表情走 WidgetSpan，其余原样文字
  static List<InlineSpan> spans(
    String text, {
    required double size,
    bool animate = false,
  }) {
    final spans = <InlineSpan>[];
    var cur = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > cur) {
        spans.add(TextSpan(text: text.substring(cur, m.start)));
      }
      final s = _of(m.group(1)!);
      if (s == null) {
        spans.add(TextSpan(text: m.group(0)));
      } else {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: size * .08),
              child: StickerImage(sticker: s, size: size, animate: animate),
            ),
          ),
        );
      }
      cur = m.end;
    }
    if (cur < text.length) spans.add(TextSpan(text: text.substring(cur)));
    return spans;
  }
}

/// 单个表情图
///
/// [animate] = true 时做一次「弹出来」的入场（评论里新发的表情会跳一下）；
/// 常驻的快捷栏用 [LiveStickerBar]，那边是持续轻微的浮动。
class StickerImage extends StatelessWidget {
  final CatchSticker sticker;
  final double size;
  final bool animate;

  const StickerImage({
    super.key,
    required this.sticker,
    required this.size,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      sticker.asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      // 表情图是透明 PNG：gapless 防止刷新时闪一下空帧
      gaplessPlayback: true,
    );
    if (!animate) return SizedBox(width: size, height: size, child: img);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .55, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(
        scale: v,
        alignment: Alignment.center,
        child: child,
      ),
      child: SizedBox(width: size, height: size, child: img),
    );
  }
}

/// 快捷回复栏：4 个表情持续轻微浮动（错相），点一下先缩再弹
///
/// 一个 ticker 驱动整排，不是每个表情各起一个 —— 详情页底部常驻，
/// 四个 controller 一起跑会白白多出三份每帧回调。
class LiveStickerBar extends StatefulWidget {
  final double size;
  final void Function(CatchSticker) onTap;

  const LiveStickerBar({super.key, required this.onTap, this.size = 56});

  @override
  State<LiveStickerBar> createState() => _LiveStickerBarState();
}

class _LiveStickerBarState extends State<LiveStickerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  String? _pressed;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap(CatchSticker s) {
    setState(() => _pressed = s.id);
    Future.delayed(const Duration(milliseconds: 130), () {
      if (mounted) setState(() => _pressed = null);
    });
    widget.onTap(s);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.size + 12,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            children: [
              for (var i = 0; i < kCatchStickers.length; i++)
                _item(kCatchStickers[i], i),
            ],
          );
        },
      ),
    );
  }

  Widget _item(CatchSticker s, int i) {
    // 错相：每个表情差 1/4 周期，看起来像依次呼吸而不是整排一起跳
    final float = 0.5 + 0.5 * math.sin(_c.value * 2 * math.pi + i * 1.35);
    final dy = -1.8 * float;
    final scale = 1.0 - 0.035 * (1 - float);
    final pressed = _pressed == s.id;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: Transform.translate(
          offset: Offset(0, pressed ? 1.5 : dy),
          child: Transform.scale(
            scale: pressed ? .84 : scale,
            child: StickerImage(sticker: s, size: widget.size),
          ),
        ),
      ),
    );
  }
}
