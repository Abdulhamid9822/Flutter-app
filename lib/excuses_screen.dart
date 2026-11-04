import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';

import 'api.dart';
import 'main.dart' show handleAuthError;
import 'push.dart';
import 'screens.dart' show timeOf;
import 'theme.dart';
import 'widgets.dart';

String _typeLabel(String t) => t == 'early' ? 'Erta ketish' : 'Kech kelish';

(String, Color) _statusInfo(String s) => switch (s) {
      'approved' => ('Tasdiqlangan', AppColors.statusPresent),
      'rejected' => ('Rad etilgan', AppColors.statusAbsent),
      _ => ('Kutilmoqda', AppColors.statusLate),
    };

class ExcusesView extends StatefulWidget {
  final bool employeeMode;
  const ExcusesView({super.key, required this.employeeMode});
  @override
  State<ExcusesView> createState() => _ExcusesViewState();
}

class _ExcusesViewState extends State<ExcusesView> {
  late Future<Map<String, dynamic>> _future = Api.instance.excuses();
  late String _filter = widget.employeeMode ? 'all' : 'pending';

  @override
  void initState() {
    super.initState();
    PushService.excuseEvents.addListener(_reload);
  }

  @override
  void dispose() {
    PushService.excuseEvents.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = Api.instance.excuses());
  }

  Future<void> _decide(int id, String decision) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision == 'approved' ? 'Tasdiqlash' : 'Rad etish'),
        content: TextField(
          controller: c,
          maxLength: 300,
          maxLines: 3,
          minLines: 2,
          autofocus: true,
          decoration: InputDecoration(
              labelText: tr('Xodimga javob (ixtiyoriy)'), border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yuborish')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.instance.decideExcuse(id, decision, note: c.text.trim());
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) return handleAuthError(context, e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _create() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewExcuseSheet(),
    );
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: widget.employeeMode
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Ariza'),
            )
          : null,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary));
          }
          if (snap.hasError) {
            final e = snap.error;
            if (e is ApiException && e.unauthorized) {
              WidgetsBinding.instance.addPostFrameCallback((_) => handleAuthError(context, e));
            }
            return ErrorBox('$e', onRetry: _reload);
          }
          final all = (snap.data!['requests'] as List).cast<Map<String, dynamic>>();
          final list = _filter == 'all' ? all : all.where((r) => r['status'] == _filter).toList();
          return Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                for (final f in const [
                  ('pending', 'Kutilmoqda'),
                  ('approved', 'Tasdiqlangan'),
                  ('rejected', 'Rad etilgan'),
                  ('all', 'Hammasi'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${f.$2} (${f.$1 == 'all' ? all.length : all.where((r) => r['status'] == f.$1).length})'),
                      selected: _filter == f.$1,
                      onSelected: (_) => setState(() => _filter = f.$1),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: list.isEmpty
                    ? ListView(children: [
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(child: Text('Arizalar yo\'q', style: TextStyle(color: appMuted(d)))),
                        ),
                      ])
                    : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
                        for (final r in list) _card(r, d),
                      ]),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _info(IconData icon, String text, bool d, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color ?? appMuted(d)),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color ?? appSubtext(d)))),
        ]),
      );

  String _dt(dynamic v) {
    final s = '${v ?? ''}';
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  Widget _card(Map<String, dynamic> r, bool d) {
    final (label, color) = _statusInfo('${r['status']}');
    final pending = r['status'] == 'pending';
    final early = r['type'] == 'early';
    final expected = r['time'] as String?;
    final actualIn = r['actual_in'] == null ? null : timeOf(r['actual_in']);
    final actualOut = r['actual_out'] == null ? null : timeOf(r['actual_out']);
    final actual = early ? actualOut : actualIn;
    final late = r['late_minutes'] as int?;
    final earlyMin = r['early_minutes'] as int?;

    String? verdict;
    Color? verdictColor;
    if (r['status'] == 'approved') {
      if (expected == null || actual == null) {
        verdict = 'Tasdiqlangan: jarima qo\'llanmaydi';
        verdictColor = AppColors.statusPresent;
      } else if (early ? actual.compareTo(expected) >= 0 : actual.compareTo(expected) <= 0) {
        verdict = 'Ariza vaqtiga amal qilgan: jarima qo\'llanmaydi';
        verdictColor = AppColors.statusPresent;
      } else {
        verdict = 'Ariza vaqtiga amal qilmagan: jarima qo\'llanadi';
        verdictColor = AppColors.statusAbsent;
      }
    }

    final spot = r['spot_id'];
    final subtitle = [
      if ('${r['position'] ?? ''}'.isNotEmpty) '${r['position']}',
      if (spot != null) 'Filial $spot',
    ].join('  •  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDecoration(d),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.employeeMode ? _typeLabel('${r['type']}') : '${r['name']}',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: appText(d))),
              if (!widget.employeeMode && subtitle.isNotEmpty)
                Text(subtitle, style: TextStyle(fontSize: 12, color: appSubtext(d))),
            ]),
          ),
          const SizedBox(width: 8),
          StatusPill(label, color),
        ]),
        const SizedBox(height: 4),
        if (!widget.employeeMode) _info(Icons.event_note, _typeLabel('${r['type']}'), d),
        _info(Icons.calendar_today, 'Sana: ${r['date']}', d),
        if (expected != null)
          _info(Icons.access_time, '${early ? 'Ketish' : 'Kelish'} vaqti (so\'ralgan): $expected', d),
        _info(Icons.fingerprint,
            'Haqiqiy: kirdi ${actualIn ?? '--:--'}  •  chiqdi ${actualOut ?? '--:--'}', d),
        if (!early && late != null && late > 0) _info(Icons.schedule, 'Kechikish: $late daqiqa', d),
        if (early && earlyMin != null && earlyMin < 0)
          _info(Icons.logout, 'Erta ketgan: ${-earlyMin} daqiqa', d),
        if ('${r['reason']}'.isNotEmpty) _info(Icons.notes, 'Sabab: ${r['reason']}', d),
        _info(Icons.send, 'Yuborilgan: ${_dt(r['created_at'])}', d),
        if (r['decided_by'] != null)
          _info(Icons.how_to_reg, 'Qaror: ${r['decided_by']}  •  ${_dt(r['decided_at'])}', d),
        if (verdict != null) _info(Icons.gavel, verdict, d, color: verdictColor),
        if ('${r['response'] ?? ''}'.isNotEmpty)
          _info(Icons.chat_bubble_outline, 'Javob: ${r['response']}', d),
        if (!widget.employeeMode && pending) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _decide(r['id'] as int, 'rejected'),
                child: const Text('Rad etish'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => _decide(r['id'] as int, 'approved'),
                child: const Text('Tasdiqlash'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _NewExcuseSheet extends StatefulWidget {
  const _NewExcuseSheet();
  @override
  State<_NewExcuseSheet> createState() => _NewExcuseSheetState();
}

class _NewExcuseSheetState extends State<_NewExcuseSheet> {
  DateTime _date = DateTime.now();
  String _type = 'late';
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _dateStr =>
      '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  String get _timeStr =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final p = await showTimePicker(context: context, initialTime: _time);
    if (p != null) setState(() => _time = p);
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final p = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 31)),
      lastDate: now.add(const Duration(days: 7)),
    );
    if (p != null) setState(() => _date = p);
  }

  Future<void> _send() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Sababni yozing');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.createExcuse(_dateStr, _type, _timeStr, _reason.text.trim());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.unauthorized) {
        Navigator.pop(context);
        return handleAuthError(context, e);
      }
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Yangi ariza', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'late', label: Text('Kech kelish', maxLines: 1, overflow: TextOverflow.ellipsis)),
              ButtonSegment(value: 'early', label: Text('Erta ketish', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(_dateStr),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickTime,
          icon: const Icon(Icons.access_time, size: 18),
          label: Text(_type == 'early' ? 'Ketish vaqti: $_timeStr' : 'Kelish vaqti: $_timeStr'),
        ),
        const SizedBox(height: 4),
        Text(
          _type == 'early'
              ? 'Shu vaqtdan oldin ketsangiz, jarima qo\'llanadi.'
              : 'Shu vaqtdan kech qolsangiz, jarima qo\'llanadi.',
          style: TextStyle(fontSize: 12, color: appMuted(isDarkOf(context))),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(labelText: tr('Sabab'), border: OutlineInputBorder()),
        ),
        if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.statusAbsent)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Yuborish'),
          ),
        ),
      ]),
      ),
    );
  }
}
