import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../app_version.dart';
import '../services/settings_service.dart';
import '../widgets/center_toast.dart';

/// 关于渔报
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('关于渔报'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        titleTextStyle: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
          // 品牌区
          Container(
            padding: const EdgeInsets.symmetric(vertical: 26),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Column(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: const Icon(Icons.set_meal, size: 34, color: Colors.black),
                ),
                const SizedBox(height: 12),
                const Text('渔报',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(kAppVersionText,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 10),
                const Text('记录每一次扬竿',
                    style: TextStyle(fontSize: 12.5, color: Colors.white60)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _card([
            _row('应用名称', '渔报'),
            const Divider(height: 1, indent: 13, endIndent: 13),
            _row('版本号', kAppVersionText),
            const Divider(height: 1, indent: 13, endIndent: 13),
            _row('包名', 'com.example.fishing.fishing_app'),
            const Divider(height: 1, indent: 13, endIndent: 13),
            _row('客服微信', '点击复制', onTap: () async {
              final info = await SettingsService.support();
              final wx = info.wechat.isEmpty ? 'yubao_kefu' : info.wechat;
              await Clipboard.setData(ClipboardData(text: wx));
              if (context.mounted) {
                CenterToast.show(context, '已复制微信号：$wx',
                    icon: Icons.copy_rounded);
              }
            }),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Text(
              '渔报是一款钓鱼人自己的记录工具：\n'
              '· 渔获拍照自动配天气、气压、钓点，长期积累成你的钓鱼档案\n'
              '· 鱼口指数按鱼种 × 钓法给出建议，出钓前心里有数\n'
              '· 钓点地图区分收费钓场与野钓点，标注禁钓区\n'
              '· 池塘按你真实的渔获养鱼，钓到的鱼有多大，池里就多大\n\n'
              '意见与建议欢迎通过「设置 - 联系客服」告诉我们。',
              style: TextStyle(
                  fontSize: 12.5, height: 1.75, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text('© 2026 渔报',
                style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
          ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _row(String title, String value, {VoidCallback? onTap}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(fontSize: 13.5, color: AppTheme.textPrimary)),
          const Spacer(),
          Text(value,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textTertiary)),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
