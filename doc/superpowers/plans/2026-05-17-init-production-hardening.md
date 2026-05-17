# Init Production Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make interactive `flutter_shadcn init` production-safe, minimal, registry-item driven, and verify it against a real Flutter project with an interactive QA report.

**Architecture:** Split the work into CLI hardening and registry hardening. The CLI must enforce path safety, preserve `pubspec.yaml`, ask before optional assets/fonts/icons/themes, and load per-component manifests as the source of truth; the registry must stop declaring broad shared/font/theme folders as init payloads and move per-component dependencies into component-local manifest files.

**Tech Stack:** Dart CLI, `args`, `yaml`, line-preserving pubspec editing, shadcn registry item semantics, Flutter integration tests, local registry fixtures, generated QA markdown/PDF.

---

## Evidence And Root-Cause Map

- Official shadcn registry semantics are item driven: a registry item declares `files`, package dependencies, registry dependencies, and related configuration. Installation should resolve the selected item and its declared dependencies, not bulk-copy broad registry folders during init.
- `lib/src/application/services/installer/installer.dart` currently runs legacy init behavior that installs a fixed core shared closure through `_coreSharedIdsForInit()` and `installShared()`.
- `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.json` declares inline init actions that copy many shared files and optional font groups. The optional font groups have `"default": true`, so they are selected when no interactive group selector is used.
- `lib/src/application/services/init_action_engine/init_action_engine.dart` writes any project-relative path that passes `ProjectPathGuard`; that protects against project escape but does not enforce "code under lib, assets under assets".
- `lib/src/application/services/init_action_engine/init_action_engine.dart` rewrites `pubspec.yaml` by loading YAML into a map and encoding it back, which loses comments and original formatting.
- `lib/src/application/services/installer/installer_theme_part.dart` skips theme selection on invalid input instead of re-prompting.
- `lib/src/application/services/installer/installer_platform_alias_part.dart` hides a hard-coded subset of Material symbols. `Stepper`, `Step`, and related Flutter Material stepper symbols are not in that hide list.
- `shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/components/*/*/*.meta.json` files exist, but they are documentation metadata only; install data still comes mainly from `components.json`.
- `shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/manifests/components.json` currently has font assets inside the `theme` shared item, which causes font files to be installed under `lib/.../shared/fonts`.

## Branch And Delivery Strategy

Use one branch per task and merge forward in order:

1. `branch-v1-init-path-policy`
2. `branch-v1-init-interactive-options`
3. `branch-v1-pubspec-preserving-merge`
4. `branch-v1-component-meta-source-truth`
5. `branch-v1-registry-minimal-init-manifests`
6. `branch-v1-stepper-alias-collision`
7. `branch-v1-interactive-qa-report`

Each branch must end with:

```bash
dart analyze
dart test
dart pub publish --dry-run
git status --short
```

If code files are changed, run:

```bash
graphify update .
```

If `graphify update .` refuses because node count decreases after intentional deletions, record the refusal in the branch report instead of forcing unless explicitly approved.

---

## Task 1: CLI Init Path Policy

**Files:**
- Create: `lib/src/application/services/init_action_engine/init_destination_policy.dart`
- Modify: `lib/src/application/services/init_action_engine/init_action_engine.dart`
- Modify: `lib/src/application/services/installer/installer_config_part.dart`
- Modify: `lib/src/application/services/installer/installer_init_config_overrides_part.dart`
- Modify: `test/init_action_engine_test.dart`
- Modify: `test/cli_integration_test.dart`

- [ ] **Step 1: Write failing tests for interactive lib path validation**

Add a CLI integration test that feeds invalid component/shared paths first, then valid `lib/...` paths. The command must not create `./y`, `./components`, or any code folder outside `lib`.

```dart
test('interactive init rejects component and shared paths outside lib', () async {
  final result = await _runCli(
    args: ['init'],
    stdinLines: [
      '',
      'y',
      'lib/y',
      'shared',
      'lib/y/shared',
      'n',
      'y',
      'n',
      '',
      'y',
    ],
  );

  expect(result.exitCode, 0, reason: result.stderr);
  expect(Directory(p.join(appRoot.path, 'y')).existsSync(), isFalse);
  expect(Directory(p.join(appRoot.path, 'shared')).existsSync(), isFalse);
  expect(Directory(p.join(appRoot.path, 'lib', 'y')).existsSync(), isTrue);
  expect(
    File(p.join(appRoot.path, '.shadcn', 'config.json')).readAsStringSync(),
    contains('"installPath":"lib/y"'),
  );
});
```

