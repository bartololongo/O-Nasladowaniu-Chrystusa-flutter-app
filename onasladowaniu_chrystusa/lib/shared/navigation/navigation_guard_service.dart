typedef NavigationGuardCallback =
    Future<bool> Function(NavigationGuardRequest request);

class NavigationGuardRequest {
  final String confirmLabel;

  const NavigationGuardRequest({required this.confirmLabel});
}

class NavigationGuardService {
  NavigationGuardService._();

  static final NavigationGuardService instance = NavigationGuardService._();

  Object? _owner;
  NavigationGuardCallback? _callback;

  bool get hasGuard => _callback != null;

  void setGuard(Object owner, NavigationGuardCallback callback) {
    _owner = owner;
    _callback = callback;
  }

  void clearGuard(Object owner) {
    if (_owner != owner) return;

    _owner = null;
    _callback = null;
  }

  Future<bool> confirmNavigation(NavigationGuardRequest request) async {
    final callback = _callback;
    if (callback == null) return true;

    return callback(request);
  }
}
