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
        // 标题样式交给 AppTheme.appBarTheme（kAppBarTitle）——
        // 在这里再写一份 titleTextStyle 会整条覆盖主题，字号/颜色/字重
        // 各写一遍不说，还会把主题里的字体设定一起冲掉
        title: Text(ad.title.isEmpty ? '详情' : ad.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        children: [
          // 顶部大图：**按原图比例完整显示**，不裁。
          // ★ 不能写成 16:9 + BoxFit.cover：首页横幅是 12:5，cover 进 16:9
          //   左右各要切掉 ~13%，运营把字放在边上（很常见）就直接被切没了。
          //   这里宽度拉满、高度跟随原图比例，竖图最多让页面多滑两下，不丢内容。
          Image.network(
            ad.image,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            // 占位按 12:5 —— 和后台建议的横幅尺寸一致，图片加载完不会跳版
            loadingBuilder: (ctx, child, prog) => prog == null
                ? child
                : const AspectRatio(
                    aspectRatio: 12 / 5,
                    child: ColoredBox(color: AppTheme.primarySoft),
                  ),
            errorBuilder: (_, __, ___) => const AspectRatio(
              aspectRatio: 12 / 5,
              child: ColoredBox(
                color: AppTheme.primarySoft,
                child: Center(
                  child: Icon(Icons.image_outlined,
                      size: 32, color: AppTheme.textTertiary),
                ),
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
                // 免责声明是要给人看清的，别用三级灰（10px 灰字等于没写）
                style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
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
