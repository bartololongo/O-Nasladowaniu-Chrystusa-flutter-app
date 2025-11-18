import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('O naśladowaniu Chrystusa'),
      ),
      body: const Center(
        child: Text('Tu będzie: Kontynuuj czytanie + Wyzwanie'),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (_) {
          // na razie nic, później ogarniemy nawigację
        },
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
            icon: Icon(Icons.edit),
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
