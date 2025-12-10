import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:face_task_5/face_painter.dart';
import 'package:image_picker/image_picker.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error initializing cameras: $e');
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

  List<Face> _faces = [];
  bool _isDetecting = false;

  // --- MORPH VARIABLES ---
  File? _staticImageFile;
  List<Face> _staticImageFaces = [];
  ui.Image? _staticImageTexture;
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
      print("Camera init error: $e");
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
      print("Error processing static image: $e");
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
      if (mounted) setState(() => _faces = faces);
    } catch (e) {
      print("Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final cameraAspectRatio = _controller!.value.aspectRatio;
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
          // Picker in Top Right
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
                aspectRatio: cameraAspectRatio,
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
                          morphOpacity: _morphValue,
                        ),
                      ),

                    // Small Preview
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
                                  fit: BoxFit.cover
                              )
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // --- CONTROLS SECTION (Bottom) ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), // Extra bottom padding
            child: Row(
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
          ),
        ],
      ),
    );
  }
}