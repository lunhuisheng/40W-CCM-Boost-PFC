% Verify the original 10 ms / 34 V hold-up specification at 24 Vac and 40 ohm.

clear;
close all;
bdclose('all');
designDir=fileparts(mfilename('fullpath'));
modelName='BoostPFC_Design_HoldUpTest';
modelFile=fullfile(designDir,[modelName '.slx']);
resultDir=fullfile(designDir,'results','hold_up_test');
if ~isfolder(resultDir), mkdir(resultDir); end
load_system(modelFile);
run(fullfile(designDir,'BoostPFC_Design_HoldUp_Init.m'));

% 1.200 s is a positive-going zero crossing; 1.205 s is the following peak.
caseNames={'zero_crossing','line_peak'};
caseLabels={'AC zero crossing','AC positive peak'};
dropCommandTimes=[1.200 1.205];
caseResults=cell(2,1);
caseData=cell(2,1);

Pspec=40;
tSpec=10e-3;
V1spec=40;
V2spec=34;
theory=struct;
theory.spec_power_W=Pspec;
theory.spec_hold_time_s=tSpec;
theory.spec_initial_voltage_V=V1spec;
theory.spec_minimum_voltage_V=V2spec;
theory.minimum_capacitance_F=2*Pspec*tSpec/(V1spec^2-V2spec^2);
theory.minimum_capacitance_uF=theory.minimum_capacitance_F*1e6;
theory.installed_capacitance_F=C_out;
theory.installed_capacitance_uF=C_out*1e6;
theory.capacitance_margin_percent=100*(C_out/theory.minimum_capacitance_F-1);
theory.ideal_constant_power_hold_s=C_out*(V1spec^2-V2spec^2)/(2*Pspec);
theory.ideal_40ohm_resistive_hold_s=Rload_nominal*C_out*log(V1spec/V2spec);
theory.assumptions={ ...
    'constant-power formula neglects all losses and assumes exactly 40 W while voltage falls'; ...
    'behavioral model uses a constant 40 ohm resistor, so power falls as Vout squared'; ...
    'behavioral capacitor has no ESR or ESL; inductor may transfer residual energy through the boost diode'};

