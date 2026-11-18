classdef testPythonEnv < matlab.unittest.TestCase
    % Smoke tests: verify Python installation and package imports for Gemini Robotics ER.
    %
    %   Run:
    %     runtests("test/testPythonEnv.m")

    properties (TestParameter)
        PackageName = {'google.genai', 'PIL', 'numpy'};
    end

    methods (TestClassSetup)
        function setupPythonEnvironment(testCase)
            % Configure the bundled interpreter via the shared helper (no projectstartup,
            % which also needs the IBP example on the path); the helper lives in the repo root.
            import matlab.unittest.fixtures.PathFixture
            projectRoot = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(PathFixture(projectRoot));

            penv = initPythonEnvironment;
            testCase.addTeardown(@() terminate(penv))

            pythonVersion = string(penv.Version);
            testCase.assertEqual(pythonVersion, "3.13", ...
                sprintf('Expected Python 3.13, but got %s', pythonVersion));
        end
    end

    methods (Test)
        function verifyPackageImport(testCase, PackageName)
            % Verify each required package imports without errors
            testCase.verifyWarningFree(@() py.importlib.import_module(PackageName), ...
                sprintf('Failed to import package: %s', PackageName));

            module = py.importlib.import_module(PackageName);
            testCase.verifyNotEmpty(module, ...
                sprintf('Package %s is empty or was not imported correctly', PackageName));
        end

        function verifyGeminiClientImport(testCase)
            % Verify project module geminiClient.py is importable
            testCase.verifyWarningFree(@() py.importlib.import_module('geminiClient'), ...
                'Failed to import geminiClient');

            module = py.importlib.import_module('geminiClient');
            testCase.verifyNotEmpty(module);
            testCase.verifyTrue(py.hasattr(module, '__file__'), ...
                'geminiClient does not have __file__ attribute');
        end

        function verifyGeminiClientInstantiable(testCase)
            % Verify GeminiClient can be instantiated with a dummy key in the Python environment
            environ = py.os.environ;
            oldKey = environ.pop('GEMINI_API_KEY', py.None);
            environ.update(py.dict(pyargs('GEMINI_API_KEY', 'dummy-key')));
            testCase.addTeardown(@() testPythonEnv.restoreEnv(environ, 'GEMINI_API_KEY', oldKey));
            module = py.importlib.import_module('geminiClient');
            testCase.verifyWarningFree( ...
                @() module.GeminiClient(), ...
                'GeminiClient constructor raised a warning');
        end
    end

    methods (Static, Access = private)
        function restoreEnv(environ, name, oldValue)
            % Put back (or remove) a Python environment variable changed by a test.
            if isa(oldValue, 'py.NoneType')
                environ.pop(name, py.None);
            else
                environ.update(py.dict(pyargs(name, oldValue)));
            end
        end
    end
end
