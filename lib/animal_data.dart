import 'dart:ui';

class AnimalData {
  final String assetPath;
  final Offset noseBase;
  final List<Offset> faceContour;
  final String gender; // 'male', 'female', or 'both'

  AnimalData({
    required this.assetPath,
    required this.noseBase,
    required this.faceContour,
    this.gender = 'both',
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
    assetPath: 'assets/morph_targets/lion.png',
    noseBase: const Offset(0.5, 0.6),
    faceContour: _getOvalPoints(0.05, 0.95, 0.05, 0.95),
    gender: 'both',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/koala.png',
    noseBase: const Offset(0.5, 0.55),
    faceContour: _getOvalPoints(0.0, 0.95, 0.0, 1.0),
    gender: 'both',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/wolf.png',
    noseBase: const Offset(0.5, 0.65),
    faceContour: _getOvalPoints(0.05, 0.95, 0.1, 0.9),
    gender: 'both',
  ),
  // New Human Faces - Split arbitrarily for demo (update as needed)
  // MALE
  AnimalData(
    assetPath: 'assets/morph_targets/face1.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'male',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/face2.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'male',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/face3.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'male',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/face4.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'male',
  ),
  // FEMALE
  AnimalData(
    assetPath: 'assets/morph_targets/face5.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'female',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/face6.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'female',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/face7.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'female',
  ),
  AnimalData(
    assetPath: 'assets/morph_targets/face8.png',
    noseBase: const Offset(0.5, 0.5),
    faceContour: _getOvalPoints(0.0, 1.0, 0.0, 1.0),
    gender: 'female',
  ),
];

// Placeholder for Add-ons (e.g. Hats, Glasses)
// Logic will be: if gender is male, show male + both. If female, show female + both.
final List<AnimalData> addOnAssets = [
  // Example Male Addon
  /*
  AnimalData(
    assetPath: 'assets/addons/hat_male.png',
    noseBase: const Offset(0.5, 0.5), 
    faceContour: [],
    gender: 'male',
  ),
  */
];
