import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';
import 'conflict.dart';
import 'diagnosis.dart';
import 'requirement.dart';

void _addDep(String key, DependencyRequirement requirement,
    Map<String, List<DependencyRequirement>> map) {
  if (map.containsKey(key))
    map[key].add(requirement);
  else
    map[key] = [requirement];
}

final String resolvedGit = (() {
  var r = Process.runSync('git', ['--version']);
  if (r.exitCode == 0 && r.stdout.startsWith('git')) return 'git';
  r = Process.runSync('git.cmd', ['--version']);
  if (r.exitCode == 0 && r.stdout.startsWith('git')) return 'git.cmd';
  throw 'You have no "git" executable available in your PATH. pub_mediator requires the availability of Git.';
})();

Future<DependencyDiagnosis> diagnoseConflicts(PubSpec projectPubspec,
    {@required bool verbose}) {
  // Resolve all requirements
  List<String> processed = [];
  Map<String, List<DependencyRequirement>> requirements = {};
  Map<String, VersionConstraint> sdkConstraints = {};
  var futures = [];
  var tempDir = new Directory.fromUri(
      Directory.current.uri.resolve('.pub_mediator_temp'));

  projectPubspec.allDependencies.forEach((name, dep) {
    // Add a dependency requirement
    _addDep(name, new DependencyRequirement(projectPubspec.name, dep),
        requirements);

    futures
        .add(resolvePubspec(name, dep, tempDir, verbose).then((pubspec) async {
      await identifyRequirements(name, pubspec, processed, requirements,
          sdkConstraints, tempDir, verbose);
    }));
  });

  return Future.wait(futures).then<DependencyDiagnosis>((_) async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);

    var d = new DependencyDiagnosis();

    // Find SDK mismatches...
    String packageWithCorrectSdk;
    VersionConstraint compatibleSdk;
    DependencyConflict sdkConflict;

    // Check if this very project applies the constraint
    if (projectPubspec.environment?.sdkConstraint != null) {
      packageWithCorrectSdk = projectPubspec.name;
      compatibleSdk = projectPubspec.environment.sdkConstraint;
    }

    if (verbose && sdkConstraints.isNotEmpty) {
      print('Comparing SDK constraints...');
    }

    sdkConstraints.forEach((packageName, sdk) {
      if (compatibleSdk == null) {
        sdk = compatibleSdk;
      } else if (!compatibleSdk.allowsAny(sdk)) {
        if (verbose)
          print(
              'Found SDK incompatibility between $packageWithCorrectSdk and $packageName.');
        if (sdkConflict == null) {
          sdkConflict = new DependencyConflict(DependencyConflictType.SDK);
          sdkConflict.sdkRequirements
              .add(new SdkRequirement(packageWithCorrectSdk, compatibleSdk));
        }

        sdkConflict.sdkRequirements.add(new SdkRequirement(packageName, sdk));
      }
    });

    if (sdkConflict != null) d.conflicts.add(sdkConflict);

    // Find version mismatches...
    requirements.forEach((packageName, reqs) {
      if (verbose) print('Comparing dependencies on $packageName...');

      DependencyConflict pkgConflict;
      reqs.fold<DependencyRequirement>(null, (a, b) {
        if (a == null) return b;
        if (a.dependency is HostedReference &&
            b.dependency is HostedReference) {
          HostedReference left = a.dependency, right = b.dependency;

          if (verbose) {
            print(
                '${a.packageName} requires ${left.versionConstraint}, ${b.packageName} requires ${right.versionConstraint}');
          }

          if (!left.versionConstraint.allowsAny(right.versionConstraint)) {
            if (pkgConflict == null) {
              pkgConflict = new DependencyConflict(
                  DependencyConflictType.PACKAGE,
                  packageName: packageName);
              pkgConflict.requirements
                  .add(new DependencyRequirement(a.packageName, a.dependency));
            }

            pkgConflict.requirements
                .add(new DependencyRequirement(b.packageName, b.dependency));
          }
        } else {
          // If they're not both hosted, create a conflict.
          if (pkgConflict == null) {
            pkgConflict = new DependencyConflict(DependencyConflictType.PACKAGE,
                packageName: packageName);
            pkgConflict.requirements
                .add(new DependencyRequirement(a.packageName, a.dependency));
          }

          pkgConflict.requirements
              .add(new DependencyRequirement(b.packageName, b.dependency));
        }

        return a;
      });

      if (pkgConflict != null) d.conflicts.add(pkgConflict);
    });

    return d;
  });
}

