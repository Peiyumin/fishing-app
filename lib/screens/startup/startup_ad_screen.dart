import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import '../../models/app_bootstrap.dart';
import '../../widgets/center_toast.dart';

/// 启动页广告：全屏广告图 + 倒计时「跳过」按钮
/// 多条广告按后台排序依次展示，每条 3 秒；点击图片打开跳转链接
class StartupAdScreen extends StatefulWidget {
  final List<AdItem> ads;
  final VoidCallback onFinished; // 全部广告结束（或用户跳过）

  const StartupAdScreen({
    super.key,
    required this.ads,
    required this.onFinished,
  });

  @override
  State<StartupAdScreen> createState() => _StartupAdScreenState();
}

class _StartupAdScreenState extends State<StartupAdScreen> {
  static const int _secondsPerAd = 3;
  int _index = 0;
  int _left = _secondsPerAd;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _left = _secondsPerAd;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        _next();
      } else {
        setState(() => _left--);
      }
    });
  }

  void _next() {
    _timer?.cancel();
    if (_index + 1 < widget.ads.length) {
      setState(() {
        _index++;
      });
      _startTimer();
    } else {
      widget.onFinished();
    }
  }

  Future<void> _openLink() async {
    final link = widget.ads[_index].link;
    if (link == null) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        CenterToast.show(context, '链接打开失败');
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ads[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 广告图（点击跳转）
          GestureDetector(
            onTap: ad.link != null ? _openLink : null,
            child: CachedNetworkImage(
              imageUrl: ad.image,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined,
                    size: 48, color: Colors.white54),
              ),
            ),
          ),
          // 顶部：广告标识 + 跳过
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 14,
            right: 14,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('广告',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ),
                const Spacer(),
                // 倒计时跳过按钮
                GestureDetector(
                  onTap: widget.onFinished,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('跳过 $_left',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
          // 底部：品牌署名
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 18,
            left: 0,
            right: 0,
            child: const Column(
              children: [
                Text('垂钓圈',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3)),
                SizedBox(height: 2),
                Text('找钓点 · 看天气 · 晒渔获',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
          // 多条广告时的进度指示
          if (widget.ads.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 64,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.ads.length,
                  (i) => Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? AppTheme.primary
                          : Colors.white54,
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
