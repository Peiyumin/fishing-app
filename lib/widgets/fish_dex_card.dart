import 'package:flutter/material.dart';

import '../models/fish.dart';
import 'fish_art.dart';

/// 我的页 -「钓鱼档案」卡片（图三样式）
///
/// 深色卡片，一眼能看出三件事：
/// ① 点亮了几种（3×2 鱼位网格 + 右侧那张大鱼）；
/// ② 离下一级还差几种（进度条 + 「再点亮 N 种 → Lv.2」）；
/// ③ 自己钓了多少（累计渔获 / 本月出钓 / 图鉴收藏）。
///
/// 鱼图全部用 App 内的矢量绘制（[FishArt]），不走网络——进页面立刻有内容，
/// 和鱼缸里游的是同一套画法，视觉统一。
class FishDexCard extends StatelessWidget {
  /// 图鉴数据（含已点亮鱼种）
  final FishGuide guide;

  /// 累计渔获（尾）
  final int totalCatches;

  /// 本月出钓次数
  final int monthTrips;

  /// 点卡片空白处：进图鉴详情
  final VoidCallback? onOpenDex;

  /// 点「拍一条入缸」
  final VoidCallback? onSnap;

  /// 点「我的鱼缸」
  final VoidCallback? onOpenTank;

  const FishDexCard({
    super.key,
    required this.guide,
    this.totalCatches = 0,
    this.monthTrips = 0,
    this.onOpenDex,
    this.onSnap,
    this.onOpenTank,
  });

  static const Color _cardBg = Color(0xFF0D1A16);
  static const Color _cellBg = Color(0xFF16241F);
  static const Color _lime = Color(0xFFC8FF6A);
  static const Color _muted = Color(0xFF7C8C85);

  List<FishSpecies> get _all => [...guide.fresh, ...guide.salt];
  List<FishSpecies> get _unlocked => _all.where((f) => f.unlocked).toList();

