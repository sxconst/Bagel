import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Draws a modern, slightly rounder “pin” and paints
/// the text “[inUse]/[total]” inside the circle. 
/// Returns a BitmapDescriptor you can hand to GoogleMap’s Marker.
Future<BitmapDescriptor> createCourtMarkerIcon({
  required int inUse,
  required int total,
  Color backgroundColor = const Color(0xFF388E3C), // green accent by default
  Color textColor = Colors.white,
}) async {
  // 1) Decide the overall canvas size
  //    We’ll draw a circle of radius 30px, plus a pointer ~40px tall.
  const int width = 100;
  const int height = 120;
  const double circleRadius = 30.0;
  final double circleCenterX = width / 2;
  final double circleCenterY = circleRadius; // y = 30

  // 2) Create a PictureRecorder and Canvas
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );

  // 3) Paint the circle (slightly round, modern color)
  final Paint circlePaint = Paint()..color = backgroundColor;
  canvas.drawCircle(
    Offset(circleCenterX, circleCenterY),
    circleRadius,
    circlePaint,
  );

  // 4) Paint a small triangular “pointer” under the circle
  //    so it looks like a map pin. Pointer’s base is at circle bottom.
  final double pointerBaseY = circleCenterY + circleRadius; // = 60
  final double pointerHeight = 40.0;
  final double pointerHalfWidth = 12.0;

  final Path pointerPath = Path()
    ..moveTo(circleCenterX - pointerHalfWidth, pointerBaseY)
    ..lineTo(circleCenterX + pointerHalfWidth, pointerBaseY)
    ..lineTo(circleCenterX, pointerBaseY + pointerHeight)
    ..close();

  final Paint pointerPaint = Paint()..color = backgroundColor;
  canvas.drawPath(pointerPath, pointerPaint);

  // 5) Draw a thin white border around the circle and pointer for a “cutout” effect
  //    (optional, but gives it a more modern look).
  final Paint borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0;

  // Circle border
  canvas.drawCircle(
    Offset(circleCenterX, circleCenterY),
    circleRadius,
    borderPaint,
  );

  // Pointer border
  final Path pointerBorderPath = Path()
    ..moveTo(circleCenterX - pointerHalfWidth, pointerBaseY)
    ..lineTo(circleCenterX, pointerBaseY + pointerHeight)
    ..lineTo(circleCenterX + pointerHalfWidth, pointerBaseY)
    ..arcToPoint(
      Offset(circleCenterX - pointerHalfWidth, pointerBaseY),
      radius: const Radius.circular(1), // tiny radius to close path
    )
    ..close();
  canvas.drawPath(pointerBorderPath, borderPaint);

  // 6) Paint the fraction text (“inUse/total”) centered in the circle
  final String fractionText = '$inUse/$total';
  final TextSpan span = TextSpan(
    text: fractionText,
    style: TextStyle(
      color: textColor,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    ),
  );
  final TextPainter tp = TextPainter(
    text: span,
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  );
  tp.layout();

  final Offset textOffset = Offset(
    circleCenterX - tp.width / 2,
    circleCenterY - tp.height / 2,
  );
  tp.paint(canvas, textOffset);

  // 7) Convert the recording to an Image, then to PNG bytes
  final ui.Image markerAsImage =
      await recorder.endRecording().toImage(width, height);
  final ByteData? byteData = await markerAsImage.toByteData(
    format: ui.ImageByteFormat.png,
  );
  final Uint8List pngBytes = byteData!.buffer.asUint8List();

  // 8) Return a BitmapDescriptor from those bytes
  return BitmapDescriptor.bytes(pngBytes);
}
