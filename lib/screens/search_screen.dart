import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/spot_service.dart';
import 'post_detail_screen.dart';
import 'spot_detail_screen.dart';

/// 搜索页
///
/// 之前是「本地生成 3 条假结果」的演示页，点不动、也搜不到东西。
/// 现在真的打后端：`/spots?keyword=` 和 `/posts?keyword=` 并行查，
/// 结果按「钓点 / 渔获」分组，每条都能点进对应的详情页。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  /// 历史搜索（本次会话内保留；点击标签可直接再搜）
  List<String> _history = const ['千岛湖', '路亚', '黑坑', '鲫鱼'];

  List<FishingSpot> _spots = const [];
  List<Post> _posts = const [];

  String _q = '';
  bool _busy = false;
  bool _searched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    if (!_history.contains(q)) {
      setState(() => _history = <String>[q, ..._history].take(8).toList());
    }
    setState(() {
      _q = q;
      _busy = true;
      _searched = true;
    });

    // 两个接口并行，单个失败只当那一组为空，不影响另一组出结果
    final spotF = SpotService.fetchSpots(keyword: q)
        .then<List<FishingSpot>>((v) => v, onError: (_) => <FishingSpot>[]);
    final postF = PostService.fetchFeed(limit: 20, keyword: q)
        .then<List<Post>>((v) => v, onError: (_) => <Post>[]);
    final spots = await spotF;
    final posts = await postF;

    if (!mounted) return;
    setState(() {
      _spots = spots;
      _posts = posts;
      _busy = false;
    });
  }

  void _openSpot(FishingSpot s) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: s)));
  }

  void _openPost(Post p) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: p)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '搜索钓点 / 渔获',
              hintStyle: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary),
              prefixIcon: Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
              prefixIconConstraints: BoxConstraints(minWidth: 38),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 11),
            ),
            onSubmitted: _search,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _search(_ctrl.text),
            child: const Text('搜索',
                style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_busy) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (!_searched) return _historyView();
    if (_spots.isEmpty && _posts.isEmpty) return _emptyView();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        if (_spots.isNotEmpty) ...[
          _groupTitle('钓点', _spots.length),
          ..._spots.map(_spotRow),
          const SizedBox(height: 14),
        ],
        if (_posts.isNotEmpty) ...[
          _groupTitle('渔获', _posts.length),
          ..._posts.map(_postRow),
        ],
      ],
    );
  }

  Widget _historyView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('历史搜索',
            style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _history
              .map((h) => _chip(h, () {
                    _ctrl.text = h;
                    _search(h);
                  }))
              .toList(),
        ),
        const SizedBox(height: 24),
        const Text('试试搜这些',
            style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['野钓', '水库', '长江', '垂钓技巧']
              .map((h) => _chip(h, () {
                    _ctrl.text = h;
                    _search(h);
                  }))
              .toList(),
        ),
      ],
    );
  }

  Widget _chip(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textPrimary)),
      ),
    );
  }

  Widget _groupTitle(String name, int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 13,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(name,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(width: 5),
          Text('$n',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _spotRow(FishingSpot s) {
    final sub = [
      if (s.type.isNotEmpty) s.type,
      if (s.address.isNotEmpty) s.address,
    ].join(' · ');
    return _card(
      onTap: () => _openSpot(s),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.place_outlined,
            size: 22, color: AppTheme.primary),
      ),
      title: s.name,
      subtitle: sub.isEmpty ? '钓点' : sub,
    );
  }

  Widget _postRow(Post p) {
    final cover = p.imageUrls.isNotEmpty ? p.imageUrls.first : null;
    final sub = [
      if ((p.username ?? '').isNotEmpty) p.username!,
      '${p.likeCount} 赞',
      if (p.city.isNotEmpty) p.city,
    ].join(' · ');
    return _card(
      onTap: () => _openPost(p),
      leading: cover == null
          ? Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.photo_library_outlined,
                  size: 20, color: AppTheme.primary),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                cover,
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 42,
                  height: 42,
                  color: AppTheme.primaryLight,
                  child: const Icon(Icons.broken_image_outlined,
                      size: 18, color: AppTheme.primary),
                ),
              ),
            ),
      title: p.title.isEmpty ? '（无标题）' : p.title,
      subtitle: sub,
      maxLines: 2,
    );
  }

  Widget _card({
    required VoidCallback onTap,
    required Widget leading,
    required String title,
    required String subtitle,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: maxLines,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.textSecondary)),
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

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded,
              size: 52, color: AppTheme.border),
          const SizedBox(height: 12),
          Text('没找到和「$_q」有关的内容',
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textPrimary)),
          const SizedBox(height: 6),
          const Text('换个关键词试试，比如地名、鱼种、钓法',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
