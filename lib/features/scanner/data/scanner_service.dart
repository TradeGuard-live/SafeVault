import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum ImageFilterType {
  original,
  grayscale,
  highContrast,
  documentBw,
}

class ScannerPage {
  final String originalPath;
  Uint8List currentBytes;
  int rotationDegrees; // 0, 90, 180, 270
  ImageFilterType filter;

  ScannerPage({
    required this.originalPath,
    required this.currentBytes,
    this.rotationDegrees = 0,
    this.filter = ImageFilterType.original,
  });
}

class ScannerService {
  /// Applies rotation (90 deg increments) and filter (grayscale, high-contrast, document B&W)
  Future<Uint8List> processImageBytes(
    Uint8List sourceBytes, {
    int rotationDegrees = 0,
    ImageFilterType filter = ImageFilterType.original,
  }) async {
    img.Image? decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;

    // Apply rotation
    if (rotationDegrees % 360 != 0) {
      decoded = img.copyRotate(decoded, angle: rotationDegrees);
    }

    // Apply filter
    switch (filter) {
      case ImageFilterType.grayscale:
        decoded = img.grayscale(decoded);
        break;
      case ImageFilterType.highContrast:
        decoded = img.grayscale(decoded);
        decoded = img.adjustColor(decoded, contrast: 1.4, brightness: 1.05);
        break;
      case ImageFilterType.documentBw:
        decoded = img.grayscale(decoded);
        // Adaptive thresholding / high contrast for document text
        decoded = img.contrast(decoded, contrast: 150);
        break;
      case ImageFilterType.original:
        break;
    }

    return Uint8List.fromList(img.encodeJpg(decoded, quality: 85));
  }

  /// Crops an image to a given bounding rectangle
  Future<Uint8List> cropImageBytes(
    Uint8List sourceBytes, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    img.Image? decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;

    final cropX = x.clamp(0, decoded.width - 1);
    final cropY = y.clamp(0, decoded.height - 1);
    final cropW = width.clamp(1, decoded.width - cropX);
    final cropH = height.clamp(1, decoded.height - cropY);

    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
  }

  /// Generates a thumbnail image (max width/height 300px)
  Future<Uint8List> generateThumbnail(Uint8List sourceBytes) async {
    img.Image? decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return sourceBytes;

    final resized = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? 300 : null,
      height: decoded.height >= decoded.width ? 300 : null,
    );

    return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
  }

  /// Compiles multiple scanned pages into a standard PDF document.
  Future<Uint8List> compileToPdf(List<Uint8List> pageImages) async {
    final pdf = pw.Document();

    for (final pageBytes in pageImages) {
      final image = pw.MemoryImage(pageBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    return await pdf.save();
  }

  /// Securely removes temporary scanner files from disk.
  Future<void> cleanupTempFiles(List<String> paths) async {
    for (final p in paths) {
      try {
        final f = File(p);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }
}

