import 'package:args/args.dart';

final ArgParser argParser = new ArgParser()
  ..addFlag('help', abbr: 'h', help: 'Print this help information.')
  ..addFlag('verbose', abbr: 'v', help: 'Print verbose output.')
  ..addOption('concurrency',
      abbr: 'j',
      help:
          'The number of worker isolates to spawn. Defaults to (# processors on machine) - 1.');
