import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RouteSettings, Scaffold;
import 'package:flutter/services.dart' show rootBundle;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/platform_capabilities.dart';
import '../../views/widgets/app_colors.dart';

/// Loads [url] (or bundled [flutterAssetPath]) in a [WebViewWidget].
///
/// JavaScript and unrestricted navigation are intentional: callers pass only
/// operator-configured HTTPS URLs (terms, help, kiosk content) from [AppConfig],
/// not arbitrary user input. Mark Sonar security hotspots **Safe** after review.
///
/// Prefer [flutterAssetPath] for legal pages on kiosks — Android TV WebViews
/// often cannot reach public hosts (`net::ERR_ADDRESS_UNREACHABLE`) even when
/// the tablet on the same venue network can.
///
/// Set [useScaffold] for edge-to-edge web content with a close control only (no
/// app bar). Used for the webview named route and by [WebViewUrlSheet].
class WebViewScreen extends StatefulWidget {
  final String url;

  /// When set, load this Flutter asset (HTML) instead of [url].
  final String? flutterAssetPath;

  /// When true, full-screen [Scaffold] with a close button overlay (no top bar).
  final bool useScaffold;

  const WebViewScreen({
    super.key,
    required this.url,
    this.flutterAssetPath,
    this.useScaffold = false,
  });

  /// Builds from [RouteSettings.arguments]: a [String] URL, or a [Map] with
  /// `url` ([String]) and optional `flutterAssetPath` ([String]).
  factory WebViewScreen.fromRouteSettings(RouteSettings? settings) {
    final args = settings?.arguments;
    String url = '';
    String? assetPath;
    if (args is String) {
      url = args;
    } else if (args is Map) {
      final u = args['url'];
      if (u is String) url = u;
      final a = args['flutterAssetPath'];
      if (a is String) assetPath = a;
    }
    return WebViewScreen(
      url: url,
      flutterAssetPath: assetPath,
      useScaffold: true,
    );
  }

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  bool get _hasAsset =>
      (widget.flutterAssetPath ?? '').trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!supportsEmbeddedWebView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openExternallyAndPop());
      });
      return;
    }
    unawaited(_initializeWebView());
  }

  Future<void> _openExternallyAndPop() async {
    final url = widget.url.trim();
    if (url.isEmpty) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _loadDocument(WebViewController controller) async {
    final asset = widget.flutterAssetPath?.trim() ?? '';
    if (asset.isNotEmpty) {
      // loadHtmlString works on Android TV / tablet / web; avoids network DNS.
      final html = await rootBundle.loadString(asset);
      await controller.loadHtmlString(html);
      return;
    }
    await controller.loadRequest(Uri.parse(widget.url));
  }

  Future<void> _initializeWebView() async {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
              }
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              // Bundled HTML should not hit the network; ignore spurious
              // subresource errors when the main document already loaded.
              if (_hasAsset) return;
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = 'Failed to load page: ${error.description}';
                });
              }
            },
          ),
        );

      if (mounted) {
        setState(() {
          _controller = controller;
          _isLoading = true;
          _errorMessage = null;
        });
      }

      await _loadDocument(controller);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to initialize WebView: $e';
        });
      }
    }
  }

  Future<void> _retryLoad() async {
    final controller = _controller;
    if (controller == null) {
      await _initializeWebView();
      return;
    }
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      await _loadDocument(controller);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load page: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);

    if (!widget.useScaffold) {
      return body;
    }

    final appColors = AppColors.of(context);
    return Scaffold(
      backgroundColor: appColors.backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          body,
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: CupertinoButton(
                  padding: const EdgeInsets.all(12),
                  minimumSize: const Size(48, 48),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: CupertinoColors.systemGrey,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final appColors = AppColors.of(context);

    if (!supportsEmbeddedWebView) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Opening in your browser…',
            style: TextStyle(color: appColors.textColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!_hasAsset && widget.url.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No URL provided',
            style: TextStyle(color: appColors.textColor),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (_errorMessage != null && !_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 48,
                color: CupertinoColors.systemRed,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                  fontSize: 14,
                  color: appColors.textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                color: CupertinoColors.systemBlue,
                onPressed: () {
                  unawaited(_retryLoad());
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading)
          const Center(child: CupertinoActivityIndicator()),
      ],
    );
  }
}

/// Top strip above the webview: drag handle + swipe-down to dismiss the sheet.
/// Right padding matches [WebViewScreen] close control (top-right).
class _WebViewSheetTopChrome extends StatefulWidget {
  final VoidCallback onDismiss;

  const _WebViewSheetTopChrome({required this.onDismiss});

  @override
  State<_WebViewSheetTopChrome> createState() => _WebViewSheetTopChromeState();
}

class _WebViewSheetTopChromeState extends State<_WebViewSheetTopChrome> {
  double _dragDown = 0;

  /// Matches [WebViewScreen] close control (padding + minimumSize + icon).
  static const double _kCloseSlot = 80;
  static const double _kStripHeight = 52;
  static const double _kDismissDistance = 56;
  static const double _kDismissVelocity = 400;

  void _resetDrag() => _dragDown = 0;

  void _onDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v > _kDismissVelocity || _dragDown > _kDismissDistance) {
      widget.onDismiss();
    }
    _resetDrag();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: _kStripHeight,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: _kCloseSlot),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: (_) => _resetDrag(),
                onVerticalDragUpdate: (details) {
                  if (details.delta.dy > 0) {
                    _dragDown += details.delta.dy;
                  }
                },
                onVerticalDragEnd: _onDragEnd,
                onVerticalDragCancel: _resetDrag,
              ),
            ),
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: IgnorePointer(
                  child: SizedBox(
                    width: 40,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey3,
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cupertino modal sheet: web content edge-to-edge with close only (same as
/// [WebViewScreen] with [WebViewScreen.useScaffold]) plus swipe-down on the top strip.
class WebViewUrlSheet extends StatelessWidget {
  final String url;
  final String? flutterAssetPath;

  const WebViewUrlSheet({
    super.key,
    required this.url,
    this.flutterAssetPath,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SizedBox(
        height: screenHeight * 0.9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            WebViewScreen(
              url: url,
              flutterAssetPath: flutterAssetPath,
              useScaffold: true,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _WebViewSheetTopChrome(
                onDismiss: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Presents [WebViewUrlSheet] as a Cupertino modal (e.g. consent legal page).
void showWebViewUrlSheet(
  BuildContext context, {
  required String url,
  String? flutterAssetPath,
}) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => WebViewUrlSheet(
      url: url,
      flutterAssetPath: flutterAssetPath,
    ),
  );
}
