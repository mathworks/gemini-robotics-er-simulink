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
            projectstartup;
            penv = pyenv;
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
            % Verify GeminiClient can be instantiated with a dummy key
            module = py.importlib.import_module('geminiClient');
            testCase.verifyWarningFree( ...
                @() module.GeminiClient('dummy-key'), ...
                'GeminiClient constructor raised a warning');
        end
    end
end
