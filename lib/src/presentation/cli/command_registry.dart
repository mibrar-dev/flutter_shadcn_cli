import 'package:flutter_shadcn_cli/src/presentation/cli/cli_command_category.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/cli_command_entry.dart';
import 'package:flutter_shadcn_cli/src/presentation/cli/command_metadata.dart';

final List<CliCommandCategory> cliCommandCategories = [
  for (final group in _sortedGroups())
    CliCommandCategory(
      group.title,
      [
        for (final command in _sortedCommands(group))
          CliCommandEntry(
            command.aliases.isEmpty
                ? command.id
                : '${command.id} (alias: ${command.aliases.join(', ')})',
            command.description,
          ),
      ],
    ),
];

List<CliCommandGroupMeta> _sortedGroups() {
  return [...cliCommandMetadata]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}

List<CliCommandMeta> _sortedCommands(CliCommandGroupMeta group) {
  return [...group.commands]
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
}
