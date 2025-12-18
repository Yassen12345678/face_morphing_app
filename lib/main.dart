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
import 'package:screen_recorder/screen_recorder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
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
    debugPrint('Error initializing cameras: $e');
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
  
  // --- SCREEN RECORDER ---
  final ScreenRecorderController _screenRecorderController = ScreenRecorderController();
  // -----------------------

  // --- GENDER DETECTION VARIABLES ---
  final GenderPredictor _genderPredictor = GenderPredictor();
  String _detectedGender = "Unknown";
  bool _isPredictingGender = false;
  DateTime _lastGenderPredictionTime = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _genderPredictionInterval = const Duration(milliseconds: 1000); // 1 Second Interval
  // ---------------------------------

  List<Face> _faces = [];
  bool _isDetecting = false;
  
  // --- RECORDING VARIABLES ---
  bool _isRecording = false;
  // ---------------------------

  // --- MORPH VARIABLES ---
  File? _staticImageFile;
  List<Face> _staticImageFaces = [];
  ui.Image? _staticImageTexture;
  AnimalData? _selectedAnimal;
  double _morphValue = 0.5;
  // ----------------------
  
  // --- ADD-ON VARIABLES ---
  // If you want a separate list for add-ons (like hats, glasses, etc.)
  // You can define them here or in a separate file like animal_data.dart
  // For now, I'll assume we select them similarly but maybe apply them differently
  // or just use the same morph logic if they are face masks.
  // ------------------------

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
      debugPrint("Camera init error: $e");
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

    List<Face> detectedFaces = [];
    
    // Heuristic: If it contains "face" in the filename, assume it's a human face
    // and try to detect landmarks using ML Kit.
    if (animal.assetPath.toLowerCase().contains("face")) {
      try {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(bytes);
        
        final inputImage = InputImage.fromFilePath(tempFile.path);
        detectedFaces = await _faceDetector.processImage(inputImage);
        
        // Cleanup
        await tempFile.delete();
      } catch (e) {
        debugPrint("Error detecting face in asset: $e");
      }
    }

    setState(() {
      if (detectedFaces.isNotEmpty) {
        // It's a human face with landmarks!
        // We set _selectedAnimal to null so FacePainter uses the landmark morphing logic
        _selectedAnimal = null;
        _staticImageFaces = detectedFaces;
      } else {
        // It's an animal or detection failed -> Use manual alignment logic
        _selectedAnimal = animal;
        _staticImageFaces = [];
      }
      _staticImageTexture = image;
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
      debugPrint("Error processing static image: $e");
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

      // --- AUTOMATIC GENDER LOGIC ---
      if (faces.isNotEmpty) {
        final now = DateTime.now();
        // Check if enough time has passed since last prediction (e.g. 1 second)
        // AND ensure we are not already running a prediction
        if (!_isPredictingGender && now.difference(_lastGenderPredictionTime) > _genderPredictionInterval) {
          _lastGenderPredictionTime = now;
          _runGenderPrediction(cameraImage, faces.first);
        }
      }
      // ----------------------------------------

      if (mounted) setState(() => _faces = faces);
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  // Helper method to run gender prediction in background
  void _runGenderPrediction(CameraImage cameraImage, Face face) async {
    setState(() {
      _isPredictingGender = true;
      // Note: We don't set "Analyzing..." here to avoid flickering the text constantly.
      // We just keep the old result until the new one is ready.
    });

    try {
      if (cameraImage.planes.isEmpty) {
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
        }
      } 
    } catch (e) {
      // debugPrint("Gender pred error: $e");
    } finally {
      if (mounted) setState(() => _isPredictingGender = false);
    }
  }
  
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // --- STOPPING RECORDING ---
      setState(() => _isRecording = false);
      
      try {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Processing video... please wait.')),
           );
        }

        // 1. Stop the recorder
        _screenRecorderController.stop();
        
        // 2. EXPORT the data
        debugPrint("Starting export...");
        final result = await _screenRecorderController.exporter.exportGif();
        debugPrint("Export finished. Bytes: ${result?.length}");
        
        if (result == null) {
          throw Exception("Recording failed: No data generated");
        }

        // 3. Create a temporary file path
        final directory = await getApplicationDocumentsDirectory();
        // Naming the file based on current time so they don't overwrite each other
        final String fileName = 'morph_video_${DateTime.now().millisecondsSinceEpoch}.gif';
        final File file = File('${directory.path}/$fileName');

        // 4. Write the bytes to the file
        // result is usually a list of bytes (Uint8List)
        await file.writeAsBytes(result as List<int>);
        debugPrint("File written to: ${file.path}");

        // 5. Save to Gallery using the 'gal' package
        // Request access first just in case
        debugPrint("Requesting gallery access...");
        await Gal.requestAccess();
        debugPrint("Saving to gallery...");
        await Gal.putImage(file.path);
        debugPrint("Saved to gallery!");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to Gallery: $fileName')),
          );
        }
      } catch (e) {
        debugPrint("Error saving video: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving: $e')),
          );
        }
      }
    } else {
      // --- STARTING RECORDING ---
      try {
        setState(() => _isRecording = true);
        _screenRecorderController.start();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error starting: $e')),
          );
        }
      }
    }
  }

  void _showAnimalList() {
    // 1. Determine Current Gender
    String currentGender = 'unknown';
    if (_detectedGender.toLowerCase().contains('male') && !_detectedGender.toLowerCase().contains('female')) {
      currentGender = 'male';
    } else if (_detectedGender.toLowerCase().contains('female')) {
      currentGender = 'female';
    }

    // 2. Filter Assets
    // Show items where gender matches OR gender is 'both'
    // If gender is unknown, we can either show ALL or show 'both'. Let's show ALL to be safe.
    final filteredList = animalAssets.where((animal) {
       if (currentGender == 'unknown') return true; 
       return animal.gender == 'both' || animal.gender == currentGender;
    }).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          height: 350, 
          child: Column(
            children: [
               Text("Showing ${currentGender == 'unknown' ? 'All' : currentGender.toUpperCase()} Options", 
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
               ),
               const SizedBox(height: 10),
               Expanded(
                 child: filteredList.isEmpty 
                  ? const Center(child: Text("No images found for this gender."))
                  : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, 
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                    ),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final animal = filteredList[index];
                      return GestureDetector(
                        onTap: () {
                          _loadAnimalAsset(animal);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedAnimal == animal ? Colors.deepPurple : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            backgroundImage: AssetImage(animal.assetPath),
                            backgroundColor: Colors.grey[300],
                          ),
                        ),
                      );
                    },
                  ),
               ),
            ],
          ),
        );
      },
    );
  }
  
  void _showAddOnList() {
    // 1. Determine Current Gender
    String currentGender = 'unknown';
    if (_detectedGender.toLowerCase().contains('male') && !_detectedGender.toLowerCase().contains('female')) {
      currentGender = 'male';
    } else if (_detectedGender.toLowerCase().contains('female')) {
      currentGender = 'female';
    }

    // 2. Filter Assets
    final filteredList = addOnAssets.where((addon) {
       if (currentGender == 'unknown') return true; 
       return addon.gender == 'both' || addon.gender == currentGender;
    }).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          height: 350,
          child: Column(
             children: [
               Text("Add-ons (${currentGender == 'unknown' ? 'All' : currentGender.toUpperCase()})", 
                 style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
               ),
               const SizedBox(height: 10),
               Expanded(
                 child: filteredList.isEmpty 
                 ? const Center(child: Text("No add-ons available yet."))
                 : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4, 
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                    ),
                    itemCount: filteredList.length,
                    itemBuilder: (context, index) {
                      final addon = filteredList[index];
                      return GestureDetector(
                        onTap: () {
                           // For now, load it like an animal (same morph logic)
                           // or you can add specific logic for add-ons here.
                          _loadAnimalAsset(addon);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedAnimal == addon ? Colors.deepPurple : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            backgroundImage: AssetImage(addon.assetPath),
                            backgroundColor: Colors.grey[300],
                          ),
                        ),
                      );
                    },
                  ),
               ),
             ],
          ),
        );
      },
    );
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
            child: ScreenRecorder(
              height: 500, // Reasonable default, expands to fill available
              width: 500,
              controller: _screenRecorderController,
              background: Colors.black,
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
                            child: Text(
                              "GENDER: $_detectedGender",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // --- BOTTOM CONTROLS ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // BUTTON ROW
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // Distribute evenly
                  children: [
                    // ADD-ON BUTTON (Left)
                    SizedBox(
                      width: 70, // Fixed Width
                      height: 70, // Fixed Height
                      child: FloatingActionButton(
                        heroTag: "addon_btn",
                        backgroundColor: Colors.deepPurple,
                        onPressed: _showAddOnList,
                        child: const Icon(Icons.face_retouching_natural, size: 30, color: Colors.white), 
                      ),
                    ),

                    // RECORD BUTTON (Center)
                    SizedBox(
                      width: 70,
                      height: 70,
                      child: FloatingActionButton(
                        heroTag: "record_btn",
                        backgroundColor: _isRecording ? Colors.red : Colors.white,
                        onPressed: _toggleRecording,
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.videocam,
                          size: 35,
                          color: _isRecording ? Colors.white : Colors.red,
                        ),
                      ),
                    ),

                    // ANIMAL BUTTON (Right)
                    SizedBox(
                      width: 70, // Fixed Width
                      height: 70, // Fixed Height
                      child: FloatingActionButton(
                        heroTag: "animal_btn",
                        backgroundColor: Colors.deepPurple,
                        onPressed: _showAnimalList,
                        child: const Icon(Icons.image, size: 30, color: Colors.white),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // SLIDER ROW
                Row(
                  children: [
                    const Text("Alpha: 0%", style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Slider(
                        value: _morphValue,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (val) {
                          setState(() {
                            _morphValue = val;
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
