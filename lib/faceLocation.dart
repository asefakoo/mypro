import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart'; // Added for embeddings

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Interpreter? _interpreter;
  Uint8List? _croppedFaceBytes;
  List<double>? _faceEmbedding; // The vector list of numbers
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  // Load the TFLite model on startup
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/mobilefacenet.tflite');
    } catch (e) {
      debugPrint("Error loading model: $e");
    }
  }

  Future<void> _processImage() async {
    if (_interpreter == null) {
      debugPrint("Model not loaded yet");
      return;
    }

    final XFile? pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isProcessing = true);

    try {
      final Uint8List originalBytes = await pickedFile.readAsBytes();
      final InputImage inputImage = InputImage.fromFilePath(pickedFile.path);

      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No face detected!")));
        setState(() => _isProcessing = false);
        return;
      }

      img.Image? decodedImage = img.decodeImage(originalBytes);
      if (decodedImage == null) return;

      final face = faces.first;
      final rect = face.boundingBox;

      int x = rect.left.toInt().clamp(0, decodedImage.width);
      int y = rect.top.toInt().clamp(0, decodedImage.height);
      int width = rect.width.toInt().clamp(0, decodedImage.width - x);
      int height = rect.height.toInt().clamp(0, decodedImage.height - y);

      // 1. Crop the face
      img.Image croppedFace = img.copyCrop(
        decodedImage,
        x: x,
        y: y,
        width: width,
        height: height,
      );

      // 2. Generate Embedding (The numbers)
      _faceEmbedding = _generateEmbedding(croppedFace);

      // 3. Prepare preview image
      Uint8List faceJpg = Uint8List.fromList(img.encodeJpg(croppedFace));

      setState(() {
        _croppedFaceBytes = faceJpg;
        _isProcessing = false;
      });

    } catch (e) {
      debugPrint("Error: $e");
      setState(() => _isProcessing = false);
    }
  }

  List<double> _generateEmbedding(img.Image faceImage) {
    // Most models (MobileFaceNet) use 112x112 input
    img.Image resized = img.copyResize(faceImage, width: 112, height: 112);

    // Convert image to Float32 input tensor [1, 112, 112, 3]
    var input = Float32List(1 * 112 * 112 * 3);
    int index = 0;
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        var pixel = resized.getPixel(x, y);
        // Normalize to -1 to 1 (adjust based on your specific model requirements)
        input[index++] = (pixel.r - 127.5) / 127.5;
        input[index++] = (pixel.g - 127.5) / 127.5;
        input[index++] = (pixel.b - 127.5) / 127.5;
      }
    }

    // Output tensor for 192 or 128 dimension vector (depends on model)
    var output = List<double>.filled(192, 0).reshape([1, 192]);
    _interpreter!.run(input.buffer.asUint8List(), output);

    return List<double>.from(output[0]);
  }

  @override
  void dispose() {
    _faceDetector.close();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Face Recognition Embedding")),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 20),
              if (_isProcessing) const CircularProgressIndicator(),
              if (_croppedFaceBytes != null) ...[
                Image.memory(_croppedFaceBytes!, height: 150),
                const SizedBox(height: 10),
                const Text("Face Vector (Embeddings):", style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  height: 200,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: ListView.builder(
                    itemCount: _faceEmbedding?.length ?? 0,
                    itemBuilder: (context, i) => Text("[$i]: ${_faceEmbedding![i].toStringAsFixed(6)}"),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _processImage,
                icon: const Icon(Icons.psychology),
                label: const Text("Pick Image & Get Numbers"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}