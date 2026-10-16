import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muzo/providers/navigation_provider.dart';
import 'package:muzo/providers/player_provider.dart';
import 'package:muzo/providers/overlay_scenes.dart';
import 'package:muzo/widgets/hivefy_mini_player.dart';
import 'package:muzo/services/share_service.dart';
import 'package:muzo/widgets/global_background.dart';
import 'package:muzo/services/storage_service.dart';
import 'package:muzo/widgets/glass_snackbar.dart';
import 'package:muzo/services/navigator_key.dart';
import 'package:app_links/app_links.dart';
import 'package:muzo/widgets/floating_sleep_timer.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:muzo/screens/profile_screen.dart';
import 'package:muzo/utils/page_routes.dart';
import 'package:muzo/providers/search_provider.dart';
import 'package:muzo/widgets/brand_sheet.dart';
import 'package:muzo/widgets/hivefy_drawer.dart';
import 'package:muzo/l10n/app_localizations.dart';
import 'package:muzo/widgets/spotify_spinner.dart';

/// Hauteur cumulée du chrome flottant en bas des onglets : la nav (64 +
/// `max(padding.bottom, 16)`, posée par-dessus le Scaffold) ET le mini-player
/// (~65 px ancré à `84 + padding.bottom`, donc bord supérieur ≈ 149 px). Un
/// onglet qui termine sa liste sur le vieux `bottom: 130` fait disparaître sa
/// dernière rangée sous le mini-player — c'est ce qui masquait le bas de la
/// grille « Parcourir tout » (catégories) et du dernier rayon de l'accueil.
const double kBottomChromeHeight = 172;

