// 仅供本地验收水印合成（不进 App 包）：
//   flutter build web -t lib/main_stamp_preview.dart --release -o build/web_stamp
// 页面会拿 sample_fish.jpg 走一遍真正的 stampWatermarkPng，并把结果按原尺寸显示
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'utils/watermark_stamp.dart';

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StampPreview(),
    ));

class StampPreview extends StatefulWidget {
  const StampPreview({super.key});

  @override
  State<StampPreview> createState() => _StampPreviewState();
}

class _StampPreviewState extends State<StampPreview> {
  Uint8List? _png;
  String? _err;

  @override
  void initState() {
    super.initState();
    // 先让界面渲染一次中文（CanvasKit 会在此时拉取 CJK 回退字体），
    // 再开始合成，否则 TextPainter 量到的字形是方框
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(seconds: 3));
      _run();
    });
  }

  Future<void> _run() async {
    try {
      final res = await http.get(Uri.parse('sample_fish.jpg'));
      final lines = <WatermarkLine>[
        const WatermarkLine(
            '渔报 · 钓鱼打卡', 12.5, FontWeight.w600, Color(0xE6FFFFFF)),
        WatermarkLine('2026-10-23 21:03', 26, FontWeight.w700,
            const Color(0xFFFFFFFF), 4),
        const WatermarkLine(
            '多云 22℃ · 湿度68% · 东风 3级 · 气压1012hPa',
            12.5,
            FontWeight.w500,
            Color(0xEBFFFFFF)),
        const WatermarkLine(
            '钓况82 · 鱼口活跃', 12.5, FontWeight.w600, Color(0xFFF2A93B)),
        const WatermarkLine(
            '厦门市 · 福建省厦门市集美区杏林湾路 12 号', 12.5, FontWeight.w500, Color(0xDBFFFFFF)),
      ];
      final out = await stampWatermarkPng(res.bodyBytes, lines);
      if (mounted) setState(() => _png = out);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return Scaffold(body: Center(child: Text('失败：$_err')));
    }
    if (_png == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('渔报 · 钓鱼打卡 多云 湿度 钓况 厦门市 集美区'),
              SizedBox(height: 12),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: Center(
        child: Image.memory(
          _png!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
