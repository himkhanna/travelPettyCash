import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../cms/presentation/widgets/cms_layout.dart';
import '../application/audit_providers.dart';
import '../domain/audit_entry.dart';

/// Admin-only "who did what, when" feed. Lists every financial mutation in
/// reverse-chronological order. Server enforces admin/super-only access.
class CmsAuditScreen extends ConsumerWidget {
  const CmsAuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AuditEntry>> async = ref.watch(auditFeedProvider);

    return CmsLayout(
      active: CmsNavItem.audit,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load audit feed: $e',
              style: const TextStyle(color: AppColors.outflow),
            ),
          ),
        ),
        data: (List<AuditEntry> entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Text(
                'No activity recorded yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: _AuditTable(entries: entries),
            ),
          );
        },
      ),
    );
  }
}

class _AuditTable extends StatelessWidget {
  const _AuditTable({required this.entries});
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context) {
    final DateFormat dateFmt = DateFormat('d MMM yyyy · HH:mm');
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: const BorderRadius.all(AppRadii.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.bgElev,
              borderRadius: BorderRadius.vertical(top: AppRadii.card),
            ),
            child: Row(
              children: const <Widget>[
                Expanded(flex: 3, child: _Th(label: 'WHEN')),
                Expanded(flex: 3, child: _Th(label: 'WHO')),
                Expanded(flex: 3, child: _Th(label: 'ACTION')),
                Expanded(flex: 4, child: _Th(label: 'SUMMARY')),
                Expanded(flex: 2, child: _Th(label: 'TRIP')),
                Expanded(
                  flex: 2,
                  child: _Th(label: 'AMOUNT', align: TextAlign.right),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.divider),
              itemBuilder: (BuildContext context, int i) {
                final AuditEntry e = entries[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: Text(
                          dateFmt.format(e.at.toLocal()),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: _WhoCell(
                            name: e.actorName, role: e.actorRole),
                      ),
                      Expanded(
                        flex: 3,
                        child: _ActionChip(action: e.action),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          e.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          e.tripName ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          e.amount?.format() ?? '',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Th extends StatelessWidget {
  const _Th({required this.label, this.align = TextAlign.left});
  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: align,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _WhoCell extends StatelessWidget {
  const _WhoCell({required this.name, required this.role});
  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          _roleLabel(role),
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  String _roleLabel(String r) {
    switch (r) {
      case 'ADMIN':
        return 'Admin';
      case 'SUPER_ADMIN':
        return 'Director General';
      case 'LEADER':
        return 'Trip Leader';
      case 'MEMBER':
        return 'Team Member';
      default:
        return r;
    }
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.action});
  final AuditAction action;

  @override
  Widget build(BuildContext context) {
    final ({String label, Color color, Color bg, IconData icon}) cfg =
        _cfgFor(action);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cfg.bg,
          borderRadius: const BorderRadius.all(AppRadii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(cfg.icon, size: 12, color: cfg.color),
            const SizedBox(width: 4),
            Text(
              cfg.label,
              style: TextStyle(
                color: cfg.color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color, Color bg, IconData icon}) _cfgFor(
    AuditAction a,
  ) {
    switch (a) {
      case AuditAction.tripCreated:
        return (
          label: 'TRIP CREATED',
          color: AppColors.brand,
          bg: AppColors.brandTint,
          icon: Icons.flight_takeoff_outlined,
        );
      case AuditAction.tripClosed:
        return (
          label: 'TRIP CLOSED',
          color: AppColors.textSecondary,
          bg: AppColors.bgInset,
          icon: Icons.lock_outline,
        );
      case AuditAction.allocationFromAdmin:
        return (
          label: 'ADMIN ALLOC',
          color: AppColors.brand,
          bg: AppColors.brandTint,
          icon: Icons.account_balance_outlined,
        );
      case AuditAction.allocationFromLeader:
        return (
          label: 'LEADER ALLOC',
          color: AppColors.goldDeep,
          bg: AppColors.goldSoft,
          icon: Icons.swap_calls_outlined,
        );
      case AuditAction.allocationAccepted:
        return (
          label: 'ACCEPTED',
          color: AppColors.green,
          bg: AppColors.greenSoft,
          icon: Icons.check_circle_outline,
        );
      case AuditAction.allocationDeclined:
        return (
          label: 'DECLINED',
          color: AppColors.red,
          bg: AppColors.redSoft,
          icon: Icons.cancel_outlined,
        );
      case AuditAction.transferSent:
        return (
          label: 'TRANSFER',
          color: AppColors.blue,
          bg: AppColors.blueSoft,
          icon: Icons.compare_arrows,
        );
      case AuditAction.transferAccepted:
        return (
          label: 'XFER ACCEPTED',
          color: AppColors.green,
          bg: AppColors.greenSoft,
          icon: Icons.check_circle_outline,
        );
      case AuditAction.transferDeclined:
        return (
          label: 'XFER DECLINED',
          color: AppColors.red,
          bg: AppColors.redSoft,
          icon: Icons.cancel_outlined,
        );
      case AuditAction.expenseLogged:
        return (
          label: 'EXPENSE',
          color: AppColors.amber,
          bg: AppColors.amberSoft,
          icon: Icons.receipt_long_outlined,
        );
      case AuditAction.userSignedIn:
        return (
          label: 'SIGN IN',
          color: AppColors.textSecondary,
          bg: AppColors.bgInset,
          icon: Icons.login,
        );
      case AuditAction.userCreated:
        return (
          label: 'USER CREATED',
          color: AppColors.brand,
          bg: AppColors.brandTint,
          icon: Icons.person_add_alt_1,
        );
      case AuditAction.userUpdated:
        return (
          label: 'USER UPDATED',
          color: AppColors.brand,
          bg: AppColors.brandTint,
          icon: Icons.edit_outlined,
        );
    }
  }
}
