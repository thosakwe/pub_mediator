import '../bin/main.dart';
import 'package:pubspec/pubspec.dart';
import 'package:pub_mediator/pub_mediator.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

main() {
  var project = new PubSpec(name: '<!>', dependencies: {
    'angel_auth': new HostedReference(new VersionConstraint.parse('^1.0.0')),
    'crypto': new HostedReference(new VersionConstraint.parse('<1.0.0'))
  });

  test('mismatching crypto', () async {
    var d = await diagnoseConflicts(project, concurrency: 1, verbose: true);
    describeDiagnosis(d);
    expect(d.conflicts, hasLength(1));
    expect(d.conflicts.first.type, DependencyConflictType.PACKAGE);
    expect(d.conflicts.first.packageName, 'crypto');
    expect(d.conflicts.first.requirements, hasLength(2));
    expect(d.conflicts.first.requirements.first.packageName, '<!>');
    expect(d.conflicts.first.requirements[1].packageName, 'angel_auth');
  });
}
