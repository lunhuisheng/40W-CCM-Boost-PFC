% BoostPFC_Design_LoopAudit
% Independent control-loop stability audit for the frozen behavioral model.
% This script does not edit or simulate the frozen Simulink model.  It:
%   1) reproduces the original ideal continuous averaged estimates;
%   2) adds load damping and conduction resistance to a working-point model;
%   3) evaluates 20/24/28 Vac using measured steady operating points; and
%   4) brackets PWM/actuation delay with a frequency-domain sensitivity test.
%
% The results are analytical small-signal baselines.  They are not a
% replacement for sampled-data linearization, switched-model loop injection,
% device-level simulation, or hardware loop-gain measurement.

clear;
close all;

designDir = fileparts(mfilename('fullpath'));
resultDir = fullfile(designDir,'results','loop_audit');
if ~isfolder(resultDir), mkdir(resultDir); end
run(fullfile(designDir,'BoostPFC_Design_ControlledStartup_Init.m'));

rangeFile = fullfile(designDir,'results','final_input_range', ...
    'final_input_range_summary.json');
if ~isfile(rangeFile)
    error('Required measured operating-point file is missing: %s',rangeFile);
end
rangeSummary = jsondecode(fileread(rangeFile));

s = tf('s');
Ci = Kp_i + Ki_i/s;
Cv = Kp_v + Ki_v/s;

% Reproduce the original script exactly: ideal integrator plants, 24 Vac,
% no load damping, conduction loss, inner-loop closure or delay.
legacyCurrentPlant = Vout_ref/(L_boost*s);
legacyVoltagePlant = gvi_coefficient/s;
legacyCurrentOpenLoop = Ci*legacyCurrentPlant;
legacyVoltageOpenLoop = Cv*legacyVoltagePlant;
legacyCurrentMargin = marginRecord(legacyCurrentOpenLoop);
legacyVoltageMargin = marginRecord(legacyVoltageOpenLoop);

cases = rangeSummary.cases;
caseAudit = repmat(struct,1,numel(cases));
currentLoops = cell(1,numel(cases));
voltageLoops = cell(1,numel(cases));

for k = 1:numel(cases)
    measured = cases(k).steady;
    Vac = cases(k).input_command_rms_V;
    Vout = measured.output_mean_V;
    Dpeak = measured.duty_mean_near_rectified_peak;

    % Line-peak CCM duty-to-current plant.  The resistance is the averaged
    % incremental conduction resistance: inductor ESR plus D*Rds(on).
    % Diode forward voltage is a DC operating-point offset, not an
    % incremental resistance in this behavioral model.
    Req = rL_effective + Dpeak*Rds_on_effective;
    Gid = Vout/(L_boost*s + Req);
    Li = Ci*Gid;
    Ti = feedback(Li,1);

    % Line-cycle averaged current-amplitude-to-voltage plant.  vLoop is the
    % commanded peak sinusoidal input-current amplitude because
    % iRef=vLoop*vrect/Vpeak.  Linearizing capacitor energy balance gives:
    % Gvi=(Vac/sqrt(2))/(C*Vout*s + 2*Vout/Rload).
    Gvi = (Vac/sqrt(2))/(C_out*Vout*s + 2*Vout/Rload_nominal);
    Lv = Cv*Gvi*Ti;

    currentLoops{k} = Li;
    voltageLoops{k} = Lv;
    caseAudit(k).input_rms_V = Vac;
    caseAudit(k).measured_output_mean_V = Vout;
    caseAudit(k).measured_duty_mean_near_rectified_peak = Dpeak;
    caseAudit(k).measured_duty_min = measured.duty_min;
    caseAudit(k).measured_boost_headroom_V = ...
        measured.boost_headroom_meanVout_minus_rectified_peak_V;
    caseAudit(k).incremental_series_resistance_ohm = Req;
    caseAudit(k).current_loop = marginRecord(Li);
    caseAudit(k).voltage_loop = marginRecord(Lv);
    caseAudit(k).switching_to_current_crossover_ratio = ...
        f_sw/caseAudit(k).current_loop.gain_crossover_Hz;
    caseAudit(k).current_to_voltage_crossover_ratio = ...
        caseAudit(k).current_loop.gain_crossover_Hz/ ...
        caseAudit(k).voltage_loop.gain_crossover_Hz;
end