- [ ] **Step 2: Write failing tests for inline init destination policy**

Add tests that reject code/file writes outside `lib`, while still allowing asset files under `assets`.

```dart
test('inline init rejects code writes outside lib but allows assets', () async {
  final engine = InitActionEngine(client: client);

  await expectLater(
    engine.executeActions(
      projectRoot: projectRoot.path,
      baseUrl: serverBaseUrl,
      actions: [
        {
          'type': 'copyFiles',
          'base': 'registry/shared',
          'destBase': '.',
          'files': ['theme/color_scheme.dart'],
        }
      ],
    ),
    throwsA(isA<InitActionEngineException>()),
  );

  final result = await engine.executeActions(
    projectRoot: projectRoot.path,
    baseUrl: serverBaseUrl,
    actions: [
      {
        'type': 'copyFiles',
        'base': 'registry/shared',
        'destBase': '.',
        'from': 'fonts',
        'to': 'assets/fonts',
        'files': ['fonts/lucide.ttf'],
      },
    ],
  );

  expect(result.filesWritten, 1);
  expect(File(p.join(projectRoot.path, 'assets/fonts/lucide.ttf')).existsSync(), isTrue);
});
```

- [ ] **Step 3: Implement `InitDestinationPolicy`**

Create a policy with explicit write classes:

```dart
enum InitWriteKind { dartCode, asset, projectConfig }

class InitDestinationPolicy {
  static InitWriteKind classify(String destinationRelativePath) {
    final path = destinationRelativePath.replaceAll('\\', '/');
    if (path == 'pubspec.yaml') return InitWriteKind.projectConfig;
    if (path.startsWith('lib/')) return InitWriteKind.dartCode;
    if (path.startsWith('assets/')) return InitWriteKind.asset;
    throw InitActionEngineException(
      'init action destination must be under lib/ or assets/: $destinationRelativePath',
    );
  }

  static void assertCopyDestination(String destinationRelativePath) {
    final kind = classify(destinationRelativePath);
    if (kind == InitWriteKind.projectConfig) {
      throw InitActionEngineException(
        'init copy actions cannot write pubspec.yaml; use mergePubspec',
      );
    }
  }
}
```

Call `InitDestinationPolicy.assertCopyDestination(destinationRel)` before every `ensureDirs`, `copyFiles`, and `copyDir` write. `mergePubspec` remains the only path that mutates `pubspec.yaml`.

- [ ] **Step 4: Tighten config path parsing**

Replace `_promptPath()` and `_normalizePathOverride()` with one strict normalizer:

```dart
String _normalizeLibPathInput(String value, {required String fallback}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return fallback;
  final expanded = _expandAliases(trimmed, _cachedConfig?.pathAliases);
  final normalized = p.posix.normalize(expanded.replaceAll('\\', '/'));
  if (normalized == 'lib' || normalized.startsWith('lib/')) {
    return normalized;
  }
  throw ResolverV1Exception('Path must start with lib/: $value');
}
```

Interactive prompts catch `ResolverV1Exception`, show the message, and re-ask. Non-interactive overrides fail fast with a non-zero exit code.

- [ ] **Step 5: Verify Task 1**

Run:

```bash
dart test test/init_action_engine_test.dart test/cli_integration_test.dart
dart analyze
```

Commit:

```bash
git add lib/src/application/services/init_action_engine lib/src/application/services/installer test/init_action_engine_test.dart test/cli_integration_test.dart
git commit -m "Harden init destination path policy"
```

---

## Task 2: Interactive Init Options For Assets, Fonts, Icons, And Themes

**Files:**
- Modify: `lib/src/application/services/installer/installer.dart`
- Modify: `lib/src/application/services/installer/installer_shared_part.dart`
- Modify: `lib/src/application/services/installer/installer_theme_part.dart`
- Modify: `lib/src/application/services/multi_registry/multi_registry_init_part.dart`
- Modify: `lib/src/application/services/init_action_engine/init_action_engine.dart`
- Modify: `test/cli_integration_test.dart`
- Modify: `test/init_action_engine_test.dart`

