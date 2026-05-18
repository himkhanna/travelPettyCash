import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/api/api_error.dart';
import '../../../core/fake/demo_store.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/user_directory_providers.dart';
import '../../auth/domain/user.dart';
import 'widgets/cms_layout.dart';

/// Updates the DemoStore name-lookup cache so other screens calling
/// `store.userById(...)` for chips and headers pick up the new display name
/// without a re-hydration. The authoritative list comes from
/// `usersDirectoryProvider`; this is purely a denormalised lookup cache.
void _upsertUserCache(WidgetRef ref, User user) {
  final DemoStore store = ref.read(demoStoreProvider);
  final int i = store.users.indexWhere((User u) => u.id == user.id);
  if (i >= 0) {
    store.users[i] = user;
  } else {
    store.users.add(user);
  }
}

/// Admin-only Users management screen. Lists every user with their role
/// + status, lets the admin create new users, edit existing ones, and
/// deactivate without deleting (history preservation per CLAUDE.md §12).
class CmsUsersScreen extends ConsumerWidget {
  const CmsUsersScreen({super.key});

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
      // Members and Leaders shouldn't even reach this route, but guard for it.
      return const CmsLayout(
        active: CmsNavItem.users,
        child: Center(child: Text('You do not have access to this page.')),
      );
    }

    final AsyncValue<List<User>> usersAsync =
        ref.watch(usersDirectoryProvider);

    return CmsLayout(
      active: CmsNavItem.users,
      floatingActionButton: me.role == UserRole.admin
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.brandBrown,
              foregroundColor: AppColors.cream,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('CREATE USER'),
              onPressed: () => _openCreate(context, ref),
            )
          : null,
      child: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, _) => Center(child: Text('Error: $e')),
        data: (List<User> users) {
          final List<User> sorted = <User>[...users]
            ..sort((User a, User b) => a.displayName.compareTo(b.displayName));
          return _UsersTable(users: sorted, me: me, canEdit: me.role == UserRole.admin);
        },
      ),
    );
  }

  Future<void> _openCreate(BuildContext context, WidgetRef ref) async {
    final bool? created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) => const CreateUserDialog(),
    );
    if (created == true) {
      ref.invalidate(usersDirectoryProvider);
    }
  }
}

class _UsersTable extends ConsumerWidget {
  const _UsersTable({
    required this.users,
    required this.me,
    required this.canEdit,
  });

