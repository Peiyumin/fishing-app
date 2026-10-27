import '../models/user_address.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 设置页相关的后端接口（v35）
///
/// 对接 api/index.php：
///   GET  /settings          读取偏好（+ 客服信息）
///   POST /settings          保存偏好
///   POST /settings/consent  同意 / 撤回隐私授权
///   GET  /settings/support  客服信息（免登录）
///   GET  /addresses         收货地址列表
///   POST /addresses         新增 / 编辑（带 id 即编辑），返回最新列表
///   POST /addresses/{id}/delete   删除
///   POST /addresses/{id}/default  设为默认
///   GET  /legal/{key}       协议文本
///   POST /account/cancel    注销账号
///
/// 未配置后端（演示模式）时全部走本地默认值，页面照常可用。
class SettingsService {
  static bool get _enabled => ApiConfig.enabled;

  /// 读取偏好；未登录 / 演示模式返回默认值
  static Future<SettingsSnapshot> fetch() async {
    if (!_enabled || ApiClient.token == null) return const SettingsSnapshot();
    try {
      final data = await ApiClient.get('/settings');
      if (data is Map) {
        return SettingsSnapshot.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {
      // 老后端没有 /settings：用默认值，页面不报错
    }
    return const SettingsSnapshot();
  }

  /// 保存偏好（只传要改的字段）
  static Future<void> save({
    bool? push,
    bool? personalized,
    bool? catchPrivacy,
    String? fontScale,
  }) async {
    if (!_enabled || ApiClient.token == null) return;
    await ApiClient.post('/settings', {
      if (push != null) 'push': push,
      if (personalized != null) 'personalized': personalized,
      if (catchPrivacy != null) 'catchPrivacy': catchPrivacy,
      if (fontScale != null) 'fontScale': fontScale,
    });
  }

  /// 同意（agree=true）/ 撤回（agree=false）隐私授权
  static Future<void> consent(bool agree) async {
    if (!_enabled || ApiClient.token == null) return;
    await ApiClient.post('/settings/consent', {'agree': agree});
  }

  /// 客服信息（免登录可查）
  static Future<SupportInfo> support() async {
    if (!_enabled) return const SupportInfo();
    try {
      final data = await ApiClient.get('/settings/support');
      return SupportInfo.fromJson(data);
    } catch (_) {
      return const SupportInfo();
    }
  }

  // ---------------- 收货地址 ----------------

  static Future<List<UserAddress>> addresses() async {
    if (!_enabled || ApiClient.token == null) return const [];
    final data = await ApiClient.get('/addresses');
    return _parseList(data);
  }

  static Future<List<UserAddress>> saveAddress({
    String? id,
    required String name,
    required String phone,
    String region = '',
    required String detail,
    bool isDefault = false,
  }) async {
    if (!_enabled || ApiClient.token == null) {
      throw Exception('未连接服务器，无法保存地址');
    }
    final data = await ApiClient.post('/addresses', {
      if (id != null && id.isNotEmpty) 'id': id,
      'name': name,
      'phone': phone,
      'region': region,
      'detail': detail,
      'isDefault': isDefault,
    });
    return _parseList(data);
  }

  static Future<List<UserAddress>> deleteAddress(String id) async {
    if (!_enabled || ApiClient.token == null) return const [];
    final data = await ApiClient.post('/addresses/$id/delete', {});
    return _parseList(data);
  }

  static Future<List<UserAddress>> setDefaultAddress(String id) async {
    if (!_enabled || ApiClient.token == null) return const [];
    final data = await ApiClient.post('/addresses/$id/default', {});
    return _parseList(data);
  }

  static List<UserAddress> _parseList(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => UserAddress.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ---------------- 协议文本 ----------------

  static Future<LegalDoc> legal(String key) async {
    if (_enabled) {
      try {
        final data = await ApiClient.get('/legal/$key');
        if (data is Map) {
          return LegalDoc.fromJson(Map<String, dynamic>.from(data));
        }
      } catch (_) {
        // 落到内置文本
      }
    }
    return fallbackLegal(key);
  }

  /// 内置兜底文本（后端未升级 / 离线时也能看）
  static LegalDoc fallbackLegal(String key) {
    const titles = {
      'terms': '用户协议',
      'privacy': '隐私政策',
      'collect': '个人信息收集与使用清单',
      'third': '第三方信息共享清单',
      'permission': '个人信息与权限',
    };
    const body = '（内容加载中）\n\n'
        '文档正文由服务器下发。若长时间空白，请检查网络后重试，'
        '或联系客服获取最新版本。\n\n'
        '客服电话 400-000-0000 · 微信 yubao_kefu';
    return LegalDoc(
      key: key,
      title: titles[key] ?? '说明',
      content: body,
    );
  }

  // ---------------- 注销账号 ----------------

  static Future<void> cancelAccount() async {
    if (!_enabled) throw Exception('演示模式不支持注销');
    await ApiClient.post('/account/cancel', {});
  }
}
