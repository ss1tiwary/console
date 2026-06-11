import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

// Public anon key — safe to commit (read-only client credential).
// service_role key is NEVER in Flutter code (PRINCIPLES security rule).
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://wodfsezackspsoafkhti.supabase.co',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndvZGZzZXphY2tzcHNvYWZraHRpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk5NzgzNTUsImV4cCI6MjA5NTU1NDM1NX0.IBhgHZqOKggXGndbV7PVSO2uPIkErAo0dPMDAsg_pnY',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: deprecated_member_use — supabase_flutter renames anonKey→publishableKey
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
  runApp(const ProviderScope(child: ConsoleApp()));
}
