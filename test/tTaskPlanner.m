classdef tTaskPlanner < matlab.unittest.TestCase
%tTaskPlanner  Tests for the TaskPlanner reasoner and RobotReasonerBlock + pixelPlanToWorldBlock.
%
% Offline tests exercise preprocess/postprocess on canned Gemini answers.
% The integration test calls the real Gemini API on the cam2 fixture and is
% skipped if no Gemini credentials are configured.
%
% Run:
%   runtests("test/tTaskPlanner.m")
%
% <Feature> TaskPlanner </Feature>
% <TestType> unit, integration </TestType>
% <Release> R2026a </Release>

    properties (Constant)
        MaxDetections = 8
        XRange        = [0.20, 0.70]   % expected world X (m) — bin depth
        YRange        = [-0.40, 0.50]  % expected world Y (m) — lateral
    end

    methods (TestClassSetup)
        function setupPath(testCase)
            import matlab.unittest.fixtures.PathFixture
            testCase.applyFixture(PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), '..')));
        end
    end

    methods (Test)

        function preprocessSendsResizedFrameAndTask(testCase)
            planner = TaskPlanner(ResizeImageTo=[NaN 640]);
            context = tTaskPlanner.makeContext(zeros(720, 1280, 3, 'uint8'), ...
                "Place the red tee on the left table", 1);

            [image, userPrompt, instructions] = planner.preprocess(context);

            testCase.verifySize(image, [360, 640, 3]);
            testCase.verifyEqual(userPrompt, "Instruction: Place the red tee on the left table");
            testCase.verifySubstring(instructions, "drop_center_2d");
            testCase.verifyTrue(endsWith(instructions, "explanatory text."), ...
                'JsonRule must close the system instructions');
        end

        function postprocessMapsPointsToFramePixels(testCase)
            planner = TaskPlanner(MaxItems=4);
            context = tTaskPlanner.makeContext(zeros(720, 1280, 3, 'uint8'), "", 3);
            % Gemini answers [y, x]; the bus carries [x y] pixels.
            raw = ['[{"label": "red tee fitting", "center_2d": [500, 250], ' ...
                   '"drop_center_2d": [100, 200], "pick_priority": 2}, ' ...
                   '{"label": "blue cross fitting", "center_2d": [1000, 1000], "pick_priority": 1}]'];

            context = planner.postprocess(raw, context);
            out = context.Output;

            testCase.verifyEqual(out.attempt, 3);
            testCase.verifyEqual(out.count, 2);
            testCase.verifyEqual(out.pick_center(1, :), [320, 360]);
            testCase.verifyEqual(out.drop_center(1, :), [256, 72]);
            testCase.verifyEqual(out.pick_center(2, :), [1280, 720]);
            testCase.verifyEqual(out.drop_center(2, :), [0, 0]);
            testCase.verifyEqual(out.pick_order(1:2), int32([2; 1]));
            testCase.verifyEqual(context.Data.plan(1).label, "red tee fitting");
            tTaskPlanner.verifyMatchesPrototype(testCase, out, planner.outputStruct());
        end

        function postprocessFallsBackToPointAndBoxKeys(testCase)
            planner = TaskPlanner();
            context = tTaskPlanner.makeContext(zeros(1000, 1000, 3, 'uint8'), "", 1);
            raw = ['[{"point": [100, 200], "drop_box_2d": [400, 600, 500, 700]}, ' ...
                   '{"box_2d": [0, 0, 200, 400]}]'];

            context = planner.postprocess(raw, context);
            out = context.Output;

            testCase.verifyEqual(out.pick_center(1, :), [200, 100]);
            testCase.verifyEqual(out.drop_center(1, :), [650, 450]);
            testCase.verifyEqual(out.pick_center(2, :), [200, 100]);
        end

        function preprocessKeepsOriginalSizeByDefault(testCase)
            frame   = zeros(720, 1280, 3, 'uint8');
            context = tTaskPlanner.makeContext(frame, "", 1);

            [image, userPrompt] = TaskPlanner().preprocess(context);

            testCase.verifyEqual(image, frame);
            testCase.verifyEqual(userPrompt, "Detect all objects visible in this image.");
        end

        function postprocessMapsAgainstFullFrameAfterResize(testCase)
            % The resize only affects the sent image; points map to the full frame.
            planner = TaskPlanner(ResizeImageTo=[NaN 640]);
            context = tTaskPlanner.makeContext(zeros(720, 1280, 3, 'uint8'), "", 1);

            context = planner.postprocess('[{"center_2d": [1000, 1000]}]', context);

            testCase.verifyEqual(context.Output.pick_center(1, :), [1280, 720]);
            testCase.verifyEqual(context.Output.pick_order(1), int32(1));
        end

        function postprocessSavesArtifacts(testCase)
            import matlab.unittest.fixtures.TemporaryFolderFixture
            folder  = testCase.applyFixture(TemporaryFolderFixture).Folder;
            planner = TaskPlanner(SaveArtifacts=true, WriteArtifactsDir=folder);
            context = tTaskPlanner.makeContext(zeros(100, 200, 3, 'uint8'), "Move the red tee", 2);
            raw = '[{"label": "red tee", "center_2d": [500, 250], "drop_center_2d": [100, 200]}]';

            planner.postprocess(raw, context);

            testCase.verifyTrue(isfile(fullfile(folder, "plan_attempt2.png")));
            saved = jsondecode(fileread(fullfile(folder, "plan_attempt2.json")));
            testCase.verifyEqual(saved.plan.label, 'red tee');
            testCase.verifyEqual(saved.rawResponse, raw);
        end

        function postprocessDropsUnusableItemsAndCaps(testCase)
            planner = TaskPlanner(MaxItems=2);
            context = tTaskPlanner.makeContext(zeros(100, 100, 3, 'uint8'), "", 1);
            raw = ['[{"label": "no point"}, {"center_2d": [1, 2, 3]}, {"center_2d": [1500, 10]}, ' ...
                   '{"center_2d": [10, 10]}, {"center_2d": [20, 20]}, {"center_2d": [30, 30]}]'];

            context = planner.postprocess(raw, context);

            testCase.verifyNumElements(context.Data.plan, 3);
            testCase.verifyEqual(context.Output.count, 2);
        end

        function postprocessToleratesInvalidJson(testCase)
            planner = TaskPlanner();
            context = tTaskPlanner.makeContext(zeros(100, 100, 3, 'uint8'), "", 1);

            context = planner.postprocess("not json", context);

            testCase.verifyEqual(context.Output.count, 0);
            testCase.verifyEqual(context.Output.attempt, 1);
        end

        function plannerOutputBusIsCorrect(testCase)
            testCase.assumeTrue(GeminiClient.hasCredentials(), ...
                'No Gemini credentials configured - skipping Gemini integration test');

            % Load cam2 fixtures
            testDir = fullfile(fileparts(mfilename('fullpath')), 'cam2');
            imgData = imread(fullfile(testDir, '..', '..', 'images', 'frame_rgb.png'));
            loaded  = load(fullfile(testDir, 'frame_depth.mat'));
            depthM  = loaded.depthM2;

            % Define bus types required by pixelPlanToWorldBlock output type
            initPlannerGeminiER();

            % Robot Reasoner block (planning) with cam2 defaults
            planner = TaskPlanner(MaxItems=testCase.MaxDetections, ResizeImageTo=[NaN 640]);
            erBlk = RobotReasonerBlock('Reasoner', planner, ...
                'BusName', "geminiPixelDetectionsBus");

            % Create pixelPlanToWorldBlock with cam2 camera parameters
            worldBlk = pixelPlanToWorldBlock( ...
                'CameraLoc',      [0.50, 0, 1.50], ...
                'CameraRot',      [pi/2, pi/2, pi/2], ...
                'FocalLength',    750, ...
                'PrincipalPoint', [640, 360], ...
                'MaxBinDistance', 0.95, ...
                'MaxDetections',  testCase.MaxDetections);

            % Step 1: a Trigger rising edge (0 -> 1) fires the reasoning chain
            pixOut = step(erBlk, "Detect all objects in the bin.", imgData, uint8(1));

            % Step 2: project pixel detections to world frame (a fresh attempt projects)
            out = step(worldBlk, pixOut, depthM);

            % --- Structural checks on pixel detections (geminiPixelDetectionsBus) ---
            testCase.verifyEqual(pixOut.attempt, 1);
            testCase.verifyGreaterThanOrEqual(pixOut.count, 0);
            testCase.verifyLessThanOrEqual(pixOut.count, testCase.MaxDetections);
            testCase.verifySize(pixOut.pick_center, [testCase.MaxDetections, 2]);
            testCase.verifySize(pixOut.drop_center, [testCase.MaxDetections, 2]);
            testCase.verifySize(pixOut.pick_order,  [testCase.MaxDetections, 1]);
            testCase.verifyClass(pixOut.pick_order, 'int32');

            % --- Structural checks on world bus (geminiTaskPlannerBus) ---
            testCase.verifyEqual(out.attempt, 1);
            testCase.verifyGreaterThanOrEqual(out.count, 0);
            testCase.verifyLessThanOrEqual(out.count, testCase.MaxDetections);
            testCase.verifySize(out.boxes,       [testCase.MaxDetections, 4]);
            testCase.verifySize(out.world_xyz,   [testCase.MaxDetections, 3]);
            testCase.verifySize(out.depth_m,     [testCase.MaxDetections, 1]);
            testCase.verifySize(out.height_m,    [testCase.MaxDetections, 1]);
            testCase.verifySize(out.pick_order,  [testCase.MaxDetections, 1]);
            testCase.verifySize(out.drop_box_2d, [testCase.MaxDetections, 4]);
            testCase.verifySize(out.drop_xyz,    [testCase.MaxDetections, 3]);
            testCase.verifyClass(out.pick_order, 'int32');

            % --- Content checks (valid detections only) ---
            N = out.count;
            testCase.verifyGreaterThan(N, 0, 'Expected at least one detection');

            for i = 1:N
                x = out.world_xyz(i, 1);
                y = out.world_xyz(i, 2);
                testCase.verifyGreaterThanOrEqual(x, testCase.XRange(1), ...
                    sprintf('Detection %d: world X=%.3f below expected range', i, x));
                testCase.verifyLessThanOrEqual(x, testCase.XRange(2), ...
                    sprintf('Detection %d: world X=%.3f above expected range', i, x));
                testCase.verifyGreaterThanOrEqual(y, testCase.YRange(1), ...
                    sprintf('Detection %d: world Y=%.3f below expected range', i, y));
                testCase.verifyLessThanOrEqual(y, testCase.YRange(2), ...
                    sprintf('Detection %d: world Y=%.3f above expected range', i, y));
            end

            % Rows beyond count must be zero-padded
            if N < testCase.MaxDetections
                testCase.verifyEqual(out.world_xyz(N+1:end, :), ...
                    zeros(testCase.MaxDetections - N, 3), ...
                    'Rows beyond count must be zero-padded');
            end
        end

    end

    methods (Static, Access = private)
        function context = makeContext(image, task, attempt)
            % Minimal reasoning-chain context as RobotReasonerBlock seeds it.
            context = struct( ...
                'Task',     string(task), ...
                'Images',   {{image, image}}, ...
                'Attempt',  attempt, ...
                'Data',     struct(), ...
                'Previous', struct(), ...
                'Output',   struct());
        end

        function verifyMatchesPrototype(testCase, out, prototype)
            % The packed output must keep the prototype's field order, sizes, and classes (bus contract).
            testCase.verifyEqual(fieldnames(out), fieldnames(prototype));
            for name = string(fieldnames(prototype))'
                testCase.verifySize(out.(name), size(prototype.(name)), name);
                testCase.verifyClass(out.(name), class(prototype.(name)), name);
            end
        end
    end

end
