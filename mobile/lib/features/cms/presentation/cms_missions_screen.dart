import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart' show AppSpacing, AppRadii;
import '../../../core/api/api_error.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user.dart';
import '../../missions/application/mission_providers.dart';
import '../../missions/domain/mission.dart';
import '../../reports/application/report_download_providers.dart';
import '../../reports/data/report_download_repository.dart';
import '../../reports/presentation/save_to_disk.dart';
import '../../trips/application/trips_providers.dart';
import '../../trips/domain/trip.dart';
import 'widgets/cms_layout.dart';
import 'widgets/cms_theme.dart';

/// Admin-only Missions management. Responsive card grid replacing the
/// earlier dense table. Each card surfaces the mission's name + Arabic
/// name, status, trip count, parent mission (if nested), and the
/// edit/delete affordances. Delete is guarded server-side and the SnackBar
/// surfaces the 7807 detail so admins know what to clean up first.
class CmsMissionsScreen extends ConsumerWidget {
  const CmsMissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<User?> meAsync = ref.watch(currentUserProvider);
    final User? me = meAsync.valueOrNull;
    if (me == null) {
      if (meAsync.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/');
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (me.role != UserRole.admin && me.role != UserRole.superAdmin) {
      return const CmsLayout(
        active: CmsNavItem.missions,
        child: Center(child: Text('You do not have access to this page.')),
      );
    }

    final AsyncValue<List<Mission>> missionsAsync =
        ref.watch(missionsProvider);
    final AsyncValue<List<Trip>> tripsAsync =
        ref.watch(_allTripsForMissionsProvider);

    return CmsLayout(
      active: CmsNavItem.missions,
      titleSubtitle: 'Group trips under a diplomatic or operational mission.',
      floatingActionButton: me.role == UserRole.admin
          ? FloatingActionButton.extended(
              backgroundColor: CmsColors.brand,
              foregroundColor: CmsColors.surfaceCard,
              icon: const Icon(Icons.add),
              label: const Text('NEW MISSION'),
              onPressed: () => _openCreate(context, ref),
            )
          : null,
      child: missionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<Mission> missions) {
          final Map<String, int> tripCounts = _countTripsByMission(
            tripsAsync.valueOrNull ?? const <Trip>[],
          );
          final Map<String, Mission> byId = <String, Mission>{
            for (final Mission m in missions) m.id: m,
          };
          // Surface parent missions first, then children — keeps any nested
          // pairs visually adjacent in the grid without requiring strict
          // indentation that doesn't translate to a card layout.
          final List<Mission> ordered = <Mission>[
            ...missions.where((Mission m) => m.parentMissionId == null),
            ...missions.where((Mission m) => m.parentMissionId != null),
          ]..sort((Mission a, Mission b) {
              final int byParent =
                  (a.parentMissionId == null ? 0 : 1) -
                      (b.parentMissionId == null ? 0 : 1);
              if (byParent != 0) return byParent;
              return b.createdAt.compareTo(a.createdAt);
            });

          if (ordered.isEmpty) {
            return const _EmptyState();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 80,
            ),
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints c) {
                final int cols = c.maxWidth >= 1400
                    ? 4
                    : c.maxWidth >= 1000
                        ? 3
                        : c.maxWidth >= 640
                            ? 2
                            : 1;
                const double gap = 16;
                final double cardWidth =
                    (c.maxWidth - (cols - 1) * gap) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    for (final Mission m in ordered)
                      SizedBox(
                        width: cardWidth,
                        child: _MissionCard(
                          mission: m,
                          parent: m.parentMissionId == null
                              ? null
                              : byId[m.parentMissionId!],
                          tripCount: tripCounts[m.id] ?? 0,
                          canEdit: me.role == UserRole.admin,
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final Mission? created = await showDialog<Mission>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => const _MissionEditorDialog(),
    );
    if (created != null) {
      ref.invalidate(missionsProvider);
    }
  }
}

/// All trips visible to Admin/SuperAdmin so we can render a trip-count
/// badge per mission and gate the delete affordance.
final FutureProvider<List<Trip>> _allTripsForMissionsProvider =
    FutureProvider<List<Trip>>((Ref ref) async {
  final User? user = await ref.watch(currentUserProvider.future);
  if (user == null) return <Trip>[];
  return ref.read(tripRepositoryProvider).allTrips();
});

Map<String, int> _countTripsByMission(List<Trip> trips) {
  final Map<String, int> counts = <String, int>{};
  for (final Trip t in trips) {
    final String? mid = t.missionId;
    if (mid == null) continue;
    counts[mid] = (counts[mid] ?? 0) + 1;
  }
  return counts;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: CmsColors.bgElev,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.flag_outlined,
              color: CmsColors.textSecondary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No missions yet.',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: CmsColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Create one to group trips under a diplomatic objective.',
            style: TextStyle(color: CmsColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MissionCard extends ConsumerWidget {
  const _MissionCard({
    required this.mission,
    required this.parent,
    required this.tripCount,
    required this.canEdit,
  });

  final Mission mission;
  final Mission? parent;
  final int tripCount;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool closed = mission.status == MissionStatus.closed;
    return Material(
      color: CmsColors.surfaceCard,
      borderRadius: const BorderRadius.all(AppRadii.card),
      child: InkWell(
        borderRadius: const BorderRadius.all(AppRadii.card),
        onTap: () => context.go('/cms/missions/${mission.id}'),
        child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(color: CmsColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header strip — name + status + overflow menu
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: closed
                          ? CmsColors.bgElev
                          : CmsColors.brandTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.flag_outlined,
                      size: 18,
                      color: closed
                          ? CmsColors.textSecondary
                          : CmsColors.brand,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          mission.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: CmsColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        if (mission.nameAr != null &&
                            mission.nameAr!.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            mission.nameAr!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: CmsColors.textSecondary,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (canEdit)
                    _OverflowMenu(
                      mission: mission,
                      tripCount: tripCount,
                    ),
                ],
              ),
            ),
            // Meta row — code + status + parent
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  _MetaChip(
                    icon: Icons.tag,
                    label: mission.code,
                    monospace: true,
                  ),
                  _StatusPill(closed: closed),
                  if (parent != null)
                    _MetaChip(
                      icon: Icons.subdirectory_arrow_right,
                      label: parent!.name,
                      color: CmsColors.gold,
                    ),
                ],
              ),
            ),
            if (mission.description != null &&
                mission.description!.isNotEmpty) ...<Widget>[
              const Divider(height: 1, color: CmsColors.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Text(
                  mission.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: CmsColors.textBody,
                    height: 1.4,
                  ),
                ),
              ),
            ],
            const Divider(height: 1, color: CmsColors.divider),
            // Footer — trip count + created date
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.flight_outlined,
                    size: 14,
                    color: tripCount == 0
                        ? CmsColors.textSecondary
                        : CmsColors.brand,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tripCount == 0
                        ? 'No trips'
                        : '$tripCount trip${tripCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: tripCount == 0
                          ? FontWeight.w500
                          : FontWeight.w700,
                      color: tripCount == 0
                          ? CmsColors.textSecondary
                          : CmsColors.brand,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('d MMM yyyy')
                        .format(mission.createdAt.toLocal()),
                    style: const TextStyle(
                      fontSize: 11,
                      color: CmsColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.mission, required this.tripCount});
  final Mission mission;
  final int tripCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Mission actions',
      icon: const Icon(
        Icons.more_vert,
        size: 20,
        color: CmsColors.textSecondary,
      ),
      onSelected: (String v) {
        if (v == 'edit') _openEdit(context, ref);
        if (v == 'delete') _confirmDelete(context, ref);
        if (v == 'download') _downloadRollup(context, ref);
        if (v == 'download-today') _downloadRollup(context, ref, today: true);
      },
      itemBuilder: (BuildContext _) => const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'download',
          child: ListTile(
            leading: Icon(Icons.download, size: 18),
            title: Text('Download rollup (XLSX)'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: 'download-today',
          child: ListTile(
            leading: Icon(Icons.today, size: 18),
            title: Text("Download today's rollup"),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('Edit mission'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline,
                size: 18, color: CmsColors.outflow),
            title: Text(
              'Delete mission',
              style: TextStyle(color: CmsColors.outflow),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    final Mission? saved = await showDialog<Mission>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) =>
          _MissionEditorDialog(existing: mission),
    );
    if (saved != null) {
      ref.invalidate(missionsProvider);
    }
  }

  /// Downloads a mission-wide XLSX rollup of every trip's expenses tagged
  /// with this mission. When [today] is true, restricts to today's date —
  /// the "send to finance at end of day" workflow.
  Future<void> _downloadRollup(
    BuildContext context,
    WidgetRef ref, {
    bool today = false,
  }) async {
    try {
      final report = await ref.read(reportDownloadRepositoryProvider).download(
            kind: ReportDownloadKind.missionRollup,
            missionId: mission.id,
            date: today ? DateTime.now() : null,
          );
      saveBytesToDisk(
        bytes: report.bytes,
        filename: report.filename,
        contentType: report.contentType,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${report.filename}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mission rollup failed: $e'),
          backgroundColor: CmsColors.outflow,
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (tripCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot delete: $tripCount trip(s) are attached to this mission.',
          ),
          backgroundColor: CmsColors.outflow,
        ),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => AlertDialog(
        title: const Text('Delete mission?'),
        content: Text('Delete "${mission.name}"? This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CmsColors.outflow,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(missionRepositoryProvider).delete(mission.id);
      ref.invalidate(missionsProvider);
    } on ApiError catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.detail),
          backgroundColor: CmsColors.outflow,
        ),
      );
    }
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.monospace = false,
    this.color,
  });
  final IconData icon;
  final String label;
  final bool monospace;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? CmsColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: monospace ? 'monospace' : null,
              letterSpacing: monospace ? 0 : 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.closed});
  final bool closed;
  @override
  Widget build(BuildContext context) {
    final Color c = closed ? CmsColors.textSecondary : CmsColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            closed ? 'Closed' : 'Active',
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Create / edit dialog — kept compact, palette aligned with CmsColors.
// =========================================================================

class _MissionEditorDialog extends ConsumerStatefulWidget {
  const _MissionEditorDialog({this.existing});
  final Mission? existing;

  @override
  ConsumerState<_MissionEditorDialog> createState() =>
      _MissionEditorDialogState();
}

class _MissionEditorDialogState
    extends ConsumerState<_MissionEditorDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _nameArCtrl =
      TextEditingController(text: widget.existing?.nameAr ?? '');
  late final TextEditingController _codeCtrl =
      TextEditingController(text: widget.existing?.code ?? '');
  late final TextEditingController _descCtrl =
      TextEditingController(text: widget.existing?.description ?? '');
  late String? _parentId = widget.existing?.parentMissionId;
  late MissionStatus _status =
      widget.existing?.status ?? MissionStatus.active;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameArCtrl.dispose();
    _codeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Mission>> missionsAsync =
        ref.watch(missionsProvider);
    final List<Mission> all = missionsAsync.valueOrNull ?? const <Mission>[];
    final List<Mission> parentOptions = all
        .where((Mission m) => m.id != widget.existing?.id)
        .toList()
      ..sort((Mission a, Mission b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.md, AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.flag_outlined, color: CmsColors.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Edit mission' : 'New mission',
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: CmsColors.divider),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mission name',
                        hintText: 'e.g. Gulf State Tour 2026',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _nameArCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mission name (Arabic)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _codeCtrl,
                      enabled: !_isEdit,
                      decoration: InputDecoration(
                        labelText: _isEdit
                            ? 'Code (immutable)'
                            : 'Code (optional — auto-generated if blank)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _descCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String?>(
                      initialValue: _parentId,
                      decoration: const InputDecoration(
                        labelText: 'Parent mission (optional)',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('— None (top-level mission)'),
                        ),
                        for (final Mission m in parentOptions)
                          DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text('${m.name}  ·  ${m.code}'),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (String? v) => setState(() => _parentId = v),
                    ),
                    if (_isEdit) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Active'),
                        subtitle: Text(
                          _status == MissionStatus.active
                              ? 'Trips can be assigned to this mission.'
                              : 'Closed — hidden from the new-trip picker.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: CmsColors.textSecondary,
                              ),
                        ),
                        value: _status == MissionStatus.active,
                        onChanged: _saving
                            ? null
                            : (bool v) => setState(() => _status =
                                v ? MissionStatus.active : MissionStatus.closed),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: CmsColors.outflow.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(AppRadii.chip),
                  border: Border.all(
                    color: CmsColors.outflow.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline,
                        size: 18, color: CmsColors.outflow),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: CmsColors.outflow),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, color: CmsColors.divider),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: CmsColors.brand,
                      foregroundColor: CmsColors.surfaceCard,
                      minimumSize: const Size(0, 40),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: CmsColors.surfaceCard,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _isEdit ? 'SAVE' : 'CREATE',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Mission name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Mission result = _isEdit
          ? await ref.read(missionRepositoryProvider).update(
                id: widget.existing!.id,
                name: _nameCtrl.text.trim(),
                nameAr: _nameArCtrl.text.trim().isEmpty
                    ? null
                    : _nameArCtrl.text.trim(),
                description: _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
                parentMissionId: _parentId,
                status: _status,
              )
          : await ref.read(missionRepositoryProvider).create(
                name: _nameCtrl.text.trim(),
                nameAr: _nameArCtrl.text.trim().isEmpty
                    ? null
                    : _nameArCtrl.text.trim(),
                code: _codeCtrl.text.trim().isEmpty
                    ? null
                    : _codeCtrl.text.trim(),
                description: _descCtrl.text.trim().isEmpty
                    ? null
                    : _descCtrl.text.trim(),
                parentMissionId: _parentId,
              );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on ApiError catch (e) {
      setState(() {
        _error = e.detail;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }
}
