% Parameters for the isolated safe-bypass qualification experiment.

initDir=fileparts(mfilename('fullpath'));
run(fullfile(initDir,'BoostPFC_Design_Init.m'));

safe_rectified_peak_V=sqrt(2)*Vac_rms-2*Vf_bridge_effective;
safe_passive_ceiling_V=safe_rectified_peak_V-Vf_boost_effective;
safe_output_fraction=0.98;
safe_rectified_fraction=0.98;
safe_output_threshold_V=safe_output_fraction*safe_passive_ceiling_V;
safe_rectified_threshold_V=safe_rectified_fraction*safe_rectified_peak_V;
safe_voltage_difference_max_V=1.5;
safe_bypass_current_max_A=0.25;
safe_condition_hold_time_s=0.2e-3;
safe_bypass_timeout_s=0.50;

fprintf(['Safe-bypass thresholds: Vo>=%.4f V, Vrect>=%.4f V, ', ...
    '|Vrect-Vo|<=%.3f V, iL<=%.3f A for %.3f ms; timeout %.3f s.\n'], ...
    safe_output_threshold_V,safe_rectified_threshold_V, ...
    safe_voltage_difference_max_V,safe_bypass_current_max_A, ...
    safe_condition_hold_time_s*1e3,safe_bypass_timeout_s);
clear initDir;
