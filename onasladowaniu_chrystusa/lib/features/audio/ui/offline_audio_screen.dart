import 'package:flutter/material.dart';

import '../../../shared/services/book_repository.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/audio_catalog.dart';
import '../data/audio_track.dart';
import '../services/app_audio_player_service.dart';
import '../services/audio_download_service.dart';

class OfflineAudioScreen extends StatefulWidget {
  const OfflineAudioScreen({super.key});

  @override
  State<OfflineAudioScreen> createState() => _OfflineAudioScreenState();
}

class _OfflineAudioScreenState extends State<OfflineAudioScreen> {
  final AudioDownloadService _downloadService = const AudioDownloadService();
  final AppAudioPlayerService _audioService = AppAudioPlayerService.instance;
  final BookRepository _bookRepository = BookRepository();

  late Future<List<AudioDownloadedTrackInfo>> _downloadsFuture;
  final Set<String> _deletingTrackIds = <String>{};
  bool _isDeletingAll = false;

  @override
  void initState() {
    super.initState();
    _downloadsFuture = _loadDownloads();
  }

  Future<List<AudioDownloadedTrackInfo>> _loadDownloads() async {
    final tracks = await _loadKnownTracks();
    return _downloadService.listDownloads(tracks);
  }

  Future<List<AudioTrack>> _loadKnownTracks() async {
    final collection = await _bookRepository.getCollection();
    final tracks = <AudioTrack>[];

    for (final book in collection.books) {
      for (final chapter in book.chapters) {
        final track = AudioCatalog.trackForChapter(
          chapterReference: chapter.reference,
          title: chapter.title,
          subtitle: book.title,
        );
        if (track != null) {
          tracks.add(track);
        }
      }
    }

    return tracks;
  }

  void _refreshDownloads() {
    if (!mounted) return;

    setState(() {
      _downloadsFuture = _loadDownloads();
    });
  }

  bool _isCurrentTrack(AudioTrack track) {
    return _audioService.currentTrack?.id == track.id;
  }

  Future<void> _deleteDownload(AudioDownloadedTrackInfo info) async {
    final messenger = ScaffoldMessenger.of(context);

    if (_isCurrentTrack(info.track)) {
      _showSnackBar(
        messenger,
        'Nie można usunąć nagrania, które jest teraz odtwarzane.',
      );
      return;
    }

    final confirmed = await _confirmDelete(
      title: 'Usunąć pobrane nagranie?',
      message: 'Nagranie będzie ponownie odtwarzane z internetu.',
      confirmLabel: 'Usuń',
    );
    if (!mounted || !confirmed) return;

    setState(() {
      _deletingTrackIds.add(info.track.id);
    });

    try {
      await _downloadService.deleteDownload(info.track);
      if (!mounted) return;

      _refreshDownloads();
      _showSnackBar(messenger, 'Pobrane nagranie zostało usunięte.');
    } catch (_) {
      if (!mounted) return;

      _showSnackBar(messenger, 'Nie udało się usunąć nagrania.');
    } finally {
      if (mounted) {
        setState(() {
          _deletingTrackIds.remove(info.track.id);
        });
      }
    }
  }

