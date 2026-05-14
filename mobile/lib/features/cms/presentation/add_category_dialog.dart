import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../expenses/application/expenses_providers.dart';

/// Admin-only — admin can extend the category list (CLAUDE.md §5 — categories
/// are addable by Admin).
class AddCategoryDialog extends ConsumerStatefulWidget {
  const AddCategoryDialog({super.key});

  @override
  ConsumerState<AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<AddCategoryDialog> {
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _enCtrl = TextEditingController();
  final TextEditingController _arCtrl = TextEditingController();
  String _iconKey = 'dots';
  bool _saving = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _enCtrl.dispose();
    _arCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.category_outlined),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Add Expense Category',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _codeCtrl,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z_]')),
                ],
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'CODE (UPPERCASE)',
                  hintText: 'FUEL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _enCtrl,
                decoration: const InputDecoration(
                  labelText: 'English label',
                  hintText: 'Fuel',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _arCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'Arabic label',
                  hintText: 'وقود',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _iconKey,
                decoration: const InputDecoration(
                  labelText: 'Icon',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'dots', child: Text('• Generic')),
                  DropdownMenuItem(value: 'cutlery', child: Text('🍽 Cutlery')),
                  DropdownMenuItem(value: 'car', child: Text('🚗 Car')),
                  DropdownMenuItem(value: 'bed', child: Text('🛏 Bed')),
                  DropdownMenuItem(value: 'phone', child: Text('📱 Phone')),
                  DropdownMenuItem(value: 'ticket', child: Text('🎟 Ticket')),
                  DropdownMenuItem(value: 'coin', child: Text('💰 Coin')),
                  DropdownMenuItem(value: 'plane', child: Text('✈ Plane')),
                ],
                onChanged: (String? v) {
                  if (v != null) setState(() => _iconKey = v);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
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
                    label: const Text('ADD CATEGORY'),
                    onPressed: _saving ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final String code = _codeCtrl.text.trim();
    final String en = _enCtrl.text.trim();
    final String ar = _arCtrl.text.trim();
    if (code.isEmpty || en.isEmpty || ar.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('All fields are required.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(categoryRepositoryProvider)
          .create(code: code, nameEn: en, nameAr: ar, iconKey: _iconKey);
      ref.invalidate(categoriesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added category "$en".')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
