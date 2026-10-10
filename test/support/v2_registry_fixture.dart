import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/application/services/lockfile/hashing.dart';
import 'package:path/path.dart' as p;

import 'theme_preset_fixture.dart';

/// A tiny, fully valid `manifests/registry.json` (schemaVersion 2) plus the
/// files it declares, written to a temp directory.
///
/// Two components (`button`, `input`), one of them depending on the other, one
/// block (`login-01`) assembled from `button`, one primitive and the always-on
/// foundation/theme core. `button` has a user-owned `button_theme.dart`. No
/// unit declares `packages`, so installs never shell out to `pub get`.
class V2RegistryFixture {
  V2RegistryFixture._(this.root);

  /// Absolute registry root.
  final String root;

  static const String buttonDart = "import '../../foundation/data.dart';\n\n"
      'class Button {}\n';
  static const String inputDart = "import '../../foundation/data.dart';\n"
      "import '../button/button.dart';\n\n"
      'class Input {}\n';
  static const String buttonThemeDart = 'class ButtonTheme {}\n';

  /// The `login-01` block: layer 4, so it imports components, never blocks.
  static const String loginBlockDart =
      "import '../../components/button/button.dart';\n\n"
      'class Login01 {}\n';

  static V2RegistryFixture create({String? parent}) {
    final dir = Directory(
      p.join(parent ?? Directory.systemTemp.path,
          'shadcn_v2_fixture_${DateTime.now().microsecondsSinceEpoch}'),
    )..createSync(recursive: true);
    final root = dir.path;

    final files = <String, String>{
      'foundation/data.dart': 'class Data {}\n',
      'theme/color_tokens.dart': 'class ColorTokens {}\n',
      'primitives/clickable.dart': 'class Clickable {}\n',
      'components/button/button.dart': buttonDart,
      'components/button/button_theme.dart': buttonThemeDart,
      'components/input/input.dart': inputDart,
      'blocks/login-01/login_01.dart': loginBlockDart,
    };
    files.forEach((rel, content) {
      final file = File(p.join(root, p.normalize(rel)));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    });

    final presetFile = p.join(root, 'themes', 'vercel.json');
    File(presetFile)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(
        themePresetJson(id: 'vercel', name: 'Vercel'),
      ));

    final manifest = buildManifest(fileHashes: {
      for (final entry in files.entries)
        entry.key: FileHashing.ofText(entry.value),
    });
    File(p.join(root, 'manifests', 'registry.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(manifest));

    return V2RegistryFixture._(root);
  }

  /// The manifest document; override [fileHashes] or mutate for negative tests.
  static Map<String, dynamic> buildManifest({
    Map<String, String>? fileHashes,
    int schemaVersion = 2,
  }) {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'registry': {
        'name': 'fixture',
        'version': '1.0.0',
        'ref': 'test',
      },
      'install': {
        'root': 'lib/ui/shadcn',
        'componentsDir': 'components',
        'blocksDir': 'blocks',
        'layerDirs': {
          'foundation': 'foundation',
          'theme': 'theme',
          'primitives': 'primitives',
        },
        'userOwnedSuffix': '_theme.dart',
      },
      'foundation': {
        'data': {
          'files': ['foundation/data.dart'],
        },
      },
      'theme': {
        'color_tokens': {
          'files': ['theme/color_tokens.dart'],
        },
      },
      'primitives': {
        'clickable': {
          'files': ['primitives/clickable.dart'],
          'deps': {'primitives': <String>[]},
        },
      },
      'components': {
        'button': {
          'name': 'Button',
          'category': 'core',
          'description': 'A button.',
          'entry': 'components/button/button.dart',
          'files': ['components/button/button.dart'],
          'userOwned': ['components/button/button_theme.dart'],
          'deps': {
            'foundation': ['data'],
            'theme': ['color_tokens'],
            'primitives': ['clickable'],
            'components': <String>[],
          },
          'tags': ['core'],
          'api': {
            'classes': ['Button'],
          },
        },
        'input': {
          'name': 'Input',
          'category': 'core',
          'description': 'An input.',
          'entry': 'components/input/input.dart',
          'files': ['components/input/input.dart'],
          'userOwned': <String>[],
          'deps': {
            'foundation': ['data'],
            'theme': <String>[],
            'primitives': ['clickable'],
            'components': ['button'],
          },
          'tags': ['form'],
          'api': {
            'classes': ['Input'],
          },
        },
      },
      'themes': {
        'vercel': {
          'file': 'themes/vercel.json',
          'name': 'Vercel',
          'modes': ['light', 'dark'],
        },
      },
      'blocks': {
        'login-01': {
          'name': 'Login 01',
          'category': 'Authentication',
          'description': 'A minimal sign-in block built on the button.',
          'viewport': 'desktop',
          'entry': 'blocks/login-01/login_01.dart',
          'files': ['blocks/login-01/login_01.dart'],
          'docs': <String>[],
          'deps': {
            'foundation': ['data'],
            'theme': <String>[],
            'primitives': <String>[],
            'components': ['button'],
          },
          'tags': ['auth', 'login'],
          'install': 'flutter_shadcn add login-01',
          'import':
              "import 'package:<your_app>/ui/shadcn/blocks/login-01/login_01.dart';",
        },
      },
      'fileHashes': fileHashes ?? <String, String>{},
    };
  }

  /// Rewrites a registry file and returns its new sha256.
  String writeRegistryFile(String rel, String content) {
    final file = File(p.join(root, p.normalize(rel)));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return FileHashing.ofText(content);
  }

  void writeManifest(Map<String, dynamic> manifest) {
    File(p.join(root, 'manifests', 'registry.json'))
        .writeAsStringSync(jsonEncode(manifest));
  }

  String read(String rel) =>
      File(p.join(root, p.normalize(rel))).readAsStringSync();

  void dispose() {
    final dir = Directory(root);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
