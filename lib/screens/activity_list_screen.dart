import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/activity.dart';
import '../services/content_service.dart';
import 'activity_detail_screen.dart';
import 'my_submissions_screen.dart';
import 'publish_activity_screen.dart';
import '../widgets/app_refresh.dart';

/// 活动列表（首页「活动」入口）
///
/// 只显示后台审核通过的活动，按开始时间升序。
/// 右上角可发布活动，发布后进后台审核，通过才出现在这个列表里。
class ActivityListScreen extends StatefulWidget {
  const ActivityListScreen({super.key});

  @override
  State<ActivityListScreen> createState() => _ActivityListScreenState();
}

class _ActivityListScreenState extends State<ActivityListScreen> {
  List<Activity> _list = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ContentService.fetchActivities();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _openPublish() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PublishActivityScreen()),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交，审核通过后会出现在活动列表里')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('活动'),
        actions: [
          IconButton(
            tooltip: '我的发布',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const MySubmissionsScreen(initialTab: 0)),
            ),
            icon: const Icon(Icons.assignment_outlined, size: 21),
          ),
          TextButton.icon(
            onPressed: _openPublish,
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('发布', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            )
          : AppRefresh(
              onRefresh: _load,
              child: _list.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                            height:
                                MediaQuery.of(context).size.height * 0.2),
                        const _EmptyTips(),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _ActivityCard(
                        activity: _list[i],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ActivityDetailScreen(activity: _list[i]),
                          ),
                        ),
                      ),
                    ),
            ),
    );
  }
}

class _EmptyTips extends StatelessWidget {
  const _EmptyTips();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Icon(Icons.event_outlined, size: 52, color: AppTheme.border),
        SizedBox(height: 12),
        Text('近期还没有活动',
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
        SizedBox(height: 6),
        Text('可以自己发起一场，审核通过后会出现在这里',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback onTap;
  const _ActivityCard({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final hasCover = a.cover.isNotEmpty;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.divider),
          ),
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dateBadge(a),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 7),
                    _meta(Icons.schedule, a.rangeText),
                    if (a.location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _meta(Icons.place_outlined, a.location),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: a.full
                                ? AppTheme.warningLight
                                : AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(a.full ? '名额已满' : a.joinText,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: a.full
                                      ? AppTheme.warning
                                      : AppTheme.primary)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(a.fee.isEmpty ? '' : a.fee,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.deepOrange)),
                        ),
                        const Icon(Icons.chevron_right,
                            size: 16, color: AppTheme.textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
              if (hasCover) ...[
                const SizedBox(width: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.network(
                    a.cover,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 左侧日期牌：上「10月」下「25」
  Widget _dateBadge(Activity a) {
    final hasDate = a.dayText.isNotEmpty;
    return Container(
      width: 52,
      height: 58,
      decoration: BoxDecoration(
        gradient: AppTheme.headerGradient,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(hasDate ? a.monthText : '待定',
              style: const TextStyle(
                  fontSize: 10.5,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500)),
          if (hasDate)
            Text(a.dayText,
                style: const TextStyle(
                    fontSize: 20,
                    height: 1.15,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12.5, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, color: AppTheme.textSecondary)),
        ),
      ],
    );
  }
}
