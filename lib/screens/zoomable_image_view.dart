/// Full-screen image viewer with pinch-to-zoom and pan.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
///
/// License: https://opensource.org/license/gpl-3-0

library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A full-screen, dismissible viewer that shows [bytes] as an image the user
/// can pinch to zoom and drag to pan. Double-tap toggles between fit and 2.5x.

class ZoomableImageView extends StatefulWidget {
  const ZoomableImageView({super.key, required this.bytes, this.title});

  final Uint8List bytes;
  final String? title;

  /// Opens the viewer as a full-screen route.

  static Future<void> show(
    BuildContext context,
    Uint8List bytes, {
    String? title,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ZoomableImageView(bytes: bytes, title: title),
      ),
    );
  }

  @override
  State<ZoomableImageView> createState() => _ZoomableImageViewState();
}

class _ZoomableImageViewState extends State<ZoomableImageView> {
  final _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_controller.value != Matrix4.identity()) {
      // Already zoomed — reset to fit.
      _controller.value = Matrix4.identity();
      return;
    }
    final pos = _doubleTapDetails?.localPosition;
    if (pos == null) return;
    // Zoom to 2.5x centred on the tap point.
    const scale = 2.5;
    final x = -pos.dx * (scale - 1);
    final y = -pos.dy * (scale - 1);
    _controller.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.title == null ? null : Text(widget.title!),
      ),
      body: GestureDetector(
        onDoubleTapDown: (d) => _doubleTapDetails = d,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.memory(widget.bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
