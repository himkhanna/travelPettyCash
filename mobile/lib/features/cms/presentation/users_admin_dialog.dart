import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/domain/user.dart';

/// Admin-only: list, create, edit, and (de)activate users for the application.
/// Users cannot be deleted — they're referenced by expenses, trips, and audit
/// rows. Deactivation hides them from new trip assignments and chat pickers,
/// without breaking historical records.
class UsersAdminDialog extends ConsumerStatefulWidget {
  const UsersAdminDialog({super.key});

  @override
  ConsumerState<UsersAdminDialog> createState() => _UsersAdminDialogState();
}

class _UsersAdminDialogState extends ConsumerState<UsersAdminDialog> {
  UserRole? _roleFilter;
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final DemoStore store = ref.watch(demoStoreProvider);
    final List<User> users = store.users
        .where((User u) {
          if (_roleFilter != null && u.role != _roleFilter) return false;
          if (!_showInactive && !u.isActive) return false;
          return true;
        })
        .toList()
      ..sort((User a, User b) => a.displayName.compareTo(b.displayName));

    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _header(context, store),
            const Divider(height: 1),
            _filters(),
            const Divider(height: 1),
            Flexible(
              child: users.isEmpty
                  ? const _Empty()
                  : ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (BuildContext _, int i) => _UserRow(
                        user: users[i],
                        onEdit: () => _openForm(existing: users[i]),
                        onToggleActive: () => _toggleActive(users[i]),
                      ),
                    ),
            ),
            const Divider(height: 1),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, DemoStore store) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.group_outlined, color: AppColors.brandBrown),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'User Management',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(width: AppSpacing.sm),
          Chip(
            label: Text('${store.users.length} users'),
            backgroundColor: AppColors.cream,
          ),
          const Spacer(),
          FilledButton.icon(
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('ADD USER'),
            onPressed: () => _openForm(),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Text(
            'ROLE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ChoiceChip(
            label: const Text('All'),
            selected: _roleFilter == null,
            onSelected: (_) => setState(() => _roleFilter = null),
          ),
          const SizedBox(width: 4),
          for (final UserRole r in UserRole.values) ...<Widget>[
            ChoiceChip(
              label: Text(_roleLabel(r)),
              selected: _roleFilter == r,
              onSelected: (_) => setState(() => _roleFilter = r),
            ),
            const SizedBox(width: 4),
          ],
          const Spacer(),
          FilterChip(
            label: const Text('Show inactive'),
            selected: _showInactive,
            onSelected: (bool v) => setState(() => _showInactive = v),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm({User? existing}) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext _) => UserFormDialog(existing: existing),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _toggleActive(User u) async {
    final DemoStore store = ref.read(demoStoreProvider);
    final int i = store.users.indexWhere((User x) => x.id == u.id);
    if (i < 0) return;
    store.users[i] = User(
      id: u.id,
      username: u.username,
      displayName: u.displayName,
      displayNameAr: u.displayNameAr,
      email: u.email,
      role: u.role,
      isActive: !u.isActive,
    );
    store.emit(DemoStoreEvent.usersChanged);
    setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${u.displayName} ${u.isActive ? 'deactivated' : 'reactivated'}.',
        ),
      ),
    );
  }
}

