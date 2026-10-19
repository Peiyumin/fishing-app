/// App 启动引导数据模型
/// 对应后端 GET /app/bootstrap：{ previews: [...], ads: [...] }
/// previews —— 启动预览页（全屏引导图，可滑动翻页）
/// ads      —— 启动页广告（开屏图 + 倒计时跳过 + 点击跳转链接）
library;

import '../services/api_config.dart';

class PreviewItem {
  final String id;
  final String title;
  final String subtitle;
  final String image; // 绝对 URL

  const PreviewItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.image,
  });

  factory PreviewItem.fromJson(Map<String, dynamic> json) => PreviewItem(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        subtitle: (json['subtitle'] as String?) ?? '',
        image: ApiConfig.mediaUrl(json['image'] as String?) ?? '',
      );

  bool get isValid => image.isNotEmpty;
}

class AdItem {
  final String id;
  final String title;
  final String image; // 绝对 URL
  final String? link; // 点击跳转链接（可为空）

  const AdItem({
    required this.id,
    required this.title,
    required this.image,
    this.link,
  });

  factory AdItem.fromJson(Map<String, dynamic> json) => AdItem(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        image: ApiConfig.mediaUrl(json['image'] as String?) ?? '',
        link: (json['link'] as String?)?.isNotEmpty == true
            ? json['link'] as String
            : null,
      );

  bool get isValid => image.isNotEmpty;
}

class AppBootstrap {
  final List<PreviewItem> previews;
  final List<AdItem> ads;

  const AppBootstrap({this.previews = const [], this.ads = const []});

  factory AppBootstrap.fromJson(Map<String, dynamic> json) {
    final previews = (json['previews'] as List?) ?? const [];
    final ads = (json['ads'] as List?) ?? const [];
    return AppBootstrap(
      previews:
          previews.map((e) => PreviewItem.fromJson(Map<String, dynamic>.from(e as Map))).where((p) => p.isValid).toList(),
      ads: ads.map((e) => AdItem.fromJson(Map<String, dynamic>.from(e as Map))).where((a) => a.isValid).toList(),
    );
  }

  /// 是否有启动内容（无则直接进首页）
  bool get hasStartupContent => previews.isNotEmpty || ads.isNotEmpty;
}
