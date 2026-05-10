import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:nevergiveup/refcator/EnvData.dart';
import 'package:nevergiveup/service_data.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:image/image.dart' as img;

enum LivenessStep { smile, blink, turnLeft, verified }

class EnvData {
  final double temp;
  final int ambientLight;
  final String exposure;
  const EnvData({required this.temp, required this.ambientLight, required this.exposure});
}

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 1;
  bool _isBusy = false;
  List<Face> _faces = [];
  Size? _imageSize;

  LivenessStep _currentStep = LivenessStep.smile;
  String _statusMsg = "CALIBRATING...";
  double _authLevel = 0.0;
  bool _isVerified = false;
  bool _isMatching = false;

  Database? _db;
  tfl.Interpreter? _interpreter;

  EnvData _envData = const EnvData(temp: 24.1, ambientLight: 415, exposure: 'Optimal');
  late AnimationController _hudController;
  late Animation<double> _hudAnimation;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableTracking: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initEngine();
    _initialize();
  }

  void _setupAnimations() {
    _hudController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _hudAnimation = CurvedAnimation(parent: _hudController, curve: Curves.easeInOut);
  }

  Future<void> _initEngine() async {
    final dbPath = await getDatabasesPath();

    final path = p.join(dbPath, 'bio_vault.db');
    debugPrint("Database Location: $path"); // Check your terminal for this!

    _db = await openDatabase(
      path,
      onCreate: (db, version) {
        debugPrint("Creating Table...");
        return db.execute('CREATE TABLE users(id TEXT PRIMARY KEY, embedding TEXT, timestamp TEXT)');
      },
      version: 1,
    );
  }

  Future<void> _initialize() async {
    _cameras = await availableCameras();
    if (_cameras.isNotEmpty) _startCamera();
  }

  void _startCamera() {
    if (_controller != null) _controller!.dispose();
    _controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );

    _controller?.initialize().then((_) {
      if (!mounted) return;
      _controller?.startImageStream(_processCameraImage);
      setState(() {});
    });
  }

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || _isMatching || _isVerified) return;
    _isBusy = true;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) {
      _isBusy = false;
      return;
    }

    try {
      final faces = await _faceDetector.processImage(inputImage);
      if (mounted) {
        setState(() {
          _faces = faces;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());

          _runModernBiometricLogic(faces, image);

          _envData = EnvData(
              temp: 24.1 + (math.Random().nextDouble() - 0.5) * 0.1,
              ambientLight: 415 + math.Random().nextInt(10) - 5,
              exposure: 'Optimal');
        });
      }
    } catch (e) {
      debugPrint("ML Error: $e");
    }

    await Future.delayed(const Duration(milliseconds: 40));
    _isBusy = false;
  }

  // --- RECOGNITION PIPELINE ---

  Future<void> _performRecognition(Face face, CameraImage image) async {

    await _handleSuccessfulRedirect();

    if (_interpreter == null || _db == null) return;

    setState(() {
      _isMatching = true;
      _statusMsg = "ANALYZING BIOMETRIC HASH...";
    });

    try {
      // 1. Generate Face Embedding
      final Float32List input = _convertImageToModelInput(image, face);

      final output = List<double>.filled(192, 0).reshape([1, 192]);

      _interpreter!.run(input, output);

      final List<double> currentEmbedding = List<double>.from(output[0]);

      // 2. Query Local Database
      final List<Map<String, dynamic>> records = await _db!.query('users');
      String? matchedId;
      double minDistance = 999.0;

      for (var row in records) {
        final List<double> storedEmbedding = List<double>.from(jsonDecode(row['embedding']));

        // Calculate Euclidean Distance
        double distance = 0;
        for (int i = 0; i < 192; i++) {
          distance += math.pow(currentEmbedding[i] - storedEmbedding[i], 2);
        }
        distance = math.sqrt(distance);

        if (distance < 0.75 && distance < minDistance) {
          minDistance = distance;
          matchedId = row['id'];
        }
      }

      // 3. Handle Identity Match/Registration
      if (matchedId != null) {
        _statusMsg = "ACCESS GRANTED: $matchedId";
      } else {
        matchedId = "NODE-${DateTime.now().millisecondsSinceEpoch % 10000}";
        await _db!.insert('users', {
          'id': matchedId,
          'embedding': jsonEncode(currentEmbedding),
          'timestamp': DateTime.now().toString().substring(0, 19)
        });
        _statusMsg = "NEW IDENTITY ANCHORED: $matchedId";
      }

      // 4. Finalize State & Redirect
      setState(() {
        _isVerified = true;
        _isMatching = false;
      });

      // Launch redirection after a short delay for visual confirmation

    } catch (e) {
      debugPrint("Recognition Failure: $e");
      setState(() {
        _isMatching = false;
        _statusMsg = "RECOGNITION ERROR";
      });
    }
  }

  Future<void> _handleSuccessfulRedirect() async {
    // 1. Release the camera hardware
    if (_controller != null) {
      await _controller!.stopImageStream();
      await _controller!.dispose();
      _controller = null;
    }

    // 2. Visual pause so the user sees the "ACCESS GRANTED" message
    await Future.delayed(const Duration(milliseconds: 1000));

    // 3. Navigate to the New Class
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const ServicesScreen()),
      );
    }
  }

  Float32List _convertImageToModelInput(CameraImage cameraImage, Face face) {
    // 1. Convert CameraImage to img.Image
    img.Image fullImage = _convertCameraImage(cameraImage);

    // 2. Rotate image for Android (90 degrees usually)
    if (Platform.isAndroid) {
      fullImage = img.copyRotate(fullImage, angle: 270);
    }

    // 3. Crop face based on bounding box
    img.Image faceCrop = img.copyCrop(
      fullImage,
      x: face.boundingBox.left.toInt(),
      y: face.boundingBox.top.toInt(),
      width: face.boundingBox.width.toInt(),
      height: face.boundingBox.height.toInt(),
    );

    // 4. Resize to 112x112
    img.Image resizedFace = img.copyResize(faceCrop, width: 112, height: 112);

    // 5. Convert to Float32 and Normalize (-1 to 1)
    var input = Float32List(1 * 112 * 112 * 3);
    var buffer = Float32List.view(input.buffer);
    int pixelIndex = 0;

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = resizedFace.getPixel(x, y);
        // Normalization: (pixel - 128) / 128
        buffer[pixelIndex++] = (pixel.r - 128) / 128.0;
        buffer[pixelIndex++] = (pixel.g - 128) / 128.0;
        buffer[pixelIndex++] = (pixel.b - 128) / 128.0;
      }
    }
    return input;
  }

  img.Image _convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image res = img.Image(width: width, height: height);

    if (image.format.group == ImageFormatGroup.yuv420) {
      // YUV420 Conversion logic
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      final vPlane = image.planes[2].bytes;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel!;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int uvIndex = uvRowStride * (y >> 1) + (x >> 1) * uvPixelStride;
          final int yp = yPlane[y * width + x];
          final int up = uPlane[uvIndex];
          final int vp = vPlane[uvIndex];

          int r = (yp + 1.402 * (vp - 128)).toInt().clamp(0, 255);
          int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).toInt().clamp(0, 255);
          int b = (yp + 1.772 * (up - 128)).toInt().clamp(0, 255);
          res.setPixelRgb(x, y, r, g, b);
        }
      }
    } else {
      // BGRA conversion (iOS)
      final bytes = image.planes[0].bytes;
      for (int i = 0; i < bytes.length; i += 4) {
        final int x = (i ~/ 4) % width;
        final int y = (i ~/ 4) ~/ width;
        res.setPixelRgb(x, y, bytes[i + 2], bytes[i + 1], bytes[i]);
      }
    }
    return res;
  }

  // --- UI FUNCTIONALITY ACTIONS ---

  void _resetSystem() {
    setState(() {
      _authLevel = 0.0;
      _currentStep = LivenessStep.smile;
      _isVerified = false;
      _isMatching = false;
      _statusMsg = "SYSTEM REBOOTED";
    });
  }

  Future<void> _showHistory() async {
    final List<Map<String, dynamic>> records = await _db!.query('users', orderBy: 'timestamp DESC');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("SCAN HISTORY", style: TextStyle(color: Colors.cyanAccent, letterSpacing: 2, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white10),
            Expanded(
              child: ListView.builder(
                itemCount: records.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(CupertinoIcons.person_crop_circle_fill, color: Colors.white70),
                  title: Text(records[i]['id'], style: const TextStyle(color: Colors.white)),
                  subtitle: Text(records[i]['timestamp'] ?? "Unknown Time", style: const TextStyle(color: Colors.white30, fontSize: 10)),
                  trailing: const Icon(CupertinoIcons.checkmark_shield_fill, color: Colors.greenAccent, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Settings",
      barrierColor: Colors.black.withOpacity(0.8),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A).withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Material( // Required for ink splashes
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header Icon & Title
                        Row(
                          children: [
                            const Icon(CupertinoIcons.settings_solid, color: Colors.cyanAccent, size: 28),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("PROTOCOL CONFIG",
                                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2)),
                                Text("ENCRYPTED ACCESS ONLY",
                                    style: TextStyle(color: Colors.cyanAccent.withOpacity(0.5), fontSize: 10, letterSpacing: 1)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),

                        // Settings Options
                        _buildSettingItem(
                          icon: CupertinoIcons.scope,
                          label: "HIGH ACCURACY MODE",
                          subLabel: "Increases sampling rate (Uses more CPU)",
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(height: 16),
                        _buildSettingItem(
                          icon: CupertinoIcons.trash,
                          label: "PURGE LOCAL DATABASE",
                          subLabel: "Irreversible deletion of all face data",
                          isDestructive: true,
                          onTap: () async {
                            await _db!.delete('users');
                            Navigator.pop(context);
                            _resetSystem();
                          },
                        ),

                        const SizedBox(height: 30),

                        // Close Button
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            color: Colors.white10,
                            onPressed: () => Navigator.pop(context),
                            child: const Text("CLOSE TERMINAL",
                                style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String label,
    required String subLabel,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final accentColor = isDestructive ? Colors.redAccent : Colors.cyanAccent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(height: 4),
                  Text(subLabel, style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  void _runModernBiometricLogic(List<Face> faces, CameraImage rawImage) {
    if (faces.isEmpty) {
      _handleNoFaceDetected();
      return;
    }

    final face = faces.first;
    if (_isVerified || _isMatching) return;

    final double smile = face.smilingProbability ?? 0.0;
    final double eyeOpenness = ((face.leftEyeOpenProbability ?? 1.0) +
        (face.rightEyeOpenProbability ?? 1.0)) / 2;
    final double headYaw = face.headEulerAngleY ?? 0.0;

    switch (_currentStep) {
      case LivenessStep.smile:
        _updateProgress(smile, 0.0, 0.33, "CHALLENGE 1: DETECTING SMILE");
        if (smile > 0.85) {
          _transitionToStep(LivenessStep.blink, 0.33, "SMILE VERIFIED");
        }
        break;

      case LivenessStep.blink:
        _updateProgress(1.0 - eyeOpenness, 0.33, 0.66, "CHALLENGE 2: BLINK TO VERIFY");
        if (eyeOpenness < 0.15) {
          _transitionToStep(LivenessStep.turnLeft, 0.66, "LIVENESS CONFIRMED");
        }
        break;

      case LivenessStep.turnLeft:
        double turnProgress = (headYaw / 25).clamp(0.0, 1.0);
        _updateProgress(turnProgress, 0.66, 1.0, "CHALLENGE 3: ROTATE HEAD LEFT");

        if (headYaw > 25) {
          _currentStep = LivenessStep.verified;
          _authLevel = 1.0;
          _statusMsg = "BIOMETRICS ANCHORED";
          _performRecognition(face, rawImage);
        }
        break;

      case LivenessStep.verified:
        _statusMsg = "IDENTITY CONFIRMED";
        break;
    }
  }

  void _handleNoFaceDetected() {
    setState(() {
      _authLevel = (_authLevel - 0.02).clamp(0.0, 1.0);
      _statusMsg = "POSITION FACE IN FRAME";
      if (_authLevel < 0.1) {
        _currentStep = LivenessStep.smile;
      }
    });
  }

  void _updateProgress(double currentActionVal, double min, double max, String msg) {
    setState(() {
      double segmentProgress = currentActionVal * (max - min);
      _authLevel = (min + segmentProgress).clamp(min, max);
      _statusMsg = msg;
    });
  }

  void _transitionToStep(LivenessStep next, double level, String feedback) {
    setState(() {
      _currentStep = next;
      _authLevel = level;
      _statusMsg = feedback;
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameras[_cameraIndex];
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _hudController.dispose();
    _controller?.dispose();
    _faceDetector.close();
    _db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.cyanAccent)));
    }

    final screenSize = MediaQuery.of(context).size;
    final double scaleFactor = screenSize.width / 375;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      drawer: _buildDrawer(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          Opacity(opacity: 0.1, child: CustomPaint(painter: GridPainter())),
          if (_imageSize != null)
            AnimatedBuilder(
              animation: _hudAnimation,
              builder: (context, child) => CustomPaint(
                painter: ModernBiometricPainter(
                  _faces,
                  _imageSize!,
                  _cameras[_cameraIndex].lensDirection,
                  _hudAnimation.value,
                  _isVerified,
                ),
              ),
            ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildModernHeader(scaleFactor),
                _buildBottomNavigation(scaleFactor),
              ],
            ),
          ),
          Positioned(
            top: screenSize.height * 0.18,
            left: 16,
            child: _buildEnvironmentalCard(scaleFactor),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0A0A0A),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.black),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(CupertinoIcons.shield_fill, color: Colors.cyanAccent, size: 40),
                SizedBox(height: 10),
                Text("BIO-LINK TERMINAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text("Secure Node: 0xF24A", style: TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.lock_shield, color: Colors.white70),
            title: const Text("Security Audit", style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.cloud_upload, color: Colors.white70),
            title: const Text("Sync Database", style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader(double scale) {
    return Column(
      children: [
        SizedBox(height: 10 * scale),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20 * scale),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(CupertinoIcons.bars, color: Colors.white, size: 24 * scale),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              Text("SECURE BIO-SCAN",
                  style: TextStyle(color: Colors.white, letterSpacing: 2, fontSize: 16 * scale, fontWeight: FontWeight.w100)),
              IconButton(
                icon: Icon(CupertinoIcons.repeat_1, color: Colors.white, size: 24 * scale),
                onPressed: _resetSystem,
              ),
            ],
          ),
        ),
        SizedBox(height: 20 * scale),
        Container(
          width: MediaQuery.of(context).size.width * 0.85,
          padding: EdgeInsets.all(20 * scale),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              Text(_statusMsg,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _isVerified ? Colors.greenAccent : Colors.cyanAccent,
                      letterSpacing: 1.5,
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.w300
                  )),
              SizedBox(height: 15 * scale),
              LinearProgressIndicator(
                  value: _authLevel,
                  backgroundColor: Colors.white10,
                  color: _isVerified ? Colors.greenAccent : Colors.cyanAccent,
                  minHeight: 2 * scale
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnvironmentalCard(double scale) {
    final style = TextStyle(color: Colors.white, fontSize: 10 * scale, letterSpacing: 1.5, fontWeight: FontWeight.w200);
    final valueStyle = TextStyle(color: Colors.greenAccent, fontSize: 10 * scale, letterSpacing: 1.5, fontWeight: FontWeight.bold);

    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _envRow(CupertinoIcons.thermometer, "TEMP:", "${_envData.temp.toStringAsFixed(1)} °C", style, valueStyle, scale),
          SizedBox(height: 10 * scale),
          _envRow(CupertinoIcons.sun_max, "AMBIENT:", "${_envData.ambientLight} lx", style, valueStyle, scale),
          SizedBox(height: 10 * scale),
          _envRow(CupertinoIcons.camera, "EXPOSURE:", _envData.exposure.toUpperCase(), style, valueStyle, scale),
        ],
      ),
    );
  }

  Widget _envRow(IconData icon, String label, String val, TextStyle s, TextStyle v, double sc) {
    return Row(children: [
      Icon(icon, color: Colors.white, size: 14 * sc),
      SizedBox(width: 10 * sc),
      Text(label, style: s),
      SizedBox(width: 5 * sc),
      Text(val, style: v)
    ]);
  }

  Widget _buildBottomNavigation(double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 40 * scale, vertical: 20 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(onTap: _showHistory, child: _navBtn(CupertinoIcons.group, "HISTORY", scale)),
          _centerCameraToggle(scale),
          GestureDetector(onTap: _showSettings, child: _navBtn(CupertinoIcons.settings, "SETTINGS", scale)),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, String label, double scale) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 22 * scale),
        SizedBox(height: 8 * scale),
        Text(label, style: TextStyle(color: Colors.white60, fontSize: 8 * scale, letterSpacing: 1.5)),
      ],
    );
  }

  Widget _centerCameraToggle(double scale) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _authLevel = 0.0;
          _currentStep = LivenessStep.smile;
          _isVerified = false;
          _cameraIndex = (_cameraIndex + 1) % _cameras.length;
          _startCamera();
        });
      },
      child: Container(
        height: 65 * scale,
        width: 65 * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white30, width: 1),
        ),
        child: Icon(CupertinoIcons.switch_camera, color: Colors.white, size: 26 * scale),
      ),
    );
  }
}

class ModernBiometricPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final CameraLensDirection direction;
  final double pulse;
  final bool isVerified;

  ModernBiometricPainter(this.faces, this.imageSize, this.direction, this.pulse, this.isVerified);

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / (Platform.isIOS ? imageSize.width : imageSize.height);
    final double scaleY = size.height / (Platform.isIOS ? imageSize.height : imageSize.width);
    final double canvasScale = size.width / 375;

    final mainColor = isVerified ? Colors.greenAccent : Colors.cyanAccent;

    for (final face in faces) {
      double left = face.boundingBox.left * scaleX;
      double top = face.boundingBox.top * scaleY;
      double right = face.boundingBox.right * scaleX;
      double bottom = face.boundingBox.bottom * scaleY;

      if (direction == CameraLensDirection.front) {
        final flippedLeft = size.width - right;
        final flippedRight = size.width - left;
        left = flippedLeft;
        right = flippedRight;
      }

      final rect = Rect.fromLTRB(left, top, right, bottom);

      final bPaint = Paint()..color = mainColor..strokeWidth = 3.0 * canvasScale..style = PaintingStyle.stroke;
      final bLen = rect.width * 0.2;

      canvas.drawPath(Path()..moveTo(rect.left, rect.top + bLen)..lineTo(rect.left, rect.top)..lineTo(rect.left + bLen, rect.top), bPaint);
      canvas.drawPath(Path()..moveTo(rect.right - bLen, rect.top)..lineTo(rect.right, rect.top)..lineTo(rect.right, rect.top + bLen), bPaint);
      canvas.drawPath(Path()..moveTo(rect.left, rect.bottom - bLen)..lineTo(rect.left, rect.bottom)..lineTo(rect.left + bLen, rect.bottom), bPaint);
      canvas.drawPath(Path()..moveTo(rect.right - bLen, rect.bottom)..lineTo(rect.right, rect.bottom)..lineTo(rect.right, rect.bottom - bLen), bPaint);

      final TextPainter tp = TextPainter(textAlign: TextAlign.left, textDirection: TextDirection.ltr);
      final String faceData = "LOC: X:${rect.center.dx.toInt()} Y:${rect.center.dy.toInt()}\n"
          "YAW: ${face.headEulerAngleY?.toStringAsFixed(1)}°\n"
          "PITCH: ${face.headEulerAngleX?.toStringAsFixed(1)}°";

      tp.text = TextSpan(text: faceData, style: TextStyle(color: mainColor, fontSize: 10 * canvasScale, fontWeight: FontWeight.bold, backgroundColor: Colors.black26));
      tp.layout();
      tp.paint(canvas, Offset(rect.left, rect.top - (tp.height + 5)));

      final meshPaint = Paint()..color = mainColor.withOpacity(0.5)..strokeWidth = 1.5 * canvasScale;
      final points = <Offset>[];
      face.landmarks.forEach((type, landmark) {
        if (landmark != null) {
          double x = landmark.position.x.toDouble() * scaleX;
          double y = landmark.position.y.toDouble() * scaleY;
          if (direction == CameraLensDirection.front) x = size.width - x;
          points.add(Offset(x, y));
          canvas.drawCircle(Offset(x, y), 2 * canvasScale, Paint()..color = mainColor);
        }
      });

      for (var i = 0; i < points.length; i++) {
        for (var j = i + 1; j < points.length; j++) {
          double distance = (points[i] - points[j]).distance;
          if (distance < rect.width * 0.45) {
            canvas.drawLine(points[i], points[j], meshPaint);
          }
        }
      }

      final laserY = rect.top + (rect.height * pulse);
      canvas.drawLine(Offset(rect.left, laserY), Offset(rect.right, laserY), Paint()..color = mainColor..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(ModernBiometricPainter oldDelegate) => true;
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double spacing = size.width / 10;
    final paint = Paint()..color = Colors.cyanAccent.withOpacity(0.05)..strokeWidth = 0.5;
    for (double i = 0; i < size.width; i += spacing) canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    for (double i = 0; i < size.height; i += spacing) canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
  }
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}