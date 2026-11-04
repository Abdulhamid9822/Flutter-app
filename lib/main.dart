import 'package:flutter/material.dart' hide Text;
import 'i18n.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'excuses_screen.dart';
import 'period.dart';
import 'push.dart';
import 'screens.dart';
import 'theme.dart';
import 'widgets.dart';

final _money = NumberFormat('#,##0', 'en_US');
String som(num v) => '${_money.format(v).replaceAll(',', ' ')} ${tr('so\'m')}';
String monthKey(DateTime d) => DateFormat('yyyy-MM').format(d);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.instance.load();
  await AppLang.load();
  await ThemeController.load();
  await PushService.init();
  PushService.register();
  Api.instance.refreshLang();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = Api.instance.token != null && Api.instance.user != null;
    return ValueListenableBuilder<String>(
      valueListenable: AppLang.lang,
      builder: (_, lang, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (_, mode, _) => MaterialApp(
          key: ValueKey(lang),
          title: 'Davomat Pro',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: loggedIn ? const HomeScreen() : const LoginScreen(),
        ),
      ),
    );
  }
}

void _toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> _forceLogout(BuildContext c) async {
  await Api.instance.logout();
  if (c.mounted) {
    Navigator.of(c).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
}

void handleAuthError(BuildContext context, Object? e) => _handleAuthError(context, e);

void _handleAuthError(BuildContext context, Object? e) {
  if (e is ApiException && e.unauthorized) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _forceLogout(context));
  }
}

// ---------------- LOGIN ----------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController(text: Api.instance.baseUrl);
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  late bool _showServer = Api.instance.baseUrl.isEmpty;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.login(_server.text.trim(), _phone.text.trim(), _pin.text.trim());
      if (!mounted) return;
      Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Scaffold(
      body: Container(
        decoration: appScreenBackground(d),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [AppColors.brandPrimary, AppColors.brandCyan]),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.access_time_filled_rounded,
                          size: 44, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('DAVOMAT PRO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: appText(d))),
                  const SizedBox(height: 6),
                  Text('Xodimlar davomati va oyligi',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: appSubtext(d))),
                  const SizedBox(height: 32),
                  const LangPicker(),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                        labelText: tr('Telefon raqam'),
                        prefixText: '+998 ',
                        prefixIcon: Icon(Icons.phone)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pin,
                    obscureText: _obscure,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'PIN',
                      counterText: '',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure)),
                    ),
                  ),
                  if (_showServer) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                          labelText: tr('Server manzili'),
                          hintText: 'example.com',
                          prefixIcon: Icon(Icons.dns)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Kirish'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _showServer = !_showServer),
                    child: Text(_showServer ? 'Server sozlamasini yashirish' : 'Server sozlamasi',
                        style: TextStyle(color: appSubtext(d), fontSize: 12)),
                  ),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.statusAbsent.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.statusAbsent.withValues(alpha: .4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: AppColors.statusAbsent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(color: AppColors.statusAbsent, fontSize: 13))),
                      ]),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- HOME ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  List<String> _titles = const [];

  @override
  void initState() {
    super.initState();
    PushService.openExcuses.addListener(_gotoExcuses);
    if (PushService.openExcuses.value > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _gotoExcuses());
  }

  @override
  void dispose() {
    PushService.openExcuses.removeListener(_gotoExcuses);
    super.dispose();
  }

  void _gotoExcuses() {
    final i = _titles.indexOf('ARIZALAR');
    if (mounted && i >= 0) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final user = Api.instance.user!;
    final pages = <Widget>[];
    final items = <NavigationDestination>[];
    final titles = <String>[];
    pages.add(DashboardView(employeeMode: user.isEmployee));
    items.add(NavigationDestination(
        icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: tr('Bosh sahifa')));
    titles.add('BOSH SAHIFA');
    if (user.isEmployee) {
      pages.addAll([
        SalaryView(employeeId: user.employeeId),
        AttendanceView(employeeId: user.employeeId),
      ]);
      items.addAll([
        NavigationDestination(
            icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: tr('Oylik')),
        NavigationDestination(
            icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: tr('Tarix')),
      ]);
      titles.addAll(['MENING OYLIGIM', 'DAVOMAT TARIXI']);
      pages.add(const ExcusesView(employeeMode: true));
      items.add(NavigationDestination(
          icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: tr('Arizalar')));
      titles.add('ARIZALAR');
    } else {
      pages.add(const EmployeesScreen());
      items.add(NavigationDestination(
          icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: tr('Xodimlar')));
      titles.add('XODIMLAR RO\'YXATI');
      pages.add(const DailyReportView());
      items.add(NavigationDestination(
          icon: Icon(Icons.event_available_outlined),
          selectedIcon: Icon(Icons.event_available),
          label: tr('Davomat')));
      titles.add('DAVOMAT');
      pages.add(const ExcusesView(employeeMode: false));
      items.add(NavigationDestination(
          icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: tr('Arizalar')));
      titles.add('ARIZALAR');
      if (user.role == 'super') {
        pages.add(const BranchesScreen());
        items.add(NavigationDestination(
            icon: Icon(Icons.store_outlined), selectedIcon: Icon(Icons.store), label: tr('Filiallar')));
        titles.add('FILIALLAR');
      }
    }
    pages.add(const ProfileScreen());
    items.add(NavigationDestination(
        icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: tr('Sozlamalar')));
    titles.add('SOZLAMALAR');
    _titles = titles;

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index],
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      ),
      body: Container(
        decoration: appScreenBackground(isDarkOf(context)),
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: items,
      ),
    );
  }
}

