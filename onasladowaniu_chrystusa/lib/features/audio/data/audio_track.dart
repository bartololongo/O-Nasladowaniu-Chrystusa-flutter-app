class AudioTrack {
  final String id;
  final int bookNumber;
  final int chapterNumber;
  final String title;
  final String subtitle;
  final String url;
  final Duration? duration;

  const AudioTrack({
    required this.id,
    required this.bookNumber,
    required this.chapterNumber,
    required this.title,
    required this.subtitle,
    required this.url,
    this.duration,
  });
}
