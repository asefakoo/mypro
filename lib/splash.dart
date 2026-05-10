import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'face_detect.dart';

class VideoSplashScreen extends StatefulWidget {
  const VideoSplashScreen({super.key});

  @override
  State<VideoSplashScreen> createState() => _VideoSplashScreenState();
}

class _VideoSplashScreenState extends State<VideoSplashScreen> {
  late VideoPlayerController _controller;
  bool _isLoading = true;
  bool _isBlocked = false;
  String _statusMessage = "INITIALIZING SECURE PROTOCOLS...";

  @override
  void initState() {
    super.initState();
    _initVideo();
    _executeSecuritySequence();
  }

  void _initVideo() {
    _controller = VideoPlayerController.asset('assets/videos/splash_bg.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller.setLooping(true);
        _controller.play();
      });
  }

  /// Main security sequence: 30-second dramatic delay + real API check
  Future<void> _executeSecuritySequence() async {
    // Start the 30-second "Dramatic" timer
    final dramaticTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isBlocked) {
        setState(() => _isLoading = false);
      }
    });

    String deviceId = await _getUniqueId();

    try {
      // 1. Check if device exists or is blocked
      final response = await http.post(
        Uri.parse("https://ekub.kushlandonlinecourses.com/ekub/check_device.php"),
        body: {"device_id": deviceId},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'blocked') {
          dramaticTimer.cancel(); // Stop the timer, don't let them in
          setState(() {
            _isBlocked = true;
            _statusMessage = "CRITICAL ERROR: HARDWARE BLACKLISTED";
          });
          return;
        }

        if (data['status'] == 'unregistered' || data['status'] == 'new') {
          setState(() => _statusMessage = "NEW HARDWARE DETECTED: REGISTERING...");
          await _registerDevice(deviceId);
          setState(() => _statusMessage = "REGISTRATION SUCCESSFUL: VERIFYING...");
        } else {
          setState(() => _statusMessage = "HARDWARE INTEGRITY VERIFIED");
        }
      }
    } catch (e) {
      // Fallback for offline or server errors
      setState(() => _statusMessage = "ENCRYPTED OFFLINE MODE ACTIVE");
    }
  }

  Future<void> _registerDevice(String id) async {
    try {
      // Note: Ensure your PHP script handles this 'register' action
      await http.post(
        Uri.parse("https://ekub.kushlandonlinecourses.com/ekub/register_device.php"),
        body: {"device_id": id},
      );
    } catch (_) {}
  }

  Future<String> _getUniqueId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      // 'id' on Android is the most stable unique hardware identifier available in this plugin
      return androidInfo.id;
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "unknown_ios";
    }
    return "unknown_platform";
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background Video Layer
          if (_controller.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),

          // Overlay for readability
          Container(color: Colors.black.withOpacity(0.6)),

          SafeArea(
            child: Center(
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  Icon(
                    _isBlocked ? Icons.gpp_bad : Icons.shape_line_sharp,
                    size: size.width * 0.22,
                    color: _isBlocked ? Colors.redAccent : Colors.cyanAccent,
                  ),
                  const SizedBox(height: 25),
                  Text(
                    "ELETAN SECURE",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size.width * 0.07,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                    ),
                  ),
                  const Spacer(flex: 2),
                  _buildStatusArea(size),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusArea(Size size) {
    if (_isBlocked) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.redAccent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _statusMessage,
          style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
      );
    }

    if (!_isLoading) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.cyanAccent,
          foregroundColor: Colors.black,
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.15, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        ),
        onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FaceDetectionScreen())
        ),
        child: const Text("INITIALIZE TERMINAL", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
      );
    }

    return Column(
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2),
        ),
        const SizedBox(height: 20),
        Text(
          _statusMessage,
          style: TextStyle(
            color: Colors.cyanAccent.withOpacity(0.7),
            fontSize: 10,
            letterSpacing: 2,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}