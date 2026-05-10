import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:ultralytics_yolo/widgets/yolo_controller.dart';

// 1. Dogoggora "Recognition isn't a type" jedhu furuuf
// Yoo package sun ofumaan hin fidin, nuti akka koflaatti (model) asitti uumna
class ObjectResult {
  final String label;
  final double confidence;
  final Rect box;

  ObjectResult({required this.label, required this.confidence, required this.box});
}

class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({super.key});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> {
  final YOLOViewController _controller = YOLOViewController();
  String _topObject = "SCANNING...";
  double _topConfidence = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("AI OBJECT VISION",
            style: TextStyle(letterSpacing: 2, color: Colors.cyanAccent, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // YOLOView: Inni kun kaameeraa fi model walitti mika
          YOLOView(
            controller: _controller,
            modelPath: "assets/yolov8n_float16.tflite", // Extension itti dabalii kallaattiin waami
            task: YOLOTask.detect,
            iouThreshold: 0.4,
            onResult: (results) {
              // 'results' dynamic waan ta'eef asitti keessaa baafanna
              if (results != null && results.isNotEmpty) {
                setState(() {
                  // Label fi Confidence argachuuf
                  _topObject = results.first.className.toString().toUpperCase();
                  _topConfidence = results.first.confidence ?? 0.0;
                });
              }
            },
          ),

          // Design Overlay (HUD)
          _buildHUD(),
        ],
      ),
    );
  }

  Widget _buildHUD() {
    return Positioned(
      bottom: 40,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("OBJECT: $_topObject",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text("${(_topConfidence * 100).toStringAsFixed(1)}%",
                    style: const TextStyle(color: Colors.cyanAccent)),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _topConfidence,
              backgroundColor: Colors.white10,
              color: Colors.cyanAccent,
            ),
            const SizedBox(height: 10),
            const Text("REAL-TIME NEURAL PROCESSING",
                style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}