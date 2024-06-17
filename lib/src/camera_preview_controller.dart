import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class Frame {
  final DateTime timestamp;
  final String image;

  Frame({required this.image, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  factory Frame.fromBytes(Uint8List bytes) => Frame(
        image: 'data:image/jpeg;base64,${base64Encode(bytes)}',
      );

  Future<Uint8List> get imageBytes => Isolate.run(
        () => base64Decode(image.split(',').last),
      );

  factory Frame.fromJson(Map<String, dynamic> json) {
    return Frame(
      image: json['image'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'image': image,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class CameraPreviewController extends ChangeNotifier {
  static const _framesPerSecond = 1.0;
  static const _keepFramesFor = Duration(seconds: 30);
  static const _notifyListenersThrottle = Duration(seconds: 10);

  DateTime? _lastFrameTimestamp = DateTime.now();
  DateTime? _lastNotifiedTimestamp = DateTime.now();

  final List<Frame> frames = [];

  List<Frame> getFrames({DateTime? from, DateTime? to}) => frames.where(
        (frame) {
          if (from != null && frame.timestamp.isBefore(from)) return false;
          if (to != null && frame.timestamp.isAfter(to)) return false;
          return true;
        },
      ).toList();

  void onImageStream(CameraImage image) async {
    final now = DateTime.now();
    if (now.difference(_lastFrameTimestamp!) <
        const Duration(seconds: 1 ~/ _framesPerSecond)) {
      return;
    }
    _lastFrameTimestamp = now;

    final frame = await Isolate.run(() {
      final rawImage = img.copyResize(
        img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: image.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        ),
        width: 480,
      );
      final jpeg = img.encodeJpg(rawImage, quality: 70);

      final frame = Frame.fromBytes(jpeg);
      return frame;
    });
    frames.add(frame);
    debugPrint(
      'Frame added: ${frame.timestamp}, size: ${frame.image.length.formatBytes()}',
    );

    final keepFramesUntil = now.subtract(_keepFramesFor);
    frames.removeWhere((frame) => frame.timestamp.isBefore(keepFramesUntil));

    if (now.difference(_lastNotifiedTimestamp!) > _notifyListenersThrottle) {
      _lastNotifiedTimestamp = now;
      debugPrint('Notifying listeners...  ${frame.timestamp}');
      notifyListeners();
    }
  }
}

extension _CameraImagePlaneX on int {
  String formatBytes({int fractionDigits = 0}) {
    if (this <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
    final i = (log(this) / log(1024)).floor();
    return '${(this / pow(1024, i)).toStringAsFixed(fractionDigits)} ${suffixes[i]}';
  }
}