% The controller function executes every Ts_sim=1 us, while its carrier is
% 50 kHz.  The exact small-signal modulator delay has not been identified.
% Therefore use a transparent 0.5/1.0/1.5*Tsw bracket, not a claimed exact
% discrete model.  Exact e^(-jwT) phase is used; magnitude is unchanged.
Tsw = 1/f_sw;
delayMultipliers = [0.5 1.0 1.5];
delayAuditCell = cell(1,numel(delayMultipliers));
case24Index = find([caseAudit.input_rms_V] == 24,1);
for k = 1:numel(delayMultipliers)
    delayRecord = delayedMarginRecord(currentLoops{case24Index}, ...
        delayMultipliers(k)*Tsw,f_sw/2);
    delayRecord.delay_in_switching_periods = delayMultipliers(k);
    delayAuditCell{k} = delayRecord;
end
delayAudit = [delayAuditCell{:}];

audit = struct;
audit.generated_at = [char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')) ...
    ' Asia/Shanghai'];
audit.scope = ['Independent analytical audit; frozen Simulink model not ', ...
    'modified or simulated by this script'];
audit.model_classes = struct( ...
    'continuous_average','PI and averaged small-signal plants used here', ...
    'discrete_delay_sensitivity', ...
        'exact frequency-domain delay bracket only; not an identified sampled-data model', ...
    'switched_behavioral', ...
        'frozen cycle-resolved model supplies measured operating points only');
audit.controller = struct( ...
    'voltage_PI_Kp',Kp_v,'voltage_PI_Ki_per_s',Ki_v, ...
    'current_PI_Kp',Kp_i,'current_PI_Ki_per_s',Ki_i, ...
    'voltage_PI_zero_Hz',Ki_v/Kp_v/(2*pi), ...
    'current_PI_zero_Hz',Ki_i/Kp_i/(2*pi), ...
    'reference_amplitude_limit_A',Ipk_limit, ...
    'duty_min',duty_min,'duty_max',duty_max, ...
    'controller_execution_step_s',Ts_sim,'switching_frequency_Hz',f_sw, ...
    'cycle_current_limit_A',actual_peak_cycle_limit_A, ...
    'behavioral_fault_latch_A',actual_peak_fault_limit_A, ...
    'anti_windup',['conditional integration in both PI loops when the ', ...
        'limited output would be driven farther into saturation']);
audit.original_analysis = struct( ...
    'basis',['24 Vac ideal continuous averaged PI-times-integrator; ', ...
        'no load pole, losses, delay, limits or inner-loop closure in outer loop'], ...
    'current_loop',legacyCurrentMargin, ...
    'voltage_loop',legacyVoltageMargin);
audit.plants_and_feedback = struct( ...
    'current_loop',['Unity feedback of measured iL.  Around the line peak, ', ...
        'Gid(s)=Vout/(L*s+rL+Dpeak*Rds_on).  The feed-forward duty term is ', ...
        'constant for the local iRef-to-iL perturbation.'], ...
    'voltage_loop',['Unity feedback of Vout.  vLoop commands sinusoidal peak ', ...
        'current through iRef=vLoop*vrect/Vpeak.  Line-cycle energy ', ...
        'linearization gives Gvi(s)=(Vac/sqrt(2))/(C*Vout*s+2*Vout/R). ', ...
        'The outer open loop also includes the closed current loop Ti(s).']);
audit.working_point_analysis_basis = [ ...
    'Continuous CCM line-peak current plant with averaged conduction resistance; ', ...
    'line-cycle averaged voltage plant with 40-ohm load damping and closed inner loop'];
audit.operating_points = caseAudit;
audit.current_loop_delay_sensitivity_24Vac = delayAudit;
audit.calculation_method = struct( ...
    'continuous_margin',['MATLAB margin(): phase margin at the 0 dB gain ', ...
        'crossover and gain margin at a finite -180 degree phase crossover'], ...
    'closed_loop_stability',['All poles of feedback(open_loop,1) must have ', ...
        'strictly negative real part'], ...
    'delay_margin',['Frequency response multiplied by exp(-j*w*Tdelay); ', ...
        'crossings found by logarithmic-frequency interpolation']);
audit.interpretation = struct( ...
    'gain_margin',['Infinite means no finite -180 degree phase crossing in ', ...
        'the applicable continuous model; it is not proof of unlimited robustness'], ...
    'delay',['Delay cases are sensitivity bounds.  The actual PWM/sampling ', ...
        'delay was not identified from the switched model'], ...
    'nonlinear_limits',['Bode results apply only while duty, current-reference ', ...
        'and actual-current protection limits are inactive'], ...
    'hardware',['No result in this file establishes device-level or hardware stability']);
