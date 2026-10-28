% Verify that the controlled-startup model initializes and runs without
% relying on the current folder, manual addpath calls, or base-workspace data.

clear;
close all;
bdclose('all');
restoredefaultpath;
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_ControlledStartup';
verificationModelFile=fullfile(designDir,[modelName '.slx']);
resultFile=fullfile(designDir,'results','controlled_startup', ...
    'clean_session_verification.txt');
originalFolder=pwd;
cleanupFolder=onCleanup(@()cd(originalFolder)); %#ok<NASGU>
cd(tempdir);

try
    load_system(verificationModelFile);
    input=Simulink.SimulationInput(modelName);
    input=input.setVariable('startup_ramp_time_s',100e-3);
    input=input.setModelParameter('StopTime','1.2');
    output=sim(input);
    logs=output.logsout;
    state=logs.getElement('controlled_startup_state').Values.Data(:);
    vout=logs.getElement('vout').Values.Data(:);
    fault=logs.getElement('overcurrent_fault').Values.Data(:);
    passed=state(end)==4 && ~any(fault>0.5) && all(isfinite(vout));
    message=sprintf([ ...
        'PASS=%d\nModel=%s\nLaunch_folder=%s\nFinal_state=%.0f\n' ...
        'Overcurrent_fault=%d\nFinal_output_voltage_V=%.6f\n'], ...
        passed,verificationModelFile,pwd,state(end),any(fault>0.5),vout(end));
    writeText(resultFile,message);
    assert(passed,'Controlled-startup clean-session verification failed.');
    fprintf('%s',message);
catch errorInfo
    message=sprintf('PASS=0\nModel=%s\nLaunch_folder=%s\nError=%s\n', ...
        verificationModelFile,pwd,errorInfo.getReport('basic','hyperlinks','off'));
    writeText(resultFile,message);
    rethrow(errorInfo);
end
close_system(modelName,0);

function writeText(fileName,textValue)
fileId=fopen(fileName,'w');
cleanup=onCleanup(@()fclose(fileId)); %#ok<NASGU>
fwrite(fileId,textValue,'char');
end
