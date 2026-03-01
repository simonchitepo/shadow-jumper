import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_windows/webview_windows.dart';

class DesktopAdBanner extends StatefulWidget {
  const DesktopAdBanner({
    super.key,
    this.height = 90,
  });

  final double height;

  @override
  State<DesktopAdBanner> createState() => _DesktopAdBannerState();
}

class _DesktopAdBannerState extends State<DesktopAdBanner> {
  final _controller = WebviewController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _controller.initialize();

    // Load the HTML from Flutter assets and inject it directly.
    final html = await rootBundle.loadString('assets/ads/banner.html');
    final dataUrl = Uri.dataFromString(
      html,
      mimeType: 'text/html',
      encoding: utf8,
    ).toString();

    await _controller.loadUrl(dataUrl);

    // Optional “lock down”
    _controller.setBackgroundColor(Colors.transparent);

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return SizedBox(height: widget.height);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Webview(_controller),
    );
  }
}