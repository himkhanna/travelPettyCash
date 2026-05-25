// ignore_for_file: avoid_web_libraries_in_flutter
// The CMS is a web-only build (`flutter build web --release`). We trigger
// browser downloads by synthesising a temporary <a download="..."> anchor;
// the file-system save dialog is what the user expects in this context.

import 'dart:html' as html;
import 'dart:typed_data';

/// Trigger a browser "Save as…" prompt for the given bytes.
///
/// Implemented with a Blob URL and a synthetic anchor click. The blob is
/// revoked after the click so we don't leak the object URL.
void saveBytesToDisk({
  required Uint8List bytes,
  required String filename,
  String contentType = 'application/octet-stream',
}) {
  final html.Blob blob = html.Blob(<dynamic>[bytes], contentType);
  final String url = html.Url.createObjectUrlFromBlob(blob);
  final html.AnchorElement anchor = html.AnchorElement(href: url)
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  // 30s is enough for the browser to start the download. Revoking
  // synchronously inside the same task sometimes cancels Chrome's save
  // dialog mid-prompt.
  Future<void>.delayed(const Duration(seconds: 30), () {
    html.Url.revokeObjectUrl(url);
  });
}

/// Open a presigned URL (e.g. MinIO receipt link) in a new tab — used for
/// the "view receipt" affordance on admin expense rows.
void openUrl(String url) {
  html.window.open(url, '_blank');
}

/// Trigger the browser's print dialog — used for the Reports dashboard
/// "Export as PDF" action. The user picks "Save as PDF" in the print
/// dialog; we don't render the PDF ourselves.
void browserPrint() {
  html.window.print();
}
