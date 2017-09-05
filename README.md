# pub_mediator
[![Pub](https://img.shields.io/pub/v/pub_mediator.svg)](https://pub.dartlang.org/packages/pub_mediator)
[![build status](https://travis-ci.org/thosakwe/pub_mediator.svg)](https://travis-ci.org/thosakwe/pub_mediator)

Diagnoses version conflicts between dependencies in Dart packages.

Try the [Web-based version](http://mediator.thosakwe.com/)!

# About
Without `mediator`, it is rather cumbersome to resolve dependency conflicts within Dart projects.
You would receive a relatively cryptic error message that doesn't tell you much in the way of
resolving conflicts:

```
Package jaguar_serializer has no versions that match >=0.3.0 <0.4.0 derived from:
- gitter 0.1.1 depends on version ^0.3.0
```

`mediator` provides you with details about where the mismatches are:

```
✗ Found 1 dependency conflict:
Found 2 mismatching dependencies on package:crypto:
  * foo requires  <1.0.0
  * angel_auth requires  ^2.0.0
```

`mediator` also tracks nested dependencies. Dependency mismatches don't always happen at the
top level, but often within the dependencies of other dependencies.

```
✗ Found 1 dependency conflict:
Found 2 mismatching dependencies on package:crypto:
  * foo requires  <1.0.0
  * bar->baz->quux requires  ^2.0.0
```

# Installation and Usage
```bash
pub global activate pub_mediator
```

Run the following in your project root:

```bash
mediator

# Enable verbose output
mediator -v

# Print help
mediator -h
```
