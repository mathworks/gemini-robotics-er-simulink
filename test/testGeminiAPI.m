classdef testGeminiAPI < matlab.unittest.TestCase
    % Tests that the Gemini Robotics ER API is reachable with the configured key.
    %
    % All tests are skipped automatically if GEMINI_API_KEY is not set.
    %
    %   Run:
    %     runtests("test/testGeminiAPI.m")

    methods (TestClassSetup)
        function setupPythonEnvironment(testCase)
            projectstartup;
            apiKey = getenv('GEMINI_API_KEY');
            testCase.assumeNotEmpty(apiKey, ...
                'GEMINI_API_KEY not set - skipping Gemini API tests');
        end
    end

    methods (Test)
        function verifyGeminiERModelAccessible(testCase)
            % Send a dummy 10x10 white image to gemini-robotics-er-1.6-preview
            % and verify a non-empty response is returned.
            apiKey = getenv('GEMINI_API_KEY');

            % Build a 10x10 white image as a numpy array
            np     = py.importlib.import_module('numpy');
            pyImg  = np.ones(py.tuple({int32(10), int32(10), int32(3)}), ...
                            pyargs('dtype', np.uint8)) * uint8(255);

            mod    = py.importlib.import_module('geminiClient');
            py.importlib.reload(mod);
            client = mod.GeminiClient(apiKey);

            response = string(client.call(py.list({pyImg}), 'Reply with valid JSON: {"pass": true}'));

            testCase.verifyNotEmpty(response, ...
                'gemini-robotics-er-1.6-preview returned an empty response');
            testCase.verifySubstring(response, '{', ...
                'Response does not look like JSON');
        end
    end
end
