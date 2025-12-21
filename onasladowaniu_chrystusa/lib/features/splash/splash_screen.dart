import 'dart:async';

import 'package:flutter/material.dart';

/// Ekran startowy aplikacji "O naśladowaniu Chrystusa".
///
/// Pokazuje pełnoekranowy obrazek PNG (assets/splash/splash.png),
/// z lekkim fade-in. Opcjonalnie może wywołać [onFinished] po krótkim
/// czasie, jeśli chcesz automatycznie przejść np. do HomeScreen.
class SplashScreen extends StatefulWidget {
  final VoidCallback? onFinished;

  const SplashScreen({
    Key? key,
    this.onFinished,
  }) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _controller.forward();

    // Jeśli podasz onFinished przy tworzeniu SplashScreen,
    // po ~1,5 s nastąpi automatyczne przejście dalej.
    if (widget.onFinished != null) {
      _finishTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        widget.onFinished!.call();
      });
    }
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ten kolor warto zgrać z `flutter_native_splash` (color: "#0f0b08")
    const backgroundColor = Color(0xFF0F0B08);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: Image.asset(
              'assets/splash/splash.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
        ],
      ),
    );
  }
}
