import 'package:flutter/material.dart';

import '../../app/theme/nyumba_colors.dart';
import '../localization/app_localizations_adapter.dart';

enum MediaPlaceholderState { loading, unavailable, none }

/// A neutral media state that never implies the aggregate has another photo.
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder.loading({super.key, this.progress})
    : state = MediaPlaceholderState.loading;

  const MediaPlaceholder.unavailable({super.key})
    : state = MediaPlaceholderState.unavailable,
      progress = null;

  /// The record carries no photo at all — nothing was asked for, so nothing
  /// failed.
  ///
  /// Distinct from [MediaPlaceholder.unavailable] because the two are different
  /// facts and only one of them is a fault. A "broken image" glyph on a listing
  /// that simply has no photos reads as an app defect to a renter, and hides the
  /// real broken-fetch case among the empty ones when diagnosing.
  const MediaPlaceholder.none({super.key})
    : state = MediaPlaceholderState.none,
      progress = null;

  final MediaPlaceholderState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.nyumba;
    final loading = state == MediaPlaceholderState.loading;
    final copy = appLocalizationsOf(context);
    final label = switch (state) {
      MediaPlaceholderState.loading => copy.imageLoading,
      MediaPlaceholderState.unavailable => copy.imageUnavailable,
      MediaPlaceholderState.none => copy.imageNone,
    };

    return Semantics(
      container: true,
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: ColoredBox(
          color: palette.neutralTint,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Icon(
                  switch (state) {
                    MediaPlaceholderState.loading => Icons.image_outlined,
                    MediaPlaceholderState.unavailable =>
                      Icons.image_not_supported_outlined,
                    MediaPlaceholderState.none => Icons.home_work_outlined,
                  },
                  color: palette.mutedInk,
                  size: 36,
                ),
              ),
              if (loading)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: progress,
                    color: palette.sageGreen,
                    backgroundColor: palette.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
