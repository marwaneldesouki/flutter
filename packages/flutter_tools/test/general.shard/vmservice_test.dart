// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/device.dart';
import 'package:flutter_tools/src/version.dart';
import 'package:flutter_tools/src/vmservice.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as rpc;
import 'package:mockito/mockito.dart';
import 'package:platform/platform.dart';
import 'package:quiver/testing/async.dart';

import '../src/common.dart';
import '../src/context.dart';
import '../src/mocks.dart';

class MockPeer implements rpc.Peer {

  Function _versionFn = (dynamic _) => null;

  @override
  rpc.ErrorCallback get onUnhandledError => null;

  @override
  Future<dynamic> get done async {
    throw 'unexpected call to done';
  }

  @override
  bool get isClosed {
    throw 'unexpected call to isClosed';
  }

  @override
  Future<dynamic> close() async {
    throw 'unexpected call to close()';
  }

  @override
  Future<dynamic> listen() async {
    // this does get called
  }

  @override
  void registerFallback(dynamic callback(rpc.Parameters parameters)) {
    throw 'unexpected call to registerFallback';
  }

  @override
  void registerMethod(String name, Function callback) {
    registeredMethods.add(name);
    if (name == 'flutterVersion') {
      _versionFn = callback;
    }
  }

  @override
  void sendNotification(String method, [ dynamic parameters ]) {
    // this does get called
    sentNotifications.putIfAbsent(method, () => <dynamic>[]).add(parameters);
  }

  Map<String, List<dynamic>> sentNotifications = <String, List<dynamic>>{};
  List<String> registeredMethods = <String>[];

  bool isolatesEnabled = false;

  Future<void> _getVMLatch;
  Completer<void> _currentGetVMLatchCompleter;

  void tripGetVMLatch() {
    final Completer<void> lastCompleter = _currentGetVMLatchCompleter;
    _currentGetVMLatchCompleter = Completer<void>();
    _getVMLatch = _currentGetVMLatchCompleter.future;
    lastCompleter?.complete();
  }

  int returnedFromSendRequest = 0;

  @override
  Future<dynamic> sendRequest(String method, [ dynamic parameters ]) async {
    if (method == 'getVM') {
      await _getVMLatch;
    }
    await Future<void>.delayed(Duration.zero);
    returnedFromSendRequest += 1;
    if (method == 'getVM') {
      return <String, dynamic>{
        'type': 'VM',
        'name': 'vm',
        'architectureBits': 64,
        'targetCPU': 'x64',
        'hostCPU': '      Intel(R) Xeon(R) CPU    E5-1650 v2 @ 3.50GHz',
        'version': '2.1.0-dev.7.1.flutter-45f9462398 (Fri Oct 19 19:27:56 2018 +0000) on "linux_x64"',
        '_profilerMode': 'Dart',
        '_nativeZoneMemoryUsage': 0,
        'pid': 103707,
        'startTime': 1540426121876,
        '_embedder': 'Flutter',
        '_maxRSS': 312614912,
        '_currentRSS': 33091584,
        'isolates': isolatesEnabled ? <dynamic>[
          <String, dynamic>{
            'type': '@Isolate',
            'fixedId': true,
            'id': 'isolates/242098474',
            'name': 'main.dart:main()',
            'number': 242098474,
          },
        ] : <dynamic>[],
      };
    }
    if (method == 'getIsolate') {
      return <String, dynamic>{
        'type': 'Isolate',
        'fixedId': true,
        'id': 'isolates/242098474',
        'name': 'main.dart:main()',
        'number': 242098474,
        '_originNumber': 242098474,
        'startTime': 1540488745340,
        '_heaps': <String, dynamic>{
          'new': <String, dynamic>{
            'used': 0,
            'capacity': 0,
            'external': 0,
            'collections': 0,
            'time': 0.0,
            'avgCollectionPeriodMillis': 0.0,
          },
          'old': <String, dynamic>{
            'used': 0,
            'capacity': 0,
            'external': 0,
            'collections': 0,
            'time': 0.0,
            'avgCollectionPeriodMillis': 0.0,
          },
        },
      };
    }
    if (method == '_flutter.listViews') {
      return <String, dynamic>{
        'type': 'FlutterViewList',
        'views': isolatesEnabled ? <dynamic>[
          <String, dynamic>{
            'type': 'FlutterView',
            'id': '_flutterView/0x4a4c1f8',
            'isolate': <String, dynamic>{
              'type': '@Isolate',
              'fixedId': true,
              'id': 'isolates/242098474',
              'name': 'main.dart:main()',
              'number': 242098474,
            },
          },
        ] : <dynamic>[],
      };
    }
    if (method == 'flutterVersion') {
      return _versionFn(parameters);
    }
    return null;
  }

