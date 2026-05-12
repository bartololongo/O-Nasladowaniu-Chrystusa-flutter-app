import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import 'features/home/home_screen.dart';
import 'features/reading/reading_hub_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/formation_challenge/formation_challenge_screen.dart';
import 'features/search/search_screen.dart';
import 'shared/navigation/app_page_route.dart';
import 'shared/navigation/main_tabs.dart';
import 'shared/navigation/navigation_guard_service.dart';
import 'shared/services/app_update_service.dart';
import 'shared/services/content_update_service.dart';
import 'shared/services/formation_notification_service.dart';
import 'shared/services/formation_widget_snapshot_service.dart';
import 'app_route_observer.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ImitationOfChristApp extends StatelessWidget {
  final String? initialNotificationPayload;

  const ImitationOfChristApp({super.key, this.initialNotificationPayload});

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0F0B08);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'O naśladowaniu Chrystusa',
      themeMode: ThemeMode.dark,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: backgroundColor,
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: backgroundColor,
          selectedItemColor: colorScheme.secondary,
          unselectedItemColor: colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: backgroundColor,
        ),
      ),
      home: _RootScreen(initialNotificationPayload: initialNotificationPayload),
      debugShowCheckedModeBanner: false,
      // RouteObserver podpinamy do wewnętrznego Navigatora, nie tutaj.
    );
  }
}

class _RootScreen extends StatefulWidget {
  final String? initialNotificationPayload;

