% Run_BoostPFC_Design
% Clean-session nominal simulation, measurements and waveform export.

clear;
close all;
bdclose('all');

designDir = fileparts(mfilename('fullpath'));
modelName = 'BoostPFC_Design';
modelFile = fullfile(designDir, [modelName '.slx']);
resultDir = fullfile(designDir, 'results');
if ~isfolder(resultDir), mkdir(resultDir); end

fprintf('Clean-session path check before model load:\n');
fprintf('  BoostPFC_Design_Init: %s\n', pathResult(which('BoostPFC_Design_Init')));

load_system(modelFile);
fprintf('Model InitFcn: %s\n', get_param(modelName, 'InitFcn'));
simulationOutput = sim(modelName);
logs = simulationOutput.logsout;

vacTs = signal(logs, 'vac');
iacTs = signal(logs, 'iac');
vrectTs = signal(logs, 'vrect');
iLTs = signal(logs, 'iL');
iRefTs = signal(logs, 'iL_ref');
voutTs = signal(logs, 'vout');
dutyTs = signal(logs, 'duty');
pwmTs = signal(logs, 'pwm');
rloadTs = signal(logs, 'Rload');

t = voutTs.Time(:);
vac = vacTs.Data(:);
iac = iacTs.Data(:);
vrect = vrectTs.Data(:);
iL = iLTs.Data(:);
iRef = iRefTs.Data(:);
vout = voutTs.Data(:);
duty = dutyTs.Data(:);
pwm = pwmTs.Data(:);
rload = rloadTs.Data(:);

% Steady-state window contains ten 50 Hz line cycles.
steadyStart = t(end)-0.20;
steady = t >= steadyStart;
steadyShort = t >= (t(end)-0.10);

metrics = struct;
metrics.model = modelName;
metrics.component_assumption = 'Non-ideal switched behavioral model';
metrics.input_voltage_rms_command_V = Vac_rms;
metrics.output_voltage_mean_V = mean(vout(steadyShort));
metrics.output_voltage_min_V = min(vout(steadyShort));
metrics.output_voltage_max_V = max(vout(steadyShort));
metrics.output_voltage_ripple_pp_V = ...
    metrics.output_voltage_max_V-metrics.output_voltage_min_V;
metrics.output_voltage_error_percent = ...
    100*(metrics.output_voltage_mean_V-Vout_ref)/Vout_ref;
metrics.output_voltage_overall_max_V = max(vout);
metrics.startup_overshoot_percent = max(0, ...
    100*(metrics.output_voltage_overall_max_V-Vout_ref)/Vout_ref);

% Settling is evaluated on one-line-cycle averages so the intentional
% 100 Hz ripple does not create a false late settling time.
samplesPerLine=round(1/(f_line*Ts_sim));
completeCycles=floor(numel(vout)/samplesPerLine);
cycleMean=zeros(completeCycles,1);
cycleEnd=zeros(completeCycles,1);
for cycleIndex=1:completeCycles
    indices=(cycleIndex-1)*samplesPerLine+(1:samplesPerLine);
    cycleMean(cycleIndex)=mean(vout(indices));
    cycleEnd(cycleIndex)=t(indices(end));
