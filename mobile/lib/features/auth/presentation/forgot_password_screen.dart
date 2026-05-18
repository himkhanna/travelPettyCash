import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Out-of-inventory companion to screen #1. The real password reset flow
/// waits on the identity provider decision (CLAUDE.md §16). For v1 we route
/// users to PDD IT — see screen-inventory.md "Forgot Password screen".
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.brandBrownDark,
      appBar: AppBar(
        backgroundColor: AppColors.brandBrownDark,
        foregroundColor: AppColors.cream,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/login'),
        ),
        title: Text(l.auth_forgot_title),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.cream.withValues(alpha: 0.08),
                        border: Border.all(color: AppColors.goldOlive),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.support_agent_outlined,
                        color: AppColors.goldOlive,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l.auth_forgot_title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.cream,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l.auth_forgot_body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.cream.withValues(alpha: 0.85),
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SelectableText(
                    l.auth_forgot_contact,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.goldOlive,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  OutlinedButton(
                    onPressed: () => context.go('/login'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.cream,
                      side: const BorderSide(color: AppColors.cream),
                    ),
                    child: Text(l.common_back),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
