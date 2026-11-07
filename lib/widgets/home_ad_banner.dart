import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/home_layout.dart';
import '../screens/ad_detail_screen.dart';

/// 首页广告位（v46）
///
/// 尺寸策略：**外框按 12:5 固定比例**（宽 12 高 5），图片统一 `BoxFit.cover`。
/// 为什么不按图片原始尺寸自适应：后台运营上传的图尺寸五花八门，
/// 自适应的话首页每次换素材都会把下面的「附近钓点」顶下去一截，
/// 用户会以为页面在抖。固定比例还有个好处 —— 竖图也会被裁成横幅，
/// 不会出现一张细长条图片把首页撑开。
///
/// 点击一律进 App 内的广告详情页（不在浏览器里跳走），
/// 详情页里如果配了外链，再给一个明确的「打开链接」按钮。
class HomeAdBanner extends StatelessWidget {
  final HomeAd ad;

  const HomeAdBanner({super.key, required this.ad});

  /// 固定宽高比（宽 / 高）——后台建议 1200×500 正好是这个比例
  static const double aspect = 12 / 5;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.pagePad, 4, AppTheme.pagePad, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: aspect,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                ad.image,
                fit: BoxFit.cover,
                // 加载中/失败都画底色，不留白洞（白洞会被误认成页面错位）
                loadingBuilder: (ctx, child, prog) =>
                    prog == null ? child : Container(color: AppTheme.primarySoft),
                errorBuilder: (_, __, ___) => Container(
                  color: AppTheme.primarySoft,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_outlined,
                      size: 26, color: AppTheme.textTertiary),
                ),
              ),
              // 整块可点：命中区域 = 图片区域，不需要额外留热区
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AdDetailScreen(ad: ad))),
                ),
              ),
              // 「广告」角标：不遮画面主体，只在右下角淡淡标一下
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('广告',
                      style: TextStyle(fontSize: 10, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
