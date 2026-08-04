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
%                                (output of geminiERBlock with Task=PlanTask)
%   geminiVerifyResultBus      — Simulink.Bus: verification flags
%                                (output of geminiERBlock with Task=VerifyTask)
%
% geminiTaskPlannerBus elements (rows beyond count are zero/default padded):
%   count        [1×1]              — number of valid detections this frame
%   boxes        [MaxDetections×4]  — pick bounding boxes [y_min x_min y_max x_max] px
%   world_xyz    [MaxDetections×3]  — world-frame pick position [x y z] m
%   depth_m      [MaxDetections×1]  — camera-to-object depth m
%   height_m     [MaxDetections×1]  — object height above bin floor m
%   pick_order   [MaxDetections×1]  — int32 pick sequence (1 = pick first)
%   drop_box_2d  [MaxDetections×4]  — drop region boxes [y_min x_min y_max x_max] px
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

    elems(1)            = Simulink.BusElement;
    elems(1).Name       = 'count';
    elems(1).Dimensions = 1;
    elems(1).DataType   = 'double';

    elems(2)            = Simulink.BusElement;
    elems(2).Name       = 'boxes';
    elems(2).Dimensions = [N, 4];
    elems(2).DataType   = 'double';

    elems(3)            = Simulink.BusElement;
    elems(3).Name       = 'world_xyz';
    elems(3).Dimensions = [N, 3];
    elems(3).DataType   = 'double';

    elems(4)            = Simulink.BusElement;
    elems(4).Name       = 'depth_m';
    elems(4).Dimensions = [N, 1];
    elems(4).DataType   = 'double';

    elems(5)            = Simulink.BusElement;
    elems(5).Name       = 'height_m';
    elems(5).Dimensions = [N, 1];
    elems(5).DataType   = 'double';

    elems(6)            = Simulink.BusElement;
    elems(6).Name       = 'pick_order';
    elems(6).Dimensions = [N, 1];
    elems(6).DataType   = 'int32';

    elems(7)            = Simulink.BusElement;
    elems(7).Name       = 'drop_box_2d';
    elems(7).Dimensions = [N, 4];
    elems(7).DataType   = 'double';

    elems(8)            = Simulink.BusElement;
    elems(8).Name       = 'drop_xyz';
    elems(8).Dimensions = [N, 3];
    elems(8).DataType   = 'double';

    bus          = Simulink.Bus;
    bus.Elements = elems;

    assignin(base, 'geminiTaskPlannerBus', bus);

    % --- geminiPixelDetectionsBus (output of geminiERBlock with Task=PlanTask) ---
    pelems(1)            = Simulink.BusElement;
    pelems(1).Name       = 'count';
    pelems(1).Dimensions = 1;
    pelems(1).DataType   = 'double';

    pelems(2)            = Simulink.BusElement;
    pelems(2).Name       = 'boxes';
    pelems(2).Dimensions = [N, 4];
    pelems(2).DataType   = 'double';

    pelems(3)            = Simulink.BusElement;
    pelems(3).Name       = 'pick_order';
    pelems(3).Dimensions = [N, 1];
    pelems(3).DataType   = 'int32';

    pelems(4)            = Simulink.BusElement;
    pelems(4).Name       = 'drop_boxes';
    pelems(4).Dimensions = [N, 4];
    pelems(4).DataType   = 'double';

    pbus          = Simulink.Bus;
    pbus.Elements = pelems;
    assignin(base, 'geminiPixelDetectionsBus', pbus);

    % --- geminiVerifyResultBus (output of geminiERBlock with Task=VerifyTask) ---
    % pass        — true = task succeeded, false = task failed
    % diagnostics — human-readable description; on failure lists unplaced
    %               objects by name/shape with approximate pixel location
    velems(1)            = Simulink.BusElement;
    velems(1).Name       = 'pass';
    velems(1).Dimensions = 1;
    velems(1).DataType   = 'boolean';

    velems(2)            = Simulink.BusElement;
    velems(2).Name       = 'diagnostics';
    velems(2).Dimensions = 1;
    velems(2).DataType   = 'string';

    vbus          = Simulink.Bus;
    vbus.Elements = velems;
    assignin(base, 'geminiVerifyResultBus', vbus);
end
