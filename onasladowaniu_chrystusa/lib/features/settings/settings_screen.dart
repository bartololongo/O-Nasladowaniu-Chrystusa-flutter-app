import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.text_fields),
            title: Text('Czcionka czytania'),
            subtitle: Text('Ustawienia rozmiaru i stylu czcionki'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.dark_mode),
            title: Text('Motyw aplikacji'),
            subtitle: Text('Jasny, ciemny lub systemowy'),
          ),
          Divider(),
          ListTile(
            leading: Icon(Icons.system_update),
            title: Text('Uaktualnienia'),
            subtitle: Text('Sprawdź informacje o wersji aplikacji'),
          ),
        ],
      ),
    );
  }
}
