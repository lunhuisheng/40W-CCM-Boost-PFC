% Verify the voltage-qualified model from an unrelated clean MATLAB session.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_VoltageQualified';
modelFile=fullfile(designDir,[modelName '.slx']);
restoredefaultpath;
rehash toolboxcache;
cd(tempdir);
assert(isempty(which('BoostPFC_Design_VoltageQualified_Init')), ...
    'Design directory unexpectedly remains on the MATLAB path.');
load_system(modelFile);
simulationOutput=sim(modelName);
logs=simulationOutput.logsout;
enable=logs.getElement('startup_enable').Values;
state=logs.getElement('startup_state').Values;
statusFile=fullfile(designDir,'results','voltage_qualified', ...
    'clean_session_verification.txt');
fileId=fopen(statusFile,'w');
cleanup=onCleanup(@()fclose(fileId));
fprintf(fileId,'PASS\nModel loaded and simulated from: %s\n',pwd);
fprintf(fileId,'InitFcn: %s\n',get_param(modelName,'InitFcn'));
fprintf(fileId,'Startup enable max: %.0f\n',max(enable.Data));
fprintf(fileId,'Startup final state: %.0f\n',state.Data(end));
close_system(modelName,0);
