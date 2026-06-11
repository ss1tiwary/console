import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qbank_ui/qbank_ui.dart';

class ConsoleTheme {
  ConsoleTheme._();

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4263EB)),
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(),
        // Register the shared renderer skin — same defaults as PIBrief.
        extensions: const [QbankTheme.standard],
      );
}
