import 'package:flutter_shadcn_cli/src/application/services/installer/dry_run_plan.dart';
import 'package:flutter_shadcn_cli/src/logger.dart';
import 'package:test/test.dart';

void main() {
  const plan = DryRunPlan(
    requested: ['button'],
    components: ['button'],
    foundation: ['data'],
    theme: ['theme'],
    primitives: ['clickable'],
    files: [
      PlannedFile(
        source: 'components/button/button.dart',
        target: 'lib/ui/shadcn/components/button/button.dart',
        action: PlanAction.add,
      ),
      PlannedFile(
        source: 'foundation/data.dart',
        target: 'lib/ui/shadcn/foundation/data.dart',
        action: PlanAction.skip,
        reason: 'identical',
      ),
      PlannedFile(
        source: 'theme/theme.dart',
        target: 'lib/ui/shadcn/theme/theme.dart',
        action: PlanAction.update,
        reason: 'overwrite',
      ),
      PlannedFile(
        source: 'components/button/button_theme.dart',
        target: 'lib/ui/shadcn/components/button/button_theme.dart',
        action: PlanAction.keep,
        userOwned: true,
        reason: 'user-owned',
      ),
    ],
    packages: [PlannedPackage(name: 'intl', constraint: '^0.20.2')],
  );

  test('counts and hasChanges', () {
    expect(plan.countOf(PlanAction.add), 1);
    expect(plan.countOf(PlanAction.skip), 1);
    expect(plan.countOf(PlanAction.update), 1);
    expect(plan.countOf(PlanAction.keep), 1);
    expect(plan.hasChanges, isTrue);
  });

  test('json output carries the actions and packages', () {
    final json = plan.toJson();
    expect(json['requested'], ['button']);
    expect(json['layers'], {
      'foundation': ['data'],
      'theme': ['theme'],
      'primitives': ['clickable'],
    });
    expect((json['counts'] as Map)['added'], 1);
    expect((json['files'] as List), hasLength(4));
    expect((json['packages'] as List).single, {
      'name': 'intl',
      'constraint': '^0.20.2',
    });
  });

  test('human output lists every action group', () {
    final lines = <String>[];
    final logger = CliLogger(
      useColor: false,
      writeLine: lines.add,
      writeStderrLine: lines.add,
    );
    plan.writeHuman(logger);
    final text = lines.join('\n');
    expect(text, contains('Dry run'));
    expect(text, contains('Added (1)'));
    expect(text, contains('Skipped (1)'));
    expect(text, contains('Updated (1)'));
    expect(text, contains('Kept (1)'));
    expect(text, contains('intl ^0.20.2'));
    expect(text, contains('lib/ui/shadcn/components/button/button.dart'));
  });
}