  @override
  dynamic withBatch(dynamic callback()) {
    throw 'unexpected call to withBatch';
  }
}

void main() {
  MockStdio mockStdio;
  final MockFlutterVersion mockVersion = MockFlutterVersion();
  group('VMService', () {

    setUp(() {
      mockStdio = MockStdio();
    });

    testUsingContext('fails connection eagerly in the connect() method', () async {
      FakeAsync().run((FakeAsync time) {
        bool failed = false;
        final Future<VMService> future = VMService.connect(Uri.parse('http://host.invalid:9999/'));
        future.whenComplete(() {
          failed = true;
        });
        time.elapse(const Duration(seconds: 5));
        expect(failed, isFalse);
        expect(mockStdio.writtenToStdout.join(''), '');
        expect(mockStdio.writtenToStderr.join(''), '');
        time.elapse(const Duration(seconds: 5));
        expect(failed, isFalse);
        expect(mockStdio.writtenToStdout.join(''), 'This is taking longer than expected...\n');
        expect(mockStdio.writtenToStderr.join(''), '');
      });
    }, overrides: <Type, Generator>{
      Logger: () => StdoutLogger(
        outputPreferences: OutputPreferences.test(),
        stdio: mockStdio,
        terminal: AnsiTerminal(stdio: mockStdio, platform: const LocalPlatform()),
        timeoutConfiguration: const TimeoutConfiguration(),
        platform: FakePlatform(),
      ),
      WebSocketConnector: () => (String url, {CompressionOptions compression}) async => throw const SocketException('test'),
    });

    testUsingContext('refreshViews', () {
      FakeAsync().run((FakeAsync time) {
        bool done = false;
        final MockPeer mockPeer = MockPeer();
        expect(mockPeer.returnedFromSendRequest, 0);
        final VMService vmService = VMService(mockPeer, null, null, null, null, null, null, null);
        expect(mockPeer.sentNotifications, contains('registerService'));
        final List<String> registeredServices =
          mockPeer.sentNotifications['registerService']
            .map((dynamic service) => (service as Map<String, String>)['service'])
            .toList();
        expect(registeredServices, contains('flutterVersion'));
        vmService.getVM().then((void value) { done = true; });
        expect(done, isFalse);
        expect(mockPeer.returnedFromSendRequest, 0);
        time.elapse(Duration.zero);
        expect(done, isTrue);
        expect(mockPeer.returnedFromSendRequest, 1);

        done = false;
        mockPeer.tripGetVMLatch(); // this blocks the upcoming getVM call
        final Future<void> ready = vmService.refreshViews(waitForViews: true);
        ready.then((void value) { done = true; });
        expect(mockPeer.returnedFromSendRequest, 1);
        time.elapse(Duration.zero); // this unblocks the listViews call which returns nothing
        expect(mockPeer.returnedFromSendRequest, 2);
        time.elapse(const Duration(milliseconds: 50)); // the last listViews had no views, so it waits 50ms, then calls getVM
        expect(done, isFalse);
        expect(mockPeer.returnedFromSendRequest, 2);
        mockPeer.tripGetVMLatch(); // this unblocks the getVM call
        expect(mockPeer.returnedFromSendRequest, 2);
        time.elapse(Duration.zero); // here getVM returns with no isolates and listViews returns no views
        expect(mockPeer.returnedFromSendRequest, 4);
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);
        expect(mockPeer.returnedFromSendRequest, 4);
        mockPeer.tripGetVMLatch(); // this unblocks the getVM call
        expect(mockPeer.returnedFromSendRequest, 4);
        time.elapse(Duration.zero); // here getVM returns with no isolates and listViews returns no views
        expect(mockPeer.returnedFromSendRequest, 6);
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);
        expect(mockPeer.returnedFromSendRequest, 6);
        mockPeer.tripGetVMLatch(); // this unblocks the getVM call
        expect(mockPeer.returnedFromSendRequest, 6);
        time.elapse(Duration.zero); // here getVM returns with no isolates and listViews returns no views
        expect(mockPeer.returnedFromSendRequest, 8);
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);
        expect(mockPeer.returnedFromSendRequest, 8);
        mockPeer.tripGetVMLatch(); // this unblocks the getVM call
        expect(mockPeer.returnedFromSendRequest, 8);
        time.elapse(Duration.zero); // here getVM returns with no isolates and listViews returns no views
        expect(mockPeer.returnedFromSendRequest, 10);
        const String message = 'Flutter is taking longer than expected to report its views. Still trying...\n';
        expect(mockStdio.writtenToStdout.join(''), message);
        expect(mockStdio.writtenToStderr.join(''), '');
        time.elapse(const Duration(milliseconds: 50)); // so refreshViews waits another 50ms
        expect(done, isFalse);
        expect(mockPeer.returnedFromSendRequest, 10);
        mockPeer.isolatesEnabled = true;
        mockPeer.tripGetVMLatch(); // this unblocks the getVM call
        expect(mockPeer.returnedFromSendRequest, 10);
        time.elapse(Duration.zero); // now it returns an isolate and the listViews call returns views
        expect(mockPeer.returnedFromSendRequest, 13);
        expect(done, isTrue);
        expect(mockStdio.writtenToStdout.join(''), message);
        expect(mockStdio.writtenToStderr.join(''), '');
      });
    }, overrides: <Type, Generator>{
      Logger: () => StdoutLogger(
        outputPreferences: outputPreferences,
        terminal: AnsiTerminal(stdio: mockStdio, platform: const LocalPlatform()),
        stdio: mockStdio,
        timeoutConfiguration: const TimeoutConfiguration(),
        platform: FakePlatform(),
      ),
    });

    testUsingContext('registers hot UI method', () {
      FakeAsync().run((FakeAsync time) {
        final MockPeer mockPeer = MockPeer();
        Future<void> reloadMethod({ String classId, String libraryId }) async {}
        VMService(mockPeer, null, null, null, null, null, null, reloadMethod);

        expect(mockPeer.registeredMethods, contains('reloadMethod'));
      });
    }, overrides: <Type, Generator>{
      Logger: () => StdoutLogger(
        outputPreferences: outputPreferences,
        terminal: AnsiTerminal(stdio: mockStdio, platform: const LocalPlatform()),
        stdio: mockStdio,
        timeoutConfiguration: const TimeoutConfiguration(),
        platform: FakePlatform(),
      ),
    });

    testUsingContext('registers flutterMemoryInfo service', () {
      FakeAsync().run((FakeAsync time) {
        final MockDevice mockDevice = MockDevice();
        final MockPeer mockPeer = MockPeer();
        Future<void> reloadSources(String isolateId, { bool pause, bool force}) async {}
        VMService(mockPeer, null, null, reloadSources, null, null, mockDevice, null);

        expect(mockPeer.registeredMethods, contains('flutterMemoryInfo'));
      });
    }, overrides: <Type, Generator>{
      Logger: () => StdoutLogger(
        outputPreferences: outputPreferences,
        terminal: AnsiTerminal(stdio: mockStdio, platform: const LocalPlatform()),
        stdio: mockStdio,
        timeoutConfiguration: const TimeoutConfiguration(),
        platform: FakePlatform(),
      ),
    });

    testUsingContext('returns correct FlutterVersion', () {
      FakeAsync().run((FakeAsync time) async {
        final MockPeer mockPeer = MockPeer();
        VMService(mockPeer, null, null, null, null, null, MockDevice(), null);

        expect(mockPeer.registeredMethods, contains('flutterVersion'));
        expect(await mockPeer.sendRequest('flutterVersion'), equals(mockVersion.toJson()));
      });
    }, overrides: <Type, Generator>{
      FlutterVersion: () => mockVersion,
    });
  });
}

class MockDevice extends Mock implements Device {}

class MockFlutterVersion extends Mock implements FlutterVersion {
  @override
  Map<String, Object> toJson() => const <String, Object>{'Mock': 'Version'};
}
