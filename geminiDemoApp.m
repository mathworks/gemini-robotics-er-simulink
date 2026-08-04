function geminiDemoApp
% geminiDemoApp  App to configure and run Gemini ER pick-and-place scenarios.
%   Select a predefined scenario or write a custom task prompt, optionally
%   randomize object positions, then simulate.

scenarios = struct( ...
    'ShapeSort', "Place all elbow fittings on the right table. Place all cross fittings on the left table.", ...
    'Positional', "Pick the leftmost fitting and place it on the left table. Pick the rightmost fitting and place it on the right table.", ...
    'Priority', "Pick the cyan cross fitting and place them on the left table. Then pick the green tee fitting and place it on the right table. Then pick the red tee fitting and place it on the right table. Leave the black and pink fittings in the bin.", ...
    'ColorSort', "Place all warm-colored fittings (red, magenta) on the right table. Place all cool-colored fittings (blue, cyan, green) on the left table. Leave any black fittings in the bin.");

scenarioNames = fieldnames(scenarios);

% Open model if not already loaded
modelName = 'IntelligentBinPickingGemini';
if ~bdIsLoaded(modelName)
    open_system(modelName);
    robotSimParams
end

% Build UI
fig = uifigure('Name', 'Gemini ER Scenario Runner', 'Position', [100 100 620 420]);
gl = uigridlayout(fig, [6 3], ...
    'RowHeight', {30, 28, 30, '1x', 22, 40}, ...
    'ColumnWidth', {'fit', '1x', 'fit'}, ...
    'Padding', [15 15 15 15], 'RowSpacing', 10);

% Row 1: Title
titleLbl = uilabel(gl, 'Text', 'Gemini ER Scenario Runner', ...
    'FontSize', 16, 'FontWeight', 'bold');
titleLbl.Layout.Row = 1; titleLbl.Layout.Column = [1 3];

% Row 2: Mode radio buttons
bg = uibuttongroup(gl, 'BorderType', 'none');
bg.Layout.Row = 2; bg.Layout.Column = [1 3];
presetRadio = uiradiobutton(bg, 'Text', 'Preset', 'Position', [0 2 80 22], 'Value', true);
uiradiobutton(bg, 'Text', 'Custom', 'Position', [90 2 80 22]);

% Row 3: Scenario dropdown + Randomize
lbl = uilabel(gl, 'Text', 'Preset scenario:');
lbl.Layout.Row = 3; lbl.Layout.Column = 1;

dd = uidropdown(gl, 'Items', scenarioNames, 'Value', scenarioNames{1});
dd.Layout.Row = 3; dd.Layout.Column = 2;

randBtn = uibutton(gl, 'Text', 'Randomize Positions');
randBtn.Layout.Row = 3; randBtn.Layout.Column = 3;

% Row 4: Task prompt text area
ta = uitextarea(gl, 'Value', char(scenarios.(scenarioNames{1})), ...
    'FontSize', 14, 'Editable', 'off');
ta.Layout.Row = 4; ta.Layout.Column = [1 3];

% Row 5: Status label
statusLbl = uilabel(gl, 'Text', '', 'FontColor', [0.4 0.4 0.4], ...
    'FontAngle', 'italic');
statusLbl.Layout.Row = 5; statusLbl.Layout.Column = [1 3];

% Row 6: Simulate / Stop buttons
simBtn = uibutton(gl, 'Text', 'Simulate', ...
    'BackgroundColor', [0.2 0.6 0.2], 'FontColor', 'w', 'FontWeight', 'bold');
simBtn.Layout.Row = 6; simBtn.Layout.Column = [1 2];

stopBtn = uibutton(gl, 'Text', 'Stop', ...
    'BackgroundColor', [0.7 0.2 0.2], 'FontColor', 'w', 'FontWeight', 'bold', ...
    'Enable', 'off');
stopBtn.Layout.Row = 6; stopBtn.Layout.Column = 3;

