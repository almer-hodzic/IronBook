import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/payment_register_download.dart';

class PaymentRegisterFileException implements Exception {
  const PaymentRegisterFileException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Native file operations are separate from the API and injectable in UI tests.
class PaymentRegisterFileService {
  const PaymentRegisterFileService();

  Future<String?> save(PaymentRegisterDownload download) async {
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
      throw const PaymentRegisterFileException(
        'The PDF could not be saved. Check the destination and try again.',
      );
    }
  }

  Future<void> open(String path) async {
    try {
      if (!await File(path).exists() || !await launchUrl(Uri.file(path))) {
        throw const PaymentRegisterFileException('Unable to open PDF.');
      }
    } catch (_) {
      throw const PaymentRegisterFileException(
        'The PDF could not be opened. Open the saved file with a PDF viewer.',
      );
    }
  }
}
