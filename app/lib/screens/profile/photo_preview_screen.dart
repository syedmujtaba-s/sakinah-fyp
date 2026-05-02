import 'package:flutter/material.dart';

/// Full-screen image viewer modeled after WhatsApp / Instagram media preview.
/// Tap anywhere to dismiss; pinch / drag to zoom and pan via [InteractiveViewer].
class PhotoPreviewScreen extends StatelessWidget {
  final ImageProvider image;
  final String heroTag;

  const PhotoPreviewScreen({
    super.key,
    required this.image,
    this.heroTag = 'profile-photo-preview',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Hero(
            tag: heroTag,
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image(image: image, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
