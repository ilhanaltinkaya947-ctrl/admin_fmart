import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../stores/data/stores_repository.dart';
import '../../stores/models/store_models.dart';
import '../data/banner_action_draft.dart';
import '../data/banner_models.dart';
import '../data/banners_repository.dart';
import '../state/banners_cubit.dart';
import 'widgets/banner_app_preview.dart';
import 'widgets/banner_info_editor.dart';
import 'widgets/banner_target_editor.dart';

/// Create or edit a single banner.
///
/// On Save: validates form fields, sends multipart to backend. The backend
/// also enforces dimensions/ratio (1.5–1.7) and returns 400 with a Russian
/// message if the image is wrong size — that surfaces here as a snackbar
/// without crashing.
///
/// 08.11 banner actions: what a tap opens (product, collection, category,
/// «Акции», search, an info page, the seasonal shelf), the badge, stores,
/// daily hours, the new-builds-only switch, «Проверить» per shop and a
/// preview of the slide and the info page as the customer app draws them.
/// Every refusal is the server's own plain sentence.
/// The first customer build that opens banner actions (2.0.9+265).
const int kBannerActionsMinBuild = 265;

class BannerEditPage extends StatefulWidget {
  final BannerItem? banner;
  const BannerEditPage({super.key, this.banner});

  @override
  State<BannerEditPage> createState() => _BannerEditPageState();
}

class _BannerEditPageState extends State<BannerEditPage> {
  final _titleCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _badgeRuCtrl = TextEditingController();
  final _badgeKkCtrl = TextEditingController();
  bool _active = true;
  File? _pickedImage;
  bool _saving = false;
  // Set on the first Save tap, before the action check and its dialog, so a
  // second tap cannot start a second save (critic 1.2.9 HIGH-1).
  bool _busy = false;
  DateTime? _startsAt;
  DateTime? _endsAt;
  // Tracked separately from the value so "clear an existing date" is
  // expressible: null + touched means delete it, null + untouched means
  // "was never set, send nothing".
  bool _startsCleared = false;
  bool _endsCleared = false;

  // 08.11 banner actions.
  late BannerActionDraft _action;
  bool _actionDirty = false;
  final Set<int> _stores = {};
  List<StoreDto> _allStores = const [];
  TimeOfDay? _dailyFrom;
  TimeOfDay? _dailyTo;
  bool _onlyNew = false;
  bool _onlyNewTouched = false;
  bool _checking = false;
  BannerCheckResult? _check;
  String? _checkError;
  int _checkGen = 0;
  bool _storesFailed = false;

  /// What the form held when it opened; leaving with anything else asks.
  late String _initialSnapshot;
  bool _leaving = false;

  BannersRepository get _repo => context.read<BannersCubit>().repo;

  @override
  void initState() {
    super.initState();
    final b = widget.banner;
    if (b != null) {
      _titleCtrl.text = b.title ?? '';
      // Shown 1-based to match the list row. Stored 0-based.
      _positionCtrl.text = '${b.sortOrder + 1}';
      _active = b.active;
      _startsAt = b.startsAt;
      _endsAt = b.endsAt;
      _badgeRuCtrl.text = b.badgeRu ?? '';
      _badgeKkCtrl.text = b.badgeKk ?? '';
      _stores.addAll(b.storeIds);
      _dailyFrom = _tod(b.dailyFrom);
      _dailyTo = _tod(b.dailyTo);
      _onlyNew = b.minAppBuild != null;
      // A banner that already has an action keeps its own choice; a plain
      // one that GAINS an action gets the new-builds default (contract §3).
      _onlyNewTouched = b.minAppBuild != null || b.actionKind != BannerActionKind.none;
      _action = BannerActionDraft.fromJson(b.actionType, b.action);
      _loadNames();
    } else {
      _action = BannerActionDraft();
      _actionDirty = true;
    }
    _loadStores();
    _initialSnapshot = _snapshot();
  }

  void _loadStores() {
    try {
      context.read<StoresRepository>().getStores().then((s) {
        if (mounted) setState(() {
          _allStores = s;
          _storesFailed = false;
        });
      }).catchError((_) {
        if (mounted) setState(() => _storesFailed = true);
      });
    } catch (_) {/* no stores repository above (tests) */}
  }

