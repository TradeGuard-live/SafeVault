import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';

class ActivityTimelineScreen extends ConsumerStatefulWidget {
  const ActivityTimelineScreen({super.key});

  @override
  ConsumerState<ActivityTimelineScreen> createState() => _ActivityTimelineScreenState();
}

class _ActivityTimelineScreenState extends ConsumerState<ActivityTimelineScreen> {
  String? _selectedFilter;

  IconData _iconForActivity(String type) {
    switch (type) {
      case 'DOCUMENT_ADDED':
        return Icons.add_circle_outline_rounded;
      case 'DOCUMENT_SCANNED':
        return Icons.document_scanner_rounded;
      case 'DOCUMENT_UPDATED':
        return Icons.edit_note_rounded;
      case 'FAVORITE_TOGGLED':
        return Icons.star_rounded;
      case 'MOVED_TO_TRASH':
        return Icons.delete_outline_rounded;
      case 'DOCUMENT_RESTORED':
        return Icons.restore_from_trash_rounded;
      case 'PERMANENTLY_DELETED':
        return Icons.delete_forever_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  Color _colorForActivity(String type, AppThemeColors colors) {
    switch (type) {
      case 'DOCUMENT_ADDED':
      case 'DOCUMENT_SCANNED':
        return colors.primaryAccent;
      case 'DOCUMENT_UPDATED':
        return const Color(0xFF2563EB);
      case 'FAVORITE_TOGGLED':
        return Colors.amber;
      case 'MOVED_TO_TRASH':
        return colors.warning;
      case 'PERMANENTLY_DELETED':
        return colors.error;
      case 'DOCUMENT_RESTORED':
        return colors.success;
      default:
        return colors.textSecondary;
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Clear Activity Timeline?',
      message: 'This will delete the local activity audit history. Documents will remain untouched.',
      confirmLabel: 'Clear History',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      final repo = ref.read(activityRepositoryProvider);
      await repo.clearAllActivities();
      ref.invalidate(activitiesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final activitiesAsync = ref.watch(activitiesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Activity Timeline', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Timeline',
            onPressed: _clearHistory,
          ),
        ],
      ),
      body: activitiesAsync.when(
        data: (activities) {
          final filtered = _selectedFilter == null
              ? activities
              : activities.where((a) => a.activityType == _selectedFilter).toList();

          if (filtered.isEmpty) {
            return const EmptyStateView(
              icon: Icons.history_rounded,
              title: 'No Activity Recorded',
              description: 'Audit logs for document additions, updates, scans, and deletions will appear here.',
              mascotPose: MascotPose.friendly,
            );
          }

          return Column(
            children: [
              // Filter Chips
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildChip('All', null, colors),
                    _buildChip('Added', 'DOCUMENT_ADDED', colors),
                    _buildChip('Scanned', 'DOCUMENT_SCANNED', colors),
                    _buildChip('Updated', 'DOCUMENT_UPDATED', colors),
                    _buildChip('Trash / Delete', 'MOVED_TO_TRASH', colors),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Chronological Timeline List
              Expanded(
                child: RefreshIndicator(
                  color: colors.primaryAccent,
                  onRefresh: () async {
                    ref.invalidate(activitiesProvider);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final item = filtered[i];
                      final color = _colorForActivity(item.activityType, colors);
                      final icon = _iconForActivity(item.activityType);

                      return Container(
                        decoration: BoxDecoration(
                          color: colors.cardBackground,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colors.cardBorder,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          title: Text(
                            item.documentName,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                item.details ?? item.activityType.replaceAll('_', ' '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                DateFormatter.formatDateTimeDisplay(item.timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: colors.primaryAccent)),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildChip(String label, String? type, AppThemeColors colors) {
    final isSelected = _selectedFilter == type;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() => _selectedFilter = type);
        },
        backgroundColor: colors.cardBackground,
        selectedColor: colors.primaryAccent.withOpacity(0.2),
        labelStyle: TextStyle(
          fontSize: 12,
          color: isSelected ? colors.primaryAccent : colors.textSecondary,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}
