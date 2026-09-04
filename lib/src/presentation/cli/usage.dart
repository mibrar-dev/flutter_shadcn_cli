import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata.dart';

void printCliUsage({bool advanced = false}) {
  print('');
  print('flutter_shadcn CLI');
  print('Usage: flutter_shadcn <command> [arguments]');
  print('');

  for (final group in _sortedGroups()) {
    final commands = _sortedCommands(group)
        .where((command) => advanced || !command.advanced)
        .map(
          (command) => MapEntry(
            command.aliases.isEmpty
                ? command.id
                : '${command.id} (alias: ${command.aliases.join(', ')})',
            command.description,
          ),
        )
        .toList();
    if (commands.isEmpty) {
      continue;
    }
    _printUsageSection(group.title, commands);
  }

  print('Global flags');
  _printUsageFlagSection('General', [
    if (advanced)
      const MapEntry(
        '--advanced',
        'Show and enable developer and experimental features',
      ),
    const MapEntry('--verbose', 'Verbose logging'),
    const MapEntry('--version', 'Show the CLI version'),
    const MapEntry('--offline', 'Disable network calls (use cache only)'),
  ]);

  _printUsageFlagSection('Registry Selection', const [
    MapEntry('--registry-name', 'Registry namespace (e.g. shadcn)'),
  ]);

  if (advanced) {
    _printUsageFlagSection('Developer', const [
      MapEntry('--registry-path', 'Use a local registry root'),
      MapEntry('--registry-url', 'Use a remote registry URL'),
      MapEntry('--registries-path', 'Use a local registries.json file'),
      MapEntry('--skip-integrity', 'Skip registry integrity checks'),
    ]);
  }

  print('');
}

List<CliCommandGroupMeta> _sortedGroups() {
  return [...cliCommandMetadata]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

List<CliCommandMeta> _sortedCommands(CliCommandGroupMeta group) {
  return [...group.commands]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

void _printUsageSection(String title, List<MapEntry<String, String>> commands) {
  print(title);
  for (final entry in commands) {
    print(_formatUsageRow(entry.key, entry.value));
  }
  print('');
}

void _printUsageFlagSection(
  String title,
  List<MapEntry<String, String>> flags,
) {
  print('  $title:');
  for (final entry in flags) {
    print(_formatUsageRow(entry.key, entry.value, indent: '    '));
  }
  print('');
}

String _formatUsageRow(
  String name,
  String description, {
  String indent = '  ',
}) {
  const width = 24;
  final paddedName =
      name.length >= width ? '$name ' : name.padRight(width, ' ');
  return '$indent$paddedName$description';
}
