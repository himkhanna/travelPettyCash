import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../application/expenses_providers.dart';
import '../data/expense_repository.dart';

/// Out-of-inventory: full-screen receipt viewer. Opened from the "VIEW
/// RECEIPT" button on screen #9. Pinch-to-zoom via [InteractiveViewer].
///
/// Slice 3C — the URL is sourced via [ExpenseRepository.receiptUrl], which
/// the real backend resolves to a presigned URL from
/// `GET /api/v1/expenses/{id}/receipt`. The fake returns a `data:` URL
/// backed by the bytes that the [pendingReceiptUploadsProvider] queue
/// (or the eager online path) put into [DemoStore.receiptBytes].
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
  late Future<String?> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _load();
  }

  Future<String?> _load() {
    return ref.read(expenseRepositoryProvider).receiptUrl(widget.expenseId);
  }

  void _retry() {
    setState(() {
      _urlFuture = _load();
    });
  }

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
      body: FutureBuilder<String?>(
        future: _urlFuture,
        builder: (BuildContext context, AsyncSnapshot<String?> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return _LoadingTile(message: l.receipt_loadingViewer);
          }
          if (snap.hasError) {
            return _ErrorRetry(
              message: l.receipt_viewer_unavailable,
              retryLabel: l.common_retry,
              onRetry: _retry,
            );
          }
          final String? url = snap.data;
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
                errorBuilder: (_, __, ___) => _ErrorRetry(
                  message: l.receipt_viewer_unavailable,
                  retryLabel: l.common_retry,
                  onRetry: _retry,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
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

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
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
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
