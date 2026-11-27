import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/auth.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'study_room_art.dart';
import 'tour.dart';

typedef _Json = Map<String, dynamic>;

List<_Json> _items(dynamic value) => (value as List).cast<_Json>();

Duration _remaining(_Json room) => DateTime.parse(
  room['endsAt'] as String,
).difference(DateTime.parse(room['serverNow'] as String));

String _clock(Duration time) {
  final seconds = math.max(0, time.inSeconds);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class StudyRoomsPage extends StatefulWidget {
  const StudyRoomsPage({super.key, required this.active});

  final bool active;

  @override
  State<StudyRoomsPage> createState() => _StudyRoomsPageState();
}

class _StudyRoomsPageState extends State<StudyRoomsPage> {
  List<_Json>? _rooms;
  Timer? _poll;
  bool _loading = false, _entering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(covariant StudyRoomsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    _poll?.cancel();
    if (widget.active) _activate();
  }

  void _activate() {
    unawaited(_load());
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_entering) unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final result = await context.read<Api>().get('/study-rooms') as _Json;
      if (mounted) {
        setState(() {
          _rooms = _items(result['items']);
          _error = null;
        });
      }
    } on ApiError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _loading = false;
    }
  }

  Future<void> _open(_Json room) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => _StudySession(room: room)));

  Future<void> _create() async {
    if (_entering) return;
    setState(() => _entering = true);
    try {
      final room = await Navigator.of(context).push<_Json>(
        MaterialPageRoute(builder: (_) => const _CreateStudyRoom()),
      );
      if (mounted && room != null) await _open(room);
    } finally {
      if (mounted) {
        setState(() => _entering = false);
        unawaited(_load());
      }
    }
  }

  Future<void> _join(_Json room) async {
    if (_entering) return;
    setState(() => _entering = true);
    try {
      final avatar = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const _JoinAvatarSheet(),
      );
      if (!mounted || avatar == null) return;
      final joined =
          await context.read<Api>().put(
                '/study-rooms/${room['id']}/member',
                body: {'avatar': avatar},
              )
              as _Json;
      if (mounted) await _open(joined);
    } on ApiError catch (error) {
      if (mounted) toast(context, error.message, error: true);
    } finally {
      if (mounted) {
        setState(() => _entering = false);
        unawaited(_load());
      }
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YaPage(
    title: 'غرف المذاكرة',
    actions: [
      IconButton(
        tooltip: 'تحديث الغرف',
        onPressed: _load,
        icon: const Icon(Icons.refresh_rounded),
      ),
    ],
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              Tour.wrap(
                'study_create',
                GradButton(
                  label: 'إنشاء غرفة',
                  icon: Icons.add_rounded,
                  onPressed: _entering ? null : _create,
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Ya.danger),
                  ),
                ),
              if (_rooms == null && _error == null)
                const Center(child: CircularProgressIndicator())
              else if (_rooms?.isEmpty == true)
                const EmptyState(
                  title: 'مفيش غرف مفتوحة دلوقتي',
                  hint: 'ابدأ جلسة مذاكرة وخلّي زمايلك ينضمّوا لك.',
                ),
              for (final room in _rooms ?? const <_Json>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _RoomCard(
                    room: room,
                    onJoin: _entering ? null : () => _join(room),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.onJoin});

  final _Json room;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    final decor = room['decor'] as String;
    final full =
        room['hasSeat'] != true &&
        (room['memberCount'] as int) >= (room['capacity'] as int);
    final subject = room['subject'] as String?;
    return YaCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 132, child: StudyBackdrop(decor)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room['title'] as String, style: Ya.display(size: 21)),
                Text(
                  [
                    studyDecors[decor] ?? '',
                    ?subject,
                    '${room['memberCount']} / ${room['capacity']} مشاركين',
                    '${_clock(_remaining(room))} متبقي',
                  ].join('  ·  '),
                  style: const TextStyle(color: Ya.muted),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: full ? null : onJoin,
                  icon: const Icon(Icons.login_rounded),
                  label: Text(full ? 'الغرفة ممتلئة' : 'انضم للغرفة'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinAvatarSheet extends StatefulWidget {
  const _JoinAvatarSheet();

  @override
  State<_JoinAvatarSheet> createState() => _JoinAvatarSheetState();
}

class _JoinAvatarSheetState extends State<_JoinAvatarSheet> {
  String? _avatar;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('اختار شخصيتك', style: Ya.display(size: 24)),
          const SizedBox(height: 12),
          StudyAvatarPicker(
            selected: _avatar,
            onSelect: (id) => setState(() => _avatar = id),
          ),
          const SizedBox(height: 18),
          GradButton(
            label: 'ادخل الغرفة',
            onPressed: _avatar == null
                ? null
                : () => Navigator.pop(context, _avatar),
          ),
        ],
      ),
    ),
  );
}