end
cycleInBand=abs(cycleMean-Vout_ref)<=0.02*Vout_ref;
firstSettled=find(arrayfun(@(index)all(cycleInBand(index:end)), ...
    (1:completeCycles)'),1,'first');
if isempty(firstSettled)
    metrics.settling_time_2percent_s=NaN;
else
    metrics.settling_time_2percent_s=cycleEnd(firstSettled);
end

metrics.input_voltage_rms_measured_V = rms(vac(steady));
metrics.input_current_rms_A = rms(iac(steady));
metrics.input_power_W = mean(vac(steady).*iac(steady));
metrics.output_power_W = mean(vout(steady).^2./rload(steady));
metrics.efficiency_percent = ...
    100*metrics.output_power_W/metrics.input_power_W;
metrics.power_factor = metrics.input_power_W/( ...
    metrics.input_voltage_rms_measured_V*metrics.input_current_rms_A);

% Low-frequency current THD, harmonics 2...40 (up to 2 kHz).
tH = t(steady);
iH = iac(steady);
harmonicRms = zeros(40,1);
for harmonic = 1:40
    cosineComponent = 2*mean(iH.*cos(2*pi*harmonic*f_line*tH));
    sineComponent = 2*mean(iH.*sin(2*pi*harmonic*f_line*tH));
    harmonicRms(harmonic) = hypot(cosineComponent,sineComponent)/sqrt(2);
end
metrics.input_current_fundamental_rms_A = harmonicRms(1);
metrics.input_current_thd_percent = ...
    100*sqrt(sum(harmonicRms(2:end).^2))/harmonicRms(1);

metrics.inductor_current_overall_max_A = max(iL);
metrics.inductor_current_steady_max_A = max(iL(steady));
metrics.inductor_current_steady_min_A = min(iL(steady));

% Estimate switching ripple around the final positive line-voltage peak.
lastPeakTime = floor((t(end)-1/(4*f_line))*f_line)/f_line + 1/(4*f_line);
if lastPeakTime > t(end), lastPeakTime = lastPeakTime-1/f_line; end
peakWindow = t >= lastPeakTime-0.5e-3 & t <= lastPeakTime+0.5e-3;
samplesPerSwitch = round(1/(f_sw*Ts_sim));
iLTrend = movmean(iL, samplesPerSwitch);
iLRipple = iL-iLTrend;
metrics.inductor_switching_ripple_pp_A = ...
    max(iLRipple(peakWindow))-min(iLRipple(peakWindow));

metrics.duty_min_steady = min(duty(steady));
metrics.duty_max_steady = max(duty(steady));
pwmTail = pwm(steady);
tPwmTail = t(steady);
risingEdges = find(diff(pwmTail>0.5)==1)+1;
if numel(risingEdges)>2
    metrics.pwm_frequency_Hz = 1/mean(diff(tPwmTail(risingEdges)));
else
    metrics.pwm_frequency_Hz = NaN;
end
metrics.pwm_min = min(pwmTail);
metrics.pwm_max = max(pwmTail);

metrics.pass_voltage_regulation = abs(metrics.output_voltage_error_percent)<=2;
metrics.pass_output_ripple = metrics.output_voltage_ripple_pp_V<=2;
metrics.pass_pf = metrics.power_factor>=0.95;
metrics.pass_thd = metrics.input_current_thd_percent<=10;

resultMat = fullfile(resultDir, 'nominal_24Vac_results.mat');
save(resultMat, 'metrics', 'harmonicRms', 't', 'vac', 'iac', 'vrect', ...
    'iL', 'iRef', 'vout', 'duty', 'pwm', 'rload');

resultJson = fullfile(resultDir, 'nominal_24Vac_metrics.json');
writeText(resultJson, jsonencode(metrics, PrettyPrint=true));

% Startup and regulation figure.
fig1 = figure('Color','w','Position',[100 100 1200 900]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
nexttile; plot(t,vout,'LineWidth',1.1); hold on; yline(Vout_ref,'--'); grid on;
ylabel('V_o (V)'); title('40 W Boost PFC - startup and regulation');
nexttile; plot(t,iL,'LineWidth',0.6); hold on; plot(t,iRef,'LineWidth',0.9); grid on;
ylabel('Current (A)'); legend('i_L','i_L^*','Location','best');
nexttile; plot(t,duty,'LineWidth',0.8); grid on; ylabel('Duty'); xlabel('Time (s)');
exportgraphics(fig1,fullfile(resultDir,'nominal_24Vac_startup.png'),'Resolution',160);
close(fig1);

% Last two line cycles: input voltage/current and current tracking.
lineWindow = t >= t(end)-0.04;
fig2 = figure('Color','w','Position',[100 100 1200 900]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
nexttile; yyaxis left; plot(t(lineWindow),vac(lineWindow),'LineWidth',1.0); ylabel('v_{ac} (V)');
yyaxis right; plot(t(lineWindow),iac(lineWindow),'LineWidth',1.0); ylabel('i_{ac} (A)'); grid on;
title(sprintf('Steady PFC waveforms: PF=%.4f, THD_{2-40}=%.2f%%', ...
    metrics.power_factor,metrics.input_current_thd_percent));
nexttile; plot(t(lineWindow),vrect(lineWindow),'LineWidth',1.0); grid on; ylabel('v_{rect} (V)');
nexttile; plot(t(lineWindow),iL(lineWindow),'LineWidth',0.7); hold on;
plot(t(lineWindow),iRef(lineWindow),'LineWidth',1.0); grid on;
ylabel('Current (A)'); xlabel('Time (s)'); legend('i_L','i_L^*','Location','best');
exportgraphics(fig2,fullfile(resultDir,'nominal_24Vac_pfc_waveforms.png'),'Resolution',160);
close(fig2);

% Switching detail.
switchWindow = t >= t(end)-0.5e-3;
fig3 = figure('Color','w','Position',[100 100 1200 750]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
nexttile; stairs(t(switchWindow),pwm(switchWindow),'LineWidth',0.9); ylim([-0.1 1.1]); grid on; ylabel('PWM');
nexttile; plot(t(switchWindow),duty(switchWindow),'LineWidth',0.9); grid on; ylabel('Duty');
nexttile; plot(t(switchWindow),iL(switchWindow),'LineWidth',0.9); grid on; ylabel('i_L (A)'); xlabel('Time (s)');
exportgraphics(fig3,fullfile(resultDir,'nominal_24Vac_switching_detail.png'),'Resolution',180);
close(fig3);

fprintf('BOOSTPFC_DESIGN_NOMINAL_DONE\n');
disp(metrics);
fprintf('Saved: %s\n',resultMat);
fprintf('Saved: %s\n',resultJson);
close_system(modelName,0);

function values = signal(logs,name)
    element = logs.getElement(name);
    assert(~isempty(element),'Missing logged signal: %s',name);
    values = element.Values;
end

function result = pathResult(value)
    if isempty(value), result='<not on MATLAB path>'; else, result=value; end
end

function writeText(fileName,textValue)
    fileId=fopen(fileName,'w');
    cleanup=onCleanup(@()fclose(fileId));
    fwrite(fileId,textValue,'char');
end

