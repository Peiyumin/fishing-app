/// 重入闸门（一次性进入、用完释放）。
///
/// 存在的原因是一个真实事故：相机页原来用「加载中」的 bool 当重入锁，
/// 而那个 bool 的初值是 true —— 于是**第一次**打开就被自己挡回去，
/// 界面永远停在「正在打开相机…」，两端都一样。
///
/// 所以这里把「占用状态」独立出来，并把初始状态钉死为**空闲**：
/// 一个新建的闸门必须允许第一次进入，否则它本身就是 bug。
///
/// 用法：
/// ```dart
/// final _gate = OpenGate();
/// ...
/// if (!_gate.tryEnter()) return;   // 正在开，别重入
/// try {
///   ...
/// } finally {
///   _gate.leave();                 // 任何 return / 异常都必须释放
/// }
/// ```
class OpenGate {
  bool _occupied = false;

  /// 当前是否已被占用（正在执行）
  bool get busy => _occupied;

  /// 尝试进入。第一次调用必然成功；已占用时返回 false。
  bool tryEnter() {
    if (_occupied) return false;
    _occupied = true;
    return true;
  }

  /// 释放。重复调用无害。
  void leave() {
    _occupied = false;
  }
}
