import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_shadcn_cli/src/exit_codes.dart';
import 'package:flutter_shadcn_cli/src/feedback_manager.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';

class FeedbackRegistryContext {
  final String? namespace;
  final String? baseUrl;

  const FeedbackRegistryContext({
    required this.namespace,
    required this.baseUrl,
  });
}

typedef FeedbackRegistryResolver = FeedbackRegistryContext? Function(
  String? namespaceOverride,
);

Future<int> runFeedbackCommand({
  required ArgResults command,
  required ArgResults rootArgs,
  required CliLogger logger,
  required FeedbackRegistryResolver resolveRegistry,
}) async {
  if (command['help'] == true) {
    print('Usage: flutter_shadcn feedback [options]');
    print('       flutter_shadcn feedback @<namespace> [options]');
    print('');
    print('Submit feedback or report issues via GitHub.');
    print('');
    print('Interactive mode (default):');
    print('  flutter_shadcn feedback');
    print('');
    print('Non-interactive mode:');
    print(
      '  flutter_shadcn feedback --type bug --title "Title" --body "Description"',
    );
    print('');
    print('Feedback types:');
    print('  bug, feature, docs, question, performance, other');
    print('');
    print('Options:');
    print('  --type, -t         Feedback type');
    print('  --title            Issue title');
    print('  --body             Issue description/body');
    print('  @<namespace>       Optional registry context (e.g. @shadcn)');
    print('  --help, -h         Show this message');
    return ExitCodes.success;
  }

  String? feedbackNamespaceOverride;
  final feedbackRest = [...command.rest];
  if (feedbackRest.isNotEmpty &&
      feedbackRest.first.startsWith('@') &&
      !feedbackRest.first.contains('/')) {
    feedbackNamespaceOverride = feedbackRest.removeAt(0).substring(1).trim();
    if (feedbackNamespaceOverride.isEmpty) {
      stderr.writeln('Error: Invalid namespace token for feedback.');
      return ExitCodes.usage;
    }
  }
  if (feedbackRest.isNotEmpty) {
    stderr.writeln('Error: Unrecognized feedback arguments.');
    return ExitCodes.usage;
  }

  final feedbackFlagNamespace = (rootArgs['registry-name'] as String?)?.trim();
  final needsFeedbackSelection = feedbackNamespaceOverride != null ||
      (feedbackFlagNamespace != null && feedbackFlagNamespace.isNotEmpty);
  final feedbackSelection = needsFeedbackSelection
      ? resolveRegistry(feedbackNamespaceOverride)
      : null;

  final feedbackMgr = FeedbackManager(logger: logger);
  await feedbackMgr.showFeedbackMenu(
    type: command['type'] as String?,
    title: command['title'] as String?,
    body: command['body'] as String?,
    registryNamespace: feedbackSelection?.namespace,
    registryBaseUrl: feedbackSelection?.baseUrl,
  );
  return ExitCodes.success;
}
