import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/build/build.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:test/test.dart';

class _MockArgResults extends Mock implements ArgResults {}

class _MockLogger extends Mock implements Logger {}

class _MockProcessResult extends Mock implements ShorebirdProcessResult {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

class _MockShorebirdProcess extends Mock implements ShorebirdProcess {}

class _MockShorebirdValidator extends Mock implements ShorebirdValidator {}

void main() {
  group(BuildAarCommand, () {
    const buildNumber = '1.0';
    const androidPackageName = 'com.example.my_flutter_module';

    late ArgResults argResults;
    late Logger logger;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdProcess shorebirdProcess;
    late ShorebirdProcessResult processResult;
    late ShorebirdValidator shorebirdValidator;
    late BuildAarCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          processRef.overrideWith(() => shorebirdProcess),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdValidatorRef.overrideWith(() => shorebirdValidator),
        },
      );
    }

    setUp(() {
      argResults = _MockArgResults();
      logger = _MockLogger();
      processResult = _MockProcessResult();
      progress = _MockProgress();
      shorebirdEnv = _MockShorebirdEnv();
      shorebirdProcess = _MockShorebirdProcess();
      shorebirdValidator = _MockShorebirdValidator();

      when(() => argResults['build-number']).thenReturn(buildNumber);
      when(() => argResults.rest).thenReturn([]);
      when(() => logger.progress(any())).thenReturn(progress);

      when(
        () => shorebirdProcess.run(
          any(),
          any(),
          runInShell: any(named: 'runInShell'),
        ),
      ).thenAnswer((invocation) async {
        return processResult;
      });

      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => shorebirdEnv.androidPackageName,
      ).thenReturn(androidPackageName);

      command = runWithOverrides(BuildAarCommand.new)
        ..testArgResults = argResults;
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('exits when validation fails', () async {
      final exception = ValidationFailedException();
      when(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: any(named: 'checkUserIsAuthenticated'),
          checkShorebirdInitialized: any(named: 'checkShorebirdInitialized'),
        ),
      ).thenThrow(exception);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(exception.exitCode.code)),
      );
      verify(
        () => shorebirdValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
          checkShorebirdInitialized: true,
        ),
      ).called(1);
    });

    test('exits with 78 if no module entry exists in pubspec.yaml', () async {
      when(() => shorebirdEnv.androidPackageName).thenReturn(null);
      final result = await runWithOverrides(command.run);
      expect(result, ExitCode.config.code);
    });

    test('exits with code 70 when building aar fails', () async {
      when(() => processResult.exitCode).thenReturn(1);
      when(() => processResult.stderr).thenReturn('oops');

      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.software.code));
      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=$buildNumber',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => progress.fail(any(that: contains('Failed to build'))),
      ).called(1);
    });

    test('exits with code 0 when building aar succeeds', () async {
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
      final result = await runWithOverrides(command.run);

      expect(result, equals(ExitCode.success.code));

      verify(
        () => shorebirdProcess.run(
          'flutter',
          [
            'build',
            'aar',
            '--no-debug',
            '--no-profile',
            '--build-number=$buildNumber',
          ],
          runInShell: any(named: 'runInShell'),
        ),
      ).called(1);
      verify(
        () => logger.info(
          '''
📦 Generated an aar at:
${lightCyan.wrap(
            p.join(
              'build',
              'host',
              'outputs',
              'repo',
              'com',
              'example',
              'my_flutter_module',
              'flutter_release',
              buildNumber,
              'flutter_release-$buildNumber.aar',
            ),
          )}''',
        ),
      ).called(1);
    });
  });
}
