// lib/widgets/camera_preview_widget.dart
//
// Dynamically fits camera preview to any screen size/aspect ratio.
// Works on phones (16:9, 20:9) and tablets (4:3, 16:10) without distortion.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class AdaptiveCameraPreview extends StatelessWidget {
  final CameraController controller;
  final List<Widget> overlays;

  const AdaptiveCameraPreview({
    super.key,
    required this.controller,
    this.overlays = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.expand(
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(color: Colors.white24),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;

        // Camera's native aspect ratio (e.g. 4:3, 16:9, etc.)
        final camRatio = controller.value.aspectRatio;

        // We want to COVER the screen (like BoxFit.cover)
        // so the preview fills the box without black bars.
        double previewW, previewH;
        if (screenW / screenH > camRatio) {
          // Screen is wider than camera — fit by width
          previewW = screenW;
          previewH = screenW / camRatio;
        } else {
          // Screen is taller than camera — fit by height
          previewH = screenH;
          previewW = screenH * camRatio;
        }

        return ClipRect(
          child: OverflowBox(
            maxWidth:  previewW,
            maxHeight: previewH,
            child: SizedBox(
              width:  previewW,
              height: previewH,
              child: Stack(
                children: [
                  // Camera preview fills the box
                  Positioned.fill(child: CameraPreview(controller)),
                  // Overlays on top (badges, panels, etc.)
                  ...overlays,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}