import 'package:flutter/material.dart';

import 'package:nyumba_property_management/core/localization/nyumba_localizations.dart';

import 'motion.dart';

/// Runs an async callback at most once at a time.
///
/// A tap that lands while the previous run is still in flight is dropped, not
/// queued: the second tap of a double-tap means "I am not sure the first one
/// registered", never "do it twice". Every mutation the app can fire from a
/// button goes through one of these, either directly or through
/// [AsyncActionButton], so a slow network cannot turn one payment into two.
class AsyncActionGuard extends ChangeNotifier {
  bool _running = false;

  bool get isRunning => _running;

  /// Runs [action] unless a previous run is still pending.
  ///
  /// Returns the action's result, or null when the call was dropped as a
  /// duplicate. Errors propagate to the caller — this only owns the flag.
  Future<T?> run<T>(Future<T> Function() action) async {
    if (_running) return null;
    _running = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

/// Which Material button [AsyncActionButton] wears.
enum AsyncActionStyle { filled, tonal, outlined, text }

/// A Material button that owns the busy state of the work it triggers.
///
/// It does three things a bare button does not:
///
/// * presses respond — the button eases down under the finger and back,
///   so a tap is acknowledged before the work behind it finishes;
/// * the label swaps for a spinner while [onPressed] runs, and the button
///   disables itself for the duration;
/// * re-entrant taps are dropped even when they arrive in the same frame as
///   the first, before the disabled state has painted.
///
/// Pass [busy] when the surrounding screen already tracks the state (a form
/// that keeps its spinner through a redirect, say); the widget ors it with
/// its own.
class AsyncActionButton extends StatefulWidget {
  const AsyncActionButton({
    required this.onPressed,
    required this.child,
    super.key,
    this.style = AsyncActionStyle.filled,
    this.icon,
    this.busy = false,
    this.enabled = true,
    this.showBusyIndicator = true,
    this.buttonStyle,
    this.autofocus = false,
    this.focusNode,
  });

  /// Convenience for the app's most common shape: a primary filled action.
  const AsyncActionButton.filled({
    required this.onPressed,
    required this.child,
    super.key,
    this.icon,
    this.busy = false,
    this.enabled = true,
    this.showBusyIndicator = true,
    this.buttonStyle,
    this.autofocus = false,
    this.focusNode,
  }) : style = AsyncActionStyle.filled;

  const AsyncActionButton.tonal({
    required this.onPressed,
    required this.child,
    super.key,
    this.icon,
    this.busy = false,
    this.enabled = true,
    this.showBusyIndicator = true,
    this.buttonStyle,
    this.autofocus = false,
    this.focusNode,
  }) : style = AsyncActionStyle.tonal;

  const AsyncActionButton.outlined({
    required this.onPressed,
    required this.child,
    super.key,
    this.icon,
    this.busy = false,
    this.enabled = true,
    this.showBusyIndicator = true,
    this.buttonStyle,
    this.autofocus = false,
    this.focusNode,
  }) : style = AsyncActionStyle.outlined;

  const AsyncActionButton.text({
    required this.onPressed,
    required this.child,
    super.key,
    this.icon,
    this.busy = false,
    this.enabled = true,
    this.showBusyIndicator = true,
    this.buttonStyle,
    this.autofocus = false,
    this.focusNode,
  }) : style = AsyncActionStyle.text;

  /// The work behind the button. A null callback disables it outright.
  final Future<void> Function()? onPressed;
  final Widget child;
  final AsyncActionStyle style;

  /// Leading icon. While busy it is replaced by the spinner, which keeps the
  /// button's width from jumping mid-action.
  final Widget? icon;

  /// Busy state owned by the caller, or-ed with the widget's own.
  final bool busy;
  final bool enabled;

  /// Whether the widget's own tracking may raise the spinner.
  ///
  /// Buttons whose action is "open a dialog" set this false: the work is
  /// finished the moment the sheet is on screen, and a spinner ticking away
  /// behind the scrim would be reporting on nothing — it also never stops,
  /// because a modal keeps the future open. They still get the duplicate
  /// guard, which is the point: two taps must not open two dialogs. A [busy]
  /// flag passed by the caller is always honoured, so a screen that knows
  /// when the real work starts can still raise the spinner then.
  final bool showBusyIndicator;
  final ButtonStyle? buttonStyle;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<AsyncActionButton> createState() => _AsyncActionButtonState();
}

class _AsyncActionButtonState extends State<AsyncActionButton> {
  final _guard = AsyncActionGuard();
  final _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _guard.addListener(_onGuardChanged);
    _states.addListener(_onStatesChanged);
  }

  @override
  void dispose() {
    _guard
      ..removeListener(_onGuardChanged)
      ..dispose();
    _states
      ..removeListener(_onStatesChanged)
      ..dispose();
    super.dispose();
  }

  void _onGuardChanged() {
    if (mounted) setState(() {});
  }

  void _onStatesChanged() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    if (mounted) setState(() => _pressed = pressed);
  }

