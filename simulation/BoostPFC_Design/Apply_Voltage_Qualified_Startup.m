% Create an independent voltage-qualified startup model from the preserved
% delayed-load baseline.  Only startup command/state logic is changed.

clear;
bdclose('all');
designDir = fileparts(mfilename('fullpath'));
sourceModel = fullfile(designDir,'BoostPFC_Design.slx');
modelName = 'BoostPFC_Design_VoltageQualified';
modelFile = fullfile(designDir,[modelName '.slx']);
if ~isfile(modelFile)
    copyfile(sourceModel,modelFile);
end
run(fullfile(designDir,'BoostPFC_Design_VoltageQualified_Init.m'));
load_system(modelFile);

set_param(modelName,'InitFcn',[ ...
    'modelFile = get_param(bdroot, ''FileName''); ', ...
    'run(fullfile(fileparts(modelFile), ', ...
    '''BoostPFC_Design_VoltageQualified_Init.m'')); clear modelFile']);

sequencerPath = [modelName '/Startup_Sequencer'];
if getSimulinkBlockHandle(sequencerPath) < 0
    add_block('simulink/User-Defined Functions/MATLAB Function', ...
        sequencerPath,'Position',[650 155 805 225]);
end
setChartScript(sequencerPath,sequencerCode());
addMissingParameters(sequencerPath,{ ...
    'Ts_sim','precharge_voltage_threshold','precharge_qualification_time', ...
    'precharge_timeout_time'});
ensureScalarData(sequencerPath,{ ...
    't','vout','startupEnable','startupState', ...
    'Ts_sim','precharge_voltage_threshold','precharge_qualification_time', ...
    'precharge_timeout_time'});

loadPath = [modelName '/Load_Profile'];
setChartScript(loadPath,loadProfileCode());
setDataScope(loadPath,'startupEnable','Input');
addMissingParameters(loadPath,{ ...
    'load_step_mode','Rload_nominal','load_step_time','Rload_precharge'});
removeChartData(loadPath,'load_enable_time');
ensureScalarData(loadPath,{ ...
    't','startupEnable','Rload','load_step_mode','Rload_nominal', ...
    'load_step_time','Rload_precharge'});

controllerPath = [modelName '/Average_Current_Mode_Control'];
setChartScript(controllerPath,controllerCode());
setDataScope(controllerPath,'startupEnable','Input');
addMissingParameters(controllerPath,{ ...
    'Ts_sim','f_sw','Vout_ref','Vac_rms','Kp_v','Ki_v','Kp_i','Ki_i', ...
    'Ipk_limit','duty_min','duty_max','softstart_time'});
removeChartData(controllerPath,'precharge_release_time');
ensureScalarData(controllerPath,{ ...
    't','vout','vrect','iL','startupEnable','iRef','duty','pwm', ...
    'vLoop','vRefSoft'});

% Remove the fixed-time Step command from the copied model.
stepPath = [modelName '/Precharge_Bypass_Command'];
if getSimulinkBlockHandle(stepPath) >= 0
    stepPorts = get_param(stepPath,'PortHandles');
    stepLine = get_param(stepPorts.Outport(1),'Line');
    if stepLine ~= -1, delete_line(stepLine); end
    delete_block(stepPath);
end

% MATLAB Function port interfaces refresh after the edited chart is saved
% and reloaded.  Do this before wiring the new inputs.
save_system(modelName,modelFile);
close_system(modelName,0);
load_system(modelFile);

% Connect measured time/output voltage to the sequencer.
connectIfMissing(modelName,'Time/1','Startup_Sequencer/1');
connectIfMissing(modelName,'Vo_ADC_Delay/1','Startup_Sequencer/2');

% One latched command now synchronizes resistor bypass, load connection and
% controller/PWM release.
connectIfMissing(modelName,'Startup_Sequencer/1','Precharge_Bypass_Switch/2');
connectIfMissing(modelName,'Startup_Sequencer/1','Load_Profile/2');
connectIfMissing(modelName,'Startup_Sequencer/1','Average_Current_Mode_Control/5');

% Preserve both sequencer outputs in signal logging.  State encoding:
% 0=precharging, 1=qualified/enabled, -1=timeout-safe-state.
addIfMissing('simulink/Sinks/Terminator',[modelName '/Startup_State_Terminator'], ...
    {'Position',[880 230 900 250]});
connectIfMissing(modelName,'Startup_Sequencer/2','Startup_State_Terminator/1');
markLoggedSignal([modelName '/Startup_Sequencer'],1,'startup_enable');
markLoggedSignal([modelName '/Startup_Sequencer'],2,'startup_state');

notes = find_system(modelName,'FindAll','on','Type','annotation');
if ~isempty(notes)
    annotationText = get_param(notes(1),'Name');
    annotationText = regexprep(annotationText,'\nLoad sequencing:.*$','');
    set_param(notes(1),'Name',[annotationText sprintf([ ...
        '\nStartup sequencing: voltage-qualified precharge; one command ', ...
        'synchronizes bypass, load and PWM.'])]);
end

save_system(modelName,modelFile);
close_system(modelName,0);
fprintf('Created voltage-qualified model: %s\n',modelFile);

function code = sequencerCode()
code = sprintf([ ...
    'function [startupEnable,startupState] = fcn(t,vout)\n', ...
    '%% 0=precharge, 1=qualified/enabled, -1=timeout safe state.\n', ...
    'persistent qualifyDuration latched timedOut\n', ...
    'if isempty(qualifyDuration), qualifyDuration=0; latched=false; timedOut=false; end\n', ...
    'if ~latched && ~timedOut\n', ...
    '    if vout >= precharge_voltage_threshold\n', ...
    '        qualifyDuration=qualifyDuration+Ts_sim;\n', ...
    '    else\n', ...
    '        qualifyDuration=0;\n', ...
    '    end\n', ...
    '    if qualifyDuration >= precharge_qualification_time\n', ...
    '        latched=true;\n', ...
    '    elseif t >= precharge_timeout_time\n', ...
    '        timedOut=true;\n', ...
    '    end\n', ...
    'end\n', ...
    'startupEnable=double(latched);\n', ...
    'if timedOut, startupState=-1; elseif latched, startupState=1; else, startupState=0; end\n']);
end

function code = loadProfileCode()
code = sprintf([ ...
    'function Rload = fcn(t,startupEnable)\n', ...
    '%% Load remains open until the startup sequencer qualifies precharge.\n', ...
    'if startupEnable < 0.5\n', ...
    '    Rload = Rload_precharge;\n', ...
    'elseif load_step_mode == 1\n', ...
    '    if t < load_step_time, Rload = 2*Rload_nominal; else, Rload = Rload_nominal; end\n', ...
    'elseif load_step_mode == 2\n', ...
    '    if t < load_step_time, Rload = Rload_nominal; else, Rload = 2*Rload_nominal; end\n', ...
    'else\n', ...
    '    Rload = Rload_nominal;\n', ...
    'end\n']);
end

function code = controllerCode()
code = sprintf([ ...
    'function [iRef,duty,pwm,vLoop,vRefSoft] = fcn(t,vout,vrect,iL,startupEnable)\n', ...
    '%% Existing average-current-mode control released by startup sequencer.\n', ...
    'persistent intV intI carrier enableTime\n', ...
    'if isempty(intV), intV=0; intI=0; carrier=0; enableTime=-1; end\n', ...
    'if startupEnable < 0.5\n', ...
    '    intV=0; intI=0; carrier=0; enableTime=-1;\n', ...
    '    iRef=0; duty=0; pwm=0; vLoop=0; vRefSoft=0; return;\n', ...
    'end\n', ...
    'if enableTime < 0, enableTime=t; end\n', ...
    'controlTime=max(t-enableTime,0);\n', ...
    'vRefSoft=Vout_ref*min(controlTime/softstart_time,1);\n', ...
    'eV=vRefSoft-vout; vUnsat=Kp_v*eV+intV;\n', ...
    'vLoop=min(max(vUnsat,0),Ipk_limit);\n', ...
    'if (vUnsat==vLoop)||(vUnsat>Ipk_limit&&eV<0)||(vUnsat<0&&eV>0), intV=intV+Ki_v*Ts_sim*eV; end\n', ...
    'vPeak=max(sqrt(2)*Vac_rms,1); iRef=min(Ipk_limit,max(0,vLoop*vrect/vPeak));\n', ...
    'eI=iRef-iL; dFeedforward=1-vrect/max(Vout_ref,1); dUnsat=dFeedforward+Kp_i*eI+intI;\n', ...
    'duty=min(max(dUnsat,duty_min),duty_max);\n', ...
    'if (dUnsat==duty)||(dUnsat>duty_max&&eI<0)||(dUnsat<duty_min&&eI>0), intI=intI+Ki_i*Ts_sim*eI; end\n', ...
    'carrier=carrier+f_sw*Ts_sim; if carrier>=1, carrier=carrier-floor(carrier); end\n', ...
    'pwm=double(duty>carrier);\n']);
end

function setChartScript(blockPath,codeText)
chart = find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
assert(~isempty(chart),'Missing MATLAB Function block: %s',blockPath);
chart.Script = codeText;
end

function addMissingParameters(blockPath,names)
chart = find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
existing = find(chart,'-isa','Stateflow.Data');
existingNames = arrayfun(@(item) string(item.Name),existing);
for index=1:numel(names)
    if ~any(existingNames==names{index})
        dataObject=Stateflow.Data(chart);
        dataObject.Name=names{index};
        dataObject.Scope='Parameter';
        dataObject.Props.Array.Size='1';
    end
end
end

function removeChartData(blockPath,name)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
dataItems=find(chart,'-isa','Stateflow.Data','Name',name);
for index=1:numel(dataItems), delete(dataItems(index)); end
end

function setDataScope(blockPath,name,scope)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
dataItems=find(chart,'-isa','Stateflow.Data','Name',name);
if isempty(dataItems)
    dataObject=Stateflow.Data(chart);
    dataObject.Name=name;
    dataObject.Props.Array.Size='1';
else
    dataObject=dataItems(1);
end
dataObject.Scope=scope;
end

function ensureScalarData(blockPath,names)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
for index=1:numel(names)
    dataItems=find(chart,'-isa','Stateflow.Data','Name',names{index});
    if ~isempty(dataItems)
        dataItems(1).Props.Array.Size='1';
        dataItems(1).DataType='Inherit: Same as Simulink';
    end
end
end

function addIfMissing(libraryPath,blockPath,arguments)
if getSimulinkBlockHandle(blockPath)<0
    add_block(libraryPath,blockPath,arguments{:});
end
end

function connectIfMissing(modelName,sourcePort,destinationPort)
destinationBlock=extractBefore(destinationPort,'/');
destinationNumber=str2double(extractAfter(destinationPort,'/'));
ports=get_param([modelName '/' destinationBlock],'PortHandles');
if numel(ports.Inport)<destinationNumber
    error('Destination port is unavailable: %s',destinationPort);
end
existingLine=get_param(ports.Inport(destinationNumber),'Line');
if existingLine==-1
    add_line(modelName,sourcePort,destinationPort,'autorouting','on');
end
end

function markLoggedSignal(blockPath,portNumber,signalName)
ports=get_param(blockPath,'PortHandles');
lineHandle=get_param(ports.Outport(portNumber),'Line');
assert(lineHandle~=-1,'Output is not connected: %s/%d',blockPath,portNumber);
set_param(lineHandle,'Name',signalName);
set_param(ports.Outport(portNumber),'DataLogging','on', ...
    'DataLoggingNameMode','SignalName');
end
