% Verify that the new work model runs without path or workspace residue.

clear;
bdclose('all');
restoredefaultpath;
originalFolder=pwd;
cleanup=onCleanup(@()cd(originalFolder));
cd(tempdir);
designDir=fileparts(mfilename('fullpath'));
modelFile=fullfile(designDir,'BoostPFC_Design_LoadConnection.slx');
load_system(modelFile);
simulationInput=Simulink.SimulationInput('BoostPFC_Design_LoadConnection');
simulationInput=simulationInput.setVariable('startup_ramp_time_s',100e-3);
simulationInput=simulationInput.setVariable('load_connection_strategy',0);
simulationInput=simulationInput.setModelParameter('StopTime','1.20');
simulationOutput=sim(simulationInput);
logs=simulationOutput.logsout;
state=logs.getElement('controlled_startup_state').Values.Data(:);
fault=logs.getElement('overcurrent_fault').Values.Data(:);
vout=logs.getElement('vout').Values.Data(:);
time=logs.getElement('vout').Values.Time(:);
tail=time>=time(end)-0.10;
tailMean=mean(vout(tail));
verification=struct('passed',state(end)==4 && ~any(fault>0.5) ...
        && abs(tailMean-40)<=0.8, ...
    'final_state',state(end),'fault_seen',any(fault>0.5), ...
    'final_output_voltage_V',vout(end), ...
    'last_100ms_mean_output_voltage_V',tailMean,'run_from_folder',pwd);
resultDir=fullfile(designDir,'results','load_connection_study');
fileId=fopen(fullfile(resultDir,'clean_session_verification.json'),'w');
fileCleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,jsonencode(verification,PrettyPrint=true),'char');
assert(verification.passed,'Clean-session verification failed.');
fprintf(['Clean-session load-model verification passed: state %.0f, ', ...
    'last-100-ms mean Vout %.4f V.\n'], ...
    verification.final_state,verification.last_100ms_mean_output_voltage_V);
close_system('BoostPFC_Design_LoadConnection',0);
