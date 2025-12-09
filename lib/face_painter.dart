import 'dart:math' as math; // Needed for the 'Point' class
import 'dart:ui' as ui;     // Needed for Image, Vertices, and ImageShader
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize;

  // New variables for the Face Swap
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
      // --- MODE 1: Standard Detection (No Face Swap yet) ---
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

      // --- MODE 2: Face Swap (Morphing) ---
      // 1. Get contours (The outline of the face)
      final liveContour = liveFace.contours[FaceContourType.face];
      final staticContour = staticFace!.contours[FaceContourType.face];

      // We need both faces to have the outline detected
      if (liveContour == null || staticContour == null) continue;

      final livePoints = liveContour.points;
      final staticPoints = staticContour.points;

      // Safety check: point counts must match roughly
      final int pointCount = livePoints.length < staticPoints.length
          ? livePoints.length
          : staticPoints.length;

      // 2. Build the Mesh (Vertices)
      // We use a "Triangle Fan" from the center of the face

      // Calculate Centers using the helper function
      Offset liveCenter = _getCentroid(livePoints);
      Offset staticCenter = _getCentroid(staticPoints);

      // Adjust live center to screen coordinates
      liveCenter = Offset(liveCenter.dx * scaleX, liveCenter.dy * scaleY);

      List<Offset> positions = [];     // Where to draw on screen (Live)
      List<Offset> textureCoords = []; // Where to pick color from (Static)
      List<int> indices = [];          // How to connect dots to make triangles

      // Add the center point first (Index 0)
      positions.add(liveCenter);
      textureCoords.add(staticCenter);

      // Add the contour points
      for (int i = 0; i < pointCount; i++) {
        // Map Live Point to Screen
        positions.add(Offset(
          livePoints[i].x.toDouble() * scaleX,
          livePoints[i].y.toDouble() * scaleY,
        ));

        // Map Static Point to Texture
        // Note: Texture coordinates are raw pixels on the original image, no scaling needed
        textureCoords.add(Offset(
          staticPoints[i].x.toDouble(),
          staticPoints[i].y.toDouble(),
        ));
      }

      // Create Triangles (Connect Center -> Point i -> Point i+1)
      for (int i = 1; i < pointCount; i++) {
        indices.add(0);     // Center
        indices.add(i);     // Current Point
        indices.add(i + 1); // Next Point
      }
      // Close the loop (Last point -> First point)
      indices.add(0);
      indices.add(pointCount);
      indices.add(1);

      // 3. Draw the Warped Mesh using dart:ui Vertices
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

  // Helper to find the center of a list of points
  Offset _getCentroid(List<math.Point<int>> points) {
    double sumX = 0;
    double sumY = 0;
    for (var p in points) {
      sumX += p.x;
      sumY += p.y;
    }
    return Offset(sumX / points.length, sumY / points.length);
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.faces != faces || oldDelegate.faceTexture != faceTexture;
  }
}