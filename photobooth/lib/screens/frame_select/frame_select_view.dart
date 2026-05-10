import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../../models/kiosk_frame_model.dart';
import '../../utils/constants.dart';
import '../../utils/route_args.dart';
import '../../utils/secure_image_url.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/centered_max_width.dart';
import '../../views/widgets/leading_with_alice.dart' show AppBarAliceAction;
import '../../views/widgets/theme_background.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart' as photo_image;
import 'frame_select_viewmodel.dart';

class FrameSelectScreen extends StatefulWidget {
  const FrameSelectScreen({super.key});

  @override
  State<FrameSelectScreen> createState() => _FrameSelectScreenState();
}

class _FrameSelectScreenState extends State<FrameSelectScreen> {
  late final FrameSelectViewModel _viewModel;
  PhotoModel? _photo;
  ThemeModel? _theme;
  bool _vmReady = false;
  bool _bootstrapStarted = false;

  /// True until we know the user stays on this route (≥2 frames). Avoids a one-frame
  /// flash of "Choose a frame" before [pushReplacementNamed] to `/generate` when auto-skipping.
  bool _deferFullFrameUi = true;

  @override
  void initState() {
    super.initState();
    _viewModel = FrameSelectViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_vmReady) return;
    final parsed = GenerateArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppSnackBar.showError(context, 'Missing photo or theme.');
        Navigator.of(context).maybePop();
      });
      return;
    }
    _photo = parsed.photo;
    _theme = parsed.theme;
    _vmReady = true;
    if (!_bootstrapStarted) {
      _bootstrapStarted = true;
      unawaited(_bootstrap());
    }
  }

  Future<void> _bootstrap() async {
    final loaded = await _viewModel.loadFrames();
    if (!mounted) return;
    if (!loaded) {
      setState(() => _deferFullFrameUi = false);
      return;
    }
    if (_viewModel.frames.length < 2) {
      final ok = await _viewModel.patchSelectedFrameAndSyncSession(
        includeSelectedFrameId: true,
        selectedFrameId: null,
      );
      if (!mounted) return;
      if (ok) {
        _goToGenerate();
      } else {
        setState(() => _deferFullFrameUi = false);
      }
      return;
    }
    setState(() => _deferFullFrameUi = false);
  }

  void _goToGenerate() {
    final photo = _photo;
    final theme = _theme;
    if (photo == null || theme == null) return;
    Navigator.pushReplacementNamed(
      context,
      AppConstants.kRouteGenerate,
      arguments: GenerateArgs(photo: photo, theme: theme),
    );
  }

  Future<void> _onPickFrame(KioskFrameModel frame) async {
    if (_viewModel.isSaving) return;
    final ok = await _viewModel.patchSelectedFrameAndSyncSession(
      includeSelectedFrameId: true,
      selectedFrameId: frame.id,
    );
    if (!mounted) return;
    if (ok) {
      _goToGenerate();
    } else if (_viewModel.errorMessage != null) {
      AppSnackBar.showError(context, _viewModel.errorMessage!);
    }
  }

  Future<void> _onPickNoFrame() async {
    if (_viewModel.isSaving) return;
    final ok = await _viewModel.patchSelectedFrameAndSyncSession(
      includeSelectedFrameId: true,
      selectedFrameId: 'none',
    );
    if (!mounted) return;
    if (ok) {
      _goToGenerate();
    } else if (_viewModel.errorMessage != null) {
      AppSnackBar.showError(context, _viewModel.errorMessage!);
    }
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final photo = _photo;

    if (theme == null || photo == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_deferFullFrameUi) {
      return ChangeNotifierProvider<FrameSelectViewModel>.value(
        value: _viewModel,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(child: ThemeBackground(theme: theme)),
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return ChangeNotifierProvider<FrameSelectViewModel>.value(
      value: _viewModel,
      child: Consumer<FrameSelectViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              forceMaterialTransparency: true,
              centerTitle: true,
              title: const Text(
                'Choose a frame',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                ),
              ),
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(20),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Pick an occasion frame or go without one.',
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
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: vm.isSaving
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
              actions: const [AppBarAliceAction()],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ThemeBackground(theme: theme),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top +
                          kToolbarHeight +
                          20 +
                          4,
                    ),
                    child: _buildBody(context, vm, photo, theme),
                  ),
                ),
                if (vm.isSaving)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black38,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    FrameSelectViewModel vm,
    PhotoModel photo,
    ThemeModel theme,
  ) {
    if (vm.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (vm.errorMessage != null && vm.frames.isEmpty) {
      return Center(
        child: CenteredMaxWidth(
          maxWidth: 400,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vm.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: vm.isSaving ? null : () => _bootstrap(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final w = MediaQuery.sizeOf(context).width;
    final crossAxisCount = w >= 900 ? 3 : 2;
    final frames = vm.frames;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: frames.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _NoFrameTile(
            photo: photo,
            enabled: !vm.isSaving,
            onTap: _onPickNoFrame,
          );
        }
        final frame = frames[index - 1];
        return _FrameTile(
          photo: photo,
          frame: frame,
          enabled: !vm.isSaving,
          onTap: () => _onPickFrame(frame),
        );
      },
    );
  }
}

class _NoFrameTile extends StatelessWidget {
  const _NoFrameTile({
    required this.photo,
    required this.enabled,
    required this.onTap,
  });

  final PhotoModel photo;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Colors.black26,
                        child: photo_image.imageFromXFileSized(
                          photo.imageFile,
                          constraints.maxWidth,
                          constraints.maxHeight,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Container(
                        alignment: Alignment.center,
                        color: Colors.black45,
                        child: Icon(
                          Icons.hide_image_outlined,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Text(
                'No frame',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrameTile extends StatelessWidget {
  const _FrameTile({
    required this.photo,
    required this.frame,
    required this.enabled,
    required this.onTap,
  });

  final PhotoModel photo;
  final KioskFrameModel frame;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final overlayUrl = SecureImageUrl.withSessionId(frame.overlayUrl);
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      photo_image.imageFromXFileSized(
                        photo.imageFile,
                        constraints.maxWidth,
                        constraints.maxHeight,
                        fit: BoxFit.cover,
                      ),
                      CachedNetworkImage(
                        imageUrl: overlayUrl,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        placeholder: const ColoredBox(color: Colors.transparent),
                        errorWidget: const ColoredBox(color: Colors.transparent),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Text(
                frame.name.isNotEmpty ? frame.name : 'Frame',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white38,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
