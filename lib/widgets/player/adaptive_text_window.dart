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
    this.minFontSize = 12,
  });

  double _calculateFontSize({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double maxHeight,
    required TextDirection textDirection,
    required TextScaler textScaler,
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
      );

      painter.layout(maxWidth: maxWidth);

      return painter.height <= maxHeight;
    }

    if (fits(baseFontSize)) {
      return baseFontSize;
    }

    if (!fits(minFontSize)) {
      return minFontSize;
    }

    var low = minFontSize;
    var high = baseFontSize;

    for (var i = 0; i < 16; i++) {
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
                        final baseStyle = TextStyle(fontSize: baseFontSize);

                        final fontSize = _calculateFontSize(
                          text: text,
                          style: baseStyle,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        );

                        final painter = TextPainter(
                          text: TextSpan(
                            text: text,
                            style: baseStyle.copyWith(fontSize: fontSize),
                          ),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                          textAlign: TextAlign.center,
                        )..layout(maxWidth: constraints.maxWidth);

                        // Для исключительно длинных текстов, которые
                        // не помещаются даже с минимальным размером,
                        // оставляем возможность прокрутки.
                        final needsScroll =
                            painter.height > constraints.maxHeight;

                        final textWidget = Text(
                          text,
                          textAlign: TextAlign.center,
                          style: baseStyle.copyWith(fontSize: fontSize),
                        );

                        if (needsScroll) {
                          return SingleChildScrollView(child: textWidget);
                        }

                        return Center(child: textWidget);
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