  @override
  Widget build(BuildContext context) {
    final unlocked = _unlocked;
    final lv = guide.level;
    final total = guide.totalCount > 0 ? guide.totalCount : _all.length;
    final need = lv.nextNeed > unlocked.length ? lv.nextNeed - unlocked.length : 0;
    // 右侧展示：优先最新点亮的（列表最后一条通常是最新解锁）
    final hero = unlocked.isNotEmpty ? unlocked.last : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2E27)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 标题行 ──
          Row(
            children: [
              const Text(
                '钓鱼档案',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'FISH DEX',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: _muted.withOpacity(0.9),
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _lime.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'LV.${lv.level}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: _lime,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onOpenDex,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: const [
                    Text('图鉴',
                        style: TextStyle(fontSize: 11.5, color: _muted)),
                    Icon(Icons.chevron_right, size: 15, color: _muted),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── 鱼位网格 + 右侧大鱼 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 58,
                child: SizedBox(
                  height: 134,
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      mainAxisExtent: 64,
                    ),
                    itemCount: 6,
                    itemBuilder: (_, i) {
                      if (i < 5) {
                        final f = i < unlocked.length ? unlocked[i] : null;
                        return _slot(f);
                      }
                      // 第 6 格：剩余未点亮数量 + 图鉴入口
                      final rest = total - unlocked.length;
                      return _moreSlot(rest);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 42,
                child: GestureDetector(
                  onTap: hero == null ? onSnap : onOpenDex,
                  child: _heroBox(hero, total, unlocked.length),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── 进度 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: unlocked.length.toString().padLeft(2, '0'),
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                    TextSpan(
                      text: ' / $total',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _muted.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lv.nextName.isEmpty
                          ? '已点亮全部鱼种'
                          : '再点亮 $need 种 → Lv.${lv.level + 1}「${lv.nextName}」',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _muted.withOpacity(0.95),
                      ),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total == 0
                            ? 0
                            : (unlocked.length / total).clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: const Color(0xFF22322B),
                        valueColor:
                            const AlwaysStoppedAnimation(Color(0xFFC8FF6A)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.white.withOpacity(0.07)),
          const SizedBox(height: 10),

          // ── 三个统计 ──
          Row(
            children: [
              _stat('$totalCatches', '累计渔获', '尾'),
              _divider(),
              _stat('$monthTrips', '本月出钓', '次'),
              _divider(),
              _stat('${unlocked.length}', '图鉴收藏', '种'),
            ],
          ),
          const SizedBox(height: 12),

          // ── 按钮 ──
          Row(
            children: [
              Expanded(
                flex: 3,
                child: GestureDetector(
                  onTap: onSnap,
                  child: Container(
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _lime,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_camera_outlined,
                            size: 17, color: Color(0xFF10240F)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            unlocked.isEmpty
                                ? '拍一条入缸 · 点亮第 1 种'
                                : '拍一条入缸 · 点亮第 ${unlocked.length + 1} 种',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF10240F),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onOpenTank,
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.water,
                          size: 16, color: Color(0xFF8FE3D2)),
                      const SizedBox(width: 5),
                      const Text(
                        '鱼缸',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 单个鱼位：点亮=彩色鱼+名字；未点亮=深色剪影+「未点亮」
  Widget _slot(FishSpecies? f) {
    return Container(
      decoration: BoxDecoration(
        color: _cellBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: f == null
              ? const Color(0xFF1B2A24)
              : const Color(0xFFC8FF6A).withOpacity(0.30),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: f == null
                  // 未点亮也给个轮廓，让人知道「这里能长出鱼」
                  ? Opacity(
                      opacity: 0.20,
                      child: FishArt(
                        name: '鱼',
                        size: 26,
                        locked: true,
                      ),
                    )
                  : FishArt(
                      name: f.name,
                      rarity: f.rarity,
                      waterType: f.waterType,
                      size: 30,
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              f == null ? '未点亮' : f.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: f == null ? FontWeight.w400 : FontWeight.w600,
                color: f == null ? _muted.withOpacity(0.6) : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 第 6 格：剩下还有多少种没点亮
  Widget _moreSlot(int rest) {
    return GestureDetector(
      onTap: onOpenDex,
      child: Container(
        decoration: BoxDecoration(
          color: _cellBg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF1B2A24)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '+${rest < 0 ? 0 : rest}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: _lime,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('图鉴',
                    style: TextStyle(fontSize: 9, color: _muted)),
                Icon(Icons.chevron_right, size: 11, color: _muted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 右侧大鱼展示框（水下底色 + 水草剪影 + 一条鱼）
  Widget _heroBox(FishSpecies? hero, int total, int got) {
    return Container(
      height: 134,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1D6E60), Color(0xFF0B3A34)],
        ),
      ),
      child: Stack(
        children: [
          // 水草剪影
          Positioned(
            left: 0,
            right: 0,
            bottom: -6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(5, (i) {
                final hh = 26.0 + (i % 3) * 10;
                return Container(
                  width: 7,
                  height: hh,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2F7A4A).withOpacity(0.55),
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(hh / 2)),
                  ),
                );
              }),
            ),
          ),
          if (hero != null)
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 14),
                  child: FishArt(
                    name: hero.name,
                    rarity: hero.rarity,
                    waterType: hero.waterType,
                    size: 72,
                    underwater: true,
                  ),
                ),
              ),
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.water_drop_outlined,
                      size: 26, color: Colors.white38),
                  const SizedBox(height: 5),
                  Text('还没有点亮的鱼',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.55))),
                ],
              ),
            ),
          // 右上角「已收集」角标
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$got/$total',
                style: const TextStyle(fontSize: 8.5, color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
              TextSpan(
                text: unit,
                style: const TextStyle(fontSize: 9.5, color: _muted),
              ),
            ]),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 9.5, color: _muted.withOpacity(0.9))),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: Colors.white.withOpacity(0.08),
      );
}
