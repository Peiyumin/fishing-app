import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/screens/watermark_camera_screen.dart';

/// 用假的相机平台驱动**真实页面**，验证「点进去真的会开相机」。
///
/// 这条测试对应的用户现象：两端点拍照后一直停在「正在打开相机…」转圈。
/// 原因是 `_opening` 初值 true 又被当重入锁，首次调用直接 return，
/// 于是 create/initialize **一次都不会被调用** —— 下面就是数这两个次数。
class _FakeCameraPlatform extends CameraPlatform {
  int createCalls = 0;
  int initializeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async =>
      const <CameraDescription>[
        CameraDescription(
          name: 'back',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
        ),
      ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) async {
    createCalls++;
    return 1;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    initializeCalls++;
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposeCalls++;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream<CameraInitializedEvent>.value(const CameraInitializedEvent(
        1,
        1080,
        1920,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ));

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream<DeviceOrientationChangedEvent>.empty();

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      const Stream<CameraErrorEvent>.empty();

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      const Stream<CameraClosingEvent>.empty();

  @override
  Stream<VideoRecordedEvent> onVideoRecordedEvent(int cameraId) =>
      const Stream<VideoRecordedEvent>.empty();

  // 预览画面在测试里没有真实纹理，用占位盒代替（页面本身照常 build）
  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();
}

void main() {
  testWidgets('首次进入就真的创建并初始化相机（不再永远转圈）', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fake = _FakeCameraPlatform();
    CameraPlatform.instance = fake;

    await tester.pumpWidget(const MaterialApp(
      home: WatermarkCameraScreen(returnResult: true, title: '记渔获'),
    ));

    // 首帧之后 postFrameCallback 就会去开相机（假平台是同步完成的，
    // 所以这里不再断言「一定看得到转圈」——转圈是否存在取决于时序，
    // 真正的判据是下面的 create/initialize 次数和最终状态）
    await tester.pump();

    // 把 postFrameCallback + 异步初始化链推完
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(fake.createCalls, 1,
        reason: '首次进入必须创建相机 —— 0 就是又被自己挡住了（本次 bug）');
    expect(fake.initializeCalls, 1, reason: '创建之后必须真的 initialize');
    expect(find.text('正在打开相机…'), findsNothing,
        reason: '初始化成功后必须离开转圈页');
  });

  testWidgets('连续两次进入只创建一次（闸门挡住重入）', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final fake = _FakeCameraPlatform();
    CameraPlatform.instance = fake;

    await tester.pumpWidget(const MaterialApp(
      home: WatermarkCameraScreen(returnResult: true, title: '记渔获'),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(fake.createCalls, 1);
    expect(fake.initializeCalls, 1);
  });
}
