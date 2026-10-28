% Create a work model that tests safe bypass only. PWM and load remain off.

clear;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
sourceFile=fullfile(designDir,'BoostPFC_Design_VoltageQualified.slx');
modelName='BoostPFC_Design_SafeBypass';
modelFile=fullfile(designDir,[modelName '.slx']);
if ~isfile(modelFile), copyfile(sourceFile,modelFile); end
run(fullfile(designDir,'BoostPFC_Design_SafeBypass_Init.m'));
load_system(modelFile);
set_param(modelName,'InitFcn',[ ...
    'modelFile=get_param(bdroot,''FileName''); ', ...
    'run(fullfile(fileparts(modelFile),''BoostPFC_Design_SafeBypass_Init.m'')); ', ...
    'clear modelFile']);

sequencerPath=[modelName '/Startup_Sequencer'];
setChartScript(sequencerPath,sequencerCode());
setDataScope(sequencerPath,'vrect','Input');
setDataScope(sequencerPath,'iL','Input');
removeParameters(sequencerPath,{ ...
    'precharge_voltage_threshold','precharge_qualification_time', ...
    'precharge_timeout_time'});
addParameters(sequencerPath,{ ...
    'Ts_sim','safe_output_threshold_V','safe_rectified_threshold_V', ...
    'safe_voltage_difference_max_V','safe_bypass_current_max_A', ...
    'safe_condition_hold_time_s','safe_bypass_timeout_s'});

% Save/reload to refresh the expanded four-input interface.
save_system(modelName,modelFile);
close_system(modelName,0);
load_system(modelFile);

connectIfMissing(modelName,'Rectified_Voltage_Clamp/1','Startup_Sequencer/3');
connectIfMissing(modelName,'iL_ADC_Delay/1','Startup_Sequencer/4');

% This experiment isolates the bypass. Remove sequencer branches to PWM and
% load, then hold both commands low with a constant block.
removeBranch(modelName,'Startup_Sequencer/1','Load_Profile/2');
removeBranch(modelName,'Startup_Sequencer/1','Average_Current_Mode_Control/5');
zeroPath=[modelName '/Safe_Test_Enable_Zero'];
if getSimulinkBlockHandle(zeroPath)<0
    add_block('simulink/Sources/Constant',zeroPath, ...
        'Value','0','Position',[835 285 875 315]);
end
connectIfMissing(modelName,'Safe_Test_Enable_Zero/1','Load_Profile/2');
connectIfMissing(modelName,'Safe_Test_Enable_Zero/1','Average_Current_Mode_Control/5');
connectIfMissing(modelName,'Startup_Sequencer/1','Precharge_Bypass_Switch/2');

markLoggedSignal(sequencerPath,1,'safe_bypass_enable');
markLoggedSignal(sequencerPath,2,'safe_bypass_state');

save_system(modelName,modelFile);
close_system(modelName,0);
fprintf('Created isolated safe-bypass model: %s\n',modelFile);

function code=sequencerCode()
code=sprintf([ ...
'function [startupEnable,startupState] = fcn(t,vout,vrect,iL)\n', ...
'%% Safe-bypass-only test. 0=precharge, 1=bypassed, -1=timeout.\n', ...
'persistent validDuration latched timedOut\n', ...
'if isempty(validDuration), validDuration=0; latched=false; timedOut=false; end\n', ...
'voltageDifference=abs(vrect-vout);\n', ...
'conditions=(vout>=safe_output_threshold_V) && ...\n', ...
' (vrect>=safe_rectified_threshold_V) && ...\n', ...
' (voltageDifference<=safe_voltage_difference_max_V) && ...\n', ...
' (iL<=safe_bypass_current_max_A);\n', ...
'if ~latched && ~timedOut\n', ...
' if conditions, validDuration=validDuration+Ts_sim; else, validDuration=0; end\n', ...
' if validDuration>=safe_condition_hold_time_s\n', ...
'  latched=true;\n', ...
' elseif t>=safe_bypass_timeout_s\n', ...
'  timedOut=true;\n', ...
' end\n', ...
'end\n', ...
'startupEnable=double(latched);\n', ...
'if timedOut, startupState=-1; elseif latched, startupState=1; else, startupState=0; end\n']);
end

function setChartScript(blockPath,codeText)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
chart.Script=codeText;
end

function setDataScope(blockPath,name,scope)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
items=find(chart,'-isa','Stateflow.Data','Name',name);
if isempty(items), item=Stateflow.Data(chart); item.Name=name; else, item=items(1); end
item.Scope=scope; item.Props.Array.Size='1';
end

function removeParameters(blockPath,names)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
for index=1:numel(names)
    items=find(chart,'-isa','Stateflow.Data','Name',names{index});
    for itemIndex=1:numel(items), delete(items(itemIndex)); end
end
end

function addParameters(blockPath,names)
chart=find(sfroot,'-isa','Stateflow.EMChart','Path',blockPath);
for index=1:numel(names)
    items=find(chart,'-isa','Stateflow.Data','Name',names{index});
    if isempty(items), item=Stateflow.Data(chart); item.Name=names{index}; else, item=items(1); end
    item.Scope='Parameter'; item.Props.Array.Size='1';
end
end

function removeBranch(modelName,sourcePort,destinationPort)
try, delete_line(modelName,sourcePort,destinationPort); catch, end
end

function connectIfMissing(modelName,sourcePort,destinationPort)
block=extractBefore(destinationPort,'/');
number=str2double(extractAfter(destinationPort,'/'));
ports=get_param([modelName '/' block],'PortHandles');
if get_param(ports.Inport(number),'Line')==-1
    add_line(modelName,sourcePort,destinationPort,'autorouting','on');
end
end

function markLoggedSignal(blockPath,portNumber,signalName)
ports=get_param(blockPath,'PortHandles');
lineHandle=get_param(ports.Outport(portNumber),'Line');
set_param(lineHandle,'Name',signalName);
set_param(ports.Outport(portNumber),'DataLogging','on', ...
    'DataLoggingNameMode','SignalName');
end
