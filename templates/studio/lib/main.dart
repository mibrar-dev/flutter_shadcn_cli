import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'preview_registry.dart';

void main() {
  runApp(const ThemeStudioApp());
}

class ThemeStudioApp extends StatelessWidget {
  const ThemeStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'shadcn Theme Studio',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0F172A),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: const ThemeStudioHome(),
    );
  }
}

class ThemeStudioHome extends StatefulWidget {
  const ThemeStudioHome({super.key});

  @override
  State<ThemeStudioHome> createState() => _ThemeStudioHomeState();
}

class _ThemeStudioHomeState extends State<ThemeStudioHome>
    with SingleTickerProviderStateMixin {
  late final Future<StudioData> _dataFuture;
  late final TabController _phaseTabController;
  late final TabController _tabController;
  final Map<String, TextEditingController> _lightControllers = {};
  final Map<String, TextEditingController> _darkControllers = {};
  final Map<String, bool> _lightValid = {};
  final Map<String, bool> _darkValid = {};
  final Map<String, String> _lightValues = {};
  final Map<String, String> _darkValues = {};
  final TextEditingController _presetNameController = TextEditingController();
  final List<ThemePreset> _presets = [];
  String? _selectedPreset;
  String? _configPath;
  final Map<String, TextEditingController> _lightCommonControllers = {};
  final Map<String, TextEditingController> _darkCommonControllers = {};
  final Map<String, bool> _lightCommonValid = {};
  final Map<String, bool> _darkCommonValid = {};
  bool _showAdvancedLight = false;
  bool _showAdvancedDark = false;
  final Map<String, String> _sidebarSelections =
      Map.from(_defaultSidebarSelections);
  final Random _random = Random();
  bool _isDirty = false;
  int _selectedComponentIndex = 0;
  String _componentSearchQuery = '';
  late List<ComponentPreview> _filteredComponents;

  @override
  void initState() {
    super.initState();
    _phaseTabController = TabController(length: 2, vsync: this);
    _tabController = TabController(length: 2, vsync: this);
    _dataFuture = _loadStudioData();
    _filteredComponents = previewRegistry;
  }

  @override
  void dispose() {
    _phaseTabController.dispose();
    _tabController.dispose();
    for (final controller in _lightControllers.values) {
      controller.dispose();
    }
    for (final controller in _darkControllers.values) {
      controller.dispose();
    }
    for (final controller in _lightCommonControllers.values) {
      controller.dispose();
    }
    for (final controller in _darkCommonControllers.values) {
      controller.dispose();
    }
    _presetNameController.dispose();
    super.dispose();
  }

  Future<StudioData> _loadStudioData() async {
    final projectRoot = await _resolveProjectRoot();
    final configPath = await _resolveConfigPath();
    _configPath = configPath;
    final service = ThemeFileService(projectRoot);
    final schemeBundle = await service.loadSchemes();
    final components = await _loadComponents(projectRoot);

    _primeScheme(
      schemeBundle.light,
      _lightControllers,
      _lightValid,
      _lightValues,
    );
    _primeScheme(
      schemeBundle.dark,
      _darkControllers,
      _darkValid,
      _darkValues,
    );
    _primeCommonControllers(
      _lightValues,
      _lightCommonControllers,
      _lightCommonValid,
    );
    _primeCommonControllers(
      _darkValues,
      _darkCommonControllers,
      _darkCommonValid,
    );

    _presets
      ..clear()
      ..addAll(await _loadPresets(configPath, schemeBundle));
    if (_presets.isNotEmpty) {
      _selectedPreset = _presets.first.name;
    }

    return StudioData(
      projectRoot: projectRoot,
      themeFilePath: service.colorSchemePath,
      components: components,
      previews: previewRegistry,
      lightScheme: schemeBundle.light,
      darkScheme: schemeBundle.dark,
    );
  }

  void _primeScheme(
    Map<String, String> scheme,
    Map<String, TextEditingController> controllers,
    Map<String, bool> validMap,
    Map<String, String> valuesMap,
  ) {
    for (final key in ColorSchemeKeys.ordered) {
      final value = scheme[key] ?? 'FF000000';
      valuesMap[key] = value;
      validMap[key] = true;
      controllers[key] = TextEditingController(text: '#$value');
    }
  }

  void _primeCommonControllers(
    Map<String, String> values,
    Map<String, TextEditingController> controllers,
    Map<String, bool> validMap,
  ) {
    for (final group in CommonColorGroups.groups) {
      final value = values[group.tokens.first] ?? 'FF000000';
      validMap[group.id] = true;
      controllers[group.id] = TextEditingController(text: '#$value');
    }
  }

  Future<void> _saveSchemes(StudioData data) async {
    final service = ThemeFileService(data.projectRoot);
    await service.saveSchemes(
      light: _lightValues,
      dark: _darkValues,
    );
  }

  void _applyPreset(ThemePreset preset) {
    _syncScheme(
      preset.light,
      _lightControllers,
      _lightValid,
      _lightValues,
    );
    _syncScheme(
      preset.dark,
      _darkControllers,
      _darkValid,
      _darkValues,
    );
    _syncCommonControllers(
      _lightValues,
      _lightCommonControllers,
      _lightCommonValid,
    );
    _syncCommonControllers(
      _darkValues,
      _darkCommonControllers,
      _darkCommonValid,
    );
    setState(() {
      _selectedPreset = preset.name;
    });
  }

  void _syncScheme(
    Map<String, String> scheme,
    Map<String, TextEditingController> controllers,
    Map<String, bool> validMap,
    Map<String, String> valuesMap,
  ) {
    for (final key in ColorSchemeKeys.ordered) {
      final value = scheme[key] ?? valuesMap[key];
      if (value == null) {
        continue;
      }
      valuesMap[key] = value;
      validMap[key] = true;
      controllers[key]?.text = '#$value';
    }
  }

  void _syncCommonControllers(
    Map<String, String> values,
    Map<String, TextEditingController> controllers,
    Map<String, bool> validMap,
  ) {
    for (final group in CommonColorGroups.groups) {
      final value = values[group.tokens.first];
      if (value == null) {
        continue;
      }
      validMap[group.id] = true;
      final controller = controllers[group.id];
      if (controller == null) {
        controllers[group.id] = TextEditingController(text: '#$value');
      } else if (controller.text != '#$value') {
        controller.text = '#$value';
      }
    }
  }

  Future<void> _savePreset(String name) async {
    if (_configPath == null) {
      return;
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final config = await _readConfig(File(_configPath!));
    final presets = (config['presets'] as Map<String, dynamic>? ?? {});
    presets[trimmed] = {
      'light': _lightValues,
      'dark': _darkValues,
    };
    config['presets'] = presets;
    await _writeConfig(File(_configPath!), config);
    setState(() {
      _presets.removeWhere((preset) => preset.name == trimmed);
      _presets.add(
        ThemePreset(
          name: trimmed,
          light: Map<String, String>.from(_lightValues),
          dark: Map<String, String>.from(_darkValues),
          isBuiltIn: false,
        ),
      );
      _selectedPreset = trimmed;
    });
  }

  void _updateSchemeValue(
    String key,
    String input,
    Map<String, String> values,
    Map<String, bool> validMap,
  ) {
    final normalized = normalizeHex(input);
    setState(() {
      if (normalized == null) {
        validMap[key] = false;
      } else {
        validMap[key] = true;
        values[key] = normalized;
        if (identical(values, _lightValues)) {
          _syncCommonControllers(
            _lightValues,
            _lightCommonControllers,
            _lightCommonValid,
          );
        } else if (identical(values, _darkValues)) {
          _syncCommonControllers(
            _darkValues,
            _darkCommonControllers,
            _darkCommonValid,
          );
        }
      }
    });
  }

  void _updateCommonGroup(
    CommonColorGroup group,
    String input,
    Map<String, String> values,
    Map<String, bool> validMap,
    Map<String, TextEditingController> controllers,
    Map<String, bool> commonValid,
  ) {
    final normalized = normalizeHex(input);
    setState(() {
      if (normalized == null) {
        commonValid[group.id] = false;
        return;
      }
      commonValid[group.id] = true;
      for (final token in group.tokens) {
        values[token] = normalized;
        validMap[token] = true;
        controllers[token]?.text = '#$normalized';
      }
      _syncCommonControllers(values, controllers, commonValid);
    });
  }

  Future<void> _showComponentEditor(
    ComponentMeta component, {
    required bool isDark,
  }) async {
    final values = isDark ? _darkValues : _lightValues;
    final validMap = isDark ? _darkValid : _lightValid;
    final controllers = isDark ? _darkControllers : _lightControllers;
    final commonValid = isDark ? _darkCommonValid : _lightCommonValid;
    final title = isDark
        ? 'Edit ${component.name} (Dark)'
        : 'Edit ${component.name} (Light)';

    final localControllers = <String, TextEditingController>{};
    for (final group in CommonColorGroups.quickEdit) {
      final value = values[group.tokens.first] ?? 'FF000000';
      localControllers[group.id] = TextEditingController(text: '#$value');
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  'Adjust common tokens for this component preview.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final group in CommonColorGroups.quickEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CommonColorField(
                      group: group,
                      controller: localControllers[group.id]!,
                      isValid: true,
                      onChanged: (_) {},
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );

    if (result != true) {
      return;
    }

    for (final group in CommonColorGroups.quickEdit) {
      final input = localControllers[group.id]?.text ?? '';
      _updateCommonGroup(
        group,
        input,
        values,
        validMap,
        controllers,
        commonValid,
      );
    }
  }

  void _updateSidebarSelection(String key, String value) {
    setState(() {
      _sidebarSelections[key] = value;
      _isDirty = true;
    });
  }

  Future<void> _handleSidebarRowTap(SidebarRowDescriptor descriptor) async {
    if (descriptor.disabled) {
      return;
    }
    final options = _sidebarOptions[descriptor.bindingKey];
    if (options == null || options.isEmpty) {
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _SelectionSheet(
          title: descriptor.label,
          options: options,
          selected: _sidebarSelections[descriptor.bindingKey],
        );
      },
    );
    if (selected == null) {
      return;
    }
    if (_sidebarSelections[descriptor.bindingKey] == selected) {
      return;
    }
    _updateSidebarSelection(descriptor.bindingKey, selected);
  }

  void _shuffleTheme() {
    setState(() {
      for (final entry in _sidebarOptions.entries) {
        final candidates = entry.value;
        if (candidates.isEmpty) {
          continue;
        }
        _sidebarSelections[entry.key] =
            candidates[_random.nextInt(candidates.length)];
      }
      _isDirty = true;
    });
  }

  void _resetToDefaults() {
    setState(() {
      _sidebarSelections
        ..clear()
        ..addAll(_defaultSidebarSelections);
      _isDirty = false;
    });
  }

  List<Widget> _buildSidebarRows() {
    final rows = <Widget>[];
    for (var index = 0; index < _sidebarRowDescriptors.length; index++) {
      final descriptor = _sidebarRowDescriptors[index];
      rows.add(
        SidebarSelectRow(
          label: descriptor.label,
          value: _sidebarSelections[descriptor.bindingKey] ?? '',
          trailingIcon: descriptor.iconName == null
              ? null
              : _iconDataFor(descriptor.iconName!),
          trailingWidget: _buildTrailingWidget(descriptor),
          disabled: descriptor.disabled,
          onTap: () => _handleSidebarRowTap(descriptor),
        ),
      );
      if (index != _sidebarRowDescriptors.length - 1) {
        rows.add(const SizedBox(height: 10));
      }
    }
    return rows;
  }

  Widget? _buildTrailingWidget(SidebarRowDescriptor descriptor) {
    switch (descriptor.trailingKind) {
      case SidebarTrailingKind.colorDot:
        final color = _colorForBinding(descriptor.bindingKey);
        return _SidebarColorDot(color: color);
      case SidebarTrailingKind.textBadge:
        return _SidebarValueBadge(text: descriptor.trailingLabel ?? 'Aa');
      default:
        return null;
    }
  }

  Color _colorForBinding(String key) {
    final value = _sidebarSelections[key];
    switch (key) {
      case 'baseColor':
        return _baseColorDotPalette[value] ?? const Color(0xFF8F8F8F);
      case 'theme':
        return _themeDotPalette[value] ?? const Color(0xFF8F8F8F);
      default:
        return Colors.transparent;
    }
  }

  void _showActionMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // Phase 3: Component selection methods
  void _selectComponent(int index) {
    setState(() {
      _selectedComponentIndex = index;
    });
  }

  void _filterComponents(String query) {
    setState(() {
      _componentSearchQuery = query;
      if (query.isEmpty) {
        _filteredComponents = previewRegistry;
      } else {
        _filteredComponents = previewRegistry
            .where((component) =>
                component.id.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
      _selectedComponentIndex = 0;
    });
  }

  Widget _buildComponentListPanel() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: const Color(0xCC0F1012),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          TextField(
            onChanged: _filterComponents,
            decoration: InputDecoration(
              hintText: 'Search components...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.all(8),
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filteredComponents.isEmpty
                ? Center(
                    child: Text(
                      'No components found',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredComponents.length,
                    itemBuilder: (context, index) {
                      final component = _filteredComponents[index];
                      final isSelected = _selectedComponentIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          onTap: () => _selectComponent(index),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  component.id,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentPreviewPanel() {
    if (_filteredComponents.isEmpty) {
      return Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D1F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: const Center(child: Text('No components available')),
        ),
      );
    }

    final index =
        _selectedComponentIndex.clamp(0, _filteredComponents.length - 1);
    final component = _filteredComponents[index];

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1D1F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              component.id,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: SingleChildScrollView(
                    child: wrapPreviewTheme(
                      _lightValues,
                      component.builder(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase3Content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildComponentListPanel(),
              const SizedBox(width: 12),
              _buildComponentPreviewPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeTabContent(StudioData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Light Variant'),
                Tab(text: 'Dark Variant'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ThemeEditor(
                title: 'Light Colors',
                values: _lightValues,
                validMap: _lightValid,
                controllers: _lightControllers,
                components: data.components,
                previews: data.previews,
                showAdvanced: _showAdvancedLight,
                onToggleAdvanced: (value) {
                  setState(() => _showAdvancedLight = value);
                },
                onChanged: (key, value) => _updateSchemeValue(
                  key,
                  value,
                  _lightValues,
                  _lightValid,
                ),
                onEditComponent: (component) =>
                    _showComponentEditor(component, isDark: false),
              ),
              _ThemeEditor(
                title: 'Dark Colors',
                values: _darkValues,
                validMap: _darkValid,
                controllers: _darkControllers,
                components: data.components,
                previews: data.previews,
                showAdvanced: _showAdvancedDark,
                onToggleAdvanced: (value) {
                  setState(() => _showAdvancedDark = value);
                },
                onChanged: (key, value) => _updateSchemeValue(
                  key,
                  value,
                  _darkValues,
                  _darkValid,
                ),
                onEditComponent: (component) =>
                    _showComponentEditor(component, isDark: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context, StudioData data) {
    final rows = _buildSidebarRows();
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(32),
        bottomRight: Radius.circular(32),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 360,
          decoration: BoxDecoration(
            color: const Color(0xCC0F1012),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StudioHeader(
                data: data,
                isDirty: _isDirty,
                onSave: () async {
                  await _saveSchemes(data);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Theme updated in project code.')),
                  );
                },
              ),
              const SizedBox(height: 18),
              _PresetPanel(
                presets: _presets,
                selectedName: _selectedPreset,
                nameController: _presetNameController,
                onSelect: (preset) => _applyPreset(preset),
                onSave: (name) async {
                  await _savePreset(name);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Saved "$name" preset.')),
                  );
                },
                onApply: () async {
                  await _saveSchemes(data);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Preset applied to project.')),
                  );
                },
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(children: rows),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _SidebarActionRow(
                      label: 'Shuffle',
                      title: 'Try Random',
                      trailingKeyHint: 'R',
                      onTap: () {
                        _shuffleTheme();
                        _showActionMessage('Sidebar refreshed.');
                      },
                    ),
                    const SizedBox(height: 10),
                    _SidebarActionRow(
                      label: 'Reset',
                      title: 'Start Over',
                      trailingIcon: Icons.undo,
                      onTap: () {
                        _resetToDefaults();
                        _showActionMessage('Sidebar reverted.');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, StudioData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: _phaseTabController,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'Phase 2: Theme'),
                Tab(text: 'Phase 3: Components'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _phaseTabController,
            children: [
              _buildThemeTabContent(data),
              _buildPhase3Content(),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudioData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load studio: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final data = snapshot.requireData;
        return Shortcuts(
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.keyR): _ShuffleIntent(),
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                _ResetIntent(),
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                _ResetIntent(),
          },
          child: Actions(
            actions: {
              _ShuffleIntent: CallbackAction<_ShuffleIntent>(
                onInvoke: (_) {
                  _shuffleTheme();
                  _showActionMessage('Theme shuffled.');
                  return null;
                },
              ),
              _ResetIntent: CallbackAction<_ResetIntent>(
                onInvoke: (_) {
                  _resetToDefaults();
                  _showActionMessage('Theme reset.');
                  return null;
                },
              ),
            },
            child: FocusScope(
              autofocus: true,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('shadcn Theme Studio'),
                ),
                body: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1100;
                    final sidebar = _buildSidebar(context, data);
                    final content = _buildContent(context, data);
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          sidebar,
                          const VerticalDivider(
                              width: 1, color: Colors.white12),
                          Expanded(child: content),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        sidebar,
                        const Divider(height: 1, color: Colors.white12),
                        Expanded(child: content),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudioHeader extends StatelessWidget {
  final StudioData data;
  final bool isDirty;
  final VoidCallback onSave;

  const _StudioHeader({
    required this.data,
    required this.isDirty,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              shape: const CircleBorder(),
              color: Colors.white12,
              child: IconButton(
                onPressed: onSave,
                icon: const Icon(Icons.settings),
                tooltip: 'Theme Studio',
                color: Colors.white,
                splashRadius: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Build your own shadcn/ui',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'When you\'re done, click Save to sync into the project.',
                    maxLines: 2,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (isDirty)
              Container(
                margin: const EdgeInsets.only(left: 6, top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Draft',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          data.projectRoot,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white70,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          data.themeFilePath,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white54,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save),
            label: const Text('Save to project'),
          ),
        ),
      ],
    );
  }
}

class _ComponentsPanel extends StatelessWidget {
  final List<ComponentMeta> components;

  const _ComponentsPanel({required this.components});

  @override
  Widget build(BuildContext context) {
    if (components.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No installed components detected in lib/ui/shadcn/components.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: components.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final component = components[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  component.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  component.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: component.tags
                      .map(
                        (tag) => Chip(
                          label: Text(tag),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThemeEditor extends StatelessWidget {
  final String title;
  final Map<String, String> values;
  final Map<String, bool> validMap;
  final Map<String, TextEditingController> controllers;
  final void Function(String key, String value) onChanged;
  final List<ComponentMeta> components;
  final List<ComponentPreview> previews;
  final bool showAdvanced;
  final ValueChanged<bool> onToggleAdvanced;
  final void Function(ComponentMeta component) onEditComponent;

  const _ThemeEditor({
    required this.title,
    required this.values,
    required this.validMap,
    required this.controllers,
    required this.onChanged,
    required this.components,
    required this.previews,
    required this.showAdvanced,
    required this.onToggleAdvanced,
    required this.onEditComponent,
  });

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _ThemePreview(values: values),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: wrapPreviewTheme(
          values,
          _ComponentPreviewGallery(
            components: components,
            previews: previews,
            values: values,
            onEdit: onEditComponent,
          ),
        ),
      ),
      SwitchListTile(
        value: showAdvanced,
        onChanged: onToggleAdvanced,
        title: const Text('Advanced tokens'),
        subtitle: const Text('Edit individual theme tokens'),
      ),
    ];

    if (showAdvanced) {
      for (final key in ColorSchemeKeys.ordered) {
        final controller = controllers[key]!;
        final valid = validMap[key] ?? false;
        final parsed = parseColor(values[key]);
        items.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: parsed ?? Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.black.withOpacity(0.1),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    key,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Hex',
                      errorText: valid ? null : 'Use #RRGGBB or #AARRGGBB',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => onChanged(key, value),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: items,
    );
  }
}

class StudioData {
  final String projectRoot;
  final String themeFilePath;
  final List<ComponentMeta> components;
  final List<ComponentPreview> previews;
  final Map<String, String> lightScheme;
  final Map<String, String> darkScheme;

  const StudioData({
    required this.projectRoot,
    required this.themeFilePath,
    required this.components,
    required this.previews,
    required this.lightScheme,
    required this.darkScheme,
  });
}

class _ThemePreview extends StatelessWidget {
  final Map<String, String> values;

  const _ThemePreview({required this.values});

  @override
  Widget build(BuildContext context) {
    final background = parseColor(values['background']) ?? Colors.white;
    final foreground = parseColor(values['foreground']) ?? Colors.black;
    final card = parseColor(values['card']) ?? Colors.white;
    final cardForeground = parseColor(values['cardForeground']) ?? foreground;
    final primary = parseColor(values['primary']) ?? Colors.black;
    final primaryForeground =
        parseColor(values['primaryForeground']) ?? Colors.white;
    final muted = parseColor(values['muted']) ?? Colors.grey.shade200;
    final mutedForeground =
        parseColor(values['mutedForeground']) ?? Colors.grey.shade600;
    final border = parseColor(values['border']) ?? Colors.grey.shade300;
    final ring = parseColor(values['ring']) ?? Colors.blueGrey;

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: TextStyle(
              color: foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Card title',
                  style: TextStyle(
                    color: cardForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Typography and border colors update live.',
                  style: TextStyle(color: mutedForeground),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: primaryForeground,
                      ),
                      onPressed: () {},
                      child: const Text('Primary'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: foreground,
                        side: BorderSide(color: border),
                      ),
                      onPressed: () {},
                      child: const Text('Outline'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Input preview',
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: ring, width: 2),
              ),
              filled: true,
              fillColor: muted,
            ),
          ),
        ],
      ),
    );
  }
}

class ComponentMeta {
  final String id;
  final String name;
  final String description;
  final List<String> tags;

  const ComponentMeta({
    required this.id,
    required this.name,
    required this.description,
    required this.tags,
  });
}

class ThemePreset {
  final String name;
  final Map<String, String> light;
  final Map<String, String> dark;
  final bool isBuiltIn;

  const ThemePreset({
    required this.name,
    required this.light,
    required this.dark,
    required this.isBuiltIn,
  });
}

class CommonColorGroup {
  final String id;
  final String label;
  final List<String> tokens;

  const CommonColorGroup({
    required this.id,
    required this.label,
    required this.tokens,
  });
}

class CommonColorGroups {
  static const List<CommonColorGroup> groups = [
    CommonColorGroup(
      id: 'surface',
      label: 'Surface',
      tokens: ['background', 'card', 'popover', 'sidebar'],
    ),
    CommonColorGroup(
      id: 'surfaceText',
      label: 'Surface Text',
      tokens: [
        'foreground',
        'cardForeground',
        'popoverForeground',
        'sidebarForeground',
      ],
    ),
    CommonColorGroup(
      id: 'primary',
      label: 'Primary',
      tokens: ['primary', 'ring', 'sidebarPrimary'],
    ),
    CommonColorGroup(
      id: 'primaryText',
      label: 'Primary Text',
      tokens: ['primaryForeground', 'sidebarPrimaryForeground'],
    ),
    CommonColorGroup(
      id: 'accent',
      label: 'Accent',
      tokens: ['secondary', 'muted', 'accent', 'sidebarAccent'],
    ),
    CommonColorGroup(
      id: 'accentText',
      label: 'Accent Text',
      tokens: [
        'secondaryForeground',
        'mutedForeground',
        'accentForeground',
        'sidebarAccentForeground',
      ],
    ),
    CommonColorGroup(
      id: 'border',
      label: 'Border',
      tokens: ['border', 'input', 'sidebarBorder'],
    ),
    CommonColorGroup(
      id: 'destructive',
      label: 'Destructive',
      tokens: ['destructive'],
    ),
  ];

  static const List<CommonColorGroup> quickEdit = [
    CommonColorGroup(
      id: 'surface',
      label: 'Surface',
      tokens: ['background', 'card', 'popover', 'sidebar'],
    ),
    CommonColorGroup(
      id: 'primary',
      label: 'Primary',
      tokens: ['primary', 'ring', 'sidebarPrimary'],
    ),
    CommonColorGroup(
      id: 'border',
      label: 'Border',
      tokens: ['border', 'input', 'sidebarBorder'],
    ),
  ];
}

class _PresetPanel extends StatelessWidget {
  final List<ThemePreset> presets;
  final String? selectedName;
  final TextEditingController nameController;
  final void Function(ThemePreset preset) onSelect;
  final void Function(String name) onSave;
  final VoidCallback onApply;

  const _PresetPanel({
    required this.presets,
    required this.selectedName,
    required this.nameController,
    required this.onSelect,
    required this.onSave,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Presets', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedName,
                items: presets
                    .map(
                      (preset) => DropdownMenuItem(
                        value: preset.name,
                        child: Text(preset.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  final preset =
                      presets.firstWhere((item) => item.name == value);
                  onSelect(preset);
                },
                decoration: const InputDecoration(
                  labelText: 'Theme preset',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Save as',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => onSave(nameController.text),
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onApply,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommonColorsPanel extends StatelessWidget {
  final String title;
  final Map<String, String> values;
  final Map<String, bool> validMap;
  final Map<String, TextEditingController> commonControllers;
  final Map<String, bool> commonValid;
  final void Function(CommonColorGroup group, String value) onChanged;

  const _CommonColorsPanel({
    required this.title,
    required this.values,
    required this.validMap,
    required this.commonControllers,
    required this.commonValid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              for (final group in CommonColorGroups.groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CommonColorField(
                    group: group,
                    controller: commonControllers[group.id]!,
                    isValid: commonValid[group.id] ?? true,
                    onChanged: (value) => onChanged(group, value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommonColorField extends StatelessWidget {
  final CommonColorGroup group;
  final TextEditingController controller;
  final bool isValid;
  final ValueChanged<String> onChanged;

  const _CommonColorField({
    required this.group,
    required this.controller,
    required this.isValid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = parseColor(normalizeHex(controller.text) ?? '');
    final currentColor = parsed ?? Colors.transparent;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: parsed ?? Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black.withOpacity(0.1)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Text(group.label),
        ),
        Expanded(
          flex: 3,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Hex',
              errorText: isValid ? null : 'Use #RRGGBB or #AARRGGBB',
              border: const OutlineInputBorder(),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        _ColorPickerButton(
          color: currentColor,
          onColorSelected: (color) => onChanged(colorToHex(color)),
        ),
      ],
    );
  }
}

enum SidebarTrailingKind { colorDot, textBadge }

class SidebarRowDescriptor {
  final String label;
  final String bindingKey;
  final String? iconName;
  final SidebarTrailingKind? trailingKind;
  final String? trailingLabel;
  final bool disabled;

  const SidebarRowDescriptor({
    required this.label,
    required this.bindingKey,
    this.iconName,
    this.trailingKind,
    this.trailingLabel,
    this.disabled = false,
  });
}

const List<SidebarRowDescriptor> _sidebarRowDescriptors = [
  SidebarRowDescriptor(
      label: 'Preset', bindingKey: 'preset', iconName: 'sparkles'),
  SidebarRowDescriptor(
      label: 'Component Library',
      bindingKey: 'componentLibrary',
      iconName: 'component'),
  SidebarRowDescriptor(label: 'Style', bindingKey: 'style', iconName: 'square'),
  SidebarRowDescriptor(
    label: 'Base Color',
    bindingKey: 'baseColor',
    trailingKind: SidebarTrailingKind.colorDot,
  ),
  SidebarRowDescriptor(
    label: 'Theme',
    bindingKey: 'theme',
    trailingKind: SidebarTrailingKind.colorDot,
  ),
  SidebarRowDescriptor(
    label: 'Icon Library',
    bindingKey: 'iconLibrary',
    iconName: 'swirl',
  ),
  SidebarRowDescriptor(
    label: 'Font',
    bindingKey: 'font',
    trailingKind: SidebarTrailingKind.textBadge,
    trailingLabel: 'Aa',
  ),
  SidebarRowDescriptor(
      label: 'Radius', bindingKey: 'radius', iconName: 'corner'),
  SidebarRowDescriptor(
    label: 'Menu Color',
    bindingKey: 'menuColor',
    iconName: 'menu',
    disabled: true,
  ),
  SidebarRowDescriptor(
      label: 'Menu Accent', bindingKey: 'menuAccent', iconName: 'drops'),
];

const Map<String, List<String>> _sidebarOptions = {
  'preset': [
    'Vega / Lucide / Inter',
    'Minimal / Lucide / Inter',
    'Bold / Lucide / Inter',
  ],
  'componentLibrary': ['Radix UI', 'Material', 'Cupertino-like'],
  'style': ['Vega', 'Glass', 'Flat', 'Sharp'],
  'baseColor': ['Neutral', 'Slate', 'Zinc', 'Stone'],
  'theme': ['Neutral', 'Warm', 'Cool', 'High Contrast'],
  'iconLibrary': ['Lucide', 'Material Symbols', 'Feather'],
  'font': ['Inter', 'SF Pro', 'Roboto', 'Manrope'],
  'radius': ['Default', 'Compact', 'Rounded', 'Pill'],
  'menuColor': ['Default', 'Muted', 'Contrast'],
  'menuAccent': ['Subtle', 'Medium', 'Bold'],
};

const Map<String, String> _defaultSidebarSelections = {
  'preset': 'Vega / Lucide / Inter',
  'componentLibrary': 'Radix UI',
  'style': 'Vega',
  'baseColor': 'Neutral',
  'theme': 'Neutral',
  'iconLibrary': 'Lucide',
  'font': 'Inter',
  'radius': 'Default',
  'menuColor': 'Default',
  'menuAccent': 'Subtle',
};

const Map<String, Color> _baseColorDotPalette = {
  'Neutral': Color(0xFF9CA3AF),
  'Slate': Color(0xFF64748B),
  'Zinc': Color(0xFF6B7280),
  'Stone': Color(0xFF78716C),
};

const Map<String, Color> _themeDotPalette = {
  'Neutral': Color(0xFF8A8A8A),
  'Warm': Color(0xFFEA7F1A),
  'Cool': Color(0xFF4BD6FF),
  'High Contrast': Color(0xFFFFFFFF),
};

IconData? _iconDataFor(String name) {
  switch (name) {
    case 'sparkles':
      return Icons.auto_awesome;
    case 'component':
      return Icons.extension;
    case 'square':
      return Icons.crop_square;
    case 'swirl':
      return Icons.auto_fix_high;
    case 'corner':
      return Icons.crop_square_rounded;
    case 'menu':
      return Icons.menu;
    case 'drops':
      return Icons.water_drop;
    case 'undo':
      return Icons.undo;
    default:
      return null;
  }
}

class _SelectionSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String? selected;

  const _SelectionSheet({
    Key? key,
    required this.title,
    required this.options,
    this.selected,
  }) : super(key: key);

  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  late List<String> _filtered;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.options);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearch(String term) {
    final query = term.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = List.from(widget.options);
      } else {
        _filtered = widget.options
            .where((option) => option.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.32,
      initialChildSize: 0.45,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F1012),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search options...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.08)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final option = _filtered[index];
                    final selected = option == widget.selected;
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor:
                          selected ? Colors.white.withOpacity(0.04) : null,
                      title: Text(option),
                      trailing: selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(context).pop(option),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SidebarSelectRow extends StatefulWidget {
  final String label;
  final String value;
  final IconData? trailingIcon;
  final Widget? trailingWidget;
  final bool disabled;
  final VoidCallback? onTap;

  const SidebarSelectRow({
    Key? key,
    required this.label,
    required this.value,
    this.trailingIcon,
    this.trailingWidget,
    this.disabled = false,
    this.onTap,
  }) : super(key: key);

  @override
  State<SidebarSelectRow> createState() => _SidebarSelectRowState();
}

class _SidebarSelectRowState extends State<SidebarSelectRow> {
  bool _hover = false;
  bool _focus = false;

  Color get _background {
    if (widget.disabled) {
      return Colors.white.withOpacity(0.02);
    }
    if (_hover) {
      return Colors.white.withOpacity(0.06);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (focused) => setState(() => _focus = focused),
      child: MouseRegion(
        cursor: widget.disabled
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 56,
          decoration: BoxDecoration(
            color: _background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: _focus
                ? [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.15),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.disabled ? null : widget.onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.label,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Colors.white.withOpacity(0.65),
                                  letterSpacing: 0.4,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.value,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (widget.trailingWidget != null) ...[
                      widget.trailingWidget!,
                      const SizedBox(width: 10),
                    ],
                    if (widget.trailingIcon != null)
                      Icon(
                        widget.trailingIcon,
                        size: 20,
                        color: Colors.white70,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarActionRow extends StatelessWidget {
  final String label;
  final String title;
  final IconData? trailingIcon;
  final String? trailingKeyHint;
  final VoidCallback onTap;

  const _SidebarActionRow({
    Key? key,
    required this.label,
    required this.title,
    this.trailingIcon,
    this.trailingKeyHint,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
            color: Colors.white.withOpacity(0.02),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withOpacity(0.6),
                        ),
                  ),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              if (trailingKeyHint != null) _SidebarKeyHint(trailingKeyHint!),
              if (trailingIcon != null) ...[
                const SizedBox(width: 10),
                Icon(trailingIcon, size: 20, color: Colors.white70),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarColorDot extends StatelessWidget {
  final Color color;

  const _SidebarColorDot({Key? key, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.35)),
      ),
    );
  }
}

class _SidebarValueBadge extends StatelessWidget {
  final String text;

  const _SidebarValueBadge({Key? key, required this.text}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withOpacity(0.18)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SidebarKeyHint extends StatelessWidget {
  final String keyHint;

  const _SidebarKeyHint(this.keyHint, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Text(
        keyHint,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
      ),
    );
  }
}

class _ShuffleIntent extends Intent {
  const _ShuffleIntent();
}

class _ResetIntent extends Intent {
  const _ResetIntent();
}

class _ColorPickerButton extends StatelessWidget {
  final Color color;
  final ValueChanged<Color> onColorSelected;

  const _ColorPickerButton({
    required this.color,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.color_lens,
        color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
      ),
      tooltip: 'Pick a color',
      onPressed: () async {
        final selected = await showDialog<Color>(
          context: context,
          builder: (context) => _ColorPickerDialog(initialColor: color),
        );
        if (selected != null) {
          onColorSelected(selected);
        }
      },
    );
  }
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerDialog({
    required this.initialColor,
  });

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _current;

  @override
  void initState() {
    super.initState();
    _current = HSVColor.fromColor(widget.initialColor);
  }

  void _updateHue(double value) =>
      setState(() => _current = _current.withHue(value));
  void _updateSaturation(double value) =>
      setState(() => _current = _current.withSaturation(value));
  void _updateValue(double value) =>
      setState(() => _current = _current.withValue(value));
  void _updateAlpha(double value) =>
      setState(() => _current = _current.withAlpha(value));

  @override
  Widget build(BuildContext context) {
    final color = _current.toColor();
    return AlertDialog(
      title: const Text('Pick a color'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 64,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black26),
            ),
          ),
          _ColorSlider(
            label: 'Hue',
            value: _current.hue,
            min: 0,
            max: 360,
            onChanged: _updateHue,
          ),
          _ColorSlider(
            label: 'Saturation',
            value: _current.saturation,
            min: 0,
            max: 1,
            onChanged: _updateSaturation,
          ),
          _ColorSlider(
            label: 'Value',
            value: _current.value,
            min: 0,
            max: 1,
            onChanged: _updateValue,
          ),
          _ColorSlider(
            label: 'Opacity',
            value: _current.alpha,
            min: 0,
            max: 1,
            onChanged: _updateAlpha,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

String colorToHex(Color color) {
  return '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

class _ComponentPreviewGallery extends StatelessWidget {
  final List<ComponentMeta> components;
  final List<ComponentPreview> previews;
  final Map<String, String> values;
  final void Function(ComponentMeta component) onEdit;

  const _ComponentPreviewGallery({
    required this.components,
    required this.previews,
    required this.values,
    required this.onEdit,
  });

  int _columnsForWidth(double width) {
    if (width >= 1440) return 4;
    if (width >= 1024) return 3;
    if (width >= 640) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    if (components.isEmpty) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsForWidth(constraints.maxWidth);
        const spacing = 18.0;
        return GridView.builder(
          itemCount: components.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: 1.02,
          ),
          itemBuilder: (context, index) {
            final component = components[index];
            final preview = previews.firstWhere(
              (entry) => entry.id == component.id,
              orElse: () => ComponentPreview.fallback(component.id),
            );
            return RepaintBoundary(
              child: _ComponentPreviewCard(
                component: component,
                values: values,
                preview: preview,
                onEdit: () => onEdit(component),
              ),
            );
          },
        );
      },
    );
  }
}

class _ComponentPreviewCard extends StatelessWidget {
  final ComponentMeta component;
  final Map<String, String> values;
  final ComponentPreview preview;
  final VoidCallback onEdit;

  const _ComponentPreviewCard({
    required this.component,
    required this.values,
    required this.preview,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final background =
        parseColor(values['card']) ?? Theme.of(context).colorScheme.surface;
    final foreground = parseColor(values['cardForeground']) ??
        Theme.of(context).colorScheme.onSurface;
    final border =
        parseColor(values['border']) ?? Colors.white.withOpacity(0.12);
    return Material(
      color: background,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    component.name,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onEdit,
                  icon: Icon(Icons.edit, size: 20, color: foreground),
                  tooltip: 'Edit component theme',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              component.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground.withOpacity(0.75),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border.withOpacity(0.4)),
              ),
              clipBehavior: Clip.hardEdge,
              child: preview.builder(context),
            ),
            const SizedBox(height: 12),
            if (component.tags.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: component.tags
                    .map(
                      (tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: foreground.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            color: foreground.withOpacity(0.9),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            if (preview.isFallback)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Preview unavailable',
                  style: TextStyle(
                    color: foreground.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ThemeSchemeBundle {
  final Map<String, String> light;
  final Map<String, String> dark;

  const ThemeSchemeBundle({
    required this.light,
    required this.dark,
  });
}

class ThemeFileService {
  final String projectRoot;

  ThemeFileService(this.projectRoot);

  String get colorSchemePath => joinPaths([
        projectRoot,
        'lib',
        'ui',
        'shadcn',
        'shared',
        'theme',
        'color_scheme.dart',
      ]);

  Future<ThemeSchemeBundle> loadSchemes() async {
    final content = await File(colorSchemePath).readAsString();
    final lightBlock = _findBlock(content, 'lightDefaultColor');
    final darkBlock = _findBlock(content, 'darkDefaultColor');

    final light = _parseColors(lightBlock.block);
    final dark = _parseColors(darkBlock.block);

    return ThemeSchemeBundle(light: light, dark: dark);
  }

  Future<void> saveSchemes({
    required Map<String, String> light,
    required Map<String, String> dark,
  }) async {
    var content = await File(colorSchemePath).readAsString();
    final lightBlock = _findBlock(content, 'lightDefaultColor');
    final updatedLight = _updateBlock(lightBlock.block, light);
    content = content.replaceRange(
      lightBlock.start,
      lightBlock.end,
      updatedLight,
    );

    final darkBlock = _findBlock(content, 'darkDefaultColor');
    final updatedDark = _updateBlock(darkBlock.block, dark);
    content = content.replaceRange(
      darkBlock.start,
      darkBlock.end,
      updatedDark,
    );

    await File(colorSchemePath).writeAsString(content);
  }

  _SchemeBlock _findBlock(String content, String name) {
    final token = 'static const ColorScheme $name = ColorScheme(';
    final start = content.indexOf(token);
    if (start == -1) {
      throw FormatException('Missing ColorScheme $name in theme file.');
    }
    final openIndex = content.indexOf('(', start);
    int depth = 0;
    int? closeIndex;
    for (int i = openIndex; i < content.length; i++) {
      final char = content[i];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          closeIndex = i;
          break;
        }
      }
    }
    if (closeIndex == null) {
      throw FormatException('Malformed ColorScheme $name block.');
    }
    final semicolonIndex = content.indexOf(';', closeIndex);
    if (semicolonIndex == -1) {
      throw FormatException('Missing semicolon in ColorScheme $name block.');
    }
    final block = content.substring(start, semicolonIndex + 1);
    return _SchemeBlock(start, semicolonIndex + 1, block);
  }

  Map<String, String> _parseColors(String block) {
    final colors = <String, String>{};
    final regex = RegExp(r'(\w+):\s*Color\(0x([0-9A-Fa-f]{8})\)');
    for (final match in regex.allMatches(block)) {
      colors[match.group(1)!] = match.group(2)!.toUpperCase();
    }
    return colors;
  }

  String _updateBlock(String block, Map<String, String> colors) {
    var updated = block;
    for (final entry in colors.entries) {
      final pattern = RegExp(
        '(${entry.key}:\\s*Color\\(0x)([0-9A-Fa-f]{8})(\\))',
      );
      updated = updated.replaceAllMapped(pattern, (match) {
        return '${match.group(1)}${entry.value}${match.group(3)}';
      });
    }
    return updated;
  }
}

class _SchemeBlock {
  final int start;
  final int end;
  final String block;

  const _SchemeBlock(this.start, this.end, this.block);
}

class ColorSchemeKeys {
  static const List<String> ordered = [
    'background',
    'foreground',
    'card',
    'cardForeground',
    'popover',
    'popoverForeground',
    'primary',
    'primaryForeground',
    'secondary',
    'secondaryForeground',
    'muted',
    'mutedForeground',
    'accent',
    'accentForeground',
    'destructive',
    'destructiveForeground',
    'border',
    'input',
    'ring',
    'chart1',
    'chart2',
    'chart3',
    'chart4',
    'chart5',
    'sidebar',
    'sidebarForeground',
    'sidebarPrimary',
    'sidebarPrimaryForeground',
    'sidebarAccent',
    'sidebarAccentForeground',
    'sidebarBorder',
    'sidebarRing',
  ];
}

String joinPaths(List<String> parts) {
  final separator = Platform.pathSeparator;
  return parts.where((part) => part.isNotEmpty).join(separator);
}

String? normalizeHex(String input) {
  var value = input.trim();
  if (value.startsWith('#')) {
    value = value.substring(1);
  }
  if (value.startsWith('0x')) {
    value = value.substring(2);
  }
  final isHex = RegExp(r'^[0-9a-fA-F]+$');
  if (value.length == 6) {
    if (!isHex.hasMatch(value)) {
      return null;
    }
    return 'FF${value.toUpperCase()}';
  }
  if (value.length == 8) {
    if (!isHex.hasMatch(value)) {
      return null;
    }
    return value.toUpperCase();
  }
  return null;
}

Color? parseColor(String? argb) {
  if (argb == null) {
    return null;
  }
  try {
    final value = int.parse(argb, radix: 16);
    return Color(value);
  } catch (_) {
    return null;
  }
}

Future<String> _resolveProjectRoot() async {
  const directRoot = String.fromEnvironment('STUDIO_PROJECT_ROOT');
  if (directRoot.isNotEmpty) {
    return Directory(directRoot).absolute.path;
  }

  const configPath = String.fromEnvironment('STUDIO_CONFIG');
  if (configPath.isNotEmpty) {
    final configFile = File(configPath);
    if (await configFile.exists()) {
      final content = await configFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final root = data['projectRoot'] as String?;
      if (root != null && root.isNotEmpty) {
        return Directory(root).absolute.path;
      }
    }
  }

  final configFile = File('studio_config.json');
  if (await configFile.exists()) {
    final content = await configFile.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final root = data['projectRoot'] as String?;
    if (root != null && root.isNotEmpty) {
      return Directory(root).absolute.path;
    }
  }

  final current = Directory.current.absolute;
  final candidate = current.parent;
  if (File(joinPaths([candidate.path, 'pubspec.yaml'])).existsSync()) {
    return candidate.path;
  }

  final fallback = candidate.parent;
  return fallback.path;
}

Future<String> _resolveConfigPath() async {
  const configPath = String.fromEnvironment('STUDIO_CONFIG');
  if (configPath.isNotEmpty) {
    return configPath;
  }
  return 'studio_config.json';
}

Future<List<ThemePreset>> _loadPresets(
  String configPath,
  ThemeSchemeBundle schemes,
) async {
  final presets = <ThemePreset>[
    ThemePreset(
      name: 'Current',
      light: Map<String, String>.from(schemes.light),
      dark: Map<String, String>.from(schemes.dark),
      isBuiltIn: true,
    ),
  ];

  final colorDir = Directory(
    joinPaths([File(configPath).absolute.parent.path, 'colors']),
  );
  if (colorDir.existsSync()) {
    for (final entry in colorDir.listSync()) {
      if (entry is! File || !entry.path.endsWith('.css')) {
        continue;
      }
      final preset = await _presetFromCss(entry);
      if (preset != null) {
        presets.add(preset);
      }
    }
  }

  final config = await _readConfig(File(configPath));
  final stored = config['presets'] as Map<String, dynamic>? ?? {};
  for (final entry in stored.entries) {
    final data = entry.value as Map<String, dynamic>? ?? {};
    final light = (data['light'] as Map<String, dynamic>? ?? {})
        .map((key, value) => MapEntry(key, value.toString()));
    final dark = (data['dark'] as Map<String, dynamic>? ?? {})
        .map((key, value) => MapEntry(key, value.toString()));
    presets.add(
      ThemePreset(
        name: entry.key,
        light: light,
        dark: dark,
        isBuiltIn: false,
      ),
    );
  }

  return presets;
}

Future<ThemePreset?> _presetFromCss(File file) async {
  try {
    final content = await file.readAsString();
    final lightBlock = _extractCssBlock(content, ':root');
    final darkBlock = _extractCssBlock(content, '.dark');
    if (lightBlock == null || darkBlock == null) {
      return null;
    }
    final light = _parseCssVariables(lightBlock);
    final dark = _parseCssVariables(darkBlock);
    if (light.isEmpty || dark.isEmpty) {
      return null;
    }
    return ThemePreset(
      name: _presetNameFromFile(file),
      light: light,
      dark: dark,
      isBuiltIn: true,
    );
  } catch (_) {
    return null;
  }
}

String? _extractCssBlock(String content, String selector) {
  final regex = RegExp('$selector\\s*\\{([\\s\\S]*?)\\}');
  final match = regex.firstMatch(content);
  return match?.group(1);
}

Map<String, String> _parseCssVariables(String block) {
  final variables = <String, String>{};
  final regex = RegExp(r'--([a-zA-Z0-9-]+)\s*:\s*([^;]+);');
  for (final match in regex.allMatches(block)) {
    final rawKey = match.group(1);
    final rawValue = match.group(2);
    if (rawKey == null || rawValue == null) {
      continue;
    }
    final tokenKey = _cssKeyToToken(rawKey);
    final color = _parseCssColor(rawValue.trim());
    if (color == null) {
      continue;
    }
    variables[tokenKey] = _hexFromColor(color);
  }
  return variables;
}

String _cssKeyToToken(String key) {
  if (key.startsWith('chart-')) {
    return 'chart${key.split('-')[1]}';
  }
  final parts = key.split('-');
  final buffer = StringBuffer(parts.first);
  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    if (part.isEmpty) {
      continue;
    }
    buffer.write(part[0].toUpperCase());
    buffer.write(part.substring(1));
  }
  return buffer.toString();
}

Color? _parseCssColor(String value) {
  if (value.startsWith('oklch')) {
    return _oklchToColor(value);
  }
  if (value.startsWith('#')) {
    final hex = value.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
  }
  return null;
}

Color? _oklchToColor(String input) {
  final regex = RegExp(
    r'oklch\\(\\s*([0-9.]+)\\s+([0-9.]+)\\s+([0-9.]+)(?:\\s*/\\s*([0-9.]+%?))?\\s*\\)',
  );
  final match = regex.firstMatch(input);
  if (match == null) {
    return null;
  }
  final l = double.parse(match.group(1)!);
  final c = double.parse(match.group(2)!);
  final h = double.parse(match.group(3)!);
  final alphaRaw = match.group(4);
  final alpha = _parseAlpha(alphaRaw);
  return _oklchToSrgb(l, c, h, alpha);
}

double _parseAlpha(String? value) {
  if (value == null || value.isEmpty) {
    return 1;
  }
  if (value.endsWith('%')) {
    final percent = double.parse(value.replaceAll('%', ''));
    return (percent / 100).clamp(0, 1);
  }
  final parsed = double.parse(value);
  if (parsed > 1) {
    return (parsed / 100).clamp(0, 1);
  }
  return parsed.clamp(0, 1);
}

Color _oklchToSrgb(double l, double c, double h, double alpha) {
  final hRad = h * pi / 180;
  final a = c * cos(hRad);
  final b = c * sin(hRad);

  final l1 = l + 0.3963377774 * a + 0.2158037573 * b;
  final m1 = l - 0.1055613458 * a - 0.0638541728 * b;
  final s1 = l - 0.0894841775 * a - 1.2914855480 * b;

  final l3 = l1 * l1 * l1;
  final m3 = m1 * m1 * m1;
  final s3 = s1 * s1 * s1;

  final rLin = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
  final gLin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
  final bLin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

  final r = _linearToSrgb(rLin);
  final g = _linearToSrgb(gLin);
  final bOut = _linearToSrgb(bLin);

  return Color.fromARGB(
    (alpha * 255).round().clamp(0, 255),
    (r * 255).round().clamp(0, 255),
    (g * 255).round().clamp(0, 255),
    (bOut * 255).round().clamp(0, 255),
  );
}

double _linearToSrgb(double channel) {
  final clamped = channel.clamp(0, 1).toDouble();
  if (clamped <= 0.0031308) {
    return 12.92 * clamped;
  }
  return 1.055 * pow(clamped, 1 / 2.4) - 0.055;
}

String _hexFromColor(Color color) {
  return color.value.toRadixString(16).padLeft(8, '0').toUpperCase();
}

String _presetNameFromFile(File file) {
  final basename = file.path.split(Platform.pathSeparator).last;
  final name = basename.replaceFirst(RegExp(r'\.css$'), '');
  if (name.isEmpty) {
    return 'Preset';
  }
  return name[0].toUpperCase() + name.substring(1);
}

Future<Map<String, dynamic>> _readConfig(File configFile) async {
  if (!await configFile.exists()) {
    return {};
  }
  try {
    final content = await configFile.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

Future<void> _writeConfig(File configFile, Map<String, dynamic> data) async {
  await configFile.writeAsString(jsonEncode(data));
}

Future<List<ComponentMeta>> _loadComponents(String projectRoot) async {
  final componentsDir = Directory(joinPaths([
    projectRoot,
    'lib',
    'ui',
    'shadcn',
    'components',
  ]));

  if (!componentsDir.existsSync()) {
    return [];
  }

  final components = <ComponentMeta>[];
  final entries = componentsDir.listSync(recursive: true);
  for (final entry in entries) {
    if (entry is! File) {
      continue;
    }
    if (!entry.path.endsWith('meta.json')) {
      continue;
    }
    try {
      final content = await entry.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      components.add(
        ComponentMeta(
          id: data['id'] as String? ?? 'unknown',
          name: data['name'] as String? ?? data['id'] as String? ?? 'Unknown',
          description: data['description'] as String? ?? 'No description',
          tags: (data['tags'] as List<dynamic>? ?? [])
              .map((tag) => tag.toString())
              .toList(),
        ),
      );
    } catch (_) {
      // Ignore invalid meta files.
    }
  }

  components.sort((a, b) => a.name.compareTo(b.name));
  return components;
}
