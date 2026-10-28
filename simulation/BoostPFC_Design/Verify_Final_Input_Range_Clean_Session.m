% Clean-session rerun of the 20 Vac and 28 Vac boundary cases.

clear;
bdclose('all');
restoredefaultpath;
originalFolder=pwd;
folderCleanup=onCleanup(@()cd(originalFolder));
cd(tempdir);
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_LoadConnection';
modelFile=fullfile(designDir,[modelName '.slx']);
load_system(modelFile);
run(fullfile(designDir,'BoostPFC_Design_LoadConnection_Init.m'));
resultDir=fullfile(designDir,'results','final_input_range');
boundaryCases=[20 28];
records=cell(numel(boundaryCases),1);

for caseIndex=1:numel(boundaryCases)
    VacCase=boundaryCases(caseIndex);
    rectifiedPeak=sqrt(2)*VacCase-2*Vf_bridge_effective;
    passiveCeiling=rectifiedPeak-Vf_boost_effective;
    simulationInput=Simulink.SimulationInput(modelName);
    simulationInput=simulationInput.setVariable('Vac_rms',VacCase);
    simulationInput=simulationInput.setVariable('safe_rectified_peak_V',rectifiedPeak);
    simulationInput=simulationInput.setVariable('safe_passive_ceiling_V',passiveCeiling);
    simulationInput=simulationInput.setVariable('safe_output_threshold_V', ...
        safe_output_fraction*passiveCeiling);
    simulationInput=simulationInput.setVariable('safe_rectified_threshold_V', ...
        safe_rectified_fraction*rectifiedPeak);
    simulationInput=simulationInput.setVariable('startup_ramp_time_s',100e-3);
    simulationInput=simulationInput.setVariable('load_connection_strategy',0);
    simulationInput=simulationInput.setModelParameter('StopTime','1.40');
    simulationOutput=sim(simulationInput);
    logs=simulationOutput.logsout;
    state=logs.getElement('controlled_startup_state').Values.Data(:);
    fault=logs.getElement('overcurrent_fault').Values.Data(:);
    voutElement=logs.getElement('vout').Values;
    time=voutElement.Time(:); vout=voutElement.Data(:);
    tail=time>=time(end)-0.10;
    record=struct('input_rms_V',VacCase,'final_state',state(end), ...
        'fault_seen',any(fault>0.5),'last_100ms_mean_output_voltage_V',mean(vout(tail)), ...
        'passed',state(end)==4 && ~any(fault>0.5) && abs(mean(vout(tail))-40)<=0.8, ...
        'run_from_folder',pwd);
    assert(record.passed,'Clean-session boundary verification failed at %g Vac.',VacCase);
    records{caseIndex}=record;
    fprintf('CLEAN_BOUNDARY %d Vac: state %.0f, mean Vout %.4f V, no fault.\n', ...
        VacCase,record.final_state,record.last_100ms_mean_output_voltage_V);
end

verification=struct('passed',all(cellfun(@(x)x.passed,records)), ...
    'cases',[records{:}]);
fileId=fopen(fullfile(resultDir,'clean_session_boundary_verification.json'),'w');
fileCleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,jsonencode(verification,PrettyPrint=true),'char');
close_system(modelName,0);
