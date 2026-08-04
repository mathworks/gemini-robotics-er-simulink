classdef tGeminiERVerify < matlab.unittest.TestCase
    % tGeminiERVerify  Integration tests for GeminiERVerify using saved fixtures.
    %
    %   Requires GEMINI_API_KEY and test/geminiVerifyPassData.mat.
    %   Both are checked in TestClassSetup; all tests skip if either is absent.
    %
    %   Run:
    %     runtests("test/tGeminiERVerify.m")

    methods (TestClassSetup)
        function setup(tc)
            projectstartup;
            tc.assumeNotEmpty(getenv('GEMINI_API_KEY'), ...
                'GEMINI_API_KEY not set - skipping GeminiERVerify tests');
            fixturePath = fullfile(fileparts(mfilename('fullpath')), 'geminiVerifyPassData.mat');
            tc.assumeTrue(isfile(fixturePath), ...
                'geminiVerifyPassData.mat not found - skipping GeminiERVerify tests');
        end
    end

    methods (Test)
        function passOnSuccessfulTask(tc)
            % Load fixture: successful task run (imageFirst, imageLast, taskPrompt).
            fixturePath = fullfile(fileparts(mfilename('fullpath')), 'geminiVerifyPassData.mat');
            data = load(fixturePath, 'imageFirst', 'imageLast', 'taskPrompt');

            % Set up GeminiERVerify with before/after images.
            mode               = GeminiERVerify();
            mode.Images{1}     = data.imageFirst;
            mode.Images{end}   = data.imageLast;
            mode.TaskPrompt    = data.taskPrompt;
            mode.ScenarioPrompt = "";

            [~, userPrompt, systemPrompt] = mode.preprocess();

            % Call Gemini.
            mod    = py.importlib.import_module('geminiClient');
            py.importlib.reload(mod);
            client = mod.GeminiClient(getenv('GEMINI_API_KEY'));

            pyImgList = py.list({py.numpy.array(data.imageFirst), ...
                                  py.numpy.array(data.imageLast)});
            raw = string(client.call(pyImgList, userPrompt, systemPrompt, int32(0)));

            out = mode.postprocess(raw);

            tc.verifyTrue(out.pass, ...
                sprintf('Expected pass=true for successful task. Diagnostics: %s', out.diagnostics));
        end
    end
end
