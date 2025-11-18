import 'package:flutter/material.dart';
import 'features/reader/reader_screen.dart';

class ImitationOfChristApp extends StatelessWidget {
  const ImitationOfChristApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'O naśladowaniu Chrystusa',
      themeMode: ThemeMode.dark,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
      ),
      home: const ReaderScreen(), // <-- startujemy od czytnika
      debugShowCheckedModeBanner: false,
    );
  }
}
