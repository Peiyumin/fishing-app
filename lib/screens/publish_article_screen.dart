import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/api_config.dart';
import '../services/content_service.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import 'auth_screen.dart';

/// 投稿文章
///
/// 提交后进入「待审核」，后台通过才会出现在技巧 / 路亚列表里。
/// 这里遵循 App 的既有原则：不做启动即弹权限、不用全屏 spinner，提交按钮自己转圈。
class PublishArticleScreen extends StatefulWidget {
  final String defaultCategory;
  const PublishArticleScreen({super.key, this.defaultCategory = 'skill'});

  @override
  State<PublishArticleScreen> createState() => _PublishArticleScreenState();
}

class _PublishArticleScreenState extends State<PublishArticleScreen> {
  static const _cats = <String, String>{
    'skill': '垂钓技巧',
    'lure_skill': '路亚技巧',
    'lure_gear': '路亚装备',
    'lure_review': '路亚评测',
  };

  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _body = TextEditingController();
  late String _cat = _cats.containsKey(widget.defaultCategory)
      ? widget.defaultCategory
      : 'skill';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty) {
      CenterToast.show(context, '请先填写标题');
      return;
    }
    if (body.isEmpty) {
      CenterToast.show(context, '正文不能为空');
      return;
    }
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (ApiConfig.enabled && !sp.isLoggedIn) {
      CenterToast.show(context, '请先登录后再投稿', icon: Icons.lock_outline);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    setState(() => _busy = true);
    final r = await ContentService.submitArticle(
      title: title,
      content: body,
      category: _cat,
      summary: _summary.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop(true);
    } else {
      CenterToast.show(context, r.msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('写文章')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.warningLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: AppTheme.warning),
                SizedBox(width: 7),
                Expanded(
                  child: Text('提交后需要后台审核，通过后才会显示在列表里',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.warning,
                          height: 1.4)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _label('标题'),
          _field(_title, hint: '给文章起个名字', maxLength: 60),
          const SizedBox(height: 14),
          _label('分类'),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _cat,
                isExpanded: true,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary),
                items: _cats.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _cat = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          _label('摘要（选填）', sub: '留空会自动截取正文开头'),
          _field(_summary, hint: '一句话概括这篇讲什么', maxLength: 60),
          const SizedBox(height: 14),
          _label('正文'),
          _field(_body, hint: '空行分段，写清楚就能发布', maxLines: 12),
          const SizedBox(height: 22),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primary.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
                elevation: 0,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('提交审核',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        children: [
          Text(t,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          if (sub != null) ...[
            const SizedBox(width: 6),
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c, {
    String? hint,
    int maxLength = 200,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        maxLength: maxLength,
        style: const TextStyle(fontSize: 14, height: 1.6),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          border: InputBorder.none,
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}
