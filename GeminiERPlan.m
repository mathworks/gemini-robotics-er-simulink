classdef GeminiERPlan < GeminiERBase
    % GeminiERPlan  Planning mode for the Gemini Robotics-ER block.
    %
    %   preprocess()  applies optional crop mask and image resize, storing
    %                 the inverse transform for box rescaling in postprocess.
    %                 Returns a system_instruction (role + scenario + format
    %                 schema) and a user message (task instruction).
    %
    %   postprocess() parses the Gemini JSON response into a raw pixel
    %                 detections struct with fields:
    %                   count      — number of valid detections (double)
    %                   boxes      — [MaxDetections x 4] pick bounding boxes (pixels)
    %                   pick_order — [MaxDetections x 1] int32 pick sequence
    %                   drop_boxes — [MaxDetections x 4] drop bounding boxes (pixels)
    %
    %   Depth back-projection and world-frame conversion are NOT done here —
    %   those are delegated to the downstream pixelPlanToWorldBlock.
    %
    %   Box coordinate convention: [y_min, x_min, y_max, x_max] (row-major).
    %   geminiClient.py rescales Gemini's 0-1000 normalised coords to thumbnail
    %   pixels before returning; preprocess/postprocess convert to original pixels.
    %
    %   See also GeminiERBase, GeminiERVerify, geminiERBlock, pixelPlanToWorldBlock.

    properties
        % Apply bin crop mask before sending the image to Gemini.
        ApplyMask (1,1) logical = false

        % Crop mask corners [x, y] in image pixels:
        %   row 1 = top-left, row 2 = top-right,
        %   row 3 = bottom-right, row 4 = bottom-left.
        % Matches PoseMaskRCNNModel.TargetBinaryMask.
        TargetBinaryMask (4,2) double = [264, 101; 1015, 101; 1015, 612; 264, 612]

        % Pixel value assigned to regions outside the crop mask.
        MaskFillValue (1,1) uint8 = 100

        % Resize so the longest image edge equals this value (pixels).
        % Set 0 to skip resizing.
        MaxLongEdge (1,1) double = 640

        % Maximum objects per plan. Must match initPlannerGeminiER and the
        % detectionsToWorld block (IBP example hardcodes 8).
        MaxDetections (1,1) double = 8
    end

    properties (Access = private)
        % Inverse transform stored by preprocess(), consumed by postprocess().
        OrigSize  (1,2) double = [1, 1]
        RowOffset (1,1) double = 0
        ColOffset (1,1) double = 0
    end

    methods
        function obj = GeminiERPlan(options)
            arguments
                options.ApplyMask        (1,1) logical = false
                options.TargetBinaryMask (4,2) double  = [264, 101; 1015, 101; 1015, 612; 264, 612]
                options.MaskFillValue    (1,1) uint8   = uint8(100)
                options.MaxLongEdge      (1,1) double  = 640
                options.MaxDetections    (1,1) double  = 8
            end
            obj.ApplyMask        = options.ApplyMask;
            obj.TargetBinaryMask = options.TargetBinaryMask;
            obj.MaskFillValue    = options.MaskFillValue;
            obj.MaxLongEdge      = options.MaxLongEdge;
            obj.MaxDetections    = options.MaxDetections;
        end

        function [img, userPrompt, systemPrompt] = preprocess(obj)
            % Apply crop mask and/or resize; store offsets for box rescaling.
            % Returns:
            %   systemPrompt — role + scenario + format schema (for system_instruction)
            %   userPrompt   — task instruction only (for user message contents)
            img       = obj.Images{end};
            rowOffset = 0;
            colOffset = 0;

            if obj.ApplyMask
                [img, rowOffset, colOffset] = obj.applyMask(img);
            end

            origSize = [size(img, 1), size(img, 2)];
            if obj.MaxLongEdge > 0 && max(origSize) > obj.MaxLongEdge
                scale   = obj.MaxLongEdge / max(origSize);
                newSize = max(1, round(origSize * scale));
                img     = imresize(img, newSize, 'lanczos3');
            end

            obj.OrigSize  = origSize;
            obj.RowOffset = rowOffset;
            obj.ColOffset = colOffset;

            % System prompt: role + scenario + format schema + base JSON rule.
            systemPrompt = obj.getSystemPrompt();

            % User prompt: just the task instruction (or detection fallback).
            taskStr = strtrim(char(obj.TaskPrompt));
            if ~isempty(taskStr)
                userPrompt = ['Instruction: ' taskStr];
            else
                userPrompt = 'Detect all objects visible in this image.';
            end
        end

        function out = postprocess(obj, apiResponse)
            % Parse Gemini JSON and rescale boxes to original pixel coords.
            %
            % apiResponse — JSON string from GeminiClient.plan(); boxes are
            %               already in thumbnail pixel coords (rescaled by Python).
            data  = jsondecode(apiResponse);
            N     = numel(data);
            Nplan = min(N, obj.MaxDetections);

            normScale = [obj.OrigSize(1)/1000, obj.OrigSize(2)/1000, ...
                         obj.OrigSize(1)/1000, obj.OrigSize(2)/1000];
            boxOffset = [obj.RowOffset, obj.ColOffset, obj.RowOffset, obj.ColOffset];

            boxes      = zeros(obj.MaxDetections, 4);
            pick_order = zeros(obj.MaxDetections, 1, 'int32');
            drop_boxes = zeros(obj.MaxDetections, 4);

            for i = 1:Nplan
                boxes(i, :) = round(data(i).box_2d(:)' .* normScale) + boxOffset;

                if isfield(data(i), 'drop_box_2d') && ~isempty(data(i).drop_box_2d)
                    drop_boxes(i, :) = round(data(i).drop_box_2d(:)' .* normScale) + boxOffset;
                end

                if isfield(data(i), 'pick_priority')
                    pick_order(i) = int32(data(i).pick_priority);
                else
                    pick_order(i) = int32(i);   % fallback: array order
                end
            end

            out = struct( ...
                'count',      Nplan, ...
                'boxes',      boxes, ...
                'pick_order', pick_order, ...
                'drop_boxes', drop_boxes);
        end

        function bus = createSimulinkBus(obj)
            % Zero-valued struct matching the raw pixel detections output.
            bus = struct( ...
                'count',      0, ...
                'boxes',      zeros(obj.MaxDetections, 4), ...
                'pick_order', zeros(obj.MaxDetections, 1, 'int32'), ...
                'drop_boxes', zeros(obj.MaxDetections, 4));
        end
    end

    methods (Access = protected)
        function s = getRole(~)
            s = [ ...
                'You are guiding a robot arm that performs intelligent bin picking.' newline ...
                'Your job is to analyse an overhead camera image and return structured JSON' newline ...
                'that identifies objects to pick and their destinations.'];
        end

        function s = getFormatSchema(~)
            s = [ ...
                'For each relevant object return a JSON array. Each element MUST include:' newline ...
                '  "label"  : colour + shape name (e.g. "red tee fitting")' newline ...
                '  "box_2d" : [y_min, x_min, y_max, x_max]  — pick bounding box' newline newline ...
                'If the instruction involves placing objects, ALSO include:' newline ...
                '  "drop_box_2d"   : [y_min, x_min, y_max, x_max]  — centred on the exact free drop spot;' newline ...
                '                    each object MUST get a DIFFERENT, non-overlapping drop_box_2d' newline ...
                '  "pick_priority" : integer, 1 = pick first, unique per object' newline newline ...
                'If detection-only (find / show / identify / detect), omit drop_box_2d and pick_priority.' newline ...
                'All coordinates are normalised 0–1000.'];
        end
    end

    methods (Access = private)
        function [imgOut, rowOffset, colOffset] = applyMask(obj, imgIn)
            % Apply the same crop-mask as PoseMaskRCNNModel:
            %   pixels outside TargetBinaryMask polygon -> MaskFillValue
            % Then crop to the axis-aligned bounding box of the mask.
            m    = obj.TargetBinaryMask;
            mask = poly2mask(m(:,1)', m(:,2)', size(imgIn,1), size(imgIn,2));

            imgOut = imgIn;
            imgOut(repmat(~mask, [1 1 3])) = obj.MaskFillValue;

            rowOffset = min(m(:,2));
            colOffset = min(m(:,1));
            rowEnd    = max(m(:,2));
            colEnd    = max(m(:,1));
            imgOut    = imgOut(rowOffset:rowEnd, colOffset:colEnd, :);
        end
    end
end
