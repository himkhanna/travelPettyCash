import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';
import '../domain/expense.dart';

/// Out-of-inventory: full-screen receipt viewer. Opened from the "VIEW
/// RECEIPT" button on screen #9. Pinch-to-zoom via [InteractiveViewer].
///
/// The receipt URL is sourced from `expense.receiptObjectKey`. In production
/// this is an S3 object key that the backend resolves into a signed URL via
/// `GET /expenses/:id/receipt`. The fake repo returns either a `blob:` URL
/// (image_picker on web) or a placeholder asset key.
class ReceiptViewerScreen extends ConsumerStatefulWidget {
  const ReceiptViewerScreen({
    super.key,
    required this.tripId,
    required this.expenseId,
  });

  final String tripId;
  final String expenseId;

  @override
  ConsumerState<ReceiptViewerScreen> createState() =>
      _ReceiptViewerScreenState();
}

class _ReceiptViewerScreenState extends ConsumerState<ReceiptViewerScreen> {
  late final Future<Expense> _expenseFuture =
      ref.read(expenseRepositoryProvider).byId(widget.expenseId);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go(
            '/m/trips/${widget.tripId}/expenses/${widget.expenseId}',
          ),
        ),
        title: Text(l.receipt_viewer_title),
      ),
      body: FutureBuilder<Expense>(
        future: _expenseFuture,
        builder: (BuildContext context, AsyncSnapshot<Expense> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          if (snap.hasError || !snap.hasData) {
            return _Unavailable(message: l.receipt_viewer_unavailable);
          }
          final String? url = signedReceiptUrl(snap.data!);
          if (url == null) {
            return _Unavailable(message: l.receipt_viewer_unavailable);
          }
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    _Unavailable(message: l.receipt_viewer_unavailable),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Returns a viewable URL for the receipt attached to [expense], or null when
/// the expense has no receipt at all. In production this hits the
/// `GET /expenses/:id/receipt` endpoint and returns a signed URL; the demo
/// echoes the locally-attached `blob:` URL from image_picker, or the asset
/// path for seed expenses.
String? signedReceiptUrl(Expense expense) {
  final String? key = expense.receiptObjectKey;
  if (key == null || key.isEmpty) return null;
  if (key.startsWith('blob:') || key.startsWith('http')) return key;
  // Seed receipts ship under assets/demo/receipts/. They aren't fetchable via
  // Image.network in production, but on web the asset path works as a
  // relative URL when the app is served from the same origin.
  if (key.startsWith('assets/')) return key;
  // Stub: pretend we hit a signed-URL endpoint.
  return 'https://demo.invalid/$key';
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
