import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class PreparedFace {
  const PreparedFace({required this.input, required this.alignedJpeg});

  final Float32List input;
  final Uint8List alignedJpeg;
}

/// 112x112 yuzni MobileFaceNet modeli uchun tayyorlaydi.
Map<String, dynamic>? _prepareFaceJob(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final image = img.bakeOrientation(decoded);
  final left = (args['left'] as num).toDouble();
  final top = (args['top'] as num).toDouble();
  final width = (args['width'] as num).toDouble();
  final height = (args['height'] as num).toDouble();

  final centerX = left + width / 2;
  final centerY = top + height / 2;
  var side = math.max(width, height) * 1.38;
  final maxSide = math.min(image.width, image.height).toDouble();
  if (side > maxSide) side = maxSide;
  if (side < 8) side = maxSide;

  var x = (centerX - side / 2).round();
  var y = (centerY - side / 2).round();
  x = x.clamp(0, math.max(0, image.width - 1)).toInt();
  y = y.clamp(0, math.max(0, image.height - 1)).toInt();
  final cropWidth = side.round().clamp(1, image.width - x).toInt();
  final cropHeight = side.round().clamp(1, image.height - y).toInt();

  var crop = img.copyCrop(
    image,
    x: x,
    y: y,
    width: cropWidth,
    height: cropHeight,
  );

  double angle = 0;
  final leftEyeX = args['leftEyeX'] as double?;
  final leftEyeY = args['leftEyeY'] as double?;
  final rightEyeX = args['rightEyeX'] as double?;
  final rightEyeY = args['rightEyeY'] as double?;
  if (leftEyeX != null &&
      leftEyeY != null &&
      rightEyeX != null &&
      rightEyeY != null) {
    angle =
        math.atan2(rightEyeY - leftEyeY, rightEyeX - leftEyeX) * 180 / math.pi;
    if (angle > 90) angle -= 180;
    if (angle < -90) angle += 180;
  } else {
    angle = (args['roll'] as double?) ?? 0;
  }

  if (angle.abs() > 1.0) {
    crop = img.copyRotate(
      crop,
      angle: -angle,
      interpolation: img.Interpolation.linear,
    );
  }

  final centerSide = math.min(crop.width, crop.height);
  final x2 = (crop.width - centerSide) ~/ 2;
  final y2 = (crop.height - centerSide) ~/ 2;
  var face = img.copyCrop(
    crop,
    x: x2,
    y: y2,
    width: centerSide,
    height: centerSide,
  );
  face = img.copyResize(
    face,
    width: FaceService.inputSize,
    height: FaceService.inputSize,
    interpolation: img.Interpolation.linear,
  );

  final values = Float32List(FaceService.inputSize * FaceService.inputSize * 3);
  var index = 0;
  for (var py = 0; py < FaceService.inputSize; py++) {
    for (var px = 0; px < FaceService.inputSize; px++) {
      final pixel = face.getPixel(px, py);
      values[index++] = (pixel.r - 128.0) / 128.0;
      values[index++] = (pixel.g - 128.0) / 128.0;
      values[index++] = (pixel.b - 128.0) / 128.0;
    }
  }
  final inputBytes = Uint8List.view(
    values.buffer,
    values.offsetInBytes,
    values.lengthInBytes,
  );
  return <String, dynamic>{
    'input': Uint8List.fromList(inputBytes),
    'aligned': Uint8List.fromList(img.encodeJpg(face, quality: 92)),
  };
}

/// Rasmni EXIF bo'yicha to'g'rilaydi, kattaligini cheklaydi va JPEG qaytaradi.
Map<String, dynamic>? _normalizeImageJob(Map<String, dynamic> args) {
  final bytes = args['bytes'] as Uint8List;
  final maxSide = (args['maxSide'] as int?) ?? 1280;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  var image = img.bakeOrientation(decoded);
  if (image.width > maxSide || image.height > maxSide) {
    if (image.width >= image.height) {
      final height = (image.height * maxSide / image.width).round();
      image = img.copyResize(
        image,
        width: maxSide,
        height: math.max(1, height),
        interpolation: img.Interpolation.linear,
      );
    } else {
      final width = (image.width * maxSide / image.height).round();
      image = img.copyResize(
        image,
        width: math.max(1, width),
        height: maxSide,
        interpolation: img.Interpolation.linear,
      );
    }
  }
  return <String, dynamic>{
    'bytes': Uint8List.fromList(img.encodeJpg(image, quality: 92)),
    'width': image.width,
    'height': image.height,
  };
}

class FaceService {
  FaceService._();

  static final FaceService instance = FaceService._();

  static const int inputSize = 112;
  static const int embeddingSize = 192;

  Interpreter? _interpreter;
  FaceDetector? _detector;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _interpreter = await Interpreter.fromAsset(
      'assets/models/mobile_face_net.tflite',
      options: InterpreterOptions()..threads = 2,
    );
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: false,
        enableTracking: false,
        enableClassification: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.12,
      ),
    );
    _initialized = true;
  }

  Future<Map<String, dynamic>?> normalizeImage(Uint8List bytes) async {
    return compute(_normalizeImageJob, <String, dynamic>{
      'bytes': bytes,
      'maxSide': 1280,
    });
  }

  Future<List<Face>> detectFaces(String imagePath) async {
    final detector = _detector;
    if (detector == null) throw StateError('FaceService.init() chaqirilmagan');
    return detector.processImage(InputImage.fromFilePath(imagePath));
  }

  Future<PreparedFace?> prepareFaceInput({
    required Uint8List imageBytes,
    required Face face,
  }) async {
    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final result = await compute(_prepareFaceJob, <String, dynamic>{
      'bytes': imageBytes,
      'left': face.boundingBox.left,
      'top': face.boundingBox.top,
      'width': face.boundingBox.width,
      'height': face.boundingBox.height,
      'leftEyeX': leftEye?.x.toDouble(),
      'leftEyeY': leftEye?.y.toDouble(),
      'rightEyeX': rightEye?.x.toDouble(),
      'rightEyeY': rightEye?.y.toDouble(),
      'roll': face.headEulerAngleZ,
    });
    if (result == null) return null;
    final inputBytes = result['input'] as Uint8List;
    final input = Float32List.fromList(
      inputBytes.buffer.asFloat32List(
        inputBytes.offsetInBytes,
        inputBytes.lengthInBytes ~/ 4,
      ),
    );
    return PreparedFace(
      input: input,
      alignedJpeg: result['aligned'] as Uint8List,
    );
  }

  Float32List? embed(Float32List input) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('FaceService.init() chaqirilmagan');
    }
    final tensor = interpreter.getInputTensor(0);
    tensor.data = input.buffer.asUint8List(
      input.offsetInBytes,
      input.lengthInBytes,
    );
    interpreter.invoke();

    final output = interpreter.getOutputTensor(0);
    final data = output.data;
    final raw = data.buffer.asFloat32List(data.offsetInBytes, embeddingSize);
    var norm = 0.0;
    for (final value in raw) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm <= 1e-9) return null;

    final normalized = Float32List(embeddingSize);
    for (var i = 0; i < embeddingSize; i++) {
      normalized[i] = raw[i] / norm;
    }
    return normalized;
  }

  Future<void> dispose() async {
    await _detector?.close();
    _detector = null;
    _interpreter?.close();
    _interpreter = null;
    _initialized = false;
  }
}