  Future<void> _handlePressed() async {
    final action = widget.onPressed;
    if (action == null) return;
    await _guard.run(action);
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy || _guard.isRunning;
    final enabled = widget.enabled && widget.onPressed != null && !busy;
    final onPressed = enabled ? _handlePressed : null;
    final showSpinner =
        widget.busy || (_guard.isRunning && widget.showBusyIndicator);
    final label = _AsyncActionLabel(
      busy: showSpinner,
      icon: widget.icon,
      child: widget.child,
    );

    final button = switch (widget.style) {
      AsyncActionStyle.filled => FilledButton(
        onPressed: onPressed,
        style: widget.buttonStyle,
        statesController: _states,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        child: label,
      ),
      AsyncActionStyle.tonal => FilledButton.tonal(
        onPressed: onPressed,
        style: widget.buttonStyle,
        statesController: _states,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        child: label,
      ),
      AsyncActionStyle.outlined => OutlinedButton(
        onPressed: onPressed,
        style: widget.buttonStyle,
        statesController: _states,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        child: label,
      ),
      AsyncActionStyle.text => TextButton(
        onPressed: onPressed,
        style: widget.buttonStyle,
        statesController: _states,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        child: label,
      ),
    };

    return Semantics(
      // Screen readers get the same "working on it" cue sighted users get
      // from the spinner.
      liveRegion: showSpinner,
      hint: showSpinner ? context.tr('Working…') : null,
      child: PressResponse(pressed: _pressed, child: button),
    );
  }
}

/// The icon-only counterpart of [AsyncActionButton].
class AsyncActionIconButton extends StatefulWidget {
  const AsyncActionIconButton({
    required this.onPressed,
    required this.icon,
    super.key,
    this.tooltip,
    this.busy = false,
    this.enabled = true,
    this.buttonStyle,
    this.filled = false,
  });

  final Future<void> Function()? onPressed;
  final Widget icon;
  final String? tooltip;
  final bool busy;
  final bool enabled;
  final ButtonStyle? buttonStyle;

  /// Renders as `IconButton.filledTonal` rather than a plain icon button.
  final bool filled;

  @override
  State<AsyncActionIconButton> createState() => _AsyncActionIconButtonState();
}

class _AsyncActionIconButtonState extends State<AsyncActionIconButton> {
  final _guard = AsyncActionGuard();
  final _states = WidgetStatesController();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _guard.addListener(_onGuardChanged);
    _states.addListener(_onStatesChanged);
  }

  @override
  void dispose() {
    _guard
      ..removeListener(_onGuardChanged)
      ..dispose();
    _states
      ..removeListener(_onStatesChanged)
      ..dispose();
    super.dispose();
  }

  void _onGuardChanged() {
    if (mounted) setState(() {});
  }

  void _onStatesChanged() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    if (mounted) setState(() => _pressed = pressed);
  }

  Future<void> _handlePressed() async {
    final action = widget.onPressed;
    if (action == null) return;
    await _guard.run(action);
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.busy || _guard.isRunning;
    final enabled = widget.enabled && widget.onPressed != null && !busy;
    // Sized to the icon it replaces so the surrounding row never reflows.
    final icon = busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.icon;
    final button = widget.filled
        ? IconButton.filledTonal(
            onPressed: enabled ? _handlePressed : null,
            tooltip: widget.tooltip,
            style: widget.buttonStyle,
            statesController: _states,
            icon: icon,
          )
        : IconButton(
            onPressed: enabled ? _handlePressed : null,
            tooltip: widget.tooltip,
            style: widget.buttonStyle,
            statesController: _states,
            icon: icon,
          );
    return PressResponse(pressed: _pressed, child: button);
  }
}

/// Eases its child down while [pressed], and back when released.
///
/// Collapses to a plain child when the platform asks for reduced motion.
class PressResponse extends StatelessWidget {
  const PressResponse({
    required this.pressed,
    required this.child,
    super.key,
    this.scale = .97,
  });

  final bool pressed;
  final Widget child;

  /// How far the child sinks. Deliberately shallow — the press should read as
  /// a nudge, not a bounce.
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (NyumbaMotion.reducedMotion(context)) return child;
    return AnimatedScale(
      scale: pressed ? scale : 1,
      duration: NyumbaMotion.fast,
      curve: NyumbaMotion.easeOut,
      child: child,
    );
  }
}

/// Label that trades its icon for a spinner while the action runs.
class _AsyncActionLabel extends StatelessWidget {
  const _AsyncActionLabel({
    required this.busy,
    required this.icon,
    required this.child,
  });

  final bool busy;
  final Widget? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final leading = busy
        ? SizedBox.square(
            key: const ValueKey('busy'),
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              // Matches whatever foreground the enclosing button resolved to,
              // so this works on filled, tonal and outlined alike.
              color: DefaultTextStyle.of(context).style.color,
            ),
          )
        : icon == null
        ? const SizedBox.shrink(key: ValueKey('idle-none'))
        : KeyedSubtree(key: const ValueKey('idle-icon'), child: icon!);

    final swapped = AnimatedSwitcher(
      duration: NyumbaMotion.fast,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: leading,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AnimatedSize keeps the gap from popping in when a button that had no
        // icon grows one for the duration of the work.
        AnimatedSize(
          duration: NyumbaMotion.fast,
          curve: NyumbaMotion.easeOut,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: busy || icon != null ? 8 : 0,
            ),
            child: swapped,
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}
