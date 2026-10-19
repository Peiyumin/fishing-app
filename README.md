# 垂钓圈 · Flutter 双端 App

一款面向钓鱼爱好者的垂钓社区 App：底部五导航（首页 / 发现 / 发布 / 钓点 / 我的）、首页四段式布局（搜索 + 宫格导航 + 钓鱼天气 + 钓点 + 实时动态流）、发布渔获（标题 + 图片 + 定位）、点赞评论。

- 框架：**Flutter**（一套代码打包 Android / iOS）
- 后端：**Supabase**（账号、数据库、图片存储、实时数据）
- 地图：**OpenStreetMap** 瓦片（免 Key）
- 天气：**Open-Meteo** 免费接口（免 Key）
- 配色：户外绿 `#2E7D32` + 水蓝 `#0288D1`

---

## 一、环境准备（只需一次）

```bash
# 1. 安装 Flutter SDK（≥ 3.3），并配置环境变量
#    官网：https://docs.flutter.dev/get-started/install

# 2. 校验环境（Android Studio / Xcode 按需安装）
flutter doctor
```

- **Android**：装 [Android Studio](https://developer.android.com/studio)，在 SDK Manager 勾选「Android SDK Command-line Tools」。
- **iOS**：需要 macOS + 安装 [Xcode](https://developer.apple.com/xcode/)，并执行 `sudo gem install cocoapods`。

---

## 二、初始化项目（生成原生工程）

本项目已包含 `pubspec.yaml` 与 `lib/`。在目录内生成 Android / iOS 原生脚手架：

```bash
cd fishing_app
flutter create --org com.example.fishing .   # 生成 android/ 与 ios/
flutter pub get                              # 拉取依赖
```

---

## 二·五、原生权限配置（务必添加，否则定位/相册/相机不可用）

- **Android** — 编辑 `android/app/src/main/AndroidManifest.xml`，在 `<manifest>` 内、`<application>` 前添加：
  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" /> <!-- Android 13+ -->
  <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
      android:maxSdkVersion="32" />
  <uses-permission android:name="android.permission.CAMERA" />
  ```
- **iOS** — 编辑 `ios/Runner/Info.plist`，在 `<dict>` 内添加：
  ```xml
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>用于显示附近钓点与发布定位</string>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>用于发布渔获时选择图片</string>
  <key>NSCameraUsageDescription</key>
  <string>用于拍照发布渔获</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  ```

---

## 三、配置 Supabase（后端）

1. 打开 https://supabase.com 新建项目。
2. 进入 **SQL Editor**，把本仓库 `supabase/schema.sql` 全选执行（建表 + 权限 + 计数函数 + 存储桶）。
3. 进入 **Project Settings → API**，复制 `Project URL` 与 `anon public key`。
4. 打开 `lib/services/supabase_config.dart`，替换：
   ```dart
   static const String url = 'https://YOUR-PROJECT.supabase.co';
   static const String anonKey = 'YOUR-ANON-KEY';
   ```
5. 进入 **Storage**，确认 `post-images` 桶已创建且为 **Public**。

> 不接后端也能跑界面：把 `HomeScreen` 里的 `PostService.fetchFeed` 临时换成内置示例数据即可预览 UI（见 V1 演示说明）。

---

## 四、运行

```bash
flutter run          # 连上手机/模拟器后运行
flutter run -d chrome # 或跑 Web 预览
```

---

## 五、打包

### Android · 生成 APK
```bash
# 1. 生成签名密钥（仅首次）
keytool -genkey -v -keystore ~/fishing.keystore \
  -keyalg RSA -keysize 2048 -validity 10000 -alias fishing

# 2. 在 android/key.properties 填写（勿提交到公开仓库）：
#    storePassword=你的密码
#    keyPassword=你的密码
#    keyAlias=fishing
#    storeFile=/绝对路径/fishing.keystore

# 3. 在 android/app/build.gradle 的 android{ } 内配置 signingConfigs（见下方示例）

# 4. 打包
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
# 直接传到安卓手机安装即可（无需上架）
```

`android/app/build.gradle` 关键片段：
```gradle
android {
    ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release { signingConfig signingConfigs.release }
    }
}
```

### iOS · 生成 IPA
```bash
# 需 macOS + Xcode + 苹果开发者账号
flutter build ios --release
# 用 Xcode 打开 ios/Runner.xcworkspace
# 选中真机 → Product → Archive → 校验后「Distribute App」
# 内测：选 TestFlight；正式：选 App Store（需上架审核）
```

> ⚠️ iOS 限制：未越狱设备必须经由 **TestFlight / App Store** 才能安装，无法像安卓直接装 APK。本专家只做本地打包指引，不做商店上架与资质审核。

---

## 六、高频报错排查

| 报错 | 原因 / 解决 |
|---|---|
| `cmdline-tools not found` | 未装 Android SDK Command-line Tools，在 SDK Manager 勾选安装 |
| `CocoaPods not installed` | iOS：`sudo gem install cocoapods` 后 `cd ios && pod install` |
| `Gradle build failed` | 先 `flutter clean` 再 `flutter pub get` 重编 |
| `keystore` 密码错误 | 检查 `key.properties` 与密钥库一致性 |
| `Provisioning profile` 不匹配 | Xcode 中重新选择 Team / 证书 |
| 地图空白 | 检查网络是否能访问 openstreetmap.org 瓦片 |
| 天气拉取失败 | 检查网络；Open-Meteo 无需 Key，但需联网 |

---

## 七、目录结构

```
fishing_app/
├── lib/
│   ├── main.dart                 # 入口 + 底部五导航（中间发布按钮）
│   ├── app_theme.dart            # 户外绿/水蓝主题
│   ├── models/                   # post、fishing_spot 数据模型
│   ├── services/                 # supabase_config / session / post / weather / spot
│   ├── widgets/                  # post_card / grid_nav / weather_card / spot_card
│   └── screens/                  # home / discover / publish / spots / profile / post_detail / search / auth
├── supabase/schema.sql           # 建表 + 权限 + 计数函数 + 存储桶
└── pubspec.yaml
```

> V1 已跑通「刷得到、发得出、点得了赞」。V2 计划：关注/私信、天气预警推送、钓点收藏评分；V3：装备商城、钓鱼赛事。
