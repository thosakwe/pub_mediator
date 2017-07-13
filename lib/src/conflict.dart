import 'requirement.dart';

class DependencyConflict {
  final DependencyConflictType type;
  final String packageName;
  final List<DependencyRequirement> requirements = [];
  final List<SdkRequirement> sdkRequirements = [];
  DependencyConflict(this.type, {this.packageName});
}

enum DependencyConflictType { PACKAGE, SDK }
