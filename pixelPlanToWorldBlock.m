classdef (StrictDefaults) pixelPlanToWorldBlock < matlab.System
    % pixelPlanToWorldBlock  Project pixel-space Gemini plan to world-frame XYZ.
    %
    %   Wraps the detectionsToWorld() function.  Takes the raw pixel detections
    %   bus output from the Gemini Robotics-ER block (Task = PlanTask) plus the
    %   depth image, and produces the full geminiTaskPlannerBus with world-frame
    %   pick and drop positions.
    %
    %   The block fires on the first simulation step and on every rising edge of
    %   trigger (0→1), matching the fire condition of geminiERBlock.  Between
    %   fires the cached output is returned unchanged — detectionsToWorld() is
    %   NOT called on every sample step.
    %
    %   Inputs:
    %     detections — struct/bus with fields:
    %                    count      (1×1 double)
    %                    boxes      ([MaxDetections×4] double) pick boxes, pixels
    %                    pick_order ([MaxDetections×1] int32)
    %                    drop_boxes ([MaxDetections×4] double) drop boxes, pixels
    %     depth      — double [H x W] depth map in metres (from Sim3D)
    %     trigger    — uint8 scalar; rising edge (0→1) triggers recomputation.
    %                  Wire to the same signal as geminiERBlock trigger.
    %
    %   Output:
    %     geminiTaskPlannerBus with fields (see initPlannerGeminiER):
    %       count, boxes, world_xyz, depth_m, height_m, pick_order,
    %       drop_box_2d, drop_xyz
    %
    %   All robot-base-frame conversions (RobotOffsetZ subtraction) are applied
    %   here, matching the original plannerGeminiER.buildTaskPlan convention.
    %
    %   See also detectionsToWorld, geminiERBlock, PlanTask, initPlannerGeminiER.

    properties (Nontunable)
        % Camera focal length in pixels (equal in both axes).
        FocalLength (1,1) double = 750

        % Principal point [cx, cy] in pixels.
        PrincipalPoint (1,2) double = [640, 360]

        % Camera position [x, y, z] in world frame (m).
        CameraLoc (1,3) double = [0.50, 0, 1.50]

        % Camera orientation as ZYX Euler angles (rad).
        CameraRot (1,3) double = [pi/2, pi/2, pi/2]

        % Depth from camera to bin floor (m). Used to estimate object height above floor.
        MaxBinDistance (1,1) double = 0.95

        % Height above drop surface at which the robot releases the object (m).
        DropHeightOffset (1,1) double = 0.10

        % Z offset of the robot base above the world-frame origin (m).
        % Subtracted from world_xyz(:,3) and drop_xyz(:,3) to convert to robot
        % base frame. Must match PoseMaskRCNNModel.RobotOffset(3) = 0.625001.
        RobotOffsetZ (1,1) double = 0.625001

        % Maximum objects per plan. Must match PlanTask.MaxDetections and
        % initPlannerGeminiER (IBP example hardcodes 8).
        MaxDetections (1,1) double = 8
    end

    properties (Access = private)
        CachedOutput    % last computed geminiTaskPlannerBus; returned between triggers
        IsFirstStep (1,1) logical = true
        LastTrigger (1,1) uint8   = 0
    end

    methods
        function obj = pixelPlanToWorldBlock(varargin)
            setProperties(obj, nargin, varargin{:});
        end
    end

    methods (Access = protected)
        function setupImpl(obj, ~, ~, ~)
            obj.IsFirstStep  = true;
            obj.LastTrigger  = uint8(0);
            obj.CachedOutput = obj.emptyOutput();
        end

        function out = stepImpl(obj, detections, depth, trigger)
            % Run world projection on the first step or rising edge of trigger.
            % Return the cached result unchanged between fires.
            risingEdge = (uint8(trigger) == uint8(1)) && (obj.LastTrigger == uint8(0));
            obj.LastTrigger = uint8(trigger);

            if obj.IsFirstStep || risingEdge
                obj.CachedOutput = obj.computeOutput(detections, depth);
                obj.IsFirstStep  = false;
            end

            out = obj.CachedOutput;
        end

        function num = getNumInputsImpl(~)
            num = 3;
        end

        function names = getInputNamesImpl(~)
            names = ["detections", "depth", "trigger"];
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
            % Run detectionsToWorld() for pick and drop boxes and pack the result.
            camParams = struct( ...
                'f',          obj.FocalLength, ...
                'cx',         obj.PrincipalPoint(1), ...
                'cy',         obj.PrincipalPoint(2), ...
                'camera_loc', obj.CameraLoc, ...
                'camera_rot', obj.CameraRot);

            count = detections.count;
            Nplan = min(count, obj.MaxDetections);

            % Pick boxes
            pickDets = struct('label', {}, 'box_2d', {});
            for i = 1:Nplan
                pickDets(i).label  = '';
                pickDets(i).box_2d = detections.boxes(i, :);
            end
            wr = detectionsToWorld(pickDets, depth, camParams, ...
                MaxBinDistance=obj.MaxBinDistance);

            % Drop boxes — back-project only where a drop box is present.
            dropDets = struct('label', {}, 'box_2d', {});
            for i = 1:Nplan
                dropDets(i).label  = '';
                dropDets(i).box_2d = detections.drop_boxes(i, :);
            end
            allDropBoxes = detections.drop_boxes(1:Nplan, :);
            if any(allDropBoxes(:))
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
                drop_box_2d(i, :) = detections.drop_boxes(i, :);
                if any(detections.drop_boxes(i, :))
                    drop_xyz(i, :) = [dropWorld(i).world_xyz(1:2), ...
                                      dropWorld(i).world_xyz(3) + obj.DropHeightOffset];
                end
            end

            % Convert world-frame Z to robot base frame.
            % Apply to pick positions always; apply to drop positions only where
            % Gemini returned a drop box — zero rows stay zero so the Task
            % Scheduler's getDroppingPose fallback works correctly.
            world_xyz(:, 3) = world_xyz(:, 3) - obj.RobotOffsetZ;
            nonZeroDrop = any(drop_xyz, 2);
            drop_xyz(nonZeroDrop, 3) = drop_xyz(nonZeroDrop, 3) - obj.RobotOffsetZ;

            out = struct( ...
                'count',       Nplan, ...
                'boxes',       boxes, ...
                'world_xyz',   world_xyz, ...
                'depth_m',     depth_m, ...
                'height_m',    height_m, ...
                'pick_order',  pick_order, ...
                'drop_box_2d', drop_box_2d, ...
                'drop_xyz',    drop_xyz);
        end

        function out = emptyOutput(obj)
            N   = obj.MaxDetections;
            out = struct( ...
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
