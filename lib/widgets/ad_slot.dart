import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../models/app_bootstrap.dart';
import '../services/app_service.dart';
import '../widgets/center_toast.dart';
import '../screens/member_center_screen.dart';

/// 内容页广告位（文章详情页在点赞和「相关阅读」之间用它）
///
/// 数据直接复用后台「启动广告」那张表：
///   `GET /app/bootstrap` → ads（已按 sort 排序，且只返回投放期内的）
/// 后台配了就在这儿展示第一条；没配就退回一张自家推广卡 ——
/// 空着一块白，用户会以为页面坏了。
class AdSlot extends StatefulWidget {
  const AdSlot({super.key});

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> {
  AdItem? _ad;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await AppService.bootstrap();
      if (!mounted) return;
      setState(() {
        _ad = b.ads.isEmpty ? null : b.ads.first;
        _done = true;
      });
    } catch (_) {
      if (mounted) setState(() => _done = true);
    }
  }

  Future<void> _openLink() async {
    final link = _ad?.link;
    if (link == null || link.trim().isEmpty) return;
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        CenterToast.show(context, '打不开这个链接，请稍后再试');
      }
    } catch (_) {
      if (mounted) CenterToast.show(context, '打不开这个链接，请稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_done) {
      // 首帧还不知道有没有广告：占一个和广告卡等高的位置，避免内容跳动
      return const SizedBox(height: 0);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Text('广告',
                    style: TextStyle(
                        fontSize: 9,
                        height: 1.3,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              const Text('推广',
                  style: TextStyle(
                      fontSize: 10.5, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 6),
          if (ad != null)
            _adCard(ad)
          else
            _houseCard(),
        ],
      ),
    );
  }

  /// 后台配置的广告：整张图 + 标题压暗
  Widget _adCard(AdItem ad) {
    final tappable = ad.link != null && ad.link!.trim().isNotEmpty;
    return GestureDetector(
      onTap: tappable ? _openLink : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: AspectRatio(
          aspectRatio: 16 / 7,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: ad.image,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const ColoredBox(color: AppTheme.primarySoft),
                errorWidget: (_, __, ___) =>
                    const ColoredBox(color: AppTheme.primarySoft),
              ),
              if (ad.title.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 18, 12, 9),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                    child: Text(
                      ad.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
              if (tappable)
                const Positioned(
                  right: 10,
                  top: 10,
                  child: Icon(Icons.open_in_new_rounded,
                      size: 15, color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 后台没配广告时的自家推广卡
  Widget _houseCard() {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MemberCenterScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppTheme.inkBg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.workspace_premium_outlined,
                  size: 22, color: AppTheme.accent),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('渔报会员',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.inkText)),
                  SizedBox(height: 3),
                  Text('解锁全部鱼种图鉴 · 不限条数私信 · 专属标识',
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppTheme.inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('了解',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentDark)),
            ),
          ],
        ),
      ),
    );
  }
}
