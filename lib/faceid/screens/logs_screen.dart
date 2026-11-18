import 'dart:io';

import 'package:flutter/material.dart';

import '../models/access_log.dart';
import '../services/database_service.dart';
import '../theme.dart';
import '../widgets/log_list_tile.dart';
import '../widgets/ui.dart';

class FaceIdLogsScreen extends StatefulWidget {
  const FaceIdLogsScreen({super.key});

  @override
  State<FaceIdLogsScreen> createState() => _FaceIdLogsScreenState();
}

class _FaceIdLogsScreenState extends State<FaceIdLogsScreen> {
  final _db = DatabaseService.instance;

  List<AccessLog> _logs = const [];
  String? _filter;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await _db.getLogs(limit: 500, action: _filter);
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _selectFilter(String? value) {
    if (_filter == value) return;
    setState(() => _filter = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jurnal'),
        actions: [
          IconButton(
            tooltip: 'Yangilash',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Barchasi',
                  selected: _filter == null,
                  onTap: () => _selectFilter(null),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Kirish',
                  selected: _filter == 'entry',
                  color: AppColors.green,
                  onTap: () => _selectFilter('entry'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Chiqish',
                  selected: _filter == 'exit',
                  color: AppColors.red,
                  onTap: () => _selectFilter('exit'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Xatolik',
        message: _error!,
        action: FilledButton(
          onPressed: _load,
          child: const Text('Qayta urinish'),
        ),
      );
    }
    if (_logs.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: "Yozuvlar yo'q",
        message: _filter == null
            ? "Hozircha jurnal bo'sh. Birinchi skanerdan so'ng yozuvlar "
                  "shu yerda paydo bo'ladi."
            : 'Bu turdagi yozuvlar topilmadi.',
      );
    }

    final groups = <String, List<AccessLog>>{};
    for (final log in _logs) {
      groups.putIfAbsent(formatDay(log.timestamp), () => []).add(log);
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          for (final entry in groups.entries) ...[
            _DayHeader(day: entry.key, logs: entry.value),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < entry.value.length; i++) ...[
                    if (i > 0) const Divider(),
                    LogListTile(
                      log: entry.value[i],
                      onTap: () => _showDetails(entry.value[i]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.storage_rounded, size: 13, color: AppColors.muted),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    "Yozuvlar qurilmada saqlanmoqda · MySQL sinxron keyin",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(AccessLog log) async {
    final color = log.isEntry ? AppColors.green : AppColors.red;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      log.isEntry ? Icons.login_rounded : Icons.logout_rounded,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.personName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          log.employeeCode,
                          style: const TextStyle(
                            color: AppColors.subtext,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Pill(text: log.actionLabel, color: color),
                ],
              ),
              if (log.photoPath != null) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(
                    File(log.photoPath!),
                    height: 240,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 120,
                      color: AppColors.surfaceHigh,
                      child: const Center(
                        child: Text(
                          'Rasm topilmadi',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _DetailRow(label: 'Vaqt', value: formatDateTime(log.timestamp)),
              const SizedBox(height: 10),
              _DetailRow(
                label: 'Ishonch',
                value: '${(log.confidence * 100).toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 10),
              const _DetailRow(
                label: 'Holat',
                value: "Qurilmada saqlangan · sinxron kutilmoqda",
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Yopish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.primary,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: color,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: selected ? color : AppColors.border),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF2A0F05) : AppColors.subtext,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      showCheckmark: false,
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.logs});

  final String day;
  final List<AccessLog> logs;

  @override
  Widget build(BuildContext context) {
    final entries = logs.where((log) => log.isEntry).length;
    final exits = logs.length - entries;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            day,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${logs.length} ta',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const Spacer(),
          if (entries > 0)
            Text(
              'kirish: $entries',
              style: const TextStyle(
                color: AppColors.green,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (entries > 0 && exits > 0) const SizedBox(width: 8),
          if (exits > 0)
            Text(
              'chiqish: $exits',
              style: const TextStyle(
                color: AppColors.red,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
