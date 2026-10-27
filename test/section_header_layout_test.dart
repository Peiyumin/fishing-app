import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_app/widgets/section_header.dart';

void main() {
  testWidgets('SectionHeader 动作链接应贴最右（有副标题时也一样）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: Column(
            children: [
              SectionHeader(
                title: '禹州 · 实时天气',
                actionLabel: '7天预报',
                onAction: () {},
              ),
              SectionHeader(
                title: '附近钓点',
                subtitle: '由近到远',
                actionLabel: '更多',
                onAction: () {},
              ),
            ],
          ),
        ),
      ),
    ));

    final box1 = tester.getRect(find.byIcon(Icons.chevron_right).first);
    final box2 = tester.getRect(find.byIcon(Icons.chevron_right).last);
    debugPrint('7天预报箭头 right=${box1.right}');
    debugPrint('更多箭头 right=${box2.right}');
    // 动作组（文字+箭头）右缘应贴近容器右缘（390 - padding 16 = 374）
    expect(box1.right, greaterThan(374 - 6));
    expect(box2.right, greaterThan(374 - 6));
    // 两者必须同一位置（有/无副标题不影响对齐）
    expect((box2.right - box1.right).abs(), lessThan(0.5));
  });
}