String _roleLabel(UserRole r) {
  switch (r) {
    case UserRole.member:
      return 'Member';
    case UserRole.leader:
      return 'Leader';
    case UserRole.admin:
      return 'Admin';
    case UserRole.superAdmin:
      return 'Director General';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Text(
          'No users match the current filters.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.onEdit,
    required this.onToggleActive,
  });

  final User user;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: user.isActive
                ? AppColors.brandBrown
                : AppColors.textSecondary.withValues(alpha: 0.4),
            child: Text(
              _initials(user.displayName),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: user.isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    decoration: user.isActive
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
                Text(
                  user.displayNameAr,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '@${user.username}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 140,
            child: _RoleChip(role: user.role),
          ),
          IconButton(
            icon: Icon(
              user.isActive ? Icons.toggle_on : Icons.toggle_off,
              color: user.isActive
                  ? AppColors.success
                  : AppColors.textSecondary,
              size: 28,
            ),
            tooltip: user.isActive ? 'Deactivate' : 'Reactivate',
            onPressed: onToggleActive,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final List<String> parts = name
        .split(' ')
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final Color c = switch (role) {
      UserRole.member => AppColors.goldOlive,
      UserRole.leader => AppColors.brandBrown,
      UserRole.admin => AppColors.success,
      UserRole.superAdmin => AppColors.outflow,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: const BorderRadius.all(AppRadii.chip),
      ),
      child: Text(
        _roleLabel(role).toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Form for create or edit. Returns true if saved.
class UserFormDialog extends ConsumerStatefulWidget {
  const UserFormDialog({super.key, this.existing});
  final User? existing;

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  static const Uuid _uuid = Uuid();

  late final TextEditingController _username;
  late final TextEditingController _displayName;
  late final TextEditingController _displayNameAr;
  late final TextEditingController _email;
  late UserRole _role;
  late bool _isActive;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final User? u = widget.existing;
    _username = TextEditingController(text: u?.username ?? '');
    _displayName = TextEditingController(text: u?.displayName ?? '');
    _displayNameAr = TextEditingController(text: u?.displayNameAr ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _role = u?.role ?? UserRole.member;
    _isActive = u?.isActive ?? true;
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    _displayNameAr.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.existing != null;
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(
            isEdit ? Icons.edit : Icons.person_add_alt_1,
            color: AppColors.brandBrown,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(isEdit ? 'Edit User' : 'Add User'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _displayName,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  hintText: 'e.g. Ahmed Al Maktoum',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _displayNameAr,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'Display name (Arabic)',
                  hintText: 'أحمد آل مكتوم',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  hintText: 'ahmed.maktoum',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'name@pdd.gov.ae',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<UserRole>>[
                  for (final UserRole r in UserRole.values)
                    DropdownMenuItem<UserRole>(
                      value: r,
                      child: Text(_roleLabel(r)),
                    ),
                ],
                onChanged: (UserRole? v) {
                  if (v != null) setState(() => _role = v);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _isActive,
                onChanged: (bool v) => setState(() => _isActive = v),
                title: const Text('Active'),
                subtitle: const Text(
                  'Inactive users are hidden from trip/chat pickers.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.outflow),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('CANCEL'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.cream,
                  ),
                )
              : const Icon(Icons.check),
          label: Text(isEdit ? 'SAVE' : 'CREATE'),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Future<void> _save() async {
    final String displayName = _displayName.text.trim();
    final String displayNameAr = _displayNameAr.text.trim();
    final String username = _username.text.trim();
    final String email = _email.text.trim();
    setState(() => _error = null);
    if (displayName.isEmpty || username.isEmpty || email.isEmpty) {
      setState(() => _error = 'Display name, username, and email are required.');
      return;
    }
    final DemoStore store = ref.read(demoStoreProvider);
    final bool clash = store.users.any(
      (User u) =>
          u.id != (widget.existing?.id ?? '') &&
          (u.username.toLowerCase() == username.toLowerCase() ||
              u.email.toLowerCase() == email.toLowerCase()),
    );
    if (clash) {
      setState(() => _error = 'Username or email already in use.');
      return;
    }
    setState(() => _saving = true);
    try {
      final User saved = User(
        id: widget.existing?.id ?? 'u-${_uuid.v4().substring(0, 8)}',
        username: username,
        displayName: displayName,
        displayNameAr: displayNameAr.isEmpty ? displayName : displayNameAr,
        email: email,
        role: _role,
        isActive: _isActive,
      );
      final int i = store.users.indexWhere((User u) => u.id == saved.id);
      if (i >= 0) {
        store.users[i] = saved;
      } else {
        store.users.add(saved);
      }
      store.emit(DemoStoreEvent.usersChanged);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
