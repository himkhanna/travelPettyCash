// ignore_for_file: avoid_web_libraries_in_flutter
// The CMS is a web-only build (`flutter build web --release`). We trigger
// browser downloads by synthesising a temporary <a download="..."> anchor;
// the file-system save dialog is what the user expects in this context.

import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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

/// Share the given bytes as a file via the Web Share API (Level 2,
/// `navigator.share({files})`). On a phone this opens the native share
/// sheet so the user can send the report straight to WhatsApp (BRD §2.6).
///
/// Returns `true` when the share sheet was invoked (including when the user
/// cancels it — an `AbortError` is treated as handled). Returns `false`
/// ONLY when Web Share with files is unsupported here, so the caller can
/// fall back to a plain download.
Future<bool> shareBytes({
  required Uint8List bytes,
  required String filename,
  required String contentType,
  String? text,
  String? title,
}) async {
  final JSObject window = globalContext;
  final JSObject navigator = window.getProperty('navigator'.toJS) as JSObject;

  // Build a JS File from the bytes. The File constructor takes an array of
  // BlobParts; a typed-array (the bytes) is a valid part on its own.
  final JSFunction fileCtor = window.getProperty('File'.toJS) as JSFunction;
  final JSObject options = JSObject()
    ..setProperty('type'.toJS, contentType.toJS);
  final JSObject file = fileCtor.callAsConstructor<JSObject>(
    <JSAny>[bytes.toJS].toJS,
    filename.toJS,
    options,
  );

  final JSObject data = JSObject()
    ..setProperty('files'.toJS, <JSObject>[file].toJS);
  if (title != null) data.setProperty('title'.toJS, title.toJS);
  if (text != null) data.setProperty('text'.toJS, text.toJS);

  // Probe support: navigator.canShare must exist AND accept this payload
  // (canShare with files returns false on desktop / unsupported browsers).
  if (!navigator.hasProperty('canShare'.toJS).toDart) return false;
  final JSAny? canShare =
      navigator.callMethod('canShare'.toJS, data);
  if (!(canShare.isA<JSBoolean>() && (canShare! as JSBoolean).toDart)) {
    return false;
  }

  try {
    final JSPromise<JSAny?> promise =
        navigator.callMethod('share'.toJS, data) as JSPromise<JSAny?>;
    await promise.toDart;
    return true;
  } catch (_) {
    // A thrown AbortError means the user dismissed the share sheet — the
    // request was still handled, so we don't fall back to a download.
    return true;
  }
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
