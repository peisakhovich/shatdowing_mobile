import 'package:flutter/material.dart';

class AdaptiveTextWindow extends StatelessWidget {
  final String title;
  final String text;
  final bool visible;
  final double baseFontSize;
  final double minFontSize;

  const AdaptiveTextWindow({
    super.key,
    required this.title,
    required this.text,
    required this.visible,
    required this.baseFontSize,
    this.minFontSize = 8,
  });

  double _calculateFontSize({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required TextHeightBehavior textHeightBehavior,
    required Locale? locale,
  }) {
    if (text.trim().isEmpty || maxWidth <= 0 || maxHeight <= 0) {
      return baseFontSize;
    }

    bool fits(double fontSize) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontSize: fontSize),
        ),
        textDirection: textDirection,
        textScaler: textScaler,
        textAlign: TextAlign.center,
        textHeightBehavior: textHeightBehavior,
        locale: locale,
      );

      painter.layout(maxWidth: maxWidth);

      final heightFits = painter.height <= maxHeight + 0.5;

      final lines = painter.computeLineMetrics();
      final widthFits = lines.every((line) => line.width <= maxWidth + 0.5);

      painter.dispose();

      return heightFits && widthFits;
    }

    if (fits(baseFontSize)) {
      return baseFontSize;
    }

    if (!fits(minFontSize)) {
      return minFontSize;
    }

    double low = minFontSize;
    double high = baseFontSize;

    for (int i = 0; i < 24; i++) {
      final middle = (low + high) / 2;

      if (fits(middle)) {
        low = middle;
      } else {
        high = middle;
      }
    }

    return low;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Expanded(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: visible
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: visible
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final textDirection = Directionality.of(context);

                        final textScaler = MediaQuery.textScalerOf(context);

                        final locale = Localizations.maybeLocaleOf(context);

                        final defaultStyle = DefaultTextStyle.of(context);

                        final baseStyle = defaultStyle.style;

                        final textHeightBehavior =
                            defaultStyle.textHeightBehavior ??
                            const TextHeightBehavior();

                        final fontSize = _calculateFontSize(
                          text: text,
                          style: baseStyle,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                          textDirection: textDirection,
                          textScaler: textScaler,
                          textHeightBehavior: textHeightBehavior,
                          locale: locale,
                        );

                        final textWidget = Text(
                          text,
                          textAlign: TextAlign.center,
                          softWrap: true,
                          textScaler: textScaler,
                          textHeightBehavior: textHeightBehavior,
                          locale: locale,
                          style: baseStyle.copyWith(fontSize: fontSize),
                        );

                        return Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Align(
                                  alignment: Alignment.center,
                                  child: textWidget,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
