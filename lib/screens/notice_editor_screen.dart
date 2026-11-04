import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/official_service.dart';
import '../widgets/center_toast.dart';

/// 写 / 改一条公告（官方工作台 - 发布公告）
///
/// 为什么单开一页而不是弹个输入框：公告是「平台对全体用户说话」，
/// 字数多、要改错别字、要置顶，挤在一个小弹窗里很容易发出去才发现写错。
class NoticeEditorScreen extends StatefulWidget {
  /// 传入 = 编辑这条；null = 新建
  final OfficialNotice? notice;

  const NoticeEditorScreen({super.key, this.notice});

  @override
  State<NoticeEditorScreen> createState() => _NoticeEditorScreenState();
}

class _NoticeEditorScreenState extends State<NoticeEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _pinned;
  bool _saving = false;

  static const int _titleMax = 60;
  static const int _bodyMax = 5000;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.notice?.title ?? '');
    _body = TextEditingController(text: widget.notice?.content ?? '');
    _pinned = widget.notice?.pinned ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty) {
      CenterToast.show(context, '请填写公告标题', icon: Icons.edit_outlined);
      return;
    }
    if (body.isEmpty) {
      CenterToast.show(context, '请填写公告内容', icon: Icons.edit_outlined);
      return;
    }
    setState(() => _saving = true);
    try {
      await OfficialService.saveNotice(
        id: widget.notice?.id ?? '',
        title: title,
        content: body,
        pinned: _pinned,
      );
      if (!mounted) return;
      CenterToast.show(context, widget.notice == null ? '公告已发布' : '公告已更新',
          icon: Icons.check_circle_outline);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      final msg = net != null
          ? '网络不太好，请稍后再试'
          : (e is ApiException ? e.message : '发布失败：$e');
      CenterToast.show(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.notice != null;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(editing ? '编辑公告' : '发布公告'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: AppTheme.lightShadow,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  maxLength: _titleMax,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '标题，例如：渔报已完成升级，恢复使用',
                    border: InputBorder.none,
                    counterStyle: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary),
                  ),
                ),
                const Divider(height: 1, color: AppTheme.divider),
                TextField(
                  controller: _body,
                  maxLength: _bodyMax,
                  maxLines: null,
                  minLines: 8,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 13.5, height: 1.6),
                  decoration: const InputDecoration(
                    hintText: '正文。建议说清三件事：发生了什么、现在能不能正常用、有问题找谁。',
                    border: InputBorder.none,
                    counterStyle: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: AppTheme.lightShadow,
            ),
            child: SwitchListTile(
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              activeColor: AppTheme.accent,
              activeTrackColor: AppTheme.accent.withOpacity(0.45),
              title: const Text('置顶到信息流第一条',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('公告一般都置顶；如果只是补充说明，可以关掉',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.starLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.starDark),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '发布后会以你（官方账号）的名义出现在信息流，昵称旁带金色「官方」徽标。'
                    '写错了可以随时回来改，改完内容立刻生效。',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.starDark, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(editing ? '保存修改' : '立即发布'),
            ),
          ),
        ),
      ),
    );
  }
}
