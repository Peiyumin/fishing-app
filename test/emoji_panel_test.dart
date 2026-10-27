import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_app/widgets/emoji_panel.dart';

/// 表情插入工具的行为锁定（v2.1.25）
///
/// 为什么值得单测：插入位置错了表现为「表情插到句尾」或「选中文字没被替换」，
/// 这类问题在真机上靠点很难复现，必须用游标断言锁住。
void main() {
  group('insertAtCursor', () {
    test('空文本：插入到开头', () {
      final c = TextEditingController(text: '');
      insertAtCursor(c, '😀');
      expect(c.text, '😀');
    });

    test('无光标信息时：追加到句尾', () {
      final c = TextEditingController(text: '今天口不错');
      insertAtCursor(c, '🎣');
      expect(c.text, '今天口不错🎣');
    });

    test('光标在中间：插到光标处，后续文字不动', () {
      final c = TextEditingController(text: '鲫鱼条');
      c.selection = const TextSelection.collapsed(offset: 1); // 「鲫」之后
      insertAtCursor(c, '🐟');
      expect(c.text, '鲫🐟鱼条');
      // 光标应停在插入内容之后（按 UTF-16 code unit 计，🐟 占 2）
      expect(c.selection.baseOffset, 3);
    });

    test('有选中区域：替换选中部分', () {
      final c = TextEditingController(text: '今天天气晴');
      c.selection =
          const TextSelection(baseOffset: 2, extentOffset: 4); // 「天气」
      insertAtCursor(c, '⛅');
      expect(c.text, '今天⛅晴');
      expect(c.selection.baseOffset, 3);
    });

    test('连续插入多个表情都按顺序进', () {
      final c = TextEditingController(text: '');
      insertAtCursor(c, '👍');
      insertAtCursor(c, '🎣');
      expect(c.text, '👍🎣');
    });
  });

  group('backspaceAtCursor', () {
    test('删 emoji 是整颗删，不会留下代理对半截（乱码）', () {
      final c = TextEditingController(text: '鱼口好🐟');
      backspaceAtCursor(c);
      expect(c.text, '鱼口好');
    });

    test('删普通中文一次一个', () {
      final c = TextEditingController(text: '鲫鱼');
      backspaceAtCursor(c);
      expect(c.text, '鲫');
    });

    test('空文本不报错', () {
      final c = TextEditingController(text: '');
      backspaceAtCursor(c);
      expect(c.text, '');
    });
  });

  group('EmojiData', () {
    test('每个分组都非空（「最近」由使用记录动态生成，启动时为空属正常）', () {
      for (final t in EmojiData.tabs) {
        if (t.key == '最近') continue;
        expect(t.value.isNotEmpty, true, reason: '${t.key} 分组为空');
      }
      // 常用分组要覆盖高频表情（打招呼/夸赞/钓鱼）
      expect(EmojiData.common, contains('👍'));
      expect(EmojiData.common, contains('🎣'));
      expect(EmojiData.activity, contains('🎣'));
    });
  });

  group('QuickEmojiBar 默认短语', () {
    test('默认 5 个快捷短语（对齐参考图四底部那排）', () {
      expect(QuickEmojiBar.defaultItems.length, 5);
      expect(QuickEmojiBar.defaultItems.map((e) => e.value).toList(),
          ['早上好', '比心', '困', '捂脸', '赞']);
    });
  });
}
