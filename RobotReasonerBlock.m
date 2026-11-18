classdef (StrictDefaults) RobotReasonerBlock < matlab.System
% Reasoner-agnostic orchestrator: wires a reasoning chain of prompt+parse reasoners to a reasoning-model Client, running preprocess -> call -> postprocess for each reasoner on every Trigger rising edge (0 -> 1).

    properties (Nontunable)
        % Reasoner
        % A ReasonerBase object, or an ordered cell array of them {R1, R2, ...} forming a reasoning chain; the terminal reasoner's outputStruct() must match BusName.
        Reasoner {mustBeReasoner} = {}

        % Output bus name
        % Registered Simulink.Bus type name for this block's output; must match the terminal reasoner's outputStruct() shape.
        BusName (1,1) string = "geminiPixelDetectionsBus"

        % Reasoning model provider
        % Backend the block resolves a transport Client for.
        Provider (1,1) string {mustBeMember(Provider, "Gemini Robotics ER2.0")} = "Gemini Robotics ER2.0"
    end

    properties (Access = private)
        % ResolvedClient - Transport Client used at runtime.
        ResolvedClient

        % CachedOutput - Last terminal-reasoner output; returned between triggers.
        CachedOutput

        % Images - Two-slot RGB buffer {before, current} (block-owned).
        Images

        % IsFirstStep - Whether the current step is the first simulation step (anchors the "before" image).
        IsFirstStep  (1,1) logical = true

        % LastTrigger - Trigger value seen on the previous step.
        LastTrigger  (1,1) uint8   = 0

        % Attempt - Number of times the reasoning chain has fired this simulation.
        Attempt      (1,1) double  = 0

        % PreviousData - context.Data left by the previous fire; seeds context.Previous (empty struct before the first fire).
        PreviousData = struct()
    end

    methods
        function obj = RobotReasonerBlock(varargin)
            % Construct the block, applying name-value property settings.
            setProperties(obj, nargin, varargin{:});
        end
    end

    methods (Access = protected)
        function setupImpl(obj)
            % Resolve the transport Client for the selected Provider and reset state (no reasoning call here).
            % The empty check lives here, not in validatePropertiesImpl, so the
            % library block (Reasoner unset) still accepts parameter edits.
            if isempty(obj.Reasoner)
                error("RobotReasonerBlock:MissingReasoner", ...
                    "Specify a Reasoner: a ReasonerBase object or a cell array of them.");
            end
            obj.ResolvedClient = obj.resolveClient();

            obj.IsFirstStep  = true;
            obj.LastTrigger  = uint8(0);
            obj.Attempt      = 0;
            obj.PreviousData = struct();
            reasoners        = obj.reasonerChain();
            obj.CachedOutput = reasoners{end}.outputStruct();
            obj.Images       = {zeros(1, 1, 3, 'uint8'), zeros(1, 1, 3, 'uint8')};
        end

        function out = stepImpl(obj, taskPrompt, image, trigger)
            % Buffer the frame and, on a trigger rising edge (0 -> 1), run the reasoning chain and return (and cache) the terminal output.
            obj.updateImages(image);

            fire            = uint8(trigger) == 1 && obj.LastTrigger == 0;
            obj.LastTrigger = uint8(trigger);
            obj.IsFirstStep = false;

            if fire
                reasoners = obj.reasonerChain();
                % Label the fire log with the terminal (output-producing) reasoner.
                fprintf('[%s] Task: %s\n', class(reasoners{end}), taskPrompt);

                % Seed the shared context, then run each reasoner in sequence:
                % preprocess(context) -> client.call -> postprocess(raw, context).
                % The context is threaded so a reasoner can read an earlier
                % reasoner's output; the terminal reasoner writes context.Output.
                % context.Previous carries the previous fire's Data, so a re-plan
                % can see the earlier attempt.
                obj.Attempt = obj.Attempt + 1;
                context = obj.seedContext(taskPrompt, reasoners);
                for k = 1:numel(reasoners)
                    [images, userPrompt, instructions] = reasoners{k}.preprocess(context);
                    if isempty(images)
                        % Cache-hit sentinel (no images): the reasoner reuses its cached
                        % output; skip the (expensive) model call and hand it "".
                        context = reasoners{k}.postprocess("", context);
                    else
                        rawResponse = obj.ResolvedClient.call(userPrompt, images, ...
                            Instructions=instructions);
                        context = reasoners{k}.postprocess(rawResponse, context);
                    end
                end
                obj.CachedOutput = context.Output;
                obj.PreviousData = context.Data;
            end

            out = obj.CachedOutput;
        end

        function num = getNumInputsImpl(~)
            num = 3;
        end

        function names = getInputNamesImpl(~)
            names = ["Task Prompt", "Image", "Trigger"];
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
            % Output bus type name from the BusName mask property, with any stray surrounding double quotes stripped.
            dt = char(strip(obj.BusName, '"'));
        end

        function flag = isOutputComplexImpl(~)
            flag = false;
        end

        function flag = isOutputFixedSizeImpl(~)
            flag = true;
        end
    end

    methods (Access = private)
        function reasoners = reasonerChain(obj)
            % The Reasoner property as a cell array: a single reasoner becomes a one-element chain.
            reasoners = obj.Reasoner;
            if ~iscell(reasoners)
                reasoners = {reasoners};
            end
        end

        function updateImages(obj, image)
            % Two-slot before/after buffer: anchor slot 1 once on the first step and always keep slot 2 current.
            if obj.IsFirstStep
                obj.Images{1} = image;
            end
            obj.Images{2} = image;
        end

        function context = seedContext(obj, taskPrompt, reasoners)
            % Build the shared reasoning-chain context, seeding Output with the terminal reasoner's zero-valued prototype and Previous with the previous fire's Data.
            context = struct( ...
                'Task',     string(taskPrompt), ...
                'Images',   {obj.Images}, ...
                'Attempt',  obj.Attempt, ...
                'Data',     struct(), ...
                'Previous', obj.PreviousData, ...
                'Output',   reasoners{end}.outputStruct());
        end

        function client = resolveClient(obj)
            % Map the selected Provider to a transport Client.
            switch obj.Provider
                case "Gemini Robotics ER2.0"
                    % GeminiClient picks the backend (Agent Platform with ADC
                    % or Developer API key) from environment variables.
                    client = GeminiClient();
                otherwise
                    error("RobotReasonerBlock:UnknownProvider", ...
                        "Unknown Provider ""%s"".", obj.Provider);
            end
        end
    end

    methods (Access = protected)
        function icon = getIconImpl(~)
            % Block mask icon, resolved from the repo dir on the MATLAB path.
            icon = matlab.system.display.Icon( ...
                fullfile(fileparts(mfilename("fullpath")), "images", ...
                "RobotReasoner.svg"));
        end
    end

    methods (Static, Access = protected)
        function flag = getSimulateUsingImpl
            % Force interpreted execution (Python interop; no codegen).
            flag = 'Interpreted execution';
        end

        function flag = showSimulateUsingImpl
            flag = false;
        end

        function header = getHeaderImpl
            header = matlab.system.display.Header( ...
                Title="Robot Reasoner", ...
                Text=['Choose the reasoning-model provider and reasoner(s). Each reasoner ' ...
                    'carries its own scene and schema Instructions. Credentials are ' ...
                    'read from environment variables.']);
        end

        function groups = getPropertyGroupsImpl
            groups = matlab.system.display.Section( ...
                Title="Configuration", ...
                Description='Set the provider and reasoner(s).', ...
                PropertyList={'Provider', 'Reasoner', 'BusName'}, ...
                AlignPrompts=true);
        end
    end
end

function mustBeReasoner(value)
% Validate Reasoner: empty (unset), a scalar ReasonerBase, or a cell array of scalar ReasonerBase objects.
    if iscell(value)
        isValid = all(cellfun(@(r) isa(r, "ReasonerBase") && isscalar(r), value));
    else
        isValid = isempty(value) || (isa(value, "ReasonerBase") && isscalar(value));
    end
    if ~isValid
        error("RobotReasonerBlock:InvalidReasoner", ...
            "Reasoner must be a ReasonerBase object or a cell array of ReasonerBase objects.");
    end
end
