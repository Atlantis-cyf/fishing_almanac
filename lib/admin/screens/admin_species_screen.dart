import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:fishing_almanac/api/api_client.dart';
import 'package:fishing_almanac/api/api_config.dart';
import 'package:fishing_almanac/api/api_exception.dart';
import 'package:fishing_almanac/theme/app_colors.dart';
import 'package:fishing_almanac/theme/app_font.dart';

class AdminSpeciesScreen extends StatefulWidget {
  const AdminSpeciesScreen({super.key});

  @override
  State<AdminSpeciesScreen> createState() => _AdminSpeciesScreenState();
}

class _AdminSpeciesScreenState extends State<AdminSpeciesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<_AdminSpeciesItem> _species = const [];

  int? _targetId; // A: keep
  int? _sourceId; // B: merge into A

  @override
  void initState() {
    super.initState();
    _fetchSpecies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _fetchSpecies({bool silent = false}) async {
    if (silent) {
      setState(() => _refreshing = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final api = context.read<ApiClient>();
      final res = await api.get<dynamic>(
        AdminSpeciesEndpoints.list,
        queryParameters: const {'status': 'all'},
      );
      final map = (res.data as Map?)?.cast<String, dynamic>() ?? const {};
      final list = (map['species'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => _AdminSpeciesItem.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      setState(() {
        _species = list;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    } finally {
      if (mounted && silent) {
        setState(() => _refreshing = false);
      }
    }
  }

  List<_AdminSpeciesItem> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _species;
    return _species.where((s) {
      if (s.speciesZh.toLowerCase().contains(q)) return true;
      if (s.scientificName.toLowerCase().contains(q)) return true;
      if ((s.aliasZh ?? '').toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  _AdminSpeciesItem? _byId(int? id) {
    if (id == null) return null;
    for (final s in _species) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> _openMergePreviewDialog() async {
    final target = _byId(_targetId);
    final source = _byId(_sourceId);
    if (target == null || source == null) return;
    if (target.id == source.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A 与 B 不能相同')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _MergePreviewDialog(
          target: target,
          source: source,
          defaultNote: _noteController.text.trim(),
          onExecute: (note, addSourceSciSynonym) async {
            final api = context.read<ApiClient>();
            await api.post<dynamic>(
              AdminSpeciesEndpoints.merge,
              data: <String, dynamic>{
                'target_species_id': target.id,
                'source_species_id': source.id,
                'create_snapshot': true,
                'add_source_scientific_as_synonym': addSourceSciSynonym,
                'note': note,
              },
            );
            _noteController.text = note;
            if (!mounted || !ctx.mounted) return;
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('合并完成：已将 B（${source.speciesZh}）并入 A（${target.speciesZh}）')),
            );
            setState(() {
              _sourceId = null;
            });
            await _fetchSpecies(silent: true);
          },
        );
      },
    );
  }

  Future<void> _openCreateSpeciesDialog() async {
    final form = _SpeciesFormValue.empty();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SpeciesEditDialog(
        title: '新增物种',
        initial: form,
        onSubmit: (value) async {
          final api = context.read<ApiClient>();
          final res = await api.post<dynamic>(AdminSpeciesEndpoints.list, data: value.toCreatePayload());
          final created = ((res.data as Map?)?['species'] as Map?)?.cast<String, dynamic>();
          final id = (created?['id'] as num?)?.toInt();
          if (id != null && value.imageBytes != null && value.imageBytes!.isNotEmpty) {
            final data = FormData.fromMap({
              'image': MultipartFile.fromBytes(
                value.imageBytes!,
                filename: 'species.jpg',
                contentType: MediaType('image', 'jpeg'),
              ),
            });
            await api.postMultipart<dynamic>(AdminSpeciesEndpoints.image(id), data: data);
          }
          await _fetchSpecies(silent: true);
        },
      ),
    );
  }

  Future<void> _openEditSpeciesDialog(_AdminSpeciesItem item) async {
    final api = context.read<ApiClient>();
    final detailRes = await api.get<dynamic>(AdminSpeciesEndpoints.detail(item.id));
    if (!mounted) return;
    final species = ((detailRes.data as Map?)?['species'] as Map?)?.cast<String, dynamic>() ?? const {};
    final form = _SpeciesFormValue.fromServer(species);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SpeciesEditDialog(
        title: '编辑物种',
        initial: form,
        onSubmit: (value) async {
          final patch = value.toPatchPayload();
          await api.patch<dynamic>(AdminSpeciesEndpoints.detail(item.id), data: patch);
          if (value.imageBytes != null && value.imageBytes!.isNotEmpty) {
            final data = FormData.fromMap({
              'image': MultipartFile.fromBytes(
                value.imageBytes!,
                filename: 'species.jpg',
                contentType: MediaType('image', 'jpeg'),
              ),
            });
            await api.postMultipart<dynamic>(AdminSpeciesEndpoints.image(item.id), data: data);
          }
          await api.post<dynamic>(
            AdminSpeciesEndpoints.replaceAliases(item.id),
            data: {'aliases': value.aliases},
          );
          await _fetchSpecies(silent: true);
        },
      ),
    );
  }

  Future<void> _openSnapshotsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _SnapshotsDialog(onRestored: () async => _fetchSpecies(silent: true)),
    );
  }

  Future<void> _openAuditLogsDialog() async {
    await showDialog<void>(context: context, builder: (ctx) => const _AuditLogsDialog());
  }

  @override
  Widget build(BuildContext context) {
    final target = _byId(_targetId);
    final source = _byId(_sourceId);
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background.withValues(alpha: 0.9),
        title: Text(
          '物种后台管理',
          style: AppFont.manrope(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : () => _fetchSpecies(silent: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('加载失败：$_error'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _fetchSpecies,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '按中文名 / 学名 / 俗名搜索',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _openCreateSpeciesDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('新增物种'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openSnapshotsDialog,
                                  icon: const Icon(Icons.restore),
                                  label: const Text('快照恢复'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _openAuditLogsDialog,
                                  icon: const Icon(Icons.history),
                                  label: const Text('合并历史'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _PickCard(
                            title: 'A（主物种，保留）',
                            value: target == null ? '未选择' : '${target.speciesZh} · ${target.scientificName}',
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 8),
                          _PickCard(
                            title: 'B（被合并，归入 A）',
                            value: source == null ? '未选择' : '${source.speciesZh} · ${source.scientificName}',
                            color: AppColors.secondary,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: (target != null && source != null) ? _openMergePreviewDialog : null,
                            icon: const Icon(Icons.merge_type),
                            label: const Text('预览并执行合并（B → A）'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final s = filtered[i];
                          final isMerged = s.mergedIntoSpeciesId != null;
                          return ListTile(
                            enabled: !isMerged,
                            title: Text('${s.speciesZh}  ·  ${s.scientificName}'),
                            subtitle: Text(
                              [
                                if ((s.aliasZh ?? '').trim().isNotEmpty) '俗名: ${s.aliasZh}',
                                '状态: ${s.status}',
                                if (isMerged) '已并入: #${s.mergedIntoSpeciesId}',
                              ].join(' ｜ '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 6,
                              children: [
                                OutlinedButton(
                                  onPressed: isMerged ? null : () => _openEditSpeciesDialog(s),
                                  child: const Text('编辑'),
                                ),
                                OutlinedButton(
                                  onPressed: isMerged
                                      ? null
                                      : () => setState(() {
                                            _targetId = s.id;
                                            if (_sourceId == s.id) _sourceId = null;
                                          }),
                                  child: const Text('设为A'),
                                ),
                                OutlinedButton(
                                  onPressed: isMerged
                                      ? null
                                      : () => setState(() {
                                            _sourceId = s.id;
                                            if (_targetId == s.id) _targetId = null;
                                          }),
                                  child: const Text('设为B'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _MergePreviewDialog extends StatefulWidget {
  const _MergePreviewDialog({
    required this.target,
    required this.source,
    required this.defaultNote,
    required this.onExecute,
  });

  final _AdminSpeciesItem target;
  final _AdminSpeciesItem source;
  final String defaultNote;
  final Future<void> Function(String note, bool addSourceSciSynonym) onExecute;

  @override
  State<_MergePreviewDialog> createState() => _MergePreviewDialogState();
}

class _MergePreviewDialogState extends State<_MergePreviewDialog> {
  bool _loading = true;
  bool _executing = false;
  String? _error;
  Map<String, dynamic>? _impact;
  bool _addSourceScientificAsSynonym = true;
  final TextEditingController _confirmController = TextEditingController();
  late final TextEditingController _noteController = TextEditingController(text: widget.defaultNote);

  bool get _confirmMatched =>
      _confirmController.text.trim().toLowerCase() == widget.target.scientificName.toLowerCase();

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _confirmController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final res = await api.post<dynamic>(
        AdminSpeciesEndpoints.mergePreview,
        data: <String, dynamic>{
          'target_species_id': widget.target.id,
          'source_species_id': widget.source.id,
        },
      );
      final map = (res.data as Map?)?.cast<String, dynamic>() ?? const {};
      final preview = (map['preview'] as Map?)?.cast<String, dynamic>() ?? const {};
      final impact = (preview['impact'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (!mounted) return;
      setState(() {
        _impact = impact;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('合并预览（B → A）'),
      content: SizedBox(
        width: 560,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('预览失败：$_error'),
                      const SizedBox(height: 10),
                      OutlinedButton(onPressed: _loadPreview, child: const Text('重试')),
                    ],
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('A（保留）：${widget.target.speciesZh} · ${widget.target.scientificName}'),
                        const SizedBox(height: 6),
                        Text('B（并入）：${widget.source.speciesZh} · ${widget.source.scientificName}'),
                        const SizedBox(height: 12),
                        Text('影响范围', style: AppFont.manrope(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('迁移鱼获数：${_impact?['catches_relink_count'] ?? 0}'),
                        Text('B 俗名总数：${_impact?['aliases_source_count'] ?? 0}'),
                        Text('新增到 A 的俗名：${_impact?['aliases_to_move_count'] ?? 0}'),
                        Text('B 异名总数：${_impact?['synonyms_source_count'] ?? 0}'),
                        Text('新增到 A 的异名：${_impact?['synonyms_to_move_count'] ?? 0}'),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _addSourceScientificAsSynonym,
                          onChanged: (v) => setState(() => _addSourceScientificAsSynonym = v ?? true),
                          title: const Text('将 B 的学名写入 A 的 synonym'),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteController,
                          decoration: const InputDecoration(
                            labelText: '合并备注（可选）',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _confirmController,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: '输入 A 的学名确认执行',
                            helperText: '请输入：${widget.target.scientificName}',
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _executing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: (_loading || _error != null || !_confirmMatched || _executing)
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _executing = true);
                  try {
                    await widget.onExecute(
                      _noteController.text.trim(),
                      _addSourceScientificAsSynonym,
                    );
                  } on ApiException catch (e) {
                    if (!mounted) return;
                    setState(() => _executing = false);
                    messenger.showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    setState(() => _executing = false);
                    messenger.showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                },
          child: _executing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('确认执行合并'),
        ),
      ],
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: color, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _AdminSpeciesItem {
  const _AdminSpeciesItem({
    required this.id,
    required this.speciesZh,
    required this.scientificName,
    required this.status,
    required this.aliasZh,
    required this.mergedIntoSpeciesId,
  });

  final int id;
  final String speciesZh;
  final String scientificName;
  final String status;
  final String? aliasZh;
  final int? mergedIntoSpeciesId;

  factory _AdminSpeciesItem.fromJson(Map<String, dynamic> json) {
    return _AdminSpeciesItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      speciesZh: (json['species_zh'] as String?) ?? '',
      scientificName: (json['scientific_name'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'approved',
      aliasZh: json['alias_zh'] as String?,
      mergedIntoSpeciesId: (json['merged_into_species_id'] as num?)?.toInt(),
    );
  }
}

class _SpeciesFormValue {
  _SpeciesFormValue({
    required this.speciesZh,
    required this.scientificName,
    required this.taxonomyZh,
    required this.descriptionZh,
    required this.isRare,
    required this.maxLengthM,
    required this.maxWeightKg,
    required this.aliases,
    this.imageBytes,
  });

  final String speciesZh;
  final String scientificName;
  final String taxonomyZh;
  final String descriptionZh;
  final bool isRare;
  final double maxLengthM;
  final double maxWeightKg;
  final List<String> aliases;
  final List<int>? imageBytes;

  factory _SpeciesFormValue.empty() => _SpeciesFormValue(
        speciesZh: '',
        scientificName: '',
        taxonomyZh: '',
        descriptionZh: '',
        isRare: false,
        maxLengthM: 0,
        maxWeightKg: 0,
        aliases: const [],
      );

  factory _SpeciesFormValue.fromServer(Map<String, dynamic> s) {
    final aliases = (s['aliases'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => (e['alias_zh'] ?? '').toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return _SpeciesFormValue(
      speciesZh: (s['species_zh'] ?? '').toString().trim(),
      scientificName: (s['scientific_name'] ?? '').toString().trim(),
      taxonomyZh: (s['taxonomy_zh'] ?? '').toString().trim(),
      descriptionZh: (s['description_zh'] ?? '').toString().trim(),
      isRare: s['is_rare'] == true,
      maxLengthM: ((s['max_length_m'] as num?)?.toDouble() ?? 0),
      maxWeightKg: ((s['max_weight_kg'] as num?)?.toDouble() ?? 0),
      aliases: aliases,
    );
  }

  Map<String, dynamic> toCreatePayload() => {
        'species_zh': speciesZh.trim(),
        'scientific_name': scientificName.trim(),
        'taxonomy_zh': taxonomyZh.trim(),
        'description_zh': descriptionZh.trim(),
        'is_rare': isRare,
        'max_length_m': maxLengthM,
        'max_weight_kg': maxWeightKg,
        'source': 'official',
        'status': 'approved',
      };

  Map<String, dynamic> toPatchPayload() => {
        'species_zh': speciesZh.trim(),
        'scientific_name': scientificName.trim(),
        'taxonomy_zh': taxonomyZh.trim(),
        'description_zh': descriptionZh.trim(),
        'is_rare': isRare,
        'max_length_m': maxLengthM,
        'max_weight_kg': maxWeightKg,
      };
}

class _SpeciesEditDialog extends StatefulWidget {
  const _SpeciesEditDialog({
    required this.title,
    required this.initial,
    required this.onSubmit,
  });

  final String title;
  final _SpeciesFormValue initial;
  final Future<void> Function(_SpeciesFormValue value) onSubmit;

  @override
  State<_SpeciesEditDialog> createState() => _SpeciesEditDialogState();
}

class _SpeciesEditDialogState extends State<_SpeciesEditDialog> {
  late final TextEditingController _zh = TextEditingController(text: widget.initial.speciesZh);
  late final TextEditingController _sci = TextEditingController(text: widget.initial.scientificName);
  late final TextEditingController _tax = TextEditingController(text: widget.initial.taxonomyZh);
  late final TextEditingController _desc = TextEditingController(text: widget.initial.descriptionZh);
  late final TextEditingController _maxLen = TextEditingController(text: widget.initial.maxLengthM.toString());
  late final TextEditingController _maxW = TextEditingController(text: widget.initial.maxWeightKg.toString());
  late final TextEditingController _aliases = TextEditingController(text: widget.initial.aliases.join(','));
  bool _isRare = false;
  bool _saving = false;
  List<int>? _imageBytes;

  @override
  void initState() {
    super.initState();
    _isRare = widget.initial.isRare;
  }

  @override
  void dispose() {
    _zh.dispose();
    _sci.dispose();
    _tax.dispose();
    _desc.dispose();
    _maxLen.dispose();
    _maxW.dispose();
    _aliases.dispose();
    super.dispose();
  }

  List<String> _parseAliases() {
    return _aliases.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _zh, decoration: const InputDecoration(labelText: '中文名 *')),
              TextField(controller: _sci, decoration: const InputDecoration(labelText: '学名 *')),
              TextField(controller: _tax, decoration: const InputDecoration(labelText: '分类')),
              TextField(controller: _aliases, decoration: const InputDecoration(labelText: '俗名（逗号分隔）')),
              Row(
                children: [
                  Expanded(child: TextField(controller: _maxLen, decoration: const InputDecoration(labelText: '最大长度(m)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _maxW, decoration: const InputDecoration(labelText: '最大重量(kg)'))),
                ],
              ),
              TextField(controller: _desc, decoration: const InputDecoration(labelText: '描述'), maxLines: 3),
              CheckboxListTile(
                value: _isRare,
                onChanged: (v) => setState(() => _isRare = v ?? false),
                title: const Text('稀有种'),
                contentPadding: EdgeInsets.zero,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                    if (x == null) return;
                    final bytes = await x.readAsBytes();
                    if (!mounted) return;
                    setState(() => _imageBytes = bytes);
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_imageBytes == null ? '选择新图片（可选）' : '已选择图片，将上传覆盖'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  if (_zh.text.trim().isEmpty || _sci.text.trim().isEmpty) {
                    messenger.showSnackBar(const SnackBar(content: Text('中文名和学名必填')));
                    return;
                  }
                  setState(() => _saving = true);
                  try {
                    await widget.onSubmit(
                      _SpeciesFormValue(
                        speciesZh: _zh.text,
                        scientificName: _sci.text,
                        taxonomyZh: _tax.text,
                        descriptionZh: _desc.text,
                        isRare: _isRare,
                        maxLengthM: double.tryParse(_maxLen.text.trim()) ?? 0,
                        maxWeightKg: double.tryParse(_maxW.text.trim()) ?? 0,
                        aliases: _parseAliases(),
                        imageBytes: _imageBytes,
                      ),
                    );
                    if (!mounted) return;
                    navigator.pop();
                  } on ApiException catch (e) {
                    if (!mounted) return;
                    setState(() => _saving = false);
                    messenger.showSnackBar(SnackBar(content: Text(e.message)));
                  } catch (e) {
                    if (!mounted) return;
                    setState(() => _saving = false);
                    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                },
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}

class _SnapshotsDialog extends StatefulWidget {
  const _SnapshotsDialog({required this.onRestored});
  final Future<void> Function() onRestored;

  @override
  State<_SnapshotsDialog> createState() => _SnapshotsDialogState();
}

class _SnapshotsDialogState extends State<_SnapshotsDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _snaps = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.get<dynamic>(AdminSpeciesEndpoints.snapshots);
    final list = (((res.data as Map?)?['snapshots'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (!mounted) return;
    setState(() {
      _snaps = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('快照恢复'),
      content: SizedBox(
        width: 620,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _snaps.length,
                itemBuilder: (context, i) {
                  final s = _snaps[i];
                  final id = (s['id'] ?? '').toString();
                  return ListTile(
                    title: Text((s['note'] ?? '无备注').toString()),
                    subtitle: Text((s['created_at'] ?? '').toString()),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final api = context.read<ApiClient>();
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('确认恢复快照'),
                            content: const Text('恢复会覆盖当前 aliases/synonyms，请谨慎操作。'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                              FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('恢复')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await api.post<dynamic>(AdminSpeciesEndpoints.restoreSnapshot(id));
                        if (!mounted) return;
                        messenger.showSnackBar(const SnackBar(content: Text('快照恢复完成')));
                        await widget.onRestored();
                        await _load();
                      },
                      child: const Text('恢复'),
                    ),
                  );
                },
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
    );
  }
}

class _AuditLogsDialog extends StatefulWidget {
  const _AuditLogsDialog();

  @override
  State<_AuditLogsDialog> createState() => _AuditLogsDialogState();
}

class _AuditLogsDialogState extends State<_AuditLogsDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _logs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final res = await api.get<dynamic>(AdminSpeciesEndpoints.auditLogs, queryParameters: const {'limit': 100});
    final list = (((res.data as Map?)?['logs'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (!mounted) return;
    setState(() {
      _logs = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('操作历史'),
      content: SizedBox(
        width: 760,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                shrinkWrap: true,
                itemBuilder: (context, i) {
                  final l = _logs[i];
                  return ListTile(
                    title: Text((l['action'] ?? '').toString()),
                    subtitle: Text('species_id=${l['species_id'] ?? '-'} ｜ ${l['created_at'] ?? ''}'),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: _logs.length,
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭'))],
    );
  }
}