class MainLayout extends ConsumerStatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final ShareService _shareService;
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final audioHandler = ref.read(audioHandlerProvider);
    _shareService = ShareService(audioHandler);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareService.init(context);
    });

    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    
    // Check initial link if app was in cold state (minimized)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Failed to get initial uri: $e');
    }

    // Handle link when app is in warm state (foreground or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep Link stream error: $err');
    });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Received Deep Link: $uri');
    // Using the exact logic as ShareService via the audio handler for playback
    _shareService.handleSharedText(context, uri.toString());
  }

  static const MethodChannel _appChannel =
      MethodChannel('com.shashwat.muzo/app');

  /// System back, handled at the shell instead of by Android.
  ///
  /// Left to the framework, back on the Home tab finishes the Activity: the
  /// Dart isolate dies, and reopening the app is a cold start — every shelf
  /// re-fetches, every counter restarts, the queue replays the calls the
  /// worker already refused. That is what felt like "les titres ne viennent
  /// plus vite". So back unwinds the stack the way a music app should: drawer,
  /// then the deepest screen still stacked, then the Home tab.
  ///
  /// That last step is what keeps this override safe. `canPop: false` also
  /// makes `Navigator.maybePop` — the back arrow of every pushed screen (full
  /// player, video, concert clip, `SpotifyBackButton`) — return false once the
  /// pushed page itself has been popped and the shell is on top. Without the
  /// two branches below, those backscreens would stop doing anything. So pop
  /// the nested navigator, then the root navigator's surplus routes (checked
  /// with `canPop`, which does not consult this `PopScope`), and only when both
  /// are already at their first page MINIMIZE the app with `moveTaskToBack`:
  /// the Activity and its engine stay alive, so coming back resumes exactly
  /// where the user left — playback included.
  void _handleBack() {
    final scaffold = mainScaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      scaffold!.closeDrawer();
      return;
    }
    // Deepest thing first, so an artist page opened from the Search tab goes
    // back to that tab instead of being flattened into Home.
    final nested = nestedNavigatorKey.currentState;
    if (nested != null && nested.canPop()) {
      nested.pop();
      return;
    }
    final root = Navigator.of(context);
    if (root.canPop()) {
      root.pop();
      return;
    }
    if (ref.read(navigationIndexProvider) != 0) {
      ref.read(navigationIndexProvider.notifier).state = 0;
      return;
    }
    _appChannel.invokeMethod<void>('moveToBack').catchError((_) {});
  }


  @override
  void dispose() {
    _shareService.dispose();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final hasMaterialLocalizations = Localizations.of<MaterialLocalizations>(context, MaterialLocalizations) != null;

    // If MaterialLocalizations not ready, render everything EXCEPT the
    // BottomNavigationBar to avoid the null-check crash while still showing
    // the main content (no black screen).

    final selectedIndex = ref.watch(navigationIndexProvider);
    final isPlayerExpanded = ref.watch(isPlayerExpandedProvider);

    final audioHandler = ref.read(audioHandlerProvider);

    final isDesktop = MediaQuery.of(context).size.width > 600;

    // Single writer for the folded state: both gestures that change it go
    // through the provider, and listening here keeps the persistence in one
    // place instead of sprinkling writes at each call site.
    ref.listen(isMiniPlayerCollapsedProvider, (prev, next) {
      if (prev == next) return;
      ref.read(storageServiceProvider).setMiniPlayerCollapsed(next);
    });

    // Listen for storage errors
    ref.listen(storageServiceProvider, (previous, next) {
      if (previous?.errorNotifier.value != next.errorNotifier.value &&
          next.errorNotifier.value != null) {
        showGlassSnackBar(context, next.errorNotifier.value!);
        next.errorNotifier.value = null;
      }
    });

    // Close any open bottom sheet and handle search on tab change
    ref.listen(navigationIndexProvider, (previous, next) {
      if (previous != next) {
        // Popping the nested navigator also dismisses any bottom sheet that
        // was opened from the page being left behind.
        if (nestedNavigatorKey.currentState != null &&
            nestedNavigatorKey.currentState!.canPop()) {
          nestedNavigatorKey.currentState!.popUntil((route) => route.isFirst);
        }
        Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
      }
      if (next != 1) {
        try { ref.read(searchControllerProvider).clear(); } catch (_) {}
        ref.read(searchFocusNodeProvider).unfocus();
        ref.read(searchQueryProvider.notifier).state = '';
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final nestedNavigator = Navigator(
      key: nestedNavigatorKey,
      // Concert/clip screens push HERE, not on the root navigator, so the
      // scene observer that hides (and reliably re-shows) the mini player has
      // to be attached to this navigator or the route-derived state never fires.
      observers: [playerSceneObserver],
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => widget.child,
          settings: settings,
        );
      },
    );

    final mainBody = isDesktop
        ? Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: isPlayerExpanded ? 0 : 240,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: isDark ? Theme.of(context).scaffoldBackgroundColor : const Color(0xFFF9F9F9),
                ),
                child: SizedBox(
                  width: 240,
                  height: double.infinity,
                  child: _buildSidebar(context, ref),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: isPlayerExpanded ? 0 : 1,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    nestedNavigator,
                    _buildLoadingOverlay(audioHandler),
                    _buildMiniPlayerPositioned(context, ref, isDesktop),
                    const FloatingSleepTimer(),
                  ],
                ),
              ),
            ],
          )
        : Stack(
            children: [
              nestedNavigator,
              _buildLoadingOverlay(audioHandler),
              _buildMiniPlayerPositioned(context, ref, isDesktop),
              const FloatingSleepTimer(),
            ],
          );

    final systemOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemOverlayStyle,
        child: GlobalBackground(
          child: Stack(
            children: [
              Scaffold(
                key: mainScaffoldKey,
                backgroundColor: Colors.transparent, // Ensure GlobalBackground is visible
                drawer: HivefyDrawer(
                  onClose: () => mainScaffoldKey.currentState?.closeDrawer(),
                ),
                body: mainBody,
              ),
              // Bottom nav bar rendered OUTSIDE the Scaffold so it stays
              // visible above the drawer (Spotify behavior).
              if (!isDesktop && hasMaterialLocalizations)
                _buildBottomNavBar(context, ref, selectedIndex, isPlayerExpanded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay(dynamic audioHandler) {
    return const SizedBox.shrink();
  }

  Widget _buildBottomNavBar(
    BuildContext context,
    WidgetRef ref,
    int selectedIndex,
    bool isPlayerExpanded,
  ) {
    final rawBottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomPadding = rawBottomPadding < 16 ? 16.0 : rawBottomPadding;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final showNavBar = !isPlayerExpanded && !keyboardVisible;
    final width = MediaQuery.of(context).size.width;
    final l10n = AppLocalizations.of(context);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 64 + bottomPadding,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: showNavBar ? 1.0 : 0.0,
        child: IgnorePointer(
          ignoring: !showNavBar,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                width: width,
                color: Colors.black.withValues(alpha: 0.65),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: BottomNavigationBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    type: BottomNavigationBarType.fixed,
                    currentIndex: selectedIndex > 2 ? 0 : selectedIndex,
                    showSelectedLabels: true,
                    showUnselectedLabels: true,
                    selectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedItemColor: const Color(0xffE5E5E5),
                    unselectedItemColor: const Color(0xff777777),
                    onTap: (value) {
                      HapticFeedback.selectionClick();
                      if (value >= 0 && value <= 2) {
                        ref.read(navigationIndexProvider.notifier).state = value;
                        nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                      }
                    },
                    items: [
                      BottomNavigationBarItem(
                        icon: Image.asset(
                          'assets/spotify/icon_home.png',
                          height: 24,
                          width: 24,
                        ),
                        activeIcon: Image.asset(
                          'assets/spotify/icon_home_active.png',
                          height: 24,
                          width: 24,
                        ),
                        label: l10n.home,
                      ),
                      BottomNavigationBarItem(
                        icon: Image.asset(
                          'assets/spotify/icon_search_bottomnav.png',
                          height: 24,
                          width: 24,
                        ),
                        activeIcon: Image.asset(
                          'assets/spotify/icon_search_active.png',
                          height: 24,
                          width: 24,
                          color: const Color(0xffE5E5E5),
                        ),
                        label: l10n.search,
                      ),
                      BottomNavigationBarItem(
                        icon: Image.asset(
                          'assets/spotify/icon_library.png',
                          height: 24,
                          width: 24,
                          color: const Color(0xff777777),
                        ),
                        activeIcon: Image.asset(
                          'assets/spotify/icon_library_active.png',
                          height: 24,
                          width: 24,
                          color: const Color(0xffE5E5E5),
                        ),
                        label: l10n.library,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlayerPositioned(
    BuildContext context,
    WidgetRef ref,
    bool isDesktop,
  ) {
    final isPlayerExpandedVal = ref.watch(isPlayerExpandedProvider);
    final isMiniPlayerCollapsed = ref.watch(isMiniPlayerCollapsedProvider);
    final bottomOffset = isDesktop
        ? 16.0
        : 84.0 + MediaQuery.of(context).padding.bottom;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    // Derived from the live route stack by `PlayerSceneObserver`, not from a
    // boolean a screen has to remember to reset.
    final scenes = ref.watch(overlayScenesProvider);
    final videoSurfaceOpen = scenes.contains(PlayerScene.clips);

    return Positioned(
      left: isDesktop ? 24 : 16,
      right: isDesktop ? 24 : 16,
      bottom: bottomOffset,
      child: ValueListenableBuilder<bool>(
        valueListenable: ref.read(audioHandlerProvider).isClipPlayback,
        builder: (context, clipMode, _) {
          final showMiniPlayer = !isPlayerExpandedVal &&
              !isMiniPlayerCollapsed &&
              !keyboardVisible &&
              !clipMode &&
              !videoSurfaceOpen;
          return AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showMiniPlayer ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !showMiniPlayer,
              child: const HivefyMiniPlayer(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(navigationIndexProvider);
    final storage = ref.watch(storageServiceProvider);
    final username = storage.username ?? 'User';
    final l10n = AppLocalizations.of(context);

    String getInitials(String name) {
      final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) return 'U';
      if (parts.length == 1) {
        final first = parts[0];
        return first.substring(0, first.length >= 2 ? 2 : 1).toUpperCase();
      }
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }

    return SafeArea(
      right: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                InkWell(
                  onTap: () => showBrandSheet(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                          'assets/icon.png',
                        height: 32,
                        width: 32,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Tunefy',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSidebarItem(
                    context,
                    ref,
                    iconRegular: FluentIcons.search_24_regular,
                    iconFilled: FluentIcons.search_24_filled,
                    label: l10n.search,
                    isSelected: selectedIndex == 1,
                    onTap: () {
                      ref.read(navigationIndexProvider.notifier).state = 1;
                      nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                    },
                  ),
                  _buildSidebarItem(
                    context,
                    ref,
                    iconRegular: FluentIcons.home_24_regular,
                    iconFilled: FluentIcons.home_24_filled,
                    label: l10n.home,
                    isSelected: selectedIndex == 0,
                    onTap: () {
                      ref.read(navigationIndexProvider.notifier).state = 0;
                      nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                    },
                  ),
                  _buildSidebarItem(
                    context,
                    ref,
                    iconRegular: FluentIcons.library_24_regular,
                    iconFilled: FluentIcons.library_24_filled,
                    label: l10n.library,
                    isSelected: selectedIndex == 2,
                    onTap: () {
                      ref.read(navigationIndexProvider.notifier).state = 2;
                      nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                    },
                  ),
                  _buildSidebarItem(
                    context,
                    ref,
                    iconRegular: FluentIcons.settings_24_regular,
                    iconFilled: FluentIcons.settings_24_filled,
                    label: l10n.settings,
                    isSelected: selectedIndex == 3,
                    onTap: () {
                      ref.read(navigationIndexProvider.notifier).state = 3;
                      nestedNavigatorKey.currentState?.popUntil((route) => route.isFirst);
                    },
                  ),
                ],
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: ref.read(storageServiceProvider).isLoadingNotifier,
            builder: (context, isLoading, _) {
              if (isLoading) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: SpotifySpinner(
                          strokeWidth: 1.5,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Syncing...",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Text(
                    "Cloud Library online",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.withValues(alpha: 0.6),
                    ),
                  ),
                );
              }
            },
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              nestedNavigatorKey.currentState?.push(
                SlidePageRoute(page: const ProfileScreen()),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                        width: 1.0,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF8E8E93),
                      child: ClipOval(
                        child: Builder(
                        builder: (context) {
                          final localPhoto = storage.profilePhotoPath;
                          if (localPhoto != null && File(localPhoto).existsSync()) {
                            return Image.file(
                              File(localPhoto),
                              height: 36,
                              width: 36,
                              fit: BoxFit.cover,
                            );
                          }
                          final avatarUrl = storage.avatarUrl;
                          final cachedSvg = storage.getUserAvatar();
                          final isSvg = avatarUrl == null ||
                              avatarUrl.contains('.svg') ||
                              avatarUrl.contains('dicebear');
                          if (isSvg && cachedSvg != null) {
                            return SvgPicture.string(
                              cachedSvg,
                              height: 36,
                              width: 36,
                              fit: BoxFit.cover,
                            );
                          }
                          if (avatarUrl != null && !isSvg) {
                            return CachedNetworkImage(
                              imageUrl: avatarUrl,
                              height: 36,
                              width: 36,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Text(
                                getInitials(username),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }
                          return Text(
                            getInitials(username),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      username,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context,
    WidgetRef ref, {
    required IconData iconRegular,
    required IconData iconFilled,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? iconFilled : iconRegular,
                color: isSelected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                size: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


}