audit.unverified = { ...
    'Frequency-response injection into the frozen switched behavioral model'; ...
    'Exact sampled-data/PWM small-signal model and effective actuation delay'; ...
    'Linearization during duty saturation, cycle current limiting or fault latch'; ...
    'Line-zero-crossing time-periodic stability and subharmonic behavior'; ...
    'Device parasitics, current-sense/filter delay, computation delay and hardware loop gain'};

makeBodeFigure(currentLoops,voltageLoops,caseAudit, ...
    fullfile(resultDir,'loop_audit_bode_20_24_28Vac.png'));
makeDelayFigure(currentLoops{case24Index},delayAudit, ...
    fullfile(resultDir,'current_loop_delay_sensitivity_24Vac.png'));

save(fullfile(resultDir,'loop_audit_results.mat'),'audit', ...
    'legacyCurrentOpenLoop','legacyVoltageOpenLoop','currentLoops','voltageLoops');
writeJson(fullfile(resultDir,'loop_audit_summary.json'),audit);
writeMarkdown(fullfile(resultDir,'CONTROL_LOOP_AUDIT.md'),audit);

disp(audit.controller);
for k = 1:numel(caseAudit)
    fprintf(['%g Vac: current fc=%.3f Hz PM=%.3f deg; ', ...
        'voltage fc=%.3f Hz PM=%.3f deg\n'], ...
        caseAudit(k).input_rms_V, ...
        caseAudit(k).current_loop.gain_crossover_Hz, ...
        caseAudit(k).current_loop.phase_margin_deg, ...
        caseAudit(k).voltage_loop.gain_crossover_Hz, ...
        caseAudit(k).voltage_loop.phase_margin_deg);
end
for k = 1:numel(delayAudit)
    fprintf('24 Vac current delay %.1f Tsw: PM=%.3f deg, GM=%.3f dB at %.3f Hz\n', ...
        delayAudit(k).delay_in_switching_periods, ...
        delayAudit(k).phase_margin_deg,delayAudit(k).gain_margin_dB, ...
        delayAudit(k).phase_crossover_Hz);
end

function rec = marginRecord(sys)
    [gm,pm,wcg,wcp] = margin(sys);
    rec = struct;
    rec.gain_crossover_Hz = wcp/(2*pi);
    rec.phase_margin_deg = pm;
    if isfinite(gm) && gm > 0 && isfinite(wcg) && wcg > 0
        rec.gain_margin_dB = 20*log10(gm);
        rec.phase_crossover_Hz = wcg/(2*pi);
        rec.gain_margin_class = 'finite';
    else
        rec.gain_margin_dB = [];
        rec.phase_crossover_Hz = [];
        rec.gain_margin_class = 'infinite_no_finite_phase_crossover';
    end
    polesClosed = pole(feedback(sys,1));
    rec.closed_loop_poles_rad_per_s = polesClosed(:).';
    rec.closed_loop_stable = all(real(polesClosed) < 0);
end

function rec = delayedMarginRecord(sys,delay_s,nyquist_Hz)
    f = logspace(-1,5,200000);
    w = 2*pi*f;
    h = squeeze(freqresp(sys,w));
    magnitude_dB = 20*log10(abs(h));
    phase_deg = unwrap(angle(h))*180/pi - w(:)*delay_s*180/pi;
    logf = log10(f(:));

    gainIndex = find(magnitude_dB(1:end-1) >= 0 & ...
        magnitude_dB(2:end) < 0,1,'first');
    if isempty(gainIndex)
        gainCrossover = NaN;
        phaseMargin = NaN;
    else
        gainLogF = interp1(magnitude_dB(gainIndex:gainIndex+1), ...
            logf(gainIndex:gainIndex+1),0);
        gainCrossover = 10^gainLogF;
        phaseAtGain = interp1(logf,phase_deg,gainLogF);
        phaseMargin = 180 + phaseAtGain;
    end

    phaseIndex = find(phase_deg(1:end-1) > -180 & ...
        phase_deg(2:end) <= -180,1,'first');
    if isempty(phaseIndex)
        phaseCrossover = NaN;
        gainMargin = NaN;
    else
        phaseLogF = interp1(phase_deg(phaseIndex:phaseIndex+1), ...
            logf(phaseIndex:phaseIndex+1),-180);
        phaseCrossover = 10^phaseLogF;
        magnitudeAtPhase = interp1(logf,magnitude_dB,phaseLogF);
        gainMargin = -magnitudeAtPhase;
    end

    rec = struct('assumed_delay_s',delay_s, ...
        'gain_crossover_Hz',gainCrossover, ...
        'phase_margin_deg',phaseMargin, ...
        'gain_margin_dB',gainMargin, ...
        'phase_crossover_Hz',phaseCrossover, ...
        'phase_crossover_below_25kHz_nyquist',phaseCrossover < nyquist_Hz, ...
        'validity_note',['Sensitivity estimate only; phase crossover near ', ...
            'the switching/Nyquist region is outside a trustworthy averaged-model range']);