  /// A reopened banner knows its products and category by number only:
  /// fetch their names so the lists read as names.
  Future<void> _loadNames() async {
    final targets = [_action.target, _action.info.cta];
    final ids = {for (final t in targets) ...t.productIds()}.toList();
    try {
      if (ids.isNotEmpty) {
        final names = await _repo.productNames(ids);
        final m = {for (final e in names.entries) e.key: (name: e.value.name, image: e.value.imageUrl)};
        for (final t in targets) {
          t.applyNames(m);
        }
      }
      if (targets.any((t) => t.kind == BannerActionKind.category && t.categoryId != null && t.categoryName.isEmpty)) {
        final cats = {for (final c in await _repo.categories()) c.id: c.name};
        for (final t in targets) {
          if (t.categoryId != null && t.categoryName.isEmpty) t.categoryName = cats[t.categoryId] ?? '';
        }
      }
    } catch (_) {/* numbers stay; nothing is lost */}
    if (mounted) setState(() {});
  }

  /// Everything the save would send, as one string (leave-without-saving).
  String _snapshot() => [
        _titleCtrl.text,
        _positionCtrl.text,
        _badgeRuCtrl.text,
        _badgeKkCtrl.text,
        _active,
        _startsAt,
        _endsAt,
        _startsCleared,
        _endsCleared,
        ([..._stores]..sort()).join(','),
        _hhmm(_dailyFrom),
        _hhmm(_dailyTo),
        _onlyNew,
        _pickedImage?.path,
        _action.kind.wire,
        _action.payload().toString(),
      ].join('|');

