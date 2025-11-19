import 'package:flutter/material.dart';

class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dziennik duchowy'),
      ),
      body: const Center(
        child: Text(
          'Tutaj powstanie dziennik duchowy.\nNa razie to tylko placeholder :)',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
