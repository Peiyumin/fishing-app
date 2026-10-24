import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/activity.dart';
import '../services/api_config.dart';
import '../services/content_service.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import 'auth_screen.dart';

/// 活动详情
///
/// 列表接口不返回正文，这里按 id 再拉一次，同时拿到「我是否已报名」。
/// 底部固定报名按钮；名额满 / 已报名 / 未过审都会变成不可点状态。
class ActivityDetailScreen extends StatefulWidget {
  final Activity activity;
  const ActivityDetailScreen({super.key, required this.activity});

  @override
  State<ActivityDetailScreen> createState() => _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends State<ActivityDetailScreen> {
  late Activity _a = widget.activity;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final full = await ContentService.fetchActivity(widget.activity.id);
    if (!mounted) return;
    setState(() {
      if (full != null) _a = full;
      _loading = false;
    });
  }

  Future<void> _join() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (ApiConfig.enabled && !sp.isLoggedIn) {
      CenterToast.show(context, '请先登录后再报名', icon: Icons.lock_outline);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    setState(() => _busy = true);
    final r = await ContentService.joinActivity(_a.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      setState(() {
        _a = _copyWith(
          joined: true,
          joinCount: r.joinCount > 0 ? r.joinCount : _a.joinCount + 1,
        );
      });
      CenterToast.show(context, r.msg, icon: Icons.check_circle_outline);
    } else {
      CenterToast.show(context, r.msg);
    }
  }

  /// Activity 没有 copyWith，这里只改报名相关的两个字段
  Activity _copyWith({bool? joined, int? joinCount}) {
    return Activity(
      id: _a.id,
      title: _a.title,
      cover: _a.cover,
      summary: _a.summary,
      content: _a.content,
      startAt: _a.startAt,
      endAt: _a.endAt,
      location: _a.location,
      fee: _a.fee,
      contact: _a.contact,
      authorId: _a.authorId,
      authorName: _a.authorName,
      statusLabel: _a.statusLabel,
      rejectReason: _a.rejectReason,
      createdAt: _a.createdAt,
      maxJoin: _a.maxJoin,
      joinCount: joinCount ?? _a.joinCount,
      status: _a.status,
      full: _a.full,
      joined: joined ?? _a.joined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showBar = _a.isApproved;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('活动详情')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(14, 12, 14, showBar ? 22 : 40),
        children: [
          if (_a.cover.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                _a.cover,
                width: double.infinity,
                height: 170,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_a.isPending || _a.isRejected) ...[
            _statusBanner(),
            const SizedBox(height: 12),
          ],
          Text(_a.title,
              style: const TextStyle(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _a.joined
                      ? AppTheme.primaryLight
                      : const Color(0xFFF2F5F3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_a.joined ? '已报名' : _a.joinText,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _a.joined
                            ? AppTheme.primary
                            : AppTheme.textSecondary)),
              ),
              if (_a.authorName.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text('发起人 ${_a.authorName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textSecondary)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _infoCard(),
          if (_a.summary.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_a.summary,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppTheme.textPrimary)),
            ),
          ],
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_a.paragraphs.isEmpty)
            const Text('发起人没有留下详细说明',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))
          else
            ..._a.paragraphs.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 13),
                  child: Text(p,
                      style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.75,
                          color: AppTheme.textPrimary)),
                )),
        ],
      ),
      bottomNavigationBar: showBar ? _joinBar() : null,
    );
  }

  /// 时间 / 地点 / 费用 / 名额 / 联系
  Widget _infoCard() {
    final rows = <Widget>[];
    void add(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return;
      if (rows.isNotEmpty) {
        rows.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 9),
          child: Divider(color: AppTheme.divider, height: 1),
        ));
      }
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppTheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary)),
          ),
        ],
      ));
    }

    add(Icons.schedule, '时间', _a.rangeText);
    add(Icons.place_outlined, '地点', _a.location);
    add(Icons.payments_outlined, '费用', _a.fee);
    add(Icons.groups_outlined, '名额', _a.joinText);
    add(Icons.call_outlined, '联系', _a.contact);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: rows),
    );
  }

  Widget _joinBar() {
    final joined = _a.joined;
    final full = _a.full && !joined;
    final enabled = !joined && !full && !_busy;
    final label = joined ? '已报名' : (full ? '名额已满' : '立即报名');
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: SizedBox(
          height: 46,
          child: ElevatedButton(
            onPressed: enabled ? _join : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: joined ? AppTheme.primaryLight : AppTheme.primary,
              foregroundColor: joined ? AppTheme.primary : Colors.white,
              disabledBackgroundColor: joined
                  ? AppTheme.primaryLight
                  : const Color(0xFFDDE4E0),
              disabledForegroundColor:
                  joined ? AppTheme.primary : AppTheme.textSecondary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (joined)
                        const Icon(Icons.check_circle_outline, size: 17),
                      if (joined) const SizedBox(width: 5),
                      Text(label,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _statusBanner() {
    final rejected = _a.isRejected;
    final color = rejected ? AppTheme.danger : AppTheme.warning;
    final bg = rejected ? AppTheme.dangerLight : AppTheme.warningLight;
    final text = rejected
        ? '这个活动没有通过审核${_a.rejectReason.isNotEmpty ? "：${_a.rejectReason}" : ""}'
        : '这个活动还在审核中，通过后才会出现在活动列表里';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(rejected ? Icons.error_outline : Icons.schedule,
              size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
