classdef tDetectionsToWorld < matlab.unittest.TestCase
%tDetectionsToWorld  Tests for detectionsToWorld pixel -> world back-projection.
%
% Uses the cam2 camera configuration. The fixture test reads saved
% detections and depth from test/cam2/; the rest use synthetic depth maps.
% No API key required.
%
%   runtests("test/tDetectionsToWorld.m")
%
% <Feature> detectionsToWorld </Feature>
% <TestType> unit </TestType>
% <Release> R2026a </Release>

    % -------------------------------------------------------------------
    % Constants
    % -------------------------------------------------------------------
    properties (Constant)
        % Camera configuration
        Cam2 = struct( ...
            'f',          750, ...
            'cx',         640, ...
            'cy',         360, ...
            'camera_loc', [0.50, 0, 1.50], ...
            'camera_rot', [pi/2, pi/2, pi/2])

        MaxBinDistance = 0.95    % cam2: depth to bin floor (m)

        % Expected world-frame bounds for bin objects
        XRange = [0.20, 0.70]    % world X (m) — bin depth from robot
        YRange = [-0.40, 0.50]   % world Y (m) — lateral extent

        % Expected world-frame bounds for drop workspace (bin + both tables)
        DropXRange = [-0.20, 1.00]
        DropYRange = [-0.90, 0.90]
    end

    % -------------------------------------------------------------------
    % Class setup
    % -------------------------------------------------------------------
    methods (TestClassSetup)
        function setupPath(testCase)
            import matlab.unittest.fixtures.PathFixture
            % repo root is one level above test/
            testCase.applyFixture(PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), '..')));
        end
    end

    methods (Test)

        function pickWorldXYInBin(testCase)
            [dets, depthM] = testCase.loadDetectionFixture();
            results = detectionsToWorld(dets, depthM, testCase.Cam2, ...
                MaxBinDistance=testCase.MaxBinDistance);
            for i = 1:numel(results)
                x = results(i).world_xyz(1);
                y = results(i).world_xyz(2);
                % <comment> Verify world X within expected bin range </comment>
                testCase.verifyGreaterThanOrEqual(x, testCase.XRange(1));
                testCase.verifyLessThanOrEqual(x,    testCase.XRange(2));
                % <comment> Verify world Y within expected lateral range </comment>
                testCase.verifyGreaterThanOrEqual(y, testCase.YRange(1));
                testCase.verifyLessThanOrEqual(y,    testCase.YRange(2));
            end
        end

        function analyticalTransform(testCase)
            cam = testCase.Cam2;
            depth = testCase.MaxBinDistance;
            depthM = ones(720, 1280) * depth;
            dets   = struct('label','I','box_2d',[cam.cy, cam.cx, cam.cy, cam.cx]);
            results = detectionsToWorld(dets, depthM, cam, MaxBinDistance=depth);
            expectedXYZ = testCase.analyticalXYZ(cam, depth);
            % <comment> Verify principal-point ray projects to analytically expected world XYZ </comment>
            testCase.verifyEqual(results.world_xyz, expectedXYZ, 'AbsTol', 1e-10);
        end

        function binDistanceAffectsHeightOnly(testCase)
            depthM = ones(720, 1280) * 0.90;
            dets   = struct('label','T','box_2d',[300, 500, 400, 600]);
            cam    = testCase.Cam2;
            r1 = detectionsToWorld(dets, depthM, cam, MaxBinDistance=0.95);
            r2 = detectionsToWorld(dets, depthM, cam, MaxBinDistance=0.60);
            % <comment> Verify world_xyz is unaffected by MaxBinDistance </comment>
            testCase.verifyEqual(r1.world_xyz, r2.world_xyz, 'AbsTol', 1e-10);
            % <comment> Verify height_m changes with MaxBinDistance </comment>
            testCase.verifyNotEqual(r1.height_m, r2.height_m);
        end

        function dropXYInWorkspace(testCase)
            depthM = ones(720, 1280) * 0.75;
            % Three drop regions: left table, right table, inside bin
            dropBoxes = [200,  100, 300,  250;   % left table region
                         200,  800, 300, 1000;   % right table region
                         300,  450, 400,  700];  % bin interior
            for k = 1:size(dropBoxes,1)
                dropDets  = struct('label','X','box_2d',dropBoxes(k,:));
                dropWorld = detectionsToWorld(dropDets, depthM, testCase.Cam2, ...
                    MaxBinDistance=testCase.MaxBinDistance);
                xy = dropWorld.world_xyz(1:2);
                % <comment> Verify drop X within workspace bounds </comment>
                testCase.verifyGreaterThanOrEqual(xy(1), testCase.DropXRange(1), ...
                    sprintf('Drop region %d: X=%.3f below workspace min', k, xy(1)));
                testCase.verifyLessThanOrEqual(xy(1), testCase.DropXRange(2), ...
                    sprintf('Drop region %d: X=%.3f above workspace max', k, xy(1)));
                % <comment> Verify drop Y within workspace bounds </comment>
                testCase.verifyGreaterThanOrEqual(xy(2), testCase.DropYRange(1), ...
                    sprintf('Drop region %d: Y=%.3f below workspace min', k, xy(2)));
                testCase.verifyLessThanOrEqual(xy(2), testCase.DropYRange(2), ...
                    sprintf('Drop region %d: Y=%.3f above workspace max', k, xy(2)));
            end
        end

        function emptyInput(testCase)
            dets    = struct('label', {}, 'box_2d', {});
            results = detectionsToWorld(dets, ones(720, 1280), testCase.Cam2, ...
                MaxBinDistance=testCase.MaxBinDistance);
            % <comment> Verify empty input returns empty struct array </comment>
            testCase.verifyEmpty(results);
        end

    end

    % -------------------------------------------------------------------
    % Helpers
    % -------------------------------------------------------------------
    methods (Static)
        function xyz = analyticalXYZ(cam, depth)
            rot           = cam.camera_rot;
            tform_cam2pts = eul2tform([-pi/2, 0, -pi/2], 'ZYX');
            tform_org2cam = eul2tform([rot(3), rot(2), rot(1)], 'ZYX');
            tform_org2cam(1:3,4) = cam.camera_loc(:);
            T   = tform_org2cam * tform_cam2pts;
            xyz = (T(1:3,1:3) * [0;0;depth] + T(1:3,4))';
        end
    end

    methods (Access = private)
        function [dets, depthM] = loadDetectionFixture(testCase)
            testDir  = fullfile(fileparts(mfilename('fullpath')), 'cam2');
            jsonPath = fullfile(testDir, 'detections_masked.json');
            matPath  = fullfile(testDir, 'frame_depth.mat');
            testCase.assumeTrue(isfile(jsonPath), 'cam2/detections_masked.json not found');
            testCase.assumeTrue(isfile(matPath),  'cam2/frame_depth.mat not found');
            raw  = jsondecode(fileread(jsonPath));
            dets = struct('label',{},'box_2d',{});
            for i = 1:numel(raw)
                dets(i).label  = raw(i).label;
                dets(i).box_2d = raw(i).box_2d(:)';
            end
            loaded = load(matPath);
            depthM = loaded.depthM2;
        end
    end

end
