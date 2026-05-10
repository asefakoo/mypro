import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;


class FaceRecognitionApp extends StatefulWidget {
  @override
  _FaceRecognitionAppState createState() => _FaceRecognitionAppState();
}

class _FaceRecognitionAppState extends State<FaceRecognitionApp> {
  CameraController? _controller;
  Interpreter? _interpreter;
  bool _isProcessing = false;
  String _displayText = "Initializing...";

  // Detection setup
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  @override
  void initState() {
    super.initState();
    _startUp();
  }

  Future<void> _startUp() async {
    // 1. Load Model (192 is the standard output for MobileFaceNet)
    _interpreter = await Interpreter.fromAsset('mobile_facenet.tflite');

    // 2. Setup Camera
    final cameras = await availableCameras();
    final frontCam = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);

    _controller = CameraController(frontCam, ResolutionPreset.medium, enableAudio: false);
    await _controller!.initialize();

    _controller!.startImageStream((image) {
      if (!_isProcessing) {
        _isProcessing = true;
        _processFrame(image);
      }
    });

    if (mounted) setState(() => _displayText = "Looking for face...");
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      // Convert frame to ML Kit format
      final inputImage = _inputImageFromCameraImage(image);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        setState(() => _displayText = "No face detected");
      } else {
        final face = faces.first;

        // 1. Convert YUV to RGB Image
        img.Image fullImg = _convertYUV420(image);

        // 2. Crop to face bounding box
        img.Image croppedFace = img.copyCrop(
          fullImg,
          x: face.boundingBox.left.toInt(),
          y: face.boundingBox.top.toInt(),
          width: face.boundingBox.width.toInt(),
          height: face.boundingBox.height.toInt(),
        );

        // 3. Generate Embedding (The "Number")
        List<double> embedding = _runFaceNet(croppedFace);

        setState(() {
          _displayText = "Face Detected!\nVector: ${embedding.take(3).toList()}...";
        });
      }
    } catch (e) {
      print("Processing error: $e");
    } finally {
      // Delay slightly to save CPU, then allow next frame
      await Future.delayed(Duration(milliseconds: 500));
      _isProcessing = false;
    }
  }

  List<double> _runFaceNet(img.Image faceImage) {
    // MobileFaceNet expects 112x112
    img.Image resized = img.copyResize(faceImage, width: 112, height: 112);

    // Normalize pixels to [-1, 1] range
    var input = Float32List(1 * 112 * 112 * 3);
    var buffer = Float32List.view(input.buffer);
    int pixelIndex = 0;

    for (var y = 0; y < 112; y++) {
      for (var x = 0; x < 112; x++) {
        var pixel = resized.getPixel(x, y);
        buffer[pixelIndex++] = (pixel.r - 128) / 128.0;
        buffer[pixelIndex++] = (pixel.g - 128) / 128.0;
        buffer[pixelIndex++] = (pixel.b - 128) / 128.0;
      }
    }

    // Output is a 1x192 tensor
    var output = List.filled(1 * 192, 0.0).reshape([1, 192]);
    _interpreter!.run(input.reshape([1, 112, 112, 3]), output);

    return List<double>.from(output[0]);
  }

  // --- Image Utilities ---

  img.Image _convertYUV420(CameraImage image) {
    // This is a simplified YUV to RGB conversion
    final width = image.width;
    final height = image.height;
    final out = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = image.planes[0].bytes[y * width + x];
        out.setPixel(x, y, img.ColorRgb8(pixel, pixel, pixel));
      }
    }
    // Mobile cameras are usually rotated 90 degrees
    return img.copyRotate(out, angle: Platform.isAndroid ? 270 : 90);
  }

  InputImage _inputImageFromCameraImage(CameraImage image) {
    final allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation270deg,
        format: InputImageFormat.yuv420,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            CameraPreview(_controller!),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: EdgeInsets.all(25),
              child: Text(
                _displayText,
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}