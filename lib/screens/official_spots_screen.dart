import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/official_service.dart';
import '../widgets/app_refresh.dart';
import 'official_spot_edit_screen.dart';

/// 钓点管理（v41）
///
/// 官方在 App 里直接管全站钓点：搜得到、点得进、改得动。
/// 列表按审核状态分三档（已上架 / 待审核 / 已下架）—— 批量导入的钓点
/// 经常是「导入成功但定位偏了」，得先能筛出待审核的那批逐条过一遍。
class OfficialSpotsScreen extends StatefulWidget {
  const OfficialSpotsScreen({super.key});

  @override
  State<OfficialSpotsScreen> createState() => _OfficialSpotsScreenState();
}

class _OfficialSpotsScreenState extends State<OfficialSpotsScreen> {
  final _kwCtrl = TextEditingController();
  final List<OfficialSpot> _items = [];

  String _show = 'normal'; // normal / pending / hidden
  String _kind = '';
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kwCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      if (!more) _error = null;
    });
    try {
      final list = await OfficialService.spots(
        keyword: _kwCtrl.text.trim(),
        kind: _kind,
        show: _show,
        page: more ? _page + 1 : 1,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _page++;
          _items.addAll(list);
        } else {
          _page = 1;
          _items
            ..clear()
            ..addAll(list);
        }
        // 后端一页 20 条；不满一页说明到底了
        _hasMore = list.length >= 20;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _humanError(Object e) {
    if (ApiClient.asNetError(e) != null) return '网络不太好，请稍后再试';
    if (e is ApiException) {
      if (e.status == 404) return '后台还没升级到 v41，钓点管理接口还不存在';
      return e.message;
    }
    return '加载失败：$e';
  }

  Future<void> _openEditor(OfficialSpot s) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OfficialSpotEditScreen(id: s.id, initial: s),
    ));
    if (saved == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('钓点管理'), elevation: 0),
      body: Column(
        children: [
          _searchBar(),
          _filters(),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : _error != null && _items.isEmpty
                    ? _errorView()
                    : _items.isEmpty
                        ? _empty()
                        : AppRefresh(
                            onRefresh: () => _load(),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              itemCount: _items.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                if (i == _items.length) return _footer();
                                return _row(_items[i]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _kwCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜钓点名称、地址、类型、鱼种',
                  hintStyle: const TextStyle(
                      fontSize: 12.5, color: AppTheme.textTertiary),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppTheme.textTertiary),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  filled: true,
                  fillColor: AppTheme.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: () => _load(),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('搜索', style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    const shows = [
      ('normal', '已上架'),
      ('pending', '待审核'),
      ('hidden', '已下架'),
    ];
    const kinds = [
      ('', '全部'),
      ('venue', '钓场'),
      ('wild', '野钓点'),
      ('shop', '渔具店'),
    ];
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final s in shows) ...[
                  _chip(s.$2, _show == s.$1, () {
                    if (_show == s.$1) return;
                    setState(() => _show = s.$1);
                    _load();
                  }),
                  const SizedBox(width: 6),
                ],
                Container(
                  width: 1,
                  height: 14,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: AppTheme.divider,
                ),
                for (final k in kinds) ...[
                  _chip(k.$2, _kind == k.$1, () {
                    if (_kind == k.$1) return;
                    setState(() => _kind = k.$1);
                    _load();
                  }, subtle: true),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap,
      {bool subtle = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? (subtle ? AppTheme.primaryLight : AppTheme.primary)
              : AppTheme.background,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: on ? Colors.transparent : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on
                ? (subtle ? AppTheme.primaryDark : Colors.white)
                : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _row(OfficialSpot s) {
    return InkWell(
      onTap: () => _openEditor(s),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 58,
                height: 58,
                child: (s.cover == null || s.cover!.isEmpty)
                    ? Container(
                        color: AppTheme.primaryLight,
                        alignment: Alignment.center,
                        child: const Icon(Icons.place_outlined,
                            size: 22, color: AppTheme.primary),
                      )
                    : CachedNetworkImage(
                        imageUrl: s.cover!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppTheme.divider),
                        errorWidget: (_, __, ___) => Container(
                          color: AppTheme.primaryLight,
                          alignment: Alignment.center,
                          child: const Icon(Icons.place_outlined,
                              size: 22, color: AppTheme.primary),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 6),
                      _statusPill(s),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('${s.kindLabel} · ${s.type}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                  if (s.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(s.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textTertiary)),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (!s.hasLocation)
                        const Text('缺定位',
                            style: TextStyle(
                                fontSize: 10.5, color: AppTheme.danger))
                      else
                        Text(
                          '${s.lat!.toStringAsFixed(4)}, ${s.lng!.toStringAsFixed(4)}',
                          style: const TextStyle(
                              fontSize: 10.5, color: AppTheme.textTertiary),
                        ),
                      const SizedBox(width: 8),
                      const Icon(Icons.image_outlined,
                          size: 11, color: AppTheme.textTertiary),
                      const SizedBox(width: 2),
                      Text('${s.imageCount}',
                          style: const TextStyle(
                              fontSize: 10.5, color: AppTheme.textTertiary)),
                      if (s.reportCount > 0) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.flag_outlined,
                            size: 11, color: AppTheme.danger),
                        const SizedBox(width: 2),
                        Text('${s.reportCount}',
                            style: const TextStyle(
                                fontSize: 10.5, color: AppTheme.danger)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4, top: 18),
              child: Icon(Icons.chevron_right,
                  size: 16, color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(OfficialSpot s) {
    final color = s.status == 1
        ? AppTheme.primary
        : (s.status == 2 ? AppTheme.textTertiary : AppTheme.starDark);
    final bg = s.status == 1
        ? AppTheme.primaryLight
        : (s.status == 2 ? AppTheme.background : AppTheme.starLight);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        s.statusLabel.isEmpty
            ? (s.status == 1 ? '已上架' : (s.status == 2 ? '已下架' : '待审核'))
            : s.statusLabel,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _footer() {
    if (_items.isEmpty) return const SizedBox.shrink();
    if (!_hasMore) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Center(
          child: Text('没有更多了',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textTertiary)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: TextButton(
          onPressed: _loading ? null : () => _load(more: true),
          child: Text(_loading ? '加载中…' : '加载更多',
              style: const TextStyle(
                  fontSize: 12.5, color: AppTheme.textSecondary)),
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.place_outlined,
                size: 44, color: AppTheme.textTertiary.withOpacity(0.6)),
            const SizedBox(height: 10),
            Text(
              _kwCtrl.text.trim().isEmpty ? '这个分类下还没有钓点' : '没搜到匹配的钓点',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            const Text('换个关键词，或切换到「待审核」看看',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textTertiary)),
          ],
        ),
      );

  Widget _errorView() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: AppTheme.textSecondary)),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: () => _load(), child: const Text('重新加载')),
          ],
        ),
      );
}