  const _RootScreen({this.initialNotificationPayload});

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> with WidgetsBindingObserver {
  /// Bazowa zakładka (Start / Droga / Książka / Dziennik / Ustawienia).
  int _baseTabIndex = MainTabs.start;

  /// Aktualnie podświetlana zakładka w BottomNavigationBar.
  int _selectedIndex = MainTabs.start;

  /// ID instancji Readera.
  final int _readerInstanceId = 0;
  final ValueNotifier<int> _pendingReaderRequestSignal = ValueNotifier<int>(0);
  String? _activeMoreRouteName;
  bool _isContextualSettingsOpen = false;

  /// Wewnętrzny Navigator, w którym renderujemy:
  /// - ekrany z bottom nav (Start, Droga, Książka, Dziennik, Ustawienia),
  /// - oraz dodatkowe ekrany: Dziennik, Ulubione, Ustawienia itp.
  ///
  /// Dzięki temu dolny pasek jest zawsze widoczny.
  final GlobalKey<NavigatorState> _innerNavigatorKey =
      GlobalKey<NavigatorState>();
  StreamSubscription<String>? _notificationSubscription;
  StreamSubscription<Uri?>? _widgetClickSubscription;
  String? _pendingNotificationPayload;
  bool _isOpeningFormationFromNotification = false;
  bool _hasCheckedContentUpdateOnLaunch = false;
  bool _hasCheckedAppUpdateOnLaunch = false;
  bool _isShowingAppUpdatePrompt = false;
  bool _isShowingContentUpdatePrompt = false;
  final AppUpdateService _appUpdateService = AppUpdateService();
  final ContentUpdateService _contentUpdateService = ContentUpdateService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationSubscription = FormationNotificationService
        .instance
        .payloadStream
        .listen(_handleNotificationPayload);
    _widgetClickSubscription = HomeWidget.widgetClicked.listen(
      _handleWidgetUri,
    );

    final initialPayload = widget.initialNotificationPayload;
    if (initialPayload != null && initialPayload.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationPayload(initialPayload);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingNotificationPayload('initState');
      _checkInitialWidgetUri();
      unawaited(_checkLaunchUpdates());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    _widgetClickSubscription?.cancel();
    _pendingReaderRequestSignal.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingNotificationPayload('resumed');
    });
  }

  Future<void> _checkPendingNotificationPayload(String source) async {
    if (!mounted) return;

    final pendingPayload = await FormationNotificationService.instance
        .takePendingPayload();
    if (!mounted) return;

    if (pendingPayload != null && pendingPayload.isNotEmpty) {
      _handleNotificationPayload(pendingPayload);
    }
  }

  Future<void> _checkInitialWidgetUri() async {
    try {
      await FormationWidgetSnapshotService.configureAppGroup();
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (!mounted) return;
      _handleWidgetUri(uri);
    } catch (_) {
      // Widget launch handling should not block app startup.
    }
  }

  Future<void> _checkContentUpdateOnLaunch() async {
    if (_hasCheckedContentUpdateOnLaunch) return;
    _hasCheckedContentUpdateOnLaunch = true;

    final availability = await _contentUpdateService.checkAvailability();
    if (!mounted) return;

    if (!availability.isAvailable || availability.isDismissed) {
      return;
    }

    final remoteVersion = availability.remoteVersion;
    if (remoteVersion == null || remoteVersion.isEmpty) {
      return;
    }

    if (_isShowingContentUpdatePrompt) return;
    _isShowingContentUpdatePrompt = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _ContentUpdatePromptSheet(
          remoteVersion: remoteVersion,
          contentUpdateService: _contentUpdateService,
        );
      },
    );

    if (!mounted) return;
    _isShowingContentUpdatePrompt = false;
  }

  Future<void> _checkLaunchUpdates() async {
    await _checkAppUpdateOnLaunch();
    if (!mounted) return;
    await _checkContentUpdateOnLaunch();
  }

  Future<void> _checkAppUpdateOnLaunch() async {
    if (_hasCheckedAppUpdateOnLaunch) return;
    _hasCheckedAppUpdateOnLaunch = true;

    final availability = await _appUpdateService.checkAvailability();
    if (!mounted) return;

    if (!availability.isAvailable || availability.isDismissed) {
      return;
    }

    final remoteVersion = availability.remoteVersion;
    if (remoteVersion == null || remoteVersion.isEmpty) {
      return;
    }

    if (_isShowingAppUpdatePrompt || _isShowingContentUpdatePrompt) return;
    _isShowingAppUpdatePrompt = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _AppUpdatePromptSheet(
          remoteVersion: remoteVersion,
          storeUrl: availability.storeUrl,
          appUpdateService: _appUpdateService,
        );
      },
    );

    if (!mounted) return;
    _isShowingAppUpdatePrompt = false;
  }

  void _handleWidgetUri(Uri? uri) {
    if (!FormationWidgetSnapshotService.isFormationWidgetUri(uri)) {
      return;
    }
    _handleNotificationPayload(FormationWidgetSnapshotService.widgetPayload);
  }

  void _handleNotificationPayload(String payload) {
    if (!_isFormationOpenPayload(payload)) {
      return;
    }

    _pendingNotificationPayload = payload;
    _openPendingNotificationPayload();
  }

  bool _isFormationOpenPayload(String? payload) {
    return payload == FormationNotificationService.formationPayload ||
        payload == FormationWidgetSnapshotService.widgetPayload;
  }

  void _openPendingNotificationPayload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final payload = _pendingNotificationPayload;
      if (!_isFormationOpenPayload(payload)) {
        return;
      }

      if (_isOpeningFormationFromNotification) {
        return;
      }

      final navigator = _innerNavigatorKey.currentState;
      if (navigator == null) {
        _openPendingNotificationPayload();
        return;
      }

      _isOpeningFormationFromNotification = true;
      _pendingNotificationPayload = null;

      setState(() {
        _selectedIndex = _baseTabIndex;
      });

      if (payload == FormationNotificationService.formationPayload) {
        unawaited(FormationNotificationService.instance.clearPendingPayload());
      }
      navigator
          .push(
            AppPageRoute.fade(
              settings: const RouteSettings(name: '/formation-challenge'),
              builder: (_) =>
                  FormationChallengeScreen(onNavigateToTab: _onTabSelected),
            ),
          )
          .whenComplete(() {
            _isOpeningFormationFromNotification = false;
          });
    });
  }

  void _onTabSelected(int index) {
    unawaited(_handleTabSelected(index));
  }

  Future<void> _handleTabSelected(int index) async {
    if (NavigationGuardService.instance.hasGuard) {
      final canNavigate = await NavigationGuardService.instance
          .confirmNavigation(
            const NavigationGuardRequest(confirmLabel: 'Przerwij i przejdź'),
          );
      if (!mounted || !canNavigate) return;
    }

    final nav = _innerNavigatorKey.currentState;
    final atRoot = !(nav?.canPop() ?? false);

    if (index == MainTabs.settings && _shouldOpenContextualSettings(atRoot)) {
      _openContextualSettings();
      return;
    }

    if (index == MainTabs.settings && _isContextualSettingsOpen) {
      return;
    }

    // Jeśli jesteśmy już na bazowym ekranie tego taba,
    // nic nie rób – unikamy ponownej animacji/pushowania.
    if (index == _baseTabIndex && atRoot) {
      setState(() {
        _selectedIndex = index; // dla porządku, choć i tak już jest
      });
      return;
    }

    setState(() {
      _activeMoreRouteName = null;
      _isContextualSettingsOpen = false;
      _baseTabIndex = index;
      _selectedIndex = index;
    });

    // Resetujemy stos wewnętrznego Navigatora do bazowego ekranu taba.
    nav?.popUntil((route) => route.isFirst);
  }

  bool _shouldOpenContextualSettings(bool atRoot) {
    if (_isContextualSettingsOpen) return false;
    if (_baseTabIndex == MainTabs.settings) return false;

    return _baseTabIndex != MainTabs.start || !atRoot;
  }

  void _openContextualSettings() {
    final navigator = _innerNavigatorKey.currentState;
    if (navigator == null) return;

    setState(() {
      _activeMoreRouteName = null;
      _isContextualSettingsOpen = true;
      _selectedIndex = MainTabs.settings;
    });

    navigator
        .push(
          AppPageRoute.fade(
            settings: const RouteSettings(name: '/settings/contextual-tab'),
            builder: (_) => SettingsScreen(
              showBackButton: true,
              onBack: _closeContextualSettings,
            ),
          ),
        )
        .whenComplete(() {
          if (!mounted) return;
          if (!_isContextualSettingsOpen) return;

          setState(() {
            _isContextualSettingsOpen = false;
            _selectedIndex = _baseTabIndex;
          });
        });
  }

  void _closeContextualSettings() {
    _innerNavigatorKey.currentState?.maybePop();
  }

  /// Otwiera ekran z sekcji "Więcej" (Dziennik/Ulubione/Ustawienia).
  /// Zachowuje podświetlenie bazowej zakładki (_baseTabIndex).
  void _openMoreScreen(Widget screen) {
    final routeName = _moreRouteNameFor(screen);
    final navigator = _innerNavigatorKey.currentState;
    if (navigator == null) return;

    if (_activeMoreRouteName == routeName) {
      if (routeName == '/settings') {
        navigator.popUntil((route) => route.settings.name == routeName);
      }
      return;
    }

    final replaceActiveMoreScreen = _activeMoreRouteName != null;

    setState(() {
      _activeMoreRouteName = routeName;
    });

    final route = AppPageRoute.fade(
      settings: RouteSettings(name: routeName),
      builder: (_) => screen,
    );
    final navigationFuture = replaceActiveMoreScreen
        ? navigator.pushReplacement(route)
        : navigator.push(route);

    navigationFuture.then((_) {
      if (!mounted) return;
      // Po powrocie z ekranu "Więcej" przywracamy podświetlenie bazowej zakładki.
      setState(() {
        if (_activeMoreRouteName == routeName) {
          _activeMoreRouteName = null;
          _selectedIndex = _baseTabIndex;
        }
      });
    });
  }

  String _moreRouteNameFor(Widget screen) {
    if (screen is JournalScreen) return '/journal';
    if (screen is FavoritesScreen) return '/favorites';
    if (screen is SettingsScreen) return '/settings';

    return '/more/${screen.runtimeType}';
  }

  /// Używane przez HomeScreen (szybkie akcje), żeby
  /// otwierać Dziennik/Ulubione/Ustawienia dokładnie tak samo,
  /// jak z bottom sheet „Więcej”.
  void _openMoreScreenFromHome(Widget screen) {
    _openMoreScreen(screen);
  }

  void _openSearchResultsFromReader(String query) {
    final navigator = _innerNavigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      AppPageRoute.fade(
        settings: const RouteSettings(name: '/search/from-reader'),
        builder: (_) => SearchScreen(
          initialQuery: query,
          onNavigateToTab: _onTabSelected,
          onOpenMoreScreen: _openMoreScreenFromHome,
          onBookResultSelectedFromReader: () {
            navigator.pop();
            _pendingReaderRequestSignal.value++;
          },
        ),
      ),
    );
  }

  /// Buduje ekran odpowiadający aktualnie wybranemu bazowemu tabowi.
  Widget _buildTabBody() {
    switch (_baseTabIndex) {
      case MainTabs.start:
        return HomeScreen(
          onNavigateToTab: _onTabSelected,
          onOpenMoreScreen: _openMoreScreenFromHome,
        );
      case MainTabs.formation:
        return FormationChallengeScreen(onNavigateToTab: _onTabSelected);
      case MainTabs.book:
        // ValueKey na podstawie _readerInstanceId wymusza nową instancję,
        // gdy ten licznik się zmieni.
        return ReadingHubScreen(
          readerScreenKey: ValueKey(_readerInstanceId),
          pendingReaderRequestSignal: _pendingReaderRequestSignal,
          onOpenSearchResults: _openSearchResultsFromReader,
          onNavigateToTab: _onTabSelected,
        );
      case MainTabs.journal:
        return JournalScreen(
          onNavigateToTab: _onTabSelected,
          showBackButton: false,
        );
      case MainTabs.settings:
        return const SettingsScreen(showBackButton: false);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAnimatedTabBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 160),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
            reverseCurve: Curves.easeIn,
          ),
          child: child,
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(_baseTabIndex),
        child: _buildTabBody(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Zamiast bezpośrednio `_buildTabBody()`, używamy wewnętrznego Navigatora.
      body: Navigator(
        key: _innerNavigatorKey,
        observers: [
          appRouteObserver, // RouteObserver działa dla wewnętrznego stosu route’ów.
        ],
        onGenerateRoute: (settings) {
          // Pierwsza (bazowa) trasa – aktualny tab (Start domyślnie).
          return MaterialPageRoute(
            builder: (_) => _buildAnimatedTabBody(),
            settings: settings,
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabSelected,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Start'),
          BottomNavigationBarItem(icon: Icon(Icons.route), label: 'Droga'),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Książka',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_note_rounded),
            label: 'Dziennik',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Ustawienia',
          ),
        ],
      ),
    );
  }
}

