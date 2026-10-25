import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/fish.dart';
import '../services/api_client.dart';
import '../services/fish_service.dart';
import '../services/session_provider.dart';
import '../widgets/app_refresh.dart';
import '../widgets/center_toast.dart';
import '../widgets/fish_photo.dart';

/// 鱼种图鉴（v27，参考图五）
/// 淡水 / 海水两大类；解锁进度驱动等级晋升；未解锁置灰。
class FishGuideScreen extends StatefulWidget {
  const FishGuideScreen({super.key});

  @override
  State<FishGuideScreen> createState() => _FishGuideScreenState();
}

class _FishGuideScreenState extends State<FishGuideScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  FishGuide _guide = FishService.fallback;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final g = await FishService.guide();
      if (!mounted) return;
      setState(() {
        _guide = g;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final lv = _guide.level;
    final unlocked = _guide.unlockedCount;
    final need = lv.nextNeed > unlocked ? lv.nextNeed - unlocked : 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('我的鱼种图鉴',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '我的池塘',
            icon: const Icon(Icons.water, color: AppTheme.accent),
            onPressed: () => Navigator.of(context).pushNamed('/fish-tank'),
          ),
        ],
      ),
      body: AppRefresh(
        color: AppTheme.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            if (_loading) _loadingBar(),
            _header(session, lv, need),
            _aiCard(),
            _statsBar(),
            _tabBar(),
            _grid(_tab.index == 0 ? _guide.fresh : _guide.salt),
          ],
        ),
      ),
    );
  }

  /// AI 识鱼入口：上传渔获照片 → 识别鱼种 → 一键激活图鉴
  Widget _aiCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: _recognizing ? null : _recognize,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.primaryBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: _recognizing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary))
                      : const Icon(Icons.auto_awesome,
                          size: 20, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI 识鱼',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('上传渔获照片，自动识别鱼种并激活图鉴',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _recognizing = false;

  /// 选图 → 上传 → AI 识别 → 让用户确认候选 → 激活图鉴
  Future<void> _recognize() async {
    final session = context.read<SessionProvider>();
    if (!session.isLoggedIn) {
      CenterToast.show(context, '请先登录后再使用 AI 识鱼');
      return;
    }
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      setState(() => _recognizing = true);

      final urls = await ApiClient.uploadImages([picked.path], watermark: true);
      if (urls.isEmpty) {
        CenterToast.show(context, '图片上传失败');
        return;
      }
      final url = urls.first;
      final r = await FishService.recognize(url);
      if (!mounted) return;

      if (r.needManual || r.matched.isEmpty) {
        CenterToast.show(context, r.msg.isEmpty ? '未识别到鱼种，请手动选择' : r.msg);
        // 降级：展开鱼种选择，让用户手动挑
        _showManualPicker(url);
        return;
      }
      _showMatchSheet(r.matched, url);
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  /// 识别到多个候选时弹出确认
  void _showMatchSheet(List<FishMatch> matches, String image) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusLg),
            topRight: Radius.circular(AppTheme.radiusLg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('识别结果',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('点击正确的鱼种即可激活图鉴',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: matches
                  .map((m) => GestureDetector(
                        onTap: () async {
                          Navigator.of(context).pop();
                          await _unlock(m.id, image);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: m.rarity == 'common'
                                ? AppTheme.primaryLight
                                : AppTheme.starLight,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.primary),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🐟',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: m.rarity == 'common'
                                          ? AppTheme.primary
                                          : AppTheme.warning)),
                              const SizedBox(width: 6),
                              Text(m.name,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 5),
                              Text(m.waterType == 'salt' ? '海水' : '淡水',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  /// AI 没识别出来时，让用户从词库里手动挑一个激活
  void _showManualPicker(String image) {
    final all = [..._guide.fresh, ..._guide.salt];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppTheme.radiusLg),
              topRight: Radius.circular(AppTheme.radiusLg),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('手动选择鱼种',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final f = all[i];
                    return ListTile(
                      dense: true,
                      leading: Text(f.isFresh ? '💧' : '🌊',
                          style: const TextStyle(fontSize: 17)),
                      title: Text(f.name,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: f.alias.isNotEmpty
                          ? Text(f.alias,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.textSecondary))
                          : null,
                      trailing: f.unlocked
                          ? const Text('已解锁',
                              style: TextStyle(
                                  fontSize: 10.5, color: AppTheme.primary))
                          : null,
                      onTap: () async {
                        Navigator.of(context).pop();
                        await _unlock(f.id, image);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlock(String speciesId, String image) async {
    try {
      final g = await FishService.unlock(speciesId, image: image);
      if (!mounted) return;
      setState(() => _guide = g);
      CenterToast.show(context, '已激活图鉴');
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Widget _loadingBar() => const Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: LinearProgressIndicator(
            minHeight: 2,
            color: AppTheme.primary,
            backgroundColor: AppTheme.divider),
      );

  Widget _header(SessionProvider session, FishLevel lv, int need) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.star, width: 2),
            ),
            child: CircleAvatar(
              radius: 34,
              backgroundColor: AppTheme.primaryLight,
              backgroundImage: (session.avatarUrl != null &&
                      session.avatarUrl!.isNotEmpty)
                  ? NetworkImage(session.avatarUrl!)
                  : null,
              child: (session.avatarUrl == null || session.avatarUrl!.isEmpty)
                  ? const Icon(Icons.person,
                      size: 34, color: AppTheme.primary)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Lv.${lv.level}',
                  style: const TextStyle(
                      color: AppTheme.star,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text(lv.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            lv.nextName.isEmpty
                ? '已解锁 ${_guide.unlockedCount} 种，达到最高等级'
                : '再发现 $need 个新鱼种，即可晋级 Lv.${lv.level + 1}「${lv.nextName}」',
            style: TextStyle(
                color: Colors.white.withOpacity(0.88), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statsBar() {
    final rare = [..._guide.fresh, ..._guide.salt]
        .where((f) => f.rarity != 'common')
        .length;
    final rareUnlocked =
        [..._guide.fresh, ..._guide.salt].where((f) => f.rarity != 'common' && f.unlocked).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child:       Row(
        children: [
          _statCell('常见鱼种', '${_guide.fresh.length + _guide.salt.length - rare}'),
          Container(width: 1, height: 26, color: AppTheme.divider),
          _statCell('稀有鱼种', '$rareUnlocked/$rare'),
        ],
      ),    );
  }

  Widget _statCell(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _tabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      decoration: BoxDecoration(
        color: AppTheme.primarySoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: TabBar(
        controller: _tab,
        onTap: (_) => setState(() {}),
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textSecondary,
        labelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        indicator: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: [
          Tab(text: '淡水鱼 (${_guide.fresh.length})'),
          Tab(text: '海水鱼 (${_guide.salt.length})'),
        ],
      ),
    );
  }

  Widget _grid(List<FishSpecies> list) {
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(34),
        child: Center(
          child: Text('该分类下暂无鱼种',
              style: TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 118,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final f = list[i];
          return GestureDetector(
            onTap: () => _showDetail(f),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                color: f.unlocked ? AppTheme.surface : AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                border: Border.all(
                  color: f.unlocked ? AppTheme.primaryBorder : AppTheme.border,
                  width: f.unlocked ? 1.2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 鱼图是 App 内置的真实鱼照（46 种，透明 PNG）：
                  // 不再等后端图片，弱网/断网也能立刻看到完整图鉴
                  Expanded(
                    child: Center(
                      child: FishPhoto(
                        name: f.name,
                        waterType: f.waterType,
                        height: f.unlocked ? 40 : 34,
                        locked: !f.unlocked,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    f.unlocked ? f.name : '未解锁',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: f.unlocked ? FontWeight.w700 : FontWeight.w500,
                      color: f.unlocked
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                  if (f.unlocked && f.count > 1) ...[
                    const SizedBox(height: 2),
                    Text('×${f.count}',
                        style: const TextStyle(
                            fontSize: 9.5, color: AppTheme.textSecondary)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDetail(FishSpecies f) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppTheme.radiusLg),
            topRight: Radius.circular(AppTheme.radiusLg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: f.unlocked ? AppTheme.primaryLight : AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Center(
                    child: FishPhoto(
                      name: f.name,
                      waterType: f.waterType,
                      height: 58,
                      locked: !f.unlocked,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.unlocked ? f.name : '未解锁鱼种',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          _chip(f.isFresh ? '淡水' : '海水'),
                          _chip(f.rarityText),
                          if (f.unlocked) _chip('已解锁 ×${f.count}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (f.alias.isNotEmpty) ...[
              const Text('别名 / 俗称',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(f.alias,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
              const SizedBox(height: 12),
            ],
            Text(
              f.unlocked
                  ? (f.intro.isEmpty ? '还没有填写该鱼种的简介。' : f.intro)
                  : '发布渔获时有这条鱼即可自动解锁；也可在发布后手动选择激活。',
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textSecondary,
                  height: 1.55),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10.5,
                color: AppTheme.primaryDark,
                fontWeight: FontWeight.w600)),
      );
}