for caseIndex=1:2
    commandTime=dropCommandTimes(caseIndex);
    simulationInput=Simulink.SimulationInput(modelName);
    simulationInput=simulationInput.setVariable('Vac_rms',24);
    simulationInput=simulationInput.setVariable('startup_ramp_time_s',100e-3);
    simulationInput=simulationInput.setVariable('load_connection_strategy',0);
    simulationInput=simulationInput.setVariable('hold_up_command_time_s',commandTime);
    simulationInput=simulationInput.setModelParameter('StopTime',num2str(commandTime+0.030));
    simulationOutput=sim(simulationInput);
    logs=simulationOutput.logsout;

    data=struct;
    [data.t,data.vout]=values(logs,'vout');
    [~,data.vac]=values(logs,'vac');
    [~,data.iac]=values(logs,'iac');
    [~,data.vrect]=values(logs,'vrect');
    [~,data.iL]=values(logs,'iL');
    [~,data.rload]=values(logs,'Rload');
    [~,data.inputEnable]=values(logs,'input_enable');
    [~,data.startupState]=values(logs,'controlled_startup_state');
    data.outputPower=data.vout.^2./data.rload;

    commandIndex=find(diff(data.inputEnable>0.5)==-1,1,'first')+1;
    assert(~isempty(commandIndex),'Input-enable falling edge was not logged.');
    actualZeroIndex=sustainedZeroIndex(data.t,data.vac,data.vrect, ...
        data.t(commandIndex),1e-3);
    assert(~isempty(actualZeroIndex),'Input did not remain at zero for the confirmation window.');
    actualZeroTime=data.t(actualZeroIndex);
    phaseDeg=mod(360*f_line*actualZeroTime,360);

    beforeWindow=data.t>=actualZeroTime-20e-3 & data.t<actualZeroTime;
    afterWindow=data.t>=actualZeroTime;
    tenMsIndex=find(data.t>=actualZeroTime+10e-3,1,'first');
    thresholdIndex=find(afterWindow & data.vout<=V2spec,1,'first');

    metrics=struct;
    metrics.case_name=caseNames{caseIndex};
    metrics.case_label=caseLabels{caseIndex};
    metrics.command_time_s=commandTime;
    metrics.command_phase_deg=mod(360*f_line*commandTime,360);
    metrics.actual_input_zero_time_s=actualZeroTime;
    metrics.actual_input_zero_phase_deg=phaseDeg;
    metrics.command_to_actual_zero_delay_s=actualZeroTime-commandTime;
    metrics.input_zero_confirmation_window_s=1e-3;
    metrics.pre_dropout_state=data.startupState(max(actualZeroIndex-1,1));
    metrics.pre_dropout_vout_mean_20ms_V=mean(data.vout(beforeWindow));
    metrics.pre_dropout_vout_ripple_20ms_pp_V= ...
        max(data.vout(beforeWindow))-min(data.vout(beforeWindow));
    metrics.pre_dropout_output_power_mean_20ms_W=mean(data.outputPower(beforeWindow));
    metrics.pre_dropout_load_mean_ohm=mean(data.rload(beforeWindow));
    metrics.vout_at_actual_input_zero_V=data.vout(actualZeroIndex);
    metrics.output_power_at_actual_input_zero_W=data.outputPower(actualZeroIndex);
    metrics.capacitor_energy_at_actual_input_zero_J= ...
        0.5*C_out*data.vout(actualZeroIndex)^2;
    metrics.inductor_current_at_input_zero_A=data.iL(actualZeroIndex);
    metrics.inductor_energy_at_input_zero_J=0.5*L_boost*data.iL(actualZeroIndex)^2;
    metrics.vout_at_10ms_V=data.vout(tenMsIndex);
    metrics.output_power_at_10ms_W=data.outputPower(tenMsIndex);
    metrics.first_34V_crossing_occurred=~isempty(thresholdIndex);
    if isempty(thresholdIndex)
        metrics.first_34V_time_s=NaN;
        metrics.actual_hold_time_to_34V_s=NaN;
    else
        metrics.first_34V_time_s=data.t(thresholdIndex);
        metrics.actual_hold_time_to_34V_s=data.t(thresholdIndex)-actualZeroTime;
    end
    metrics.minimum_vout_after_dropout_V=min(data.vout(afterWindow));
    metrics.peak_inductor_current_after_dropout_A=max(data.iL(afterWindow));
    metrics.load_stayed_40ohm=all(abs(data.rload(afterWindow)-Rload_nominal)<1e-9);
    metrics.maximum_abs_vac_after_actual_zero_V=max(abs(data.vac(afterWindow)));
    metrics.maximum_vrect_after_actual_zero_V=max(data.vrect(afterWindow));
    metrics.pass_formal_10ms_34V_spec=metrics.vout_at_10ms_V>=V2spec;
    metrics.constant_power_theory_hold_s_using_pre_dropout_mean= ...
        C_out*(metrics.pre_dropout_vout_mean_20ms_V^2-V2spec^2)/(2*Pspec);
    metrics.resistive_theory_hold_s_using_pre_dropout_mean= ...
        Rload_nominal*C_out*log(metrics.pre_dropout_vout_mean_20ms_V/V2spec);
    metrics.constant_power_theory_hold_s_using_instantaneous_vout= ...
        C_out*(metrics.vout_at_actual_input_zero_V^2-V2spec^2)/(2*Pspec);
    metrics.resistive_theory_hold_s_using_instantaneous_vout= ...
        Rload_nominal*C_out*log(metrics.vout_at_actual_input_zero_V/V2spec);
    metrics.simulation_minus_40V_constant_power_theory_ms= ...
        1e3*(metrics.actual_hold_time_to_34V_s-theory.ideal_constant_power_hold_s);
    metrics.simulation_minus_case_resistive_theory_ms= ...
        1e3*(metrics.actual_hold_time_to_34V_s- ...
        metrics.resistive_theory_hold_s_using_instantaneous_vout);

    assert(metrics.pre_dropout_state==4,'Dropout occurred before final run state.');
    assert(metrics.load_stayed_40ohm,'Load did not remain at 40 ohm.');

    caseResults{caseIndex}=metrics;
    caseData{caseIndex}=data;
    save(fullfile(resultDir,[caseNames{caseIndex} '_raw_results.mat']),'data','metrics','theory');
    writeText(fullfile(resultDir,[caseNames{caseIndex} '_metrics.json']), ...
        jsonencode(metrics,PrettyPrint=true));
    fprintf(['HOLD_UP %s: actual zero %.6f s / %.3f deg, pre %.4f V, ', ...
        '10 ms %.4f V, 34 V at %.4f ms, pass=%d\n'], ...
        caseNames{caseIndex},actualZeroTime,phaseDeg, ...
        metrics.pre_dropout_vout_mean_20ms_V,metrics.vout_at_10ms_V, ...
        1e3*metrics.actual_hold_time_to_34V_s,metrics.pass_formal_10ms_34V_spec);
end

