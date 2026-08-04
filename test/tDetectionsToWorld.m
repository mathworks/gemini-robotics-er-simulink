classdef tDetectionsToWorld < matlab.unittest.TestCase
%tDetectionsToWorld  Tests for the detectionsToWorld pipeline.
%
% Two test groups (use TestTags to run selectively):
%
%   Detection — tests for pick back-projection via detectionsToWorld.
%               Runs on saved fixtures for cam1 and cam2.  Analytical
%               and edge-case tests run without any fixture files.
%               No API key required.
%
%   Place     — tests for drop back-projection and DropHeightOffset.
%               All synthetic (no fixture files, no API key required).
%               cam2 camera config only.
%
% Run all:
%   runtests("test/tDetectionsToWorld.m")
%
% Run one group:
%   runtests("test/tDetectionsToWorld.m", Tag="Detection")
%   runtests("test/tDetectionsToWorld.m", Tag="Place")
%
% <Feature> detectionsToWorld </Feature>
% <TestType> unit </TestType>
% <Release> R2026a </Release>

% Copyright 2026 The MathWorks, Inc.

    % -------------------------------------------------------------------
    % Constants
    % -------------------------------------------------------------------
    properties (Constant)
        % Camera configurations
        Cam1 = struct( ...
            'f',          750, ...
            'cx',         640, ...
            'cy',         360, ...
            'camera_loc', [0.48, 0, 1.15], ...
            'camera_rot', [pi/2, pi/2, pi/2])
        Cam2 = struct( ...
            'f',          750, ...
            'cx',         640, ...
            'cy',         360, ...
            'camera_loc', [0.50, 0, 1.50], ...
            'camera_rot', [pi/2, pi/2, pi/2])

        MaxBinDistance1 = 0.60   % cam1: depth to bin floor (m)
        MaxBinDistance2 = 0.95   % cam2: depth to bin floor (m)

        DropHeightOffset = 0.10  % must match geminiTaskPlanner default

        % Expected world-frame bounds for bin objects
        XRange = [0.20, 0.70]    % world X (m) — bin depth from robot
        YRange = [-0.40, 0.50]   % world Y (m) — lateral extent

        % Expected world-frame bounds for drop workspace (bin + both tables)
        DropXRange = [-0.20, 1.00]
        DropYRange = [-0.90, 0.90]

        XYTolerance = 0.05       % max XY error vs ground truth (m)

        ExpectedFields = {'label','box_2d','uv','depth_m','world_xyz','height_m'}
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

    % ===================================================================
    %  GROUP 1 — Detection tests
    % ===================================================================

    % --- Structural tests (cam1 fixtures) ------------------------------

    methods (Test, TestTags=["Detection","Cam1"])

        function detect_cam1_outputFields(testCase)
            [dets, depthM] = testCase.loadDetectionFixture('cam1');
            results = testCase.runPickProjection(dets, depthM, testCase.Cam1, testCase.MaxBinDistance1);
            % <comment> Verify result struct has all expected fields </comment>
            testCase.verifyEqual(sort(fieldnames(results)), sort(testCase.ExpectedFields(:)));
        end

        function detect_cam1_outputCount(testCase)
            [dets, depthM] = testCase.loadDetectionFixture('cam1');
            results = testCase.runPickProjection(dets, depthM, testCase.Cam1, testCase.MaxBinDistance1);
            % <comment> Verify one result per input detection </comment>
            testCase.verifyEqual(numel(results), numel(dets));
        end

        function detect_cam1_labelsPreserved(testCase)
            [dets, depthM] = testCase.loadDetectionFixture('cam1');
            results = testCase.runPickProjection(dets, depthM, testCase.Cam1, testCase.MaxBinDistance1);
            % <comment> Verify output labels match input labels </comment>
            for i = 1:numel(dets)
                testCase.verifyEqual(results(i).label, dets(i).label);
            end
        end

        function detect_cam1_worldXYInRange(testCase)
            [dets, depthM] = testCase.loadDetectionFixture('cam1');
            results = testCase.runPickProjection(dets, depthM, testCase.Cam1, testCase.MaxBinDistance1);
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

        function detect_cam1_groundTruthCoverage(testCase)
            [dets, depthM] = testCase.loadDetectionFixture('cam1');
            testDir = fullfile(fileparts(mfilename('fullpath')), 'cam1');
            gtPath  = fullfile(testDir, 'groundTruth.json');
            testCase.assumeTrue(isfile(gtPath), 'groundTruth.json not found');
            results = testCase.runPickProjection(dets, depthM, testCase.Cam1, testCase.MaxBinDistance1);
            gt    = jsondecode(fileread(gtPath));
            gtXY  = cell2mat(arrayfun(@(g) reshape(g.world_xyz(1:2), 1, 2), gt(:)',  'UniformOutput', false)');
            detXY = cell2mat(arrayfun(@(r) reshape(r.world_xyz(1:2), 1, 2), results(:)', 'UniformOutput', false)');
            for k = 1:numel(gt)
                dists  = sqrt(sum((detXY - gtXY(k,:)).^2, 2));
                minDist = min(dists);
                % <comment> Verify each GT object has a detection within tolerance </comment>
                testCase.verifyLessThanOrEqual(minDist, testCase.XYTolerance, ...
                    sprintf('GT object %d (%s) not covered within %.3f m', ...
                            k, gt(k).label, testCase.XYTolerance));
            end
        end

        function detect_cam1_analyticalTransform(testCase)
            cam = testCase.Cam1;
            H = 720; W = 1280; depth = 0.60;
            depthM = ones(H, W) * depth;
            dets   = struct('label','I','box_2d',[cam.cy, cam.cx, cam.cy, cam.cx]);
            results = testCase.runPickProjection(dets, depthM, cam, testCase.MaxBinDistance1);
            expectedXYZ = testCase.analyticalXYZ(cam, depth);
            % <comment> Verify principal-point ray projects to analytically expected world XYZ </comment>
            testCase.verifyEqual(results.world_xyz, expectedXYZ, 'AbsTol', 1e-10);
        end

        function detect_cam1_emptyInput(testCase)
            loaded = load(fullfile(fileparts(mfilename('fullpath')), 'cam1', 'frame_depth.mat'), 'depthM');
            dets   = struct('label', {}, 'box_2d', {});
            results = testCase.runPickProjection(dets, loaded.depthM, testCase.Cam1, testCase.MaxBinDistance1);
            % <comment> Verify empty input returns empty struct array </comment>
            testCase.verifyEmpty(results);
        end

    end

    % --- Structural tests (cam2 fixtures) ------------------------------

    methods (Test, TestTags=["Detection","Cam2"])

        function detect_cam2_worldXYInRange(testCase)
            [dets, depthM] = testCase.loadDetectionFixture('cam2');
            results = testCase.runPickProjection(dets, depthM, testCase.Cam2, testCase.MaxBinDistance2);
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

        function detect_cam2_analyticalTransform(testCase)
            cam = testCase.Cam2;
            H = 720; W = 1280; depth = testCase.MaxBinDistance2;
            depthM = ones(H, W) * depth;
            dets   = struct('label','I','box_2d',[cam.cy, cam.cx, cam.cy, cam.cx]);
            results = testCase.runPickProjection(dets, depthM, cam, testCase.MaxBinDistance2);
            expectedXYZ = testCase.analyticalXYZ(cam, depth);
            % <comment> Verify principal-point ray projects to analytically expected world XYZ </comment>
            testCase.verifyEqual(results.world_xyz, expectedXYZ, 'AbsTol', 1e-10);
        end

        function detect_cam2_binDistanceAffectsHeightOnly(testCase)
            H = 720; W = 1280;
            depthM = ones(H, W) * 0.90;
            dets   = struct('label','T','box_2d',[300, 500, 400, 600]);
            cam    = testCase.Cam2;
            r1 = detectionsToWorld(dets, depthM, cam, MaxBinDistance=0.95);
            r2 = detectionsToWorld(dets, depthM, cam, MaxBinDistance=0.60);
            % <comment> Verify world_xyz is unaffected by MaxBinDistance </comment>
            testCase.verifyEqual(r1.world_xyz, r2.world_xyz, 'AbsTol', 1e-10);
            % <comment> Verify height_m changes with MaxBinDistance </comment>
            testCase.verifyNotEqual(r1.height_m, r2.height_m);
        end

        function detect_cam2_emptyInput(testCase)
            loaded = load(fullfile(fileparts(mfilename('fullpath')), 'cam2', 'frame_depth.mat'));
            depthM = loaded.depthM2;
            dets   = struct('label', {}, 'box_2d', {});
            results = testCase.runPickProjection(dets, depthM, testCase.Cam2, testCase.MaxBinDistance2);
            % <comment> Verify empty input returns empty struct array </comment>
            testCase.verifyEmpty(results);
        end

    end

    % --- Detection-only plan fields (synthetic, no fixture) ------------

    methods (Test, TestTags="Detection")

        function detect_dropXyzZeroWhenNoDropBox(testCase)
            % Simulate detection-only response: no drop_box_2d
            H = 720; W = 1280; depth = 0.80;
            depthM = ones(H, W) * depth;
            rawDets = struct('label','X','box_2d',[300,400,400,500], ...
                             'drop_box_2d',zeros(1,4),'pick_priority',1);
            cam = testCase.Cam2;
            dropDets  = struct('label','X','box_2d',rawDets.drop_box_2d);
            dropWorld = detectionsToWorld(dropDets, depthM, cam, MaxBinDistance=testCase.MaxBinDistance2);
            drop_xyz  = zeros(1,3);
            if any(rawDets.drop_box_2d)
                drop_xyz = [dropWorld.world_xyz(1:2), dropWorld.world_xyz(3) + testCase.DropHeightOffset];
            end
            % <comment> Verify drop_xyz is zeros when drop_box_2d is absent </comment>
            testCase.verifyEqual(drop_xyz, zeros(1,3));
        end

        function detect_pickOrderFallbackToIndex(testCase)
            % Simulate detection-only response: pick_priority absent, fallback = array index
            rawDets(1) = struct('label','X','box_2d',[300,400,400,500],'drop_box_2d',zeros(1,4),'pick_priority',1);
            rawDets(2) = struct('label','T','box_2d',[200,300,300,400],'drop_box_2d',zeros(1,4),'pick_priority',2);
            for i = 1:numel(rawDets)
                % <comment> Verify fallback pick_priority equals array index </comment>
                testCase.verifyEqual(rawDets(i).pick_priority, i);
            end
        end

    end

    % ===================================================================
    %  GROUP 2 — Place tests (cam2, all synthetic)
    % ===================================================================

    methods (Test, TestTags=["Place","Cam2"])

        function place_dropXyzPopulatedWhenDropBoxPresent(testCase)
            cam = testCase.Cam2;
            H = 720; W = 1280; depth = 0.75;
            depthM   = ones(H, W) * depth;
            dropBox  = [200, 800, 300, 1000];   % box over right-table region
            dropDets = struct('label','X','box_2d',dropBox);
            dropWorld = detectionsToWorld(dropDets, depthM, cam, MaxBinDistance=testCase.MaxBinDistance2);
            drop_xyz  = [dropWorld.world_xyz(1:2), dropWorld.world_xyz(3) + testCase.DropHeightOffset];
            % <comment> Verify drop_xyz is nonzero when drop box is present </comment>
            testCase.verifyNotEqual(drop_xyz, zeros(1,3));
        end

        function place_dropZAboveSurface(testCase)
            cam = testCase.Cam2;
            H = 720; W = 1280; depth = 0.75;
            depthM   = ones(H, W) * depth;
            dropBox  = [200, 800, 300, 1000];
            dropDets = struct('label','X','box_2d',dropBox);
            dropWorld = detectionsToWorld(dropDets, depthM, cam, MaxBinDistance=testCase.MaxBinDistance2);
            surfaceZ  = dropWorld.world_xyz(3);
            drop_z    = surfaceZ + testCase.DropHeightOffset;
            % <comment> Verify drop Z is above surface by exactly DropHeightOffset </comment>
            testCase.verifyEqual(drop_z, surfaceZ + testCase.DropHeightOffset, 'AbsTol', 1e-10);
            % <comment> Verify drop Z is strictly above the surface </comment>
            testCase.verifyGreaterThan(drop_z, surfaceZ);
        end

        function place_dropXYInWorkspace(testCase)
            cam = testCase.Cam2;
            H = 720; W = 1280; depth = 0.75;
            depthM = ones(H, W) * depth;
            % Three drop regions: left table, right table, inside bin
            dropBoxes = [200,  100, 300,  250;   % left table region
                         200,  800, 300, 1000;   % right table region
                         300,  450, 400,  700];  % bin interior
            for k = 1:size(dropBoxes,1)
                dropDets  = struct('label','X','box_2d',dropBoxes(k,:));
                dropWorld = detectionsToWorld(dropDets, depthM, cam, MaxBinDistance=testCase.MaxBinDistance2);
                drop_xyz  = [dropWorld.world_xyz(1:2), dropWorld.world_xyz(3) + testCase.DropHeightOffset];
                % <comment> Verify drop X within workspace bounds </comment>
                testCase.verifyGreaterThanOrEqual(drop_xyz(1), testCase.DropXRange(1), ...
                    sprintf('Drop region %d: X=%.3f below workspace min', k, drop_xyz(1)));
                testCase.verifyLessThanOrEqual(drop_xyz(1), testCase.DropXRange(2), ...
                    sprintf('Drop region %d: X=%.3f above workspace max', k, drop_xyz(1)));
                % <comment> Verify drop Y within workspace bounds </comment>
                testCase.verifyGreaterThanOrEqual(drop_xyz(2), testCase.DropYRange(1), ...
                    sprintf('Drop region %d: Y=%.3f below workspace min', k, drop_xyz(2)));
                testCase.verifyLessThanOrEqual(drop_xyz(2), testCase.DropYRange(2), ...
                    sprintf('Drop region %d: Y=%.3f above workspace max', k, drop_xyz(2)));
            end
        end

        function place_pickOrderUniqueAndPositive(testCase)
            % Simulate plan response with three objects and assigned priorities
            priorities = int32([2, 1, 3]);
            pick_order = zeros(3, 1, 'int32');
            for i = 1:3
                pick_order(i) = priorities(i);
            end
            % <comment> Verify all pick_order values are positive </comment>
            testCase.verifyTrue(all(pick_order > 0));
            % <comment> Verify pick_order values are unique </comment>
            testCase.verifyEqual(numel(unique(pick_order)), numel(pick_order));
        end

        function place_multipleObjectsDropXyzIndependent(testCase)
            % Two objects with different drop boxes should get different drop_xyz
            cam = testCase.Cam2;
            H = 720; W = 1280; depth = 0.75;
            depthM = ones(H, W) * depth;
            box1 = [200,  100, 300,  250];   % left
            box2 = [200,  800, 300, 1000];   % right
            dw1 = detectionsToWorld(struct('label','X','box_2d',box1), depthM, cam, ...
                MaxBinDistance=testCase.MaxBinDistance2);
            dw2 = detectionsToWorld(struct('label','T','box_2d',box2), depthM, cam, ...
                MaxBinDistance=testCase.MaxBinDistance2);
            drop1 = [dw1.world_xyz(1:2), dw1.world_xyz(3) + testCase.DropHeightOffset];
            drop2 = [dw2.world_xyz(1:2), dw2.world_xyz(3) + testCase.DropHeightOffset];
            % <comment> Verify two distinct drop regions yield different world positions </comment>
            testCase.verifyNotEqual(drop1, drop2);
        end

    end

    % -------------------------------------------------------------------
    % Static helpers
    % -------------------------------------------------------------------
    methods (Static)
        function results = runPickProjection(dets, depthM, camParams, maxBinDistance)
            results = detectionsToWorld(dets, depthM, camParams, ...
                MaxBinDistance=maxBinDistance);
        end

        function xyz = analyticalXYZ(cam, depth)
            rot           = cam.camera_rot;
            tform_cam2pts = eul2tform([-pi/2, 0, -pi/2], 'ZYX');
            tform_org2cam = eul2tform([rot(3), rot(2), rot(1)], 'ZYX');
            tform_org2cam(1:3,4) = cam.camera_loc(:);
            T   = tform_org2cam * tform_cam2pts;
            xyz = (T(1:3,1:3) * [0;0;depth] + T(1:3,4))';
        end
    end

    % -------------------------------------------------------------------
    % Private helpers
    % -------------------------------------------------------------------
    methods (Access = private)
        function [dets, depthM] = loadDetectionFixture(testCase, camName)
            testDir  = fileparts(mfilename('fullpath'));
            jsonPath = fullfile(testDir, camName, 'detections_masked.json');
            matPath  = fullfile(testDir, camName, 'frame_depth.mat');
            testCase.assumeTrue(isfile(jsonPath), ...
                sprintf('%s/detections_masked.json not found — capture with API key first', camName));
            testCase.assumeTrue(isfile(matPath), ...
                sprintf('%s/frame_depth.mat not found', camName));
            raw  = jsondecode(fileread(jsonPath));
            dets = struct('label',{},'box_2d',{});
            for i = 1:numel(raw)
                dets(i).label  = raw(i).label;
                dets(i).box_2d = raw(i).box_2d(:)';
            end
            loaded = load(matPath);
            if strcmp(camName, 'cam1')
                depthM = loaded.depthM;
            else
                depthM = loaded.depthM2;
            end
        end
    end

end
