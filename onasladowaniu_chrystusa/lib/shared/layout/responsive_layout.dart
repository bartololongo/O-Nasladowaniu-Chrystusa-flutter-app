import 'package:flutter/material.dart';

const double kCompactAndroidBreakpoint = 350;

extension ResponsiveLayout on BuildContext {
  bool get isCompactAndroid {
    return Theme.of(this).platform == TargetPlatform.android &&
        MediaQuery.sizeOf(this).width <= kCompactAndroidBreakpoint;
  }

  double get compactLayoutScale {
    if (!isCompactAndroid) return 1;

    return (MediaQuery.sizeOf(this).width / 393).clamp(0.84, 0.9).toDouble();
  }

  double layoutValue(double regular, {double? compact}) {
    if (!isCompactAndroid) return regular;

    return compact ?? regular * compactLayoutScale;
  }

  EdgeInsets compactInsets({
    required double horizontal,
    required double vertical,
    double? compactHorizontal,
    double? compactVertical,
  }) {
    return EdgeInsets.symmetric(
      horizontal: layoutValue(horizontal, compact: compactHorizontal),
      vertical: layoutValue(vertical, compact: compactVertical),
    );
  }
}
