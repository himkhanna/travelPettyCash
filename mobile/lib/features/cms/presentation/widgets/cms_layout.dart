import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/application/auth_actions.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../auth/domain/user.dart';
import '../../../notifications/application/notifications_providers.dart';
import '../../../notifications/data/notifications_repository.dart';
import '../../../notifications/domain/notification.dart';
import '../../../search/data/search_repository.dart';
import 'cms_theme.dart';

/// Top-level CMS sections that map to actual routes.
///
/// The mockup's sidebar lists several items we don't have screens for
/// yet (Trips, Approvals, Expenses, Organizations, Overview, Spend,
/// Settings). They appear as "coming soon" entries — `_SidebarItem` with
/// `enabled: false` — so the IA reads correctly without dragging the
/// admin to a broken route.
enum CmsNavItem {
  home, trips, missions, expenses, users, audit, dg, reports, settings,
}

extension on CmsNavItem {
  String get label {
    switch (this) {
      case CmsNavItem.home:
        return 'Home';
      case CmsNavItem.trips:
        return 'Trips';
      case CmsNavItem.missions:
        return 'Missions';
      case CmsNavItem.expenses:
        return 'Expenses';
      case CmsNavItem.users:
        return 'Users';
      case CmsNavItem.audit:
        return 'Audit log';
      case CmsNavItem.dg:
        return 'DG View';
      case CmsNavItem.reports:
        return 'Reports';
      case CmsNavItem.settings:
        return 'Settings';
    }
  }

  String get path {
    switch (this) {
      case CmsNavItem.home:
        return '/cms';
      case CmsNavItem.trips:
        return '/cms/trips';
      case CmsNavItem.missions:
        return '/cms/missions';
      case CmsNavItem.expenses:
        return '/cms/expenses';
      case CmsNavItem.users:
        return '/cms/users';
      case CmsNavItem.audit:
        return '/cms/audit';
      case CmsNavItem.dg:
        return '/cms/dg';
      case CmsNavItem.reports:
        return '/cms/reports';
      case CmsNavItem.settings:
        return '/cms/settings';
    }
  }
}

/// Shared shell for every CMS screen. Three-column layout:
///   ┌─ sidebar (220) ─┬─ top bar  ──────────────────────────┐
///   │                 ├─ child  · optional right rail       │
///   └─────────────────┴─────────────────────────────────────┘
///
/// The right rail is opt-in per screen — dashboard uses it for spend
/// charts + recent activity; everything else leaves it null and the
/// child takes the full width.
class CmsLayout extends ConsumerWidget {
  const CmsLayout({
    super.key,
    required this.active,
    required this.child,
    this.floatingActionButton,
    this.trailing,
    this.title,
    this.titleSubtitle,
    this.breadcrumb,
    this.rightRail,
    this.rightRailWidth = 280,
    this.showTitleStrip = true,
  });

  final CmsNavItem active;
  final Widget child;
  final Widget? floatingActionButton;

  /// Optional action widgets in the top bar (between search and bell).
  /// Pass the primary CTA here, e.g. a "+ New trip" button.
  final List<Widget>? trailing;

  /// Page heading shown in the strip below the top bar. Defaults to the
  /// active sidebar item's label.
  final String? title;
  final String? titleSubtitle;

  /// Legacy field — was the breadcrumb path before the breadcrumb was
  /// removed. Kept so existing callers that pass it still compile;
  /// nothing currently renders it.
  final List<String>? breadcrumb;

  /// Hide the page title strip — used by the home dashboard which has
  /// its own big greeting and doesn't need an extra strip above it.
  final bool showTitleStrip;

