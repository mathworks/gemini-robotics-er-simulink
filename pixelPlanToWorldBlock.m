classdef (StrictDefaults) pixelPlanToWorldBlock < matlab.System
% Project a pixel-space plan to world-frame XYZ via detectionsToWorld, packing geminiTaskPlannerBus.

    properties (Nontunable)
        % FocalLength - camera focal length in pixels (equal in both axes)
        FocalLength (1,1) double = 750

        % PrincipalPoint - principal point [cx, cy] in pixels
        PrincipalPoint (1,2) double = [640, 360]

        % CameraLoc - camera position [x, y, z] in world frame (m)
        CameraLoc (1,3) double = [0.50, 0, 1.50]

        % CameraRot - camera orientation as ZYX Euler angles (rad)
        CameraRot (1,3) double = [pi/2, pi/2, pi/2]

        % MaxBinDistance - depth camera to bin floor (m), for object height estimate
        MaxBinDistance (1,1) double = 0.95

        % DropHeightOffset - height above drop surface at release (m)
        DropHeightOffset (1,1) double = 0.10

        % RobotOffsetZ - robot base Z offset above world origin (m), subtracted for base frame
        RobotOffsetZ (1,1) double = 0.625001

        % MaxDetections - max objects per plan (must match TaskPlanner and initPlannerGeminiER)
        MaxDetections (1,1) double = 8
    end

    properties (Access = private)
        % CachedOutput - last computed geminiTaskPlannerBus; returned until a fresh plan arrives
        CachedOutput
        % LastAttempt - plan attempt last projected (0 = none yet, the planner's idle value)
        LastAttempt (1,1) double = 0
    end

    methods
        function obj = pixelPlanToWorldBlock(varargin)
            setProperties(obj, nargin, varargin{:});
        end
    end

    methods (Access = protected)
        function setupImpl(obj, ~, ~)
            obj.LastAttempt  = 0;
            obj.CachedOutput = obj.emptyOutput();
        end

        function out = stepImpl(obj, detections, depth)
        % Run world projection only on a fresh plan (its attempt changed), else return the cached result.
            % The planner stamps each fire with a new attempt, so this projects
            % every plan (re-plans included) exactly once, reading the depth
            % frame at the plan's step.
            if detections.attempt ~= obj.LastAttempt
                obj.CachedOutput = obj.computeOutput(detections, depth);
                obj.LastAttempt  = detections.attempt;
            end

            out = obj.CachedOutput;
        end

        function num = getNumInputsImpl(~)
            num = 2;
        end

        function names = getInputNamesImpl(~)
            names = ["detections", "depth"];
        end

        function num = getNumOutputsImpl(~)
            num = 1;
        end

        function flag = isInputSizeMutableImpl(~, ~)
            flag = false;
        end

        % --- Simulink type/size propagation ---------------------------------

        function sz = getOutputSizeImpl(~)
            sz = [1, 1];
        end

        function dt = getOutputDataTypeImpl(~)
            dt = 'geminiTaskPlannerBus';
        end

        function flag = isOutputComplexImpl(~)
            flag = false;
        end

        function flag = isOutputFixedSizeImpl(~)
            flag = true;
        end

    end

    methods (Access = private)
        function out = computeOutput(obj, detections, depth)
        % Run detectionsToWorld() for pick and drop boxes and pack the fixed-size result.
            camParams = struct( ...
                'f',          obj.FocalLength, ...
                'cx',         obj.PrincipalPoint(1), ...
                'cy',         obj.PrincipalPoint(2), ...
                'camera_loc', obj.CameraLoc, ...
                'camera_rot', obj.CameraRot);

            count = detections.count;
            Nplan = min(count, obj.MaxDetections);

            % Pick points -> zero-size boxes [y x y x] so detectionsToWorld reuses
            % unchanged (it back-projects each box centre).
            pickDets = struct('label', {}, 'box_2d', {});
            for i = 1:Nplan
                pickDets(i).label  = '';
                pickDets(i).box_2d = obj.pointToBox(detections.pick_center(i, :));
            end
            wr = detectionsToWorld(pickDets, depth, camParams, ...
                MaxBinDistance=obj.MaxBinDistance);

            % Drop points — back-project only where a drop point is present.
            dropDets = struct('label', {}, 'box_2d', {});
            for i = 1:Nplan
                dropDets(i).label  = '';
                dropDets(i).box_2d = obj.pointToBox(detections.drop_center(i, :));
            end
            allDropPoints = detections.drop_center(1:Nplan, :);
            if any(allDropPoints(:))
                dropWorld = detectionsToWorld(dropDets, depth, camParams, ...
                    MaxBinDistance=obj.MaxBinDistance);
            else
                dropWorld = repmat(struct('world_xyz', zeros(1,3)), 1, Nplan);
            end

            % Pack into fixed-size output arrays, padded to MaxDetections.
            boxes       = zeros(obj.MaxDetections, 4);
            world_xyz   = zeros(obj.MaxDetections, 3);
            depth_m     = zeros(obj.MaxDetections, 1);
            height_m    = zeros(obj.MaxDetections, 1);
            pick_order  = zeros(obj.MaxDetections, 1, 'int32');
            drop_box_2d = zeros(obj.MaxDetections, 4);
            drop_xyz    = zeros(obj.MaxDetections, 3);

            for i = 1:Nplan
                boxes(i, :)       = wr(i).box_2d;
                world_xyz(i, :)   = wr(i).world_xyz;
                depth_m(i)        = wr(i).depth_m;
                height_m(i)       = wr(i).height_m;
                pick_order(i)     = detections.pick_order(i);
                drop_box_2d(i, :) = dropDets(i).box_2d;
                if any(detections.drop_center(i, :))
                    drop_xyz(i, :) = [dropWorld(i).world_xyz(1:2), ...
                                      dropWorld(i).world_xyz(3) + obj.DropHeightOffset];
                end
            end

            % Convert world-frame Z to robot base frame.
            % Apply to pick positions always; apply to drop positions only where
            % the plan returned a drop point — zero rows stay zero so the Task
            % Scheduler's getDroppingPose fallback works correctly.
            world_xyz(:, 3) = world_xyz(:, 3) - obj.RobotOffsetZ;
            nonZeroDrop = any(drop_xyz, 2);
            drop_xyz(nonZeroDrop, 3) = drop_xyz(nonZeroDrop, 3) - obj.RobotOffsetZ;

            out = struct( ...
                'attempt',     detections.attempt, ...
                'count',       Nplan, ...
                'boxes',       boxes, ...
                'world_xyz',   world_xyz, ...
                'depth_m',     depth_m, ...
                'height_m',    height_m, ...
                'pick_order',  pick_order, ...
                'drop_box_2d', drop_box_2d, ...
                'drop_xyz',    drop_xyz);
        end

        function box = pointToBox(~, point)
        % Convert a pixel [x y] point to a zero-size box [y_min x_min y_max x_max].
            % detectionsToWorld's centre (u=(x_min+x_max)/2, v=(y_min+y_max)/2)
            % recovers the point exactly. A zero point stays a zero box.
            box = [point(2), point(1), point(2), point(1)];
        end

        function out = emptyOutput(obj)
        % Build a zero-valued geminiTaskPlannerBus struct.
            N   = obj.MaxDetections;
            out = struct( ...
                'attempt',     0, ...
                'count',       0, ...
                'boxes',       zeros(N, 4), ...
                'world_xyz',   zeros(N, 3), ...
                'depth_m',     zeros(N, 1), ...
                'height_m',    zeros(N, 1), ...
                'pick_order',  zeros(N, 1, 'int32'), ...
                'drop_box_2d', zeros(N, 4), ...
                'drop_xyz',    zeros(N, 3));
        end
    end

    methods (Static, Access = protected)
        function flag = getSimulateUsingImpl
            flag = 'Interpreted execution';
        end

        function flag = showSimulateUsingImpl
            flag = false;
        end

        function groups = getPropertyGroupsImpl
            camSection = matlab.system.display.Section( ...
                'Title',        'Camera', ...
                'PropertyList', {'FocalLength', 'PrincipalPoint', ...
                                 'CameraLoc', 'CameraRot', 'MaxBinDistance'});
            robotSection = matlab.system.display.Section( ...
                'Title',        'Robot', ...
                'PropertyList', {'DropHeightOffset', 'RobotOffsetZ', 'MaxDetections'});
            groups = [ ...
                matlab.system.display.SectionGroup('Title', 'Camera', 'Sections', camSection), ...
                matlab.system.display.SectionGroup('Title', 'Robot',  'Sections', robotSection)];
        end
    end
end
