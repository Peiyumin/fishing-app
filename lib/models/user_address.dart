/// 收货地址（设置 - 收货地址）
class UserAddress {
  final String id;
  final String name;
  final String phone;
  final String region;
  final String detail;
  final bool isDefault;

  const UserAddress({
    required this.id,
    required this.name,
    required this.phone,
    this.region = '',
    required this.detail,
    this.isDefault = false,
  });

  factory UserAddress.fromJson(Map<String, dynamic> j) {
    return UserAddress(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      region: (j['region'] ?? '').toString(),
      detail: (j['detail'] ?? '').toString(),
      isDefault: j['isDefault'] == true || j['isDefault'] == 1,
    );
  }

  /// 完整地址：省市区 + 详细门牌
  String get fullAddress =>
      region.isEmpty ? detail : '$region $detail';

  /// 手机号中间四位打码（列表里展示）
  String get maskedPhone {
    if (phone.length < 7) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'region': region,
        'detail': detail,
        'isDefault': isDefault,
      };
}

/// 协议文档
class LegalDoc {
  final String key;
  final String title;
  final String content;

  const LegalDoc({required this.key, required this.title, required this.content});

  factory LegalDoc.fromJson(Map<String, dynamic> j) => LegalDoc(
        key: (j['key'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
      );
}

/// 客服信息
class SupportInfo {
  final String phone;
  final String wechat;
  final String hours;

  const SupportInfo({
    this.phone = '',
    this.wechat = '',
    this.hours = '',
  });

  factory SupportInfo.fromJson(dynamic j) {
    if (j is! Map) return const SupportInfo();
    return SupportInfo(
      phone: (j['phone'] ?? '').toString(),
      wechat: (j['wechat'] ?? '').toString(),
      hours: (j['hours'] ?? '').toString(),
    );
  }
}

/// 设置快照（服务端返回的偏好 + 客服信息）
class SettingsSnapshot {
  final bool push;
  final bool personalized;
  final bool catchPrivacy;
  final String fontScale;
  final SupportInfo support;

  const SettingsSnapshot({
    this.push = true,
    this.personalized = true,
    this.catchPrivacy = true,
    this.fontScale = 'standard',
    this.support = const SupportInfo(),
  });

  factory SettingsSnapshot.fromJson(Map<String, dynamic> j) => SettingsSnapshot(
        push: j['push'] != false,
        personalized: j['personalized'] != false,
        catchPrivacy: j['catchPrivacy'] != false,
        fontScale: (j['fontScale'] ?? 'standard').toString(),
        support: SupportInfo.fromJson(j['support']),
      );
}
