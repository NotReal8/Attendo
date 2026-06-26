// lib/utils/camera_utils.dart
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class CameraUtils {
  CameraUtils._();

  static Future<Uint8List?> cameraImageToJpeg(CameraImage image) async {
    try {
      if (image.format.group == ImageFormatGroup.jpeg) {
        return image.planes.first.bytes;
      }
      if (image.format.group == ImageFormatGroup.yuv420) {
        final converted = _fromYuv420(image);
        if (converted == null) return null;
        return Uint8List.fromList(img.encodeJpg(converted, quality: 90));
      }
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final converted = _fromBgra8888(image);
        if (converted == null) return null;
        return Uint8List.fromList(img.encodeJpg(converted, quality: 90));
      }
      debugPrint('[CameraUtils] Unsupported format: ${image.format.group}');
      return null;
    } catch (error) {
      debugPrint('[CameraUtils] conversion error: $error');
      return null;
    }
  }

  static img.Image? _fromYuv420(CameraImage image) {
    if (image.planes.length < 3) return null;
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final uvRowStride   = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final result = img.Image(width: width, height: height);

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final yIndex  = row * yPlane.bytesPerRow + col;
        final uvIndex = (row >> 1) * uvRowStride + (col >> 1) * uvPixelStride;

        if (yIndex >= yBytes.length ||
            uvIndex >= uBytes.length ||
            uvIndex >= vBytes.length) continue;

        final yVal = yBytes[yIndex];
        final uVal = uBytes[uvIndex];
        final vVal = vBytes[uvIndex];

        final r = (yVal + 1.402   * (vVal - 128)).round().clamp(0, 255);
        final g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
                      .round()
                      .clamp(0, 255);
        final b = (yVal + 1.772   * (uVal - 128)).round().clamp(0, 255);

        result.setPixelRgba(col, row, r, g, b, 255);
      }
    }
    return result;
  }

  static img.Image? _fromBgra8888(CameraImage image) {
    if (image.planes.isEmpty) return null;
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra,
    );
  }
}