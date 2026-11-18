classdef TaskPlanner < ReasonerBase
% Planning reasoner (terminal): detect the task's objects and plan one pick point, drop point, and pick priority each in a single Gemini Robotics ER call (point-based, Gemini's native [y, x] normalized 0-1000; [x y] pixels on the bus).

    properties
        % ResizeImageTo - imresize [numrows numcols] target applied before sending (NaN in one slot preserves aspect); [] keeps the original size.
        ResizeImageTo double = []

        % MaxItems - Maximum objects per plan; bounds the fixed-size output struct (kept in sync with the base-workspace MaxDetections in initPlannerGeminiER and pixelPlanToWorldBlock).
        MaxItems (1,1) double = 8
    end

    properties (Constant, Access = private)
        % CoordScale - Range coordinates are normalized to.
        CoordScale = 1000

        % CenterKeys - Pick-point keys, in order: center_2d, then Gemini's native point, then a box_2d center.
        CenterKeys = ["center_2d", "point", "box_2d"]

        % DropKeys - Drop-point keys, in order: drop_center_2d, then a drop_box_2d center.
        DropKeys = ["drop_center_2d", "drop_box_2d"]
    end

    methods
        function obj = TaskPlanner(options)
            % Construct a TaskPlanner reasoner.
            arguments
                options.Instructions (1,1) string
                options.InstructionsFile (1,1) string {mustBeFile}
                options.ResizeImageTo double = []
                options.MaxItems (1,1) double = 8
                options.SaveArtifacts (1,1) logical = false
                options.WriteArtifactsDir (1,1) string = ""
            end
            obj@ReasonerBase(ReasonerBase.resolveInstructions(options, "TaskPlanner"));
            obj.ResizeImageTo     = options.ResizeImageTo;
            obj.MaxItems          = options.MaxItems;
            obj.SaveArtifacts     = options.SaveArtifacts;
            obj.WriteArtifactsDir = options.WriteArtifactsDir;
        end

        function [image, userPrompt, instructions] = preprocess(obj, context)
            % Resize the current frame; the user prompt is the task instruction (or a detect-all fallback).
            image = context.Images{end};
            if ~isempty(obj.ResizeImageTo)
                image = imresize(image, obj.ResizeImageTo, 'lanczos3');
            end

            task = strtrim(context.Task);
            if strlength(task) > 0
                userPrompt = "Instruction: " + task;
            else
                userPrompt = "Detect all objects visible in this image.";
            end
            instructions = obj.composeInstructions();
        end

        function context = postprocess(obj, rawResponse, context)
            % Decode the plan into context.Data.plan, then convert its normalized points to full-frame pixels and pack the fixed-size output.
            plan = obj.decodePlan(rawResponse);
            context.Data.plan = plan;

            % Normalized 0-1000 points -> pixels against the full-res scene
            % (context.Images{end} stays full resolution; the per-reasoner resize
            % only affects the sent image, not the mapping).
            [imageHeight, imageWidth, ~] = size(context.Images{end});
            context.Output = obj.packPlan(plan, imageWidth, imageHeight, context.Attempt);

            if obj.SaveArtifacts
                obj.saveArtifacts(obj.artifactStem("plan", context), ...
                    rawResponse, plan, context.Images{end}, context.Task);
            end
        end

        function outStruct = outputStruct(obj)
            % Zero-valued prototype of the fixed-size point-based plan struct (terminal reasoner; maps to geminiPixelDetectionsBus); attempt 0 = no plan yet.
            outStruct = struct( ...
                'attempt',     0, ...
                'count',       0, ...
                'pick_center', zeros(obj.MaxItems, 2), ...
                'drop_center', zeros(obj.MaxItems, 2), ...
                'pick_order',  zeros(obj.MaxItems, 1, 'int32'));
        end
    end

    methods (Access = private)
        function saveArtifacts(obj, stem, rawResponse, plan, fullFrame, task)
            % Write the raw response + decoded plan, and the full frame with pick dots, pick->drop arrows, and the task banner.
            jsonData = struct( ...
                'rawResponse', string(strtrim(rawResponse)), ...
                'plan',        plan);
            annotated = ImageAnnotator.drawPlan(fullFrame, plan);
            annotated = ImageAnnotator.drawTaskBanner(annotated, task);
            obj.writeArtifacts(stem, jsonData, annotated);
        end

        function out = packPlan(obj, plan, imageWidth, imageHeight, attempt)
            % Pack the plan into the fixed-size output struct: normalized [x y] points -> full-frame [x y] pixels (a missing drop stays [0 0]), pick order from pick_priority (array order when absent), stamped with the fire's attempt.
            count       = min(numel(plan), obj.MaxItems);
            pick_center = zeros(obj.MaxItems, 2);
            drop_center = zeros(obj.MaxItems, 2);
            pick_order  = zeros(obj.MaxItems, 1, 'int32');

            for k = 1:count
                pick_center(k, :) = obj.toPixel(plan(k).center_2d, imageWidth, imageHeight);
                if ~isempty(plan(k).drop_center_2d)
                    drop_center(k, :) = obj.toPixel(plan(k).drop_center_2d, imageWidth, imageHeight);
                end
                if plan(k).pick_priority > 0
                    pick_order(k) = int32(plan(k).pick_priority);
                else
                    pick_order(k) = int32(k);
                end
            end

            out = struct( ...
                'attempt',     attempt, ...
                'count',       count, ...
                'pick_center', pick_center, ...
                'drop_center', drop_center, ...
                'pick_order',  pick_order);
        end
    end

    methods (Static, Access = private)
        function pixel = toPixel(point, imageWidth, imageHeight)
            % Normalized [x y] (0-1000) -> rounded integer pixel [x y] against the given size (output bus carries doubles, but pick/drop points must land on whole pixels).
            pixel = [ ...
                round(point(1) / TaskPlanner.CoordScale * imageWidth), ...
                round(point(2) / TaskPlanner.CoordScale * imageHeight)];
        end

        function plan = decodePlan(rawResponse)
            % Decode the JSON array into a struct array {label, center_2d, drop_center_2d, pick_priority} with [x y] points; items without a usable pick point are dropped, and an undecodable answer yields an empty plan.
            plan = struct('label', {}, 'center_2d', {}, 'drop_center_2d', {}, 'pick_priority', {});
            try
                decoded = jsondecode(rawResponse);
            catch
                return
            end
            if isstruct(decoded)
                decoded = num2cell(decoded);
            elseif ~iscell(decoded)
                return
            end

            for k = 1:numel(decoded)
                item = decoded{k};
                if ~isstruct(item)
                    continue
                end
                center = TaskPlanner.pointOf(item, TaskPlanner.CenterKeys);
                if isempty(center)
                    continue
                end
                plan(end + 1) = struct( ...
                    'label',          TaskPlanner.labelOf(item), ...
                    'center_2d',      center, ...
                    'drop_center_2d', TaskPlanner.pointOf(item, TaskPlanner.DropKeys), ...
                    'pick_priority',  TaskPlanner.priorityOf(item)); %#ok<AGROW>
            end
        end

        function value = fieldOrEmpty(item, name)
            % Case-insensitive field lookup, [] if absent.
            value = [];
            names = string(fieldnames(item));
            matched = names(lower(names) == lower(name));
            if ~isempty(matched)
                value = item.(matched(1));
            end
        end

        function point = pointOf(item, keys)
            % A normalized [x y] point (0-1000) from the first usable key, or [] if none: Gemini answers [y, x], and a 4-value [y_min x_min y_max x_max] box yields its center.
            point = [];
            for key = keys
                value = TaskPlanner.fieldOrEmpty(item, key);
                if ~isnumeric(value)
                    continue
                end
                value = double(value(:).');
                if numel(value) == 4
                    value = [value(1) + value(3), value(2) + value(4)] / 2;
                end
                if numel(value) == 2 && all(value >= 0 & value <= TaskPlanner.CoordScale)
                    point = fliplr(value);
                    return
                end
            end
        end

        function label = labelOf(item)
            % The object's label as a string, "" if absent.
            label = "";
            value = TaskPlanner.fieldOrEmpty(item, "label");
            if ischar(value) || isstring(value)
                label = string(value);
            end
        end

        function priority = priorityOf(item)
            % pick_priority as a positive integer, or 0 if absent or invalid.
            priority = 0;
            value = TaskPlanner.fieldOrEmpty(item, "pick_priority");
            if isnumeric(value) && isscalar(value) && value >= 1 && value == round(value)
                priority = double(value);
            end
        end
    end
end
