% Run input-voltage sweep and bidirectional load-step cases.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
resultDir=fullfile(designDir,'results');
if ~isfolder(resultDir), mkdir(resultDir); end
modelName='BoostPFC_Design';
modelFile=fullfile(designDir,[modelName '.slx']);
initFile=fullfile(designDir,'BoostPFC_Design_Init.m');
run(initFile);
load_system(modelFile);

% Variables are set explicitly for each case in this clean MATLAB process.
% Disable the callback only in memory so it cannot reset case overrides.
savedInitFcn=get_param(modelName,'InitFcn');
set_param(modelName,'InitFcn','');

voltageCases=[20 24 28];
voltageCells=cell(1,numel(voltageCases));
for caseIndex=1:numel(voltageCases)
    run(initFile);
    Vac_rms=voltageCases(caseIndex);
    load_step_mode=0;
    sim_stop_time=1.0;
    set_param(modelName,'StopTime','sim_stop_time');
    fprintf('Running input case: %.1f Vac\n',Vac_rms);
    output=sim(modelName);
    voltageCells{caseIndex}=analyzeCase(output.logsout,Vac_rms,f_line,f_sw,Ts_sim,Vout_ref);
end
voltageResults=[voltageCells{:}];

% Load step: 50% -> 100% and 100% -> 50% at 0.70 s.
stepModes=[1 2];
stepNames={'50_to_100_percent','100_to_50_percent'};
loadCells=cell(1,2);
for caseIndex=1:2
    run(initFile);
    Vac_rms=24;
    load_step_mode=stepModes(caseIndex);
    load_step_time=0.70;
    sim_stop_time=1.20;
    set_param(modelName,'StopTime','sim_stop_time');
    fprintf('Running load step: %s\n',stepNames{caseIndex});
    output=sim(modelName);
    loadCells{caseIndex}=analyzeLoadStep(output.logsout,stepNames{caseIndex}, ...
        load_step_time,Vout_ref);
end
loadResults=[loadCells{:}];

set_param(modelName,'InitFcn',savedInitFcn);

save(fullfile(resultDir,'multi_case_results.mat'),'voltageResults','loadResults');
voltageMetrics=rmfield(voltageResults,{'time','vout','iac'});
loadMetrics=rmfield(loadResults,{'time','vout'});
writeJson(fullfile(resultDir,'input_voltage_case_metrics.json'),voltageMetrics);
writeJson(fullfile(resultDir,'load_step_metrics.json'),loadMetrics);

