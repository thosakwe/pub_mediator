import 'package:pubspec/pubspec.dart';
import 'package:pub_mediator/pub_mediator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

main() {
  var project = new PubSpec(
      name: '<!>',
      environment: new Environment(new VersionConstraint.parse('>=3.0.0'), {}),
      dependencies: {
        'meta': new HostedReference(new VersionConstraint.parse('^1.0.0'))
      });

  test('mismatching sdk', () async {
    var d = await diagnoseConflicts(project, verbose: true);
    expect(d.conflicts, hasLength(1));
    expect(d.conflicts.first.type, DependencyConflictType.SDK);
    expect(d.conflicts.first.sdkRequirements, hasLength(2));
    expect(d.conflicts.first.sdkRequirements.first.packageName, '<!>');
    expect(d.conflicts.first.sdkRequirements[1].packageName, 'meta');
  });
}