- [ ] **Step 1: Write failing interactive init test**

The test must run without `--yes`, decline all optional groups, skip theme selection, and assert that no font/icon assets and no bulk shared tree are installed.

```dart
test('interactive init does not install optional fonts icons or shared component closure by default', () async {
  final result = await _runCli(
    args: ['init', 'official'],
    stdinLines: [
      '',
      '',
      'n',
      'y',
      'n',
      'n',
      '',
      'n',
    ],
  );

  expect(result.exitCode, 0, reason: result.stderr);
  expect(Directory(p.join(appRoot.path, 'assets', 'fonts')).existsSync(), isFalse);
  expect(File(p.join(appRoot.path, 'lib/ui/shadcn/shared/fonts/lucide.ttf')).existsSync(), isFalse);
  expect(File(p.join(appRoot.path, 'lib/ui/shadcn/shared/theme/generated_colors.dart')).existsSync(), isFalse);
});
```

- [ ] **Step 2: Stop legacy init from installing the fixed core shared closure**

Change `Installer.init()` so it only:

1. loads or asks config,
2. executes inline registry init actions when the selected registry has them,
3. prompts for theme only if theme presets are available,
4. writes state/config/alias files without installing all shared items.

Do not call `_coreSharedIdsForInit()` from `init`. Keep `installShared()` for `add` dependency resolution.

- [ ] **Step 3: Make optional grouped actions always interactive unless `--yes` is explicit**

For non-`--yes` init, wire `groupSelector` so `copyFiles.groups` presents each group and only installs selected groups. For `--yes`, install no optional asset groups unless the registry marks a group with `"required": true`.

Prompt rule:

```text
Install font assets?
  1) Geist Sans - 18 weight/style variants
  2) Geist Mono - 17 weight/style variants
  3) Bootstrap icon font
  4) Lucide icon font
  5) Radix icon font
Select numbers separated by comma, "a" for all, or Enter to skip:
```

- [ ] **Step 4: Theme prompt must re-ask on invalid selection**

Change `_interactiveThemeSelection()` so invalid numbers and unknown ids do not pick a default and do not skip. It should loop until valid input or empty input.

```dart
while (true) {
  stdout.write('Theme number or id (Enter to skip): ');
  final input = stdin.readLineSync()?.trim() ?? '';
  if (input.isEmpty) return;
  final chosen = _resolveThemeInput(input, entries);
  if (chosen != null) {
    await applyThemeById(chosen.id, refresh: refresh);
    return;
  }
  logger.warn('Invalid theme selection "$input". Choose 1-${entries.length} or press Enter to skip.');
}
```

- [ ] **Step 5: Verify Task 2**

Run:

```bash
dart test test/init_action_engine_test.dart test/cli_integration_test.dart
dart analyze
```

Commit:

```bash
git add lib/src/application/services test/init_action_engine_test.dart test/cli_integration_test.dart
git commit -m "Make init optional assets and themes interactive"
```

---

## Task 3: Preserve `pubspec.yaml` Formatting And Comments

**Files:**
- Create: `lib/src/application/services/pubspec/pubspec_editor.dart`
- Modify: `lib/src/application/services/init_action_engine/init_action_engine.dart`
- Modify: `lib/src/application/services/installer/installer_pubspec_part.dart`
- Create: `test/pubspec_editor_test.dart`
- Modify: `test/init_action_engine_test.dart`
- Modify: `test/installer_test.dart`

- [ ] **Step 1: Write failing tests for comment-preserving pubspec merge**

