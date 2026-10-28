import '../models/wallet.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// 钱包
class WalletService {
  static Future<WalletInfo> info() async {
    final data = jsonMap(await ApiClient.get('/wallet'));
    return WalletInfo.fromJson(data.cast<String, dynamic>());
  }

  static Future<List<WalletLog>> logs({int page = 1}) async {
    final data = jsonList(await ApiClient.get('/wallet/logs', {'page': '$page'}));
    return data
        .map((e) => WalletLog.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  static Future<List<ChargePlan>> chargePlans() async {
    if (!ApiConfig.enabled) return const [];
    try {
      final data = jsonList(await ApiClient.get('/wallet/charge-plans'));
      return data
          .map((e) => ChargePlan.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 创建充值单（后台确认后到账）
  static Future<ChargeOrder> charge(String planId) async {
    final data = jsonMap(await ApiClient.post('/wallet/charge', {'planId': planId}));
    return ChargeOrder.fromJson(data.cast<String, dynamic>());
  }

  static Future<List<ChargeOrder>> chargeOrders() async {
    final data = jsonList(await ApiClient.get('/wallet/charge-orders'));
    return data
        .map((e) => ChargeOrder.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
