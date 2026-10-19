import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/app_bootstrap.dart';

/// 启动预览页：全屏引导图，可左右滑动翻页
/// 打开即开始 5 秒倒计时，到点自动进主界面；右上角「跳过」可立即进入
class PreviewPagerScreen extends StatefulWidget {
  final List<PreviewItem> previews;
  final VoidCallback onFinished;

  const PreviewPagerScreen({
    super.key,
    required this.previews,
    required this.onFinished,
  });

  @override
  State<PreviewPagerScreen> createState() => _PreviewPagerScreenState();
}

class _PreviewPagerScreenState extends State<PreviewPagerScreen> {
  final _controller = PageController();
  int _page = 0;

  /// 倒计时总秒数
  static const int _totalSeconds = 5;

  int _remain = _totalSeconds;
  Timer? _timer;
  bool _entered = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _timer?.cancel();
    _remain = _totalSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_remain <= 1) {
        t.cancel();
        _enter();
      } else {
        setState(() => _remain -= 1);
      }
    });
  }

  /// 进入主界面（倒计时到点 / 点跳过，两条路都走这里，保证只触发一次）
  void _enter() {
    if (_entered) return;
    _entered = true;
    _timer?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.previews.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final p = widget.previews[i];
              return Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: p.image,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 48, color: Colors.white54),
                    ),
                  ),
                  // 底部文案区（标题 + 副标题）
                  Positioned(
                    left: 28,
                    right: 28,
                    bottom: MediaQuery.of(context).padding.bottom + 52,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.title.isNotEmpty)
                          Text(p.title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.black54, blurRadius: 8)
                                  ])),
                        if (p.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(p.subtitle,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  height: 1.5,
                                  shadows: [
                                    Shadow(color: Colors.black54, blurRadius: 8)
                                  ])),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          // 右上角「跳过 Ns」：点击立即进主界面，也顺便告诉用户还剩几秒
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 14,
            child: GestureDetector(
              onTap: _enter,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('跳过 ${_remain}s',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ),
          ),
          // 底部：页码指示点（进入按钮已移除，倒计时到点自动进主界面）
          Positioned(
            left: 28,
            right: 28,
            bottom: MediaQuery.of(context).padding.bottom + 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.previews.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i == _page ? AppTheme.primary : Colors.white54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
