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
        children: [
          const ListTile(
            leading: Icon(Icons.text_fields),
            title: Text('Czcionka czytania'),
            subtitle: Text('Ustawienia rozmiaru i stylu czcionki'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.system_update),
            title: Text('Uaktualnienia'),
            subtitle: Text('Sprawdź informacje o wersji aplikacji'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('O aplikacji'),
            subtitle: const Text('Informacje, autor, licencja'),
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: false,
                builder: (sheetContext) {
                  final colorScheme = Theme.of(sheetContext).colorScheme;

                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.menu_book,
                                size: 32,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'O naśladowaniu Chrystusa',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Wersja 1.0.0',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Aplikacja do czytania klasycznego dzieła '
                            '„O naśladowaniu Chrystusa” z możliwością '
                            'notowania, zapisywania ulubionych cytatów '
                            'i prowadzenia dziennika duchowego.',
                            style: TextStyle(fontSize: 14, height: 1.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Autor: Bartek (projekt prywatny)',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  colorScheme.onSurface.withOpacity(0.8),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tekst książki: domena publiczna / zgodnie z prawami autorskimi zastosowanego '
                            'tłumaczenia.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color:
                                  colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(),
                              child: const Text('Zamknij'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
