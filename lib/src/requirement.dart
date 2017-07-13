import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec/pubspec.dart';

class DependencyRequirement {
  final String packageName;
  final DependencyReference dependency;
  DependencyRequirement(this.packageName, this.dependency);
}

class SdkRequirement {
  final String packageName;
  final VersionConstraint sdk;

  SdkRequirement(this.packageName, this.sdk);
}