% Store handles for callbacks
handles = struct('dd', dd, 'ta', ta, 'simBtn', simBtn, 'stopBtn', stopBtn, ...
    'statusLbl', statusLbl, 'lbl', lbl, 'presetRadio', presetRadio);
fig.UserData = handles;

% Callbacks
bg.SelectionChangedFcn = @(~, evt) onModeChanged(evt, fig, scenarios, scenarioNames);
dd.ValueChangedFcn = @(~,~) onScenarioChanged(fig, scenarios);
randBtn.ButtonPushedFcn = @(~,~) onRandomize(statusLbl);
simBtn.ButtonPushedFcn = @(~,~) startSim(fig);
stopBtn.ButtonPushedFcn = @(~,~) stopSim(fig);
end

function onModeChanged(evt, fig, scenarios, scenarioNames)
    h = fig.UserData;
    forceStop(fig);

    if strcmp(evt.NewValue.Text, 'Preset')
        % Show dropdown, make text area read-only, load preset
        h.lbl.Visible = 'on';
        h.dd.Visible = 'on';
        h.ta.Editable = 'off';
        h.ta.Value = char(scenarios.(h.dd.Value));
    else
        % Hide dropdown, make text area editable, pre-fill example
        h.lbl.Visible = 'off';
        h.dd.Visible = 'off';
        h.ta.Editable = 'on';
        if isempty(strtrim(strjoin(string(h.ta.Value), ' '))) || ...
                any(strcmp(h.dd.Value, scenarioNames))
            h.ta.Value = 'Pick the red elbow fitting and place it on the left table.';
        end
    end
end

function onScenarioChanged(fig, scenarios)
    h = fig.UserData;
    forceStop(fig);
    h.ta.Value = char(scenarios.(h.dd.Value));
end

function onRandomize(statusLbl)
    seed = randi(9999);
    assignin('base', 'randSeed', seed);
    evalin('base', 'rng(randSeed); robotSimParams;');
    statusLbl.Text = sprintf('Object positions randomized (seed=%d)', seed);
end

function startSim(fig)
    h = fig.UserData;
    modelName = 'IntelligentBinPickingGemini';

    % Set task prompt in base workspace
    prompt = strjoin(string(h.ta.Value), ' ');
    assignin('base', 'taskPrompt', prompt);

    % Update UI
    h.simBtn.Enable = 'off';
    h.stopBtn.Enable = 'on';
    h.statusLbl.Text = 'Simulating...';
    drawnow

    % Start simulation
    try
        set_param(modelName, 'SimulationCommand', 'start');
    catch ex
        h.simBtn.Enable = 'on';
        h.stopBtn.Enable = 'off';
        h.statusLbl.Text = '';
        uialert(fig, ex.message, 'Simulation Error');
        return
    end

    % Poll for simulation end using a timer
    t = timer('ExecutionMode', 'fixedSpacing', 'Period', 1, ...
        'TimerFcn', @(src,~) checkSimStatus(src, fig));
    start(t);
end

function checkSimStatus(tmr, fig)
    modelName = 'IntelligentBinPickingGemini';
    try
        status = get_param(modelName, 'SimulationStatus');
    catch
        status = 'stopped';
    end
    if strcmp(status, 'stopped') || strcmp(status, 'terminating')
        stop(tmr);
        delete(tmr);
        h = fig.UserData;
        h.simBtn.Enable = 'on';
        h.stopBtn.Enable = 'off';
        if strcmp(h.statusLbl.Text, 'Simulating...')
            h.statusLbl.Text = 'Done.';
        end
    end
end

function stopSim(fig)
    forceStop(fig);
    h = fig.UserData;
    h.statusLbl.Text = 'Stopped.';
end

function forceStop(fig)
    h = fig.UserData;
    modelName = 'IntelligentBinPickingGemini';
    try
        status = get_param(modelName, 'SimulationStatus');
        if ~strcmp(status, 'stopped')
            set_param(modelName, 'SimulationCommand', 'stop');
        end
    catch
    end
    h.simBtn.Enable = 'on';
    h.stopBtn.Enable = 'off';
end
