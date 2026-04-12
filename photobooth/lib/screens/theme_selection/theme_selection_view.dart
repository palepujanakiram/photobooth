import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoColors, CupertinoIcons;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_selection_viewmodel.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../photo_capture/photo_model.dart';
import '../../utils/constants.dart';
import '../../utils/app_config.dart';
import '../../views/widgets/theme_card.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/bottom_safe_area.dart';
import '../../views/widgets/falling_starfield_background.dart';
import '../../services/theme_manager.dart';
import 'theme_model.dart';

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
  String? _armedThemeId;
  String? _pendingArmThemeId;
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
    _carouselTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
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

  void _stopCarouselTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = null;
  }

  void _pauseAutoScrollTemporarily() {
    _isAutoScrollPaused = true;
    _autoScrollResumeTimer?.cancel();
    _autoScrollResumeTimer = Timer(
      AppConstants.kThemeCarouselAutoScrollPauseDuration,
      () {
      if (!mounted) return;
      setState(() {
        _isAutoScrollPaused = false;
        _armedThemeId = null;
      });
    },
    );
  }

  void _clearArmedSelection() {
    if (_armedThemeId == null &&
        _pendingArmThemeId == null &&
        !_isAutoScrollPaused) {
      return;
    }
    _autoScrollResumeTimer?.cancel();
    if (mounted) {
      setState(() {
        _armedThemeId = null;
        _pendingArmThemeId = null;
        _isAutoScrollPaused = false;
      });
    }
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
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map) {
      final photo = args['photo'] as PhotoModel?;
      final addOneMore = args['addOneMoreStyle'] == true;
      final used = args['usedThemeIds'];
      final usedIds = used is List
          ? used.map((e) => e.toString()).toList()
          : <String>[];
      if (_photoFromCapture != photo ||
          _addOneMoreStyle != addOneMore ||
          _usedThemeIds.length != usedIds.length ||
          !listEquals(_usedThemeIds, usedIds)) {
        _photoFromCapture = photo;
        _addOneMoreStyle = addOneMore;
        _usedThemeIds = usedIds;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _onContinue(
      BuildContext context, ThemeViewModel viewModel) async {
    final selectedTheme = viewModel.selectedTheme;
    if (selectedTheme == null) return;

    if (_addOneMoreStyle) {
      Navigator.of(context).pop(selectedTheme);
      return;
    }

    final currentContext = context;
    if (_photoFromCapture != null) {
      _startTimer();
      setState(() => _isGenerating = true);
      bool success = false;
      try {
        success = await viewModel.updateSessionWithTheme();
        if (!mounted || !currentContext.mounted) return;
        if (success) {
          Navigator.pushNamed(
            currentContext,
            AppConstants.kRouteGenerate,
            arguments: {
              'photo': _photoFromCapture,
              'theme': selectedTheme,
            },
          );
        } else {
          AppSnackBar.showError(
            currentContext,
            viewModel.errorMessage ??
                'Failed to update session with theme',
          );
        }
      } catch (e) {
        if (mounted && currentContext.mounted) {
          AppSnackBar.showError(
            currentContext,
            'An error occurred: ${e.toString()}',
          );
        }
      } finally {
        _stopTimer();
        if (mounted) setState(() => _isGenerating = false);
      }
    } else {
      Navigator.pushNamed(currentContext, AppConstants.kRouteCapture).then((result) {
        if (!mounted || !currentContext.mounted || result == null || result is! PhotoModel) return;
        Navigator.pushReplacementNamed(
          currentContext,
          AppConstants.kRouteHome,
          arguments: {'photo': result},
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return PopScope(
      canPop: _addOneMoreStyle,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && !_addOneMoreStyle) {
          Navigator.pushNamed(context, AppConstants.kRouteTerms);
        }
      },
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
                'Select a theme',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
                onPressed: () {
                  if (_addOneMoreStyle) {
                    Navigator.of(context).pop();
                  } else {
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
                      top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                    ),
                    child: Consumer<ThemeViewModel>(
                      builder: (context, viewModel, child) {
                      if (viewModel.showNoThemesMessage) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          final vm = context.read<ThemeViewModel>();
                          if (vm.showNoThemesMessage) {
                            AppSnackBar.showError(context, 'No themes available');
                            vm.clearNoThemesMessage();
                          }
                        });
                      }
                      if (viewModel.isLoading) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (viewModel.hasError) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                CupertinoIcons.exclamationmark_triangle,
                                size: 64,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                viewModel.errorMessage ?? 'Unknown error',
                                style: const TextStyle(
                                    fontSize: 16, color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              TextButton(
                                onPressed: () => viewModel.loadThemes(),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }
                      if (viewModel.themes.isEmpty) {
                        return const Center(
                          child: Text(
                            'No themes available',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      }

                      final reducedBottomInset = math.max(
                        0.0,
                        effectiveBottomInset(context) - 40.0,
                      );
                      return Padding(
                        padding: EdgeInsets.only(bottom: reducedBottomInset),
                        child: Column(
                          children: [
                            _buildCategoryTabs(context, viewModel),
                            Expanded(
                              child: _buildCarouselAndThumbnails(
                                context,
                                viewModel,
                                isLandscape,
                              ),
                            ),
                          ],
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
    if (theme?.sampleImageUrl == null || theme!.sampleImageUrl!.isEmpty) {
      return '';
    }
    final imageUrl = theme.sampleImageUrl!;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final baseUrl = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
    return '$baseUrl$path';
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

  static const double _categorySidePadding = 24.0;
  static const double _categoryChipGap = 8.0;
  static const double _categoryChipRowHeight = 48.0;
  static const int _maxVisibleCategoryChips = 5;

  /// Larger fraction on phone portrait so the hero card uses the screen; smaller on tablet / landscape.
  double _carouselViewportFractionFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    if (w < AppConstants.kTabletBreakpoint) {
      return h >= w ? 0.76 : 0.52;
    }
    if (w < 900) {
      return 0.42;
    }
    return AppConstants.kThemeCarouselViewportFraction;
  }

  Widget _buildCategoryTabs(BuildContext context, ThemeViewModel viewModel) {
    final ids = viewModel.categoryIds;
    final screenW = MediaQuery.sizeOf(context).width;
    final chipW = screenW < 400 ? 78.0 : 90.0;
    final itemExtent = chipW + _categoryChipGap;
    final maxRowWidth = _maxVisibleCategoryChips * itemExtent;
    final rowW = math.min(maxRowWidth, screenW - _categorySidePadding * 2);

    return Padding(
      padding: const EdgeInsets.only(
        top: 4,
        bottom: 10,
        left: _categorySidePadding,
        right: _categorySidePadding,
      ),
      child: Center(
        child: SizedBox(
          width: rowW,
          height: _categoryChipRowHeight,
          child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: ids.length,
          itemBuilder: (context, index) {
          final id = ids[index];
          final isActive = viewModel.selectedCategoryId == id;
          return SizedBox(
            width: itemExtent,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: chipW,
                child: Center(
                  child: Material(
                    color: isActive
                        ? const Color(0xFF2A6DF4)
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _armedThemeId = null;
                          _pendingArmThemeId = null;
                        });
                        viewModel.selectCategory(id);
                        if (_pageController != null &&
                            viewModel.filteredThemes.isNotEmpty) {
                          _pageController!.animateToPage(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Center(
                          child: Text(
                            viewModel.getCategoryDisplayName(id),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: screenW < 400 ? 13 : 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
          ),
        ),
      ),
    );
  }

  /// Responsive columns for card-grid theme list (web + Android).
  int _themeGridCrossAxisCount(BuildContext context, bool isLandscape) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1200) return isLandscape ? 5 : 4;
    if (w >= 900) return 4;
    if (w >= 700) return 3;
    return 2;
  }

  Widget _buildThemeContinueButton(
    BuildContext context,
    ThemeViewModel viewModel,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 16),
          color: (viewModel.selectedTheme != null &&
                  _armedThemeId == viewModel.selectedTheme!.id &&
                  !_isGenerating &&
                  !viewModel.isUpdatingSession)
              ? CupertinoColors.systemBlue
              : CupertinoColors.systemGrey,
          borderRadius: BorderRadius.circular(12),
          onPressed: (viewModel.selectedTheme != null &&
                  _armedThemeId == viewModel.selectedTheme!.id &&
                  !_isGenerating &&
                  !viewModel.isUpdatingSession)
              ? () => _onContinue(context, viewModel)
              : null,
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
                    isSelected && _armedThemeId == theme.id ? 4.0 : 2.0,
                onTap: () {
                  viewModel.setCarouselIndex(index);
                  viewModel.selectTheme(theme);
                  setState(() {
                    _armedThemeId = theme.id;
                    _pendingArmThemeId = null;
                  });
                  _pauseAutoScrollTemporarily();
                },
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

    _syncCarouselTimer(viewModel);

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
          flex: 6,
          child: PageView.builder(
            controller: _pageController,
            itemCount: filtered.length,
            onPageChanged: (i) {
              final currentTheme = filtered[i];
              if (_pendingArmThemeId == currentTheme.id) {
                setState(() {
                  _pendingArmThemeId = null;
                  _armedThemeId = currentTheme.id;
                });
                _pauseAutoScrollTemporarily();
              } else {
                _clearArmedSelection();
              }
              viewModel.setCarouselIndex(i);
            },
            itemBuilder: (context, index) {
              final theme = filtered[index];
              final isSelected =
                  viewModel.selectedTheme?.id == theme.id;
              return AnimatedBuilder(
                animation: _pageController!,
                builder: (context, _) {
                  final hasPage = _pageController!.position.hasContentDimensions &&
                      _pageController!.page != null;
                  final page = hasPage
                      ? _pageController!.page!
                      : viewModel.carouselIndex.toDouble();
                  final offset = page - index;
                  final delta = offset.abs();
                  final scale = (1.0 - (delta * 0.28)).clamp(0.48, 1.15);
                  final opacity = (1.0 - (delta * 0.22)).clamp(0.5, 1.0);
                  final isCenter = delta < 0.5;
                  const perspective = 0.001;
                  final angleY = offset * 0.5;
                  final matrix = Matrix4.identity()
                    ..setEntry(3, 2, perspective)
                    ..rotateY(angleY)
                    ..scaleByDouble(scale, scale, 1.0, 1.0);
                  final aspectRatio = isCenter
                      ? AppConstants.themeCardSlotAspectRatio(context)
                      : AppConstants.themeCarouselSideAspectRatio(context);
                  return Opacity(
                    opacity: opacity,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: matrix,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 16),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: aspectRatio,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(alpha: 0.6),
                                    blurRadius: 40,
                                    offset: const Offset(0, 20),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ThemeCard(
                                theme: theme,
                                isSelected: isSelected,
                                selectedBorderWidth: isSelected &&
                                        _armedThemeId == theme.id
                                    ? 4.0
                                    : 2.0,
                                onTap: () {
                                  final isCurrentCenter =
                                      viewModel.carouselIndex == index;
                                  if (isCurrentCenter) {
                                    viewModel.selectTheme(theme);
                                    setState(() {
                                      _pendingArmThemeId = null;
                                      _armedThemeId = theme.id;
                                    });
                                    _pauseAutoScrollTemporarily();
                                    return;
                                  }
                                  _clearArmedSelection();
                                  setState(() {
                                    _pendingArmThemeId = theme.id;
                                  });
                                  viewModel.selectTheme(theme);
                                  viewModel.setCarouselIndex(index);
                                  _pageController?.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 400),
                                    curve: Curves.easeOut,
                                  );
                                },
                                showSelectedLabel: _addOneMoreStyle &&
                                    _usedThemeIds.contains(theme.id),
                                onSelectPressed: null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        _buildThemeContinueButton(context, viewModel),
        const SizedBox(height: 8),
        _buildThumbnails(context, viewModel, isLandscape),
      ],
    );
  }

  static const double _thumbWidth = 70;
  static const double _thumbSpacing = 10;
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

    const double thumbHeight = 72.0;
    const double verticalPadding = 8.0;
    const double borderMargin = 4.0;
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
                          _clearArmedSelection();
                          viewModel.setCarouselIndex(index);
                          _pageController?.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
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
    if (theme.sampleImageUrl == null || theme.sampleImageUrl!.isEmpty) {
      return '';
    }
    final imageUrl = theme.sampleImageUrl!;
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final baseUrl = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final relativePath =
        imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
    return '$baseUrl$relativePath';
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

