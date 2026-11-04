import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// v2.1.72 钓点搜索修复
///
/// 问题：批量导入 148 条钓点之后，用「黑坑」「野钓」这种**类型词**搜不到东西。
/// 根因在后端 —— 关键词只匹配 名称 / 简介 / 地址，而库里 49 条 type=黑坑、
/// 105 条 type=野钓。前端还有两个「帮倒忙」的地方：
///   ① 推荐词写的是「长江」，而库里一条长江都没有 → 点一下就是空结果；
///   ② 搜索失败时回落到演示数据（千岛湖/青山湖），用户以为库里就那些。
///
/// 后端断言在 v40_official_test.php（PHP 侧），这里守前端这两条。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('推荐词必须有数据', () {
    test('推荐词是类型词，不再是「长江」这种库里没有的词', () {
      final src = read('lib/screens/search_screen.dart');
      expect(src.contains("_suggests = ['野钓', '黑坑', '水库', '钓场']"), isTrue);
      // 只看字符串字面量：注释里提到这两个词是为了说明原因，不算
      expect(src.contains("'长江'"), isFalse,
          reason: '「长江」在本库 0 条，点了就是空结果');
      expect(src.contains("'垂钓技巧'"), isFalse);
    });

    test('空结果提示告诉用户能按类型搜', () {
      final src = read('lib/screens/search_screen.dart');
      expect(src.contains('类型（野钓、黑坑）'), isTrue);
    });
  });

  group('搜索失败不能拿演示数据冒充', () {
    test('带关键词失败时返回空列表', () {
      final src = read('lib/services/spot_service.dart');
      expect(src.contains('if (keyword.isNotEmpty) return const <FishingSpot>[]'),
          isTrue);
      // 不能再出现「catch 之后按名字过滤演示数据」的老写法
      expect(src.contains('all = all.where((s) => s.name.contains(keyword)).toList();'),
          isFalse);
    });
  });
}
