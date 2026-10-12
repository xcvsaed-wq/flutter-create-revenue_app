import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RevenueApp());
}

const List<String> kParties = ['سعيد', 'إبراهيم'];

const List<String> kMonthsAr = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

// ---------------------------------------------------------------------------
// نموذج السجل
// ---------------------------------------------------------------------------
class RevenueRecord {
  final String id;
  final String party;
  final int year;
  final int month; // 1..12
  double amount;
  String note;
  final String createdAt;

  RevenueRecord({
    required this.id,
    required this.party,
    required this.year,
    required this.month,
    required this.amount,
    required this.note,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'party': party,
        'year': year,
        'month': month,
        'amount': amount,
        'note': note,
        'createdAt': createdAt,
      };

  factory RevenueRecord.fromJson(Map<String, dynamic> j) => RevenueRecord(
        id: j['id'] as String,
        party: j['party'] as String,
        year: j['year'] as int,
        month: j['month'] as int,
        amount: (j['amount'] as num).toDouble(),
        note: (j['note'] as String?) ?? '',
        createdAt: (j['createdAt'] as String?) ?? '',
      );
}

// ---------------------------------------------------------------------------
// مخزن البيانات (SharedPreferences + JSON)
// ---------------------------------------------------------------------------
class RevenueStore {
  static const _key = 'revenues_v1';
  final List<RevenueRecord> _items = [];

  List<RevenueRecord> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _items.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      for (final e in decoded) {
        _items.add(RevenueRecord.fromJson(e as Map<String, dynamic>));
      }
    } catch (_) {
      // بيانات تالفة — نبدأ من جديد بأمان بدل الكراش
      _items.clear();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_key, encoded);
  }

  bool exists(String party, int year, int month) {
    return _items.any(
      (e) => e.party == party && e.year == year && e.month == month,
    );
  }

  Future<void> add(RevenueRecord r) async {
    _items.add(r);
    await _persist();
  }

  Future<void> update(String id, double amount, String note) async {
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _items[idx].amount = amount;
    _items[idx].note = note;
    await _persist();
  }

  Future<void> delete(String id) async {
    _items.removeWhere((e) => e.id == id);
    await _persist();
  }

  List<RevenueRecord> filtered({String? party, int? year}) {
    return _items.where((e) {
      if (party != null && e.party != party) return false;
      if (year != null && e.year != year) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        if (a.year != b.year) return b.year.compareTo(a.year);
        if (a.month != b.month) return b.month.compareTo(a.month);
        return a.party.compareTo(b.party);
      });
  }

  List<int> distinctYears() {
    final set = <int>{for (final e in _items) e.year};
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  Map<String, double> yearlyTotals() {
    final map = <String, double>{};
    for (final e in _items) {
      final k = '${e.year}|${e.party}';
      map[k] = (map[k] ?? 0) + e.amount;
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// التطبيق
// ---------------------------------------------------------------------------
class RevenueApp extends StatelessWidget {
  const RevenueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سجل الإيرادات',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFC107),
          secondary: Color(0xFF2E6BFF),
        ),
      ),
      home: const RevenueScreen(),
    );
  }
}