end

function makeBodeFigure(currentLoops,voltageLoops,caseAudit,fileName)
    currentFrequency = logspace(1,4.7,2500);
    voltageFrequency = logspace(-1,2.5,2500);
    colors = lines(numel(caseAudit));
    fig = figure('Color','w','Position',[80 80 1350 900]);
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    ax1 = nexttile; hold(ax1,'on');
    ax2 = nexttile; hold(ax2,'on');
    ax3 = nexttile; hold(ax3,'on');
    ax4 = nexttile; hold(ax4,'on');
    labels = cell(1,numel(caseAudit));
    for k = 1:numel(caseAudit)
        labels{k} = sprintf('%g Vac',caseAudit(k).input_rms_V);
        [mag,phase] = response(currentLoops{k},currentFrequency);
        semilogx(ax1,currentFrequency,mag,'LineWidth',1.2,'Color',colors(k,:));
        semilogx(ax3,currentFrequency,phase,'LineWidth',1.2,'Color',colors(k,:));
        [mag,phase] = response(voltageLoops{k},voltageFrequency);
        semilogx(ax2,voltageFrequency,mag,'LineWidth',1.2,'Color',colors(k,:));
        semilogx(ax4,voltageFrequency,phase,'LineWidth',1.2,'Color',colors(k,:));
    end
    yline(ax1,0,'k:'); yline(ax2,0,'k:');
    yline(ax3,-180,'k:'); yline(ax4,-180,'k:');
    grid(ax1,'on'); grid(ax2,'on'); grid(ax3,'on'); grid(ax4,'on');
    set([ax1 ax2 ax3 ax4],'XScale','log');
    xlim(ax1,[currentFrequency(1) currentFrequency(end)]);
    xlim(ax3,[currentFrequency(1) currentFrequency(end)]);
    xlim(ax2,[voltageFrequency(1) voltageFrequency(end)]);
    xlim(ax4,[voltageFrequency(1) voltageFrequency(end)]);
    title(ax1,'Current-loop open-loop magnitude'); ylabel(ax1,'Magnitude (dB)');
    title(ax2,'Voltage-loop open-loop magnitude'); ylabel(ax2,'Magnitude (dB)');
    title(ax3,'Current-loop open-loop phase'); ylabel(ax3,'Phase (deg)'); xlabel(ax3,'Frequency (Hz)');
    title(ax4,'Voltage-loop open-loop phase'); ylabel(ax4,'Phase (deg)'); xlabel(ax4,'Frequency (Hz)');
    legend(ax1,labels,'Location','southwest'); legend(ax2,labels,'Location','southwest');
    sgtitle('Working-point-aware continuous averaged loop audit (not hardware validation)');
    exportgraphics(fig,fileName,'Resolution',170);
    close(fig);
end

function makeDelayFigure(currentLoop,delayAudit,fileName)
    f = logspace(1,4.7,2500);
    w = 2*pi*f;
    h = squeeze(freqresp(currentLoop,w));
    mag = 20*log10(abs(h));
    basePhase = unwrap(angle(h))*180/pi;
    colors = lines(numel(delayAudit)+1);
    fig = figure('Color','w','Position',[100 100 1200 800]);
    tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
    ax1=nexttile; semilogx(ax1,f,mag,'LineWidth',1.3,'Color',colors(1,:));
    hold(ax1,'on'); yline(ax1,0,'k:'); grid(ax1,'on'); ylabel(ax1,'Magnitude (dB)');
    title(ax1,'24 Vac current-loop magnitude (delay has unity magnitude)');
    ax2=nexttile; semilogx(ax2,f,basePhase,'LineWidth',1.3,'Color',colors(1,:)); hold(ax2,'on');
    labels={'0 T_{sw}'};
    for k=1:numel(delayAudit)
        phase=basePhase-w(:)*delayAudit(k).assumed_delay_s*180/pi;
        semilogx(ax2,f,phase,'LineWidth',1.2,'Color',colors(k+1,:));
        labels{end+1}=sprintf('%.1f T_{sw}',delayAudit(k).delay_in_switching_periods); %#ok<AGROW>
    end
    yline(ax2,-180,'k:'); grid(ax2,'on'); ylabel(ax2,'Phase (deg)'); xlabel(ax2,'Frequency (Hz)');
    title(ax2,'PWM/actuation-delay sensitivity (assumed, not identified)');
    legend(ax2,labels,'Location','southwest');
    exportgraphics(fig,fileName,'Resolution',170);
    close(fig);