  final List<User> users;
  final User me;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: const BorderRadius.all(AppRadii.card),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: <Widget>[
            // Header
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.vertical(top: AppRadii.card),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: Text(_h('Name'), style: _headerStyle(context)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_h('Username'), style: _headerStyle(context)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(_h('Email'), style: _headerStyle(context)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_h('Role'), style: _headerStyle(context)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(_h('Status'), style: _headerStyle(context)),
                  ),
                  if (canEdit) const SizedBox(width: 40),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: users.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (BuildContext context, int i) {
                  final User u = users[i];
                  return _UserRow(
                    user: u,
                    isSelf: u.id == me.id,
                    canEdit: canEdit,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _h(String t) => t.toUpperCase();
  TextStyle _headerStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall!.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      );
}

class _UserRow extends ConsumerWidget {
  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.canEdit,
  });

  final User user;
  final bool isSelf;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _avatarColor(user.role),
                  child: Text(
                    _initials(user.displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    user.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelf) ...<Widget>[
                  const SizedBox(width: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.goldOlive.withValues(alpha: 0.2),
                      borderRadius: const BorderRadius.all(AppRadii.chip),
                    ),
                    child: const Text(
                      'you',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.goldOlive,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              user.username,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              user.email,
              style: const TextStyle(color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 2, child: _RoleChip(role: user.role)),
          Expanded(flex: 2, child: _StatusBadge(active: user.isActive)),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit user',
              onPressed: () => _openEdit(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, WidgetRef ref) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext _) =>
          EditUserDialog(user: user, isSelf: isSelf),
    );
    if (saved == true) {
      ref.invalidate(usersDirectoryProvider);
    }
  }

  String _initials(String name) {
    final List<String> parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Color _avatarColor(UserRole r) {
    switch (r) {
      case UserRole.admin:
        return AppColors.brandBrown;
      case UserRole.superAdmin:
        return AppColors.goldOlive;
      case UserRole.leader:
        return AppColors.brandBrown;
      case UserRole.member:
        return AppColors.textSecondary;
    }
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color) = switch (role) {
      UserRole.superAdmin => ('Director General', AppColors.goldOlive),
      UserRole.admin => ('Admin', AppColors.brandBrown),
      UserRole.leader => ('Leader', AppColors.brandBrown),
      UserRole.member => ('Member', AppColors.textSecondary),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: const BorderRadius.all(AppRadii.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.success : AppColors.outflow;
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'Active' : 'Inactive',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Create dialog
// ============================================================================

class CreateUserDialog extends ConsumerStatefulWidget {
  const CreateUserDialog({super.key});

  @override
  ConsumerState<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<CreateUserDialog> {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _nameArCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  UserRole _role = UserRole.member;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nameCtrl.dispose();
    _nameArCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _UserDialogShell(
      title: 'Create User',
      saving: _saving,
      error: _error,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _formField(
            label: 'Username',
            controller: _usernameCtrl,
            hint: 'lowercase, e.g. "aalmaktoum"',
          ),
          const SizedBox(height: AppSpacing.md),
          _formField(label: 'Display name', controller: _nameCtrl),
          const SizedBox(height: AppSpacing.md),
          _formField(label: 'Display name (Arabic)', controller: _nameArCtrl),
          const SizedBox(height: AppSpacing.md),
          _formField(label: 'Email', controller: _emailCtrl),
          const SizedBox(height: AppSpacing.md),
          _formField(
            label: 'Temporary password',
            controller: _passwordCtrl,
            obscure: true,
            hint: 'At least 8 characters',
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'ROLE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RolePicker(
            selected: _role,
            onSelected: (UserRole r) => setState(() => _role = r),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_usernameCtrl.text.trim().isEmpty ||
          _nameCtrl.text.trim().isEmpty ||
          _nameArCtrl.text.trim().isEmpty ||
          _emailCtrl.text.trim().isEmpty ||
          _passwordCtrl.text.length < 8) {
        throw const FormatException(
          'All fields are required. Password must be at least 8 characters.',
        );
      }
      final User created =
          await ref.read(userDirectoryRepositoryProvider).create(
                username: _usernameCtrl.text.trim().toLowerCase(),
                displayName: _nameCtrl.text.trim(),
                displayNameAr: _nameArCtrl.text.trim(),
                email: _emailCtrl.text.trim(),
                role: _role,
                password: _passwordCtrl.text,
              );
      // Push into DemoStore *only* as a name-lookup cache for callers like
      // store.userById in chips/headers. The list itself comes back from the
      // server via usersDirectoryProvider invalidation in the parent.
      _upsertUserCache(ref, created);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      setState(() {
        _error = e.detail;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }
}

// ============================================================================
// Edit dialog
// ============================================================================

class EditUserDialog extends ConsumerStatefulWidget {
  const EditUserDialog({
    super.key,
    required this.user,
    required this.isSelf,
  });

  final User user;
  final bool isSelf;

  @override
  ConsumerState<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<EditUserDialog> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.user.displayName);
  late final TextEditingController _nameArCtrl =
      TextEditingController(text: widget.user.displayNameAr);
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.user.email);
  final TextEditingController _passwordCtrl = TextEditingController();
  late UserRole _role = widget.user.role;
  late bool _active = widget.user.isActive;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameArCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _UserDialogShell(
      title: 'Edit ${widget.user.displayName}',
      saving: _saving,
      error: _error,
      onCancel: () => Navigator.of(context).pop(false),
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: const BorderRadius.all(AppRadii.chip),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.alternate_email,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  widget.user.username,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  'Username is immutable',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _formField(label: 'Display name', controller: _nameCtrl),
          const SizedBox(height: AppSpacing.md),
          _formField(label: 'Display name (Arabic)', controller: _nameArCtrl),
          const SizedBox(height: AppSpacing.md),
          _formField(label: 'Email', controller: _emailCtrl),
          const SizedBox(height: AppSpacing.md),
          _formField(
            label: 'New password',
            controller: _passwordCtrl,
            obscure: true,
            hint: 'Leave blank to keep current',
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'ROLE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RolePicker(
            selected: _role,
            onSelected: widget.isSelf
                ? null
                : (UserRole r) => setState(() => _role = r),
          ),
          if (widget.isSelf) ...<Widget>[
            const SizedBox(height: 4),
            const Text(
              'You cannot change your own role.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Account active'),
            subtitle: Text(
              widget.isSelf
                  ? 'You cannot deactivate your own account.'
                  : _active
                      ? 'User can sign in and act on this trip.'
                      : 'User is locked out and hidden from new assignments.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            value: _active,
            onChanged: widget.isSelf
                ? null
                : (bool v) => setState(() => _active = v),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final User updated =
          await ref.read(userDirectoryRepositoryProvider).update(
                id: widget.user.id,
                displayName: _nameCtrl.text.trim() == widget.user.displayName
                    ? null
                    : _nameCtrl.text.trim(),
                displayNameAr:
                    _nameArCtrl.text.trim() == widget.user.displayNameAr
                        ? null
                        : _nameArCtrl.text.trim(),
                email: _emailCtrl.text.trim() == widget.user.email
                    ? null
                    : _emailCtrl.text.trim(),
                role: widget.isSelf || _role == widget.user.role ? null : _role,
                active: widget.isSelf || _active == widget.user.isActive
                    ? null
                    : _active,
                password: _passwordCtrl.text.isEmpty ? null : _passwordCtrl.text,
              );
      // Update the DemoStore name-lookup cache so chips/headers everywhere
      // pick up the new display name. The authoritative list still comes
      // from usersDirectoryProvider once the parent invalidates it.
      _upsertUserCache(ref, updated);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      setState(() {
        _error = e.detail;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }
}

// ============================================================================
// Shared bits
// ============================================================================

class _UserDialogShell extends StatelessWidget {
  const _UserDialogShell({
    required this.title,
    required this.saving,
    required this.error,
    required this.onCancel,
    required this.onSave,
    required this.child,
  });

  final String title;
  final bool saving;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.person_outline, color: AppColors.brandBrown),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: saving ? null : onCancel,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: child,
              ),
            ),
            if (error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.outflow.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.all(AppRadii.chip),
                  border: Border.all(
                    color: AppColors.outflow.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline,
                        size: 18, color: AppColors.outflow),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(color: AppColors.outflow),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: saving ? null : onCancel,
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBrown,
                    ),
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.cream,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: const Text(
                      'SAVE',
                      style: TextStyle(
                        color: AppColors.cream,
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
}

class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.selected, required this.onSelected});

  final UserRole selected;
  final ValueChanged<UserRole>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: <Widget>[
        for (final UserRole r in <UserRole>[
          UserRole.member,
          UserRole.leader,
          UserRole.admin,
          UserRole.superAdmin,
        ])
          ChoiceChip(
            label: Text(_label(r)),
            selected: selected == r,
            onSelected: onSelected == null ? null : (_) => onSelected!(r),
          ),
      ],
    );
  }

  String _label(UserRole r) {
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
}

Widget _formField({
  required String label,
  required TextEditingController controller,
  String? hint,
  bool obscure = false,
}) {
  return TextField(
    controller: controller,
    obscureText: obscure,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );
}
