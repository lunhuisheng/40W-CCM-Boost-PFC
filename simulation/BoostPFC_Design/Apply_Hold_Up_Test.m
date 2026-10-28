% Create an independent AC-dropout test model from the frozen final baseline.

clear;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
sourceFile=fullfile(designDir,'BoostPFC_Design_LoadConnection.slx');
modelName='BoostPFC_Design_HoldUpTest';
modelFile=fullfile(designDir,[modelName '.slx']);
assert(isfile(sourceFile),'Missing frozen source model: %s',sourceFile);
assert(~isfile(modelFile),'Refusing to overwrite existing test model: %s',modelFile);
copyfile(sourceFile,modelFile);
load_system(modelFile);

set_param(modelName,'InitFcn',[ ...
    'modelFile=get_param(bdroot,''FileName''); ', ...
    'run(fullfile(fileparts(modelFile),''BoostPFC_Design_HoldUp_Init.m'')); ', ...
    'clear modelFile']);

sourcePath=[modelName '/AC_Source_20_to_28_Vrms'];
sourcePorts=get_param(sourcePath,'PortHandles');
oldLine=get_param(sourcePorts.Outport(1),'Line');
assert(oldLine~=-1,'AC source output line was not found.');
destinationPorts=get_param(oldLine,'DstPortHandle');
delete_line(oldLine);

gatePath=[modelName '/AC_Dropout_Gate'];
enablePath=[modelName '/AC_Input_Enable'];
add_block('simulink/Math Operations/Product',gatePath, ...
    'Inputs','**','Position',[145 95 180 145]);
add_block('simulink/Sources/Step',enablePath, ...
    'Time','hold_up_command_time_s','Before','1','After','0', ...
    'SampleTime','Ts_sim','Position',[60 165 135 195]);

gatePorts=get_param(gatePath,'PortHandles');
enablePorts=get_param(enablePath,'PortHandles');
add_line(modelName,sourcePorts.Outport(1),gatePorts.Inport(1),'autorouting','on');
enableLine=add_line(modelName,enablePorts.Outport(1),gatePorts.Inport(2),'autorouting','on');
set_param(enableLine,'Name','input_enable');
for index=1:numel(destinationPorts)
    newLine=add_line(modelName,gatePorts.Outport(1),destinationPorts(index),'autorouting','on');
    if index==1, set_param(newLine,'Name','vac'); end
end

% Move source-voltage logging to the gated signal and log the gate command.
set_param(sourcePorts.Outport(1),'DataLogging','off');
set_param(gatePorts.Outport(1),'DataLogging','on','DataLoggingNameMode','SignalName');
set_param(enablePorts.Outport(1),'DataLogging','on','DataLoggingNameMode','SignalName');

save_system(modelName,modelFile);
close_system(modelName,0);
fprintf('Created independent hold-up test model: %s\n',modelFile);
