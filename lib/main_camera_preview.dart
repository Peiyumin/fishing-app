// 仅供本地截图验收使用（不进 App 包）：直接打开渔获拍照页
//   flutter build web -t lib/main_camera_preview.dart --release -o build/web_cam
import 'package:flutter/material.dart';

import 'screens/watermark_camera_screen.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WatermarkCameraScreen(returnResult: true, title: '记渔获'),
  ));
}
