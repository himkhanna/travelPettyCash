import 'dart:typed_data';

/// Native fallback — file save lands in a follow-up slice via
/// path_provider + open_file.
void triggerBrowserDownload(Uint8List bytes, String name, String mime) {}