class _CreateStudyRoom extends StatefulWidget {
  const _CreateStudyRoom();

  @override
  State<_CreateStudyRoom> createState() => _CreateStudyRoomState();
}

class _CreateStudyRoomState extends State<_CreateStudyRoom> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _subject = TextEditingController();
  final _duration = TextEditingController(text: '25');
  final _participantCount = TextEditingController(text: '6');
  String _decor = 'library';
  String? _avatar;
  bool _saving = false;

  int? _number(String value) {
    final latin = value.trim().replaceAllMapped(
      RegExp(r'[٠-٩۰-۹]'),
      (match) => (match[0]!.codeUnitAt(0) % 16).toString(),
    );
    return int.tryParse(latin);
  }

  int? get _minutes => _number(_duration.text);
  int? get _capacity => _number(_participantCount.text);
  bool get _validCount =>
      _capacity != null && _capacity! >= 2 && _capacity! <= 12;

  void _countChanged(String value) {
    setState(() {
      final count = _capacity;
      if (_validCount && count! > studyDecorCapacity(_decor)) {
        _decor = 'garden';
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final avatar = _avatar;
    if (avatar == null) {
      toast(context, 'اختار الشخصية اللي هتمثّلك في الغرفة', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final response =
          await context.read<Api>().post(
                '/study-rooms',
                body: {
                  'title': _title.text.trim(),
                  'subject': _subject.text.trim(),
                  'durationMinutes': _minutes,
                  'capacity': _capacity,
                  'decor': _decor,
                  'avatar': avatar,
                },
              )
              as _Json;
      if (mounted) Navigator.pop(context, response);
    } on ApiError catch (error) {
      if (mounted) toast(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _duration.dispose();
    _participantCount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YaPage(
    title: 'إنشاء غرفة مذاكرة',
    back: true,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _title,
                maxLength: 45,
                decoration: const InputDecoration(
                  labelText: 'اسم الغرفة',
                  hintText: 'مثلاً: نذاكر سوا',
                ),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'اكتب اسمًا للغرفة'
                    : null,
              ),
              TextFormField(
                controller: _subject,
                maxLength: 35,
                decoration: const InputDecoration(
                  labelText: 'المادة (اختياري)',
                  hintText: 'مثلاً: رياضيات',
                ),
              ),
              TextFormField(
                controller: _duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'مدة الغرفة بالدقائق',
                ),
                validator: (_) {
                  final minutes = _minutes;
                  return minutes == null || minutes < 5 || minutes > 180
                      ? 'اختار مدة بين ٥ و١٨٠ دقيقة'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _participantCount,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
                  LengthLimitingTextInputFormatter(2),
                ],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'عدد المشاركين (يشملك)',
                  hintText: 'اكتب عددًا من ٢ إلى ١٢',
                ),
                validator: (_) => _validCount ? null : 'اكتب عددًا من ٢ إلى ١٢',
                onChanged: _countChanged,
              ),
              const SizedBox(height: 20),
              Text('اختار المكان', style: Ya.display(size: 21)),
              const SizedBox(height: 8),
              if (!_validCount)
                const Text(
                  'اكتب عدد المشاركين لعرض الأماكن المناسبة.',
                  style: TextStyle(color: Ya.muted),
                ),
              for (final decor in studyDecors.entries.where(
                (entry) =>
                    _validCount && studyDecorCapacity(entry.key) >= _capacity!,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: YaCard(
                    onTap: () => setState(() {
                      _decor = decor.key;
                    }),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 94,
                            height: 58,
                            child: StudyBackdrop(decor.key),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${decor.value} · حتى ${studyDecorCapacity(decor.key)} مشاركين',
                          ),
                        ),
                        Icon(
                          _decor == decor.key
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          color: Ya.teal,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text('اختار شخصيتك', style: Ya.display(size: 21)),
              const SizedBox(height: 8),
              StudyAvatarPicker(
                selected: _avatar,
                onSelect: (id) => setState(() => _avatar = id),
              ),
              const SizedBox(height: 20),
              GradButton(
                label: _saving ? 'جارٍ الإنشاء…' : 'أنشئ الغرفة وادخل',
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _StudySession extends StatefulWidget {
  const _StudySession({required this.room});

  final _Json room;

  @override
  State<_StudySession> createState() => _StudySessionState();
}

class _StudySessionState extends State<_StudySession>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _remainingTime = ValueNotifier<Duration>(Duration.zero);
  final _clockSinceSync = Stopwatch();
  late final AnimationController _chatPulse;
  late final Api _api;
  late _Json _room;
  List<_Json> _members = [], _messages = [];
  Duration _timeAtSync = Duration.zero;
  Timer? _poll, _tick;
  String? _error;
  bool _loading = false, _sending = false, _closed = false;
  bool _chatOpen = false;
  bool _movingSeat = false;
  bool _hasDraft = false;
  Offset _chatButtonOffset = const Offset(18, 18);

  String get _path => '/study-rooms/${_room['id']}';

  @override
  void initState() {
    super.initState();
    _chatPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    unawaited(_restoreChatButtonPosition());
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    _api = context.read<Api>();
    _room = widget.room;
    _syncTime();
    unawaited(_load());
    _poll = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_load()),
    );
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _remainingTime.value = _timeAtSync - _clockSinceSync.elapsed;
      if (_remainingTime.value <= Duration.zero) unawaited(_load());
    });
  }

  void _syncTime() {
    _timeAtSync = _remaining(_room);
    _clockSinceSync
      ..reset()
      ..start();
    _remainingTime.value = _timeAtSync;
  }

  Future<void> _restoreChatButtonPosition() async {
    final preferences = await SharedPreferences.getInstance();
    final right = preferences.getDouble('study_chat_launcher_right');
    final bottom = preferences.getDouble('study_chat_launcher_bottom');
    if (!mounted || right == null || bottom == null) return;
    setState(() => _chatButtonOffset = Offset(right, bottom));
  }

  Future<void> _saveChatButtonPosition() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(
      'study_chat_launcher_right',
      _chatButtonOffset.dx,
    );
    await preferences.setDouble(
      'study_chat_launcher_bottom',
      _chatButtonOffset.dy,
    );
  }

  Future<void> _load() async {
    if (_loading || _closed) return;
    _loading = true;
    try {
      final data = await _api.get('$_path/session') as _Json;
      if (!mounted) return;
      setState(() {
        _room = data['room'] as _Json;
        _members = _items(data['members']);
        _messages = _items(data['messages']);
        _error = null;
      });
      _syncTime();
    } on ApiError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _closed =
            error.status == 410 ||
            error.status == 404 ||
            error.code == 'STUDY_NOT_JOINED';
      });
      if (_closed) {
        _poll?.cancel();
        _tick?.cancel();
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_closed || _sending || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _api.post('$_path/messages', body: {'text': text});
      if (!mounted) return;
      if (_input.text.trim() == text) {
        _input.clear();
        setState(() => _hasDraft = false);
      }
      unawaited(_load());
      _closeChat();
    } on ApiError catch (error) {
      if (mounted) toast(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _moveSeat(int seat) async {
    if (_closed || _movingSeat) return;
    setState(() => _movingSeat = true);
    try {
      await _api.patch('$_path/seat', body: {'seat': seat});
      if (!mounted) return;
      final id = context.read<AuthState>().id;
      setState(() {
        _members = [
          for (final member in _members)
            if (member['userId'] == id) {...member, 'seat': seat} else member,
        ];
      });
      unawaited(_load());
    } on ApiError catch (error) {
      if (mounted) {
        toast(context, error.message, error: true);
        unawaited(_load());
      }
    } finally {
      if (mounted) setState(() => _movingSeat = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _clockSinceSync.stop();
    _chatPulse.dispose();
    _input.dispose();
    _inputFocus.dispose();
    _remainingTime.dispose();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
    unawaited(
      _api.delete('$_path/member').then<void>((_) {}, onError: (Object _) {}),
    );
    super.dispose();
  }

  void _closeChat() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _chatOpen = false);
  }

  void _openChat() {
    setState(() => _chatOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final decor = _room['decor'] as String;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final capacity = _room['capacity'] as int;
    return PopScope(
      canPop: !_chatOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _chatOpen) _closeChat();
      },
      child: Scaffold(
        backgroundColor: Ya.ink,
        resizeToAvoidBottomInset: false,
        body: LayoutBuilder(
          builder: (context, bounds) {
            final space = math.max(0.0, bounds.maxHeight - keyboard);
            final landscape = bounds.maxWidth > bounds.maxHeight;
            final panelHeight = math.min(
              450.0,
              keyboard > 0 ? space : space * .58,
            );
            final floatingPanelHeight = math.min(
              420.0,
              math.max(260.0, bounds.maxHeight * .62),
            );
            final chatOnRight = _chatButtonOffset.dx <= bounds.maxWidth / 2;
            final chatLauncherTop =
                bounds.maxHeight - _chatButtonOffset.dy - 58;
            final openPanelBelowLauncher =
                keyboard == 0 &&
                bounds.maxHeight - (chatLauncherTop + 58) >=
                    floatingPanelHeight + 12;
            final floatingPanelBottom = (_chatButtonOffset.dy + 68)
                .clamp(10.0, bounds.maxHeight - floatingPanelHeight - 10)
                .toDouble();
            final floatingPanelTop = (chatLauncherTop + 68)
                .clamp(10.0, bounds.maxHeight - floatingPanelHeight - 10)
                .toDouble();
            final chatPanelAlignment = openPanelBelowLauncher
                ? (chatOnRight ? Alignment.topRight : Alignment.topLeft)
                : (chatOnRight ? Alignment.bottomRight : Alignment.bottomLeft);
            return Stack(
              fit: StackFit.expand,
              children: [
                _StudyScene(
                  decor: decor,
                  members: _members,
                  messages: _messages,
                  capacity: capacity,
                  onSeat: _closed || _movingSeat ? null : _moveSeat,
                ),
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x92231917),
                          Colors.transparent,
                          Colors.transparent,
                          Color(0x84231917),
                        ],
                        stops: [0, .23, .72, 1],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    minimum: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: _roomHeader(decor),
                  ),
                ),
                if (_chatOpen && landscape)
                  Positioned(
                    right: chatOnRight ? 12 : null,
                    left: chatOnRight ? null : 12,
                    width: math.min(360, bounds.maxWidth * .46),
                    height: keyboard > 0 ? null : floatingPanelHeight,
                    top: keyboard > 0
                        ? 0
                        : openPanelBelowLauncher
                        ? floatingPanelTop
                        : null,
                    bottom: keyboard > 0
                        ? keyboard
                        : openPanelBelowLauncher
                        ? null
                        : floatingPanelBottom,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      tween: Tween(begin: .86, end: 1),
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.scale(
                          alignment: chatPanelAlignment,
                          scale: value,
                          child: child,
                        ),
                      ),
                      child: _chatPanel(),
                    ),
                  )
                else if (_chatOpen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: keyboard,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 620),
                        child: SizedBox(
                          height: panelHeight,
                          child: _chatPanel(),
                        ),
                      ),
                    ),
                  )
                else ...[
                  PositionedDirectional(
                    start: 16,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: Ya.dangerBg,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(color: Ya.danger),
                                  ),
                                ),
                              ),
                            ),
                          Chip(
                            avatar: const Icon(
                              Icons.people_alt_outlined,
                              size: 18,
                            ),
                            label: Text('${_members.length} / $capacity'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _draggableChatButton(bounds),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _draggableChatButton(BoxConstraints bounds) {
    final maxRight = math.max(12.0, bounds.maxWidth - 155);
    final maxBottom = math.max(12.0, bounds.maxHeight - 92);
    final right = _chatButtonOffset.dx.clamp(12.0, maxRight).toDouble();
    final bottom = _chatButtonOffset.dy.clamp(12.0, maxBottom).toDouble();
    return Positioned(
      right: right,
      bottom: bottom,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _chatButtonOffset = Offset(
              (_chatButtonOffset.dx - details.delta.dx)
                  .clamp(12.0, maxRight)
                  .toDouble(),
              (_chatButtonOffset.dy - details.delta.dy)
                  .clamp(12.0, maxBottom)
                  .toDouble(),
            );
          });
        },
        onPanEnd: (_) => unawaited(_saveChatButtonPosition()),
        child: _floatingChatButton(),
      ),
    );
  }

  Widget _floatingChatButton() => Semantics(
    label: 'فتح دردشة الغرفة',
    button: true,
    child: AnimatedBuilder(
      animation: _chatPulse,
      builder: (context, child) {
        final lift = Curves.easeInOut.transform(_chatPulse.value);
        return Transform.translate(
          offset: Offset(0, -3 * lift),
          child: Transform.scale(scale: 1 + (.035 * lift), child: child),
        );
      },
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        elevation: 10,
        shadowColor: const Color(0x80000000),
        child: Ink(
          decoration: BoxDecoration(
            gradient: Ya.btnGradient,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x662A8F8B),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: InkWell(
            onTap: _openChat,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 58,
              height: 58,
              child: Icon(Icons.chat_bubble_rounded, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _roomHeader(String decor) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      IconButton.filledTonal(
        tooltip: 'خروج من الغرفة',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_forward_rounded),
      ),
      const Spacer(),
      ValueListenableBuilder(
        valueListenable: _remainingTime,
        builder: (_, value, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xE51B3836),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0x66E9C37A)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x35000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_bottom_rounded,
                color: Color(0xFFE9C37A),
                size: 20,
              ),
              const SizedBox(width: 9),
              Text(
                _clock(value),
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget _chatPanel() {
    final me = context.read<AuthState>().id;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact = keyboardVisible;
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(26),
      elevation: 12,
      child: Column(
        children: [
          Container(
            padding: EdgeInsetsDirectional.fromSTEB(
              12,
              compact ? 5 : 9,
              5,
              compact ? 5 : 9,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Ya.tealLight, Ya.teal]),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: compact ? 15 : 18,
                  backgroundColor: Color(0x33FFFFFF),
                  child: Icon(Icons.groups_rounded, color: Colors.white),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'دردشة الغرفة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 1),
                        const Text(
                          'محادثة مباشرة مع الموجودين',
                          style: TextStyle(
                            color: Color(0xDFFFFFFF),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'إخفاء الدردشة',
                  onPressed: _closeChat,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  constraints: BoxConstraints.tightFor(
                    width: compact ? 40 : 48,
                    height: compact ? 40 : 48,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Ya.danger)),
            ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'ابدأ الكلام مع زمايلك',
                      style: TextStyle(color: Ya.muted),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      12,
                      10,
                      12,
                      8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      final message = _messages[_messages.length - index - 1];
                      final mine = message['senderId'] == me;
                      return Align(
                        key: ValueKey(message['id']),
                        alignment: mine
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.centerStart,
                        child: _chatMessage(message, mine),
                      );
                    },
                  ),
          ),
          if (!_closed)
            Padding(
              padding: EdgeInsets.fromLTRB(
                10,
                compact ? 2 : 4,
                10,
                compact ? 3 : 8,
              ),
              child: Container(
                padding: EdgeInsetsDirectional.fromSTEB(
                  6,
                  compact ? 4 : 8,
                  4,
                  compact ? 4 : 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(
                    top: BorderSide(color: Color(0xFFE7EAF0)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F2F5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _input,
                          focusNode: _inputFocus,
                          minLines: 1,
                          maxLines: compact ? 1 : 3,
                          maxLength: 500,
                          textCapitalization: TextCapitalization.sentences,
                          autocorrect: true,
                          enableSuggestions: true,
                          textInputAction: TextInputAction.newline,
                          onChanged: (value) {
                            final hasDraft = value.trim().isNotEmpty;
                            if (hasDraft != _hasDraft) {
                              setState(() => _hasDraft = hasDraft);
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'اكتب رسالة…',
                            counterText: '',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: compact ? 7 : 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      label: 'إرسال الرسالة',
                      button: true,
                      child: Material(
                        color: _hasDraft && !_sending
                            ? Ya.teal
                            : const Color(0xFFE1E5EB),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'إرسال',
                          onPressed: _hasDraft && !_sending ? _send : null,
                          icon: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chatMessage(_Json message, bool mine) {
    final createdAt = DateTime.tryParse(
      '${message['createdAt'] ?? ''}',
    )?.toLocal();
    final avatar = '${message['avatar'] ?? ''}';
    final accent = switch (avatar) {
      'berry' || 'coral' => const Color(0xFFE8899B),
      'amber' => Ya.gold,
      'ocean' || 'indigo' => const Color(0xFF558CCB),
      'plum' => const Color(0xFF8864A8),
      'olive' => const Color(0xFF738D59),
      _ => Ya.teal,
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 12, 9),
      decoration: BoxDecoration(
        color: mine ? Ya.teal : const Color(0xFFF0F2F5),
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(19),
          topEnd: const Radius.circular(19),
          bottomStart: Radius.circular(mine ? 19 : 5),
          bottomEnd: Radius.circular(mine ? 5 : 19),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine) ...[
                CircleAvatar(
                  radius: 10,
                  backgroundColor: accent.withValues(alpha: .18),
                  child: Icon(Icons.face_rounded, size: 14, color: accent),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                mine ? 'أنت' : '${message['name'] ?? ''}',
                style: TextStyle(
                  color: mine ? Colors.white : Ya.strong,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              if (createdAt != null) ...[
                const SizedBox(width: 7),
                Text(
                  ftime(createdAt),
                  style: TextStyle(
                    color: mine ? const Color(0xDFFFFFFF) : Ya.muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${message['text'] ?? ''}',
            style: TextStyle(
              color: mine ? Colors.white : Ya.strong,
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyScene extends StatefulWidget {
  const _StudyScene({
    required this.decor,
    required this.members,
    required this.messages,
    required this.capacity,
    required this.onSeat,
  });

  final String decor;
  final List<_Json> members;
  final List<_Json> messages;
  final int capacity;
  final ValueChanged<int>? onSeat;

  @override
  State<_StudyScene> createState() => _StudySceneState();
}

class _StudySceneState extends State<_StudyScene>
    with SingleTickerProviderStateMixin {
  final _speech = <String, ({String text, DateTime until})>{};
  Timer? _speechExpiry;

  @override
  void didUpdateWidget(covariant _StudyScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final known = oldWidget.messages.map((message) => message['id']).toSet();
    for (final message in widget.messages) {
      final created = DateTime.tryParse(message['createdAt'] as String? ?? '');
      if (!known.contains(message['id']) &&
          created != null &&
          DateTime.now().difference(created).inSeconds < 15) {
        _speech[message['senderId'] as String] = (
          text: message['text'] as String,
          until: DateTime.now().add(const Duration(seconds: 10)),
        );
      }
    }
    if (_speech.isNotEmpty && _speechExpiry == null) {
      _speechExpiry = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(
          () => _speech.removeWhere(
            (_, value) => value.until.isBefore(DateTime.now()),
          ),
        );
        if (_speech.isEmpty) {
          _speechExpiry?.cancel();
          _speechExpiry = null;
        }
      });
    }
  }

  // Hip and notebook coordinates use the same 724px canvas as each decor.
  static const _layout = {
    'library': [
      (Offset(190, 397), Offset(249, 414)),
      (Offset(532, 398), Offset(480, 414)),
      (Offset(158, 441), Offset(228, 458)),
      (Offset(562, 442), Offset(500, 458)),
      (Offset(128, 500), Offset(207, 514)),
      (Offset(599, 500), Offset(527, 515)),
      (Offset(212, 363), Offset(262, 376)),
      (Offset(510, 364), Offset(464, 377)),
    ],
    'rooftop': [
      (Offset(193, 398), Offset(245, 414)),
      (Offset(535, 398), Offset(484, 414)),
      (Offset(162, 441), Offset(224, 458)),
      (Offset(569, 442), Offset(508, 459)),
      (Offset(129, 500), Offset(202, 515)),
      (Offset(603, 500), Offset(529, 515)),
      (Offset(218, 364), Offset(261, 376)),
      (Offset(511, 364), Offset(472, 376)),
    ],
    'ocean': [
      (Offset(200, 397), Offset(256, 414)),
      (Offset(545, 397), Offset(497, 414)),
      (Offset(170, 441), Offset(240, 458)),
      (Offset(578, 442), Offset(514, 460)),
      (Offset(143, 500), Offset(219, 515)),
      (Offset(614, 500), Offset(535, 516)),
      (Offset(224, 362), Offset(269, 376)),
      (Offset(516, 363), Offset(481, 376)),
    ],
  };

  List<(Offset, Offset)> get _seats {
    if (studyDecorCapacity(widget.decor) == 12) {
      if (widget.decor == 'garden') {
        return const [
          (Offset(216, 275), Offset(280, 267)),
          (Offset(508, 275), Offset(441, 267)),
          (Offset(204, 329), Offset(275, 317)),
          (Offset(520, 329), Offset(446, 317)),
          (Offset(194, 385), Offset(271, 375)),
          (Offset(531, 385), Offset(454, 375)),
          (Offset(181, 446), Offset(266, 443)),
          (Offset(544, 446), Offset(459, 443)),
          (Offset(171, 513), Offset(260, 512)),
          (Offset(555, 513), Offset(465, 512)),
          (Offset(159, 583), Offset(252, 587)),
          (Offset(566, 583), Offset(472, 587)),
        ];
      }
      return [
        for (var row = 0; row < 6; row++) ...[
          (
            Offset(200 - row * 9, 269 + row * 55),
            Offset(258 - row * 4, 256 + row * 55),
          ),
          (
            Offset(524 + row * 9, 269 + row * 55),
            Offset(466 + row * 4, 256 + row * 55),
          ),
        ],
      ];
    }
    return _layout[widget.decor] ?? _layout['library']!;
  }

  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );
  bool _animate = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate = !MediaQuery.disableAnimationsOf(context);
    if (_animate && !_motion.isAnimating) {
      _motion.repeat();
    } else if (!_animate && _motion.isAnimating) {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _speechExpiry?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: FittedBox(
      fit: BoxFit.cover,
      alignment: const Alignment(0, -.75),
      child: SizedBox(
        width: 1086,
        height: 724,
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox.square(
            dimension: 724,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StudyBackdrop(widget.decor),
                for (
                  var seat = 0;
                  seat < studyDecorCapacity(widget.decor);
                  seat++
                )
                  if (!widget.members.any((member) => member['seat'] == seat))
                    Positioned(
                      left: _seats[seat].$1.dx - 22,
                      top: _seats[seat].$1.dy - 23,
                      width: 44,
                      height: 44,
                      child: Semantics(
                        label: 'الانتقال للكرسي ${seat + 1}',
                        button: true,
                        child: Tooltip(
                          message: 'اقعد هنا',
                          child: Material(
                            color: Colors.white.withValues(alpha: .24),
                            shape: const CircleBorder(
                              side: BorderSide(color: Color(0xBFFFFFFF)),
                            ),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onSeat == null
                                  ? null
                                  : () => widget.onSeat!(seat),
                              child: const Icon(
                                Icons.event_seat_outlined,
                                size: 21,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                if (_animate)
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: StudyRoomAtmosphere(widget.decor, _motion),
                      ),
                    ),
                  ),
                for (
                  var index = 0;
                  index < studyDecorCapacity(widget.decor);
                  index++
                )
                  for (final member in widget.members.where(
                    (person) => person['seat'] == index,
                  ))
                    _person(member),
                for (final member in widget.members)
                  if (_speech[member['userId']] != null) _memberOverlay(member),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _person(_Json member) {
    final seat = member['seat'] as int;
    final isRight = seat.isOdd;
    final (position, notebook) = _seats[seat];
    final size = studyDecorCapacity(widget.decor) == 12 ? 64.0 : 85.0;
    final unit = size / 64;
    const hip = Offset(30, 57);
    final writingPage = Offset(
      hip.dx + (notebook.dx - position.dx).abs() / unit,
      hip.dy + (notebook.dy - position.dy) / unit,
    );
    final avatarWidth = math.max(size * 1.65, (writingPage.dx + 12) * unit);
    return AnimatedPositioned(
      key: ValueKey(member['userId']),
      duration: _animate ? const Duration(milliseconds: 850) : Duration.zero,
      curve: Curves.easeInOutCubic,
      left:
          position.dx - (isRight ? avatarWidth - hip.dx * unit : hip.dx * unit),
      top: position.dy - hip.dy * unit,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: _animate ? 0 : 1, end: 1),
        duration: _animate ? const Duration(milliseconds: 1100) : Duration.zero,
        builder: (_, progress, _) {
          final remaining = 1 - Curves.easeOutCubic.transform(progress);
          final step = math.sin(progress * math.pi * 7).abs() * remaining;
          return Opacity(
            opacity: math.min(1, progress * 3 + .18),
            child: Transform.translate(
              offset: Offset(
                (isRight ? 94 : -94) * remaining,
                42 * remaining - 7 * step,
              ),
              child: SizedBox(
                width: avatarWidth,
                height: size * 1.34,
                child: Stack(
                  children: [
                    IgnorePointer(
                      child: StudyAvatar(
                        member['avatar'] as String,
                        facesLeft: isRight,
                        size: size,
                        motion: _animate ? _motion : null,
                        seat: seat,
                        arrival: progress,
                        writingPage: writingPage,
                      ),
                    ),
                    Positioned(
                      left: isRight ? avatarWidth - 54 * unit : 6 * unit,
                      top: 2 * unit,
                      width: 48 * unit,
                      height: 40 * unit,
                      child: Tooltip(
                        message:
                            (member['accountName'] ?? member['name']) as String,
                        triggerMode: TooltipTriggerMode.tap,
                        preferBelow: false,
                        verticalOffset: 12,
                        showDuration: const Duration(seconds: 4),
                        child: Semantics(
                          label: 'إظهار اسم ${member['name']}',
                          button: true,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _memberOverlay(_Json member) {
    final seat = member['seat'] as int;
    final position = _seats[seat].$1;
    final speech = _speech[member['userId']];
    final compact = studyDecorCapacity(widget.decor) == 12;
    final width = compact ? 108.0 : 132.0;
    final size = compact ? 64.0 : 85.0;
    final center = position.dx + (seat.isOdd ? 12 : -12) * size / 64;
    final name = (member['accountName'] ?? member['name'] ?? '') as String;
    return AnimatedPositioned(
      key: ValueKey('label-${member['userId']}'),
      duration: _animate ? const Duration(milliseconds: 850) : Duration.zero,
      curve: Curves.easeInOutCubic,
      left: (center - width / 2).clamp(6.0, 718.0 - width),
      bottom: 724 - (position.dy - 57 * size / 64 - 4),
      width: width,
      child: AnimatedSize(
        duration: _animate ? const Duration(milliseconds: 220) : Duration.zero,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (speech != null) ...[
              Material(
                color: Colors.white,
                elevation: 5,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(3),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(name),
                      content: SingleChildScrollView(child: Text(speech.text)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إغلاق'),
                        ),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Text(
                      speech.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Ya.ink,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
