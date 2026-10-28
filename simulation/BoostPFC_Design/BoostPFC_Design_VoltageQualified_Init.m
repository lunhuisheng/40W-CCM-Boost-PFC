% Voltage-qualified startup parameters for BoostPFC_Design_VoltageQualified.
% Load the unchanged electrical and control design first.

startupInitDir = fileparts(mfilename('fullpath'));
run(fullfile(startupInitDir,'BoostPFC_Design_Init.m'));

% A passive bridge/boost-diode precharge cannot reach the 40 V regulated
% output.  Its modeled ceiling is the rectified line peak minus the two
% conducting bridge-diode drops and the boost-diode drop.
precharge_passive_ceiling_V = sqrt(2)*Vac_rms ...
    - 2*Vf_bridge_effective - Vf_boost_effective;
precharge_voltage_fraction = 0.90;
precharge_voltage_threshold = ...
    precharge_voltage_fraction*precharge_passive_ceiling_V;

% Qualification must persist for one quarter of a 50 Hz line cycle.  The
% timeout spans 25 line cycles and is much longer than Rpre*Cout = 22 ms.
precharge_qualification_time = 5e-3;
precharge_timeout_time = 0.50;

fprintf(['Voltage-qualified startup: passive ceiling %.3f V, threshold ', ...
    '%.3f V, qualification %.1f ms, timeout %.3f s.\n'], ...
    precharge_passive_ceiling_V,precharge_voltage_threshold, ...
    precharge_qualification_time*1e3,precharge_timeout_time);

clear startupInitDir;
