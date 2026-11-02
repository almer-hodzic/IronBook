import 'dart:typed_data';

class PdfDownload {
  const PdfDownload({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}
