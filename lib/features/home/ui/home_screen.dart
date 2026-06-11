import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../extraction/ui/extraction_panel.dart';
import '../../feedback/ui/feedback_panel.dart';
import '../../ideas/ui/ideas_panel.dart';
import '../../relevance/ui/relevance_hub_panel.dart';

enum _Dest { extraction, feedback, relevance, ideas }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Dest _current = _Dest.extraction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _Dest.values.indexOf(_current),
            onDestinationSelected: (i) =>
                setState(() => _current = _Dest.values[i]),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.quiz_outlined),
                selectedIcon: Icon(Icons.quiz),
                label: Text('Extraction'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.feedback_outlined),
                selectedIcon: Icon(Icons.feedback),
                label: Text('Feedback'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rate_review_outlined),
                selectedIcon: Icon(Icons.rate_review),
                label: Text('Relevance'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.lightbulb_outline),
                selectedIcon: Icon(Icons.lightbulb),
                label: Text('Ideas'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: () =>
                        Supabase.instance.client.auth.signOut(),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _panel()),
        ],
      ),
    );
  }

  Widget _panel() => switch (_current) {
        _Dest.extraction => const ExtractionPanel(),
        _Dest.feedback => const FeedbackPanel(),
        _Dest.relevance => const RelevanceHubPanel(),
        _Dest.ideas => const IdeasPanel(),
      };
}
