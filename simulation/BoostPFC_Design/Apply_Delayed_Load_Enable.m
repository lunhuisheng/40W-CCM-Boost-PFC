% Apply only the approved delayed-load startup change to the working model.
% The existing power stage, controller, precharge resistor and release time
% are left unchanged.

clear;
bdclose('all');
designDir = fileparts(mfilename('fullpath'));
modelName = 'BoostPFC_Design';
modelFile = fullfile(designDir, [modelName '.slx']);
run(fullfile(designDir, 'BoostPFC_Design_Init.m'));
load_system(modelFile);

loadProfilePath = [modelName '/Load_Profile'];
chart = find(sfroot, '-isa', 'Stateflow.EMChart', 'Path', loadProfilePath);
assert(~isempty(chart), 'Load_Profile MATLAB Function block was not found.');
chart.Script = loadProfileCode();

parameterNames = {'load_step_mode','Rload_nominal','load_step_time', ...
    'load_enable_time','Rload_precharge'};
existing = find(chart, '-isa', 'Stateflow.Data');
existingNames = arrayfun(@(item) string(item.Name), existing);
for index = 1:numel(parameterNames)
    if ~any(existingNames == parameterNames{index})
        dataObject = Stateflow.Data(chart);
        dataObject.Name = parameterNames{index};
        dataObject.Scope = 'Parameter';
        dataObject.Props.Array.Size = '1';
    end
end

notes = find_system(modelName, 'FindAll', 'on', 'Type', 'annotation');
if ~isempty(notes)
    annotationText = get_param(notes(1), 'Name');
    annotationText = regexprep(annotationText, '\nLoad sequencing:.*$', '');
    set_param(notes(1), 'Name', [annotationText, sprintf([ ...
        '\nLoad sequencing: open during precharge; 40 ohm load connects at precharge release.'])]);
end

save_system(modelName, modelFile);
close_system(modelName, 0);
fprintf('Applied delayed-load enable only to: %s\n', modelFile);

function code = loadProfileCode()
code = sprintf([ ...
    'function Rload = fcn(t)\n', ...
    '%% Load is open during precharge, then the selected profile is connected.\n', ...
    'if t < load_enable_time\n', ...
    '    Rload = Rload_precharge;\n', ...
    'elseif load_step_mode == 1\n', ...
    '    if t < load_step_time, Rload = 2*Rload_nominal; else, Rload = Rload_nominal; end\n', ...
    'elseif load_step_mode == 2\n', ...
    '    if t < load_step_time, Rload = Rload_nominal; else, Rload = 2*Rload_nominal; end\n', ...
    'else\n', ...
    '    Rload = Rload_nominal;\n', ...
    'end\n']);
end
