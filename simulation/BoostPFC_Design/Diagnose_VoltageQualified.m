% Compile/update check and startup-interface record for the work model.

clear;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_VoltageQualified';
modelFile=fullfile(designDir,[modelName '.slx']);
load_system(modelFile);

diagnostic=struct;
diagnostic.model_file=modelFile;
diagnostic.init_fcn=get_param(modelName,'InitFcn');
diagnostic.fixed_step=get_param(modelName,'FixedStep');
diagnostic.stop_time=get_param(modelName,'StopTime');
diagnostic.blocks=struct;
blockNames={'Startup_Sequencer','Precharge_Bypass_Switch', ...
    'Load_Profile','Average_Current_Mode_Control'};
for index=1:numel(blockNames)
    blockPath=[modelName '/' blockNames{index}];
    ports=get_param(blockPath,'PortHandles');
    diagnostic.blocks.(blockNames{index})=struct( ...
        'inputs',numel(ports.Inport),'outputs',numel(ports.Outport));
end
try
    set_param(modelName,'SimulationCommand','update');
    diagnostic.compile_identifier='NO_ERROR';
    diagnostic.compile_message='Model update succeeded.';
catch errorObject
    diagnostic.compile_identifier=errorObject.identifier;
    diagnostic.compile_message=errorObject.message;
end

fileId=fopen(fullfile(designDir,'voltage_qualified_diagnostic.json'),'w');
cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,jsonencode(diagnostic,PrettyPrint=true),'char');
close_system(modelName,0);
disp(diagnostic);
