import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';

import 'theme.dart';

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: appText(d), letterSpacing: -.5)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: appSubtext(d))),
        ],
      ),
    );
  }
}

/// Kartalar balandligi mazmuniga qarab o'zgaradi; ekran juda tor bo'lsa 1 ustun, keng bo'lsa 3 ustun.
class MetricGrid extends StatelessWidget {
  final List<Widget> children;
  const MetricGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 300 ? 1 : (c.maxWidth >= 640 ? 3 : 2);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        final slice = children.skip(i).take(cols).toList();
        rows.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(child: j < slice.length ? slice[j] : const SizedBox.shrink()),
              ],
            ]),
          ),
        ));
      }
      return Column(children: rows);
    });
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: appSubtext(isDarkOf(context)))),
      );
}

class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .4)),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorBox(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 50, color: AppColors.statusAbsent),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: appSubtext(isDarkOf(context)))),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Qayta urinish')),
            ],
          ]),
        ),
      );
}
