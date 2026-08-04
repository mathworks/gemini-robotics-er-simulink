classdef GeminiERBase < handle
    % GeminiERBase  Base strategy class for the Gemini Robotics-ER block.
    %
    %   The geminiERBlock System object populates TaskPrompt, Image,
    %   ScenarioPrompt and Trigger before each API call, then invokes:
    %     1. [img, userPrompt, systemPrompt] = mode.preprocess()
    %     2. out = mode.postprocess(apiResponse)
    %
    %   Subclasses override preprocess and postprocess to implement
    %   mode-specific behaviour (planning, verification, etc.).
    %
    %   See also GeminiERPlan, GeminiERVerify, geminiERBlock.

    properties (Constant, Access = protected)
        % Common output constraint appended to every system_instruction.
        SystemPrompt = 'Reply ONLY with valid JSON. Do not include markdown code fences or explanatory text.'
    end

    properties
        % Natural-language task or verification prompt.
        TaskPrompt = ""

        % Cell array of uint8 [H x W x 3] RGB images passed to Gemini.
        % Default: one slot (current image only).
        % Subclasses that need multiple images (e.g. before/after) initialise
        % more slots in their constructor.
        Images = {zeros(1, 1, 3, 'uint8')}

        % Scene context string (camera view, objects, workspace layout).
        % Set via the block mask ScenarioPrompt parameter.
        ScenarioPrompt = ""

        % Raw trigger input value (uint8).
        Trigger = uint8(0)
    end

    methods
        function tf = firesOnFirstStep(~)
            % Return true if this mode should call Gemini on the first simulation step.
            % Override to false in modes that should only fire on trigger (e.g. GeminiERVerify).
            tf = true;
        end

        function updateImages(obj, image, ~)
            % Default: single-slot mode — always update last slot with current frame.
            % Override in subclasses that need before/after image pairs (e.g. GeminiERVerify).
            obj.Images{end} = image;
        end

        function [img, userPrompt, systemPrompt] = preprocess(obj)
            % Default: pass last image and task prompt through unchanged.
            img          = obj.Images{end};
            userPrompt   = char(obj.TaskPrompt);
            systemPrompt = '';
        end

        function out = postprocess(~, ~)
            % Default: return true to indicate a successful API call.
            out = true;
        end

        function bus = createSimulinkBus(~)
            % Subclasses return a zero-valued struct matching their output bus.
            bus = struct();
        end
    end

    methods (Access = protected)
        function s = getSystemPrompt(obj)
            % Assembles the system_instruction from role, scenario, format schema,
            % and base JSON rules. Called by subclass preprocess() implementations.
            parts = {};
            role = obj.getRole();
            if ~isempty(role)
                parts{end+1} = role;
            end
            scenarioStr = strtrim(char(obj.ScenarioPrompt));
            if ~isempty(scenarioStr)
                parts{end+1} = scenarioStr;
            end
            schema = obj.getFormatSchema();
            if ~isempty(schema)
                parts{end+1} = schema;
            end
            parts{end+1} = obj.SystemPrompt;
            s = strjoin(parts, [newline newline]);
        end

        function s = getRole(~)
            % Override in subclasses to return the task-specific role prompt.
            s = '';
        end

        function s = getFormatSchema(~)
            % Override in subclasses to return the task-specific format schema.
            s = '';
        end
    end
end
