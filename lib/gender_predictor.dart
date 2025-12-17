import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class GenderPredictor {
  Interpreter? _interpreter;
  bool _isModelLoaded = false;
  String _loadError = "";

  // Tensor config
  int _inputWidth = 128;
  int _inputHeight = 128;
  TensorType _inputType = TensorType.float32;
  
  // Output config
  List<int> _outputShape = [1, 2];
  TensorType _outputType = TensorType.float32;

  String get modelInfo => _isModelLoaded 
      ? "In:${_inputWidth}x${_inputHeight} Out:$_outputShape" 
      : "Not Loaded ($_loadError)";

  GenderPredictor() {
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset('assets/gender_model.tflite', options: options);

      var inputTensor = _interpreter!.getInputTensor(0);
      var shape = inputTensor.shape;
      if (shape.length == 4) {
        _inputHeight = shape[1];
        _inputWidth = shape[2];
      }
      _inputType = inputTensor.type;

      var outputTensor = _interpreter!.getOutputTensor(0);
      _outputShape = outputTensor.shape;
      _outputType = outputTensor.type;

      print("GenderPredictor Loaded. In: ${_inputWidth}x${_inputHeight} $_inputType. Out: $_outputShape $_outputType");

      _isModelLoaded = true;
    } catch (e) {
      _loadError = e.toString();
      print("GenderPredictor Load Error: $e");
    }
  }

  String predict(img.Image faceImage) {
    if (_loadError.isNotEmpty) return "LoadErr: $_loadError";
    if (!_isModelLoaded) return "Loading...";

    String step = "Start";
    try {
      step = "Resize";
      img.Image resizedImage = img.copyResize(faceImage, width: _inputWidth, height: _inputHeight);

      step = "InputPrep";
      Object input;
      if (_inputType == TensorType.uint8) {
        input = List.generate(1, (i) => List.generate(_inputHeight, (y) => List.generate(_inputWidth, (x) {
          var pixel = resizedImage.getPixel(x, y);
          return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
        })));
      } else {
        input = List.generate(1, (i) => List.generate(_inputHeight, (y) => List.generate(_inputWidth, (x) {
          var pixel = resizedImage.getPixel(x, y);
          return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
        })));
      }

      step = "OutputAlloc";
      int outputFlatSize = 1;
      for (var s in _outputShape) {
        outputFlatSize *= s;
      }
      
      Object output;
      // Handle output type
      if (_outputType == TensorType.uint8) {
         output = List.filled(outputFlatSize, 0).reshape(_outputShape);
      } else {
         output = List.filled(outputFlatSize, 0.0).reshape(_outputShape);
      }

      step = "Run";
      _interpreter!.run(input, output);

      step = "Parse";
      // Inspect structure
      if (output is List) {
        if (output.isEmpty) return "Empty Output";
        
        // Check if nested list
        if (output[0] is List) {
          List inner = output[0] as List;
          
          if (inner.length == 1) {
            // [1, 1]
            double val = _toDouble(inner[0]);
            return "Val: ${val.toStringAsFixed(4)}";
          } 
          else if (inner.length == 2) {
             // [1, 2]
             double v1 = _toDouble(inner[0]);
             double v2 = _toDouble(inner[1]);
             if (v1 > v2) return "Male ${(v1*100).toStringAsFixed(1)}%";
             return "Female ${(v2*100).toStringAsFixed(1)}%";
          }
          else {
             return "Shape: $_outputShape (Len ${inner.length})";
          }
        } else {
          // Flat list [1, N] or just [N] if shape was [N]
          // If shape is [2]
           if (output.length == 2) {
             double v1 = _toDouble(output[0]);
             double v2 = _toDouble(output[1]);
             return v1 > v2 ? "Male" : "Female";
           }
           if (output.length == 1) {
             return "Val: ${_toDouble(output[0]).toStringAsFixed(4)}";
           }
           return "Flat: $output";
        }
      }
      
      return "Unknown format: $output";

    } catch (e) {
      return "Err($step): $e";
    }
  }
  
  double _toDouble(dynamic val) {
    if (val is int) return val.toDouble();
    if (val is double) return val;
    return 0.0;
  }

  void close() {
    _interpreter?.close();
  }
}
