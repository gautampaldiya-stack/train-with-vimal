import 'package:flutter/foundation.dart';

/// A ChangeNotifier that stays quiet once disposed. A page's controller is often still loading when the page goes
/// away (a quick tab change, Back), and its late notifyListeners() threw "used after being disposed" in debug runs
/// (Probid's phone, 18 Nov).
class SafeNotifier extends ChangeNotifier {
  bool _gone = false;

  /// True once [dispose] ran.
  bool get isDisposed => _gone;

  @override
  void notifyListeners() {
    if (!_gone) super.notifyListeners();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }
}