```dart
test('pubspec editor appends dependencies assets and fonts without rewriting comments', () {
  final input = '''
name: sample_app

# Keep this dependency comment.
dependencies:
  flutter:
    sdk: flutter

flutter:
  # Keep this asset comment.
  uses-material-design: true
''';

  final editor = PubspecEditor(input);
  editor.addDependencies({'gap': '^3.0.1'});
  editor.addFlutterAssets(['assets/fonts/lucide.ttf']);
  editor.addFlutterFonts([
    PubspecFontFamily('LucideIcons', [PubspecFontAsset('assets/fonts/lucide.ttf')]),
  ]);

  final output = editor.toString();
  expect(output, contains('# Keep this dependency comment.'));
  expect(output, contains('# Keep this asset comment.'));
  expect(output, contains('  gap: ^3.0.1'));
  expect(output, contains('    - assets/fonts/lucide.ttf'));
  expect(output, contains('    - family: LucideIcons'));
});
```

- [ ] **Step 2: Implement line-preserving `PubspecEditor`**

The editor must:

- find top-level `dependencies:`, `dev_dependencies:`, and `flutter:` by indentation,
- insert missing map entries at the end of each existing section,
- preserve existing comments and blank lines,
- append a new top-level section only when missing,
- never encode the entire YAML document from scratch.

Use the existing line-based helpers in `installer_pubspec_part.dart` as the starting pattern, then move shared behavior into `PubspecEditor`.

- [ ] **Step 3: Route both init action engine and installer through `PubspecEditor`**

Replace `_loadPubspecDocument()`, `_encodeYamlDocument()`, `_mergeTopLevelMapEntries()`, `_mergeFlutterAssetsIntoDocument()`, and `_mergeFlutterFontsIntoDocument()` usage in init action merge code with `PubspecEditor`. Keep rollback line-preserving by removing only the entries added by the recorded `InitPubspecDelta`.

- [ ] **Step 4: Verify Task 3**

Run:

```bash
dart test test/pubspec_editor_test.dart test/init_action_engine_test.dart test/installer_test.dart
dart analyze
```

Commit:

```bash
git add lib/src/application/services/pubspec lib/src/application/services/init_action_engine lib/src/application/services/installer test/pubspec_editor_test.dart test/init_action_engine_test.dart test/installer_test.dart
git commit -m "Preserve pubspec formatting during registry merges"
```

---

## Task 4: Per-Component Manifest Source Of Truth

**Files:**
- Create: `lib/src/application/services/installer/component_manifest_resolver.dart`
- Modify: `lib/src/registry/component.dart`
- Modify: `lib/src/infrastructure/registry/index_loader.dart`
- Modify: `lib/src/application/services/installer/installer.dart`
- Modify: `lib/src/application/services/installer/installer_manifest_part.dart`
- Create: `test/component_manifest_resolver_test.dart`
- Modify: `test/installer_test.dart`

- [ ] **Step 1: Write failing tests for manifest-first install resolution**

Fixture:

```json
{
  "schemaVersion": 1,
  "id": "button",
  "name": "Button",
  "files": [
    {
      "source": "registry/components/control/button/button.dart",
      "destination": "{installPath}/components/control/button/button.dart"
    }
  ],
  "shared": ["clickable"],
  "dependsOn": [],
  "pubspec": {"dependencies": {"gap": "^3.0.1"}},
  "assets": [],
  "fonts": []
}
```

Test:

```dart
test('component manifest resolver prefers component-local meta over components json', () async {
  final resolver = ComponentManifestResolver(registry: registry, logger: logger);
  final resolved = await resolver.resolve('button');

  expect(resolved.shared, contains('clickable'));
  expect(resolved.pubspec['dependencies']['gap'], '^3.0.1');
});
```

- [ ] **Step 2: Implement lookup order**

For component `button`, resolve in this exact order:

1. `registry/components/<category>/<button>/button.meta.json`
2. `registry/components/<category>/<button>/meta.json`
3. `registry/components/<button>/button.meta.json`
4. `registry/components/<button>/meta.json`
5. current `components.json`
6. current `index.json` summary only for display metadata, never as install file source.

Cache per registry:

```dart
class ComponentManifestResolver {
  final Set<String> registriesWithoutComponentManifests = {};
}
```

If no component-local manifest exists for any component in a registry, mark that registry root as "no component manifests" and skip manifest probes on future installs in the same process.

- [ ] **Step 3: Keep fallback behavior safe**

If a manifest is present but malformed, fail the install with a clear error. Do not silently fallback to `components.json`, because that hides registry corruption.

- [ ] **Step 4: Verify Task 4**

