import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/user_address.dart';
import '../services/settings_service.dart';
import '../utils/legal_text.dart';
import '../widgets/center_toast.dart';

/// 协议文本页（用户协议 / 隐私政策 / 两份清单 / 个人信息与权限说明）
///
/// 正文由后端 /legal/{key} 下发，纯文本：
///   · `## ` 开头 → 小节标题
///   · 其它行 → 正文段落
/// 后端不可用时用 SettingsService.fallbackLegal 的提示文本，不会白屏。
class LegalDocScreen extends StatefulWidget {
  const LegalDocScreen({super.key, required this.docKey, required this.title});

  final String docKey;
  final String title;

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  LegalDoc? _doc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final doc = await SettingsService.legal(widget.docKey);
      if (mounted) setState(() => _doc = doc);
    } catch (e) {
      if (mounted) CenterToast.show(context, '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : doc == null
              ? Center(
                  child: TextButton(onPressed: _load, child: const Text('加载失败，点击重试')),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
                  children: [
                    ..._render(doc.content),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text('渔报 · 本页内容随版本更新',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textTertiary)),
                    ),
                  ],
                ),
    );
  }

  /// 纯文本 → 段落 Widget（`## ` 当小标题）
  List<Widget> _render(String content) {
    final blocks = parseLegalText(content);
    final out = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.isTitle) {
        out.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 6 : 16, bottom: 6),
          child: Text(
            b.text,
            style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
        ));
      } else {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            b.text,
            style: const TextStyle(
                fontSize: 13.5, height: 1.75, color: AppTheme.textSecondary),
          ),
        ));
      }
    }
    return out;
  }
}
