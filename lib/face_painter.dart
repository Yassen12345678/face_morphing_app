import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'animal_data.dart'; // Ensure this import exists



class FacePainter extends CustomPainter {

  final List<Face> faces;

  final Size absoluteImageSize;

  final ui.Image? faceTexture;

  final Face? staticFace; // Logic 1 Trigger (Phone Image)

  final AnimalData? manualAnimal; // Logic 2 Trigger (Animal Icon)

  final double morphOpacity;



  FacePainter({

    required this.faces,

    required this.absoluteImageSize,

    this.faceTexture,

    this.staticFace,

    this.manualAnimal,

    required this.morphOpacity,

  });



  @override

  void paint(Canvas canvas, Size size) {

    if (faces.isEmpty || absoluteImageSize.width == 0 || absoluteImageSize.height == 0) return;



    final double scaleX = size.width / absoluteImageSize.width;

    final double scaleY = size.height / absoluteImageSize.height;



// Helper paint for debugging (optional)

    final Paint debugPaint = Paint()

      ..style = PaintingStyle.stroke

      ..strokeWidth = 2.0

      ..color = Colors.red.withOpacity(0.3);



    for (final liveFace in faces) {



// ==============================================================

// SCENARIO 1: IMAGE FROM PHONE (Human to Human Morph)

// ==============================================================

      if (staticFace != null && faceTexture != null) {



// 1. Get Contours & Noses

        final liveContour = liveFace.contours[FaceContourType.face];

        final staticContour = staticFace!.contours[FaceContourType.face];

        final liveNose = liveFace.landmarks[FaceLandmarkType.noseBase];

        final staticNose = staticFace!.landmarks[FaceLandmarkType.noseBase];



        if (liveContour == null || staticContour == null || liveNose == null || staticNose == null) continue;



        final livePoints = liveContour.points;

        final staticPoints = staticContour.points;



// 2. Match Point Counts

        int pointCount = math.min(livePoints.length, staticPoints.length);



        List<Offset> positions = [];

        List<Offset> textureCoords = [];

        List<int> indices = [];



// 3. Build Mesh Center (Nose)

        positions.add(Offset(

            liveNose.position.x.toDouble() * scaleX,

            liveNose.position.y.toDouble() * scaleY

        ));

        textureCoords.add(Offset(

            staticNose.position.x.toDouble(),

            staticNose.position.y.toDouble()

        ));



// 4. Build Mesh Edges (Face Outline)

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



// 5. Connect Triangles

        for (int i = 1; i < pointCount; i++) {

          indices.add(0);

          indices.add(i);

          indices.add(i + 1);

        }

        indices.add(0);

        indices.add(pointCount);

        indices.add(1);



// 6. Draw

        _drawMesh(canvas, positions, textureCoords, indices, faceTexture!);

      }



// ==============================================================

// SCENARIO 2: ANIMAL SELECTED (Inflated Mask)

// ==============================================================

      else if (manualAnimal != null && faceTexture != null) {



        final liveContour = liveFace.contours[FaceContourType.face];

        final liveNose = liveFace.landmarks[FaceLandmarkType.noseBase];

// Note: Code 2 uses mouth for logic, but mainly relies on inflation loop

        final liveMouth = liveFace.landmarks[FaceLandmarkType.bottomMouth];



        if (liveContour == null || liveNose == null) continue;



// 1. Center Point (Nose)

        Offset nosePos = Offset(

            liveNose.position.x.toDouble() * scaleX,

            liveNose.position.y.toDouble() * scaleY

        );



// 2. Sample 12 Points

        List<math.Point<int>> allLivePoints = liveContour.points;

        List<Offset> livePointsSampled = [];



        if (allLivePoints.length < 12) {

          livePointsSampled = allLivePoints.map((p) => Offset(p.x.toDouble() * scaleX, p.y.toDouble() * scaleY)).toList();

        } else {

          int step = (allLivePoints.length / 12).floor();

          for (int i = 0; i < 12; i++) {

            int index = i * step;

            if (index < allLivePoints.length) {

              var p = allLivePoints[index];

              livePointsSampled.add(Offset(p.x.toDouble() * scaleX, p.y.toDouble() * scaleY));

            }

          }

        }



// 3. Inflate / Stretch Logic

        double inflationFactor = 1.45;

        List<Offset> inflatedPoints = [];



        for (var point in livePointsSampled) {

          double dx = point.dx - nosePos.dx;

          double dy = point.dy - nosePos.dy;

          inflatedPoints.add(Offset(

              nosePos.dx + (dx * inflationFactor),

              nosePos.dy + (dy * inflationFactor)

          ));

        }



// 4. Prepare Animal Static Points

        double w = faceTexture!.width.toDouble();

        double h = faceTexture!.height.toDouble();



        Offset staticNose = Offset(

            manualAnimal!.noseBase.dx * w,

            manualAnimal!.noseBase.dy * h

        );



        List<Offset> staticPoints = manualAnimal!.faceContour.map((Offset o) {

          return Offset(o.dx * w, o.dy * h);

        }).toList();



// 5. Build Mesh Arrays

        int pointCount = math.min(inflatedPoints.length, staticPoints.length);



        List<Offset> positions = [];

        List<Offset> textureCoords = [];

        List<int> indices = [];



        positions.add(nosePos);

        textureCoords.add(staticNose);



        for (int i = 0; i < pointCount; i++) {

          positions.add(inflatedPoints[i]);

          textureCoords.add(staticPoints[i]);

        }



        for (int i = 1; i <= pointCount; i++) {

          indices.add(0);

          indices.add(i);

          indices.add(i == pointCount ? 1 : i + 1);

        }



// 6. Draw

        _drawMesh(canvas, positions, textureCoords, indices, faceTexture!);

      }



// ==============================================================

// SCENARIO 3: NOTHING SELECTED (Draw Box)

// ==============================================================

      else {

        canvas.drawRect(

          Rect.fromLTRB(

            liveFace.boundingBox.left * scaleX,

            liveFace.boundingBox.top * scaleY,

            liveFace.boundingBox.right * scaleX,

            liveFace.boundingBox.bottom * scaleY,

          ),

          debugPaint,

        );

      }

    }

  }



// Helper method to keep code clean since drawing logic is same for both

  void _drawMesh(Canvas canvas, List<Offset> positions, List<Offset> textureCoords, List<int> indices, ui.Image texture) {

    final vertices = ui.Vertices(

      ui.VertexMode.triangles,

      positions,

      textureCoordinates: textureCoords,

      indices: indices,

    );



    final Paint meshPaint = Paint()

      ..shader = ui.ImageShader(

        texture,

        ui.TileMode.clamp,

        ui.TileMode.clamp,

        Matrix4.identity().storage,

      )

      ..color = Colors.white.withOpacity(morphOpacity);



    canvas.drawVertices(vertices, BlendMode.srcOver, meshPaint);

  }



  @override

  bool shouldRepaint(FacePainter oldDelegate) {

    return oldDelegate.faces != faces ||

        oldDelegate.faceTexture != faceTexture ||

        oldDelegate.staticFace != staticFace || // Check static face change

        oldDelegate.manualAnimal != manualAnimal || // Check animal change

        oldDelegate.morphOpacity != morphOpacity;

  }

}