end

function [mag,phase] = response(sys,f)
    h=squeeze(freqresp(sys,2*pi*f));
    mag=20*log10(abs(h));
    phase=unwrap(angle(h))*180/pi;
end

function writeJson(fileName,value)
    fileId=fopen(fileName,'w');
    if fileId<0, error('Cannot open %s for writing.',fileName); end
    cleaner=onCleanup(@()fclose(fileId));
    fwrite(fileId,jsonencode(value,PrettyPrint=true),'char');
end

function writeMarkdown(fileName,audit)
    fileId=fopen(fileName,'w');
    if fileId<0, error('Cannot open %s for writing.',fileName); end
    cleaner=onCleanup(@()fclose(fileId));
    c=audit.controller;
    fprintf(fileId,'# Control-loop stability audit\n\n');
    fprintf(fileId,'Generated: %s\n\n',audit.generated_at);
    fprintf(fileId,['This is an analytical continuous-averaged baseline. It does **not** ', ...
        'claim sampled-data, device-level, or hardware stability. The frozen ', ...
        'Simulink model and all controller values were left unchanged.\n\n']);
    fprintf(fileId,'## Controller values verified from the frozen model\n\n');
    fprintf(fileId,'| Item | Value |\n|---|---:|\n');
    fprintf(fileId,'| Voltage PI Kp | %.12g |\n',c.voltage_PI_Kp);
    fprintf(fileId,'| Voltage PI Ki | %.12g 1/s |\n',c.voltage_PI_Ki_per_s);
    fprintf(fileId,'| Current PI Kp | %.12g |\n',c.current_PI_Kp);
    fprintf(fileId,'| Current PI Ki | %.12g 1/s |\n',c.current_PI_Ki_per_s);
    fprintf(fileId,'| Current-amplitude reference limit | %.3f A |\n',c.reference_amplitude_limit_A);
    fprintf(fileId,'| Duty range | %.3f to %.3f |\n',c.duty_min,c.duty_max);
    fprintf(fileId,'| Behavioral cycle limiter | %.3f A |\n',c.cycle_current_limit_A);
    fprintf(fileId,'| Behavioral fault latch | %.3f A |\n',c.behavioral_fault_latch_A);
    fprintf(fileId,'| Controller execution step | %.3g s |\n',c.controller_execution_step_s);
    fprintf(fileId,'| PWM frequency | %.0f Hz |\n\n',c.switching_frequency_Hz);
    fprintf(fileId,'Anti-windup: %s.\n\n',c.anti_windup);
    fprintf(fileId,'## Plants, feedback paths and method\n\n');
    fprintf(fileId,'- Current loop: %s\n',audit.plants_and_feedback.current_loop);
    fprintf(fileId,'- Voltage loop: %s\n',audit.plants_and_feedback.voltage_loop);
    fprintf(fileId,'- Continuous margins: %s.\n',audit.calculation_method.continuous_margin);
    fprintf(fileId,'- Stability test: %s.\n',audit.calculation_method.closed_loop_stability);
    fprintf(fileId,'- Delay sensitivity: %s.\n\n',audit.calculation_method.delay_margin);
    fprintf(fileId,['The gains come from `BoostPFC_Design_Init.m`: the current PI was ', ...
        'sized for a 3 kHz crossover and 500 Hz zero using Vout/(L*s); the ', ...
        'voltage PI was sized for an 8 Hz crossover and 1.5 Hz zero at 24 Vac ', ...
        'using Vac/(sqrt(2)*C*Vout*s). They were not retuned in this audit.\n\n']);
    fprintf(fileId,'## What the original loop script calculated\n\n%s.\n\n',audit.original_analysis.basis);
    fprintf(fileId,'| Loop | Crossover | Phase margin | Gain margin |\n|---|---:|---:|---|\n');
    writeMarginRow(fileId,'Current',audit.original_analysis.current_loop);
    writeMarginRow(fileId,'Voltage',audit.original_analysis.voltage_loop);
    fprintf(fileId,'\n## Working-point-aware continuous averaged audit\n\n%s.\n\n',audit.working_point_analysis_basis);
    fprintf(fileId,['| Input | Current fc | Current PM | Current GM | Voltage fc | ', ...
        'Voltage PM | Voltage GM | fsw/fci | fci/fcv |\n']);
    fprintf(fileId,'|---:|---:|---:|---|---:|---:|---|---:|---:|\n');
    for k=1:numel(audit.operating_points)
        q=audit.operating_points(k);
        fprintf(fileId,'| %.0f Vac | %.3f Hz | %.3f deg | %s | %.3f Hz | %.3f deg | %s | %.2f | %.1f |\n', ...
            q.input_rms_V,q.current_loop.gain_crossover_Hz,q.current_loop.phase_margin_deg, ...
            marginText(q.current_loop),q.voltage_loop.gain_crossover_Hz, ...
            q.voltage_loop.phase_margin_deg,marginText(q.voltage_loop), ...
            q.switching_to_current_crossover_ratio,q.current_to_voltage_crossover_ratio);
    end
    fprintf(fileId,'\nAll listed closed-loop poles are in the open left half-plane for these linear models. ');
    fprintf(fileId,'That conclusion applies only around the stated unsaturated working points.\n\n');
    fprintf(fileId,'## 24 Vac current-loop delay sensitivity\n\n');
    fprintf(fileId,'| Assumed delay | PM | GM | Phase crossing | Below 25 kHz Nyquist? |\n');
    fprintf(fileId,'|---:|---:|---:|---:|---|\n');
    for k=1:numel(audit.current_loop_delay_sensitivity_24Vac)
        q=audit.current_loop_delay_sensitivity_24Vac(k);
        fprintf(fileId,'| %.1f Tsw | %.3f deg | %.3f dB | %.3f Hz | %s |\n', ...
            q.delay_in_switching_periods,q.phase_margin_deg,q.gain_margin_dB, ...
            q.phase_crossover_Hz,string(q.phase_crossover_below_25kHz_nyquist));
    end
    fprintf(fileId,['\nThe delay range is an explicit sensitivity assumption. The actual ', ...
        'effective modulator delay has not been identified, so these finite gain ', ...
        'margins are not accepted as measured margins.\n\n']);
    fprintf(fileId,'## Limits of applicability\n\n');
    fprintf(fileId,['- Current-loop linearization is at the rectified-line peak. ', ...
        'Line zero crossings and discontinuous/saturated intervals are not covered.\n']);
    fprintf(fileId,['- The outer model assumes the inner current loop follows a sinusoidal ', ...
        'amplitude command and averages energy over a complete line cycle.\n']);
    fprintf(fileId,['- At 28 Vac the measured mean near-peak duty and minimum duty are small; ', ...
        'downward control authority is limited and large perturbations can hit zero duty.\n']);
    fprintf(fileId,['- The current crossover is about 3.04 kHz, or f_sw/f_ci about 16.45. ', ...
        'It is below f_sw/10, but the delay sensitivity shows that switching ', ...
        'and modulation delay still materially reduce phase margin.\n']);
    fprintf(fileId,['- The current/voltage crossover separation is 347 to 519, so the ', ...
        'cascade bandwidth hierarchy is strong in these averaged models.\n']);
    fprintf(fileId,['- Conditional-integration anti-windup and current protection are nonlinear ', ...
        'and therefore absent from the unsaturated Bode model.\n']);
    fprintf(fileId,['- Device parasitics, sensing filters and delays, magnetic saturation and ', ...
        'digital implementation effects are absent.\n\n']);
    fprintf(fileId,'## Not yet verified\n\n');
    for k=1:numel(audit.unverified), fprintf(fileId,'- %s\n',audit.unverified{k}); end
end

function writeMarginRow(fileId,name,q)
    fprintf(fileId,'| %s | %.3f Hz | %.3f deg | %s |\n', ...
        name,q.gain_crossover_Hz,q.phase_margin_deg,marginText(q));
end

function text = marginText(q)
    if strcmp(q.gain_margin_class,'finite')
        text=sprintf('%.3f dB at %.3f Hz',q.gain_margin_dB,q.phase_crossover_Hz);
    else
        text='Inf (no finite phase crossing)';
    end
end
