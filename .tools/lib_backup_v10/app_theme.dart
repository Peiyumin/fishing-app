import 'package:flutter/material.dart';

/// 全局设计系统：湖光 · 青绿（专业级视觉规范）
///
/// 设计语言：
///  - 主色采用「深湖绿」，辅助色采用「水蓝」，二者同属冷色水系，和谐统一；
///  - 暖金（星标）作为唯一暖色点缀，制造焦点对比；
///  - 卡片以 18px 大圆角 + 1px 细边框取代生硬阴影，干净通透；
///  - 统一的字阶、间距与语义色，配合中文字体回退，整体精致现代。
class AppTheme {
  // ───────────────────────── 品牌主色 ─────────────────────────
  /// 主色：深湖绿（导航、按钮、强调）
  static const Color primary = Color(0xFF0F7A53);
  static const Color primaryDark = Color(0xFF0A5C3C);
  static const Color primaryLight = Color(0xFFE3F1EA);
  /// 极浅绿灰（占位背景、轻表面）
  static const Color primarySoft = Color(0xFFF0F6F3);
  /// 主色描边（虚线框、图标描边）
  static const Color primaryBorder = Color(0xFFC9DED5);

  /// 辅助色：水蓝（天气、链接、次级强调）
  static const Color accent = Color(0xFF0E91A8);
  static const Color accentDark = Color(0xFF0B7488);
  static const Color accentLight = Color(0xFFE0F3F6);

  // ───────────────────────── 语义 / 点缀色 ─────────────────────────
  /// 星标 / 评分：暖金（唯一暖色，制造焦点）
  static const Color star = Color(0xFFF2A93B);
  static const Color starLight = Color(0xFFFCEFDB);
  /// 危险 / 删除 / 红标
  static const Color danger = Color(0xFFE5484D);
  static const Color dangerDark = Color(0xFFB71C1C);
  static const Color dangerLight = Color(0xFFFCE8E9);
  /// 警示 / 橙标
  static const Color warning = Color(0xFFE8973A);
  static const Color warningLight = Color(0xFFFBEEDD);
  /// 紫（说说 / 技巧类）
  static const Color violet = Color(0xFF7C6CD4);
  static const Color violetLight = Color(0xFFEDEAFE);
  /// 靛（渔具店）
  static const Color indigo = Color(0xFF5A6BCF);
  static const Color indigoLight = Color(0xFFE9ECF8);
  /// 深橙（野钓点）
  static const Color deepOrange = Color(0xFFF0763E);
  static const Color deepOrangeLight = Color(0xFFFDEBE1);

  // ───────────────────────── 表面 / 文字 / 线条 ─────────────────────────
  /// 页面背景（带极淡绿调的干净灰白）
  static const Color background = Color(0xFFF4F7F5);
  /// 卡片 / 浮层表面
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF16241E);
  static const Color textSecondary = Color(0xFF5A6B62);
  static const Color divider = Color(0xFFE9EEEA);
  static const Color border = Color(0xFFE1E8E3);

  // ───────────────────────── 形状 / 间距 / 字阶 ─────────────────────────
  static const double radiusLg = 18;
  static const double radiusMd = 14;
  static const double radiusSm = 10;
  static const double radiusPill = 999;

  static const double sp1 = 4;
  static const double sp2 = 8;
  static const double sp3 = 12;
  static const double sp4 = 16;
  static const double sp5 = 20;
  static const double sp6 = 24;
  static const double sp8 = 32;

  static const double fsCaption = 12;
  static const double fsBody = 14;
  static const double fsTitle = 16;
  static const double fsHeadline = 18;
  static const double fsDisplay = 22;

  // ───────────────────────── 渐变 ─────────────────────────
  /// 顶部导航 / Hero 标题栏渐变（深→浅湖绿）
  static const Gradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryDark, primary],
  );
  /// 品牌强调渐变（湖绿→水蓝）
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accent],
  );
  /// 水蓝渐变（链接 / 强调按钮）
  static const Gradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDark],
  );

  /// 柔和阴影（取代硬 elevation，卡片/浮层通用）
  static List<BoxShadow> get softShadow => const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 14,
          offset: Offset(0, 5),
        ),
      ];

  /// 更轻的阴影（小浮层 / 横向卡片）
  static List<BoxShadow> get lightShadow => const [
        BoxShadow(
          color: Color(0x0D000000),
          blurRadius: 8,
          offset: Offset(0, 3),
        ),
      ];

  /// 中文优先字体回退栈（设备自带，无需打包字体资源）
  static List<String> get cjkFallback => const [
        'PingFang SC',
        'Hiragino Sans GB',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'Noto Sans SC',
      ];

  /// 类别语义色（与发布中心、信息流标签、钓点筛选统一）
  static Color categoryColor(String cat) {
    switch (cat) {
      case 'ask':
        return accent;
      case 'say':
        return violet;
      case 'sell':
        return danger;
      case 'buy':
        return warning;
      case 'venue':
        return primaryDark;
      case 'shop':
        return indigo;
      case 'wild':
        return deepOrange;
      default:
        return primary;
    }
  }

  /// 类别浅色底（标签 / 图标容器底色）
  static Color categorySoft(String cat) {
    switch (cat) {
      case 'ask':
        return accentLight;
      case 'say':
        return violetLight;
      case 'sell':
        return dangerLight;
      case 'buy':
        return warningLight;
      case 'venue':
        return primaryLight;
      case 'shop':
        return indigoLight;
      case 'wild':
        return deepOrangeLight;
      default:
        return primaryLight;
    }
  }

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    fontFamilyFallback: cjkFallback,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: accentLight,
      onSecondaryContainer: accentDark,
      surface: surface,
      onSurface: textPrimary,
      outline: divider,
      error: danger,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: const TextStyle(
        fontSize: fsHeadline,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: divider, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: fsBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontSize: fsCaption,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: primary,
      unselectedItemColor: Colors.grey,
      selectedLabelStyle:
          TextStyle(fontSize: fsCaption, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: fsCaption),
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(
      color: divider,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      // 未选中：中性浅底 + 次要文字；选中：品牌浅绿 + 主色加粗 + 勾选
      backgroundColor: const Color(0xFFF2F5F3),
      selectedColor: primaryLight,
      labelStyle: const TextStyle(color: textSecondary, fontSize: fsCaption),
      secondaryLabelStyle: const TextStyle(
        color: primary,
        fontSize: fsCaption,
        fontWeight: FontWeight.w600,
      ),
      checkmarkColor: primary,
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
  );
}
