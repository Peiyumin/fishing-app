import '../models/wallet.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 钱包
class WalletService {
  static Future<WalletInfo> info() async {
    final data = await ApiClient.get('/wallet') as Map;
    return WalletInfo.fromJson(data.cast<String, dynamic>());
  }

  static Future<List<WalletLog>> logs({int page = 1}) async {
    final data = await ApiClient.get('/wallet/logs', {'page': '$page'}) as List;
    return data
        .map((e) => WalletLog.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  static Future<List<ChargePlan>> chargePlans() async {
    if (!ApiConfig.enabled) return const [];
    try {
      final data = await ApiClient.get('/wallet/charge-plans') as List;
      return data
          .map((e) => ChargePlan.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 创建充值单（后台确认后到账）
  static Future<ChargeOrder> charge(String planId) async {
    final data = await ApiClient.post('/wallet/charge', {'planId': planId}) as Map;
    return ChargeOrder.fromJson(data.cast<String, dynamic>());
  }

  static Future<List<ChargeOrder>> chargeOrders() async {
    final data = await ApiClient.get('/wallet/charge-orders') as List;
    return data
        .map((e) => ChargeOrder.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