Run:

```bash
dart test test/component_manifest_resolver_test.dart test/installer_test.dart
dart analyze
```

Commit:

```bash
git add lib/src/application/services/installer lib/src/registry lib/src/infrastructure/registry test/component_manifest_resolver_test.dart test/installer_test.dart
git commit -m "Use component manifests as install source of truth"
```

---

## Task 5: Registry Minimal Init And Per-Component Shared Dependencies

**Files In Registry Repo:**
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/registry-directory/registries/registries.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/manifests/components.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/manifests/index.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/components/**/meta.json`
- Modify: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry/components/**/*.meta.json`
- Create: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/tool/registry_manifest_audit.dart`
- Create: `/Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit/test/registry_manifest_audit_test.dart`

- [ ] **Step 1: Write registry audit checks**

The audit must fail when:

- any shared file destination under `{sharedPath}/fonts` contains `.ttf`, `.otf`, `.woff`, or `.woff2`,
- init copies more than minimal bootstrap files,
- init has `defaultComponents`,
- a component imports `../../../shared/...` but its manifest lacks the matching shared id,
- a component imports another component but its manifest lacks `dependsOn`,
- generated theme install entries copy an entire generated theme folder instead of exactly the selected theme manifest files.

Command:

```bash
cd /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit
dart run tool/registry_manifest_audit.dart
```

- [ ] **Step 2: Remove font/icon files from shared `theme`**

Move font/icon asset declarations out of the `theme` shared item. Fonts/icons belong in optional init asset groups or in per-component `assets`/`fonts` only when the component actually needs them.

Expected result:

```bash
rg -n '"destination": "\\{sharedPath\\}/fonts|registry/shared/fonts/.*\\.(ttf|otf|woff2?)"' flutter_shadcn_kit/lib/registry/manifests/components.json
```

Expected output: no matches.

- [ ] **Step 3: Replace init payload with minimal setup**

Update `registries.json` inline init:

- keep only path/config messages and required project-level dependency merge,
- do not include `defaultComponents`,
- do not copy component files,
- do not copy broad shared files,
- keep optional font/icon groups as optional and default-off,
- copy selected font/icon groups to `assets/fonts/...`,
- use `mergePubspec` to add only selected assets/fonts.

- [ ] **Step 4: Enrich every component-local manifest**

For every component manifest, add install-source fields:

```json
{
  "files": [],
  "shared": [],
  "dependsOn": [],
  "pubspec": {"dependencies": {}},
  "assets": [],
  "fonts": [],
  "postInstall": []
}
```

Use import scanning to populate `shared` and `dependsOn`. Keep README/docs metadata in the same file; the CLI will ignore doc-only fields for installation.

- [ ] **Step 5: Verify Task 5**

Run:

```bash
cd /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit/flutter_shadcn_kit
dart run tool/registry_manifest_audit.dart
dart test
```

Then from CLI repo:

```bash
dart test test/component_manifest_resolver_test.dart test/cli_integration_test.dart
```

Commit in each repo that changed:

```bash
git add registry-directory/registries/registries.json
git commit -m "Minimize official registry init actions"
```

```bash
cd /Users/ibrar/Desktop/infinora.noworkspace/shadcn_copy_paste/shadcn_flutter_kit
git add flutter_shadcn_kit/lib/registry flutter_shadcn_kit/tool flutter_shadcn_kit/test
git commit -m "Move install metadata into component manifests"
```

---

## Task 6: Stepper And Material Symbol Collision

**Files:**
- Modify: `lib/src/application/services/installer/installer_platform_alias_part.dart`
- Modify: `test/cli_integration_test.dart`
- Add fixture component files if needed under `test/fixtures/`

- [ ] **Step 1: Write failing test for Stepper**

Install `stepper`, import `app_components.dart`, and analyze a small Dart file using `Stepper` and `Step`. The generated alias file must hide Flutter Material `Stepper` and `Step`.

```dart
test('app components hides material Stepper and Step when registry stepper is installed', () async {
  await _runCli(args: ['init', '--yes']);
  await _runCli(args: ['add', 'stepper']);

  final aliases = File(p.join(appRoot.path, 'lib/ui/shadcn/app_components.dart')).readAsStringSync();
  expect(aliases, contains('Stepper'));
  expect(aliases, contains('Step'));

  final smoke = File(p.join(appRoot.path, 'lib', 'stepper_smoke.dart'));
  smoke.writeAsStringSync("""
import 'ui/shadcn/app_components.dart';

Widget buildStepper() {
  return Stepper(steps: const [Step(title: Text('One'))]);
}
""");
  final analyze = await Process.run('dart', ['analyze', smoke.path], workingDirectory: appRoot.path);
  expect(analyze.exitCode, 0, reason: '${analyze.stdout}\n${analyze.stderr}');
});
```

- [ ] **Step 2: Expand collision handling**

Add at minimum:

```dart
'Step',
'Stepper',
'StepState',
'StepStyle',
'StepperType',
```

Then add a defensive test that every installed public class with a matching Material export appears in the hide list.

- [ ] **Step 3: Verify Task 6**

Run:

```bash
dart test test/cli_integration_test.dart
dart analyze
```

Commit:

```bash
git add lib/src/application/services/installer/installer_platform_alias_part.dart test/cli_integration_test.dart
git commit -m "Hide material stepper symbols in generated aliases"
```

---

## Task 7: Interactive QA Report

**Files:**
- Create: `tool/qa/interactive_cli_qa.dart`
- Create: `qa_reports/interactive-cli-production-hardening.md`
- Create: `qa_reports/interactive-cli-production-hardening.pdf`
- Modify: `.gitignore` or `.pubignore` only if generated artifacts should not be published.

- [ ] **Step 1: Create automated interactive QA harness**

The harness must create a fresh Flutter project and run these user-realistic commands without `--yes` except where explicitly testing non-interactive behavior:

```bash
flutter create qa_manual_app
dart run bin/flutter_shadcn.dart init official
dart run bin/flutter_shadcn.dart add button
dart run bin/flutter_shadcn.dart add stepper
dart run bin/flutter_shadcn.dart theme
dart run bin/flutter_shadcn.dart locale init
dart run bin/flutter_shadcn.dart audit
dart run bin/flutter_shadcn.dart validate
flutter analyze
```

Capture:

- exact stdin choices,
- exact files created,
- `pubspec.yaml` diff preserving comments,
- asset files installed or skipped,
- generated `app_components.dart`,
- component manifests written under `.shadcn/components`,
- pass/fail result for each assertion.

- [ ] **Step 2: Score the QA report**

The report must score:

- Path safety: 20 points
- Optional asset prompt behavior: 20 points
- Minimal init file count: 15 points
- Per-component manifest install behavior: 15 points
- Pubspec preservation: 10 points
- Theme invalid-selection retry: 10 points
- Stepper/material collision: 10 points

Production acceptance is `100/100`, with no known failures.

- [ ] **Step 3: Generate PDF**

Use the existing local report generation approach already used in `qa_reports/`, or create a Dart/Markdown-to-PDF script if no reusable tool exists.

- [ ] **Step 4: Verify Task 7**

Run:

```bash
dart run tool/qa/interactive_cli_qa.dart
dart analyze
dart test
dart pub publish --dry-run
```

Commit:

```bash
git add tool/qa qa_reports
git commit -m "Add interactive CLI production QA report"
```

---

## Final Acceptance Checklist

- [ ] `init` never writes code folders/files outside `lib/`.
- [ ] `init` may write assets only under `assets/`.
- [ ] `init` does not install broad shared/component trees.
- [ ] Fonts and icon fonts are optional, prompted, default-off in interactive init, and installed under `assets/fonts`.
- [ ] Invalid theme selections re-prompt.
- [ ] Generated theme installation writes only selected theme files.
- [ ] `pubspec.yaml` comments, existing ordering, and indentation are preserved.
- [ ] Per-component manifest files are the install source of truth.
- [ ] Registry-level fallback to `components.json`/`index.json` only happens when the registry has no per-component manifests and is cached per registry.
- [ ] Shared files required by a component are declared in that component's manifest and installed only when the component is installed.
- [ ] Installing `stepper` does not create Material `Stepper`/`Step` collisions through `app_components.dart`.
- [ ] Full QA report reaches `100/100`.

