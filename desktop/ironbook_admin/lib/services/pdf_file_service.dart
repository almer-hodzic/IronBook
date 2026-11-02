import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pdf_download.dart';

class PdfFileException implements Exception {
  const PdfFileException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Native file operations are separate from the API and injectable in UI tests.
class PdfFileService {
  const PdfFileService();

  Future<String?> save(PdfDownload download) async {
    try {
      final location = await getSaveLocation(
        suggestedName: download.fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF document', extensions: ['pdf']),
        ],
      );
      if (location == null) return null;
      await File(location.path).writeAsBytes(download.bytes, flush: true);
      return location.path;
    } catch (_) {
      throw const PdfFileException(
        'The PDF could not be saved. Check the destination and try again.',
      );
    }
  }

  Future<void> open(String path) async {
    try {
      if (!await File(path).exists() || !await launchUrl(Uri.file(path))) {
        throw const PdfFileException('Unable to open PDF.');
      }
    } catch (_) {
      throw const PdfFileException(
        'The PDF could not be opened. Open the saved file with a PDF viewer.',
      );
    }
  }
}