summary=struct;
summary.model=modelName;
summary.test_baseline=struct('input_rms_V',24,'load_ohm',40, ...
    'startup_ramp_time_s',100e-3,'L_H',L_boost,'C_F',C_out, ...
    'dropout_applied_only_after_state_4',true);
summary.hold_time_definition=[ ...
    'from the first sample at/after input-enable falling edge for which both ', ...
    'gated Vac and Vrect remain zero for 1 ms, to the first Vout <=34 V sample'];
summary.formal_acceptance='Vout at 10 ms after actual input loss must be >=34 V';
summary.theory=theory;
summary.cases=[caseResults{:}];
save(fullfile(resultDir,'hold_up_summary.mat'),'summary');
writeText(fullfile(resultDir,'hold_up_summary.json'),jsonencode(summary,PrettyPrint=true));

% Unified, dropout-aligned waveform comparison.
fig=figure('Color','w','Position',[70 50 1450 1150]);
tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
colors=lines(2);
nexttile; hold on;
for k=1:2
    x=1e3*(caseData{k}.t-caseResults{k}.actual_input_zero_time_s);
    plot(x,caseData{k}.vout,'Color',colors(k,:),'LineWidth',1);
end
yline(34,'--','34 V'); xline(0,':'); xline(10,':','10 ms');
grid on; ylabel('V_o (V)'); title('40 W hold-up test aligned to actual input loss');
legend(caseLabels{1},caseLabels{2},'34 V','input lost','10 ms','Location','best');
nexttile; hold on;
for k=1:2
    x=1e3*(caseData{k}.t-caseResults{k}.actual_input_zero_time_s);
    plot(x,caseData{k}.iL,'Color',colors(k,:));
end
grid on; ylabel('i_L (A)'); xline(0,':');
nexttile; hold on;
for k=1:2
    x=1e3*(caseData{k}.t-caseResults{k}.actual_input_zero_time_s);
    plot(x,caseData{k}.vac,'Color',colors(k,:));
end
grid on; ylabel('V_{ac} (V)'); xline(0,':');
nexttile; hold on;
for k=1:2
    x=1e3*(caseData{k}.t-caseResults{k}.actual_input_zero_time_s);
    plot(x,caseData{k}.outputPower,'Color',colors(k,:));
end
grid on; ylabel('P_o (W)'); xlabel('Time from actual input loss (ms)'); xline(0,':');
set(findall(fig,'Type','axes'),'XLim',[-25 30]);
exportgraphics(fig,fullfile(resultDir,'hold_up_phase_comparison.png'),'Resolution',180);
close(fig);

for k=1:2
    data=caseData{k}; metrics=caseResults{k};
    x=1e3*(data.t-metrics.actual_input_zero_time_s);
    fig=figure('Color','w','Position',[90 70 1300 1000]);
    tiledlayout(4,1,'TileSpacing','compact','Padding','compact');
    nexttile; plot(x,data.vout,'LineWidth',1); hold on; yline(34,'--'); xline(0,':'); xline(10,':');
    grid on; ylabel('V_o (V)'); title(caseLabels{k});
    nexttile; plot(x,data.iL,'LineWidth',1); grid on; ylabel('i_L (A)'); xline(0,':');
    nexttile; plot(x,data.vac,'LineWidth',1); hold on; plot(x,data.vrect,'LineWidth',1);
    grid on; ylabel('Input (V)'); legend('Vac','Vrect','Location','best'); xline(0,':');
    nexttile; plot(x,data.outputPower,'LineWidth',1); grid on; ylabel('P_o (W)'); xlabel('Time from actual input loss (ms)'); xline(0,':');
    set(findall(fig,'Type','axes'),'XLim',[-25 30]);
    exportgraphics(fig,fullfile(resultDir,[caseNames{k} '_waveforms.png']),'Resolution',180);
    close(fig);
end

close_system(modelName,0);

function [t,data]=values(logs,name)
element=logs.getElement(name); assert(~isempty(element),'Missing signal: %s',name);
t=element.Values.Time(:); data=element.Values.Data(:);
end

function index=sustainedZeroIndex(t,vac,vrect,startTime,confirmationTime)
dt=median(diff(t)); nConfirm=max(1,ceil(confirmationTime/dt));
startIndex=find(t>=startTime,1,'first'); index=[];
for candidate=startIndex:numel(t)-nConfirm+1
    range=candidate:candidate+nConfirm-1;
    if all(abs(vac(range))<=1e-12) && all(abs(vrect(range))<=1e-12)
        index=candidate; return;
    end
end
end

function writeText(fileName,textValue)
fileId=fopen(fileName,'w'); cleanup=onCleanup(@()fclose(fileId));
fwrite(fileId,textValue,'char');
end
