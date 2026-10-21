import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:finamp/components/AddToPlaylistScreen/add_to_playlist_button.dart';
import 'package:finamp/components/audio_fade_progress_visualizer_container.dart';
import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/components/one_line_marquee_helper.dart';
import 'package:finamp/components/print_duration.dart';
import 'package:finamp/extensions/color_extensions.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/services/current_track_metadata_provider.dart';
import 'package:finamp/services/feedback_helper.dart';
import 'package:finamp/services/queue_service.dart';
import 'package:finamp/services/theme_provider.dart';
import 'package:finamp/services/widget_bindings_observer_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';

import '../models/jellyfin_models.dart' as jellyfin_models;
import '../screens/player_screen.dart';
import '../services/current_album_image_provider.dart';
import '../services/finamp_settings_helper.dart';
import '../services/media_state_stream.dart';
import '../services/music_player_background_task.dart';
import '../services/process_artist.dart';
import 'PlayerScreen/player_split_screen_scaffold.dart';
import 'album_image.dart';

class NowPlayingBar extends ConsumerWidget {
  const NowPlayingBar({super.key});

  static const horizontalPadding = 8.0;
  static const barHeight = 64.0;
  static const albumImageSize = 48.0;
  static const showPlayButtonAtEnd = true;

  Color getProgressForegroundColor(WidgetRef ref) {
    return ColorScheme.of(ref.context).primary;
  }

  Color getProgressBackgroundColor(WidgetRef ref) {
    return Color.alphaBlend(
      getProgressForegroundColor(ref).withValues(alpha: 0.75),
      // this is an approximation, the actual background has the blurred cover image
      ref.watch(brightnessProvider) == Brightness.dark ? Colors.black : Colors.white,
    );
  }

