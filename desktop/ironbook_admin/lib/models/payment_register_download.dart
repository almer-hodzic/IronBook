import 'dart:typed_data';

class PaymentRegisterDownload {
  const PaymentRegisterDownload({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}
