import 'package:flutter_shadcn_cli/src/presentation/cli/arg_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('arg helpers', () {
    test('parseFileKindOptions throws typed usage error for invalid kind', () {
      expect(
        () => parseFileKindOptions(['readme,bad'], optionName: 'include-files'),
        throwsA(
          isA<CliArgumentException>()
              .having(
                  (error) => error.optionName, 'optionName', 'include-files')
              .having((error) => error.token, 'token', 'bad'),
        ),
      );
    });
  });
}
