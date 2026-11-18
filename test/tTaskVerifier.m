classdef tTaskVerifier < matlab.unittest.TestCase
    % tTaskVerifier  Tests for the TaskVerifier reasoner.
    %
    %   Offline tests exercise preprocess/postprocess on canned answers. The
    %   integration tests call Gemini on images/frame_rgb.png (before) and
    %   images/frame_rgb_after.png (after) and are skipped without Gemini credentials.
    %
    %   Run:
    %     runtests("test/tTaskVerifier.m")

    methods (TestClassSetup)
        function setupPath(tc)
            import matlab.unittest.fixtures.PathFixture
            tc.applyFixture(PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), '..')));
        end
    end

    methods (Test)
        function preprocessSendsBeforeAndAfterImages(tc)
            before  = zeros(4, 4, 3, 'uint8');
            after   = ones(4, 4, 3, 'uint8');
            context = tTaskVerifier.makeContext({before, after}, "Move the red tee", 1);

            [images, userPrompt, instructions] = TaskVerifier().preprocess(context);

            tc.verifyEqual(images, {before, after});
            tc.verifyEqual(userPrompt, "Task: ""Move the red tee""");
            tc.verifySubstring(instructions, "Image 1");
        end

        function preprocessResizesEachImage(tc)
            before  = zeros(720, 1280, 3, 'uint8');
            after   = ones(720, 1280, 3, 'uint8');
            context = tTaskVerifier.makeContext({before, after}, "", 1);

            images = TaskVerifier(ResizeImageTo=[NaN 640]).preprocess(context);

            tc.verifyNumElements(images, 2);
            tc.verifySize(images{1}, [360, 640, 3]);
            tc.verifySize(images{2}, [360, 640, 3]);
        end

        function postprocessSavesArtifacts(tc)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            folder   = tc.applyFixture(TemporaryFolderFixture).Folder;
            verifier = TaskVerifier(SaveArtifacts=true, WriteArtifactsDir=folder);
            context  = tTaskVerifier.makeContext( ...
                {zeros(100, 200, 3, 'uint8'), ones(100, 200, 3, 'uint8')}, "", 1);

            verifier.postprocess('{"pass": true, "diagnostics": "Done."}', context);

            for name = ["verify.png", "verify_before.png", "verify_after.png"]
                tc.verifyTrue(isfile(fullfile(folder, name)), name);
            end
            saved = jsondecode(fileread(fullfile(folder, "verify.json")));
            tc.verifyTrue(saved.pass);
            tc.verifyEqual(saved.diagnostics, 'Done.');
        end

        function postprocessParsesVerdict(tc)
            context = tTaskVerifier.makeContext({}, "", 2);
            raw = '{"pass": false, "diagnostics": "The red tee fitting was not placed."}';

            context = TaskVerifier().postprocess(raw, context);

            tc.verifyEqual(context.Output.attempt, 2);
            tc.verifyFalse(context.Output.pass);
            tc.verifyEqual(context.Output.diagnostics, "The red tee fitting was not placed.");
            tc.verifyEqual(fieldnames(context.Output), fieldnames(TaskVerifier().outputStruct()));
        end

        function postprocessFallsBackToPassOnInvalidJson(tc)
            context = tTaskVerifier.makeContext({}, "", 1);

            context = TaskVerifier().postprocess("not json", context);

            tc.verifyTrue(context.Output.pass);
            tc.verifyEqual(context.Output.diagnostics, "not json");
        end

        function passOnSuccessfulTask(tc)
            % After frame: gray elbow on the right table, green tee on the left.
            output = tTaskVerifier.verifyScene(tc, ...
                "Move the gray elbow fitting to the right table. " + ...
                "Move the green tee fitting to the left table. " + ...
                "Leave all other fittings in the bin");

            tc.verifyTrue(output.pass, ...
                sprintf('Expected pass=true for successful task. Diagnostics: %s', ...
                output.diagnostics));
        end

        function failOnWrongObjectPlaced(tc)
            % After frame has the green tee, not the cyan cross, on the left table.
            output = tTaskVerifier.verifyScene(tc, ...
                "Move the gray elbow fitting to the right table. " + ...
                "Move the cyan cross fitting to the left table. " + ...
                "Leave all other fittings in the bin");

            tc.verifyFalse(output.pass, ...
                sprintf('Expected pass=false when the wrong fitting was placed. Diagnostics: %s', ...
                output.diagnostics));
        end
    end

    methods (Static, Access = private)
        function output = verifyScene(tc, task)
            % Run TaskVerifier through Gemini on images/frame_rgb.png -> images/frame_rgb_after.png.
            tc.assumeTrue(GeminiClient.hasCredentials(), ...
                'No Gemini credentials configured - skipping TaskVerifier integration test');
            imageDir = fullfile(fileparts(mfilename('fullpath')), '..', 'images');
            before   = imread(fullfile(imageDir, 'frame_rgb.png'));
            after    = imread(fullfile(imageDir, 'frame_rgb_after.png'));
            context  = tTaskVerifier.makeContext({before, after}, task, 1);

            verifier = TaskVerifier(ResizeImageTo=[NaN 640]);
            [images, userPrompt, instructions] = verifier.preprocess(context);
            rawResponse = GeminiClient().call(userPrompt, images, Instructions=instructions);
            context = verifier.postprocess(rawResponse, context);
            output  = context.Output;
        end

        function context = makeContext(images, task, attempt)
            % Minimal reasoning-chain context as RobotReasonerBlock seeds it.
            context = struct( ...
                'Task',     string(task), ...
                'Images',   {images}, ...
                'Attempt',  attempt, ...
                'Data',     struct(), ...
                'Previous', struct(), ...
                'Output',   struct());
        end
    end
end
