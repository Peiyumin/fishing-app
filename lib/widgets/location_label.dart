import 'package:flutter/material.dart';

import '../utils/geo_names.dart';

/// 定位文字：若原始值是坐标（如「34.141, 113.461」），自动逆地编码成中文地名；
/// 已是中文地名则原样显示。
///
/// 用于动态卡片、详情页等所有展示 `_post.locationName` 的位置——
/// 这样**历史动态里存的坐标也能正确显示成城市名**，无需刷库。
class LocationLabel extends StatefulWidget {
  const LocationLabel({
    super.key,
    required this.raw,
    this.style,
    this.maxLines = 1,
  });

  /// 原始定位字符串（可能是坐标，也可能是地名）
  final String raw;
  final TextStyle? style;
  final int maxLines;

  @override
  State<LocationLabel> createState() => _LocationLabelState();
}

class _LocationLabelState extends State<LocationLabel> {
  late String _text;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _text = widget.raw;
    _maybeResolve();
  }

  @override
  void didUpdateWidget(covariant LocationLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raw != widget.raw) {
      _text = widget.raw;
      _maybeResolve();
    }
  }

  Future<void> _maybeResolve() async {
    if (!GeoNames.isCoordinate(widget.raw)) return;
    if (_resolving) return;
    _resolving = true;
    try {
      final name = await GeoNames.resolveName(widget.raw);
      if (!mounted) return;
      if (name != widget.raw) setState(() => _text = name);
    } catch (_) {
      // 逆地编码失败时保留坐标原文，不影响展示
    } finally {
      _resolving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _text,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      style: widget.style,
    );
  }
}