  Future<void> _deleteAllDownloads(
    List<AudioDownloadedTrackInfo> downloads,
  ) async {
    final messenger = ScaffoldMessenger.of(context);

    if (downloads.any((info) => _isCurrentTrack(info.track))) {
      _showSnackBar(
        messenger,
        'Nie można usunąć wszystkich nagrań, gdy jedno z nich jest odtwarzane.',
      );
      return;
    }

    final confirmed = await _confirmDelete(
      title: 'Usunąć wszystkie pobrane nagrania?',
      message: 'Rozdziały audio będą ponownie odtwarzane z internetu.',
      confirmLabel: 'Usuń wszystkie',
    );
    if (!mounted || !confirmed) return;

    setState(() {
      _isDeletingAll = true;
    });

    try {
      await _downloadService.deleteAllDownloads(
        downloads.map((info) => info.track),
      );
      if (!mounted) return;

      _refreshDownloads();
      _showSnackBar(messenger, 'Wyczyszczono pobrane nagrania.');
    } catch (_) {
      if (!mounted) return;

      _showSnackBar(messenger, 'Nie udało się usunąć pobranych nagrań.');
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAll = false;
        });
      }
    }
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Anuluj'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  void _showSnackBar(ScaffoldMessengerState messenger, String message) {
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SectionHeader(
              title: 'Nagrania offline',
              subtitle: 'Pobrane rozdziały dostępne bez internetu.',
              icon: Icons.download_done_rounded,
              showBackButton: Navigator.canPop(context),
            ),
            Expanded(
              child: FutureBuilder<List<AudioDownloadedTrackInfo>>(
                future: _downloadsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _OfflineMessage(
                      icon: Icons.error_outline_rounded,
                      title: 'Nie udało się odczytać pobranych nagrań.',
                      subtitle: 'Spróbuj ponownie za chwilę.',
                      action: TextButton.icon(
                        onPressed: _refreshDownloads,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Odśwież'),
                      ),
                    );
                  }

                  final downloads =
                      snapshot.data ?? const <AudioDownloadedTrackInfo>[];
                  if (downloads.isEmpty) {
                    return const _OfflineMessage(
                      icon: Icons.cloud_off_rounded,
                      title: 'Nie masz jeszcze pobranych nagrań.',
                      subtitle:
                          'Pobieranie rozdziału znajdziesz w pełnym odtwarzaczu.',
                    );
                  }

                  return _buildDownloadsList(context, downloads);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadsList(
    BuildContext context,
    List<AudioDownloadedTrackInfo> downloads,
  ) {
    final totalBytes = downloads.fold<int>(
      0,
      (sum, info) => sum + info.sizeBytes,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      children: [
        _DownloadsSummaryCard(
          count: downloads.length,
          totalSize: _formatBytes(totalBytes),
          isDeletingAll: _isDeletingAll,
          onDeleteAll: _isDeletingAll
              ? null
              : () => _deleteAllDownloads(downloads),
        ),
        const SizedBox(height: 12),
        for (final info in downloads) ...[
          _DownloadedTrackTile(
            info: info,
            sizeLabel: _formatBytes(info.sizeBytes),
            downloadedAtLabel: _formatDate(info.downloadedAt),
            isCurrentTrack: _isCurrentTrack(info.track),
            isDeleting:
                _isDeletingAll || _deletingTrackIds.contains(info.track.id),
            onDelete: () => _deleteDownload(info),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';

    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';

    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  String? _formatDate(DateTime? value) {
    if (value == null) return null;

    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day.$month.${local.year}';
  }
}

class _DownloadsSummaryCard extends StatelessWidget {
  final int count;
  final String totalSize;
  final bool isDeletingAll;
  final VoidCallback? onDeleteAll;

  const _DownloadsSummaryCard({
    required this.count,
    required this.totalSize,
    required this.isDeletingAll,
    required this.onDeleteAll,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Pobrane nagrania',
                  value: '$count',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetric(
                  label: 'Zajęte miejsce',
                  value: totalSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onDeleteAll,
            icon: isDeletingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_rounded),
            label: const Text('Usuń wszystkie pobrane'),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.68),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DownloadedTrackTile extends StatelessWidget {
  final AudioDownloadedTrackInfo info;
  final String sizeLabel;
  final String? downloadedAtLabel;
  final bool isCurrentTrack;
  final bool isDeleting;
  final VoidCallback onDelete;

  const _DownloadedTrackTile({
    required this.info,
    required this.sizeLabel,
    required this.downloadedAtLabel,
    required this.isCurrentTrack,
    required this.isDeleting,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final downloadedMeta = downloadedAtLabel == null
        ? sizeLabel
        : '$sizeLabel · Pobrano: $downloadedAtLabel';
    final subtitleParts = <String>[
      '${info.track.subtitle} · Rozdział ${info.track.chapterNumber}',
      downloadedMeta,
      if (isCurrentTrack) 'Teraz odtwarzane',
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        leading: Icon(Icons.audio_file_rounded, color: colorScheme.primary),
        title: Text(info.track.title),
        subtitle: Text(subtitleParts.join('\n')),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Usuń pobrane nagranie',
          onPressed: isDeleting ? null : onDelete,
          icon: isDeleting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_outline_rounded),
        ),
      ),
    );
  }
}

class _OfflineMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _OfflineMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
