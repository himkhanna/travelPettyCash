import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/signature_providers.dart';
import '../domain/signature_service.dart';

/// Modal that mimics releasing a hardware-backed signing key.
///
/// Demo behaviour: biometric succeeds immediately, PIN requires 4+ digits.
/// In production the same widget is driven by a real PKCS#11 / biometric
/// flow (CLAUDE.md §10) — only the [SignatureService] implementation changes.
class SignReportModal extends ConsumerStatefulWidget {
  const SignReportModal({
    super.key,
    required this.tripId,
    required this.reportKind,
  });

  final String tripId;
  final String reportKind;

  @override
  ConsumerState<SignReportModal> createState() => _SignReportModalState();
}

class _SignReportModalState extends ConsumerState<SignReportModal> {
  SigningMethod _method = SigningMethod.biometric;
  final TextEditingController _pinCtrl = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final AppLocalizations l = AppLocalizations.of(context);
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    final SignerCredentials creds = _method == SigningMethod.biometric
        ? const SignerCredentials.biometric()
        : SignerCredentials.pin(_pinCtrl.text.trim());

    final SignatureResult result = await ref
        .read(signatureServiceProvider)
        .sign(
          tripId: widget.tripId,
          reportKind: widget.reportKind,
          credentials: creds,
        );

    if (!mounted) return;

    switch (result) {
      case SignatureSuccess():
        Navigator.of(context).pop(true);
      case SignatureFailure(:final SignatureFailureCode code):
        setState(() {
          _submitting = false;
          _errorMessage = code == SignatureFailureCode.invalidPin
              ? l.reports_sign_error_pin
              : l.reports_sign_error_generic;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(AppRadii.card),
      ),
      title: Row(
        children: <Widget>[
          const Icon(Icons.fingerprint, color: AppColors.brandBrown),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(l.reports_signing_modal_title)),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.reports_signing_modal_intro,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<SigningMethod>(
              groupValue: _method,
              onChanged: (SigningMethod? v) {
                if (_submitting || v == null) return;
                setState(() => _method = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RadioListTile<SigningMethod>(
                    value: SigningMethod.biometric,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.reports_signing_method_biometric),
                  ),
                  RadioListTile<SigningMethod>(
                    value: SigningMethod.pin,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.reports_signing_method_pin),
                  ),
                ],
              ),
            ),
            if (_method == SigningMethod.pin) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _pinCtrl,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 8,
                decoration: InputDecoration(
                  hintText: l.reports_signing_pin_hint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  counterText: '',
                ),
              ),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.outflow,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(l.reports_signing_cancel),
        ),
        FilledButton.icon(
          icon: _submitting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.draw_outlined, size: 18),
          label: Text(l.reports_signing_submit),
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
