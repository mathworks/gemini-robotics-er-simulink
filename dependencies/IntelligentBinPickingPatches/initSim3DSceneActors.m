function initSim3DSceneActors(Actor, World)
% Build the Sim3D bin-picking scene: stand, tray, two tables, and the parts.
%
% Called from the InitScriptText of Simulink_3D_IBP_Target/Sim3D Scene
% Generation/Simulation 3D Actor7 (set by installIntelligentBinPicking). Mirrors the
% shipped script, except that parts cycle through a color table instead of one
% uniform color. The part layout comes from generateParam.mat, written by the
% patched initSim3DRobotModelParam (which applies actorSeed), so the scene and
% the gripper's binActor lookup tables always agree.

paramFile = fullfile(fileparts(which('initSim3DRobotModelParam')), 'generateParam.mat');
param = load(paramFile).param;

fileName = "binPickingStand_scaled.stl";
Stand = sim3d.Actor('ActorName', 'Stand');
Stand.load(fileName, [1 1 1]);
Stand.Rotation = single([0 0 0]);
Stand.Translation = single([0 0 0.001]*[1 0 0; 0 -1 0; 0 0 1]);
Stand.CoordinateSystem = 'MATLAB';
Stand.Color = [0.6078,0.5569,0.6275];
Stand.Collisions = false;
Stand.Shadows = 0;
Stand.Shininess = 0.2;
Stand.Flat = 1;
World.add(Stand, Actor);

fileName2 = "Bin_STL_Scaled.stl";
Tray = sim3d.Actor('ActorName', 'Tray');
Tray.load(fileName2, [1 1 0.35]);
Tray.Rotation = single([0 0 pi/2]*[1 0 0; 0 -1 0; 0 0 -1]);
Tray.Translation = single([0.48 0 0.55]*[1 0 0; 0 -1 0; 0 0 1]);
Tray.CoordinateSystem = 'MATLAB';
Tray.Metallic = 0.70;
Tray.Color = [0.2784,0.2667,0.6824];
Tray.PreciseContacts = true;
Tray.Shininess = 0.20;
Tray.Shadows = 1;
Tray.Flat = 1;
World.add(Tray, Actor);

fileName = "table_solid_scaled.stl";
Table = sim3d.Actor('ActorName', 'Table');
Table.load(fileName, [1 1 1]);
Table.Rotation = single([0 0 0]);
Table.Translation = single([0.23 0.68 0.40]*[1 0 0; 0 -1 0; 0 0 1]);
Table.CoordinateSystem = 'MATLAB';
Table.Color = [0.6824,0.4706,0.4667];
Table.Shadows = 0;
Table.Friction = 1;
Table.Shininess = 0.2;
Table.Flat = 1;
Table.Restitution = 0.15;
World.add(Table, Actor);

Table2 = sim3d.Actor('ActorName', 'Table2');
Table2.load(fileName, [1 1 1]);
Table2.Rotation = single([0 0 0]);
Table2.Translation = single([0.23 -0.68 0.40]*[1 0 0; 0 -1 0; 0 0 1]);
Table2.CoordinateSystem = 'MATLAB';
Table2.Color = [0.6824,0.4706,0.4667];
Table2.Shadows = 1;
Table2.Friction = 1.0;
Table2.Shininess = 0.2;
Table2.Flat = 1;
Table2.Restitution = 0.1;
World.add(Table2, Actor);

% Parts
colors = [ ...
    0.95, 0.20, 0.20;   % red
    0.15, 0.80, 0.25;   % green
    0.20, 0.40, 0.95;   % blue
    0.10, 0.90, 0.90;   % cyan
    0.90, 0.15, 0.90;   % magenta
    0.15, 0.15, 0.15];  % black

for i = 1:param.numInstEachObj*numel(param.model_files)
    inst_label = sim3d.utils.SemanticType(param.pose_list(i).instance_label);
    aname = sprintf("binActor%d", i);
    model = sim3d.Actor('ActorName', aname, ...
        'ActorClassId', inst_label);
    model.load(param.pose_list(i).model_path, [1 1 1] * 1.1);
    model.Mobility = sim3d.utils.MobilityTypes.Movable;
    model.Gravity = true;
    model.Physics = true;
    model.Shadows = true;
    model.Translation = param.pose_list(i).loc;
    model.Rotation = param.pose_list(i).rot;
    model.Shininess = param.Shininess;
    model.Color = colors(mod(i-1, height(colors)) + 1,:);
    model.Metallic = param.Metallic;
    model.Flat = param.Flat;
    model.Mass = 0.5;
    % Dropped parts land with spin; undamped, the straight fittings roll ~10 cm
    % from their spawn and break the gripper's nearest-spawn actor lookup.
    model.AngularDamping = 2;
    model.Restitution = 0.1;
    World.add(model, Actor);
end
end
