import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/bookmarks/bookmarks_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/favorites/favorites_screen.dart';


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
    // Ostatni przycisk ("Więcej") otwiera bottom sheet,
    // nie zmieniamy wtedy wybranego taba.
    if (index == 3) {
      _showMoreSheet();
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showMoreSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Dziennik duchowy'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => JournalScreen(
                        onNavigateToTab: _onTabSelected, // 👈 KLUCZOWA ZMIANA
                      ),
                    ),
                  );
                },
              ),

              ListTile(
                leading: const Icon(Icons.format_quote),
                title: const Text('Ulubione cytaty'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FavoritesScreen(
                        onNavigateToTab: _onTabSelected,
                      ),
                    ),
                  );
                },
              ),              
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Ustawienia'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return HomeScreen(onNavigateToTab: _onTabSelected);
      case 1:
        return const ReaderScreen();
      case 2:
        return BookmarksScreen(onNavigateToTab: _onTabSelected);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
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
            icon: Icon(Icons.bookmark),
            label: 'Zakładki',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'Więcej',
          ),
        ],
      ),
    );
  }
}
