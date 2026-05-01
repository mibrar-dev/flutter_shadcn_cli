import 'dart:convert';
import 'dart:io';

import 'package:flutter_shadcn_cli/src/infrastructure/resolver/v1/project_path_guard.dart';
import 'package:flutter_shadcn_cli/src/inline_action_journal/inline_action_journal_entry.dart';
import 'package:path/path.dart' as p;

class InlineActionJournal {
  final Map<String, List<InlineActionJournalEntry>> byNamespace;

  const InlineActionJournal({
    required this.byNamespace,
  });

  static File journalFile(String projectRoot) {
    return File(p.join(projectRoot, '.shadcn', 'inline_actions.json'));
  }

  static Future<InlineActionJournal> load(String projectRoot) async {
    final file = journalFile(projectRoot);
    if (!await file.exists()) {
      return const InlineActionJournal(byNamespace: {});
    }
    try {
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final registries = (raw['registries'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value),
          ) ??
          const <String, dynamic>{};
      final parsed = <String, List<InlineActionJournalEntry>>{};
      for (final entry in registries.entries) {
        final list = (entry.value as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (value) => InlineActionJournalEntry.fromJson(
                value.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList();
        parsed[entry.key] = list;
      }
      return InlineActionJournal(byNamespace: parsed);
    } catch (_) {
      return const InlineActionJournal(byNamespace: {});
    }
  }

  Future<void> save(String projectRoot) async {
    final file = File(
      ProjectPathGuard.resolveSafeWritePath(
        projectRoot: projectRoot,
        destinationRelativePath: p.join('.shadcn', 'inline_actions.json'),
      ),
    );
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final payload = {
      'schemaVersion': 1,
      'registries': byNamespace.map(
        (key, value) => MapEntry(
          key,
          value.map((entry) => entry.toJson()).toList(),
        ),
      ),
    };
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  InlineActionJournal append({
    required String namespace,
    required InlineActionJournalEntry entry,
  }) {
    final next = <String, List<InlineActionJournalEntry>>{};
    byNamespace.forEach((key, value) {
      next[key] = List<InlineActionJournalEntry>.from(value);
    });
    final list =
        next.putIfAbsent(namespace, () => <InlineActionJournalEntry>[]);
    list.add(entry);
    return InlineActionJournal(byNamespace: next);
  }

  ({InlineActionJournal journal, InlineActionJournalEntry? entry}) takeLatest(
    String namespace, {
    required bool Function(InlineActionJournalEntry entry) where,
  }) {
    final current = byNamespace[namespace];
    if (current == null || current.isEmpty) {
      return (journal: this, entry: null);
    }

    final next = <String, List<InlineActionJournalEntry>>{};
    byNamespace.forEach((key, value) {
      next[key] = List<InlineActionJournalEntry>.from(value);
    });

    final list = next[namespace]!;
    InlineActionJournalEntry? removed;
    for (var i = list.length - 1; i >= 0; i--) {
      if (where(list[i])) {
        removed = list.removeAt(i);
        break;
      }
    }
    if (list.isEmpty) {
      next.remove(namespace);
    }
    return (
      journal: InlineActionJournal(byNamespace: next),
      entry: removed,
    );
  }

  ({InlineActionJournal journal, List<InlineActionJournalEntry> entries})
      takeAll(String namespace) {
    final current =
        byNamespace[namespace] ?? const <InlineActionJournalEntry>[];
    final next = <String, List<InlineActionJournalEntry>>{};
    byNamespace.forEach((key, value) {
      if (key != namespace) {
        next[key] = List<InlineActionJournalEntry>.from(value);
      }
    });
    return (
      journal: InlineActionJournal(byNamespace: next),
      entries: List<InlineActionJournalEntry>.from(current),
    );
  }
}
