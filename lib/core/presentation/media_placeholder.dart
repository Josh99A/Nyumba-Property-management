import 'package:flutter/material.dart';

import '../../app/theme/nyumba_colors.dart';
import '../localization/app_localizations_adapter.dart';

enum MediaPlaceholderState { loading, unavailable }

/// A neutral media state that never implies the aggregate has another photo.
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder.loading({super.key, this.progress})
    : state = MediaPlaceholderState.loading;

  const MediaPlaceholder.unavailable({super.key})
    : state = MediaPlaceholderState.unavailable,
      progress = null;

  final MediaPlaceholderState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.nyumba;
    final loading = state == MediaPlaceholderState.loading;
    final label = loading
        ? appLocalizationsOf(context).imageLoading
        : appLocalizationsOf(context).imageUnavailable;

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
                  loading
                      ? Icons.image_outlined
                      : Icons.image_not_supported_outlined,
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
