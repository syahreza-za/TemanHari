import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/agenda_provider.dart';
import 'providers/app_providers.dart';
import 'providers/chat_provider.dart';
import 'providers/session_provider.dart';

class TemanHariApp extends ConsumerStatefulWidget {
  const TemanHariApp({super.key});

  @override
  ConsumerState<TemanHariApp> createState() => _TemanHariAppState();
}

class _TemanHariAppState extends ConsumerState<TemanHariApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrapApp);
  }

  Future<void> _bootstrapApp() async {
    await ref.read(sessionProvider.notifier).bootstrap();
    await Future.wait([
      ref.read(agendaProvider.notifier).loadAgenda(),
      ref.read(chatProvider.notifier).loadHistoryAndGreeting(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'TemanHari',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      locale: const Locale('id', 'ID'),
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
