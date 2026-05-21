import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoColors, CupertinoIcons;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_selection_layout.dart';
import 'theme_selection_viewmodel.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../photo_capture/photo_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/theme_card.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/bottom_safe_area.dart';
import '../../views/widgets/falling_starfield_background.dart';
import '../../views/widgets/centered_max_width.dart';
import '../../services/theme_manager.dart';
import 'theme_model.dart';
import 'theme_preview_screen.dart';
import 'theme_selection_carousel_page.dart';
import 'theme_selection_on_continue_helpers.dart';
import 'theme_selection_loaded_body.dart';
import '../../utils/route_args.dart';

class ThemeSelectionScreen extends StatefulWidget {
  const ThemeSelectionScreen({super.key});

  @override
  State<ThemeSelectionScreen> createState() => _ThemeSelectionScreenState();
}

class _ThemeSelectionScreenState extends State<ThemeSelectionScreen> {
  PhotoModel? _photoFromCapture;
  bool _addOneMoreStyle = false;
  List<String> _usedThemeIds = const [];
  bool _isGenerating = false;
  Timer? _timer;
  Timer? _carouselTimer;
  Timer? _autoScrollResumeTimer;
  int _elapsedSeconds = 0;
  PageController? _pageController;
  ScrollController? _thumbScrollController;
  String? _prevCategoryId;
  bool _thumbScrollLayoutDone = false;
  int _lastCarouselThemeCount = 0;
  bool _isAutoScrollPaused = false;
  /// Tracks [PageController.viewportFraction] so we can rebuild when phone vs tablet layout changes.
  double? _carouselViewportFraction;

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startCarouselTimer(ThemeViewModel viewModel) {
    _carouselTimer?.cancel();
    _carouselTimer =
        Timer.periodic(AppConstants.kThemeCarouselAutoScrollInterval, (_) {
      if (!mounted) return;
      if (_isAutoScrollPaused) return;
      final list = viewModel.filteredThemes;
      if (list.isEmpty) return;
      final next = (viewModel.carouselIndex + 1) % list.length;
      _pageController?.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
      // View model is updated in onPageChanged when the animation completes
    });
  }

  /// Restarts the periodic timer so the next auto-advance is a full interval away
  /// (e.g. after user idle time ends).
  void _restartCarouselTimer(ThemeViewModel viewModel) {
    final count = viewModel.filteredThemes.length;
    if (count <= 1) {
      _lastCarouselThemeCount = count;
      _stopCarouselTimer();
      return;
    }
    _lastCarouselThemeCount = count;
    _startCarouselTimer(viewModel);
  }