  /// Optional right rail. When non-null the content area splits into a
  /// scrollable [child] and a fixed-width rail.
  final Widget? rightRail;
  final double rightRailWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final User? me = ref.watch(currentUserProvider).valueOrNull;
    return Scaffold(
      backgroundColor: CmsColors.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Sidebar(active: active, me: me),
          Expanded(
            child: Column(
              children: <Widget>[
                _TopBar(
                  active: active,
                  me: me,
                  breadcrumb: breadcrumb ??
                      <String>['Home', active.label],
                  trailing: trailing,
                ),
                if (showTitleStrip)
                  _PageTitleBar(
                    title: title ?? active.label,
                    subtitle: titleSubtitle,
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(child: child),
                      if (rightRail != null) ...<Widget>[
                        Container(
                          width: 1,
                          color: CmsColors.divider,
                        ),
                        SizedBox(
                          width: rightRailWidth,
                          child: rightRail!,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Slim white strip below the top bar — carries the current page's
/// title + optional subtitle, with a gold rule on the left. Skipped on
/// the home dashboard (which has its own big greeting).
class _PageTitleBar extends StatelessWidget {
  const _PageTitleBar({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: CmsColors.surfaceCard,
        border: Border(
          bottom: BorderSide(color: CmsColors.divider),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(width: 3, height: 22, color: CmsColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CmsColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CmsColors.textSecondary,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// Sidebar
// =========================================================================

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.active, required this.me});
  final CmsNavItem active;
  final User? me;

  static const double width = 220;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: CmsColors.sidebarBg,
        border: Border(right: BorderSide(color: CmsColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SidebarLogo(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SidebarSection(title: 'Operations'),
                  _SidebarItem(
                    icon: Icons.home_outlined,
                    label: 'Home',
                    selected: active == CmsNavItem.home,
                    onTap: () =>
                        GoRouter.of(context).go(CmsNavItem.home.path),
                  ),
                  _SidebarItem(
                    icon: Icons.flight_takeoff_outlined,
                    label: 'Trips',
                    selected: active == CmsNavItem.trips,
                    onTap: () =>
                        GoRouter.of(context).go(CmsNavItem.trips.path),
                  ),
                  _SidebarItem(
                    icon: Icons.flag_outlined,
                    label: 'Missions',
                    selected: active == CmsNavItem.missions,
                    onTap: () =>
                        GoRouter.of(context).go(CmsNavItem.missions.path),
                  ),
                  const _SidebarItem(
                    icon: Icons.task_alt_outlined,
                    label: 'Approvals',
                    enabled: false,
                  ),
                  _SidebarItem(
                    icon: Icons.receipt_long_outlined,
                    label: 'Expenses',
                    selected: active == CmsNavItem.expenses,
                    onTap: () =>
                        GoRouter.of(context).go(CmsNavItem.expenses.path),
                  ),
                  _SidebarSection(title: 'Reporting'),
                  _SidebarItem(
                    icon: Icons.pie_chart_outline,
                    label: 'Reports',
                    selected: active == CmsNavItem.reports,
                    onTap: () =>
                        GoRouter.of(context).go(CmsNavItem.reports.path),
                  ),
                  if (me?.role == UserRole.superAdmin)
                    _SidebarItem(
                      icon: Icons.bar_chart_outlined,
                      label: 'DG View',
                      selected: active == CmsNavItem.dg,
                      onTap: () =>
                          GoRouter.of(context).go(CmsNavItem.dg.path),
                    ),
                  _SidebarSection(title: 'System'),
                  _SidebarItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    selected: active == CmsNavItem.settings,
                    onTap: () =>
                        GoRouter.of(context).go(CmsNavItem.settings.path),
                  ),
                ],
              ),
            ),
          ),
          if (me != null) _SidebarUserFooter(me: me!),
        ],
      ),
    );
  }
}

class _SidebarLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: CmsColors.brand,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: const Text(
              'P',
              style: TextStyle(
                color: CmsColors.surfaceCard,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const <Widget>[
                Text(
                  'PDD',
                  style: TextStyle(
                    color: CmsColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.1,
                  ),
                ),
                Text(
                  'Protocol & Delegation',
                  style: TextStyle(
                    color: CmsColors.textSecondary,
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarSection extends StatelessWidget {
  const _SidebarSection({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: CmsColors.textTertiary,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    // Plumbed for sidebar unread badges; no call site supplies it yet.
    // ignore: unused_element_parameter
    this.badge,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final Color fg = !enabled
        ? CmsColors.textTertiary
        : selected
            ? CmsColors.textPrimary
            : CmsColors.textBody;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color:
            selected ? CmsColors.brandTint : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled
              ? (onTap ??
                  () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Coming soon')),
                      ))
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CmsColors.brand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: CmsColors.surfaceCard,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarUserFooter extends StatelessWidget {
  const _SidebarUserFooter({required this.me});
  final User me;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: CmsColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor: CmsColors.brand,
            child: Text(
              _initials(me.displayName),
              style: const TextStyle(
                color: CmsColors.surfaceCard,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  me.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CmsColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.15,
                  ),
                ),
                Text(
                  _roleLabel(me.role),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CmsColors.textSecondary,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _roleLabel(UserRole r) {
    switch (r) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Super admin';
      case UserRole.leader:
        return 'Leader';
      case UserRole.member:
        return 'Member';
    }
  }
}

// =========================================================================
// Top bar
// =========================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.active,
    required this.me,
    required this.breadcrumb,
    required this.trailing,
  });

  final CmsNavItem active;
  final User? me;
  final List<String> breadcrumb;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: CmsColors.surface,
        border: Border(bottom: BorderSide(color: CmsColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: <Widget>[
          Expanded(child: _SearchField()),
          const SizedBox(width: 14),
          if (trailing != null) ...<Widget>[
            for (final Widget t in trailing!) ...<Widget>[
              t,
              const SizedBox(width: 8),
            ],
          ],
          _NotificationBell(),
          const SizedBox(width: 4),
          _TopBarIcon(
            icon: Icons.help_outline,
            tooltip: 'Help',
            onTap: () {},
          ),
          const SizedBox(width: 10),
          if (me != null) _AccountChip(me: me!),
        ],
      ),
    );
  }
}

/// Top-bar search input with a live results dropdown. Debounces input
/// by 220ms before hitting the backend, then renders the typed results
/// (trips / missions / users) as a grouped list anchored under the box.
/// Clicking a hit closes the overlay and navigates to its `link`.
class _SearchField extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(_onTextChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChange);
    _ctrl.removeListener(_onTextChange);
    _focus.dispose();
    _ctrl.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus && _query.length >= 2) {
      _showOverlay();
    } else if (!_focus.hasFocus) {
      // Delay closing slightly so a click on a result has time to fire.
      Future<void>.delayed(const Duration(milliseconds: 150), _hideOverlay);
    }
  }

  void _onTextChange() {
    final String trimmed = _ctrl.text.trim();
    if (trimmed == _query) return;
    _query = trimmed;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      if (_query.length < 2) {
        _hideOverlay();
      } else {
        _showOverlay();
        // Re-render the overlay so it picks up the new query.
        _overlay?.markNeedsBuild();
      }
    });
  }

  void _showOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlay!);
  }

