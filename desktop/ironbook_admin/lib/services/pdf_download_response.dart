import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/pdf_download.dart';

/// The same binary/filename rules for both backend-generated registers.
PdfDownload parsePdfDownload(
  http.Response response, {
  required String fallbackFileName,
}) {
  final bytes = response.bodyBytes;
  if (response.headers['content-type']?.split(';').first.trim().toLowerCase() !=
          'application/pdf' ||
      bytes.length < 5 ||
      ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
    throw const FormatException(
      'The API did not return a valid PDF. Please retry.',
    );
  }
  return PdfDownload(
    bytes: bytes,
    fileName: _pdfFileName(
      response.headers['content-disposition'],
      fallbackFileName,
    ),
  );
}

String _pdfFileName(String? header, String fallback) {
  if (header == null) return fallback;
  String? name;
  final extended = RegExp(
    r"(?:^|;)\s*filename\*\s*=\s*UTF-8''([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);
  if (extended != null) {
    try {
      name = Uri.decodeComponent(extended.group(1)!.trim());
    } on FormatException {
      /* Try the ordinary filename instead. */
    } on ArgumentError {
      /* Invalid percent encoding: try the ordinary filename instead. */
    }
  }
  name ??= RegExp(
    r'(?:^|;)\s*filename\s*=\s*(?:"([^"]*)"|([^;]+))',
    caseSensitive: false,
  ).firstMatch(header)?.groups([1, 2]).whereType<String>().firstOrNull;
  name = name?.trim();
  if (name == null ||
      name.length > 180 ||
      name.toLowerCase() == '.pdf' ||
      !name.toLowerCase().endsWith('.pdf') ||
      RegExp(r'[\\/:*?"<>|\x00-\x1f]').hasMatch(name)) {
    return fallback;
  }
  return name;
}
