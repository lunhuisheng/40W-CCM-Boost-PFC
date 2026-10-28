% Compare the same controller/plant equations with conduction losses set to zero.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
resultDir=fullfile(designDir,'results');
modelName='BoostPFC_Design';
run(fullfile(designDir,'BoostPFC_Design_Init.m'));
load_system(fullfile(designDir,[modelName '.slx']));
savedInitFcn=get_param(modelName,'InitFcn');
set_param(modelName,'InitFcn','');

% Idealized conduction assumptions; topology, control gains, L/C, load and
% precharge timing are unchanged.
Vf_bridge_effective=0;
Vf_boost_effective=0;
Rds_on_effective=0;
rL_effective=0;
sim_stop_time=1.0;
set_param(modelName,'StopTime','sim_stop_time');
output=sim(modelName);
logs=output.logsout;
t=getTime(logs,'vout');
vac=getData(logs,'vac'); iac=getData(logs,'iac');
vout=getData(logs,'vout'); rload=getData(logs,'Rload');
steady=t>=t(end)-0.20;
short=t>=t(end)-0.10;
idealMetrics=struct;
idealMetrics.assumption='Ideal bridge/boost diodes, zero MOSFET Rds(on), zero inductor ESR';
idealMetrics.Vout_mean_V=mean(vout(short));
idealMetrics.Vout_ripple_pp_V=max(vout(short))-min(vout(short));
idealMetrics.Pin_W=mean(vac(steady).*iac(steady));
idealMetrics.Pout_W=mean(vout(steady).^2./rload(steady));
idealMetrics.efficiency_percent=100*idealMetrics.Pout_W/idealMetrics.Pin_W;
idealMetrics.PF=idealMetrics.Pin_W/(rms(vac(steady))*rms(iac(steady)));
save(fullfile(resultDir,'ideal_component_comparison.mat'),'idealMetrics');
fileId=fopen(fullfile(resultDir,'ideal_component_metrics.json'),'w');
cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,jsonencode(idealMetrics,PrettyPrint=true),'char');
disp(idealMetrics);
set_param(modelName,'InitFcn',savedInitFcn);
close_system(modelName,0);

function data=getData(logs,name)
element=logs.getElement(name); data=element.Values.Data(:);
end
function time=getTime(logs,name)
element=logs.getElement(name); time=element.Values.Time(:);
end

