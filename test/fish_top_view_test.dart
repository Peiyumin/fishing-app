import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/widgets/fish_top_view.dart';

/// 鱼形护栏：这几条数字决定「像不像鱼」，改了就报警
///
/// 背景：池塘是航拍俯视，鱼只能程序化画。第一版画成「鱼 + 老鼠结合体」
/// （有眼睛/胸鳍椭圆/燕尾鳍条/圆管立体），第二版又成「落叶/香蕉」。
/// 现在这套轮廓是照真实俯视照片量出来的，锁死在这里防止回退。
void main() {
  test('尾柄必须很细（不然尾巴挂不住、整条鱼成叶子）', () {
    expect(FishTopView.topWidth(0), lessThan(.12));
  });

  test('最宽处落在中前段（u .55~.68），不是正中间', () {
    var maxW = -1.0;
    var maxU = 0.0;
    for (var i = 0; i <= 100; i++) {
      final u = i / 100;
      final w = FishTopView.topWidth(u);
      if (w > maxW) {
        maxW = w;
        maxU = u;
      }
    }
    expect(maxW, closeTo(1.0, .01));
    expect(maxU, inInclusiveRange(.55, .68),
        reason: '最宽处落在正中就成了对称柳叶，鱼味全无');
  });

  test('吻端比尾柄宽、比身体窄很多（圆钝的窄吻）', () {
    expect(FishTopView.topWidth(1), lessThan(.05));
    expect(FishTopView.topWidth(.90), lessThan(.6));
    expect(FishTopView.topWidth(.90), greaterThan(FishTopView.topWidth(0)));
  });

  test('轮廓单调：中段之后一路收窄，不能有鼓包', () {
    var prev = FishTopView.topWidth(.6);
    for (var i = 61; i <= 100; i++) {
      final w = FishTopView.topWidth(i / 100);
      expect(w, lessThanOrEqualTo(prev + 1e-9),
          reason: 'u=${i / 100} 处比前面宽，头就鼓包了');
      prev = w;
    }
  });

  test('体色压暗并往水色偏：不能把素材的白底亮色直接搬进池塘', () {
    const base = Color(0xFFF2E4C8); // 素材那种偏白的背色
    final c = FishTopView.shade(base, 0, .6, .5);
    expect(c.red, lessThan(120), reason: '太亮就会像浮在水面的亮纸');
    expect(c.blue, lessThan(c.green), reason: '水吸收红光，水下应是冷调');

    final edge = FishTopView.shade(base, 1.2, .6, .5);
    expect(edge.alpha, lessThan(30), reason: '|t|=1.2 是羽化外缘，必须几乎透明');
  });
}
