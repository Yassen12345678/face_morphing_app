import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize;
  final ui.Image? faceTexture;     // The loaded static image
  final Face? staticFace;          // The landmarks of the static face

  FacePainter({
    required this.faces,
    required this.absoluteImageSize,
    this.faceTexture,
    this.staticFace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty) return;
    if (absoluteImageSize.width == 0 || absoluteImageSize.height == 0) return;

    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    for (final liveFace in faces) {
      // --- MODE 1: Standard Detection (Red Box) ---
      if (faceTexture == null || staticFace == null) {
        canvas.drawRect(
          Rect.fromLTRB(
            liveFace.boundingBox.left * scaleX,
            liveFace.boundingBox.top * scaleY,
            liveFace.boundingBox.right * scaleX,
            liveFace.boundingBox.bottom * scaleY,
          ),
          paint,
        );
        continue;
      }

      // --- MODE 2: Face Swap (Anchored Mesh) ---

      // 1. Get the Key Contours
      // We grab the face oval AND the nose bridge to find a stable center
      final liveContour = liveFace.contours[FaceContourType.face];
      final staticContour = staticFace!.contours[FaceContourType.face];

      // We use the Nose Base as the "Anchor" so the face doesn't float
      final liveNose = liveFace.landmarks[FaceLandmarkType.noseBase];
      final staticNose = staticFace!.landmarks[FaceLandmarkType.noseBase];

      if (liveContour == null || staticContour == null || liveNose == null || staticNose == null) continue;

      final livePoints = liveContour.points;
      final staticPoints = staticContour.points;

      // 2. Prepare Data Lists
      List<Offset> positions = [];     // Screen coordinates (Live)
      List<Offset> textureCoords = []; // Texture coordinates (Static)
      List<int> indices = [];          // Triangle connections

      // 3. Add the ANCHOR Point (The Nose) at Index 0
      // This pins the texture to your nose, preventing sliding
      positions.add(Offset(
        liveNose.position.x.toDouble() * scaleX,
        liveNose.position.y.toDouble() * scaleY,
      ));

      textureCoords.add(Offset(
        staticNose.position.x.toDouble(),
        staticNose.position.y.toDouble(),
      ));

      // 4. Add the Face Contour Points
      // We use the smaller count to avoid crashes if one face is detected differently
      final int pointCount = math.min(livePoints.length, staticPoints.length);

      for (int i = 0; i < pointCount; i++) {
        // Live Point (Scaled to screen)
        positions.add(Offset(
          livePoints[i].x.toDouble() * scaleX,
          livePoints[i].y.toDouble() * scaleY,
        ));

        // Static Point (Raw pixels)
        textureCoords.add(Offset(
          staticPoints[i].x.toDouble(),
          staticPoints[i].y.toDouble(),
        ));
      }

      // 5. Build the Mesh (Triangle Fan)
      // Connect: Nose(0) -> ContourPoint(i) -> ContourPoint(i+1)
      // This stretches the skin from your nose to the edge of your face
      for (int i = 1; i < pointCount; i++) {
        indices.add(0);     // Nose Anchor
        indices.add(i);     // Current Edge Point
        indices.add(i + 1); // Next Edge Point
      }

      // Close the loop (Connect last point back to first point)
      indices.add(0);
      indices.add(pointCount);
      indices.add(1);

      // 6. Draw
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
        );

      canvas.drawVertices(vertices, BlendMode.srcOver, meshPaint);
    }
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.faces != faces || oldDelegate.faceTexture != faceTexture;
  }
}