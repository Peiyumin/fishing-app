// 渔报表情护栏
//
// 每个新增 / 改动表情都要满足这几条，否则「发出去是一条评论、别人看着是一串
// 中括号代码」这种事故就会重新出现：
//   ① 素材文件存在，且是带透明通道的 PNG（不能有底色）
//   ② 写进评论正文的是「[中文]」，老版本 / 网页后台也能读懂
//   ③ 纯表情评论 = 单独一张大图；和文字混排 = 行内小图
//   ④ 全角/半角问号都要认得（手机中文输入法常给半角）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/widgets/catch_sticker.dart';

void main() {
  group('① 素材', () {
    test('四个表情的素材文件都打进包了', () {
      for (final s in kCatchStickers) {
        final f = File(s.asset);
        expect(f.existsSync(), isTrue, reason: '缺素材 ${s.asset}');
        expect(f.lengthSync(), greaterThan(2000), reason: '${s.asset} 太小，可能是空图');
      }
    });

    test('素材是 PNG，且头 26 字节里声明了 RGBA（透明通道）', () {
      for (final s in kCatchStickers) {
        final head = File(s.asset).readAsBytesSync().take(33).toList();
        // PNG 魔数
        expect(head.sublist(0, 8),
            [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
            reason: '${s.asset} 不是 PNG');
        // IHDR 里 bit depth(24) + color type(25)：6 = RGBA
        expect(head[25], 6, reason: '${s.asset} 不是 RGBA，去底没生效');
      }
    });

    test('id / label 不重复', () {
      expect(kCatchStickers.map((e) => e.id).toSet().length,
          kCatchStickers.length);
      expect(kCatchStickers.map((e) => e.label).toSet().length,
          kCatchStickers.length);
    });
  });

  group('② token', () {
    test('token 是中括号包中文，不是私有代码', () {
      for (final s in kCatchStickers) {
        expect(s.token, '[${s.label}]');
        expect(s.token.contains(r'$'), isFalse);
        expect(s.token.length, greaterThan(3));
      }
    });
  });

  group('③ 解析', () {
    test('纯表情评论 → single 命中', () {
      final s = StickerCodec.single('[好鱼！]');
      expect(s, isNotNull);
      expect(s!.id, 'haoyu');
    });

    test('前后带空格也算纯表情', () {
      expect(StickerCodec.single('  [爆护了] ')?.id, 'baohu');
    });

    test('表情 + 文字 → single 为 null（走混排）', () {
      expect(StickerCodec.single('[好鱼！]这条真肥'), isNull);
      expect(StickerCodec.has('[好鱼！]这条真肥'), isTrue);
    });

    test('半角问号也认', () {
      expect(StickerCodec.single('[这么大?]')?.id, 'zhemeda');
      expect(StickerCodec.single('[这么大？]')?.id, 'zhemeda');
    });

    test('半角感叹号也认', () {
      expect(StickerCodec.single('[好鱼!]')?.id, 'haoyu');
    });

    test('普通评论不受影响', () {
      expect(StickerCodec.has('今天风太大了，一条没有'), isFalse);
      expect(StickerCodec.single(''), isNull);
      expect(StickerCodec.spans('普通文字', size: 20).length, 1);
    });

    test('未知中括号原样保留，不吃字', () {
      expect(StickerCodec.has('[这不是表情]'), isFalse);
      final spans = StickerCodec.spans('[这不是表情]', size: 20);
      expect(spans.length, 1);
    });

    test('一条评论里两个表情都能拆出来', () {
      final spans = StickerCodec.spans('前面[好鱼！]中间[爆护了]后面', size: 20);
      // 文字 + 表情 + 文字 + 表情 + 文字
      expect(spans.length, 5);
    });
  });
}
