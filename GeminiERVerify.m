classdef GeminiERVerify < GeminiERBase
    % GeminiERVerify  Verification mode for the Gemini Robotics-ER block.
    %
    %   preprocess()  builds a system_instruction (role + scenario + format
    %                 schema for end-of-task scenario check) and a user
    %                 message containing the task clause.
    %
    %   postprocess() parses the Gemini JSON response into a pass/diagnostics
    %                 struct. On unexpected JSON, defaults to pass=true so
    %                 the Task Scheduler is not blocked (safe fallback).
    %
    %   buildVerifyPrompt  static method retained for backward compatibility
    %                      and standalone use (e.g. drop-check trigger=1).
    %
    %   See also GeminiERBase, GeminiERPlan, geminiERBlock.

    methods
        function obj = GeminiERVerify()
            % Two image slots: Images{1} = initial scene, Images{2} = current scene.
            obj.Images = {zeros(1, 1, 3, 'uint8'), zeros(1, 1, 3, 'uint8')};
        end

        function tf = firesOnFirstStep(~)
            % Verify mode waits for an explicit trigger — does not fire at sim start.
            tf = false;
        end

        function updateImages(obj, image, isFirstStep)
            % Two-slot before/after: anchor Images{1} once on the first step,
            % then always keep Images{2} current.
            if isFirstStep
                obj.Images{1} = image;
            end
            obj.Images{2} = image;
        end

        function [img, userPrompt, systemPrompt] = preprocess(obj)
            % Returns:
            %   systemPrompt — role + scenario + format schema (for system_instruction)
            %   userPrompt   — task clause only, e.g. 'Task: "Pick leftmost fitting..."'
            img = obj.Images{end};

            % System prompt: role + scenario + format schema (triggerType=2) + base JSON rule.
            systemPrompt = obj.getSystemPrompt();

            % User prompt: just the task clause (or empty if no task given).
            taskStr = strtrim(char(obj.TaskPrompt));
            if ~isempty(taskStr)
                userPrompt = ['Task: "' taskStr '"'];
            else
                userPrompt = 'Look at the current scene image.';
            end
        end

        function out = postprocess(~, apiResponse)
            % Parse JSON into struct with pass (logical) and diagnostics (string).
            % Expected: {"pass": bool, "diagnostics": "..."}
            % Safe fallback on any unexpected structure.
            try
                result = jsondecode(apiResponse);
                if isfield(result, 'pass')
                    passVal = logical(result.pass);
                else
                    passVal = true;
                end
                if isfield(result, 'diagnostics') && ~isempty(result.diagnostics)
                    diagStr = string(result.diagnostics);
                else
                    diagStr = string(apiResponse);
                end

            catch
                passVal = true;
                diagStr = string(apiResponse);
            end
            out = struct('pass', passVal, 'diagnostics', diagStr);
        end

        function zero = createSimulinkBus(~)
            % Zero-valued struct matching geminiVerifyResultBus.
            zero = struct('pass', false, 'diagnostics', "");
        end
    end

    methods (Access = protected)
        function s = getRole(~)
            s = [ ...
                'You are verifying a robot arm that performs intelligent bin picking.' newline ...
                'Your job is to analyse an overhead camera image and determine whether' newline ...
                'the robot has correctly completed its assigned task.'];
        end

        function s = getFormatSchema(~)
            % Format schema for end-of-task scenario check.
            s = [ ...
                'You are given two images:' newline ...
                '- Image 1: the scene at the start of the task (before the robot acted)' newline ...
                '- Image 2: the current scene (after the robot completed its actions)' newline newline ...
                'Compare the two images. Has every object specified in the task been placed' newline ...
                'at its correct destination?' newline ...
                'Identify any objects that were NOT placed correctly, using the same name/colour/shape' newline ...
                'language from the task (e.g. "The red tee fitting").' newline ...
                'Use this exact schema:' newline ...
                '{"pass": true,  "diagnostics": "Task successful. All objects placed correctly."}' newline ...
                '{"pass": false, "diagnostics": "Task unsuccessful. The <colour> <shape> fitting was not placed. ..."}' newline ...
                'Rules:' newline ...
                '- Only evaluate objects whose types are explicitly mentioned in the task.' newline ...
                '  Objects not mentioned in the task may remain in the bin — do NOT count them as failures.' newline ...
                '- List at most 3 unplaced named objects by colour/shape.' newline ...
                '- If more than 3 named objects are unplaced, append "N more unplaced."' newline ...
                '- No pixel coordinates. Keep diagnostics to 50 characters or fewer.'];
        end
    end

    methods (Static)
        function prompt = buildVerifyPrompt(triggerType, userPrompt)
            % buildVerifyPrompt  Build a standalone Gemini verification prompt.
            %
            %   prompt = GeminiERVerify.buildVerifyPrompt(triggerType, userPrompt)
            %
            %   Returns a self-contained prompt string (task clause + instructions
            %   + JSON schema) suitable for use outside the Simulink block, e.g.
            %   for drop-check (triggerType=1) or standalone testing.
            %
            %   triggerType  — uint8 scalar: 1 = drop check, 2 = scenario check
            %   userPrompt   — string or char: task description (may be empty)

            taskClause = '';
            if strtrim(string(userPrompt)) ~= ""
                if triggerType == uint8(1)
                    taskClause = ['Task context: "' char(userPrompt) '"' newline];
                else
                    taskClause = ['Task: "' char(userPrompt) '"' newline];
                end
            end

            if triggerType == uint8(1)
                prompt = [taskClause ...
                    'Look at the scene image.' newline ...
                    'The robot just released an object at its destination.' newline ...
                    'Is the object visibly at the intended destination — ' ...
                    'not dropped in the wrong location and not fallen off?' newline ...
                    'Reply ONLY with JSON: {"success": true, "message": "Object placed successfully."} or ' ...
                    '{"success": false, "message": "Object not at destination: <reason>."}'];
            else
                prompt = [taskClause ...
                    'Look at the current scene image.' newline ...
                    'Has every object specified in the task been placed at its correct destination?' newline ...
                    'Identify any objects that were NOT placed correctly, using the same name/colour/shape ' ...
                    'language from the task (e.g. "The red tee fitting").' newline ...
                    'Reply ONLY with JSON:' newline ...
                    '{"pass": true,  "diagnostics": "Task successful. All objects placed correctly."}' newline ...
                    '{"pass": false, "diagnostics": "Task unsuccessful. The <colour> <shape> fitting was not placed. ..."}' newline ...
                    'Rules for the diagnostics string:' newline ...
                    '- List at most 3 unplaced objects by name/colour/shape.' newline ...
                    '- If more than 3 are unplaced, append "N more object(s) remain in the bin."' newline ...
                    '- Do not include pixel coordinates.' newline ...
                    '- Keep the diagnostics string to 50 characters or fewer.'];
            end
        end
    end
end
