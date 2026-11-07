import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/home_layout.dart';
import '../widgets/center_toast.dart';

/// 首页广告详情页（v46）
///
/// 需求原话是「点击广告 App 内跳转页面显示」，所以这里**不往浏览器甩**：
/// 点横幅进到这一页，App 内直接看得到图、标题和后台填的正文；
/// 只有运营在后台额外填了外链，页面底部才多一个「打开链接」按钮，
/// 而且必须用户自己点才跳出去（避免误触跳出 App）。
class AdDetailScreen extends StatelessWidget {
  final HomeAd ad;

  const AdDetailScreen({super.key, required this.ad});

  @override
  Widget build(BuildContext context) {
    final hasContent = ad.content.trim().isNotEmpty;
    final link = (ad.link ?? '').trim();
    final hasLink = link.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(ad.title.isEmpty ? '详情' : ad.title),
        titleTextStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary),
      ),
      body: ListView(
        children: [
          // 顶部大图：和详情页一致走 16:9，图片本身已经在上一条横幅里出现过，
          // 这里给的是能看清细节的尺寸
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              ad.image,
              fit: BoxFit.cover,
              loadingBuilder: (ctx, child, prog) =>
                  prog == null ? child : Container(color: AppTheme.primarySoft),
              errorBuilder: (_, __, ___) => Container(
                color: AppTheme.primarySoft,
                alignment: Alignment.center,
                child: const Icon(Icons.image_outlined,
                    size: 32, color: AppTheme.textTertiary),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              ad.title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: AppTheme.textPrimary),
            ),
          ),
          if (hasContent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                ad.content,
                style: const TextStyle(
                    fontSize: 14.5, height: 1.75, color: AppTheme.textPrimary),
              ),
            ),
          if (!hasContent)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('该广告没有填写正文，可直接看上方图片。',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ),
          if (hasLink)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openLink(context, link),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('打开链接'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Text('该内容由商家提供，与平台立场无关',
                style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
          ),
        ],
      ),
    );
  }

  Future<void> _openLink(BuildContext context, String link) async {
    var url = link;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (context.mounted) CenterToast.show(context, '链接格式不对');
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) CenterToast.show(context, '打不开这个链接');
    } catch (_) {
      if (context.mounted) CenterToast.show(context, '打不开这个链接');
    }
  }
}
