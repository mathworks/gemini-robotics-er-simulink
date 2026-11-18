classdef TaskVerifier < ReasonerBase
% Task-verification reasoner (terminal): compare a before/after image pair against the task and report whether the robot completed it.

    properties
        % ResizeImageTo - imresize [numrows numcols] target applied to each image before sending (NaN in one slot preserves aspect); [] keeps the original size.
        ResizeImageTo double = []
    end

    methods
        function obj = TaskVerifier(options)
            % Construct a TaskVerifier reasoner.
            arguments
                options.Instructions (1,1) string
                options.InstructionsFile (1,1) string {mustBeFile}
                options.ResizeImageTo double = []
                options.SaveArtifacts (1,1) logical = false
                options.WriteArtifactsDir (1,1) string = ""
            end
            obj@ReasonerBase(ReasonerBase.resolveInstructions(options, "TaskVerifier"));
            obj.ResizeImageTo     = options.ResizeImageTo;
            obj.SaveArtifacts     = options.SaveArtifacts;
            obj.WriteArtifactsDir = options.WriteArtifactsDir;
        end

        function [images, userPrompt, instructions] = preprocess(obj, context)
            % Send the (resized) before/after pair with a task-clause user prompt and a compare-schema system prompt.
            images = context.Images;
            if ~isempty(obj.ResizeImageTo)
                images = cellfun(@(image) imresize(image, obj.ResizeImageTo, 'lanczos3'), ...
                    images, UniformOutput=false);
            end
            instructions = obj.composeInstructions();

            task = strtrim(context.Task);
            if strlength(task) > 0
                userPrompt = "Task: """ + task + """";
            else
                userPrompt = "Look at the current scene image.";
            end
        end

        function context = postprocess(obj, rawResponse, context)
            % Parse {"pass": bool, "diagnostics": "..."} into context.Data.verify and context.Output (falls back to pass=true), stamped with context.Attempt.
            passValue   = true;
            diagnostics = string(rawResponse);
            try
                decoded = jsondecode(rawResponse);
                if isfield(decoded, 'pass')
                    passValue = logical(decoded.pass);
                end
                if isfield(decoded, 'diagnostics') && ~isempty(decoded.diagnostics)
                    diagnostics = string(decoded.diagnostics);
                end
            catch
                % Leave the safe fallback (pass=true, raw text) in place.
            end
            verify = struct('attempt', context.Attempt, 'pass', logical(passValue), ...
                'diagnostics', string(diagnostics));
            context.Data.verify = verify;
            context.Output      = verify;

            if obj.SaveArtifacts
                obj.saveArtifacts(obj.artifactStem("verify", context), ...
                    rawResponse, verify, context.Images);
            end
        end

        function outStruct = outputStruct(~)
            % Idle prototype of the verify output (terminal reasoner; maps to geminiVerifyResultBus); attempt 0 = not verified yet.
            outStruct = struct('attempt', 0, 'pass', false, 'diagnostics', "Not verified yet");
        end
    end

    methods (Access = private)
        function saveArtifacts(obj, stem, rawResponse, verify, images)
            % Write the raw response + verdict, the after-frame banner-annotated with pass/diagnostics, and the raw before/after input frames (<stem>_before/_after.png) for offline replay.
            jsonData = struct( ...
                'rawResponse', string(strtrim(rawResponse)), ...
                'pass',        verify.pass, ...
                'diagnostics', verify.diagnostics);
            obj.writeArtifacts(stem, jsonData, ...
                ImageAnnotator.drawVerdict(images{end}, verify));
            obj.writeImageArtifact(stem + "_before", images{1});
            obj.writeImageArtifact(stem + "_after", images{end});
        end
    end
end