  void _hideOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _go(String link) {
    _hideOverlay();
    _focus.unfocus();
    _ctrl.clear();
    _query = '';
    GoRouter.of(context).go(link);
  }

  Widget _buildOverlay() {
    return Positioned(
      width: 460,
      child: CompositedTransformFollower(
        link: _link,
        offset: const Offset(0, 38),
        showWhenUnlinked: false,
        child: Material(
          elevation: 8,
          shadowColor: CmsColors.brand.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          child: Consumer(builder: (BuildContext _, WidgetRef r, __) {
            final AsyncValue<List<SearchHit>> async =
                r.watch(globalSearchProvider(_query));
            return Container(
              constraints: const BoxConstraints(maxHeight: 360),
              decoration: BoxDecoration(
                color: CmsColors.surfaceCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: CmsColors.divider),
              ),
              child: async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Searching…',
                    style: TextStyle(
                      color: CmsColors.textSecondary, fontSize: 12),
                  ),
                ),
                error: (Object e, _) => Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Search failed: $e',
                    style: const TextStyle(
                      color: CmsColors.outflow, fontSize: 12),
                  ),
                ),
                data: (List<SearchHit> hits) {
                  if (hits.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'No matches.',
                        style: TextStyle(
                            color: CmsColors.textSecondary, fontSize: 12),
                      ),
                    );
                  }
                  // Group by type so trips/missions/users render under headers.
                  final Map<String, List<SearchHit>> grouped =
                      <String, List<SearchHit>>{};
                  for (final SearchHit h in hits) {
                    grouped.putIfAbsent(h.type, () => <SearchHit>[]).add(h);
                  }
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final String type in const <String>[
                          'trip', 'mission', 'user',
                        ])
                          if (grouped[type] != null)
                            ..._renderBucket(type, grouped[type]!),
                      ],
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ),
    );
  }

  List<Widget> _renderBucket(String type, List<SearchHit> hits) {
    return <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Text(
          _labelFor(type).toUpperCase(),
          style: const TextStyle(
            color: CmsColors.textTertiary,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
      for (final SearchHit h in hits)
        InkWell(
          onTap: () => _go(h.link),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(
              children: <Widget>[
                Icon(_iconFor(type), size: 14, color: CmsColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        h.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CmsColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        h.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CmsColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  String _labelFor(String type) => switch (type) {
        'trip' => 'Trips',
        'mission' => 'Missions',
        'user' => 'Users',
        _ => type,
      };
  IconData _iconFor(String type) => switch (type) {
        'trip' => Icons.flight_takeoff_outlined,
        'mission' => Icons.flag_outlined,
        'user' => Icons.person_outline,
        _ => Icons.search,
      };

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Container(
        height: 34,
        constraints: const BoxConstraints(maxWidth: 460),
        decoration: BoxDecoration(
          color: CmsColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CmsColors.divider),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.search, size: 15, color: CmsColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search trips, users, missions…',
                  hintStyle: TextStyle(
                    color: CmsColors.textTertiary, fontSize: 13,
                  ),
                ),
                style: const TextStyle(
                  color: CmsColors.textPrimary, fontSize: 13,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: CmsColors.bgElev,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '⌘K',
                style: TextStyle(
                  color: CmsColors.textSecondary,
                  fontSize: 10, fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: CmsColors.textSecondary),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }
}

class _AccountChip extends ConsumerWidget {
  const _AccountChip({required this.me});
  final User me;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 40),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleAvatar(
            radius: 13,
            backgroundColor: CmsColors.brand,
            child: Text(
              _initials(me.displayName),
              style: const TextStyle(
                color: CmsColors.surfaceCard,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                me.displayName,
                style: const TextStyle(
                  color: CmsColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              Text(
                _roleLabel(me.role),
                style: const TextStyle(
                  color: CmsColors.textSecondary,
                  fontSize: 10,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
      itemBuilder: (BuildContext _) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            me.email,
            style: const TextStyle(color: CmsColors.textSecondary),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signout',
          child: ListTile(
            leading: Icon(Icons.logout, size: 18),
            title: Text('Sign out'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      onSelected: (String v) {
        if (v == 'signout') {
          confirmAndSignOut(context, ref, redirect: '/portal');
        }
      },
    );
  }

  String _initials(String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _roleLabel(UserRole r) {
    switch (r) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.superAdmin:
        return 'Super admin';
      case UserRole.leader:
        return 'Leader';
      case UserRole.member:
        return 'Member';
    }
  }
}

// =========================================================================
// Notification bell (top-bar popover)
// =========================================================================

/// Top-bar bell with an unread badge and a click-out popover that shows
/// the most recent notifications, routes each to the right CMS surface,
/// and clears unread on tap. Mirrors the search overlay pattern so the
/// popover anchors directly under the icon and tears down on outside
/// click.
class _NotificationBell extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<_NotificationBell> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlay;
  bool _open = false;

  @override
  void dispose() {
    _closeOverlay();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_open) {
      _closeOverlay();
    } else {
      _openOverlay();
    }
  }

  void _openOverlay() {
    _overlay = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlay!);
    setState(() => _open = true);
  }

  void _closeOverlay() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() => _open = false);
  }

  Widget _buildOverlay() {
    // Full-bleed barrier behind the popover so a click anywhere outside
    // dismisses it without us tracking pointer events ourselves.
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeOverlay,
          ),
        ),
        Positioned(
          width: 380,
          child: CompositedTransformFollower(
            link: _link,
            offset: const Offset(-340, 36),
            showWhenUnlinked: false,
            child: Material(
              elevation: 10,
              shadowColor: CmsColors.brand.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 460),
                decoration: BoxDecoration(
                  color: CmsColors.surfaceCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: CmsColors.divider),
                ),
                child: Consumer(builder: (BuildContext _, WidgetRef r, __) {
                  final AsyncValue<List<AppNotification>> async =
                      r.watch(myNotificationsProvider);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _popoverHeader(r, async.valueOrNull ?? <AppNotification>[]),
                      Flexible(
                        child: async.when(
                          loading: () => const _PopoverEmpty(
                            label: 'Loading…',
                          ),
                          error: (Object e, _) => _PopoverEmpty(
                            label: 'Could not load notifications.\n$e',
                            isError: true,
                          ),
                          data: (List<AppNotification> list) {
                            if (list.isEmpty) {
                              return const _PopoverEmpty(
                                label: "You're all caught up.",
                              );
                            }
                            final List<AppNotification> top =
                                list.take(12).toList();
                            return ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: top.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1, color: CmsColors.divider,
                              ),
                              itemBuilder: (BuildContext _, int i) =>
                                  _NotificationRow(
                                n: top[i],
                                onTap: () => _handleTap(r, top[i]),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _popoverHeader(WidgetRef r, List<AppNotification> rows) {
    final int unread = rows
        .where((AppNotification n) =>
            n.state == NotificationState.unread)
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CmsColors.divider)),
      ),
      child: Row(
        children: <Widget>[
          const Text(
            'Notifications',
            style: TextStyle(
              color: CmsColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(width: 8),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 2,
              ),
              decoration: BoxDecoration(
                color: CmsColors.brand,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unread new',
                style: const TextStyle(
                  color: CmsColors.surfaceCard,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          const Spacer(),
          if (unread > 0)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: CmsColors.brand,
                minimumSize: const Size(0, 28),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 11.5,
                ),
              ),
              onPressed: () => _markAllRead(r, rows),
              child: const Text('Mark all read'),
            ),
        ],
      ),
    );
  }

  Future<void> _markAllRead(
    WidgetRef r, List<AppNotification> rows,
  ) async {
    final NotificationsRepository repo =
        r.read(notificationsRepositoryProvider);
    final List<Future<void>> futures = <Future<void>>[];
    for (final AppNotification n in rows) {
      if (n.state == NotificationState.unread) {
        futures.add(repo.markRead(n.id));
      }
    }
    await Future.wait(futures);
    if (mounted) ref.invalidate(myNotificationsProvider);
  }

  Future<void> _handleTap(WidgetRef r, AppNotification n) async {
    final bool wasUnread = n.state == NotificationState.unread;
    _closeOverlay();
    if (wasUnread) {
      await r.read(notificationsRepositoryProvider).markRead(n.id);
      if (mounted) ref.invalidate(myNotificationsProvider);
    }
    if (!mounted) return;
    final String? target = _cmsTargetFor(n);
    if (target != null) {
      GoRouter.of(context).go(target);
    }
  }

  /// Route a notification to its admin-side surface. We don't have
  /// dedicated CMS chat / single-expense screens, so a few types
  /// (chat, expense-query) deep-link to the related trip page where the
  /// admin can drill down from there.
  String? _cmsTargetFor(AppNotification n) {
    final Map<String, Object?> p = n.payload;
    String? str(String key) => p[key] as String?;
    switch (n.type) {
      case NotificationType.reportReady:
        final String? scope = str('scope');
        final String? scopeId = str('scopeId');
        if (scope == 'mission' && scopeId != null) {
          return '/cms/missions/$scopeId';
        }
        if (scope == 'trip' && scopeId != null) {
          return '/cms/trips/$scopeId';
        }
        final String? tripId = str('tripId');
        if (tripId != null) return '/cms/trips/$tripId';
        return '/cms/reports';
      case NotificationType.expenseQuery:
        final String? expenseId = str('expenseId');
        if (expenseId != null) return '/cms/expenses/$expenseId';
        return '/cms/expenses';
      case NotificationType.chatMessage:
      case NotificationType.allocationReceived:
      case NotificationType.transferReceived:
      case NotificationType.transferAccepted:
      case NotificationType.tripAssigned:
      case NotificationType.tripClosed:
        final String? tripId = str('tripId');
        if (tripId != null) return '/cms/trips/$tripId';
        return '/cms/trips';
    }
  }

  @override
  Widget build(BuildContext context) {
    final int unread = ref.watch(myUnreadCountProvider);
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: 'Notifications',
        child: InkWell(
          onTap: _toggleOverlay,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                const Center(
                  child: Icon(
                    Icons.notifications_none_outlined,
                    size: 18,
                    color: CmsColors.textSecondary,
                  ),
                ),
                if (unread > 0)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 14, minHeight: 14,
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: CmsColors.outflow,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: CmsColors.surface, width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: CmsColors.surfaceCard,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PopoverEmpty extends StatelessWidget {
  const _PopoverEmpty({required this.label, this.isError = false});
  final String label;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isError ? CmsColors.outflow : CmsColors.textSecondary,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ({Color color, IconData icon, String label}) cfg = _styleFor(n.type);
    final bool unread = n.state == NotificationState.unread;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: cfg.color.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(cfg.icon, size: 14, color: cfg.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        cfg.label,
                        style: TextStyle(
                          color: cfg.color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _timeAgo(n.createdAt),
                        style: const TextStyle(
                          color: CmsColors.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _summarize(n),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CmsColors.textPrimary,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight:
                          unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 6, top: 6),
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: CmsColors.outflow,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  ({Color color, IconData icon, String label}) _styleFor(NotificationType t) {
    switch (t) {
      case NotificationType.allocationReceived:
        return (
          color: CmsColors.gold,
          icon: Icons.account_balance_outlined,
          label: 'ALLOCATION',
        );
      case NotificationType.transferReceived:
        return (
          color: CmsColors.brand,
          icon: Icons.swap_horiz,
          label: 'TRANSFER',
        );
      case NotificationType.transferAccepted:
        return (
          color: CmsColors.accent,
          icon: Icons.check_circle_outline,
          label: 'ACCEPTED',
        );
      case NotificationType.tripAssigned:
        return (
          color: CmsColors.brand,
          icon: Icons.flight_takeoff_outlined,
          label: 'TRIP',
        );
      case NotificationType.tripClosed:
        return (
          color: CmsColors.textSecondary,
          icon: Icons.lock_outline,
          label: 'CLOSED',
        );
      case NotificationType.expenseQuery:
        return (
          color: CmsColors.gold,
          icon: Icons.help_outline,
          label: 'QUERY',
        );
      case NotificationType.reportReady:
        return (
          color: CmsColors.brand,
          icon: Icons.description_outlined,
          label: 'REPORT',
        );
      case NotificationType.chatMessage:
        return (
          color: CmsColors.brand,
          icon: Icons.chat_bubble_outline,
          label: 'CHAT',
        );
    }
  }

  String _summarize(AppNotification n) {
    String? s(String k) => n.payload[k] as String?;
    switch (n.type) {
      case NotificationType.allocationReceived:
        return 'Funds were allocated.';
      case NotificationType.transferReceived:
        return 'A peer transfer was received.';
      case NotificationType.transferAccepted:
        return n.payload['response'] == 'declined'
            ? 'A transfer was declined.'
            : 'A transfer was accepted.';
      case NotificationType.tripAssigned:
        return 'A new trip has been assigned.';
      case NotificationType.tripClosed:
        final String tripName = s('tripName') ?? 'A trip';
        return '$tripName was closed.';
      case NotificationType.expenseQuery:
        final String snip = s('snippet') ?? '';
        final String trip = s('tripName') ?? 'a trip';
        return snip.isEmpty
            ? 'A comment was posted on an expense in $trip.'
            : 'New comment in $trip: "$snip"';
      case NotificationType.reportReady:
        final String name = s('scopeName') ?? s('tripName') ?? 'a trip';
        final String reason = s('reason') ?? 'manual';
        if (reason == 'trip-closed') {
          return 'Trip closed — $name. Open to generate '
              'the finance letter.';
        }
        return 'Report ready for $name. Open to download.';
      case NotificationType.chatMessage:
        final String trip = s('tripName') ?? 'a trip';
        final String snip = s('snippet') ?? '';
        return snip.isEmpty
            ? 'New chat message in $trip.'
            : 'Chat in $trip: "$snip"';
    }
  }

  String _timeAgo(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${d.inDays ~/ 7}w ago';
  }
}
