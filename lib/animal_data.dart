import 'dart:ui';

class AnimalData {
  final String assetPath;
  final Offset noseBase;
  final List<Offset> faceContour;

  AnimalData({
    required this.assetPath,
    required this.noseBase,
    required this.faceContour,
  });
}

// Update: Use almost the full image (0.0 to 1.0) to get ears and chin
List<Offset> _getOvalPoints(double topY, double bottomY, double leftX, double rightX) {
  final double centerX = (leftX + rightX) / 2;
  final double centerY = (topY + bottomY) / 2;
  final double widthRadius = (rightX - leftX) / 2;
  final double heightRadius = (bottomY - topY) / 2;

  List<Offset> points = [];
  // Top Center
  points.add(Offset(centerX, topY));
  // Top Right
  points.add(Offset(rightX - (widthRadius * 0.3), topY + (heightRadius * 0.1)));
  points.add(Offset(rightX - (widthRadius * 0.05), topY + (heightRadius * 0.4)));
  // Right
  points.add(Offset(rightX, centerY));
  // Bottom Right
  points.add(Offset(rightX - (widthRadius * 0.1), bottomY - (heightRadius * 0.3)));
  points.add(Offset(rightX - (widthRadius * 0.4), bottomY - (heightRadius * 0.1)));
  // Bottom (Chin)
  points.add(Offset(centerX, bottomY));
  // Bottom Left
  points.add(Offset(leftX + (widthRadius * 0.4), bottomY - (heightRadius * 0.1)));
  points.add(Offset(leftX + (widthRadius * 0.1), bottomY - (heightRadius * 0.3)));
  // Left
  points.add(Offset(leftX, centerY));
  // Top Left
  points.add(Offset(leftX + (widthRadius * 0.05), topY + (heightRadius * 0.4)));
  points.add(Offset(leftX + (widthRadius * 0.3), topY + (heightRadius * 0.1)));

  return points;
}

final List<AnimalData> animalAssets = [
  AnimalData(
    assetPath: 'assets/lion.png',
    noseBase: const Offset(0.5, 0.6),
    // Expanded boundaries to capture full mane
    faceContour: _getOvalPoints(0.05, 0.95, 0.05, 0.95),
  ),
  AnimalData(
    assetPath: 'assets/koala.png',
    noseBase: const Offset(0.5, 0.55),
    // Koala is wide, use full width
    faceContour: _getOvalPoints(0.0, 0.95, 0.0, 1.0),
  ),
  AnimalData(
    assetPath: 'assets/wolf.png',
    noseBase: const Offset(0.5, 0.65),
    // Wolf is tall
    faceContour: _getOvalPoints(0.05, 0.95, 0.1, 0.9),
  ),
];