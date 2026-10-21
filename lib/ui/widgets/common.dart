import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

String formatDuration(Duration d) {
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
  }
  return '${d.inMinutes}:$s';
}

/// Whether the layout has room for desktop chrome (sidebar, player bar).
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// A short confirmation along the bottom ("Playing next"), replacing any
/// that is still showing.
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Horizontal padding for page content.
double pagePadding(BuildContext context) => isWide(context) ? 28 : 16;

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 32, pad - 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// A titled, horizontally scrolling row. On desktop it can be scrolled with
/// the arrow buttons or by dragging with the mouse.
class Carousel extends StatefulWidget {
  const Carousel({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.action,
    this.spacing = 18,
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? action;
  final double spacing;

  @override
  State<Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<Carousel> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int direction) {
    final p = _controller.position;
    _controller.animateTo(
      (p.pixels + direction * p.viewportDimension * 0.85).clamp(
        0,
        p.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final wide = isWide(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          widget.title,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ?widget.action,
              if (wide) ...[
                _ArrowButton(Icons.chevron_left_rounded, () => _page(-1)),
                _ArrowButton(Icons.chevron_right_rounded, () => _page(1)),
              ],
            ],
          ),
        ),
        SizedBox(
          height: widget.height,
          child: ScrollConfiguration(
            behavior: const _DragScrollBehavior(),
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad),
              itemCount: widget.itemCount,
              separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton(this.icon, this.onPressed);

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton.filledTonal(
        style: IconButton.styleFrom(
          backgroundColor: EncoreColors.surfaceHigh,
          foregroundColor: EncoreColors.text,
          minimumSize: const Size(32, 32),
          fixedSize: const Size(32, 32),
          padding: EdgeInsets.zero,
        ),
        iconSize: 22,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

/// Lets mice drag horizontal lists, which desktop Flutter disables by
/// default, and hides the scrollbar on them.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, details) => child;
}

/// The large title at the top of a page.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 24, pad - 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A message with an icon, for empty lists and errors.
class Message extends StatelessWidget {
  const Message({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: EncoreColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: EncoreColors.textSecondary),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Message(
      icon: Icons.wifi_off_rounded,
      text: message,
      action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}

/// A large white circular play button, the primary action on a page.
class PlayCircleButton extends StatelessWidget {
  const PlayCircleButton({
    super.key,
    required this.onPressed,
    this.size = 56,
    this.icon = Icons.play_arrow_rounded,
  });

  final VoidCallback? onPressed;
  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: EncoreColors.text,
        foregroundColor: Colors.black,
        disabledBackgroundColor: EncoreColors.surfaceHighest,
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
      ),
      iconSize: size * 0.55,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}
