/// Model types for the CLI command reference metadata.
///
/// The groups themselves live in the sibling `command_metadata_*` files; this
/// library only defines the shapes they share.
library;

/// A titled, ordered group of commands (Components, Project, ...).
class CliCommandGroupMeta {
  final String title;
  final String slug;
  final int sortOrder;
  final List<CliCommandMeta> commands;

  const CliCommandGroupMeta({
    required this.title,
    required this.slug,
    required this.sortOrder,
    required this.commands,
  });
}

/// One command's reference entry.
class CliCommandMeta {
  final String id;
  final String description;
  final int sortOrder;
  final bool advanced;
  final List<String> aliases;
  final String usage;
  final List<CliArgumentMeta> arguments;
  final List<CliFlagMeta> flags;
  final List<String> examples;
  final String notes;
  final List<String> seeAlso;

  const CliCommandMeta({
    required this.id,
    required this.description,
    required this.sortOrder,
    required this.usage,
    this.advanced = false,
    this.aliases = const [],
    this.arguments = const [],
    this.flags = const [],
    this.examples = const [],
    this.notes = '',
    this.seeAlso = const [],
  });
}

/// A positional argument shown in a command's reference page.
class CliArgumentMeta {
  final String name;
  final bool required;
  final String description;

  const CliArgumentMeta(this.name, this.required, this.description);
}

/// A flag shown in a command's reference page.
class CliFlagMeta {
  final String name;
  final String short;
  final String defaultValue;
  final String description;
  final bool advanced;

  const CliFlagMeta({
    required this.name,
    required this.description,
    this.short = '',
    this.defaultValue = '',
    this.advanced = false,
  });
}
