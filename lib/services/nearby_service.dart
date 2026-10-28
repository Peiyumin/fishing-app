import '../models/nearby_angler.dart';
import 'api_client.dart';
import '../utils/json_num.dart';

/// 附近钓友（所有登录用户可用）
class NearbyService {
  /// 附近钓友列表（由近到远）
  static Future<List<NearbyAngler>> anglers({
    required double lat,
    required double lng,
  }) async {
    final data = jsonList(await ApiClient.get('/nearby/anglers', {
      'lat': '$lat',
      'lng': '$lng',
    }));
    return data
        .map((e) => NearbyAngler.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 上报定位（顺带设置是否公开位置）
  static Future<void> reportLocation(double lat, double lng,
      {bool? public}) async {
    await ApiClient.post('/nearby/location', {
      'lat': '$lat',
      'lng': '$lng',
      if (public != null) 'public': public,
    });
  }
}
