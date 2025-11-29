import 'package:flutter/widgets.dart';

/// Globalny RouteObserver, którego używamy m.in. w HomeScreen,
/// żeby wiedzieć, kiedy wracamy z innych ekranów (Settings, Backup itp.).
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
