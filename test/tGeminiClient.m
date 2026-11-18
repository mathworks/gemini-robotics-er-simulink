classdef tGeminiClient < matlab.unittest.TestCase
    % Smoke tests for the GeminiClient transport layer.
    %
    % All tests are skipped automatically if no Gemini credentials are configured
    % (GOOGLE_GENAI_USE_ENTERPRISE or GEMINI_API_KEY / GOOGLE_API_KEY).
    %
    %   Run:
    %     runtests("test/tGeminiClient.m")

    methods (TestClassSetup)
        function setupPythonEnvironment(testCase)
            % Python + repo root only; the API check doesn't need the IBP example.
            import matlab.unittest.fixtures.PathFixture
            projectRoot = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(PathFixture(projectRoot));

            penv = initPythonEnvironment;
            testCase.addTeardown(@() terminate(penv))

            testCase.assumeTrue(GeminiClient.hasCredentials(), ...
                "No Gemini credentials configured - skipping Gemini API tests");
        end
    end

    methods (Test)
        function modelPropertyIsSet(testCase)
            % The model id requests are sent to must be a non-empty string.
            gemini = GeminiClient();

            % Log the model serving this session.
            fprintf("Served model: %s (%s backend)\n", gemini.Model, gemini.Backend);

            testCase.verifyClass(gemini.Model, "string", ...
                "Model must be a string.");
            testCase.verifyTrue(isscalar(gemini.Model), ...
                "Model must be a scalar string.");
            testCase.verifyGreaterThan(strlength(strtrim(gemini.Model)), 0, ...
                "Model must be a non-empty id.");
        end

        function textOnlyReturnsNonEmptyString(testCase)
            % The answer must be a non-empty string.
            userPrompt = "Describe a red ball on a table.";

            gemini = GeminiClient();
            response = gemini.call(userPrompt);   % {} images -> text-only

            testCase.verifyClass(response, "string", ...
                "call() must return a string.");
            testCase.verifyTrue(isscalar(response), ...
                "call() must return a scalar string.");
            testCase.verifyGreaterThan(strlength(strtrim(response)), 0, ...
                "Text-only call returned an empty response.");
        end

        function groundingPromptReturnsThreeBoxes(testCase)
            % Exercise system instructions and image transport.
            instructions = "You are an image-grounding assistant. Reply ONLY " + ...
                "with valid JSON. Return an array of objects with ""label"" " + ...
                "and ""box_2d"" as [ymin, xmin, ymax, xmax], normalized 0-1000.";
            userPrompt = "Find the red, green, and blue boxes in the image.";
            image = 255 * ones(128, 128, 3, "uint8");
            image(32:64, 12:36, 2:3) = 0;   % Red box
            image(32:64, 52:76, [1 3]) = 0; % Green box
            image(32:64, 92:116, 1:2) = 0;  % Blue box

            gemini = GeminiClient();
            rawResponse = gemini.call(userPrompt, {image}, ...
                Instructions=instructions);

            testCase.verifyClass(rawResponse, "string", ...
                "call() must return a string.");
            testCase.verifyTrue(isscalar(rawResponse), ...
                "call() must return a scalar string.");
            testCase.verifyGreaterThan(strlength(strtrim(rawResponse)), 0, ...
                "Grounding prompt returned an empty response.");
            detections = jsondecode(rawResponse);
            testCase.verifyEqual(numel(detections), 3, ...
                "Grounding response must contain all three colored boxes.");
            boxes = reshape([detections.box_2d], 4, []).';
            testCase.verifySize(boxes, [3, 4], ...
                "Each detection must include one four-coordinate box_2d.");
        end
    end
end
