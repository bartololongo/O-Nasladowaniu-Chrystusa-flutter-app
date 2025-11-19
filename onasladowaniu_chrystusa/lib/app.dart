import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/settings/settings_screen.dart';

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
        appBarTheme: const AppBarTheme(
          centerTitle: false,
        ),
      ),
      home: const _RootScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen({super.key});

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> {
  int _selectedIndex = 0;

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tab index:
    // 0 - Start (Home)
    // 1 - Czytanie
    // 2 - Dziennik
    // 3 - Ustawienia

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          HomeScreen(onNavigateToTab: _onTabSelected),
          const ReaderScreen(),
          const JournalScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabSelected,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Start',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Czytanie',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_note),
            label: 'Dziennik',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Ustawienia',
          ),
        ],
      ),
    );
  }
}
