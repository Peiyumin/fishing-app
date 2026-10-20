import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 钓点标记：定位针 + 「钓点」文字标签。
/// 让用户一眼看出这个标记是一个「可以钓鱼的地方」，而不是普通地点。
class SpotMapMarker extends StatelessWidget {
  final Color color;
  final String label;
  const SpotMapMarker({
    super.key,
    this.color = AppTheme.primary,
    this.label = '钓点',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.location_on,
          color: color,
          size: 34,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(top: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

/// 「我的位置」标记：蓝色圆点 + 白边（标准定位指示），
/// 与钓点标记区分，方便用户确认自己当前所在位置。
class MyLocationMarker extends StatelessWidget {
  const MyLocationMarker({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
      );
}
