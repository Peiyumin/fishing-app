import 'package:flutter/material.dart';

import '../../app_theme.dart';

/// 启动封面：拉取启动配置（预览页/广告）时的品牌展示
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular( 26),
              ),
              child: const Icon(Icons.phishing, size: 62, color: AppTheme.primary),
            ),
            const SizedBox(height: 20),
            const Text('垂钓圈',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6)),
            const SizedBox(height: 8),
            const Text('找钓点 · 看天气 · 晒渔获',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 44),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