class _AppUpdatePromptSheet extends StatefulWidget {
  final String remoteVersion;
  final String? storeUrl;
  final AppUpdateService appUpdateService;

  const _AppUpdatePromptSheet({
    required this.remoteVersion,
    required this.storeUrl,
    required this.appUpdateService,
  });

  @override
  State<_AppUpdatePromptSheet> createState() => _AppUpdatePromptSheetState();
}

class _AppUpdatePromptSheetState extends State<_AppUpdatePromptSheet> {
  bool _isOpeningStore = false;

  Future<void> _dismissForNow() async {
    await widget.appUpdateService.dismissAppVersion(widget.remoteVersion);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openStore() async {
    if (_isOpeningStore) return;

    final storeUrl = widget.storeUrl;
    final uri = storeUrl == null ? null : Uri.tryParse(storeUrl);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (uri == null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć App Store.')),
      );
      return;
    }

    setState(() {
      _isOpeningStore = true;
    });

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    if (ok) {
      navigator.pop();
      return;
    }

    setState(() {
      _isOpeningStore = false;
    });
    messenger.clearSnackBars();
    messenger.showSnackBar(
      const SnackBar(content: Text('Nie udało się otworzyć App Store.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Dostępna nowa wersja',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'W App Store jest dostępna nowsza wersja aplikacji.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 8),
            const Text(
              'Możesz zaktualizować aplikację teraz albo zrobić to później.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isOpeningStore ? null : _dismissForNow,
                  child: const Text('Nie teraz'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isOpeningStore ? null : _openStore,
                  icon: _isOpeningStore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.open_in_new_rounded),
                  label: Text(_isOpeningStore ? 'Otwieranie...' : 'Aktualizuj'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentUpdatePromptSheet extends StatefulWidget {
  final String remoteVersion;
  final ContentUpdateService contentUpdateService;

  const _ContentUpdatePromptSheet({
    required this.remoteVersion,
    required this.contentUpdateService,
  });

  @override
  State<_ContentUpdatePromptSheet> createState() =>
      _ContentUpdatePromptSheetState();
}

class _ContentUpdatePromptSheetState extends State<_ContentUpdatePromptSheet> {
  bool _isDownloading = false;

  Future<void> _dismissForNow() async {
    await widget.contentUpdateService.dismissContentVersion(
      widget.remoteVersion,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _download() async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await widget.contentUpdateService.checkAndDownloadLatest();
    if (!mounted) return;

    final message = _contentUpdateMessage(result);
    messenger.clearSnackBars();

    if (result.status == ContentUpdateStatus.updated) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    setState(() {
      _isDownloading = false;
    });
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _contentUpdateMessage(ContentUpdateResult result) {
    final suffix = result.status == ContentUpdateStatus.updated
        ? ' Zmiany będą widoczne po ponownym otwarciu czytnika.'
        : '';

    final message = switch (result.status) {
      ContentUpdateStatus.updated => 'Pobrano najnowszą wersję tekstu.',
      ContentUpdateStatus.upToDate => 'Masz już najnowszą wersję tekstu.',
      ContentUpdateStatus.skippedIncompatibleAppVersion =>
        'Ta wersja tekstu wymaga nowszej wersji aplikacji.',
      ContentUpdateStatus.manifestUnavailable =>
        'Nie udało się sprawdzić aktualizacji tekstu.',
      ContentUpdateStatus.downloadFailed => 'Nie udało się pobrać tekstu.',
      ContentUpdateStatus.invalidHash =>
        'Pobrany plik nie przeszedł weryfikacji.',
      ContentUpdateStatus.invalidJson =>
        'Pobrany tekst ma nieprawidłowy format.',
      ContentUpdateStatus.unknownError => 'Wystąpił nieznany błąd.',
    };

    return '$message$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 32,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Dostępna aktualizacja tekstu',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Jest dostępna nowsza wersja tekstu książki. Może zawierać '
              'poprawki literówek i dopasowanie tekstu do nagrań.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 8),
            const Text(
              'Możesz to zrobić później w ustawieniach.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isDownloading ? null : _dismissForNow,
                  child: const Text('Nie teraz'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isDownloading ? null : _download,
                  icon: _isDownloading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_isDownloading ? 'Pobieranie...' : 'Pobierz'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
