classdef tGeminiERPlan < matlab.unittest.TestCase
%tGeminiERPlan  End-to-end integration test for geminiERBlock + pixelPlanToWorldBlock.
%
% Calls geminiERBlock (GeminiERPlan mode) and pixelPlanToWorldBlock in
% standalone mode using cam2 fixtures and a real Gemini API call.
% Verifies pixel detections bus structure and world-frame coordinate
% plausibility.
%
% Requires GEMINI_API_KEY environment variable. The test fails immediately
% if the variable is not set.
%
% Run:
%   runtests("test/tGeminiERPlan.m")
%
% <Feature> geminiERBlock </Feature>
% <TestType> integration </TestType>
% <Release> R2026a </Release>

% Copyright 2026 The MathWorks, Inc.

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

        function plannerOutputBusIsCorrect(testCase)
            % Fail fast if no API key
            testCase.assertNotEmpty(getenv('GEMINI_API_KEY'), ...
                'GEMINI_API_KEY is not set');

            % Load cam2 fixtures
            testDir = fullfile(fileparts(mfilename('fullpath')), 'cam2');
            imgData = imread(fullfile(testDir, 'frame_rgb.png'));
            loaded  = load(fullfile(testDir, 'frame_depth.mat'));
            depthM  = loaded.depthM2;

            % Define bus types required by pixelPlanToWorldBlock output type
            initPlannerGeminiER();

            % Create geminiERBlock (planning mode) with cam2 defaults
            mode  = GeminiERPlan('MaxDetections', testCase.MaxDetections, ...
                                 'ApplyMask', false, 'MaxLongEdge', 640);
            erBlk = geminiERBlock('Mode', mode, 'UseEnvApiKey', true);

            % Create pixelPlanToWorldBlock with cam2 camera parameters
            worldBlk = pixelPlanToWorldBlock( ...
                'CameraLoc',      [0.50, 0, 1.50], ...
                'CameraRot',      [pi/2, pi/2, pi/2], ...
                'FocalLength',    750, ...
                'PrincipalPoint', [640, 360], ...
                'MaxBinDistance', 0.95, ...
                'MaxDetections',  testCase.MaxDetections);

            % Step 1: geminiERBlock fires on first step, returns pixel detections
            pixOut = step(erBlk, "Detect all objects in the bin.", imgData, uint8(0));

            % Step 2: project pixel detections to world frame
            out = step(worldBlk, pixOut, depthM, uint8(0));

            % --- Structural checks on pixel detections (geminiPixelDetectionsBus) ---
            testCase.verifyGreaterThanOrEqual(pixOut.count, 0);
            testCase.verifyLessThanOrEqual(pixOut.count, testCase.MaxDetections);
            testCase.verifySize(pixOut.boxes,      [testCase.MaxDetections, 4]);
            testCase.verifySize(pixOut.pick_order, [testCase.MaxDetections, 1]);
            testCase.verifySize(pixOut.drop_boxes, [testCase.MaxDetections, 4]);
            testCase.verifyClass(pixOut.pick_order, 'int32');

            % --- Structural checks on world bus (geminiTaskPlannerBus) ---
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

end