class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  final RevenueStore _store = RevenueStore();

  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _party = kParties.first;
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;

  String _filterParty = 'الكل';
  int? _filterYear;

  String? _editingId;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _store.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // --- منطق -----------------------------------------------------------
  Future<void> _add() async {
    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', ''));
    if (amount == null || amount < 0) {
      _snack('أدخل مبلغاً رقمياً صحيحاً (≥ 0).');
      return;
    }
    if (_editingId == null && _store.exists(_party, _year, _month)) {
      _snack('يوجد سجل بالفعل لـ $_party في ${kMonthsAr[_month - 1]} $_year.');
      return;
    }

    final now = DateTime.now().toIso8601String();
    final rec = RevenueRecord(
      id: _editingId ?? now,
      party: _party,
      year: _year,
      month: _month,
      amount: amount,
      note: _noteCtrl.text.trim(),
      createdAt: _editingId == null ? now : now,
    );

    if (_editingId == null) {
      await _store.add(rec);
    } else {
      await _store.update(_editingId!, amount, rec.note);
    }

    if (!mounted) return;
    setState(() {
      _editingId = null;
      _amountCtrl.clear();
      _noteCtrl.clear();
    });
    _snack('تم الحفظ.');
  }

  Future<void> _delete(RevenueRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B2E),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
        content: Text(
          'حذف سجل ${r.party} — ${kMonthsAr[r.month - 1]} ${r.year}؟',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _store.delete(r.id);
    if (!mounted) return;
    setState(() {});
  }

  void _loadIntoForm(RevenueRecord r) {
    setState(() {
      _editingId = r.id;
      _party = r.party;
      _year = r.year;
      _month = r.month;
      _amountCtrl.text = r.amount.toString();
      _noteCtrl.text = r.note;
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1B1B2E),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- بناء الواجهة ---------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0E0E1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFC107)),
        ),
      );
    }

    final rows = _store.filtered(
      party: _filterParty == 'الكل' ? null : _filterParty,
      year: _filterYear,
    );
    final totals = _store.yearlyTotals();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E1A),
        elevation: 0,
        title: const Text(
          '📒 سجل الإيرادات الشهرية',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
        ),
        centerTitle: true,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            _buildForm(),
            _buildFilters(),
            Expanded(child: _buildList(rows)),
            _buildTotals(totals),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final years = <int>[
      for (int y = DateTime.now().year - 5;
          y <= DateTime.now().year + 5;
          y++)
        y,
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161625),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _dropdown<String>(
                  label: 'الطرف',
                  value: _party,
                  items: kParties,
                  labelOf: (v) => v,
                  onChanged: (v) => setState(() => _party = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dropdown<int>(
                  label: 'السنة',
                  value: _year,
                  items: years,
                  labelOf: (v) => '$v',
                  onChanged: (v) => setState(() => _year = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _dropdown<int>(
                  label: 'الشهر',
                  value: _month,
                  items: List.generate(12, (i) => i + 1),
                  labelOf: (v) => kMonthsAr[v - 1],
                  onChanged: (v) => setState(() => _month = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco('المبلغ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _noteCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDeco('ملاحظة (اختياري)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _add,
                  icon: Icon(
                    _editingId == null ? Icons.add : Icons.save,
                    color: Colors.black,
                  ),
                  label: Text(
                    _editingId == null ? 'إضافة' : 'تعديل المحدد',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _editingId = null;
                    _amountCtrl.clear();
                    _noteCtrl.clear();
                  });
                },
                icon: const Icon(Icons.cleaning_services,
                    color: Colors.white70),
                label: const Text('تفريغ',
                    style: TextStyle(color: Colors.white70)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final years = _store.distinctYears();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161625),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Text('فلترة:',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: _dropdown<String>(
              label: 'الطرف',
              value: _filterParty,
              items: ['الكل', ...kParties],
              labelOf: (v) => v,
              onChanged: (v) => setState(() => _filterParty = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dropdown<int?>(
              label: 'السنة',
              value: _filterYear,
              items: [null, ...years],
              labelOf: (v) => v == null ? 'الكل' : '$v',
              onChanged: (v) => setState(() => _filterYear = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<RevenueRecord> rows) {
    if (rows.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد سجلات بعد.',
          style: TextStyle(color: Colors.white38, fontSize: 15),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final r = rows[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161625),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _editingId == r.id ? Colors.amber : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor:
                    r.party == 'سعيد' ? Colors.amber : const Color(0xFF2E6BFF),
                child: Text(
                  r.party.characters.first,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.party} — ${kMonthsAr[r.month - 1]} ${r.year}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (r.note.isNotEmpty)
                      Text(
                        r.note,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                r.amount.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              IconButton(
                onPressed: () => _loadIntoForm(r),
                icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
                tooltip: 'تعديل',
              ),
              IconButton(
                onPressed: () => _delete(r),
                icon: const Icon(Icons.delete,
                    color: Colors.redAccent, size: 20),
                tooltip: 'حذف',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTotals(Map<String, double> totals) {
    if (totals.isEmpty) return const SizedBox.shrink();
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161625),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الإجماليات السنوية',
            style: TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final e in entries) ...[
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      '${e.key.replaceFirst('|', ' — ')}: ${e.value.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- عناصر مساعدة ---------------------------------------------------
  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: const Color(0xFF1B1B2E),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: [
            for (final it in items)
              DropdownMenuItem<T>(value: it, child: Text(labelOf(it))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}