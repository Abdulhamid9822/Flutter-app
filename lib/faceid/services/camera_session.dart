import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class CameraSession extends ChangeNotifier with WidgetsBindingObserver {
  CameraSession({this.preferredLens = CameraLensDirection.front});

  final CameraLensDirection preferredLens;

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lens = CameraLensDirection.front;
  bool _initializing = true;
  bool _disposed = false;
  String? _error;

  CameraController? get controller => _controller;
  bool get initializing => _initializing;
  String? get error => _error;
  CameraLensDirection get lens => _lens;
  bool get canSwitchCamera =>
      _cameras.where((camera) => camera.lensDirection != _lens).isNotEmpty;

  bool get isReady => _controller != null && _controller!.value.isInitialized;

  Future<void> start() async {
    if (_disposed) return;
    WidgetsBinding.instance.addObserver(this);
    await _loadCameras();
  }

  Future<void> _loadCameras() async {
    _setInitializing(true);
    _error = null;
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _error = "Kamera topilmadi. Qurilmada kamera borligini tekshiring.";
        _setInitializing(false);
        return;
      }

      CameraDescription? selected;
      for (final camera in _cameras) {
        if (camera.lensDirection == preferredLens) {
          selected = camera;
          break;
        }
      }
      selected ??= _cameras.first;
      await _initCamera(selected);
    } on CameraException catch (error) {
      _error = _cameraErrorText(error);
      _setInitializing(false);
    } catch (error) {
      _error = "Kamerani ishga tushirib bo'lmadi: $error";
      _setInitializing(false);
    }
  }

  Future<void> _initCamera(CameraDescription camera) async {
    final old = _controller;
    _controller = null;
    await old?.dispose();

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _lens = camera.lensDirection;

    try {
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _error = null;

      // Avtomatik fokus mavjud bo'lsa, yoqamiz.
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {
        // Ba'zi kameralar bu rejimni qo'llab-quvvatlamaydi.
      }
    } on CameraException catch (error) {
      await controller.dispose();
      _error = _cameraErrorText(error);
    } catch (error) {
      await controller.dispose();
      _error = "Kamerani ishga tushirib bo'lmadi: $error";
    } finally {
      _setInitializing(false);
    }
  }

  Future<void> switchCamera() async {
    if (_cameras.length < 2 || _initializing) return;
    final next = _cameras.where((camera) => camera.lensDirection != _lens);
    if (next.isEmpty) return;
    _setInitializing(true);
    await _initCamera(next.first);
  }

  Future<void> retry() async {
    await _loadCameras();
  }

  Future<String> takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw CameraException('notReady', 'Kamera hali tayyor emas.');
    }
    if (controller.value.isTakingPicture) {
      throw CameraException('busy', 'Oldingi rasm olinmoqda.');
    }
    final file = await controller.takePicture();
    return file.path;
  }

  void _setInitializing(bool value) {
    _initializing = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller = null;
      controller?.dispose();
      if (!_disposed) notifyListeners();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _error == null) {
        _loadCameras();
      }
    }
  }

  String _cameraErrorText(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
        return "Kamera ruxsati berilmagan. Telefon sozlamalarida FaceID "
            "ilovasiga kamera ruxsatini bering.";
      case 'CameraAccessRestricted':
        return "Kameradan foydalanish cheklangan.";
      default:
        return "Kamera xatosi: ${error.description ?? error.code}";
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}

class CameraPreviewBox extends StatelessWidget {
  const CameraPreviewBox({
    super.key,
    required this.session,
    this.borderRadius = 24,
  });

  final CameraSession session;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          if (session.initializing) {
            return const ColoredBox(
              color: AppColors.surfaceHigh,
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }
          if (session.error != null) {
            return ColoredBox(
              color: AppColors.surfaceHigh,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.no_photography_outlined,
                        color: AppColors.subtext,
                        size: 36,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        session.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: session.retry,
                        child: const Text('Qayta urinish'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final controller = session.controller!;
          final size = controller.value.previewSize;
          if (size == null) {
            return const ColoredBox(color: AppColors.surfaceHigh);
          }
          return ColoredBox(
            color: Colors.black,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.height,
                height: size.width,
                child: CameraPreview(controller),
              ),
            ),
          );
        },
      ),
    );
  }
}
