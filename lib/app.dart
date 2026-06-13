import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qbank_ui/qbank_ui.dart';
import 'package:resolve_theme/resolve_theme.dart';
import 'core/di/router.dart';

class ConsoleApp extends ConsumerWidget {
  const ConsoleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'PnAConsole',
      debugShowCheckedModeBanner: false,
      theme: ResolveTheme.light.withQbankSkin(),
      darkTheme: ResolveTheme.dark.withQbankSkin(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