// ---------------- MONTH PICKER ----------------
class MonthBar extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const MonthBar({super.key, required this.month, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    final isCurrent = monthKey(month) == monthKey(DateTime.now());
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: cardDecoration(d),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(
            onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left)),
        Text(DateFormat('MMMM yyyy', AppLang.code).format(month),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: appText(d))),
        IconButton(
            onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }
}

// ---------------- SALARY ----------------
class SalaryView extends StatefulWidget {
  final int? employeeId;
  const SalaryView({super.key, this.employeeId});
  @override
  State<SalaryView> createState() => _SalaryViewState();
}

class _SalaryViewState extends State<SalaryView> {
  DateTime _month = DateTime.now();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Api.instance.salary(monthKey(_month), employeeId: widget.employeeId);
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Column(children: [
      MonthBar(
          month: _month,
          onChanged: (m) => setState(() {
                _month = m;
                _load();
              })),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary));
            }
            if (snap.hasError) {
              _handleAuthError(context, snap.error);
              return ErrorBox('${snap.error}', onRetry: () => setState(_load));
            }
            final s = snap.data!['salary'] as Map<String, dynamic>;
            final emp = snap.data!['employee'] as Map<String, dynamic>;
            final payments = (snap.data!['payments'] as List).cast<Map<String, dynamic>>();
            final paymentsOk = snap.data!['payments_available'] == true;
            final assigned = <String>[];
            if ((s['fixed'] as num) > 0) assigned.add('${som(s['fixed'])} / oy');
            if ((s['hourly'] as num) > 0) assigned.add('${som(s['hourly'])} / soat');
            if ((s['percent'] as num) > 0) assigned.add('${s['percent']}%');
            if ((s['shift'] as num) > 0) assigned.add('${som(s['shift'])} / smena');
            final balance = s['balance'] as num?;
            final debt = balance != null && balance > 0;

            return RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.brandPrimary, AppColors.brandCyan]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(emp['name'] ?? '',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    if ((emp['position'] ?? '').toString().isNotEmpty)
                      Text(emp['position'], style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    const Text('BELGILANGAN OYLIK',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(assigned.isEmpty ? 'Belgilanmagan' : assigned.join('\n'),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(height: 14),
                MetricGrid(
                  children: [
                    MetricCard(
                        label: 'Hisoblangan',
                        value: s['earned'] == null ? '—' : som(s['earned']),
                        icon: Icons.calculate,
                        color: AppColors.brandPrimary),
                    MetricCard(
                        label: 'To\'langan',
                        value: s['paid'] == null ? '—' : som(s['paid']),
                        icon: Icons.check_circle,
                        color: AppColors.statusPresent),
                    MetricCard(
                        label: 'Oldingi oy balansi',
                        value: som(s['previous_balance']),
                        icon: Icons.history,
                        color: AppColors.brandIndigo),
                    MetricCard(
                        label: balance == null
                            ? 'To\'lanishi kerak'
                            : (debt ? 'To\'lanishi kerak' : balance < 0 ? 'Ortiqcha to\'langan' : 'Hisob-kitob teng'),
                        value: balance == null ? '—' : som(balance.abs()),
                        icon: Icons.account_balance_wallet,
                        color: balance != null && balance < 0 ? AppColors.statusAbsent : AppColors.statusLate),
                  ],
                ),
                if (s['earned'] == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Bu oy hisobi hali veb-hisobotda saqlanmagan.',
                        style: TextStyle(fontSize: 12, color: appMuted(d))),
                  ),
                SectionLabel(paymentsOk ? 'To\'lovlar (${payments.length})' : 'To\'lovlarni olib bo\'lmadi'),
                for (final p in payments)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: cardDecoration(d),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: AppColors.statusPresent.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.payments, color: AppColors.statusPresent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(som(p['amount'] as num),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16, color: appText(d))),
                          Text(
                              [
                                p['date'].toString().split(' ').first,
                                if ((p['comment'] ?? '').toString().isNotEmpty) p['comment'],
                              ].join('  •  '),
                              style: TextStyle(fontSize: 12, color: appSubtext(d))),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            );
          },
        ),
      ),
    ]);
  }
}

