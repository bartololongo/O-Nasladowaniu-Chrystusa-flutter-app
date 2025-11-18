import 'package:flutter/material.dart';
import 'package:onasladowaniu_chrystusa/shared/models/book_models.dart';
import 'package:onasladowaniu_chrystusa/shared/services/book_repository.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final BookRepository _bookRepository = BookRepository();

  double _fontSize = 18.0;
  double _lineHeight = 1.5;
  bool _isJustified = true;

  late Future<BookChapter> _chapterFuture;

  @override
  void initState() {
    super.initState();
    _chapterFuture = _bookRepository.getFirstChapter();
  }

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
          Expanded(
            child: FutureBuilder<BookChapter>(
              future: _chapterFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Błąd wczytywania rozdziału:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: Text('Brak danych rozdziału'));
                }

                final chapter = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTitle(chapter),
                    const SizedBox(height: 8),
                    _buildReader(chapter),
                  ],
                );
              },
            ),
          ),
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

  Widget _buildTitle(BookChapter chapter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          chapter.title,
          style: TextStyle(
            fontSize: _fontSize + 2,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildReader(BookChapter chapter) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final paragraph in chapter.paragraphs) ...[
              Text(
                paragraph.text,
                textAlign: _isJustified ? TextAlign.justify : TextAlign.left,
                style: TextStyle(
                  fontSize: _fontSize,
                  height: _lineHeight,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
