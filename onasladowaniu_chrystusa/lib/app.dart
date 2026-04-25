import 'dart:async';

import 'package:flutter/material.dart';

import 'features/home/home_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/bookmarks/bookmarks_screen.dart';
import 'features/journal/journal_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/favorites/favorites_screen.dart';
import 'features/formation_challenge/formation_challenge_screen.dart';
import 'shared/services/formation_notification_service.dart';
import 'app_route_observer.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ImitationOfChristApp extends StatelessWidget {
  final String? initialNotificationPayload;

  const ImitationOfChristApp({
    super.key,
    this.initialNotificationPayload,
  });

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
          unselectedItemColor:
              colorScheme.onSurface.withOpacity(0.7),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: backgroundColor,
        ),
      ),
      home: _RootScreen(
        initialNotificationPayload: initialNotificationPayload,
      ),
      debugShowCheckedModeBanner: false,
      // RouteObserver podpinamy do wewnętrznego Navigatora, nie tutaj.
    );
  }
}

class _RootScreen extends StatefulWidget {
  final String? initialNotificationPayload;

  const _RootScreen({
    this.initialNotificationPayload,
  });

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen>
    with WidgetsBindingObserver {
  /// Bazowa zakładka (Start / Czytanie / Zakładki).
  int _baseTabIndex = 0;

  /// Aktualnie podświetlana zakładka w BottomNavigationBar (Start/Czytanie/Zakładki/Więcej).
  int _selectedIndex = 0;

  /// ID instancji Readera – zmiana powoduje utworzenie nowej ReaderScreen.
  int _readerInstanceId = 0;

  /// Wewnętrzny Navigator, w którym renderujemy:
  /// - ekrany z bottom nav (Start, Czytanie, Zakładki),
  /// - oraz stack "Więcej": Dziennik, Ulubione, Ustawienia itp.
  ///
  /// Dzięki temu dolny pasek jest zawsze widoczny.
  final GlobalKey<NavigatorState> _innerNavigatorKey =
      GlobalKey<NavigatorState>();
  StreamSubscription<String>? _notificationSubscription;
  String? _pendingNotificationPayload;
  bool _isOpeningFormationFromNotification = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint(
      '[FormationNavigation] _RootScreen initState, '
      'initialPayload=${widget.initialNotificationPayload}',
    );
    _notificationSubscription = FormationNotificationService
        .instance.payloadStream
        .listen(_handleNotificationPayload);

    final initialPayload = widget.initialNotificationPayload;
    if (initialPayload != null && initialPayload.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationPayload(initialPayload);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingNotificationPayload('initState');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[FormationNavigation] lifecycle state changed: $state');
    if (state != AppLifecycleState.resumed) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingNotificationPayload('resumed');
    });
  }

  Future<void> _checkPendingNotificationPayload(String source) async {
    if (!mounted) return;

    debugPrint('[FormationNavigation] checking pending payload from $source');
    final pendingPayload =
        await FormationNotificationService.instance.takePendingPayload();
    if (!mounted) return;

    if (pendingPayload != null && pendingPayload.isNotEmpty) {
      _handleNotificationPayload(pendingPayload);
    }
  }

  void _handleNotificationPayload(String payload) {
    debugPrint('[FormationNavigation] payload received: $payload');
    if (payload != FormationNotificationService.formationPayload) {
      debugPrint('[FormationNavigation] payload ignored: $payload');
      return;
    }

    debugPrint('[FormationNavigation] formation_challenge payload detected');
    _pendingNotificationPayload = payload;
    _openPendingNotificationPayload();
  }

  void _openPendingNotificationPayload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final payload = _pendingNotificationPayload;
      if (payload != FormationNotificationService.formationPayload) {
        debugPrint(
          '[FormationNavigation] no pending formation payload to open',
        );
        return;
      }

      if (_isOpeningFormationFromNotification) {
        debugPrint('[FormationNavigation] push already in progress');
        return;
      }

      final navigator = appNavigatorKey.currentState;
      if (navigator == null) {
        debugPrint(
          '[FormationNavigation] root navigator not ready, retrying push',
        );
        _openPendingNotificationPayload();
        return;
      }

      _isOpeningFormationFromNotification = true;
      _pendingNotificationPayload = null;

      setState(() {
        _selectedIndex = _baseTabIndex;
      });

      debugPrint(
        '[FormationNavigation] trying to push FormationChallengeScreen',
      );
      navigator
          .push(
            MaterialPageRoute(
              settings: const RouteSettings(name: '/formation-challenge'),
              builder: (_) => const FormationChallengeScreen(),
            ),
          )
          .whenComplete(() {
        _isOpeningFormationFromNotification = false;
      });
      debugPrint(
        '[FormationNavigation] push invoked for FormationChallengeScreen',
      );
    });
  }

  void _onTabSelected(int index) {
    // Ostatni przycisk ("Więcej") otwiera bottom sheet,
    // nie zmieniamy wtedy bazowej zakładki.
    if (index == 3) {
      _showMoreSheet();
      return;
    }

    final nav = _innerNavigatorKey.currentState;
    final atRoot = !(nav?.canPop() ?? false);

    // Jeśli jesteśmy już na bazowym ekranie tego taba
    // i nie jest to "Czytanie", to nic nie rób – unikamy
    // ponownej animacji/pushowania.
    //
    // Dla "Czytanie" (index == 1) zostawiamy specjalne
    // zachowanie: ponowne kliknięcie tworzy nową instancję
    // ReaderScreen, więc nie short-circuitujemy.
    if (index == _baseTabIndex && atRoot && index != 1) {
      setState(() {
        _selectedIndex = index; // dla porządku, choć i tak już jest
      });
      return;
    }

    final previousBase = _baseTabIndex;

    setState(() {
      // Specjalny przypadek: Czytanie -> Czytanie.
      if (index == 1 && previousBase == 1) {
        _readerInstanceId++;
      }
      _baseTabIndex = index;
      _selectedIndex = index;
    });

    // Resetujemy stos wewnętrznego Navigatora do bazowego ekranu taba.
    nav?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => _buildTabBody(),
      ),
      (route) => false,
    );
  }

  void _showMoreSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Dziennik duchowy'),
                onTap: () {
                  Navigator.of(ctx).pop(); // zamknij bottom sheet
                  _openMoreScreen(
                    JournalScreen(
                      onNavigateToTab: _onTabSelected,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_quote),
                title: const Text('Ulubione cytaty'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openMoreScreen(
                    FavoritesScreen(
                      onNavigateToTab: _onTabSelected,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Ustawienia'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openMoreScreen(
                    const SettingsScreen(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Otwiera ekran z sekcji "Więcej" (Dziennik/Ulubione/Ustawienia).
  /// Podświetla przycisk "Więcej", a po zamknięciu ekranu przywraca
  /// podświetlenie bazowej zakładki (_baseTabIndex).
  void _openMoreScreen(Widget screen) {
    setState(() {
      _selectedIndex = 3; // podświetl "Więcej"
    });

    _innerNavigatorKey.currentState
        ?.push(
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    )
        .then((_) {
      if (!mounted) return;
      // Po powrocie z ekranu "Więcej" przywracamy podświetlenie bazowej zakładki.
      setState(() {
        _selectedIndex = _baseTabIndex;
      });
    });
  }

  /// Używane przez HomeScreen (szybkie akcje), żeby
  /// otwierać Dziennik/Ulubione/Ustawienia dokładnie tak samo,
  /// jak z bottom sheet „Więcej”.
  void _openMoreScreenFromHome(Widget screen) {
    _openMoreScreen(screen);
  }

  /// Buduje ekran odpowiadający aktualnie wybranemu bazowemu tabowi
  /// (Start/Czytanie/Zakładki).
  Widget _buildTabBody() {
    switch (_baseTabIndex) {
      case 0:
        return HomeScreen(
          onNavigateToTab: _onTabSelected,
          onOpenMoreScreen: _openMoreScreenFromHome,
        );
      case 1:
        // ValueKey na podstawie _readerInstanceId wymusza nową instancję,
        // gdy ten licznik się zmieni.
        return ReaderScreen(key: ValueKey(_readerInstanceId));
      case 2:
        return BookmarksScreen(onNavigateToTab: _onTabSelected);
      default:
        return const SizedBox.shrink();
    }
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
            builder: (_) => _buildTabBody(),
            settings: settings,
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabSelected,
        type: BottomNavigationBarType.fixed,
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
            icon: Icon(Icons.bookmark),
            label: 'Zakładki',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'Więcej',
          ),
        ],
      ),
    );
  }
}
