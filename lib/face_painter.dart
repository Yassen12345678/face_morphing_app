import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize;
  final ui.Image? faceTexture;
  final Face? staticFace;
  final double morphOpacity;

  FacePainter({
    required this.faces,
    required this.absoluteImageSize,
    this.faceTexture,
    this.staticFace,
    required this.morphOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty) return;
    if (absoluteImageSize.width == 0 || absoluteImageSize.height == 0) return;

    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;

    // Optional: Draw bounding box for debugging (currently hidden)
    final Paint debugPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red.withOpacity(0.3);

    for (final liveFace in faces) {
      // --- MODE 1: Standard (No Morph) ---
      if (faceTexture == null || staticFace == null || morphOpacity == 0.0) {
        canvas.drawRect(
          Rect.fromLTRB(
            liveFace.boundingBox.left * scaleX,
            liveFace.boundingBox.top * scaleY,
            liveFace.boundingBox.right * scaleX,
            liveFace.boundingBox.bottom * scaleY,
          ),
          debugPaint,
        );
        continue;
      }

      // --- MODE 2: Stable Morph (Nose Anchor Only) ---

      // 1. Get Face Contour (The Outline)
      final liveContour = liveFace.contours[FaceContourType.face];
      final staticContour = staticFace!.contours[FaceContourType.face];

      // 2. Get Nose Anchor (The Pin)
      final liveNose = liveFace.landmarks[FaceLandmarkType.noseBase];
      final staticNose = staticFace!.landmarks[FaceLandmarkType.noseBase];

      if (liveContour == null || staticContour == null || liveNose == null || staticNose == null) continue;

      final livePoints = liveContour.points;
      final staticPoints = staticContour.points;

      // Match point counts
      int pointCount = math.min(livePoints.length, staticPoints.length);

      List<Offset> positions = [];
      List<Offset> textureCoords = [];
      List<int> indices = [];

      // 3. Build Mesh
      // Center Point = NOSE (Stable)
      positions.add(Offset(
          liveNose.position.x.toDouble() * scaleX,
          liveNose.position.y.toDouble() * scaleY
      ));
      textureCoords.add(Offset(
          staticNose.position.x.toDouble(),
          staticNose.position.y.toDouble()
      ));

      // Edge Points = FACE OUTLINE
      for (int i = 0; i < pointCount; i++) {
        positions.add(Offset(
          livePoints[i].x.toDouble() * scaleX,
          livePoints[i].y.toDouble() * scaleY,
        ));

        textureCoords.add(Offset(
          staticPoints[i].x.toDouble(),
          staticPoints[i].y.toDouble(),
        ));
      }

      // 4. Connect Triangles (Nose -> Edge -> Next Edge)
      // This creates a clean "Fan" shape that never crosses over itself.
      for (int i = 1; i < pointCount; i++) {
        indices.add(0);
        indices.add(i);
        indices.add(i + 1);
      }
      // Close the loop
      indices.add(0);
      indices.add(pointCount);
      indices.add(1);

      // 5. Draw
      final vertices = ui.Vertices(
        ui.VertexMode.triangles,
        positions,
        textureCoordinates: textureCoords,
        indices: indices,
      );

      final Paint meshPaint = Paint()
        ..shader = ui.ImageShader(
          faceTexture!,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          Matrix4.identity().storage,
        )
        ..color = Colors.white.withOpacity(morphOpacity); // Apply slider opacity

      canvas.drawVertices(vertices, BlendMode.srcOver, meshPaint);
    }
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.faceTexture != faceTexture ||
        oldDelegate.morphOpacity != morphOpacity;
  }
}