  Widget buildLoadingQueueBar(WidgetRef ref, void Function()? retryCallback) {
    final progressBackgroundColor = getProgressBackgroundColor(ref).withValues(alpha: 0.5);
    var context = ref.context;

    return SimpleGestureDetector(
      onVerticalSwipe: (direction) {
        if (direction == SwipeDirection.up && retryCallback != null) {
          retryCallback();
        }
      },
      onTap: retryCallback,
      child: _NowPlayingBarSurface(
        color: getProgressBackgroundColor(ref),
        child: ClipRect(
          child: Material(
            borderRadius: BorderRadius.zero,
            clipBehavior: Clip.antiAlias,
            color: Theme.brightnessOf(context) == Brightness.dark
                ? IconTheme.of(context).color!.withValues(alpha: 0.1)
                : Theme.of(context).cardColor,
            child: Container(
              width: MediaQuery.widthOf(context),
              height: barHeight,
              padding: EdgeInsets.zero,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(color: progressBackgroundColor, shape: const RoundedRectangleBorder()),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Container(
                        width: albumImageSize,
                        height: albumImageSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: const Color.fromRGBO(0, 0, 0, 0.3),
                        ),
                        child: (retryCallback != null)
                            ? const Icon(Icons.refresh, size: 24)
                            : const Center(
                                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator.adaptive()),
                              ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: barHeight,
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          (retryCallback != null)
                              ? AppLocalizations.of(context)!.queueRetryMessage
                              : AppLocalizations.of(context)!.queueLoadingMessage,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> openPlayerScreen() async {
    minimizeSplitScreen.value = false;
    await GlobalSnackbar.navigatorState?.push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (MediaQuery.disableAnimationsOf(context)) {
            return child;
          }
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOutQuad));
          var offsetAnimation = animation.drive(tween);

          if (animation.status == AnimationStatus.reverse) {
            // dismiss animation
            return FadeTransition(opacity: animation, child: child);
          } else {
            return SlideTransition(position: offsetAnimation, child: child);
          }
        },
        settings: const RouteSettings(name: PlayerScreen.routeName),
      ),
    );
  }

  Widget buildNowPlayingBar(WidgetRef ref, FinampQueueItem currentTrack) {
    final audioHandler = GetIt.instance<MusicPlayerBackgroundTask>();
    final queueService = GetIt.instance<QueueService>();

    final currentTrackBaseItem = currentTrack.item.extras?["itemJson"] != null
        ? jellyfin_models.BaseItemDto.fromJson(currentTrack.item.extras!["itemJson"] as Map<String, dynamic>)
        : null;
    var context = ref.context;

    final elapsedPartBackgroundColor = getProgressForegroundColor(ref);
    final remainingPartBackgroundColor = getProgressBackgroundColor(ref);
    final averageBackgroundColor = Color.alphaBlend(
      elapsedPartBackgroundColor.withValues(alpha: 0.5),
      remainingPartBackgroundColor,
    );
    Color primaryTextColor = AtContrast.getContrastiveTintedTextColor(onBackground: averageBackgroundColor);

    final showPauseButton = ref.watch(
      mediaStateProvider.select((x) => x.playbackState.playing && x.fadeDirection != FadeDirection.fadeOut),
    );

    return _NowPlayingBarSurface(
      color: remainingPartBackgroundColor,
      footer: _NowPlayingTime(
        duration: currentTrack.item.duration,
        initialPosition: audioHandler.playbackState.value.position,
        color: primaryTextColor.withValues(alpha: 0.75),
      ),
      progress: ref.watch(finampSettingsProvider.showProgressOnNowPlayingBar)
          ? StreamBuilder<Duration>(
              stream: AudioService.position,
              initialData: audioHandler.playbackState.value.position,
              builder: (context, snapshot) {
                final duration = currentTrack.item.duration?.inMilliseconds ?? 0;
                final position = snapshot.data?.inMilliseconds ?? 0;
                final progress = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
                return FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: progress,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: elapsedPartBackgroundColor,
                      borderRadius: const BorderRadiusDirectional.only(topEnd: Radius.circular(12)),
                    ),
                  ),
                );
              },
            )
          : null,
      child: Semantics.fromProperties(
        properties: SemanticsProperties(label: AppLocalizations.of(context)!.nowPlayingBarTooltip, button: true),
        child: SimpleGestureDetector(
          onTap: () async => await openPlayerScreen(),
          child: Dismissible(
            key: const Key("NowPlayingBarDismiss"),
            direction: ref.watch(finampSettingsProvider.disableGesture)
                ? DismissDirection.none
                : DismissDirection.vertical,
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.down) {
                FeedbackHelper.feedback(FeedbackType.success);
                await queueService.stopAndClearQueue();
              } else {
                await openPlayerScreen();
              }
              return false;
            },
            dismissThresholds: const {DismissDirection.up: 0.15, DismissDirection.down: 0.7},
            child: ClipRect(
              clipBehavior: Clip.antiAlias,
              //TODO use a PageView instead of a Dismissible, and only wrap dynamic items (not the buttons)
              child: Dismissible(
                key: const Key("NowPlayingBar"),
                direction: ref.watch(finampSettingsProvider.disableGesture)
                    ? DismissDirection.none
                    : DismissDirection.horizontal,
                confirmDismiss: (direction) async {
                  if (direction == DismissDirection.endToStart) {
                    FeedbackHelper.feedback(FeedbackType.light);
                    await audioHandler.skipToNext();
                  } else {
                    FeedbackHelper.feedback(FeedbackType.light);
                    await audioHandler.skipToPrevious(forceSkip: true);
                  }
                  return false;
                },
                child: Material(
                  borderRadius: BorderRadius.zero,
                  clipBehavior: Clip.antiAlias,
                  color: Colors.transparent,
                  // If we have a media item and the player hasn't finished, show
                  // the now playing bar.
                  child: //TODO move into separate component and share with queue list
                  SizedBox(
                    width: MediaQuery.widthOf(context),
                    height: barHeight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                          child: SizedBox.square(
                            dimension: albumImageSize,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AlbumImage(
                                  imageListenable: currentAlbumImageProvider,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                if (!showPlayButtonAtEnd)
                                  AudioFadeProgressVisualizerContainer(
                                    key: const Key("AlbumArtAudioFadeProgressVisualizer"),
                                    width: albumImageSize,
                                    height: albumImageSize,
                                    borderRadius: BorderRadius.circular(8),
                                    child: IconButton(
                                      tooltip: AppLocalizations.of(context)!.togglePlaybackButtonTooltip,
                                      onPressed: () {
                                        FeedbackHelper.feedback(FeedbackType.light);
                                        unawaited(audioHandler.togglePlayback());
                                      },
                                      color: Colors.white,
                                      icon: Icon(
                                        showPauseButton ? TablerIcons.player_pause : TablerIcons.player_play,
                                        shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 10.0)],
                                        size: 32,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Container(
                                  height: barHeight,
                                  padding: const EdgeInsets.only(left: 8, right: 4),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      OneLineMarqueeHelper(
                                        key: ValueKey(currentTrack.item.id),
                                        text: currentTrack.item.title,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          height: 26 / 20,
                                          color: primaryTextColor,
                                          fontWeight: Theme.brightnessOf(context) == Brightness.light
                                              ? FontWeight.w500
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        processArtist(currentTrack.item.artist, context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: primaryTextColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 5.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    AddToPlaylistButton(
                                      item: currentTrackBaseItem,
                                      queueItem: currentTrack,
                                      color: primaryTextColor,
                                      size: 28,
                                      visualDensity: const VisualDensity(horizontal: -4),
                                    ),

                                    if (showPlayButtonAtEnd)
                                      AudioFadeProgressVisualizerContainer(
                                        key: const Key("NowPlayingPlaybackControl"),
                                        color: primaryTextColor.withValues(alpha: 0.5),
                                        width: 48,
                                        height: 48,
                                        borderRadius: BorderRadius.circular(12.0),
                                        child: IconButton(
                                          tooltip: AppLocalizations.of(context)!.togglePlaybackButtonTooltip,
                                          onPressed: () {
                                            FeedbackHelper.feedback(FeedbackType.light);
                                            unawaited(audioHandler.togglePlayback());
                                          },
                                          color: primaryTextColor,
                                          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                                          icon: Icon(
                                            showPauseButton ? TablerIcons.player_pause : TablerIcons.player_play,
                                            size: 28,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueService = GetIt.instance<QueueService>();

    return Hero(
      tag: "nowplaying",
      createRectTween: (from, to) => RectTween(begin: from, end: from),
      child: PlayerScreenTheme(
        // use consumer to obtain ref of correct (player screen theme) ProviderContainer
        child: Consumer(
          builder: (context, ref, child) {
            ref.listen(currentTrackMetadataProvider, (metadataOrNull, metadata) {}); // keep provider alive
            return StreamBuilder<FinampQueueInfo?>(
              stream: queueService.getQueueStream(),
              initialData: queueService.getQueue(),
              builder: (context, snapshot) {
                if (snapshot.hasData &&
                    snapshot.data!.saveState == SavedQueueState.loading &&
                    !usingPlayerSplitScreen) {
                  return buildLoadingQueueBar(ref, null);
                } else if (snapshot.hasData &&
                    snapshot.data!.saveState == SavedQueueState.failed &&
                    !usingPlayerSplitScreen) {
                  return buildLoadingQueueBar(ref, queueService.retryQueueLoad);
                } else if (snapshot.hasData && snapshot.data!.currentTrack != null && !usingPlayerSplitScreen) {
                  return buildNowPlayingBar(ref, snapshot.data!.currentTrack!);
                } else {
                  // Reserve the system inset even when the player is hidden.
                  return const SafeArea(top: false, child: SizedBox.shrink());
                }
              },
            );
          },
        ),
      ),
    );
  }
}

class _NowPlayingBarSurface extends StatelessWidget {
  const _NowPlayingBarSurface({required this.color, required this.child, this.progress, this.footer});

  final Color color;
  final Widget child;
  final Widget? progress;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.paddingOf(context);
    final footerHeight = footer == null
        ? 0.0
        : MediaQuery.textScalerOf(context).scale(_NowPlayingTime.fontSize) * 1.2 + 20;
    // Paint the background and progress through the system insets, with only the controls inset.
    return ColoredBox(
      color: color,
      child: Stack(
        children: [
          if (progress != null) Positioned.fill(child: IgnorePointer(child: progress!)),
          SafeArea(
            top: false,
            minimum: EdgeInsets.only(bottom: footerHeight),
            child: child,
          ),
          if (footer != null)
            Positioned(
              left: insets.left + 16,
              right: insets.right + 16,
              bottom: 14,
              child: IgnorePointer(
                child: Align(alignment: Alignment.center, child: footer!),
              ),
            ),
        ],
      ),
    );
  }
}

class _NowPlayingTime extends StatelessWidget {
  const _NowPlayingTime({required this.duration, required this.initialPosition, required this.color});

  static const fontSize = 12.0;

  final Duration? duration;
  final Duration initialPosition;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: AudioService.position,
      initialData: initialPosition,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final showRemaining = (Platform.isIOS || Platform.isMacOS) && duration != null;
        final remaining = (duration ?? Duration.zero) - position;
        final time = showRemaining
            ? printDuration(remaining.isNegative ? Duration.zero : remaining, leadingZeroes: false, isRemaining: true)
            : '${printDuration(position, leadingZeroes: false)}${duration == null ? "" : " / ${printDuration(duration, leadingZeroes: false)}"}';
        final positionHours = position.inHours;
        final positionMinutes = position.inMinutes % 60;
        final positionSeconds = position.inSeconds % 60;
        final durationHours = duration?.inHours ?? 0;
        final durationMinutes = (duration?.inMinutes ?? 0) % 60;
        final durationSeconds = (duration?.inSeconds ?? 0) % 60;

        return Semantics(
          label:
              '${positionHours > 0 ? "$positionHours hours " : ""}${positionMinutes > 0 ? "$positionMinutes minutes " : ""}$positionSeconds seconds${duration == null ? "" : " of ${durationHours > 0 ? "$durationHours hours " : ""}${durationMinutes > 0 ? "$durationMinutes minutes " : ""}$durationSeconds seconds"}',
          excludeSemantics: true,
          child: Text(
            time,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}
