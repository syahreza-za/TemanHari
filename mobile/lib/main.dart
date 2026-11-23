import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app.dart';
import 'core/storage/local_cache.dart';
import 'providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);

  final localCache = LocalCacheService();
  await localCache.init();

  runApp(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(localCache),
      ],
      child: const TemanHariApp(),
    ),
  );
}
