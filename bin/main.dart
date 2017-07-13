import 'dart:io';
import 'package:args/args.dart';
import 'package:console/console.dart';
import 'package:pubspec/pubspec.dart';
import 'package:pub_mediator/pub_mediator.dart';
import 'args.dart';

main(List<String> args) async {
  try {
    var result = argParser.parse(args);
    if (result['help']) {
      printHelp(stdout);
    } else {
      var dir = result.rest.isEmpty
          ? Directory.current
          : new Directory(result.rest.first);
      var pubspec = await PubSpec.load(dir);
      var diagnosis =
          await diagnoseConflicts(pubspec, verbose: result['verbose']);
      describeDiagnosis(diagnosis);
      new TextPen().normal().text('Done at ${new DateTime.now()}.').call();
    }
  } on ArgParserException {
    printHelp(stderr);
    exitCode = 1;
  }
}

void printHelp(IOSink sink) {
  sink.writeln('usage: mediator [options...]');
  sink.writeln('\nOptions:');
  sink.writeln(argParser.usage);
}

void describeDiagnosis(DependencyDiagnosis diagnosis) {
  if (diagnosis.conflicts.isEmpty) {
    var p = new TextPen()..green();
    p.text(
        '${Icon.CHECKMARK} No dependency conflicts found! You should be good to go.')();
  } else {
    var p = new TextPen()..red();
    var noun = diagnosis.conflicts.length == 1 ? 'conflict' : 'conflicts';
    p.text(
        '${Icon.BALLOT_X} Found ${diagnosis.conflicts.length} dependency $noun:')();

    for (var conflict in diagnosis.conflicts) {
      p.reset();

      if (conflict.type == DependencyConflictType.SDK) {
        p
            .text('You are running ')
            .cyan()
            .text('Dart SDK version ${Platform.version}.')
              ..call()
              ..reset();

        for (var req in conflict.sdkRequirements) {
          p
              .text('  * ${req.packageName} requires SDK ')
              .red()
              .text(req.sdk.toString())
                ..call()
                ..reset();
        }
      } else {
        p
            .text(
                'Found ${conflict.requirements.length} mismatching dependencies on ')
            .cyan()
            .text('package:${conflict.packageName}')
            .normal()
            .text(':')
              ..call()
              ..reset();

        for (var req in conflict.requirements) {
          var dep = req.dependency;
          p.text('  * ${req.packageName} requires  ').red();

          if (dep is HostedReference) {
            p.text(dep.versionConstraint.toString());
          } else if (dep is GitReference) {
            p.text('git://${dep.url}');
            if (dep.ref != null) p.text('#${dep.ref}');
          } else if (dep is PathReference) {
            p.text('path ${dep.path}');
          }

          p
            ..call()
            ..reset();
        }
      }
    }
  }
}