Future<PubSpec> resolvePubspec(String packageName, DependencyReference dep,
    Directory tempDir, bool verbose) async {
  var pubHosted =
  (Platform.environment['PUB_HOSTED_URL'] ?? 'https://pub.dartlang.org') + '/api';

  if (dep is HostedReference) {
    var client = new http.Client();
    if (verbose) print('Downloading $pubHosted/packages/$packageName...');
    var pkgResponse = await client.get('$pubHosted/packages/$packageName');
    List<Map> versions = JSON.decode(pkgResponse.body)['versions'];
    Map<Version, String> versionMap = {};
    List<Version> potentialVersions = [];

    for (var v in versions) {
      var versionString = v['pubspec']['version'];
      var ver = new Version.parse(versionString);
      if (dep.versionConstraint.allows(ver)) {
        potentialVersions.add(ver);
        versionMap[ver] = versionString;
      }
    }

    if (potentialVersions.isNotEmpty) {
      // Choose most recent compatible version
      potentialVersions.sort((a, b) => b.compareTo(a));
      var versionString = versionMap[potentialVersions.first];
      if (verbose)
        print(
            'Downloading $pubHosted/packages/$packageName/versions/$versionString...');
      var response = await client
          .get('$pubHosted/packages/$packageName/versions/$versionString');
      client.close();

      try {
        var p = JSON.decode(response.body)['pubspec'];
        if (p is! Map) throw 'Response is not a JSON object.';
        return new PubSpec.fromJson(p..remove('dev_dependencies'));
      } catch (e) {
        throw 'Couldn\'t parse $packageName version from response: ${response.body}: $e';
      }
    }

    client.close();
    throw 'Couldn\'t resolve a hosted version of "$packageName" matching constraint ${dep.versionConstraint}.';
  } else if (dep is PathReference) {
    var d = new Directory(dep.path);
    if (verbose)
      print('Resolved $packageName to ${d.absolute.uri.toFilePath()}...');
    return await PubSpec.load(d);
  } else if (dep is GitReference) {
    var dir = new Directory.fromUri(tempDir.uri.resolve(packageName));
    if (await dir.exists()) await dir.delete(recursive: true);
    List<String> args = ['clone'];
    args.add(dep.url);
    args.add(dir.absolute.uri.toFilePath());
    if (verbose) print('$resolvedGit ' + args.join(' ') + '...');
    var result = await Process.run(resolvedGit, args);

    if (result.exitCode != 0) {
      throw '$resolvedGit ' +
          args.join(' ') +
          ' exited with code ${result.exitCode}: ${result.stderr}';
    }

    if (verbose) {
      print('$resolvedGit ' +
          args.join(' ') +
          ' exited with code ${result.exitCode}');
      if (result.stdout.isNotEmpty) print('STDOUT: ${result.stdout}');
      if (result.stderr.isNotEmpty) print('STDERR: ${result.stderr}');
    }

    if (dep.ref != null) {
      var s = '$resolvedGit reset --hard ${dep.ref}';
      var reset = await Process.run(resolvedGit, ['reset', '--hard', dep.ref],
          workingDirectory: dir.absolute.path);
      if (reset.exitCode != 0) {
        s = '$resolvedGit checkout ${dep.ref}';
        var chk = await Process.run(resolvedGit, ['checkout', dep.ref],
            workingDirectory: dir.absolute.path);
        if (chk.exitCode != 0) {
          // Try a tag...
          var s = '$resolvedGit checkout tags/${dep.ref}';
          var tag = await Process.run(
              resolvedGit, ['checkout', 'tags/${dep.ref}'],
              workingDirectory: dir.absolute.path);

          if (tag.exitCode != 0)
            throw '$s exited with code ${result.exitCode}';
          else if (verbose) {
            print('$s exited with code ${tag.exitCode}');
            if (tag.stdout.isNotEmpty) print('STDOUT: ${tag.stdout}');
            if (tag.stderr.isNotEmpty) print('STDERR: ${tag.stderr}');
          }
        }

        if (verbose) {
          print('$s exited with code ${chk.exitCode}');
          if (chk.stdout.isNotEmpty) print('STDOUT: ${chk.stdout}');
          if (chk.stderr.isNotEmpty) print('STDERR: ${chk.stderr}');
        }
      } else if (verbose) {
        print('$s exited with code ${reset.exitCode}');
        if (reset.stdout.isNotEmpty) print('STDOUT: ${reset.stdout}');
        if (reset.stderr.isNotEmpty) print('STDERR: ${reset.stderr}');
      }
    }

    return await PubSpec.load(dir);
  } else
    throw new ArgumentError('Invalid dependency: $dep');
}

Future identifyRequirements(
    String packageName,
    PubSpec pubspec,
    List<String> processed,
    Map<String, List<DependencyRequirement>> requirements,
    Map<String, VersionConstraint> sdkConstraints,
    Directory tempDir,
    bool verbose) async {
  var stub = packageName.split('->').last;
  if (processed.contains(stub)) return;

  if (verbose) print('Identifying requirements of $packageName...');
  processed.add(pubspec.name);

  // Add sdk constraint
  if (pubspec.environment?.sdkConstraint != null)
    sdkConstraints.putIfAbsent(
        packageName, () => pubspec.environment.sdkConstraint);

  // Add dependencies of this package.
  pubspec.dependencies.forEach((name, dep) {
    _addDep(name, new DependencyRequirement(packageName, dep), requirements);
  });

  // Next, check for any packages that haven't been crawled yet.

  var futures = [];
  pubspec.dependencies.forEach((name, dep) {
    if (!processed.contains(name)) {
      futures.add(
          resolvePubspec(name, dep, tempDir, verbose).then((pubspec) async {
        await identifyRequirements('$packageName->$name', pubspec, processed,
            requirements, sdkConstraints, tempDir, verbose);
      }));
    }
  });

  await Future.wait(futures);
}
