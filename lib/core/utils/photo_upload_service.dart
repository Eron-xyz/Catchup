import 'dart:convert';
import 'package:catchup/core/utils/performance_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Top-level isolate worker function for `compute()` so image decoding,
/// resizing, and JPEG encoding never block the UI frame rate.
Uint8List _compressImageInIsolate(
  ({Uint8List rawBytes, int maxDimension, int quality}) args,
) {
  final decoded = img.decodeImage(args.rawBytes);
  if (decoded == null) return args.rawBytes;

  img.Image resized = decoded;
  if (decoded.width > args.maxDimension || decoded.height > args.maxDimension) {
    resized = decoded.width >= decoded.height
        ? img.copyResize(
            decoded,
            width: args.maxDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            decoded,
            height: args.maxDimension,
            interpolation: img.Interpolation.average,
          );
  }
  return Uint8List.fromList(img.encodeJpg(resized, quality: args.quality));
}

/// Handles product photo selection, background isolate compression,
/// and CDN-cached Firebase Storage upload across Web and Android.
class PhotoUploadService {
  static final ImagePicker _picker = ImagePicker();

  /// Returns true when running on a native Android device where the camera is available.
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Picks an image (from gallery/files on Web & Android, or camera on Android)
  /// and compresses it in a background isolate to max 640px & JPEG quality 70.
  static Future<Uint8List?> pickAndCompressImage({
    bool fromCamera = false,
  }) async {
    Uint8List? rawBytes;

    if (kIsWeb) {
      final files = await FilePicker.pickFiles(type: FileType.image);
      if (files.isNotEmpty) {
        rawBytes = await files.first.xFile.readAsBytes();
      }
    } else {
      final XFile? file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 640,
        maxHeight: 640,
        imageQuality: 70,
      );
      if (file != null) {
        rawBytes = await file.readAsBytes();
      }
    }

    if (rawBytes == null) return null;
    return compressImageBytes(rawBytes);
  }

  /// Compresses raw image bytes down to max 640px & JPEG quality 70 off the UI thread.
  static Future<Uint8List> compressImageBytes(
    Uint8List bytes, {
    int maxDimension = 640,
    int quality = 70,
  }) async {
    try {
      return await compute(
        _compressImageInIsolate,
        (rawBytes: bytes, maxDimension: maxDimension, quality: quality),
      );
    } catch (_) {
      return bytes;
    }
  }

  /// Uploads compressed JPEG bytes to `products/{productId}/photo.jpg` in
  /// Firebase Storage with immutable 1-year CDN Cache-Control headers.
  static Future<String> uploadProductPhoto({
    required String productId,
    required Uint8List imageBytes,
  }) async {
    final ref = FirestoreConnectionPool.instance.storage
        .ref()
        .child('products')
        .child(productId)
        .child('photo.jpg');

    await ref.putData(
      imageBytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=31536000, immutable',
      ),
    );
    final url = await ref.getDownloadURL();
    ApiResponseCache.instance.set<String>('photo_url_$productId', url);
    return url;
  }

  /// Encodes compressed bytes as a data URL for local preview mode when Firebase
  /// Storage has not yet been configured.
  static String toDataUrl(Uint8List bytes) {
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  }
}
