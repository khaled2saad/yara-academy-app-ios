import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/sheet.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class TeacherAccountingPage extends StatefulWidget {
  const TeacherAccountingPage({super.key, this.teacherId, this.teacherName, this.initialPeriod, this.initialArchived = false});
  final String? teacherId;
  final String? teacherName;
  final DateTimeRange? initialPeriod;
  final bool initialArchived;

  @override
  State<TeacherAccountingPage> createState() => _TeacherAccountingPageState();
}

class _TeacherAccountingPageState extends State<TeacherAccountingPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  int _unassigned = 0;
  String _query = '';
  bool _unpaidOnly = true;
  bool _saving = false;
  DateTimeRange? _period;
  int _loadVersion = 0;
  bool _archived = false;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    _archived = widget.initialArchived;
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    final period = _period;
    try {
      final response = await context.read<Api>().get('/sessions/accounting', query: {
        if (period != null) 'from': _date(period.start),
        if (period != null) 'to': _date(period.end),
        'tz': 'Africa/Cairo',
      });
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _items = (response['items'] as List).cast<Map<String, dynamic>>()
          .where((row) => widget.teacherId == null || row['teacher']['id'] == widget.teacherId).toList();
        _unassigned = widget.teacherId == null ? response['unassigned'] as int : 0;
        _loading = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted && version == _loadVersion) setState(() { _loading = false; _error = e.message; });
    }
  }

  String _date(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String _displayDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  Future<void> _pickPeriod() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context, firstDate: DateTime(2000), lastDate: now,
      initialDateRange: _period ?? DateTimeRange(start: DateTime(now.year, now.month), end: now),
      helpText: 'اختر بداية الفترة ونهايتها', saveText: 'عرض التقرير',
    );
    if (range == null || !mounted) return;
    setState(() { _period = range; _loading = true; });
    await _load();
  }

  Future<void> _clearPeriod() async {
    setState(() { _period = null; _loading = true; });
    await _load();
  }

  Future<void> _pay(Map<String, dynamic> row) async {
    if (_period != null) return;
    final api = context.read<Api>();
    final remaining = row['remaining'] as int;
    final count = TextEditingController(text: '$remaining');
    bool busy = false;
    String? error;
    final saved = await showYaSheet<bool>(context, (sheetContext) => StatefulBuilder(builder: (c, set) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('تسجيل دفعة حصص', style: Ya.display(size: 25)),
        const SizedBox(height: 8),
        Text('${row['teacher']['fullName']} · ${row['course']['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('المتبقي بدون دفع: $remaining حصة', style: const TextStyle(color: Ya.muted)),
        Field('عدد الحصص المدفوعة في هذه الدفعة', child: TextField(
          controller: count, keyboardType: TextInputType.number, enabled: !busy,
          decoration: InputDecoration(hintText: 'من 1 إلى $remaining', errorText: error),
        )),
        const SizedBox(height: 10),
        const Text('التسجيل يثبت دفع مقابل الحصص، ولا ينفّذ تحويلًا ماليًا.', style: TextStyle(color: Ya.muted, fontSize: 12.5)),
        const SizedBox(height: 16),
        GradButton(label: 'تأكيد تسجيل الدفعة', busy: busy, onPressed: busy ? null : () async {
          var text = count.text.trim();
          const arabic = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
          for (var i = 0; i < 10; i++) {
            text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
          }
          final value = int.tryParse(text);
          if (value == null || value < 1 || value > remaining) {
            set(() => error = 'اكتب عددًا من 1 إلى $remaining');
            return;
          }
          set(() { busy = true; error = null; });
          try {
            await api.post('/sessions/accounting/pay', body: {
              'teacherId': row['teacher']['id'], 'courseId': row['course']['id'], 'count': value,
            });
            if (c.mounted) Navigator.pop(c, true);
          } on ApiError catch (e) {
            if (c.mounted) set(() { busy = false; error = e.message; });
          }
        }),
      ]);
    }));
    // The closing sheet animates before releasing its text field.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    count.dispose();
    if (saved == true && mounted) {
      toast(context, 'تم تسجيل الدفعة');
      await _load();
    }
  }

  Widget _stat(int value, String label, Color color) => Expanded(child: Column(children: [
    Text('$value', style: Ya.display(size: 27, color: color)),
    Text(label, style: const TextStyle(color: Ya.muted, fontSize: 12.5)),
  ]));

  Future<void> _openTeacher(Map<String, dynamic> teacher) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TeacherAccountingPage(
      teacherId: teacher['id'] as String, teacherName: teacher['fullName'] as String,
      initialPeriod: _period,
      initialArchived: _archived,
    )));
    if (mounted) await _load();
  }

  Future<void> _payAll(Map<String, dynamic> teacher, int remaining) async {
    if (_saving || _period != null) return;
    final sure = await askConfirm(context, 'تسجيل دفع كل الحصص؟', ok: 'تأكيد الدفع',
      body: '${teacher['fullName']}\n$remaining حصة في جميع كورساتها.\nسجّلها بعد دفع مقابلها للمعلمة.');
    if (!sure || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<Api>().post('/sessions/accounting/pay', body: {
        'teacherId': teacher['id'], 'count': remaining, 'all': true,
      });
      if (mounted) toast(context, 'تم تسجيل دفع $remaining حصة');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        await _load();
      }
    }
  }

  Future<void> _archiveCourse(Map<String, dynamic> row) async {
    if (_saving || _period != null) return;
    final restore = row['archivedAt'] != null;
    final sure = await askConfirm(context, restore ? 'إرجاع الكورس للقائمة الحالية؟' : 'إقفال وإخفاء حساب الكورس؟',
      ok: restore ? 'إرجاع الكورس' : 'إقفال الكورس',
      body: '${row['course']['title']}\n${restore ? 'سيظهر من جديد في حساب المعلمة.' : 'سينتقل إلى المقفلة، مع بقاء سجل الحصص والدفعات محفوظًا.'}');
    if (!sure || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<Api>().post('/sessions/accounting/archive', body: {
        'teacherId': row['teacher']['id'], 'courseId': row['course']['id'], 'archive': !restore,
      });
      if (mounted) toast(context, restore ? 'تم إرجاع الكورس' : 'تم نقل الكورس إلى المقفلة');
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final individual = widget.teacherId != null;
    final items = _items.where((row) => _period != null || (row['archivedAt'] != null) == _archived).toList();
    final courses = items.where((row) => '${row['course']['title']}'.contains(_query)).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in items) {
      groups.putIfAbsent(row['teacher']['id'] as String, () => []).add(row);
    }
    final teachers = groups.values.where((rows) =>
      (!_unpaidOnly || _archived || rows.any((row) => (row['remaining'] as int) > 0)) &&
      rows.any((row) => '${row['teacher']['fullName']} ${row['course']['title']}'.contains(_query))).toList();
    final completed = items.fold<int>(0, (sum, row) => sum + (row['completed'] as int));
    final paid = items.fold<int>(0, (sum, row) => sum + (row['paid'] as int));
    return YaPage(
      title: individual ? widget.teacherName ?? 'حساب المعلمة' : 'حساب الحصص',
      subtitle: individual ? 'كل كورس · المنجز والمدفوع والمتبقي للدفع' : 'اختار المعلمة لعرض كورساتها', back: true,
      actions: [IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      child: _loading ? const Center(child: CircularProgressIndicator(color: Ya.teal))
        : _error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('إعادة المحاولة'))]))
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
          YaCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.date_range_rounded, color: Ya.teal),
              const SizedBox(width: 8),
              Expanded(child: Text(_period == null ? 'الحساب الحالي · كل التواريخ' : 'من ${_displayDate(_period!.start)} إلى ${_displayDate(_period!.end)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              TextButton(onPressed: _pickPeriod, child: Text(_period == null ? 'اختيار فترة' : 'تغيير')),
            ]),
            if (_period != null) ...[
              const Text('حصص الفترة المختارة · المدفوع والمتبقي حتى نهاية آخر يوم، بتوقيت مصر.', style: TextStyle(fontSize: 12, color: Ya.muted, height: 1.5)),
              TextButton(onPressed: _clearPeriod, child: const Text('عرض الحساب الحالي وتسجيل دفعة')),
            ],
          ])),
          const SizedBox(height: 14),
          if (_period == null) ...[
            Row(children: [
              Expanded(child: FilterPill('الحالية', selected: !_archived, onTap: () => setState(() => _archived = false))),
              const SizedBox(width: 8),
              Expanded(child: FilterPill('المقفلة', selected: _archived, onTap: () => setState(() => _archived = true))),
            ]),
            const SizedBox(height: 14),
          ],
          YaCard(child: Row(children: [_stat(completed, 'المنجز', Ya.strong), _stat(paid, 'المدفوع', Ya.teal), _stat(completed - paid, 'متبقي للدفع', Ya.gold)])),
          const SizedBox(height: 14),
          if (!individual && !_archived) ...[
          Row(children: [
            Expanded(child: FilterPill('عليهم مستحقات', selected: _unpaidOnly, onTap: () => setState(() => _unpaidOnly = true))),
            const SizedBox(width: 8),
            Expanded(child: FilterPill('كل المعلمات', selected: !_unpaidOnly, onTap: () => setState(() => _unpaidOnly = false))),
          ]),
          const SizedBox(height: 14),
          ],
          TextField(onChanged: (value) => setState(() => _query = value.trim()), decoration: InputDecoration(hintText: individual ? 'ابحث باسم الكورس' : 'ابحث باسم المعلمة أو الكورس', prefixIcon: const Icon(Icons.search_rounded))),
          const SizedBox(height: 14),
          if (_unassigned > 0) ...[
            YaCard(edge: Ya.gold, child: Text('توجد $_unassigned حصة قديمة بدون معلمة محددة، غير مضافة لحساب أي معلمة.', style: const TextStyle(color: Ya.muted, height: 1.6))),
            const SizedBox(height: 12),
          ],
          if (individual) ...[
            if (courses.isEmpty) EmptyState(title: _archived && _period == null ? 'لا توجد كورسات مقفلة' : 'لا توجد كورسات', hint: 'يمكنك التنقل بين الحالية والمقفلة لمراجعة حساب المعلمة.'),
            for (final row in courses) _courseCard(row),
          ] else ...[
            if (teachers.isEmpty) EmptyState(title: _query.isNotEmpty ? 'لا توجد نتائج' : _archived ? 'لا توجد حسابات مقفلة' : _unpaidOnly ? 'الحسابات خالصة' : 'لا توجد حسابات', hint: _unpaidOnly && !_archived ? 'اعرض كل المعلمات لمراجعة الحسابات.' : 'تظهر هنا حسابات الكورسات الخاصة بكل معلمة.'),
            for (final rows in teachers) _teacherCard(rows),
          ],
        ])),
    );
  }

  Widget _teacherCard(List<Map<String, dynamic>> rows) {
    final teacher = rows.first['teacher'] as Map<String, dynamic>;
    final completed = rows.fold<int>(0, (sum, row) => sum + (row['completed'] as int));
    final paid = rows.fold<int>(0, (sum, row) => sum + (row['paid'] as int));
    final remaining = completed - paid;
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: YaCard(onTap: () => _openTeacher(teacher), edge: remaining > 0 ? Ya.gold : Ya.teal, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const CircleAvatar(backgroundColor: Ya.soft, child: Icon(Icons.school_outlined, color: Ya.teal)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${teacher['fullName']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text('${rows.length} كورس', style: const TextStyle(color: Ya.muted, fontSize: 13)),
              ])),
            ]),
            const SizedBox(height: 16),
            Row(children: [_stat(completed, 'أنجزت', Ya.strong), _stat(paid, 'مدفوع', Ya.teal), _stat(remaining, 'باقي للدفع', Ya.gold)]),
            const SizedBox(height: 16),
            if (remaining > 0 && _period == null)
              GradButton(label: 'تسجيل دفع الكل · $remaining حصة', height: 44, icon: Icons.done_all_rounded, onPressed: _saving ? null : () => _payAll(teacher, remaining))
            else if (remaining == 0) const Center(child: Text('✓ كل الحصص مدفوعة', style: TextStyle(color: Ya.teal, fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: () => _openTeacher(teacher), icon: const Icon(Icons.menu_book_outlined), label: const Text('عرض كورسات المعلمة')),
          ])));
  }

  Widget _courseCard(Map<String, dynamic> row) {
    final remaining = row['remaining'] as int;
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: YaCard(
      edge: remaining > 0 ? Ya.gold : Ya.teal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const CircleAvatar(backgroundColor: Ya.soft, child: Icon(Icons.menu_book_outlined, color: Ya.teal)),
          const SizedBox(width: 10),
          Expanded(child: Text('${row['course']['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
          if (row['archivedAt'] != null) const Pill('مقفل', bg: Ya.soft, fg: Ya.teal),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          _stat(row['completed'] as int, 'أنجزت', Ya.strong),
          _stat(row['paid'] as int, 'اتحاسبت على', Ya.teal),
          _stat(remaining, 'متبقي للدفع', Ya.gold),
        ]),
        const SizedBox(height: 8),
        const Text('الأعداد بالحصص', textAlign: TextAlign.center, style: TextStyle(color: Ya.muted, fontSize: 12)),
        const SizedBox(height: 14),
        if (remaining > 0 && _period == null)
          GradButton(label: 'تسجيل دفع لهذا الكورس', height: 44, icon: Icons.payments_outlined, onPressed: _saving ? null : () => _pay(row))
        else if (remaining > 0) Text('متبقي $remaining حصة حتى ${_displayDate(_period!.end)}', textAlign: TextAlign.center, style: const TextStyle(color: Ya.warn, fontWeight: FontWeight.w700))
        else const Center(child: Text('✓ لا توجد حصص متبقية للدفع', style: TextStyle(color: Ya.teal, fontWeight: FontWeight.w700))),
        if (_period == null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving || (remaining > 0 && row['archivedAt'] == null) ? null : () => _archiveCourse(row),
            icon: Icon(row['archivedAt'] == null ? Icons.archive_outlined : Icons.unarchive_outlined),
            label: Text(row['archivedAt'] == null ? 'إقفال وإخفاء الكورس' : 'إرجاع للقائمة الحالية'),
          ),
          if (remaining > 0 && row['archivedAt'] == null) const Text('متاح الإقفال بعد سداد كل الحصص', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Ya.muted)),
        ],
      ]),
    ));
  }
}
