import 'package:flutter/material.dart';

import '../services/location_service.dart';
import 'center_toast.dart';

/// 定位失败提示：权限被拒 → 弹窗引导去系统设置；其他原因 → 居中 toast
class LocationPrompt {
  static void showError(BuildContext context, LocationException e) {
    if (e.type == LocationErrorType.permissionDenied) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('需要定位权限'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('暂不'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                LocationService.openSettings();
              },
              child: const Text('去设置'),
            ),
          ],
        ),
      );
    } else {
      CenterToast.show(context, e.message, icon: Icons.location_off_outlined);
    }
  }
}
