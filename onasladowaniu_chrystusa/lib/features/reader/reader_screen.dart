import 'package:flutter/material.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  double _fontSize = 18.0;
  double _lineHeight = 1.5;
  bool _isJustified = true;

  // Mockowy tytuł rozdziału
  final String _mockTitle = 'Księga I — Rozdział 1 (mock)';

  // Mockowy tekst — placeholder, żeby tylko zobaczyć zachowanie UI
  static const String _mockText = '''
Kto pragnie ćwiczyć się w czytaniu duchowym, dobrze robi, jeśli szuka spokojnego miejsca i chwili ciszy.

Ten przykładowy tekst jest tylko wypełniaczem, żeby zobaczyć działanie przewijania, zmiany czcionki i formatowania. Właściwy tekst książki będzie pobierany z pliku JSON, gdy tylko będziemy mieli gotowy model danych i załatwione prawa do tłumaczenia.

Czytanie powoli, uważnie i z sercem pomaga bardziej niż szybkie przelatywanie wzrokiem. Dlatego warto mieć możliwość dopasowania rozmiaru czcionki do własnych oczu i warunków oświetlenia.

Można też wypróbować różne ustawienia odstępów między wierszami, tak aby tekst był jak najbardziej czytelny i nie męczył wzroku podczas dłuższej lektury.

To tylko kilka akapitów przykładowego tekstu. W prawdziwej wersji w tym miejscu pojawią się treści książki „O naśladowaniu Chrystusa”, podzielone na księgi, rozdziały i akapity, z możliwością dodawania zakładek, ulubionych cytatów i notatek.
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Czytanie'),
      ),
      body: Column(
        children: [
          _buildControls(),
          const Divider(height: 1),
          _buildTitle(),
          const SizedBox(height: 8),
          _buildReader(),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize - 2).clamp(12.0, 30.0);
              });
            },
            icon: const Icon(Icons.remove),
            tooltip: 'Mniejsza czcionka',
          ),
          Expanded(
            child: Slider(
              value: _fontSize,
              min: 12,
              max: 30,
              label: '${_fontSize.toStringAsFixed(0)}',
              onChanged: (value) {
                setState(() {
                  _fontSize = value;
                });
              },
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize + 2).clamp(12.0, 30.0);
              });
            },
            icon: const Icon(Icons.add),
            tooltip: 'Większa czcionka',
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              setState(() {
                _isJustified = !_isJustified;
              });
            },
            icon: Icon(
              _isJustified ? Icons.format_align_justify : Icons.format_align_left,
            ),
            tooltip: _isJustified ? 'Wyrównaj do lewej' : 'Wyjustuj tekst',
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _mockTitle,
          style: TextStyle(
            fontSize: _fontSize + 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildReader() {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Text(
          _mockText,
          textAlign: _isJustified ? TextAlign.justify : TextAlign.left,
          style: TextStyle(
            fontSize: _fontSize,
            height: _lineHeight,
          ),
        ),
      ),
    );
  }
}
