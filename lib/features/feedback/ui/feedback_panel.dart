import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../data/feedback_model.dart';
import '../../../core/palette.dart';
import '../../../core/spacing.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _feedbackFilterProvider = StateProvider<String?>((ref) => 'pending');

final _allFeedbackProvider =
    FutureProvider.autoDispose<List<AdminFeedbackItem>>((ref) {
  final filter = ref.watch(_feedbackFilterProvider);
  return ref
      .watch(feedbackRepositoryProvider)
      .getAllFeedback(filterStatus: filter);
});

// ── Panel ─────────────────────────────────────────────────────────────────────

/// Admin panel for reviewing user-submitted content feedback.
class FeedbackPanel extends ConsumerWidget {
  const FeedbackPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(_feedbackFilterProvider);
    final feedAsync = ref.watch(_allFeedbackProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          color: AppPalette.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Feedback Review',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _FilterTabBar(
                  current: filter,
                  onChanged: (v) =>
                      ref.read(_feedbackFilterProvider.notifier).state = v),
              const Divider(height: 1, color: AppPalette.grey200),
            ],
          ),
        ),
        // Body
        Expanded(
          child: feedAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (items) => items.isEmpty
                ? _emptyState(filter)
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(_allFeedbackProvider.future),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: AppSpacing.pagePadding),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _FeedbackCard(
                        item: items[i],
                        onStatusToggle: () =>
                            _toggleStatus(ref, context, items[i]),
                        onDelete: () =>
                            _confirmDelete(ref, context, items[i]),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String? filter) {
    final label = switch (filter) {
      'pending' => 'No pending feedback',
      'addressed' => 'No addressed feedback',
      _ => 'No feedback yet',
    };
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 48, color: AppPalette.grey300),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  color: AppPalette.grey400, fontSize: 15)),
        ],
      ),
    );
  }

  Future<void> _toggleStatus(
      WidgetRef ref, BuildContext context, AdminFeedbackItem item) async {
    final newStatus = item.isPending ? 'addressed' : 'pending';
    try {
      await ref
          .read(feedbackRepositoryProvider)
          .updateStatus(item.id, newStatus);
      ref.invalidate(_allFeedbackProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to update status'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _confirmDelete(
      WidgetRef ref, BuildContext context, AdminFeedbackItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete feedback?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete',
                style: TextStyle(color: AppPalette.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(feedbackRepositoryProvider)
          .deleteById(item.id);
      ref.invalidate(_allFeedbackProvider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to delete'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }
}

// ── Filter tab bar ─────────────────────────────────────────────────────────────

class _FilterTabBar extends StatelessWidget {
  final String? current;
  final ValueChanged<String?> onChanged;
  const _FilterTabBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(children: [
        _Tab('Pending', 'pending', current, onChanged),
        _Tab('Addressed', 'addressed', current, onChanged),
        _Tab('All', null, current, onChanged),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final String? value;
  final String? current;
  final ValueChanged<String?> onChanged;
  const _Tab(this.label, this.value, this.current, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppPalette.white,
            border: Border(
              bottom: BorderSide(
                color: selected ? AppPalette.indigo : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppPalette.indigo : AppPalette.grey400,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Feedback card ─────────────────────────────────────────────────────────────

class _FeedbackCard extends StatelessWidget {
  final AdminFeedbackItem item;
  final VoidCallback onStatusToggle;
  final VoidCallback onDelete;
  const _FeedbackCard({
    required this.item,
    required this.onStatusToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (typeColor, typeBg) = _typeColors(item.feedbackType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppPalette.white,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color:
              item.isPending ? AppPalette.grey200 : AppPalette.grey100,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeBg,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    item.feedbackType.label.toUpperCase(),
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 3),
                  decoration: BoxDecoration(
                    color: item.isPending
                        ? AppPalette.amber
                        : AppPalette.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  item.isPending ? 'Pending' : 'Addressed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: item.isPending
                        ? AppPalette.amber
                        : AppPalette.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TargetTypeBadge(targetType: item.targetType),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.targetLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.grey900,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (item.note?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
              child: Text(
                '"${item.note}"',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.grey600,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
            child: Text(
              _formatDate(item.createdAt),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppPalette.grey400, fontSize: 11),
            ),
          ),
          const Divider(
              height: 16,
              indent: 14,
              endIndent: 14,
              color: AppPalette.grey100),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: onStatusToggle,
                  icon: Icon(
                    item.isPending
                        ? Icons.check_circle_outline
                        : Icons.refresh,
                    size: 16,
                    color: item.isPending
                        ? AppPalette.green
                        : AppPalette.grey400,
                  ),
                  label: Text(
                    item.isPending ? 'Mark addressed' : 'Mark pending',
                    style: TextStyle(
                      color: item.isPending
                          ? AppPalette.green
                          : AppPalette.grey400,
                      fontSize: 13,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: AppPalette.red),
                  tooltip: 'Delete',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _typeColors(FeedbackType type) => switch (type) {
        FeedbackType.relevanceTooHigh =>
          (AppPalette.red, const Color(0xFFFEE2E2)),
        FeedbackType.relevanceTooLow =>
          (AppPalette.amber, AppPalette.amberLight),
        FeedbackType.syllabusWrong =>
          (const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
        FeedbackType.schemeMissed =>
          (AppPalette.green, AppPalette.greenLight),
        FeedbackType.summaryPoor =>
          (const Color(0xFF0891B2), const Color(0xFFE0F7FA)),
        FeedbackType.incorrectInfo =>
          (AppPalette.red, const Color(0xFFFEE2E2)),
        FeedbackType.outdated =>
          (AppPalette.amber, AppPalette.amberLight),
        FeedbackType.missingDetail =>
          (const Color(0xFF0891B2), const Color(0xFFE0F7FA)),
        FeedbackType.wrongClassification =>
          (const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
        FeedbackType.notUseful =>
          (AppPalette.grey600, AppPalette.grey100),
        FeedbackType.other => (AppPalette.grey600, AppPalette.grey100),
      };

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

class _TargetTypeBadge extends StatelessWidget {
  final ContentTargetType targetType;
  const _TargetTypeBadge({required this.targetType});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (targetType) {
      ContentTargetType.post =>
        (AppPalette.indigo, AppPalette.indigoLight),
      ContentTargetType.scheme =>
        (AppPalette.green, AppPalette.greenLight),
      ContentTargetType.entity =>
        (const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
      ContentTargetType.legalRef =>
        (AppPalette.amber, AppPalette.amberLight),
      ContentTargetType.question =>
        (const Color(0xFF0D9488), const Color(0xFFF0FDFA)),
      ContentTargetType.app =>
        (AppPalette.grey600, AppPalette.grey100),
    };
    return Container(
      margin: const EdgeInsets.only(top: 1),
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(
        targetType.label.toUpperCase(),
        style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3),
      ),
    );
  }
}
