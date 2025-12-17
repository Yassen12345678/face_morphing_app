import 'dart:io';
import 'dart:ui' as ui;
import 'package:face_task_5/face_painter.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'animal_data.dart';
import 'gender_predictor.dart';

List<CameraDescription> cameras = [];

/// Converts a [CameraImage] to a [img.Image] format.
img.Image? convertCameraImage(CameraImage cameraImage) {
  try {
    // iOS BGRA
    if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      return img.Image.fromBytes(
        width: cameraImage.width,
        height: cameraImage.height,
        bytes: cameraImage.planes[0].bytes.buffer,
        order: img.ChannelOrder.bgra,
      );
    } 
    
    // Android NV21 / YUV420
    if (cameraImage.format.group == ImageFormatGroup.nv21 || cameraImage.format.group == ImageFormatGroup.yuv420) {
      return _convertYUVtoRGB(cameraImage);
    }
    
    return null;
  } catch (e) {
    return null;
  }
}

img.Image? _convertYUVtoRGB(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    final int planes = cameraImage.planes.length;
    
    final image = img.Image(width: width, height: height);

    if (planes >= 2) {
      final yBuffer = cameraImage.planes[0].bytes;
      Uint8List? uvBuffer;
      int uvRowStride = 0;
      int uvPixelStride = 1;
      
      if (planes == 2) {
         uvBuffer = cameraImage.planes[1].bytes;
         uvRowStride = cameraImage.planes[1].bytesPerRow;
         uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 2;
      } else if (planes >= 3) {
         // Fallback to Grayscale for 3-plane (safe)
         return _convertGrayscale(cameraImage);
      }

      for (var y = 0; y < height; ++y) {
        for (var x = 0; x < width; ++x) {
          final yIndex = y * width + x;
          final yValue = yBuffer[yIndex];

          final uvx = (x / 2).floor();
          final uvy = (y / 2).floor();
          
          int uValue = 128;
          int vValue = 128;
          
          if (uvBuffer != null) {
              final uvIndex = uvy * uvRowStride + uvx * uvPixelStride;
              if (uvIndex < uvBuffer.length - 1) {
                  vValue = uvBuffer[uvIndex];
                  uValue = uvBuffer[uvIndex + 1];
              }
          }

          final yDouble = yValue.toDouble();
          final uDouble = uValue - 128.0;
          final vDouble = vValue - 128.0;

          final r = (yDouble + 1.402 * vDouble).round().clamp(0, 255);
          final g = (yDouble - 0.344136 * uDouble - 0.714136 * vDouble).round().clamp(0, 255);
          final b = (yDouble + 1.772 * uDouble).round().clamp(0, 255);

          image.setPixelRgb(x, y, r, g, b);
        }
      }
      return image;
    } 
    else if (planes == 1) {
       return _convertGrayscale(cameraImage);
    }
    
    return null;
}

img.Image _convertGrayscale(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;
    final yBuffer = cameraImage.planes[0].bytes;
    
    final image = img.Image(width: width, height: height);
    
    for (var y = 0; y < height; ++y) {
      for (var x = 0; x < width; ++x) {
         int val = yBuffer[y * width + x];
         image.setPixelRgb(x, y, val, val, val);
      }
    }
    return image;
}


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    // print('Error initializing cameras: $e');
  }
  runApp(const FaceMorphApp());
}

class FaceMorphApp extends StatelessWidget {
  const FaceMorphApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Morphing',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: CameraScreen(cameras: cameras),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  late CameraDescription _cameraDescription;
  bool _isCameraInitialized = false;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      minFaceSize: 0.15,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  // --- GENDER DETECTION VARIABLES ---
  final GenderPredictor _genderPredictor = GenderPredictor();
  String _detectedGender = "Unknown";
  bool _isPredictingGender = false;
  bool _triggerGenderCheck = false;
  // ---------------------------------

  List<Face> _faces = [];
  bool _isDetecting = false;

