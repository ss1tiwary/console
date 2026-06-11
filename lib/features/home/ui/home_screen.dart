import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Navigation destinations — expanded in Phase 3 when admin screens move in.
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
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    // Placeholder — replaced in Phase 3 when screens are moved in.
    return Center(
      child: Text(
        _current.name,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
