# CLI Testing Guide

## Test Commands

```bash
dart test
dart test test/skill_manager_test.dart
dart test test/cli_parser_test.dart
dart test test/command_matrix_test.dart
dart test test/resolver_v1_test.dart
dart test test/init_action_engine_test.dart
dart test test/e2e_multi_registry_fixture_test.dart
```

## By Change Type

- Parser/help change: `cli_parser_test.dart`, `command_matrix_test.dart`, manual `--help`.
- Registry resolution change: `resolver_v1_test.dart`, `multi_registry_manager_test.dart`, `e2e_multi_registry_fixture_test.dart`.
- Config/state migration: `config_state_migration_test.dart`, `config_test.dart`.
- Inline init action change: `init_action_engine_test.dart`.
- Installer behavior: `installer_test.dart`, `add_resolution_service_test.dart`, manual `dry-run --json`.
- Diagnostics: `validate_command_test.dart`, `deps_command.dart` related tests, `audit_command.dart` related tests.
- Skill install behavior: `skill_manager_test.dart`, manual `--advanced install-skill --available`.
- Docs generation: `docs_generator_test.dart`, `flutter_shadcn --advanced docs --generate`.

## Manual Smoke

```bash
dart run bin/flutter_shadcn.dart --help
dart run bin/flutter_shadcn.dart --advanced --help
dart run bin/flutter_shadcn.dart registries --json
dart run bin/flutter_shadcn.dart doctor --json
dart run bin/flutter_shadcn.dart --advanced install-skill --available
```

Document known analyzer failures rather than hiding them. New failures caused by a change must be fixed before completion.
