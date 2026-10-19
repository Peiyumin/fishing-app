import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// 动态视频播放器：未播放时显示播放按钮（黑底），
/// 首次点击才初始化并播放，避免信息流里多个视频同时加载耗流量
class PostVideoPlayer extends StatefulWidget {
  final String url;
  final double height;

  const PostVideoPlayer({
    super.key,
    required this.url,
    this.height = 240,
  });

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _error = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final c = _controller;
    if (c != null) {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        c.play();
      }
      setState(() {});
      return;
    }
    if (_initializing) return;
    setState(() => _initializing = true);
    try {
      final nc = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await nc.initialize();
      if (!mounted) {
        nc.dispose();
        return;
      }
      nc.setLooping(true);
      setState(() => _controller = nc);
      await nc.play();
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: Colors.black,
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 视频画面（初始化后才有）
            if (_controller != null)
              SizedBox(
                width: double.infinity,
                height: widget.height,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller!,
                      builder: (_, v, __) => VideoPlayer(_controller!),
                    ),
                  ),
                ),
              ),
            // 中央播放/暂停按钮
            if (!_error)
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: _initializing
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                        )
                      : (_controller == null
                          ? const Icon(Icons.play_arrow,
                              color: Colors.white, size: 32)
                          : ValueListenableBuilder<VideoPlayerValue>(
                              valueListenable: _controller!,
                              builder: (_, v, __) => Icon(
                                v.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 32,
                              ),
                            )),
                ),
              ),
            // 加载失败提示
            if (_error)
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, color: Colors.white70, size: 30),
                  SizedBox(height: 6),
                  Text('视频加载失败',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            // 左上角视频标识
            if (!_error)
              const Positioned(
                left: 8,
                top: 8,
                child: Row(
                  children: [
                    Icon(Icons.videocam, size: 14, color: Colors.white70),
                    SizedBox(width: 3),
                    Text('视频',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
