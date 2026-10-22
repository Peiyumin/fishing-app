import '../models/nearby_angler.dart';
import 'api_client.dart';

/// 附近钓友（会员专属）
class NearbyService {
  /// 附近钓友列表（由近到远）
  static Future<List<NearbyAngler>> anglers({
    required double lat,
    required double lng,
  }) async {
    final data = await ApiClient.get('/nearby/anglers', {
      'lat': '$lat',
      'lng': '$lng',
    }) as List;
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
