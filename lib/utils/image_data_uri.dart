import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// 把本地图片解码并按宽度缩放到 [maxWidth]，输出 PNG base64 data URI。
///
/// 用途：发布渔获前的「AI 视觉核验」要把首图传给后端 /fish/recognize，
/// 后端该接口已支持 data: URI（无需先走上传流程）。直接发原图 base64 太大，
/// 缩到 ~448px 既够识别又只产生 ~200KB 的请求体。
Future<String> fileToScaledDataUri(File file, {int maxWidth = 448}) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  try {
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bd == null) throw Exception('无法编码图片');
    final Uint8List png = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
    return 'data:image/png;base64,${base64Encode(png)}';
  } finally {
    img.dispose();
  }
}
