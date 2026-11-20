import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class AdminImageHelper {
  static final ImagePicker _picker = ImagePicker();

  /// Pick an image from Gallery/Camera and compress to < 80KB Base64 data URI
  static Future<String?> pickAndCompressBase64({
    ImageSource source = ImageSource.gallery,
    int targetWidth = 300,
  }) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 400,
        maxHeight: 400,
      );
      if (file == null) return null;
      final Uint8List rawBytes = await file.readAsBytes();
      Uint8List compressed = await _compressBytes(rawBytes, targetWidth: targetWidth);
      if (compressed.lengthInBytes > 85000) {
        compressed = await _compressBytes(compressed, targetWidth: 200);
      }
      return 'data:image/jpeg;base64,${base64Encode(compressed)}';
    } catch (e) {
      debugPrint('Admin image pick error: $e');
      return null;
    }
  }

  static Future<Uint8List> _compressBytes(Uint8List rawBytes, {int targetWidth = 300}) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(rawBytes, targetWidth: targetWidth);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ByteData? byteData = await frameInfo.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Compression fallback: $e');
    }
    return rawBytes;
  }

  /// Renders either HTTP URL, Base64 data URI, or fallback widget
  static Widget buildImage(
    String imgStr, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget? fallback,
  }) {
    final trimmed = imgStr.trim();
    final fb = fallback ?? const Icon(Icons.image_outlined, color: Colors.grey);

    if (trimmed.isEmpty) return fb;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => fb,
      );
    }

    if (trimmed.startsWith('data:image') || trimmed.length > 40) {
      try {
        final clean = trimmed.contains(',') ? trimmed.split(',').last : trimmed;
        final bytes = base64Decode(clean.trim());
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => fb,
        );
      } catch (_) {
        return fb;
      }
    }

    // Emoji string
    return Center(
      child: Text(
        trimmed,
        style: const TextStyle(fontSize: 22),
      ),
    );
  }
}
