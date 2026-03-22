import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show RouteSettings, Scaffold;
import 'package:webview_flutter/webview_flutter.dart';

import '../../views/widgets/app_colors.dart';

/// Loads [url] in a [WebViewWidget] with loading and error states.
///
/// Set [useScaffold] for edge-to-edge web content with a close control only (no
/// app bar). Used for the webview named route and by [WebViewUrlSheet].
class WebViewScreen extends StatefulWidget {
  final String url;

  /// When true, full-screen [Scaffold] with a close button overlay (no top bar).
  final bool useScaffold;

  const WebViewScreen({
    super.key,
    required this.url,
    this.useScaffold = false,
  });

  /// Builds from [RouteSettings.arguments]: a [String] URL, or a [Map] with
  /// `url` ([String]).
  factory WebViewScreen.fromRouteSettings(RouteSettings? settings) {
    final args = settings?.arguments;
    String url = '';
    if (args is String) {
      url = args;
    } else if (args is Map) {
      final u = args['url'];
      if (u is String) url = u;
    }
    return WebViewScreen(url: url, useScaffold: true);
  }

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
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
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = 'Failed to load page: ${error.description}';
                });
              }
            },
          ),
        );

      setState(() {
        _controller = controller;
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _controller != null) {
          _controller!.loadRequest(Uri.parse(widget.url));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to initialize WebView: $e';
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
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: CupertinoColors.systemGrey,
                    size: 28,
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

    if (widget.url.isEmpty) {
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
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                  });
                  _controller?.reload();
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

  static const double _kCloseSlot = 56;
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

  const WebViewUrlSheet({super.key, required this.url});

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
            WebViewScreen(url: url, useScaffold: true),
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
}) {
  showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => WebViewUrlSheet(url: url),
  );
}
