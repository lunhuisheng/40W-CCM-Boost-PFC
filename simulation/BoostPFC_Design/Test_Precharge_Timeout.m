% Verify that an unreachable qualification threshold leaves the model safe.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_VoltageQualified';
modelFile=fullfile(designDir,[modelName '.slx']);
resultDir=fullfile(designDir,'results','voltage_qualified');
if ~isfolder(resultDir), mkdir(resultDir); end

load_system(modelFile);
run(fullfile(designDir,'BoostPFC_Design_VoltageQualified_Init.m'));
forcedThreshold=precharge_passive_ceiling_V+1.0;
simulationInput=Simulink.SimulationInput(modelName);
simulationInput=simulationInput.setVariable( ...
    'precharge_voltage_threshold',forcedThreshold);
simulationInput=simulationInput.setModelParameter('StopTime','0.55');
simulationOutput=sim(simulationInput);
logs=simulationOutput.logsout;

enableTs=signal(logs,'startup_enable');
stateTs=signal(logs,'startup_state');
pwmTs=signal(logs,'pwm');
rloadTs=signal(logs,'Rload');
voutTs=signal(logs,'vout');

timeout=struct;
timeout.forced_threshold_V=forcedThreshold;
timeout.passive_ceiling_V=precharge_passive_ceiling_V;
timeout.expected_timeout_s=precharge_timeout_time;
timeout.final_state=stateTs.Data(end);
timeout.enable_max=max(enableTs.Data);
timeout.pwm_max=max(pwmTs.Data);
timeout.minimum_load_resistance_ohm=min(rloadTs.Data);
timeout.output_voltage_max_V=max(voutTs.Data);
timeout.pass_timeout_state=timeout.final_state < -0.5;
timeout.pass_bypass_remained_open=timeout.enable_max < 0.5;
timeout.pass_pwm_remained_off=timeout.pwm_max < 0.5;
timeout.pass_load_remained_disconnected= ...
    timeout.minimum_load_resistance_ohm > 1e8;
timeout.pass_all=timeout.pass_timeout_state ...
    && timeout.pass_bypass_remained_open ...
    && timeout.pass_pwm_remained_off ...
    && timeout.pass_load_remained_disconnected;

writeText(fullfile(resultDir,'timeout_safety_test.json'), ...
    jsonencode(timeout,PrettyPrint=true));

fig=figure('Color','w','Position',[100 100 1150 800]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
nexttile; plot(voutTs.Time,voutTs.Data,'LineWidth',1); hold on;
yline(forcedThreshold,'--r','unreachable threshold'); grid on; ylabel('V_o (V)');
title('Precharge timeout safety test');
nexttile; stairs(enableTs.Time,enableTs.Data,'LineWidth',1); hold on;
stairs(stateTs.Time,stateTs.Data,'LineWidth',1); grid on;
ylabel('State'); legend('enable','state','Location','best');
nexttile; stairs(pwmTs.Time,pwmTs.Data,'LineWidth',1); grid on;
ylabel('PWM'); xlabel('Time (s)');
exportgraphics(fig,fullfile(resultDir,'timeout_safety_test.png'),'Resolution',170);
close(fig);

disp(timeout);
close_system(modelName,0);

function values=signal(logs,name)
element=logs.getElement(name);
assert(~isempty(element),'Missing logged signal: %s',name);
values=element.Values;
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w');
cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
