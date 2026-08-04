classdef tGeminiTaskPlannerHarness < matlab.unittest.TestCase
%tGeminiTaskPlannerHarness  Integration tests for the Gemini ER Simulink harness.
%
% Runs tGeminiTaskPlannerHarness.slx with cam2 fixtures, captures the
% geminiTaskPlannerBus output via signal logging, and verifies structure
% and world-coordinate plausibility.
%
% All tests require GEMINI_API_KEY; they are skipped automatically if
% the variable is not set.
%
% Run:
%   runtests("test/tGeminiTaskPlannerHarness.m")
%
% <Feature> geminiERBlock </Feature>
% <TestType> integration </TestType>
% <Release> R2026a </Release>

% Copyright 2026 The MathWorks, Inc.

    % ---------------------------------------------------------------
    % Constants
    % ---------------------------------------------------------------
    properties (Constant)
        HarnessPath = fullfile(fileparts(mfilename('fullpath')), 'tGeminiTaskPlannerHarness.slx')
        TestDir     = fullfile(fileparts(mfilename('fullpath')), 'cam2')
        VisPath     = fullfile(fileparts(mfilename('fullpath')), 'cam2', 'detections_vis.png')
        XRange      = [0.20, 0.70]   % expected world X (m) — bin depth from robot
        YRange      = [-0.40, 0.50]  % expected world Y (m) — lateral extent
    end

    % ---------------------------------------------------------------
    % Class setup: path fixture
    % ---------------------------------------------------------------
    methods (TestClassSetup)
        function setupPath(testCase)
            import matlab.unittest.fixtures.PathFixture
            repoRoot = fullfile(fileparts(mfilename('fullpath')), '..');
            testCase.applyFixture(PathFixture(repoRoot));
        end
    end

    % ---------------------------------------------------------------
    % Per-test setup: require API key, load fixtures, open harness
    % ---------------------------------------------------------------
    methods (TestMethodSetup)
        function prepareHarness(testCase)
            testCase.assumeNotEmpty(getenv('GEMINI_API_KEY'), ...
                'GEMINI_API_KEY not set — skipping');

            img    = imread(fullfile(testCase.TestDir, 'frame_rgb.png'));
            loaded = load(fullfile(testCase.TestDir, 'frame_depth.mat'));
            assignin('base', 'tGTP_image', img);
            assignin('base', 'tGTP_depth', loaded.depthM2);

            robotSimParams;
            load_system(testCase.HarnessPath);

            ph = get_param('tGeminiTaskPlannerHarness/Pixel Plan to World', 'PortHandles');
            set_param(ph.Outport(1), ...
                'DataLogging',         'on', ...
                'DataLoggingNameMode', 'Custom', ...
                'DataLoggingName',     'Detections');
        end
    end

    % ---------------------------------------------------------------
    % Per-test teardown: close harness without saving
    % ---------------------------------------------------------------
    methods (TestMethodTeardown)
        function closeHarness(~)
            if bdIsLoaded('tGeminiTaskPlannerHarness')
                close_system('tGeminiTaskPlannerHarness', 0);
            end
        end
    end

    % ---------------------------------------------------------------
    % Tests
    % ---------------------------------------------------------------
    methods (Test)

        function detectionCountIsPositive(testCase)
            % <comment> Verify Gemini returned at least one detection </comment>
            dets = testCase.runAndExtract();
            testCase.verifyGreaterThan(dets.count, 0, ...
                'Expected at least one detection from Gemini');
        end

        function depthValuesArePositive(testCase)
            % <comment> Verify camera-to-object depth is positive for each detection </comment>
            dets = testCase.runAndExtract();
            for i = 1:dets.count
                testCase.verifyGreaterThan(dets.depth_m(i), 0, ...
                    sprintf('Detection %d has non-positive depth', i));
            end
        end

        function worldXInBinRange(testCase)
            % <comment> Verify world X coordinate is within expected bin depth range </comment>
            dets = testCase.runAndExtract();
            for i = 1:dets.count
                x = dets.world_xyz(i, 1);
                testCase.verifyGreaterThanOrEqual(x, testCase.XRange(1), ...
                    sprintf('Detection %d world X=%.3f below min %.3f', i, x, testCase.XRange(1)));
                testCase.verifyLessThanOrEqual(x, testCase.XRange(2), ...
                    sprintf('Detection %d world X=%.3f above max %.3f', i, x, testCase.XRange(2)));
            end
        end

        function worldYInBinRange(testCase)
            % <comment> Verify world Y coordinate is within expected lateral range </comment>
            dets = testCase.runAndExtract();
            for i = 1:dets.count
                y = dets.world_xyz(i, 2);
                testCase.verifyGreaterThanOrEqual(y, testCase.YRange(1), ...
                    sprintf('Detection %d world Y=%.3f below min %.3f', i, y, testCase.YRange(1)));
                testCase.verifyLessThanOrEqual(y, testCase.YRange(2), ...
                    sprintf('Detection %d world Y=%.3f above max %.3f', i, y, testCase.YRange(2)));
            end
        end

        function boxesAreWithinImageBounds(testCase)
            % <comment> Verify all bounding boxes lie within the 720x1280 image </comment>
            dets = testCase.runAndExtract();
            H = 720; W = 1280;
            for i = 1:dets.count
                box = dets.boxes(i,:);  % [y_min x_min y_max x_max]
                testCase.verifyGreaterThanOrEqual(box(1), 0);
                testCase.verifyGreaterThanOrEqual(box(2), 0);
                testCase.verifyLessThanOrEqual(box(3), H);
                testCase.verifyLessThanOrEqual(box(4), W);
            end
        end

        function paddedRowsAreZero(testCase)
            % <comment> Verify rows beyond count are zero-padded </comment>
            dets = testCase.runAndExtract();
            N = dets.count;
            if N < size(dets.boxes, 1)
                testCase.verifyEqual(dets.boxes(N+1:end, :), ...
                    zeros(size(dets.boxes, 1) - N, 4), ...
                    'Rows beyond count should be zero-padded');
            end
        end

        function visualizationImageIsSaved(testCase)
            % <comment> Verify detection visualisation image is created </comment>
            dets = testCase.runAndExtract();
            img  = imread(fullfile(testCase.TestDir, 'frame_rgb.png'));
            visualizeDetections(img, dets, SavePath=testCase.VisPath);
            testCase.verifyTrue(isfile(testCase.VisPath), ...
                'Visualisation image was not saved');
        end

    end

    % ---------------------------------------------------------------
    % Private helpers
    % ---------------------------------------------------------------
    methods (Access = private)

        function dets = runAndExtract(~)
            simOut = sim('tGeminiTaskPlannerHarness', ...
                'StopTime',          '0.1', ...
                'Solver',            'FixedStepDiscrete', ...
                'FixedStep',         '0.1', ...
                'SignalLogging',     'on',   ...
                'SignalLoggingName', 'logsout');

            % Bus logged as struct of timeseries (one per bus element)
            vals = simOut.logsout.getElement('Detections').Values;

            dets.count     = vals.count.Data(end);
            dets.boxes     = squeeze(vals.boxes.Data(:,:,end));
            dets.world_xyz = squeeze(vals.world_xyz.Data(:,:,end));
            dets.depth_m   = squeeze(vals.depth_m.Data(:,end));
        end

    end

end
