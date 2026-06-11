import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/di/router.dart';
import 'core/theme/console_theme.dart';

class ConsoleApp extends ConsumerWidget {
  const ConsoleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Resolve Console',
      debugShowCheckedModeBanner: false,
      theme: ConsoleTheme.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
