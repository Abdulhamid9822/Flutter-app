import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'theme.dart';

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTimeRange todayRange() {
  final n = DateTime.now();
  final d = DateTime(n.year, n.month, n.day);
  return DateTimeRange(start: d, end: d);
}

DateTimeRange weekRange() {
  final n = DateTime.now();
  final d = DateTime(n.year, n.month, n.day);
  return DateTimeRange(start: d.subtract(const Duration(days: 6)), end: d);
}

DateTimeRange monthRange() {
  final n = DateTime.now();
  return DateTimeRange(start: DateTime(n.year, n.month, 1), end: DateTime(n.year, n.month + 1, 0));
}

bool _same(DateTimeRange a, DateTimeRange b) => dayKey(a.start) == dayKey(b.start) && dayKey(a.end) == dayKey(b.end);

class PeriodBar extends StatelessWidget {
  final DateTimeRange range;
  final ValueChanged<DateTimeRange> onChanged;
  const PeriodBar({super.key, required this.range, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: range,
    );
    if (r != null) onChanged(r);
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    final presets = <(String, DateTimeRange)>[
      ('Bugun', todayRange()),
      ('Hafta', weekRange()),
      ('Oy', monthRange()),
    ];
    final custom = !presets.any((p) => _same(p.$2, range));
    final f = DateFormat('dd.MM.yyyy');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: cardDecoration(d),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.$1),
                  selected: _same(p.$2, range),
                  onSelected: (_) => onChanged(p.$2),
                ),
              ),
            ChoiceChip(
              avatar: const Icon(Icons.date_range, size: 16),
              label: const Text('Oraliq'),
              selected: custom,
              onSelected: (_) => _pick(context),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          _same(range, DateTimeRange(start: range.start, end: range.start))
              ? f.format(range.start)
              : '${f.format(range.start)}  —  ${f.format(range.end)}',
          style: TextStyle(fontSize: 12, color: appSubtext(d), fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

/// Har kun uchun keldi / kechikdi / kelmadi ustunlari.
class AttendanceChart extends StatelessWidget {
  final List<Map<String, dynamic>> days;
  const AttendanceChart({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    if (days.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: cardDecoration(d),
        child: Text('Ma\'lumot yo\'q', style: TextStyle(color: appMuted(d))),
      );
    }
    final width = (days.length * 44.0).clamp(MediaQuery.of(context).size.width - 64, 4000.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: cardDecoration(d),
      child: Column(children: [
        SizedBox(
          height: 170,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: CustomPaint(
              size: Size(width, 170),
              painter: _ChartPainter(days, appSubtext(d), appCardBorder(d)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _Legend('Keldi', AppColors.statusPresent),
          SizedBox(width: 14),
          _Legend('Kechikdi', AppColors.statusLate),
          SizedBox(width: 14),
          _Legend('Kelmadi', AppColors.statusAbsent),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final String t;
  final Color c;
  const _Legend(this.t, this.c);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(t, style: TextStyle(fontSize: 11, color: appSubtext(isDarkOf(context)))),
      ]);
}

class _ChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> days;
  final Color label;
  final Color grid;
  _ChartPainter(this.days, this.label, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 20.0;
    final h = size.height - bottom;
    int maxV = 1;
    for (final r in days) {
      for (final k in ['came', 'late', 'absent']) {
        final v = (r[k] as num).toInt();
        if (v > maxV) maxV = v;
      }
    }
    final line = Paint()..color = grid..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = h - h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    final slot = size.width / days.length;
    final barW = (slot / 4).clamp(4.0, 12.0);
    const colors = [AppColors.statusPresent, AppColors.statusLate, AppColors.statusAbsent];
    const keys = ['came', 'late', 'absent'];
    for (var i = 0; i < days.length; i++) {
      final cx = slot * i + slot / 2;
      for (var j = 0; j < 3; j++) {
        final v = (days[i][keys[j]] as num).toDouble();
        final bh = h * v / maxV;
        final x = cx + (j - 1) * (barW + 2) - barW / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, h - bh, barW, bh), const Radius.circular(3)),
          Paint()..color = colors[j],
        );
      }
      final tp = TextPainter(
        text: TextSpan(
            text: days[i]['date'].toString().substring(8),
            style: TextStyle(fontSize: 10, color: label)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, h + 5));
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.days != days;
}
