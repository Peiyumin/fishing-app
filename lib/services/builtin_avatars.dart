import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';

/// 安装包内置头像（assets/avatars/）
///
/// 用途：新注册用户随机分配一个内置头像作为初始头像。
/// 实现方式：注册成功后随机选一个 asset → 写临时文件 → 上传服务器 →
/// 更新资料。头像链路与普通用户头像完全一致（都是服务器 URL），
/// 各端展示统一，无需改后端与其它页面。
class BuiltinAvatars {
  static const List<String> all = [
    'assets/avatars/avatar_01.png', // 老渔翁
    'assets/avatars/avatar_02.png', // 墨镜钓手
    'assets/avatars/avatar_03.png', // 潮流青年
    'assets/avatars/avatar_04.png', // 马尾女钓手
    'assets/avatars/avatar_05.png', // 少年
    'assets/avatars/avatar_06.png', // 阿姨
    'assets/avatars/avatar_07.png', // 短发女生
    'assets/avatars/avatar_08.png', // 胖大叔
  ];

  /// 随机挑一个内置头像 asset
  static String random() => all[Random().nextInt(all.length)];

  /// 随机选一个内置头像上传服务器，返回可访问 URL；失败返回 null
  /// （上传失败不阻塞注册流程，调用方静默降级即可）
  static Future<String?> uploadRandom() async {
    try {
      final asset = random();
      final bytes = await rootBundle.load(asset);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${asset.split('/').last}');
      await file.writeAsBytes(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          flush: true);
      return await ApiClient.uploadFile(file.path,
          contentType: 'image/png');
    } catch (_) {
      return null;
    }
  }
}
