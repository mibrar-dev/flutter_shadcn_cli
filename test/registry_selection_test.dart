import 'package:flutter_shadcn_cli/src/presentation/cli/registry_selection.dart';
import 'package:test/test.dart';

void main() {
  test('default remote registry base points at the live registry repo', () {
    expect(
      resolveRemoteBase(null),
      'https://raw.githubusercontent.com/ibrar-x/shadcn-flutter-registry/master',
    );
  });
}
