import 'package:flutter/material.dart';

import '../../../shared/navigation/navigation_guard_service.dart';
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
  final Object _navigationGuardOwner = Object();

  late Future<_OfflineDownloadsData> _downloadsFuture;
  final Set<String> _deletingTrackIds = <String>{};
  bool _isDeletingAll = false;
  bool _isDownloadingAll = false;
  bool _isCancellingDownload = false;
  bool _isShowingLeaveConfirmation = false;
  int _downloadCompleted = 0;
  int _downloadTotal = 0;
  AudioDownloadCancelToken? _downloadCancelToken;

  @override
  void initState() {
    super.initState();
    _downloadsFuture = _loadDownloads();
  }

  Future<_OfflineDownloadsData> _loadDownloads() async {
    final tracks = await _loadKnownTracks();
    final downloads = await _downloadService.listDownloads(tracks);
    return _OfflineDownloadsData(tracks: tracks, downloads: downloads);
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

  @override
  void dispose() {
    _downloadCancelToken?.cancel();
    _clearNavigationGuard();
    super.dispose();
  }

  void _setNavigationGuard() {
    NavigationGuardService.instance.setGuard(
      _navigationGuardOwner,
      _confirmGuardedNavigation,
    );
  }

  void _clearNavigationGuard() {
    NavigationGuardService.instance.clearGuard(_navigationGuardOwner);
  }

  Future<bool> _confirmGuardedNavigation(NavigationGuardRequest request) async {
    return _confirmLeaveDuringDownload(confirmLabel: request.confirmLabel);
  }

  Future<void> _deleteDownload(AudioDownloadedTrackInfo info) async {
    final messenger = ScaffoldMessenger.of(context);

    if (_isDownloadingAll) return;

    if (_isCurrentTrack(info.track)) {
      _showSnackBar(
        messenger,
        'Nie można usunąć nagrania, które jest teraz odtwarzane.',
      );
      return;
    }

    final confirmed = await _confirmAction(
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

    if (_isDownloadingAll) return;

    if (downloads.any((info) => _isCurrentTrack(info.track))) {
      _showSnackBar(
        messenger,
        'Nie można usunąć wszystkich nagrań, gdy jedno z nich jest odtwarzane.',
      );
      return;
    }

    final confirmed = await _confirmAction(
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

  Future<void> _downloadAllMissing(List<AudioTrack> tracks) async {
    final messenger = ScaffoldMessenger.of(context);

    if (_isDownloadingAll) return;

    final missingTracks = await _downloadService.missingDownloads(tracks);
    if (!mounted) return;

    if (missingTracks.isEmpty) {
      _showSnackBar(messenger, 'Wszystkie nagrania są już pobrane.');
      return;
    }

    final confirmed = await _confirmAction(
      title: 'Pobrać wszystkie nagrania?',
      message:
          'Nagrania zostaną zapisane na urządzeniu i będą dostępne offline.\n\n'
          'To może potrwać chwilę i zużyć transfer danych.',
      confirmLabel: 'Pobierz',
    );
    if (!mounted || !confirmed) return;

    setState(() {
      _isDownloadingAll = true;
      _isCancellingDownload = false;
      _downloadCompleted = 0;
      _downloadTotal = missingTracks.length;
      _downloadCancelToken = AudioDownloadCancelToken();
    });
    _setNavigationGuard();

    try {
      final result = await _downloadService.downloadMissingTracks(
        missingTracks,
        cancelToken: _downloadCancelToken,
        onProgress: (completed, total, _) {
          if (!mounted) return;

          setState(() {
            _downloadCompleted = completed;
            _downloadTotal = total;
          });
        },
      );
      if (!mounted) return;

      _refreshDownloads();

      if (result.cancelled) {
        _showSnackBar(
          messenger,
          'Pobieranie przerwane. Pobrano ${result.downloadedCount} nagrań.',
        );
      } else if (result.requestedCount == 0) {
        _showSnackBar(messenger, 'Wszystkie nagrania są już pobrane.');
      } else if (result.failedCount == 0) {
        _showSnackBar(messenger, 'Pobrano wszystkie nagrania.');
      } else {
        _showSnackBar(
          messenger,
          'Pobrano ${result.downloadedCount} nagrań. '
          'Nie udało się pobrać ${result.failedCount}.',
        );
      }
    } catch (_) {
      if (!mounted) return;

      _showSnackBar(messenger, 'Nie udało się rozpocząć pobierania nagrań.');
    } finally {
      if (mounted) {
        _clearNavigationGuard();
        setState(() {
          _isDownloadingAll = false;
          _isCancellingDownload = false;
          _downloadCancelToken = null;
        });
      }
    }
  }

  void _cancelBulkDownload() {
    if (!_isDownloadingAll || _isCancellingDownload) return;

    setState(() {
      _isCancellingDownload = true;
    });
    _downloadCancelToken?.cancel();
  }

  Future<void> _handleBackDuringDownload() async {
    if (!_isDownloadingAll) {
      Navigator.of(context).maybePop();
      return;
    }

    final shouldLeave = await _confirmLeaveDuringDownload(
      confirmLabel: 'Przerwij i wyjdź',
    );
    if (!mounted || !shouldLeave) return;

    await Navigator.of(context).maybePop();
  }

  Future<bool> _confirmLeaveDuringDownload({
    required String confirmLabel,
  }) async {
    if (!_isDownloadingAll) return true;
    if (_isShowingLeaveConfirmation) return false;

    setState(() {
      _isShowingLeaveConfirmation = true;
    });

    final shouldLeave = await _confirmAction(
      title: 'Trwa pobieranie nagrań',
      message:
          'Jeśli teraz wyjdziesz, pobieranie zostanie przerwane. '
          'Pobrane już nagrania zostaną zachowane.',
      cancelLabel: 'Zostań',
      confirmLabel: confirmLabel,
    );
    if (!mounted) return false;

    setState(() {
      _isShowingLeaveConfirmation = false;
    });

    if (!shouldLeave) return false;

    _downloadCancelToken?.cancel();
    setState(() {
      _isCancellingDownload = true;
    });
    return true;
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String cancelLabel = 'Anuluj',
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
                        child: Text(cancelLabel),
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
    return PopScope(
      canPop: !_isDownloadingAll,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackDuringDownload();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SectionHeader(
                title: 'Nagrania offline',
                subtitle: 'Pobrane rozdziały dostępne bez internetu.',
                icon: Icons.download_done_rounded,
                showBackButton: Navigator.canPop(context),
                onBack: _handleBackDuringDownload,
              ),
              Expanded(
                child: FutureBuilder<_OfflineDownloadsData>(
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

                    final data = snapshot.data ?? const _OfflineDownloadsData();
                    return _buildDownloadsList(context, data);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadsList(BuildContext context, _OfflineDownloadsData data) {
    final downloads = data.downloads;
    final allDownloaded =
        data.tracks.isNotEmpty && downloads.length >= data.tracks.length;
    final canDownloadAll =
        data.tracks.isNotEmpty &&
        !allDownloaded &&
        !_isDownloadingAll &&
        !_isDeletingAll;
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
          isDownloadingAll: _isDownloadingAll,
          isCancellingDownload: _isCancellingDownload,
          downloadCompleted: _downloadCompleted,
          downloadTotal: _downloadTotal,
          onCancelDownload: _isDownloadingAll && !_isCancellingDownload
              ? _cancelBulkDownload
              : null,
          onDownloadAll: canDownloadAll
              ? () => _downloadAllMissing(data.tracks)
              : null,
          isDeletingAll: _isDeletingAll,
          onDeleteAll: downloads.isEmpty || _isDeletingAll
              ? null
              : () => _deleteAllDownloads(downloads),
        ),
        const SizedBox(height: 12),
        if (downloads.isEmpty)
          const _OfflineMessage(
            icon: Icons.cloud_off_rounded,
            title: 'Nie masz jeszcze pobranych nagrań.',
            subtitle:
                'Możesz pobrać wszystkie rozdziały albo pojedyncze nagranie z pełnego odtwarzacza.',
          )
        else
          for (final info in downloads) ...[
            _DownloadedTrackTile(
              info: info,
              sizeLabel: _formatBytes(info.sizeBytes),
              downloadedAtLabel: _formatDate(info.downloadedAt),
              isCurrentTrack: _isCurrentTrack(info.track),
              isDeleting:
                  _isDeletingAll ||
                  _isDownloadingAll ||
                  _deletingTrackIds.contains(info.track.id),
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

class _OfflineDownloadsData {
  final List<AudioTrack> tracks;
  final List<AudioDownloadedTrackInfo> downloads;

  const _OfflineDownloadsData({
    this.tracks = const <AudioTrack>[],
    this.downloads = const <AudioDownloadedTrackInfo>[],
  });
}

class _DownloadsSummaryCard extends StatelessWidget {
  final int count;
  final String totalSize;
  final bool isDownloadingAll;
  final bool isCancellingDownload;
  final int downloadCompleted;
  final int downloadTotal;
  final VoidCallback? onCancelDownload;
  final VoidCallback? onDownloadAll;
  final bool isDeletingAll;
  final VoidCallback? onDeleteAll;

  const _DownloadsSummaryCard({
    required this.count,
    required this.totalSize,
    required this.isDownloadingAll,
    required this.isCancellingDownload,
    required this.downloadCompleted,
    required this.downloadTotal,
    required this.onCancelDownload,
    required this.onDownloadAll,
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
          FilledButton.icon(
            onPressed: onDownloadAll,
            icon: isDownloadingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(
              isDownloadingAll
                  ? isCancellingDownload
                        ? 'Anulowanie...'
                        : 'Pobieranie $downloadCompleted z $downloadTotal'
                  : 'Pobierz wszystkie',
            ),
          ),
          if (isDownloadingAll && downloadTotal > 0) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: downloadCompleted / downloadTotal),
          ],
          if (isDownloadingAll) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onCancelDownload,
              icon: const Icon(Icons.close_rounded),
              label: Text(isCancellingDownload ? 'Anulowanie...' : 'Anuluj'),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: isDownloadingAll ? null : onDeleteAll,
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
