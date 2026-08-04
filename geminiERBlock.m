classdef (StrictDefaults) geminiERBlock < matlab.System
    % geminiERBlock  Generic Gemini Robotics-ER Simulink block.
    %
    %   A single mode-agnostic block that owns Python interop and the Gemini
    %   API call.  Mode-specific preprocessing and postprocessing are delegated
    %   to a GeminiERBase subclass instance (GeminiERPlan or GeminiERVerify)
    %   stored in the Mode property, which is set via the block mask.
    %
    %   Inputs:
    %     taskPrompt — string scalar; task description or pre-built verify prompt
    %     image      — uint8 [H x W x 3] RGB image from the camera
    %     trigger    — uint8 scalar; rising edge (0→1) triggers a new Gemini call
    %
    %   Output:
    %     out — bus or struct defined by Mode.createSimulinkBus()
    %            GeminiERPlan:   raw pixel detections (count, boxes, pick_order, drop_boxes)
    %            GeminiERVerify: verification result (pass, diagnostics)
    %
    %   Block mask parameters:
    %     Mode           — MATLAB expression, e.g. GeminiERPlan() or GeminiERVerify()
    %     ScenarioPrompt — scene context string (text-wrap enabled in Mask Editor)
    %
    %   The Gemini API is called on the first simulation step and on every
    %   rising edge of trigger.  Results are cached between calls.
    %
    %   Requires GEMINI_API_KEY set as an environment variable (or ApiKey
    %   property when UseEnvApiKey = false).
    %
    %   See also GeminiERPlan, GeminiERVerify, pixelPlanToWorldBlock.

    properties (Nontunable)
        % Mode object (GeminiERPlan or GeminiERVerify). Implements
        % preprocess/postprocess for a specific Gemini use case.
        Mode = []

        % Scene context forwarded to Mode.ScenarioPrompt before each API call.
        % Describes the camera view, objects, and workspace layout.
        % Set via block mask (text-wrap param).
        ScenarioPrompt (1,1) string = ...
            "The scene is viewed from a camera mounted directly above the work cell, looking straight down." + newline + ...
            "The bin in the centre contains white plastic pipe fittings of four types: cross, tee, elbow, and straight." + newline + ...
            "Two placement tables are positioned on either side of the bin."

        % Read the API key from the GEMINI_API_KEY environment variable.
        UseEnvApiKey (1,1) logical = true

        % Gemini API key. Used only when UseEnvApiKey is false.
        ApiKey (1,1) string = ""

        % Thinking budget for Gemini extended thinking.
        % 0 = no thinking (fastest). -1 = unlimited.
        ThinkingBudget (1,1) double = 0
    end

    properties (Access = private)
        Client          % Python GeminiClient instance
        CachedOutput    % last postprocess() result; returned between triggers
        IsFirstStep  (1,1) logical = true
        LastTrigger  (1,1) uint8   = 0
    end

    methods
        function obj = geminiERBlock(varargin)
            setProperties(obj, nargin, varargin{:});
        end
    end

    methods (Access = protected)
        function setupImpl(obj, ~, ~, ~)
            % Initialise Python interop.
            % Gemini is NOT called here — Simulink passes dummy inputs during setup.
            coreDir = fileparts(mfilename('fullpath'));
            if count(py.sys.path, coreDir) == 0
                insert(py.sys.path, int32(0), coreDir);
            end
            pyMod = py.importlib.import_module('geminiClient');
            py.importlib.reload(pyMod);

            if obj.UseEnvApiKey
                apiKey = string(getenv('GEMINI_API_KEY'));
            else
                apiKey = obj.ApiKey;
            end
            obj.Client      = pyMod.GeminiClient(apiKey);
            obj.IsFirstStep = true;
            obj.LastTrigger = uint8(0);
            obj.CachedOutput = obj.Mode.createSimulinkBus();
            obj.Mode.Images(:) = {zeros(1, 1, 3, 'uint8')};
        end

        function out = stepImpl(obj, taskPrompt, image, trigger)
            % Delegate image slot management to the mode (mode-specific anchoring logic).
            obj.Mode.updateImages(image, obj.IsFirstStep);

            % Fire on any trigger value change; plan mode also fires on first step.
            triggered  = (uint8(trigger) ~= obj.LastTrigger);
            obj.LastTrigger = uint8(trigger);
            shouldFire = triggered || (obj.IsFirstStep && obj.Mode.firesOnFirstStep());

            if shouldFire
                fprintf('[%s] Task prompt: %s\n', class(obj.Mode), taskPrompt);

                % Populate Mode inputs.
                obj.Mode.TaskPrompt     = string(taskPrompt);
                obj.Mode.ScenarioPrompt = obj.ScenarioPrompt;
                obj.Mode.Trigger        = uint8(trigger);

                % Preprocess -> call Gemini -> postprocess.
                [img, userPrompt, systemPrompt] = obj.Mode.preprocess();

                % Replace last slot with preprocessed image (e.g. cropped/resized).
                imgs      = obj.Mode.Images;
                imgs{end} = img;

                pyImgList = cell(1, numel(imgs));
                for k = 1:numel(imgs)
                    pyImgList{k} = py.numpy.array(imgs{k});
                end

                thinkingBudget = int32(obj.ThinkingBudget);
                raw = string(obj.Client.call(py.list(pyImgList), userPrompt, systemPrompt, thinkingBudget));

                obj.CachedOutput = obj.Mode.postprocess(raw);
            end

            % Always clear after the first step so Images{1} is never overwritten again.
            obj.IsFirstStep = false;

            out = obj.CachedOutput;
        end

        function num = getNumInputsImpl(~)
            num = 3;
        end

        function names = getInputNamesImpl(~)
            names = ["taskPrompt", "image", "trigger"];
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

        function dt = getOutputDataTypeImpl(obj)
            % Return the bus type name defined by the Mode subclass.
            if isa(obj.Mode, 'GeminiERPlan')
                dt = 'geminiPixelDetectionsBus';
            else
                dt = 'geminiVerifyResultBus';
            end
        end

        function flag = isOutputComplexImpl(~)
            flag = false;
        end

        function flag = isOutputFixedSizeImpl(~)
            flag = true;
        end

        function flag = isInactivePropertyImpl(obj, prop)
            switch prop
                case 'ApiKey'
                    flag = obj.UseEnvApiKey;
                case 'ThinkingBudget'
                    flag = ~isa(obj.Mode, 'GeminiERVerify');
                otherwise
                    flag = false;
            end
        end

    end

    methods (Static, Access = protected)
        function flag = getSimulateUsingImpl
            % Python interop requires Interpreted execution — cannot use codegen.
            flag = 'Interpreted execution';
        end

        function flag = showSimulateUsingImpl
            flag = false;
        end

        function groups = getPropertyGroupsImpl
            taskSection = matlab.system.display.Section( ...
                'Title',        'Mode', ...
                'PropertyList', {'Mode', 'ScenarioPrompt', 'ThinkingBudget'});

            apiSection = matlab.system.display.Section( ...
                'Title',        'API', ...
                'PropertyList', {'UseEnvApiKey', 'ApiKey'});

            groups = matlab.system.display.SectionGroup( ...
                'Sections', [apiSection, taskSection]);
        end
    end
end
