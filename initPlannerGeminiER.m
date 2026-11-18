function initPlannerGeminiER()
% initPlannerGeminiER  Define workspace parameters for IntelligentBinPickingGemini.
%
% Call from the model PreLoadFcn, or run manually before opening the model.
% Assigns the following variables to the base workspace:
%
%   MaxDetections              — scalar double, max objects per plan (default 10)
%   geminiTaskPlannerBus       — Simulink.Bus: full world-frame task plan
%                                (output of pixelPlanToWorldBlock)
%   geminiPixelDetectionsBus   — Simulink.Bus: raw pixel detections
%                                (output of RobotReasonerBlock with Reasoner=TaskPlanner)
%   geminiVerifyResultBus      — Simulink.Bus: verification flags
%                                (output of RobotReasonerBlock with Reasoner=TaskVerifier)
%
% Both reasoner buses lead with attempt: the fire count that produced the
% output (0 = idle / not verified yet).
%
% geminiTaskPlannerBus elements (rows beyond count are zero/default padded):
%   attempt      [1×1]              — plan fire number carried from geminiPixelDetectionsBus
%   count        [1×1]              — number of valid detections this frame
%   boxes        [MaxDetections×4]  — pick points as zero-size boxes [y x y x] px
%   world_xyz    [MaxDetections×3]  — world-frame pick position [x y z] m
%   depth_m      [MaxDetections×1]  — camera-to-object depth m
%   height_m     [MaxDetections×1]  — object height above bin floor m
%   pick_order   [MaxDetections×1]  — int32 pick sequence (1 = pick first)
%   drop_box_2d  [MaxDetections×4]  — drop points as zero-size boxes [y x y x] px
%   drop_xyz     [MaxDetections×3]  — world-frame drop position [x y z] m
%                                     z = surface_z_from_depth + DropHeightOffset
%
% If MaxDetections already exists in the base workspace its value is preserved.

    base = 'base';

    if evalin(base, "exist('MaxDetections','var')") == 1
        N = evalin(base, 'MaxDetections');
    else
        N = 10;
        assignin(base, 'MaxDetections', N);
    end

    % attempt is carried through from geminiPixelDetectionsBus.
    elems(1)            = Simulink.BusElement;
    elems(1).Name       = 'attempt';
    elems(1).Dimensions = 1;
    elems(1).DataType   = 'double';

    elems(2)            = Simulink.BusElement;
    elems(2).Name       = 'count';
    elems(2).Dimensions = 1;
    elems(2).DataType   = 'double';

    elems(3)            = Simulink.BusElement;
    elems(3).Name       = 'boxes';
    elems(3).Dimensions = [N, 4];
    elems(3).DataType   = 'double';

    elems(4)            = Simulink.BusElement;
    elems(4).Name       = 'world_xyz';
    elems(4).Dimensions = [N, 3];
    elems(4).DataType   = 'double';

    elems(5)            = Simulink.BusElement;
    elems(5).Name       = 'depth_m';
    elems(5).Dimensions = [N, 1];
    elems(5).DataType   = 'double';

    elems(6)            = Simulink.BusElement;
    elems(6).Name       = 'height_m';
    elems(6).Dimensions = [N, 1];
    elems(6).DataType   = 'double';

    elems(7)            = Simulink.BusElement;
    elems(7).Name       = 'pick_order';
    elems(7).Dimensions = [N, 1];
    elems(7).DataType   = 'int32';

    elems(8)            = Simulink.BusElement;
    elems(8).Name       = 'drop_box_2d';
    elems(8).Dimensions = [N, 4];
    elems(8).DataType   = 'double';

    elems(9)            = Simulink.BusElement;
    elems(9).Name       = 'drop_xyz';
    elems(9).Dimensions = [N, 3];
    elems(9).DataType   = 'double';

    bus          = Simulink.Bus;
    bus.Elements = elems;

    assignin(base, 'geminiTaskPlannerBus', bus);

    % --- geminiPixelDetectionsBus (output of RobotReasonerBlock with Reasoner=TaskPlanner) ---
    % Point-based plan. pick_center / drop_center are pixel [x y] points (the
    % reasoner converts the model's normalized 0-1000 points to pixels); a
    % [0 0] drop_center means no drop point.
    pelems(1)            = Simulink.BusElement;
    pelems(1).Name       = 'attempt';
    pelems(1).Dimensions = 1;
    pelems(1).DataType   = 'double';

    pelems(2)            = Simulink.BusElement;
    pelems(2).Name       = 'count';
    pelems(2).Dimensions = 1;
    pelems(2).DataType   = 'double';

    pelems(3)            = Simulink.BusElement;
    pelems(3).Name       = 'pick_center';
    pelems(3).Dimensions = [N, 2];
    pelems(3).DataType   = 'double';

    pelems(4)            = Simulink.BusElement;
    pelems(4).Name       = 'drop_center';
    pelems(4).Dimensions = [N, 2];
    pelems(4).DataType   = 'double';

    pelems(5)            = Simulink.BusElement;
    pelems(5).Name       = 'pick_order';
    pelems(5).Dimensions = [N, 1];
    pelems(5).DataType   = 'int32';

    pbus          = Simulink.Bus;
    pbus.Elements = pelems;
    assignin(base, 'geminiPixelDetectionsBus', pbus);

    % --- geminiVerifyResultBus (output of RobotReasonerBlock with Reasoner=TaskVerifier) ---
    % attempt     — fire count that produced this verdict (0 = not verified yet)
    % pass        — true = task succeeded, false = task failed
    % diagnostics — human-readable description; on failure lists unplaced
    %               objects by name/shape with approximate pixel location
    velems(1)            = Simulink.BusElement;
    velems(1).Name       = 'attempt';
    velems(1).Dimensions = 1;
    velems(1).DataType   = 'double';

    velems(2)            = Simulink.BusElement;
    velems(2).Name       = 'pass';
    velems(2).Dimensions = 1;
    velems(2).DataType   = 'boolean';

    velems(3)            = Simulink.BusElement;
    velems(3).Name       = 'diagnostics';
    velems(3).Dimensions = 1;
    velems(3).DataType   = 'string';

    vbus          = Simulink.Bus;
    vbus.Elements = velems;
    assignin(base, 'geminiVerifyResultBus', vbus);
end
