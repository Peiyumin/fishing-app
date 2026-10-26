import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../services/app_update_service.dart';
import 'center_toast.dart';

/// 热更新弹窗
/// 流程：展示新版本说明 →「立即更新」后台下载（进度条）→ 安卓自动拉起安装；
/// iOS 受系统限制无法静默安装，改为「前往下载」跳转浏览器。
/// force=true 时弹窗不可关闭（barrierDismissible=false，无「稍后再说」按钮）。
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  /// 检查更新并有新版时弹出（供启动流程调用）
  static Future<void> checkAndShow(BuildContext context) async {
    final info = await AppUpdateService.check();
    if (info == null || !context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: !info.force,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, installing, failed }

class _UpdateDialogState extends State<UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;

  bool get _isAndroid => Theme.of(context).platform == TargetPlatform.android;

  Future<void> _startUpdate() async {
    final info = widget.info;
    // iOS：跳浏览器下载（系统不允许第三方 App 静默安装 ipa）
    if (!_isAndroid) {
      final ok = await launchUrl(
        Uri.parse(info.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) CenterToast.show(context, '无法打开下载链接');
      return;
    }
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
    });
    final path = await AppUpdateService.download(info.downloadUrl, (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    if (path == null) {
      setState(() => _phase = _Phase.failed);
      return;
    }
    setState(() => _phase = _Phase.installing);
    try {
      await AppUpdateService.installApk(path);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final force = info.force;
    final notes = info.releaseNotes.trim();

    return PopScope(
      canPop: !force && _phase != _Phase.downloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: AppTheme.accentDark),
            const SizedBox(width: 8),
            Text('发现新版本 v${info.version}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notes.isNotEmpty) ...[
              const Text('更新内容：',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(notes, style: const TextStyle(height: 1.6)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_phase == _Phase.downloading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('正在后台下载 ${(_progress * 100).toStringAsFixed(0)}%…',
                  style: const TextStyle(fontSize: 13)),
            ],
            if (_phase == _Phase.installing)
              const Text('下载完成，正在调起安装…', style: TextStyle(fontSize: 13)),            if (_phase == _Phase.failed)
              const Text('下载失败，请检查网络后重试',
                  style: TextStyle(fontSize: 13, color: Colors.red)),
          ],
        ),
        actions: [
          if (!force && _phase != _Phase.downloading)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('稍后再说'),
            ),
            if (_phase == _Phase.downloading)
              const TextButton(onPressed: null, child: Text('下载中…'))
            else if (_phase == _Phase.failed)
              TextButton(onPressed: _startUpdate, child: const Text('重试'))
            else if (_isAndroid)
              TextButton(onPressed: _startUpdate, child: const Text('立即更新'))
            else
              TextButton(onPressed: _startUpdate, child: const Text('前往下载')),
        ],
      ),
    );
  }
}
