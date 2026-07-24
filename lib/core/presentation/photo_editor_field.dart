import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text, Tooltip;

import 'package:nyumba_property_management/core/localization/localized_material.dart';
import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';

import 'async_action_button.dart';
import 'image_picking.dart';

/// A photo set part-way through an edit: images already saved on the record,
/// plus ones just chosen from disk.
///
/// The two are kept apart until save because they are different things. A
/// saved photo is a data URI already on the aggregate; a new one is still raw
/// bytes in memory. Holding them separately is what lets an edit form drop one
/// existing photo without touching or re-encoding the ones it keeps.
final class EditablePhotoSet {
  EditablePhotoSet({
    List<String> existing = const <String>[],
    List<PickedImage> picked = const <PickedImage>[],
  }) : existing = List.of(existing),
       picked = List.of(picked);

  /// Data URIs already stored on the record, in display order.
  final List<String> existing;

  /// Newly chosen images, not yet part of the record.
  final List<PickedImage> picked;

  int get length => existing.length + picked.length;
  bool get isEmpty => length == 0;
  bool get isNotEmpty => !isEmpty;

  /// The value to persist. Kept originals stay ahead of new arrivals, so the
  /// first photo — the one used as the primary image — only changes when it
  /// was explicitly removed.
  List<String> toImageUrls() => <String>[
    ...existing,
    for (final image in picked) image.dataUri,
  ];
}

/// Add-and-remove photo editing over an [EditablePhotoSet].
///
/// Shared by the property and listing editors so both offer the same
/// behaviour on photos that are already saved. Before this existed, the create
/// forms could attach photos and the edit forms could not touch them at all.
class PhotoEditorField extends StatelessWidget {
  const PhotoEditorField({
    required this.label,
    required this.photos,
    required this.limit,
    required this.pick,
    required this.onChanged,
    super.key,
    this.helperText,
  });

  final String label;

  /// Mutated in place; [onChanged] fires after so the host can rebuild.
  final EditablePhotoSet photos;

  final int limit;

  /// The subject-specific chooser enforces the configured photo cap.
  final Future<ImagePickOutcome> Function({required int remainingSlots}) pick;

  /// Called after any mutation, carrying the problems from the last pick so
  /// the host can surface rejected files. Empty on a removal.
  final void Function(List<String> problems) onChanged;

  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final full = photos.length >= limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.localized(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        AsyncActionButton.outlined(
          showBusyIndicator: false,
          onPressed: full
              ? null
              : () async {
                  final result = await pick(
                    remainingSlots: limit - photos.length,
                  );
                  // Backing out of the chooser changes nothing, and must not
                  // clear problems the landlord has not read yet.
                  if (result.cancelled) return;
                  photos.picked.addAll(result.images);
                  onChanged(result.problems);
                },
          icon: const Icon(Icons.add_photo_alternate_outlined),
          child: Text.localized(
            photos.isEmpty
                ? 'Choose photos'
                : 'Add more (${photos.length}/$limit)',
          ),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (index, uri) in photos.existing.indexed)
                _PhotoChip(
                  // A saved photo has no filename to show, so it is numbered.
                  label: context.tr('Photo ${index + 1}'),
                  bytes: decodePhotoDataUri(uri),
                  onDeleted: () {
                    photos.existing.remove(uri);
                    onChanged(const <String>[]);
                  },
                ),
              for (final image in photos.picked)
                _PhotoChip(
                  label: image.name,
                  bytes: image.bytes,
                  onDeleted: () {
                    photos.picked.remove(image);
                    onChanged(const <String>[]);
                  },
                ),
            ],
          ),
        ],
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text.localized(
            helperText!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _PhotoChip extends StatelessWidget {
  const _PhotoChip({
    required this.label,
    required this.bytes,
    required this.onDeleted,
  });

  final String label;
  final Uint8List? bytes;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: bytes == null
          // A stored photo that will not decode still has to be removable,
          // so it is shown as a placeholder rather than dropped silently.
          ? const CircleAvatar(
              child: Icon(Icons.broken_image_outlined, size: 16),
            )
          : CircleAvatar(backgroundImage: MemoryImage(bytes!)),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
      // Named rather than left to the theme default, which differs between
      // Material versions and left the control hard to identify.
      deleteIcon: const Icon(Icons.close_rounded, size: 18),
      deleteButtonTooltipMessage: context.tr('Remove photo'),
      onDeleted: onDeleted,
    );
  }
}