  // --- MORPH VARIABLES ---
  File? _staticImageFile;
  List<Face> _staticImageFaces = [];
  ui.Image? _staticImageTexture;
  AnimalData? _selectedAnimal;
  double _morphValue = 0.5;
  // ----------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.cameras.isNotEmpty) {
      _cameraDescription = widget.cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );
      _initializeCamera(initialCamera: _cameraDescription);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      if (mounted) setState(() => _isCameraInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(initialCamera: _cameraDescription);
    }
  }

  Future<void> _initializeCamera({CameraDescription? initialCamera}) async {
    if (widget.cameras.isEmpty) return;
    _cameraDescription = initialCamera ?? widget.cameras.first;
    if (_controller != null) await _controller!.dispose();

    final newController = CameraController(
      _cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await newController.initialize();
      _controller = newController;
      if (mounted) {
        await _controller!.startImageStream(_processCameraImage);
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      // print("Camera init error: $e");
    }
  }

  void _toggleCamera() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final cameras = widget.cameras;
    final currentCameraIndex = cameras.indexWhere((c) => c.name == _cameraDescription.name);
    final nextCameraIndex = (currentCameraIndex + 1) % cameras.length;
    final newCamera = cameras[nextCameraIndex];
    setState(() => _isCameraInitialized = false);
    await _initializeCamera(initialCamera: newCamera);
  }

  Future<void> _loadAnimalAsset(AnimalData animal) async {
    final ByteData data = await rootBundle.load(animal.assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final image = await decodeImageFromList(bytes);

    setState(() {
      _selectedAnimal = animal;
      _staticImageTexture = image;
      _staticImageFaces = [];
      _staticImageFile = null;
    });
  }

  Future<void> _loadStaticImageTexture(File file) async {
    final data = await file.readAsBytes();
    final image = await decodeImageFromList(data);
    setState(() {
      _staticImageTexture = image;
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _staticImageFile = File(image.path);
        _selectedAnimal = null;
        _staticImageFaces = [];
        _staticImageTexture = null;
      });
      await _loadStaticImageTexture(File(image.path));
      await _processStaticImage(InputImage.fromFilePath(image.path));
    }
  }

  Future<void> _processStaticImage(InputImage inputImage) async {
    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        setState(() {
          _staticImageFaces = faces;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Target Face Detected!')),
          );
        }
      }
    } catch (e) {
      // print("Error processing static image: $e");
    }
  }

  InputImageRotation _rotationFromCamera(CameraDescription camera) {
    final int rotation = camera.sensorOrientation;
    return InputImageRotationValue.fromRawValue(rotation) ?? InputImageRotation.rotation0deg;
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (!_isCameraInitialized || _isDetecting || _controller == null) return;
    _isDetecting = true;
    try {
      final camera = _controller!.description;
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final InputImage inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()),
          rotation: _rotationFromCamera(camera),
          format: InputImageFormat.nv21,
          bytesPerRow: cameraImage.planes.first.bytesPerRow,
        ),
      );

      final faces = await _faceDetector.processImage(inputImage);

      // --- NEW GENDER LOGIC (MANUAL TRIGGER) ---
      if (faces.isNotEmpty && _triggerGenderCheck) {
        _triggerGenderCheck = false; // Turn off trigger immediately
        if (!_isPredictingGender) {
          _runGenderPrediction(cameraImage, faces.first);
        }
      }
      // ----------------------------------------

      if (mounted) setState(() => _faces = faces);
    } catch (e) {
      // print("Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  // Helper method to run gender prediction in background
  void _runGenderPrediction(CameraImage cameraImage, Face face) async {
    setState(() {
      _isPredictingGender = true;
      _detectedGender = "Analyzing...";
    });

    try {
      if (cameraImage.planes.isEmpty) {
        if (mounted) setState(() => _detectedGender = "Err: No Planes");
        return;
      }

      final convertedImage = await compute(convertCameraImage, cameraImage);

      if (convertedImage != null) {
        
        // --- ROTATION FIX ---
        img.Image processedImage = convertedImage;
        // Rotate image if sensor orientation requires it (usually 90 or 270 on Android)
        // This aligns the image with the face coordinates from ML Kit
        if (_cameraDescription.sensorOrientation != 0) {
           processedImage = img.copyRotate(convertedImage, angle: _cameraDescription.sensorOrientation);
        }

        int x = face.boundingBox.left.toInt();
        int y = face.boundingBox.top.toInt();
        int w = face.boundingBox.width.toInt();
        int h = face.boundingBox.height.toInt();

        // Safety Clamp
        if (x < 0) { w += x; x = 0; }
        if (y < 0) { h += y; y = 0; }
        if (x + w > processedImage.width) w = processedImage.width - x;
        if (y + h > processedImage.height) h = processedImage.height - y;

        if (w > 0 && h > 0) {
          final faceImage = img.copyCrop(processedImage, x: x, y: y, width: w, height: h);
          String result = _genderPredictor.predict(faceImage);
          if (mounted) setState(() => _detectedGender = result);
        } else {
          if (mounted) setState(() => _detectedGender = "Bounds Error: ${processedImage.width}x${processedImage.height} vs $x,$y ${w}x$h");
        }
      } else {
        String fmt = cameraImage.format.group.toString().split('.').last;
        int planes = cameraImage.planes.length;
        if (mounted) setState(() => _detectedGender = "Fmt:$fmt P:$planes Fail");
      }
    } catch (e) {
      if (mounted) setState(() => _detectedGender = "AppErr: $e");
    } finally {
      if (mounted) setState(() => _isPredictingGender = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    double aspectRatio = _controller!.value.aspectRatio;
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      aspectRatio = 1 / aspectRatio;
    }

    Size imageSize = const Size(0,0);
    if (_controller!.value.previewSize != null) {
      imageSize = Size(
          _controller!.value.previewSize!.height,
          _controller!.value.previewSize!.width
      );
    }
    final isFrontCamera = _cameraDescription.lensDirection == CameraLensDirection.front;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Morph'),
        actions: [
          IconButton(icon: const Icon(Icons.flip_camera_ios), onPressed: _toggleCamera),
          IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _pickImage
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CameraPreview(_controller!),

                    if (imageSize.width != 0)
                      isFrontCamera
                          ? Transform.scale(
                        scaleX: -1,
                        scaleY: 1,
                        alignment: Alignment.center,
                        child: CustomPaint(
                          painter: FacePainter(
                            faces: _faces,
                            absoluteImageSize: imageSize,
                            faceTexture: _staticImageTexture,
                            staticFace: _staticImageFaces.isNotEmpty ? _staticImageFaces[0] : null,
                            manualAnimal: _selectedAnimal,
                            morphOpacity: _morphValue,
                          ),
                        ),
                      )
                          : CustomPaint(
                        painter: FacePainter(
                          faces: _faces,
                          absoluteImageSize: imageSize,
                          faceTexture: _staticImageTexture,
                          staticFace: _staticImageFaces.isNotEmpty ? _staticImageFaces[0] : null,
                          manualAnimal: _selectedAnimal,
                          morphOpacity: _morphValue,
                        ),
                      ),

                    // --- GENDER TEXT OVERLAY ---
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: ConstrainedBox(
                             constraints: const BoxConstraints(maxHeight: 200),
                             child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: Text(
                                  "GENDER: $_detectedGender",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: _detectedGender.length > 25 ? 14 : 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                             ),
                          ),
                        ),
                      ),
                    ),
                    // ---------------------------

                    if (_staticImageFile != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          width: 80,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            image: DecorationImage(
                              image: FileImage(_staticImageFile!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isPredictingGender
                        ? null
                        : () {
                      setState(() {
                        _triggerGenderCheck = true;
                      });
                    },
                    icon: _isPredictingGender
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.face),
                    label: Text(_isPredictingGender ? "ANALYZING..." : "DETECT GENDER"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: animalAssets.map((animal) {
                      return GestureDetector(
                        onTap: () => _loadAnimalAsset(animal),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _selectedAnimal == animal ? Colors.deepPurple : Colors.transparent,
                                width: 3
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: CircleAvatar(
                            backgroundImage: AssetImage(animal.assetPath),
                            radius: 25,
                            backgroundColor: Colors.grey[300],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text("Alpha: 0%", style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Slider(
                        value: _morphValue,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (value) {
                          setState(() {
                            _morphValue = value;
                          });
                        },
                      ),
                    ),
                    const Text("100%", style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
