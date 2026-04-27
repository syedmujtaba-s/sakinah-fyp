import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Live camera preview that auto-captures a high-quality face shot.
///
/// Pipeline:
///   1. Open the front-facing camera at a balanced resolution.
///   2. On every frame, run on-device ML Kit face detection.
///   3. Show a green oval overlay when the face is centered + eyes open
///      + frontal pose. Once the user holds steady for [holdDuration]
///      we auto-capture the JPEG and call [onCaptured] with the bytes.
///   4. The widget never uploads anything itself — that's the parent
///      screen's responsibility, so the bytes can also be discarded if
///      the user cancels.
///
/// Why ML Kit gates BEFORE upload:
///   - Saves bandwidth (we never upload an out-of-frame face).
///   - Improves backend accuracy (HSEmotion likes well-aligned crops).
///   - Lets the UI tell the user *why* it's not capturing yet
///     ("center your face", "open your eyes", etc.).
class EmotionCameraView extends StatefulWidget {
  final void Function(Uint8List jpegBytes) onCaptured;
  final VoidCallback? onCameraError;
  final Duration holdDuration;

  const EmotionCameraView({
    super.key,
    required this.onCaptured,
    this.onCameraError,
    this.holdDuration = const Duration(milliseconds: 800),
  });

  @override
  State<EmotionCameraView> createState() => _EmotionCameraViewState();
}

class _EmotionCameraViewState extends State<EmotionCameraView>
    with WidgetsBindingObserver {
  CameraController? _camera;
  FaceDetector? _detector;

  bool _initializing = true;
  bool _isProcessing = false;       // throttle ML Kit to one frame at a time
  bool _capturing = false;
  String? _initError;

  // Quality gate state.
  String _hint = 'Initializing camera...';
  bool _faceReady = false;
  DateTime? _readySince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _initializing = false;
          _initError = 'No camera found on this device.';
        });
        widget.onCameraError?.call();
        return;
      }
      // Prefer front-facing camera for emotion check-in.
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // Medium resolution is plenty — HSEmotion downsamples to 224x224 anyway,
      // and lower preview cost = smoother UX on older phones.
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      _camera = controller;

      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,    // gives us smiling + eye-open probabilities
          enableContours: false,
          enableLandmarks: false,
          enableTracking: false,
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.3,              // face must occupy >=30% of frame
        ),
      );

      await controller.startImageStream(_onFrame);

      if (!mounted) return;
      setState(() {
        _initializing = false;
        _hint = 'Center your face in the oval';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _initError = 'Camera unavailable: $e';
      });
      widget.onCameraError?.call();
    }
  }

  void _onFrame(CameraImage image) {
    // Throttle: skip frames while we're still chewing on the previous one
    // OR while we're already capturing.
    if (_isProcessing || _capturing || _detector == null || _camera == null) {
      return;
    }
    _isProcessing = true;
    _processFrame(image).whenComplete(() => _isProcessing = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    final input = _toInputImage(image);
    if (input == null) return;

    try {
      final faces = await _detector!.processImage(input);
      _evaluateFaces(faces);
    } catch (_) {
      // ML Kit can throw for individual bad frames — silently skip.
    }
  }

  void _evaluateFaces(List<Face> faces) {
    if (!mounted) return;

    if (faces.isEmpty) {
      _setHint('Center your face in the oval', ready: false);
      return;
    }
    if (faces.length > 1) {
      _setHint('Make sure only your face is in the frame', ready: false);
      return;
    }

    final face = faces.first;

    // Eye-open probability — ML Kit returns null when not classifiable.
    final leftEye = face.leftEyeOpenProbability ?? 1.0;
    final rightEye = face.rightEyeOpenProbability ?? 1.0;
    if (leftEye < 0.4 || rightEye < 0.4) {
      _setHint('Open your eyes', ready: false);
      return;
    }

    // Head pose — keep within ~25° of frontal so HSEmotion gets a clean shot.
    final yaw = face.headEulerAngleY?.abs() ?? 0;
    final pitch = face.headEulerAngleX?.abs() ?? 0;
    if (yaw > 25 || pitch > 25) {
      _setHint('Look straight at the camera', ready: false);
      return;
    }

    // Quality looks good — start the hold timer.
    _setHint('Hold still...', ready: true);
  }

  void _setHint(String hint, {required bool ready}) {
    if (!mounted) return;
    setState(() {
      _hint = hint;
      _faceReady = ready;
      if (ready) {
        _readySince ??= DateTime.now();
        if (DateTime.now().difference(_readySince!) >= widget.holdDuration) {
          _capture();
        }
      } else {
        _readySince = null;
      }
    });
  }

  Future<void> _capture() async {
    if (_capturing || _camera == null) return;
    _capturing = true;

    try {
      // Pause the stream so we don't double-fire and so takePicture has
      // exclusive access to the camera buffer.
      await _camera!.stopImageStream();
      final shot = await _camera!.takePicture();
      final bytes = await File(shot.path).readAsBytes();

      // Cleanup the temp file the plugin wrote — we already have the bytes.
      try { await File(shot.path).delete(); } catch (_) {}

      if (mounted) widget.onCaptured(bytes);
    } catch (e) {
      _capturing = false;
      if (mounted) {
        setState(() => _hint = 'Capture failed, try again');
        // Resume stream so the user can retry.
        try {
          await _camera!.startImageStream(_onFrame);
        } catch (_) {}
      }
    }
  }

  /// Convert a CameraImage to ML Kit's InputImage. Format-aware so this works
  /// on both Android (NV21) and iOS (BGRA8888).
  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;

    final sensorOrientation = camera.description.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // ML Kit expects a single contiguous byte buffer.
    Uint8List bytes;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
    } else {
      final builder = BytesBuilder();
      for (final plane in image.planes) {
        builder.add(plane.bytes);
      }
      bytes = builder.toBytes();
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    // Stop the stream when backgrounded; resume when foregrounded.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      cam.stopImageStream().catchError((_) {});
    } else if (state == AppLifecycleState.resumed && !_capturing) {
      cam.startImageStream(_onFrame).catchError((_) {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final cam = _camera;
    if (cam != null) {
      cam.stopImageStream().catchError((_) {});
      cam.dispose();
    }
    _detector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const _StatusOverlay(message: 'Starting camera…', spinner: true);
    }
    if (_initError != null) {
      return _StatusOverlay(message: _initError!, spinner: false);
    }
    final controller = _camera;
    if (controller == null || !controller.value.isInitialized) {
      return const _StatusOverlay(message: 'Camera not ready', spinner: false);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Show the front camera preview as-is (no mirror) so the captured
        // image and what the user sees stay aligned. Some users find the
        // mirrored selfie look disorienting.
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 1,
              height: controller.value.previewSize?.width ?? 1,
              child: CameraPreview(controller),
            ),
          ),
        ),

        // Quality oval that turns green when the gate is satisfied.
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 280,
            height: 380,
            decoration: BoxDecoration(
              border: Border.all(
                color: _faceReady
                    ? const Color(0xFF15803D)
                    : Colors.white.withValues(alpha: 0.55),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(200),
            ),
          ),
        ),

        // Hint chip at the top.
        Positioned(
          top: 60,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _hint,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusOverlay extends StatelessWidget {
  final String message;
  final bool spinner;
  const _StatusOverlay({required this.message, required this.spinner});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade900,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (spinner)
            const CircularProgressIndicator(color: Colors.white)
          else
            const Icon(Icons.videocam_off_rounded,
                color: Colors.white24, size: 60),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}
