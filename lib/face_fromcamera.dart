import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img; // Add this import

class AdvancedFaceTracker extends StatefulWidget {
  const AdvancedFaceTracker({super.key});
  @override
  State<AdvancedFaceTracker> createState() => _AdvancedFaceTrackerState();
}

class _AdvancedFaceTrackerState extends State<AdvancedFaceTracker> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;

  bool _isBusy = false;
  bool _isSaving = false;
  bool _isCooldown = false;

  List<Face> _faces = [];
  Size? _imageSize;
  File? _lastCapturedFile;

  late AnimationController _scannerController;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  @override
  void initState() {
    super.initState();
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _setupCamera();
  }

  Future<void> _setupCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    _cameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _initCamera(_cameras[_cameraIndex == -1 ? 0 : _cameraIndex]);
  }

  Future<void> _initCamera(CameraDescription description) async {
    await _controller?.dispose();
    _controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller?.initialize();
      _controller?.startImageStream(_processImage);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Init Error: $e");
    }
  }

  void _processImage(CameraImage image) async {
    if (_isBusy || _isCooldown || _isSaving || !mounted) return;
    _isBusy = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      final detectedFaces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faces = detectedFaces;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
      }

      if (detectedFaces.isNotEmpty && !_isSaving) {
        _captureSequence();
      }
    } finally {
      _isBusy = false;
    }
  }

  InputImage _inputImageFromCameraImage(CameraImage image) {
    final sensorOrientation = _controller!.description.sensorOrientation;
    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg,
        format: InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }


  Future<void> _captureSequence() async {
    _isSaving = true;
    _isCooldown = true;

    try {
      if (_faces.isEmpty) return;

      // 1. Take the full picture
      await _controller?.stopImageStream();
      final XFile file = await _controller!.takePicture();

      // 2. Load the image into memory
      final bytes = await File(file.path).readAsBytes();
      img.Image? fullImage = img.decodeImage(bytes);

      if (fullImage != null) {
        // 3. Get the bounding box of the first detected face
        final face = _faces.first;
        final rect = face.boundingBox;

        // 4. Crop the image
        // Note: You may need to adjust coordinates if the image is rotated
        img.Image croppedFace = img.copyCrop(
          fullImage,
          x: rect.left.toInt(),
          y: rect.top.toInt(),
          width: rect.width.toInt(),
          height: rect.height.toInt(),
        );

        // 5. Save the cropped version
        final directory = await getApplicationDocumentsDirectory();
        final String path = '${directory.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final File croppedFile = File(path);

        await croppedFile.writeAsBytes(img.encodeJpg(croppedFace));

        setState(() => _lastCapturedFile = croppedFile);
        debugPrint("Cropped Face Saved: $path");
      }
    } catch (e) {
      debugPrint("Crop failed: $e");
    } finally {
      _isSaving = false;
      if (mounted) _controller?.startImageStream(_processImage);
      Future.delayed(const Duration(seconds: 3), () => _isCooldown = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)));
    }

    final isFront = _controller!.description.lensDirection == CameraLensDirection.front;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(isFront ? 3.14159 : 0),
            child: CameraPreview(_controller!),
          ),
          if (_imageSize != null)
            CustomPaint(painter: ModernFacePainter(_faces, _imageSize!, isFront, _scannerController)),
          _buildOverlayUI(),
        ],
      ),
    );
  }

  Widget _buildOverlayUI() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildTopBar(),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebarStats(),
                const Spacer(),
                _buildThumbnail(),
              ],
            ),
            const Spacer(),
            if (_faces.isNotEmpty) _buildTelemetryDashboard(_faces.first),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        const Icon(Icons.radar, color: Colors.cyanAccent, size: 28),
        const SizedBox(width: 10),
        const Text("BIOMETRIC ANALYTICS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
          onPressed: () {
            _cameraIndex = (_cameraIndex + 1) % _cameras.length;
            _initCamera(_cameras[_cameraIndex]);
          },
        ),
      ],
    );
  }

  Widget _buildThumbnail() {
    return Column(
      children: [
        Container(
          width: 90, height: 90,
          decoration: BoxDecoration(
            color: Colors.black45,
            border: Border.all(color: _lastCapturedFile != null ? Colors.cyanAccent : Colors.redAccent.withOpacity(0.5), width: 2),
            borderRadius: BorderRadius.circular(12),
            image: _lastCapturedFile != null
                ? DecorationImage(image: FileImage(_lastCapturedFile!), fit: BoxFit.cover)
                : null,
          ),
          child: _lastCapturedFile == null ? const Icon(Icons.no_photography, color: Colors.white24) : null,
        ),
        const SizedBox(height: 5),
        Text(_lastCapturedFile != null ? "LOCKED" : "SCANNING",
            style: TextStyle(color: _lastCapturedFile != null ? Colors.cyanAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSidebarStats() {
    if (_faces.isEmpty) return const SizedBox.shrink();
    final f = _faces.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _teleUnit("TARGETS", _faces.length.toString()),
        const SizedBox(height: 15),
        _teleUnit("SMILE", "${((f.smilingProbability ?? 0) * 100).toInt()}%"),
        const SizedBox(height: 15),
        _teleUnit("L_EYE", "${((f.leftEyeOpenProbability ?? 0) * 100).toInt()}%"),
      ],
    );
  }

  Widget _buildTelemetryDashboard(Face face) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _teleUnit("POS X", face.boundingBox.left.toInt().toString()),
              _teleUnit("POS Y", face.boundingBox.top.toInt().toString()),
              _teleUnit("WIDTH", face.boundingBox.width.toInt().toString()),
              _teleUnit("HEIGHT", face.boundingBox.height.toInt().toString()),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white10)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _teleUnit("PITCH", face.headEulerAngleX?.toStringAsFixed(1) ?? "0"),
              _teleUnit("YAW", face.headEulerAngleY?.toStringAsFixed(1) ?? "0"),
              _teleUnit("ROLL", face.headEulerAngleZ?.toStringAsFixed(1) ?? "0"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _teleUnit(String label, String val) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
        Text(val, style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}

class ModernFacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final bool isFrontCamera;
  final Animation<double> animation;

  ModernFacePainter(this.faces, this.imageSize, this.isFrontCamera, this.animation) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 2.0;

    for (var face in faces) {
      final double scaleX = size.width / imageSize.height;
      final double scaleY = size.height / imageSize.width;

      final rect = Rect.fromLTRB(
        isFrontCamera ? size.width - (face.boundingBox.right * scaleX) : face.boundingBox.left * scaleX,
        face.boundingBox.top * scaleY,
        isFrontCamera ? size.width - (face.boundingBox.left * scaleX) : face.boundingBox.right * scaleX,
        face.boundingBox.bottom * scaleY,
      );

      // 1. Draw Corner Brackets
      canvas.drawPath(_buildCornerPath(rect), paint);

      // 2. Scan Line Animation
      final scanY = rect.top + (rect.height * animation.value);
      canvas.drawLine(
          Offset(rect.left, scanY),
          Offset(rect.right, scanY),
          Paint()..color = Colors.cyanAccent.withOpacity(0.6)..strokeWidth = 1.5
      );

      // 3. Landmarks Mesh
      final meshPaint = Paint()..color = Colors.cyanAccent.withOpacity(0.25)..strokeWidth = 0.5;
      final points = face.landmarks.values
          .where((l) => l != null)
          .map((l) => Offset(
          isFrontCamera ? size.width - (l!.position.x * scaleX) : l!.position.x * scaleX,
          l.position.y * scaleY))
          .toList();

      for (var i = 0; i < points.length; i++) {
        for (var j = i + 1; j < points.length; j++) {
          canvas.drawLine(points[i], points[j], meshPaint);
        }
      }
    }
  }

  Path _buildCornerPath(Rect rect) {
    const len = 20.0;
    return Path()
      ..moveTo(rect.left, rect.top + len)..lineTo(rect.left, rect.top)..lineTo(rect.left + len, rect.top)
      ..moveTo(rect.right - len, rect.top)..lineTo(rect.right, rect.top)..lineTo(rect.right, rect.top + len)
      ..moveTo(rect.left, rect.bottom - len)..lineTo(rect.left, rect.bottom)..lineTo(rect.left + len, rect.bottom)
      ..moveTo(rect.right - len, rect.bottom)..lineTo(rect.right, rect.bottom)..lineTo(rect.right, rect.bottom - len);
  }

  @override
  bool shouldRepaint(ModernFacePainter old) => true;
}