  Future<void> _maybeLeave() async {
    // A save in flight still lands: «Изменения пропадут» would be untrue.
    if (_busy) {
      _error('Идёт сохранение, подождите');
      return;
    }
    if (_snapshot() == _initialSnapshot) {
      _leaving = true;
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Выйти без сохранения?'),
        content: const Text('Изменения пропадут.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Остаться')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Выйти')),
        ],
      ),
    );
    if (leave == true && mounted) {
      _leaving = true;
      Navigator.of(context).pop();
    }
  }

  static TimeOfDay? _tod(String? hhmm) {
    if (hhmm == null) return null;
    final p = hhmm.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return (h == null || m == null) ? null : TimeOfDay(hour: h, minute: m);
  }

  static String? _hhmm(TimeOfDay? t) =>
      t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final c in [_titleCtrl, _positionCtrl, _badgeRuCtrl, _badgeKkCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _actionChanged() {
    if (!mounted) return;
    setState(() {
      _actionDirty = true;
      _check = null;
      _checkError = null;
      // A banner that opens something should not reach builds that cannot
      // open it (they would show it as a dead picture). On by default.
      if (!_onlyNewTouched) _onlyNew = _action.kind != BannerActionKind.none;
    });
  }

  /// «Проверить»: the server's per-shop availability. Returns the result
  /// (null on a local or server refusal, which is shown inline).
  Future<BannerCheckResult?> _runCheck() async {
    final local = _action.localError();
    if (local != null) {
      setState(() => _checkError = local);
      return null;
    }
    final gen = ++_checkGen;
    setState(() {
      _checking = true;
      _check = null;
      _checkError = null;
    });
    try {
      final r = await _repo.checkAction(_action.kind.wire, _action.payload());
      // A newer edit or check started meanwhile: this answer is stale.
      if (!mounted || gen != _checkGen) return null;
      setState(() => _check = r);
      return r;
    } on BannerValidationException catch (e) {
      if (mounted && gen == _checkGen) setState(() => _checkError = e.message);
      return null;
    } catch (_) {
      if (mounted && gen == _checkGen) setState(() => _checkError = 'Не удалось проверить: нет связи с сервером');
      return null;
    } finally {
      if (mounted && gen == _checkGen) setState(() => _checking = false);
    }
  }

  /// The shops this banner is for (all when none is picked).
  bool _targets(int storeId) => _stores.isEmpty || _stores.contains(storeId);

  /// Why the banner would not show right now, from this form alone.
  List<String> _localReasons() {
    String d(DateTime x) => _fmt(x);
    final now = DateTime.now();
    final out = <String>[];
    if (!_active) out.add('Выключен переключатель «Показывать на главной»');
    if (_endsAt != null && !_endsAt!.isAfter(now)) out.add('Показ закончился ${d(_endsAt!)}');
    if (_startsAt != null && _startsAt!.isAfter(now)) out.add('Показ начнётся ${d(_startsAt!)}');
    if (_dailyFrom != null || _dailyTo != null) {
      final t = now.hour * 60 + now.minute;
      final f = _dailyFrom == null ? null : _dailyFrom!.hour * 60 + _dailyFrom!.minute;
      final u = _dailyTo == null ? null : _dailyTo!.hour * 60 + _dailyTo!.minute;
      final inside = f != null && u != null
          ? (f <= u ? (t >= f && t < u) : (t >= f || t < u))
          : (f != null ? t >= f : t < u!);
      if (!inside) {
        out.add('Сейчас не время показа: ${_hhmm(_dailyFrom) == null ? '' : 'с ${_hhmm(_dailyFrom)} '}'
                '${_hhmm(_dailyTo) == null ? '' : 'до ${_hhmm(_dailyTo)}'}'
            .trim());
      }
    }
    if (_onlyNew && _action.kind != BannerActionKind.none) out.add('Только в приложении 2.0.9 и новее');
    return out;
  }

  Future<void> _pickDaily({required bool from}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: (from ? _dailyFrom : _dailyTo) ?? const TimeOfDay(hour: 19, minute: 0),
    );
    if (t == null || !mounted) return;
    setState(() => from ? _dailyFrom = t : _dailyTo = t);
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final current = isStart ? _startsAt : _endsAt;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year, date.month, date.day,
      time?.hour ?? 0, time?.minute ?? 0,
    );
    setState(() {
      if (isStart) {
        _startsAt = picked;
        _startsCleared = false;
      } else {
        _endsAt = picked;
        _endsCleared = false;
      }
    });
  }

  /// Reject an impossible window before the round-trip. The backend enforces
  /// the same rule and returns 400, but catching it here keeps the operator's
  /// input on screen instead of bouncing them out of the form.
  String? _windowError() {
    if (_startsAt != null && _endsAt != null && !_endsAt!.isAfter(_startsAt!)) {
      return 'Дата окончания должна быть позже даты начала';
    }
    return null;
  }

  String? _dailyError() {
    if (_dailyFrom != null && _dailyTo != null && _dailyFrom == _dailyTo) {
      return 'Время «с» и «до» должно отличаться';
    }
    return null;
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _pick() async {
    // Two sources because iOS image_picker only reaches the Photos library —
    // banner artwork often arrives via Telegram/email and lives in Files/iCloud
    // Drive. file_picker covers those.
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Из галереи'),
              onTap: () => Navigator.of(sheetCtx).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Из файлов'),
              subtitle: const Text('iCloud Drive, Файлы, и т.д.'),
              onTap: () => Navigator.of(sheetCtx).pop('files'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    File? file;
    if (choice == 'gallery') {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        // No pre-resize — backend validates exact dimensions.
      );
      if (picked != null) file = File(picked.path);
    } else if (choice == 'files') {
      // FileType.image opens UIImagePickerController which lands in
      // Photos, not Files — defeats the whole point of the "Из файлов"
      // option. FileType.custom with an explicit extension whitelist
      // forces UIDocumentPickerViewController = iOS Files app.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic'],
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path != null && path.isNotEmpty) file = File(path);
    }
    if (file == null || !mounted) return;
    setState(() => _pickedImage = file);
  }

  void _error(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: const Color(0xFFD32F2F)),
      );

  /// Busy from the FIRST tap (critic 1.2.9 HIGH-1): the action check and the
  /// «нигде не покажется» dialog run before the request, and a second tap
  /// during them used to slip past the guard and create a second banner.
  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _saveSteps();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSteps() async {
    // For new banners, an image is required. For edits the image is optional.
    final isNew = widget.banner == null;
    if (isNew && _pickedImage == null) {
      _error('Выберите изображение');
      return;
    }
    if (_actionDirty) {
      final err = _action.localError();
      if (err != null) {
        _error(err);
        return;
      }
    }
    final windowErr = _windowError() ?? _dailyError();
    if (windowErr != null) {
      _error(windowErr);
      return;
    }

    // Blank means "let the backend append it"; only an explicit number pins a
    // position. Guard against nonsense like -5 or "abc".
    final rawPosition = _positionCtrl.text.trim();
    int? position;
    if (rawPosition.isNotEmpty) {
      final parsed = int.tryParse(rawPosition);
      if (parsed == null || parsed < 1) {
        _error('Позиция должна быть целым числом от 1');
        return;
      }
      // The field is 1-based for the operator; sort_order is 0-based.
      position = parsed - 1;
    }

    final hasAction = _action.kind != BannerActionKind.none;
    // A sell banner that no targeted shop can show right now: say so first.
    // Only for a new or changed action: an untouched one never blocks a save.
    if (hasAction && _actionDirty) {
      final r = await _runCheck();
      if (!mounted) return;
      if (r == null && _checkError != null && !_checkError!.startsWith('Не удалось проверить')) {
        _error(_checkError!);
        return;
      }
      final shown = r?.stores.where((s) => _targets(s.storeId)).toList() ?? const <BannerStoreCheck>[];
      if (r != null && r.stores.isNotEmpty && shown.every((s) => s.orderable == 0)) {
        // An info page whose BUTTON has nothing to open still shows, just
        // without the button (contract section 3).
        final cta = r.checked == 'cta';
        final go = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(cta ? 'Кнопка страницы сейчас нигде не откроется' : 'Баннер сейчас нигде не покажется'),
            content: Text(cta
                ? 'Ни в одном выбранном магазине сейчас нечего открыть по кнопке. Страница покажется без кнопки. Сохранить всё равно?'
                : 'Ни в одном выбранном магазине сейчас нечего открыть по этому баннеру. Сохранить всё равно?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Вернуться')),
              TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Сохранить')),
            ],
          ),
        );
        if (go != true || !mounted) return;
      }
    }
    final extras = BannerExtras(
      storeIds: _stores.toList(),
      dailyFrom: _hhmm(_dailyFrom),
      dailyTo: _hhmm(_dailyTo),
      // A badge only shows on a banner that opens something (08.11).
      badgeRu: hasAction ? _badgeRuCtrl.text : '',
      badgeKk: hasAction ? _badgeKkCtrl.text : '',
      // No action: no version limit (the switch is hidden then). A floor a
      // script set (e.g. 270) is kept while the switch stays on.
      minAppBuild: (hasAction && _onlyNew) ? (widget.banner?.minAppBuild ?? kBannerActionsMinBuild) : null,
      sendAction: _actionDirty,
      actionType: _action.kind.wire,
      action: _action.payload(),
    );

    setState(() => _saving = true);
    try {
      final cubit = context.read<BannersCubit>();
      // The link field is gone (08.11): links are actions now. Not sending
      // link_url keeps whatever a script set (the gift banner's shelf link).
      if (isNew) {
        await cubit.create(
          imageFile: _pickedImage!,
          title: _titleCtrl.text.trim(),
          sortOrder: position,
          active: _active,
          startsAt: _startsAt,
          endsAt: _endsAt,
          extras: extras,
        );
      } else {
        await cubit.update(
          id: widget.banner!.id,
          imageFile: _pickedImage,
          title: _titleCtrl.text.trim(),
          sortOrder: position,
          active: _active,
          startsAt: _startsAt,
          clearStartsAt: _startsCleared,
          endsAt: _endsAt,
          clearEndsAt: _endsCleared,
          extras: extras,
        );
      }
      if (!mounted) return;
      _leaving = true;
      Navigator.of(context).pop(true);
    } on BannerValidationException catch (e) {
      if (!mounted) return;
      _error(e.message);
    } catch (_) {
      if (!mounted) return;
      _error('Нет связи с сервером. Перед повтором обновите список: баннер мог сохраниться.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, [String? hint]) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.banner == null;
    final kind = _action.kind;
    final hasAction = kind != BannerActionKind.none;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _maybeLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'Новый баннер' : 'Редактирование'),
          actions: [
            TextButton(
              onPressed: _busy ? null : _save,
              child: const Text('Сохранить'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. The picture as the app draws it, with its badge.
            _ImagePickerCard(
              picked: _pickedImage,
              existingUrl: widget.banner?.imageUrl,
              onPick: _pick,
              kind: kind,
              badge: _badgeRuCtrl.text,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFFEE6F00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Рекомендуемый размер: 1300 × 800. '
                      'Соотношение сторон 1.5–1.7. Лишнее обрежется.'
                      '${hasAction ? ' Справа внизу будет кнопка «${bannerPillText(kind)}», '
                          'слева вверху метка: не ставьте туда текст.' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Название (для админки)',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            // 2. What a tap opens.
            _section('Что откроется при нажатии',
                'Без действия баннер просто картинка. Ссылки на сайты не поддерживаются.'),
            BannerTargetEditor(
              key: const ValueKey('banner-target'),
              target: _action.target,
              kinds: BannerActionKind.values,
              repo: _repo,
              stores: _allStores,
              onChanged: _actionChanged,
            ),
            if (kind == BannerActionKind.info) ...[
              const SizedBox(height: 8),
              BannerInfoEditor(
                info: _action.info,
                repo: _repo,
                stores: _allStores,
                onChanged: _actionChanged,
                heroFile: _pickedImage,
                heroUrl: widget.banner?.imageUrl,
              ),
            ],
            if (hasAction) ...[
              _section('Метка на баннере', 'Необязательно. Коротко: «−20%», «Новинка».'),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _badgeRuCtrl,
                    maxLength: 24,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Метка', border: OutlineInputBorder(), counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _badgeKkCtrl,
                    maxLength: 24,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Метка (KK)',
                      border: const OutlineInputBorder(),
                      counterText: '',
                      helperText: kkMissing(_badgeRuCtrl.text, _badgeKkCtrl.text) == null ? null : 'Нет KK',
                      helperStyle: const TextStyle(color: Color(0xFFB26A00)),
                    ),
                  ),
                ),
              ]),
            ],
            // 3. Where and when.
            _section('Где и когда'),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Показывать на главной'),
              contentPadding: EdgeInsets.zero,
            ),
            const Text('Магазины', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Без выбора баннер виден во всех магазинах.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              ChoiceChip(
                label: const Text('Все магазины'),
                selected: _stores.isEmpty,
                onSelected: (_) => setState(_stores.clear),
              ),
              for (final s in _allStores)
                FilterChip(
                  label: Text(s.storeName),
                  selected: _stores.contains(s.storeId),
                  onSelected: (v) => setState(() => v ? _stores.add(s.storeId) : _stores.remove(s.storeId)),
                ),
              for (final id in _stores.where((id) => !_allStores.any((s) => s.storeId == id)))
                FilterChip(
                  label: Text('Магазин $id'),
                  selected: true,
                  onSelected: (_) => setState(() => _stores.remove(id)),
                ),
            ]),
            if (_storesFailed)
              TextButton.icon(
                onPressed: _loadStores,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Не удалось загрузить магазины. Повторить'),
              ),
            const SizedBox(height: 12),
            _ScheduleRow(
              label: 'Начало показа',
              value: _startsAt == null ? null : _fmt(_startsAt!),
              onPick: () => _pickDateTime(isStart: true),
              onClear: _startsAt == null && !_startsCleared
                  ? null
                  : () => setState(() {
                        _startsAt = null;
                        _startsCleared = true;
                      }),
            ),
            const SizedBox(height: 8),
            _ScheduleRow(
              label: 'Конец показа',
              value: _endsAt == null ? null : _fmt(_endsAt!),
              onPick: () => _pickDateTime(isStart: false),
              onClear: _endsAt == null && !_endsCleared
                  ? null
                  : () => setState(() {
                        _endsAt = null;
                        _endsCleared = true;
                      }),
            ),
            if (_windowError() != null) ...[
              const SizedBox(height: 8),
              Text(
                _windowError()!,
                style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Text('Часы показа каждый день (время Алматы). Без времени: весь день.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: _ScheduleRow(
                  label: 'С',
                  value: _hhmm(_dailyFrom),
                  onPick: () => _pickDaily(from: true),
                  onClear: _dailyFrom == null ? null : () => setState(() => _dailyFrom = null),
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ScheduleRow(
                  label: 'До',
                  value: _hhmm(_dailyTo),
                  onPick: () => _pickDaily(from: false),
                  onClear: _dailyTo == null ? null : () => setState(() => _dailyTo = null),
                  icon: Icons.schedule,
                ),
              ),
            ]),
            if (_dailyError() != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_dailyError()!, style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 12)),
              ),
            if (hasAction)
              SwitchListTile(
                key: const ValueKey('banner-only-new'),
                contentPadding: EdgeInsets.zero,
                value: _onlyNew,
                onChanged: (v) => setState(() {
                  _onlyNew = v;
                  _onlyNewTouched = true;
                }),
                title: const Text('Только новые версии приложения'),
                subtitle: Text(_onlyNew
                    ? 'Покажется с версии 2.0.9 (сборка $kBannerActionsMinBuild). В старых версиях нажать на баннер нельзя, поэтому там его не будет.'
                    : 'Старые версии покажут его просто картинкой, без нажатия.'),
              ),
            // 4. Where it shows right now.
            _section('Где баннер покажется сейчас'),
            for (final r in _localReasons())
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFFB26A00)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r)),
                ]),
              ),
            Row(children: [
              OutlinedButton.icon(
                key: const ValueKey('banner-check'),
                onPressed: (!hasAction || _checking) ? null : _runCheck,
                icon: _checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fact_check_outlined),
                label: const Text('Проверить по магазинам'),
              ),
            ]),
            if (!hasAction)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Картинку без действия проверять не нужно.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
            if (_checkError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_checkError!, style: const TextStyle(color: Color(0xFFD32F2F))),
              ),
            if (_check != null) _CheckResult(result: _check!, targeted: _targets, shelf: kind == BannerActionKind.shelf),
            // 5. Position.
            const SizedBox(height: 20),
            TextField(
              controller: _positionCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Позиция (1 — самый первый)',
                helperText: 'Оставьте пустым, чтобы баннер встал в конец',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                key: const ValueKey('banner-save'),
                onPressed: _busy ? null : _save,
                // Also spins while Save runs the action check.
                icon: (_saving || (_busy && _checking))
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Проверить»: per shop, whether a customer there can open the banner now.
class _CheckResult extends StatelessWidget {
  const _CheckResult({required this.result, required this.targeted, this.shelf = false});
  final BannerCheckResult result;
  final bool Function(int storeId) targeted;
  final bool shelf;

  String _line(BannerStoreCheck s) {
    if (!targeted(s.storeId)) return '${s.storeName}: не выбран для этого баннера';
    if (s.orderable == 0) {
      return shelf
          ? '${s.storeName}: полка здесь сейчас не идёт, баннер не покажется'
          : '${s.storeName}: сейчас не продаётся, баннер не покажется';
    }
    if (shelf) return '${s.storeName}: полка идёт';
    if (s.total == 1) return '${s.storeName}: товар в продаже';
    return '${s.storeName}: в продаже ${s.orderable} из ${s.total}';
  }

  @override
  Widget build(BuildContext context) {
    if (result.stores.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Это действие работает во всех магазинах, проверка по магазинам не нужна',
            style: TextStyle(color: Color(0xFF2E7D32))),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (result.checked == 'cta')
          const Text('Кнопка страницы:', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final s in result.stores)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Icon(
                !targeted(s.storeId)
                    ? Icons.block
                    : (s.orderable > 0 ? Icons.check_circle : Icons.remove_circle_outline),
                size: 18,
                color: !targeted(s.storeId)
                    ? Colors.grey
                    : (s.orderable > 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_line(s),
                    style: TextStyle(color: targeted(s.storeId) ? null : Colors.grey.shade600)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _ImagePickerCard extends StatelessWidget {
  final File? picked;
  final String? existingUrl;
  final VoidCallback onPick;
  final BannerActionKind kind;
  final String badge;

  const _ImagePickerCard({
    required this.picked,
    required this.existingUrl,
    required this.onPick,
    this.kind = BannerActionKind.none,
    this.badge = '',
  });

  @override
  Widget build(BuildContext context) {
    final hasArt = picked != null || (existingUrl ?? '').isNotEmpty;
    // Drawn as the customer app draws the slide (16/8, cover, the badge and
    // the pill on a banner with an action), so what is centred here is
    // centred on the phone.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onPick,
        child: Stack(
          children: [
            hasArt
                ? BannerSlidePreview(file: picked, url: existingUrl, kind: kind, badge: badge)
                : AspectRatio(
                    aspectRatio: 16 / 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey.shade500),
                            const SizedBox(height: 8),
                            Text(
                              'Выбрать изображение',
                              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            if (hasArt) const Positioned(right: 8, top: 8, child: _ChangeBadge()),
          ],
        ),
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text('Изменить', style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

/// One row of the publish-window editor: a label, the chosen timestamp (or a
/// placeholder), a pick button, and a clear button that only appears once
/// there is something to clear.
class _ScheduleRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final IconData icon;

  const _ScheduleRow({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
    this.icon = Icons.calendar_month_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? 'Не задано',
                    style: TextStyle(
                      fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
                      color: value == null ? Colors.grey.shade600 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              IconButton(
                tooltip: 'Очистить',
                icon: const Icon(Icons.clear, size: 20),
                onPressed: onClear,
              ),
            Icon(icon, size: 20),
          ],
        ),
      ),
    );
  }
}
