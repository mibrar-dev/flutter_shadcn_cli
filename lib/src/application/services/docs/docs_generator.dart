import 'dart:io';

import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata.dart';
import 'package:path/path.dart' as p;

String renderCommandReferenceIndex() {
  final buffer = StringBuffer()
    ..writeln('# Command Reference')
    ..writeln()
    ..writeln(
      'Generated from CLI command metadata. Do not edit these files by hand.',
    )
    ..writeln();

  for (final group in _sortedGroups()) {
    buffer
      ..writeln('## ${group.title}')
      ..writeln();
    if (group.slug == 'advanced') {
      buffer
        ..writeln('Advanced commands require `--advanced`.')
        ..writeln();
    }
    for (final command in _sortedCommands(group)) {
      buffer.writeln(
        '- [`flutter_shadcn ${command.id}`](./${group.slug}/${command.id}.md) - ${command.description}',
      );
    }
    buffer.writeln();
  }

  return _finalizeMarkdown(buffer);
}

String renderCommandPage(CliCommandGroupMeta group, CliCommandMeta command) {
  final buffer = StringBuffer()
    ..writeln('# flutter_shadcn ${command.id}')
    ..writeln()
    ..writeln('> ${command.description}')
    ..writeln();

  if (command.advanced) {
    buffer
      ..writeln('This command requires `--advanced`.')
      ..writeln();
  }

  if (command.aliases.isNotEmpty) {
    buffer
      ..writeln('## Aliases')
      ..writeln()
      ..writeln(command.aliases.map((alias) => '- `$alias`').join('\n'))
      ..writeln();
  }

  buffer
    ..writeln('## Usage')
    ..writeln()
    ..writeln('```bash')
    ..writeln(command.usage)
    ..writeln('```')
    ..writeln();

  _writeArguments(buffer, command);
  _writeFlags(buffer, command);
  _writeExamples(buffer, command);
  _writeNotes(buffer, command);
  _writeSeeAlso(buffer, group, command);

  return _finalizeMarkdown(buffer);
}

Map<String, String> renderCommandReferenceFiles() {
  final files = <String, String>{
    'index.md': renderCommandReferenceIndex(),
  };

  for (final group in _sortedGroups()) {
    for (final command in _sortedCommands(group)) {
      files[p.posix.join(group.slug, '${command.id}.md')] =
          renderCommandPage(group, command);
    }
  }

  return files;
}

Future<void> generateDocsSite({
  required String cliRoot,
  required CliLogger logger,
}) async {
  final commandsRoot = Directory(
    p.join(cliRoot, 'docs', 'reference', 'commands'),
  );
  if (commandsRoot.existsSync()) {
    commandsRoot.deleteSync(recursive: true);
  }
  commandsRoot.createSync(recursive: true);

  final files = renderCommandReferenceFiles();
  for (final entry in files.entries) {
    final file = File(p.join(commandsRoot.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
    logger.info('Wrote ${file.path}');
  }

  logger.success('Command reference docs regenerated.');
}

void _writeArguments(StringBuffer buffer, CliCommandMeta command) {
  buffer
    ..writeln('## Arguments')
    ..writeln();

  if (command.arguments.isEmpty) {
    buffer
      ..writeln('This command does not define positional arguments.')
      ..writeln();
    return;
  }

  buffer
    ..writeln('| Argument | Required | Description |')
    ..writeln('|----------|----------|-------------|');
  for (final argument in command.arguments) {
    buffer.writeln(
      '| `${argument.name}` | ${argument.required ? 'Yes' : 'No'} | ${argument.description} |',
    );
  }
  buffer.writeln();
}

void _writeFlags(StringBuffer buffer, CliCommandMeta command) {
  buffer
    ..writeln('## Flags')
    ..writeln();

  final flags = command.flags;
  if (flags.isEmpty) {
    buffer
      ..writeln('This command does not define command-specific flags.')
      ..writeln();
    return;
  }

  buffer
    ..writeln('| Flag | Short | Default | Description |')
    ..writeln('|------|-------|---------|-------------|');
  for (final flag in flags) {
    final description = flag.advanced
        ? '${flag.description} Requires `--advanced`.'
        : flag.description;
    buffer.writeln(
      '| `${flag.name}` | ${_tableCode(flag.short)} | ${_tableCode(flag.defaultValue)} | $description |',
    );
  }
  buffer.writeln();
}

void _writeExamples(StringBuffer buffer, CliCommandMeta command) {
  if (command.examples.isEmpty) {
    return;
  }

  buffer
    ..writeln('## Examples')
    ..writeln()
    ..writeln('```bash');
  for (final example in command.examples) {
    buffer.writeln(example);
  }
  buffer
    ..writeln('```')
    ..writeln();
}

void _writeNotes(StringBuffer buffer, CliCommandMeta command) {
  if (command.notes.isEmpty) {
    return;
  }

  buffer
    ..writeln('## Notes')
    ..writeln()
    ..writeln(command.notes)
    ..writeln();
}

void _writeSeeAlso(
  StringBuffer buffer,
  CliCommandGroupMeta group,
  CliCommandMeta command,
) {
  if (command.seeAlso.isEmpty) {
    return;
  }

  buffer
    ..writeln('## See Also')
    ..writeln();
  for (final id in command.seeAlso) {
    final target = _findCommand(id);
    if (target == null) {
      continue;
    }
    final (targetGroup, targetCommand) = target;
    final link = targetGroup.slug == group.slug
        ? '${targetCommand.id}.md'
        : '../${targetGroup.slug}/${targetCommand.id}.md';
    buffer.writeln('- [`flutter_shadcn ${targetCommand.id}`]($link)');
  }
  buffer.writeln();
}

List<CliCommandGroupMeta> _sortedGroups() {
  return [...cliCommandMetadata]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

List<CliCommandMeta> _sortedCommands(CliCommandGroupMeta group) {
  return [...group.commands]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

(CliCommandGroupMeta, CliCommandMeta)? _findCommand(String id) {
  for (final group in cliCommandMetadata) {
    for (final command in group.commands) {
      if (command.id == id || command.aliases.contains(id)) {
        return (group, command);
      }
    }
  }
  return null;
}

String _tableCode(String value) {
  if (value.isEmpty) {
    return '';
  }
  return '`$value`';
}

String _finalizeMarkdown(StringBuffer buffer) {
  return '${buffer.toString().trimRight()}\n';
}
