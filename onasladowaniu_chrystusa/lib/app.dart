import 'dart:async';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'features/home/home_screen.dart';
import 'features/reading/reading_hub_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/formation_challenge/formation_challenge_screen.dart';
import 'features/audio/ui/listen_screen.dart';
import 'features/search/search_screen.dart';
import 'shared/navigation/app_page_route.dart';
import 'shared/navigation/main_tabs.dart';
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
          unselectedItemColor: colorScheme.onSurface.withOpacity(0.7),
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
  /// Bazowa zakładka (Start / Droga / Czytaj / Słuchaj).
  int _baseTabIndex = MainTabs.start;

  /// Aktualnie podświetlana zakładka w BottomNavigationBar (Start/Droga/Czytaj/Słuchaj).
  int _selectedIndex = MainTabs.start;

  /// ID instancji Readera.
  final int _readerInstanceId = 0;
  final ValueNotifier<int> _pendingReaderRequestSignal = ValueNotifier<int>(0);
  String? _activeMoreRouteName;

  /// Wewnętrzny Navigator, w którym renderujemy:
  /// - ekrany z bottom nav (Start, Droga, Czytaj, Słuchaj),
  /// - oraz dodatkowe ekrany: Dziennik, Ulubione, Ustawienia itp.
  ///
  /// Dzięki temu dolny pasek jest zawsze widoczny.
  final GlobalKey<NavigatorState> _innerNavigatorKey =
      GlobalKey<NavigatorState>();
  StreamSubscription<String>? _notificationSubscription;
  StreamSubscription<Uri?>? _widgetClickSubscription;
  String? _pendingNotificationPayload;
  bool _isOpeningFormationFromNotification = false;

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
    final nav = _innerNavigatorKey.currentState;
    final atRoot = !(nav?.canPop() ?? false);

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
      _baseTabIndex = index;
      _selectedIndex = index;
    });

    // Resetujemy stos wewnętrznego Navigatora do bazowego ekranu taba.
    nav?.popUntil((route) => route.isFirst);
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

  /// Buduje ekran odpowiadający aktualnie wybranemu bazowemu tabowi
  /// (Start/Droga/Czytaj/Słuchaj).
  Widget _buildTabBody() {
    switch (_baseTabIndex) {
      case MainTabs.start:
        return HomeScreen(
          onNavigateToTab: _onTabSelected,
          onOpenMoreScreen: _openMoreScreenFromHome,
        );
      case MainTabs.formation:
        return FormationChallengeScreen(onNavigateToTab: _onTabSelected);
      case MainTabs.read:
        // ValueKey na podstawie _readerInstanceId wymusza nową instancję,
        // gdy ten licznik się zmieni.
        return ReadingHubScreen(
          readerScreenKey: ValueKey(_readerInstanceId),
          pendingReaderRequestSignal: _pendingReaderRequestSignal,
          onOpenSearchResults: _openSearchResultsFromReader,
          onNavigateToTab: _onTabSelected,
        );
      case MainTabs.listen:
        return ListenScreen(onNavigateToTab: _onTabSelected);
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
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Czytaj'),
          BottomNavigationBarItem(
            icon: Icon(Icons.headphones_rounded),
            label: 'Słuchaj',
          ),
        ],
      ),
    );
  }
}