fig1=figure('Color','w','Position',[100 100 1200 900]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile; hold on;
for index=1:numel(voltageResults)
    plot(voltageResults(index).time,voltageResults(index).vout,'LineWidth',1.0);
end
yline(Vout_ref,'--'); grid on; ylabel('V_o (V)');
legend('20 Vac','24 Vac','28 Vac','40 V reference','Location','best');
title('Input-voltage comparison');
nexttile; hold on;
for index=1:numel(voltageResults)
    tail=voltageResults(index).time>=voltageResults(index).time(end)-0.04;
    plot(voltageResults(index).time(tail),voltageResults(index).iac(tail),'LineWidth',0.9);
end
grid on; ylabel('i_{ac} (A)'); xlabel('Time (s)');
legend('20 Vac','24 Vac','28 Vac','Location','best');
exportgraphics(fig1,fullfile(resultDir,'input_voltage_comparison.png'),'Resolution',160);
close(fig1);

fig2=figure('Color','w','Position',[100 100 1200 800]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
for index=1:2
    nexttile;
    plot(loadResults(index).time,loadResults(index).vout,'LineWidth',1.1); hold on;
    yline(Vout_ref,'--'); xline(load_step_time,':'); grid on;
    ylabel('V_o (V)'); title(strrep(stepNames{index},'_',' '));
end
xlabel('Time (s)');
exportgraphics(fig2,fullfile(resultDir,'load_step_responses.png'),'Resolution',160);
close(fig2);

disp(voltageResults);
disp(loadResults);
fprintf('BOOSTPFC_DESIGN_CASES_DONE\n');
close_system(modelName,0);

function result=analyzeCase(logs,VacCommand,fline,fsw,Ts,Vref)
vac=values(logs,'vac'); iac=values(logs,'iac'); vout=values(logs,'vout');
duty=values(logs,'duty'); iL=values(logs,'iL'); pwm=values(logs,'pwm');
t=timeVector(logs,'vout');
steady=t>=t(end)-0.20;
lastHalf=t>=t(end)-0.10;
result=struct;
result.Vac_command_V=VacCommand;
result.Vac_measured_rms_V=rms(vac(steady));
result.Vout_mean_V=mean(vout(lastHalf));
result.Vout_ripple_pp_V=max(vout(lastHalf))-min(vout(lastHalf));
result.Vout_error_percent=100*(result.Vout_mean_V-Vref)/Vref;
result.Pin_W=mean(vac(steady).*iac(steady));
result.Pout_W=mean(vout(steady).^2/40);
result.efficiency_percent=100*result.Pout_W/result.Pin_W;
result.Iac_rms_A=rms(iac(steady));
result.PF=result.Pin_W/(rms(vac(steady))*rms(iac(steady)));
tH=t(steady); iH=iac(steady); h=zeros(40,1);
for n=1:40
    h(n)=hypot(2*mean(iH.*cos(2*pi*n*fline*tH)), ...
        2*mean(iH.*sin(2*pi*n*fline*tH)))/sqrt(2);
end
result.THD_2_to_40_percent=100*sqrt(sum(h(2:end).^2))/h(1);
result.iL_max_steady_A=max(iL(steady));
result.iL_max_overall_A=max(iL);
result.duty_min_steady=min(duty(steady));
result.duty_max_steady=max(duty(steady));
vacPeak=max(abs(vac(steady)));
nearPeak=steady & abs(abs(vac)-vacPeak)<0.02*vacPeak;
result.duty_mean_near_line_peak=mean(duty(nearPeak));
tailPwm=pwm(steady); tailTime=t(steady);
edges=find(diff(tailPwm>0.5)==1)+1;
result.pwm_frequency_Hz=1/mean(diff(tailTime(edges)));
result.pass_voltage=abs(result.Vout_error_percent)<=2;
result.pass_ripple=result.Vout_ripple_pp_V<=2;
result.pass_pf=result.PF>=0.95;
result.pass_thd=result.THD_2_to_40_percent<=10;
stride=max(1,round(10e-6/Ts));
result.time=t(1:stride:end);
result.vout=vout(1:stride:end);
result.iac=iac(1:stride:end);
end

function result=analyzeLoadStep(logs,name,stepTime,Vref)
t=timeVector(logs,'vout'); vout=values(logs,'vout'); rload=values(logs,'Rload');
post=t>=stepTime;
result=struct;
result.name=name;
result.step_time_s=stepTime;
result.load_before_ohm=mean(rload(t>=stepTime-0.05 & t<stepTime));
result.load_after_ohm=mean(rload(t>=t(end)-0.05));
result.minimum_after_step_V=min(vout(post));
result.maximum_after_step_V=max(vout(post));
result.maximum_deviation_after_step_V=max(abs(vout(post)-Vref));
result.final_mean_V=mean(vout(t>=t(end)-0.10));
result.final_ripple_pp_V=max(vout(t>=t(end)-0.10))-min(vout(t>=t(end)-0.10));
stride=10;
result.time=t(1:stride:end);
result.vout=vout(1:stride:end);
end

function data=values(logs,name)
element=logs.getElement(name);
series=element.Values;
data=series.Data(:);
end

function time=timeVector(logs,name)
element=logs.getElement(name);
series=element.Values;
time=series.Time(:);
end

function writeJson(path,value)
fileId=fopen(path,'w'); cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,jsonencode(value,PrettyPrint=true),'char');
end