// ---------------- ATTENDANCE ----------------
class AttendanceView extends StatefulWidget {
  final int? employeeId;
  const AttendanceView({super.key, this.employeeId});
  @override
  State<AttendanceView> createState() => _AttendanceViewState();
}

class _AttendanceViewState extends State<AttendanceView> {
  DateTimeRange _range = monthRange();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future = Api.instance.attendance(monthKey(_range.start),
        employeeId: widget.employeeId, from: dayKey(_range.start), to: dayKey(_range.end));
  }

  String _t(dynamic v) => timeOf(v);

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Column(children: [
      PeriodBar(
          range: _range,
          onChanged: (r) => setState(() {
                _range = r;
                _load();
              })),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary));
            }
            if (snap.hasError) {
              _handleAuthError(context, snap.error);
              return ErrorBox('${snap.error}', onRetry: () => setState(_load));
            }
            final days = (snap.data!['days'] as List).cast<Map<String, dynamic>>();
            final manual = ((snap.data!['manual'] as List?) ?? []).cast<Map<String, dynamic>>();
            final penalties = manual.where((m) => m['turi'] == 'penalty').toList();
            if (days.isEmpty && penalties.isEmpty) {
              return Center(
                  child: Text('Bu davrda davomat yo\'q', style: TextStyle(color: appSubtext(d))));
            }
            return RefreshIndicator(
              onRefresh: () async => setState(_load),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: days.length + penalties.length,
                itemBuilder: (_, i) {
                  if (i >= days.length) {
                    final m = penalties[i - days.length];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: cardDecoration(d),
                      child: Row(children: [
                        const Icon(Icons.gavel, color: AppColors.statusAbsent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Jarima: -${som(double.tryParse('${m['miqdor']}') ?? 0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, color: AppColors.statusAbsent)),
                            if ('${m['izoh'] ?? ''}'.isNotEmpty)
                              Text('Sabab: ${m['izoh']}',
                                  style: TextStyle(fontSize: 12, color: appSubtext(d))),
                            Text('${m['oy_vaqt']}'.substring(0, 7),
                                style: TextStyle(fontSize: 12, color: appSubtext(d))),
                          ]),
                        ),
                      ]),
                    );
                  }
                  final r = days[i];
                  final late = int.tryParse('${r['kechikish_daqiqa'] ?? 0}') ?? 0;
                  final st = statusFor(r['davomat_holati'] as String?, late);
                  final penalty = double.tryParse('${r['penalty'] ?? 0}') ?? 0;
                  final why = '${r['penalty_reason'] ?? ''}';
                  final reasons = <String>[
                    for (final p in why.split(',').where((e) => e.isNotEmpty))
                      p.startsWith('late:')
                          ? '${tr('Kechikish')}: ${p.substring(5)} ${tr('daqiqa')}'
                          : '${tr('Erta ketgan')}: ${p.substring(6)} ${tr('daqiqa')}',
                  ];
                  final excused = '${r['excused'] ?? ''}'.isNotEmpty;
                  final note = '${r['note'] ?? ''}';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: cardDecoration(d),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: st.$2.withValues(alpha: .15),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(r['sana'].toString().substring(8),
                            style: TextStyle(
                                color: st.$2, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (r['davomat_holati'] != 'dayoff')
                            Text('${_t(r['check_in'])}  —  ${_t(r['check_out'])}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15, color: appText(d))),
                          if (note.isNotEmpty)
                            Text('Izoh: $note', style: TextStyle(fontSize: 12, color: appSubtext(d))),
                          if (late > 0 && penalty <= 0)
                            Text('Kechikish: $late daqiqa',
                                style: const TextStyle(fontSize: 12, color: AppColors.statusLate)),
                          if (penalty > 0) ...[
                            Text('Jarima: -${som(penalty)}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.statusAbsent)),
                            for (final x in reasons)
                              Text('Sabab: $x',
                                  style: const TextStyle(fontSize: 12, color: AppColors.statusLate)),
                          ],
                          if (excused)
                            Text('Ariza tasdiqlangan — jarima yo\'q',
                                style: const TextStyle(fontSize: 12, color: AppColors.statusPresent)),
                        ]),
                      ),
                      StatusPill(st.$1, st.$2),
                    ]),
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ---------------- EMPLOYEES (admin) ----------------
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  DateTime _month = DateTime.now();
  String _q = '';
  int _spot = 0;
  List<Map<String, dynamic>> _branches = [];
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _load();
    if (Api.instance.user!.role == 'super') {
      Api.instance.branches().then((d) {
        if (mounted) setState(() => _branches = (d['branches'] as List).cast<Map<String, dynamic>>());
      }).catchError((_) {});
    }
  }

  void _load() {
    _future = Api.instance.employees(monthKey(_month), q: _q, spotId: _spot);
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return Column(children: [
      MonthBar(
          month: _month,
          onChanged: (m) => setState(() {
                _month = m;
                _load();
              })),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                  hintText: tr('Xodim qidirish'), prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (v) {
                _q = v.trim();
                setState(_load);
              },
            ),
          ),
          if (_branches.isNotEmpty) ...[
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _spot,
              underline: const SizedBox.shrink(),
              dropdownColor: appCardBackground(d),
              items: [
                const DropdownMenuItem(value: 0, child: Text('Barchasi')),
                for (final b in _branches.where((b) => b['spot_id'] != 0))
                  DropdownMenuItem(value: b['spot_id'] as int, child: Text('Filial ${b['spot_id']}')),
              ],
              onChanged: (v) => setState(() {
                _spot = v ?? 0;
                _load();
              }),
            ),
          ],
        ]),
      ),
      Expanded(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary));
            }
            if (snap.hasError) {
              _handleAuthError(context, snap.error);
              return ErrorBox('${snap.error}', onRetry: () => setState(_load));
            }
            final list = (snap.data!['employees'] as List).cast<Map<String, dynamic>>();
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  Expanded(
                    child: MetricCard(
                        label: 'Xodimlar',
                        value: '${list.length}',
                        icon: Icons.people,
                        color: AppColors.brandPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                        label: 'Jami to\'langan',
                        value: som(snap.data!['total_paid'] as num),
                        icon: Icons.payments,
                        color: AppColors.statusPresent),
                  ),
                ]),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => setState(_load),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final e = list[i];
                      final assigned = <String>[];
                      if ((e['fixed'] as num) > 0) assigned.add('${som(e['fixed'])}/oy');
                      if ((e['hourly'] as num) > 0) assigned.add('${som(e['hourly'])}/soat');
                      if ((e['percent'] as num) > 0) assigned.add('${e['percent']}%');
                      if ((e['shift'] as num) > 0) assigned.add('${som(e['shift'])}/smena');
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => showEmployeeSheet(
                            context, e['id'] as int, e['name'] ?? '', e['position'] ?? ''),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: cardDecoration(d),
                          child: Row(children: [
                            CircleAvatar(
                              backgroundColor: AppColors.brandPrimary.withValues(alpha: .2),
                              child: Text(
                                  (e['name'] ?? '?').toString().isEmpty
                                      ? '?'
                                      : e['name'].toString().substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                      color: AppColors.brandPrimary, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(e['name'] ?? '',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 15, color: appText(d))),
                                Text(
                                    '${e['position'] ?? ''}  •  ${assigned.isEmpty ? 'oylik belgilanmagan' : assigned.join(' + ')}',
                                    style: TextStyle(fontSize: 12, color: appSubtext(d))),
                              ]),
                            ),
                            Flexible(
                              flex: 0,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 110),
                                child: Builder(builder: (_) {
                              final bal = e['balance'] as num?;
                              final debt = bal != null && bal > 0;
                              final over = bal != null && bal < 0;
                              return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(debt ? 'To\'lanishi kerak' : over ? 'Ortiqcha to\'langan' : 'Hisob-kitob teng',
                                    maxLines: 2,
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10, color: appMuted(d))),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(bal == null ? '—' : som(bal.abs()),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: over
                                            ? AppColors.statusAbsent
                                            : debt
                                                ? AppColors.statusLate
                                                : appSubtext(d))),
                                ),
                              ]);
                            }),
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