  void _stopCarouselTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = null;
  }

  void _pauseAutoScrollTemporarily(ThemeViewModel viewModel) {
    _isAutoScrollPaused = true;
    _autoScrollResumeTimer?.cancel();
    _autoScrollResumeTimer = Timer(
      AppConstants.kThemeCarouselAutoScrollPauseDuration,
      () {
        if (!mounted) return;
        setState(() {
          _isAutoScrollPaused = false;
        });
        if (!viewModel.useCardGridLayout) {
          _restartCarouselTimer(viewModel);
        }
      },
    );
  }

  void _clearArmedSelection(ThemeViewModel viewModel) {
    viewModel.clearArmedTheme();
  }

  void _onCarouselThemeTap(ThemeViewModel viewModel, ThemeModel theme, int index) {
    final isCurrentCenter = viewModel.carouselIndex == index;
    if (isCurrentCenter) {
      viewModel.selectTheme(theme);
      viewModel.armTheme(theme);
      _pauseAutoScrollTemporarily(viewModel);
      return;
    }
    _clearArmedSelection(viewModel);
    viewModel.selectTheme(theme);
    viewModel.setCarouselIndex(index);
    _pageController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
    _pauseAutoScrollTemporarily(viewModel);
  }

  void _syncCarouselTimer(ThemeViewModel viewModel) {
    final count = viewModel.filteredThemes.length;
    if (count <= 1) {
      _lastCarouselThemeCount = count;
      _stopCarouselTimer();
      return;
    }
    if (_carouselTimer == null || _lastCarouselThemeCount != count) {
      _lastCarouselThemeCount = count;
      _startCarouselTimer(viewModel);
    }
  }

  @override
  void dispose() {
    _stopTimer();
    _stopCarouselTimer();
    _autoScrollResumeTimer?.cancel();
    _pageController?.dispose();
    _thumbScrollController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _thumbScrollController = ScrollController()
      ..addListener(() {
        if (mounted) setState(() {});
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = context.read<ThemeViewModel>();
      final themeManager = ThemeManager();
      if (themeManager.hasThemes) {
        viewModel.updateFromCache();
      }
      viewModel.loadThemes();
      viewModel.loadLayoutPreference();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parsed = ThemeSelectionArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed != null) {
      final photo = parsed.photo;
      final addOneMore = parsed.addOneMoreStyle;
      final usedIds = parsed.usedThemeIds;

      var changed = false;
      // Route args that omit `photo` (e.g. "add one more style") must not clear
      // an existing capture — only explicit non-null updates replace it.
      if (photo != null && _photoFromCapture != photo) {
        _photoFromCapture = photo;
        changed = true;
      }
      if (_addOneMoreStyle != addOneMore ||
          _usedThemeIds.length != usedIds.length ||
          !listEquals(_usedThemeIds, usedIds)) {
        _addOneMoreStyle = addOneMore;
        _usedThemeIds = usedIds;
        changed = true;
      }
      if (changed && mounted) setState(() {});
    }
  }

  Future<void> _onContinue(
      BuildContext context, ThemeViewModel viewModel) async {
    final selectedTheme = viewModel.armedTheme ?? viewModel.selectedTheme;
    if (selectedTheme == null) return;

    if (_addOneMoreStyle) {
      Navigator.of(context).pop(selectedTheme);
      return;
    }

    if (_photoFromCapture != null) {
      _startTimer();
      await themeSelectionContinueWithPhoto(
        context: context,
        viewModel: viewModel,
        photo: _photoFromCapture!,
        selectedTheme: selectedTheme,
        mounted: mounted,
        setGenerating: (v) {
          if (mounted) setState(() => _isGenerating = v);
        },
      );
      _stopTimer();
      return;
    }

    await themeSelectionContinueToCapture(
      context: context,
      mounted: mounted,
      setPhotoFromCapture: (photo) {
        if (mounted) setState(() => _photoFromCapture = photo);
      },
    );
  }

  Future<void> _openThemePreview(
    BuildContext context,
    ThemeViewModel viewModel,
    ThemeModel theme,
    int index,
  ) async {
    final imageUrl = ThemePreviewScreen.resolveSampleImageUrl(theme);
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        pageBuilder: (_, __, ___) {
          return ThemePreviewScreen(
            theme: theme,
            imageUrl: imageUrl,
            onSelect: () {
              viewModel.setCarouselIndex(index);
              viewModel.selectTheme(theme);
              viewModel.armTheme(theme);
              _pauseAutoScrollTemporarily(viewModel);
              Navigator.of(context).pop();
            },
          );
        },
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return PopScope(
      canPop: true,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              forceMaterialTransparency: true,
              centerTitle: true,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'PICK',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                ),
              ),
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(22),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Choose a style that speaks to you',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
                onPressed: () async {
                  final popped = await Navigator.of(context).maybePop();
                  if (!popped && context.mounted) {
                    Navigator.pushNamed(context, AppConstants.kRouteTerms);
                  }
                },
              ),
              // Layout toggle (web + mobile); Alice on wider layouts only.
              actions: [
                Selector<ThemeViewModel, bool>(
                  selector: (_, vm) => vm.useCardGridLayout,
                  builder: (context, useGrid, _) {
                    return IconButton(
                      icon: Icon(
                        useGrid ? Icons.view_carousel_outlined : Icons.grid_view,
                      ),
                      tooltip: useGrid ? 'Carousel layout' : 'Card grid layout',
                      color: Colors.white,
                      onPressed: () async {
                        final vm = context.read<ThemeViewModel>();
                        final next = !vm.useCardGridLayout;
                        if (next) {
                          _stopCarouselTimer();
                          _pageController?.dispose();
                          _pageController = null;
                          _carouselViewportFraction = null;
                        }
                        await vm.setUseCardGridLayout(next);
                        if (mounted) setState(() {});
                      },
                    );
                  },
                ),
                if (MediaQuery.sizeOf(context).width >= 520)
                  const AppBarAliceAction(),
              ],
              automaticallyImplyLeading: false,
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: Selector<ThemeViewModel, ThemeModel?>(
                    selector: (_, vm) => vm.selectedTheme,
                    builder: (_, theme, __) => _buildScreenBackgroundForTheme(context, theme),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      // Body is behind the app bar; account for app bar + subtitle height.
                      top: MediaQuery.paddingOf(context).top +
                          kToolbarHeight +
                          22 +
                          6,
                    ),
                    child: Consumer<ThemeViewModel>(
                      builder: (context, viewModel, child) {
                        final reducedBottomInset = math.max(
                          0.0,
                          effectiveBottomInset(context) - 40.0,
                        );
                        return ThemeSelectionLoadedBody(
                          viewModel: viewModel,
                          mounted: mounted,
                          bottomPadding: reducedBottomInset,
                          carousel: _buildCarouselAndThumbnails(
                            context,
                            viewModel,
                            isLandscape,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isGenerating)
            Positioned.fill(
              child: FullScreenLoader(
                text: 'Updating Session',
                loaderColor: Colors.blue,
                elapsedSeconds: _elapsedSeconds,
              ),
            ),
        ],
      ),
    );
  }

  String _themeSampleImageUrl(ThemeModel? theme) {
    final url = theme?.sampleImageUrl;
    if (url == null || url.isEmpty) return '';
    return ThemeSelectionLayoutMetrics.resolveThemeImageUrl(url);
  }

  Color? _parseThemeBackgroundColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return null;
    final hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }

  Widget _buildScreenBackgroundForTheme(BuildContext context, ThemeModel? theme) {
    final imageUrl = _themeSampleImageUrl(theme);
    final themeColor = theme != null ? _parseThemeBackgroundColor(theme.backgroundColor) : null;

    return Stack(
      key: ValueKey(theme?.id ?? 'no-theme'),
      fit: StackFit.expand,
      children: [
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            key: ValueKey(imageUrl),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: math.max(
                  640,
                  (MediaQuery.sizeOf(context).width * 0.7).round(),
                ),
                cacheHeight: math.max(
                  360,
                  (MediaQuery.sizeOf(context).height * 0.7).round(),
                ),
                filterQuality: FilterQuality.low,
                placeholder: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF0D2130),
                        Color(0xFF0A1628),
                        Color(0xFF050810),
                      ],
                    ),
                  ),
                ),
                errorWidget: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF0D2130),
                        Color(0xFF0A1628),
                        Color(0xFF050810),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (themeColor != null)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.35),
              ),
            ),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: imageUrl.isNotEmpty
                    ? [
                        const Color(0xFF0D2130).withValues(alpha: 0.75),
                        const Color(0xFF0A1628).withValues(alpha: 0.82),
                        const Color(0xFF050810).withValues(alpha: 0.88),
                      ]
                    : const [
                        Color(0xFF0D2130),
                        Color(0xFF0A1628),
                        Color(0xFF050810),
                      ],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: FallingStarfieldBackground(),
        ),
      ],
    );
  }

  // Category chips hidden by request. Keep constants/method removed to avoid dead code.

  /// Larger fraction on phone portrait so the hero card uses the screen; smaller on tablet / landscape.
  double _carouselViewportFractionFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return ThemeSelectionLayoutMetrics.carouselViewportFraction(
      width: size.width,
      height: size.height,
    );
  }

  int _themeGridCrossAxisCount(BuildContext context, bool isLandscape) {
    return ThemeSelectionLayoutMetrics.gridCrossAxisCount(
      width: MediaQuery.sizeOf(context).width,
      isLandscape: isLandscape,
    );
  }

  Widget _buildThemeContinueButton(
    BuildContext context,
    ThemeViewModel viewModel,
  ) {
    final enabled = viewModel.armedTheme != null &&
        !_isGenerating &&
        !viewModel.isUpdatingSession;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: CenteredMaxWidth(
          maxWidth: 360,
          child: SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: enabled
                  ? CupertinoColors.systemBlue
                  : CupertinoColors.systemGrey,
              borderRadius: BorderRadius.circular(14),
              onPressed: enabled ? () => _onContinue(context, viewModel) : null,
              child: const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardGridLayout(
    BuildContext context,
    ThemeViewModel viewModel,
    bool isLandscape,
  ) {
    final filtered = viewModel.filteredThemes;
    final crossAxis = _themeGridCrossAxisCount(context, isLandscape);
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxis,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final theme = filtered[index];
              final isSelected = viewModel.selectedTheme?.id == theme.id;
              return ThemeCard(
                theme: theme,
                isSelected: isSelected,
                selectedBorderWidth:
                    isSelected && viewModel.armedTheme?.id == theme.id ? 4.0 : 2.0,
                onTap: () {
                  viewModel.setCarouselIndex(index);
                  viewModel.selectTheme(theme);
                  viewModel.armTheme(theme);
                  _pauseAutoScrollTemporarily(viewModel);
                },
                onPreview: () => _openThemePreview(context, viewModel, theme, index),
                showSelectedLabel: _addOneMoreStyle &&
                    _usedThemeIds.contains(theme.id),
                onSelectPressed: null,
              );
            },
          ),
        ),
        _buildThemeContinueButton(context, viewModel),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCarouselAndThumbnails(
    BuildContext context,
    ThemeViewModel viewModel,
    bool isLandscape,
  ) {
    final filtered = viewModel.filteredThemes;
    if (filtered.isEmpty) {
      _stopCarouselTimer();
      return const Center(child: Text('No themes in this category'));
    }

    if (viewModel.useCardGridLayout) {
      _stopCarouselTimer();
      return _buildCardGridLayout(context, viewModel, isLandscape);
    }

    final vf = _carouselViewportFractionFor(context);
    if (_pageController == null || _carouselViewportFraction != vf) {
      final initial = viewModel.carouselIndex.clamp(0, filtered.length - 1);
      _pageController?.dispose();
      _pageController = PageController(
        viewportFraction: vf,
        initialPage: initial,
      );
      _carouselViewportFraction = vf;
    }

    // Start/stop carousel timer only after controllers are stable for this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncCarouselTimer(viewModel);
    });

    if (_prevCategoryId != viewModel.selectedCategoryId) {
      _prevCategoryId = viewModel.selectedCategoryId;
      _thumbScrollLayoutDone = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController!.hasClients) {
          _pageController!.jumpToPage(0);
        }
      });
    }

    return Column(
      children: [
        Expanded(
          flex: 7,
          child: PageView.builder(
            controller: _pageController,
            itemCount: filtered.length,
            onPageChanged: (i) {
              viewModel.setCarouselIndex(i);
            },
            itemBuilder: (context, index) {
              final theme = filtered[index];
              return ThemeSelectionCarouselPage(
                theme: theme,
                index: index,
                pageController: _pageController!,
                viewModel: viewModel,
                fallbackCarouselIndex: viewModel.carouselIndex,
                addOneMoreStyle: _addOneMoreStyle,
                usedThemeIds: _usedThemeIds,
                onTap: () => _onCarouselThemeTap(viewModel, theme, index),
                onPreview: () =>
                    _openThemePreview(context, viewModel, theme, index),
              );
            },
          ),
        ),
        _buildThemeContinueButton(context, viewModel),
        const SizedBox(height: 4),
        _buildThumbnails(context, viewModel, isLandscape),
      ],
    );
  }

  static const double _thumbWidth = 56;
  static const double _thumbSpacing = 8;
  static const double _thumbScrollAmount = 240;

  Widget _buildThumbnails(
    BuildContext context,
    ThemeViewModel viewModel,
    bool isLandscape,
  ) {
    final filtered = viewModel.filteredThemes;
    final hasClients = _thumbScrollController?.hasClients ?? false;
    final offset = hasClients ? _thumbScrollController!.offset : 0.0;
    final maxExtent = hasClients
        ? _thumbScrollController!.position.maxScrollExtent
        : 0.0;
    final canScrollLeft = hasClients && offset > 8;
    final canScrollRight = hasClients && maxExtent > 8 && offset < maxExtent - 8;

    if (filtered.isNotEmpty && hasClients && !_thumbScrollLayoutDone) {
      _thumbScrollLayoutDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }

    const double thumbHeight = 60.0;
    const double verticalPadding = 4.0;
    const double borderMargin = 3.0;
    const rowHeight =
        thumbHeight + borderMargin * 2 + verticalPadding * 2;

    const double sidePadding = _thumbWidth;

    return SizedBox(
      height: rowHeight,
      child: Stack(
        children: [
          Row(
            children: [
              const SizedBox(width: sidePadding),
              Expanded(
                child: ListView.builder(
                  controller: _thumbScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: verticalPadding),
                  clipBehavior: Clip.none,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final theme = filtered[index];
                    final isActive = viewModel.carouselIndex == index;
                    return Padding(
                      padding: const EdgeInsets.only(
                        left: borderMargin,
                        top: borderMargin,
                        right: _thumbSpacing,
                        bottom: borderMargin,
                      ),
                      child: GestureDetector(
                        onTap: () {
                          _clearArmedSelection(viewModel);
                          viewModel.setCarouselIndex(index);
                          _pageController?.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                          _pauseAutoScrollTemporarily(viewModel);
                        },
                        child: Container(
                          width: _thumbWidth,
                          height: thumbHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _ThemeThumbImage(theme: theme),
                              if (!isActive)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: sidePadding),
            ],
          ),
          if (canScrollLeft)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: sidePadding,
              child: Center(
                child: _buildThumbArrow(context, isLeft: true),
              ),
            ),
          if (canScrollRight)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: sidePadding,
              child: Center(
                child: _buildThumbArrow(context, isLeft: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbArrow(BuildContext context, {required bool isLeft}) {
    return IconButton(
      onPressed: () {
        if (_thumbScrollController == null || !_thumbScrollController!.hasClients) return;
        final pos = _thumbScrollController!.position;
        final current = pos.pixels;
        final target = isLeft
            ? (current - _thumbScrollAmount).clamp(0.0, pos.maxScrollExtent)
            : (current + _thumbScrollAmount).clamp(0.0, pos.maxScrollExtent);
        _thumbScrollController!.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
      icon: Icon(
        isLeft ? CupertinoIcons.chevron_left : CupertinoIcons.chevron_right,
        color: Colors.white.withValues(alpha: 0.9),
        size: 28,
      ),
    );
  }

}

class _ThemeThumbImage extends StatelessWidget {
  final ThemeModel theme;

  const _ThemeThumbImage({required this.theme});

  String _getImageUrl() {
    final url = theme.sampleImageUrl;
    if (url == null || url.isEmpty) return '';
    return ThemeSelectionLayoutMetrics.resolveThemeImageUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final url = _getImageUrl();
    if (url.isEmpty) {
      return Container(
        color: Colors.grey.shade300,
        child: const Icon(CupertinoIcons.photo, size: 32),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      cacheWidth: 140,
      cacheHeight: 160,
      filterQuality: FilterQuality.low,
      placeholder: const Center(
        child: CircularProgressIndicator(),
      ),
      errorWidget: const Icon(
        CupertinoIcons.photo,
        size: 32,
      ),
    );
  }
}

