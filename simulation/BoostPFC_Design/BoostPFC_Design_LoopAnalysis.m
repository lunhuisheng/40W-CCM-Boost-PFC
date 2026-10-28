% BoostPFC_Design_LoopAnalysis
% Analytical continuous-time loop estimates at the 24 Vac operating point.

clear;
close all;
designDir=fileparts(mfilename('fullpath'));
resultDir=fullfile(designDir,'results');
if ~isfolder(resultDir), mkdir(resultDir); end
run(fullfile(designDir,'BoostPFC_Design_Init.m'));

s=tf('s');
currentPlant=Vout_ref/(L_boost*s);
currentController=Kp_i+Ki_i/s;
currentOpenLoop=currentController*currentPlant;
[gmI,pmI,wcgI,wcpI]=margin(currentOpenLoop);

voltagePlant=gvi_coefficient/s;
voltageController=Kp_v+Ki_v/s;
voltageOpenLoop=voltageController*voltagePlant;
[gmV,pmV,wcgV,wcpV]=margin(voltageOpenLoop);

loopMetrics=struct;
loopMetrics.analysis_basis='Continuous averaged small-signal estimates; switching delay and nonlinear limits excluded';
loopMetrics.current_loop_gain_margin_dB=20*log10(gmI);
loopMetrics.current_loop_phase_margin_deg=pmI;
loopMetrics.current_loop_gain_crossover_Hz=wcpI/(2*pi);
loopMetrics.current_loop_phase_crossover_Hz=wcgI/(2*pi);
loopMetrics.voltage_loop_gain_margin_dB=20*log10(gmV);
loopMetrics.voltage_loop_phase_margin_deg=pmV;
loopMetrics.voltage_loop_gain_crossover_Hz=wcpV/(2*pi);
loopMetrics.voltage_loop_phase_crossover_Hz=wcgV/(2*pi);
loopMetrics.gain_margin_interpretation= ...
    'No useful finite -180 degree phase crossover in this idealized PI-plus-integrator model; numerical Inf is exported as JSON null.';

fig=figure('Color','w','Position',[100 100 1200 850]);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
nexttile; margin(currentOpenLoop); grid on; title('Current-loop open-loop estimate');
nexttile; margin(voltageOpenLoop); grid on; title('Voltage-loop open-loop estimate');
exportgraphics(fig,fullfile(resultDir,'loop_bode_margins.png'),'Resolution',160);
close(fig);

save(fullfile(resultDir,'loop_analysis.mat'),'loopMetrics','currentOpenLoop','voltageOpenLoop');
fileId=fopen(fullfile(resultDir,'loop_metrics.json'),'w');
cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,jsonencode(loopMetrics,PrettyPrint=true),'char');
disp(loopMetrics);

