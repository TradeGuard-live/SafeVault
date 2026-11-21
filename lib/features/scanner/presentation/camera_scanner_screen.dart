import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/security/file_validator.dart';
import '../../../core/services/native_saf_and_share_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';

class CameraScannerScreen extends StatefulWidget {
  const CameraScannerScreen({super.key});

  @override
  State<CameraScannerScreen> createState() => _CameraScannerScreenState();
}

class _CameraScannerScreenState extends State<CameraScannerScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  FlashMode _flashMode = FlashMode.off;

  final List<String> _capturedPagePaths = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    // Wipe any un-saved captured camera photos if screen was exited
    for (final path in _capturedPagePaths) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _isCameraInitialized = false);
        return;
      }

      final camera = _cameras[_selectedCameraIndex];
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);

      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCameraInitialized = false);
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final nextMode = _flashMode == FlashMode.off
        ? FlashMode.torch
        : (_flashMode == FlashMode.torch ? FlashMode.auto : FlashMode.off);

    try {
      await _controller!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (_) {}
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    _initializeCamera();
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);
    HapticFeedback.mediumImpact();

    try {
      final xFile = await _controller!.takePicture();
      setState(() {
        _capturedPagePaths.add(xFile.path);
        _isCapturing = false;
      });
    } catch (e) {
      setState(() => _isCapturing = false);
      if (mounted) {
        ErrorDialog.show(context, title: 'Capture Failed', message: e.toString());
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final safItems = await NativeSafAndShareService.instance.pickDocuments(
        allowMultiple: true,
        mimeTypes: const ['image/jpeg', 'image/jpg', 'image/png'],
      );
      if (safItems.isNotEmpty) {
        for (final item in safItems) {
          final file = File(item.path);
          if (await file.exists()) {
            await FileValidator.validateFile(file);
            setState(() {
              _capturedPagePaths.add(item.path);
            });
          }
        }
        return;
      }

      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (files.isEmpty) return;

      for (final pf in files) {
        if (pf.path != null) {
          final file = File(pf.path!);
          await FileValidator.validateFile(file);
          setState(() {
            _capturedPagePaths.add(pf.path!);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorDialog.show(context, title: 'Import Failed', message: e.toString());
      }
    }
  }

  void _proceedToReview() {
    if (_capturedPagePaths.isEmpty) return;
    context.push(
      '/scanner-preview',
      extra: {'pagePaths': List<String>.from(_capturedPagePaths)},
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Document Scanner', style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          IconButton(
            icon: Icon(
              _flashMode == FlashMode.torch
                  ? Icons.flash_on
                  : (_flashMode == FlashMode.auto ? Icons.flash_auto : Icons.flash_off),
              color: _flashMode != FlashMode.off ? colors.primaryAccent : Colors.white,
            ),
            tooltip: 'Flash',
            onPressed: _toggleFlash,
          ),
          if (_cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.flip_camera_android_rounded, color: Colors.white),
              tooltip: 'Switch Camera',
              onPressed: _switchCamera,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Camera Preview with Document Alignment Overlay
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isCameraInitialized && _controller != null)
                      CameraPreview(_controller!)
                    else
                      _buildCameraUnavailableFallback(),

                    // Document Frame Guideline Overlay
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colors.primaryAccent.withOpacity(0.85),
                            width: 2.0,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),

                    // Guide Label
                    Positioned(
                      top: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Align document within frame',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Multi-page thumbnail strip (if pages captured)
            if (_capturedPagePaths.isNotEmpty) ...[
              Container(
                height: 70,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.black,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _capturedPagePaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_capturedPagePaths[i]),
                            width: 50,
                            height: 54,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _capturedPagePaths.removeAt(i);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],

            // Bottom Shutter Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Pick from Gallery
                  IconButton(
                    icon: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 28),
                    tooltip: 'Gallery',
                    onPressed: _pickFromGallery,
                  ),

                  // Shutter Button
                  InkWell(
                    onTap: _isCapturing ? null : _capturePhoto,
                    child: Container(
                      width: 76,
                      height: 76,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isCapturing ? colors.warning : colors.primaryAccent,
                        ),
                        child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 32),
                      ),
                    ),
                  ),

                  // Done / Next Button
                  if (_capturedPagePaths.isNotEmpty)
                    ElevatedButton(
                      onPressed: _proceedToReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primaryAccent,
                        foregroundColor: colors.onPrimaryAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Done (${_capturedPagePaths.length})'),
                          const Icon(Icons.arrow_forward, size: 16),
                        ],
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraUnavailableFallback() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, size: 56, color: Colors.white54),
          const SizedBox(height: 14),
          const Text(
            'Hardware Camera Unavailable',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select document photos from gallery or device files',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _pickFromGallery,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: const Text('Pick Image from Storage'),
          ),
        ],
      ),
    );
  }
}