class EmployeeDetailScreen extends StatelessWidget {
  final int id;
  final String name;
  const EmployeeDetailScreen({super.key, required this.id, required this.name});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          bottom: const TabBar(
              indicatorColor: AppColors.brandPrimary,
              tabs: [Tab(text: 'Oylik'), Tab(text: 'Davomat')]),
        ),
        body: Container(
          decoration: appScreenBackground(isDarkOf(context)),
          child: TabBarView(children: [SalaryView(employeeId: id), AttendanceView(employeeId: id)]),
        ),
      ),
    );
  }
}

// ---------------- BRANCHES (super) ----------------
class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});
  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  late Future<Map<String, dynamic>> _future = Api.instance.branches();

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: AppColors.brandPrimary));
        }
        if (snap.hasError) {
          return ErrorBox('${snap.error}',
              onRetry: () => setState(() => _future = Api.instance.branches()));
        }
        final list = (snap.data!['branches'] as List).cast<Map<String, dynamic>>();
        return RefreshIndicator(
          onRefresh: () async => setState(() => _future = Api.instance.branches()),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            for (final b in list)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: cardDecoration(d),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.brandPrimary.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.store, color: AppColors.brandPrimary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(b['spot_id'] == 0 ? 'Biriktirilmagan' : 'Filial ${b['spot_id']}',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: appText(d))),
                  ),
                  StatusPill('${b['employees']} xodim', AppColors.brandPrimary),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

// ---------------- PROFILE ----------------
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _changePin(BuildContext context) async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN almashtirish'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: oldC,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Eski PIN'))),
          const SizedBox(height: 12),
          TextField(
              controller: newC,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(labelText: tr('Yangi PIN (4-6 raqam)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Saqlash')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.instance.changePin(oldC.text, newC.text);
      if (context.mounted) _toast(context, 'PIN o\'zgartirildi');
    } on ApiException catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }

  Widget _tile(bool d, IconData icon, String title, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? AppColors.brandPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(d),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration:
                BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: c, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: TextStyle(fontWeight: FontWeight.w700, color: color ?? appText(d)))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = isDarkOf(context);
    final u = Api.instance.user!;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.brandPrimary, AppColors.brandCyan]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          const CircleAvatar(
              radius: 26,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 28)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name.isEmpty ? '—' : u.name,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
              Text(u.roleLabel, style: const TextStyle(color: Colors.white70)),
            ]),
          ),
        ]),
      ),
      _tile(d, Icons.lock_reset, 'PIN almashtirish', () => _changePin(context)),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LangPicker(),
      ),
      ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeController.mode,
        builder: (_, m, _) => _tile(
            d,
            m == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            m == ThemeMode.dark ? 'Yorqin mavzu' : 'Qorong\'u mavzu',
            () => ThemeController.set(m == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark)),
      ),
      _tile(d, Icons.notifications_active, 'Push sinash', () async {
        _toast(context, 'Sinalmoqda...');
        final r = await PushService.test();
        if (context.mounted) {
          showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                    title: const Text('Push sinov'),
                    content: Text(r),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                  ));
        }
      }),
      _tile(d, Icons.logout, 'Chiqish', () => _forceLogout(context), color: AppColors.statusAbsent),
    ]);
  }
}
