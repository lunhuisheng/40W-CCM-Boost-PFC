# 40 W CCM Boost PFC — first simulation design record

## Project identity

This is an independently constructed switched behavioral Simulink model. It was created from an empty model by `Build_BoostPFC_Design.m`; it is not a renamed or edited copy of the repository/MathWorks PFC example.

Power flow represented by the model:

`20–28 Vac source -> full-wave bridge -> precharge path -> 470 uH boost inductor -> MOSFET/boost-diode switching states -> 2200 uF output capacitor -> resistive load`

The control path contains a voltage PI, sinusoidal current-reference generator, current PI, feed-forward duty term, anti-windup limits, soft start and a 50 kHz PWM comparator.

## Parameters and assumptions

- Rated input: 24 Vac RMS, 50 Hz.
- Output target: 40 V, 40 W, 40 ohm.
- Switching frequency: 50 kHz.
- Simulation step: 1 us (20 steps per switching period).
- Initial L/C: 470 uH / 2200 uF.
- Non-ideal conduction assumptions: 0.7 V per bridge diode, 0.65 V boost diode, 40 milliohm MOSFET Rds(on), 100 milliohm inductor ESR.
- Not yet modeled: reverse recovery, nonlinear capacitances, magnetic saturation/core loss, capacitor ESR/ESL and gate-driver delay.
- The model is primarily CCM over the power-carrying portion of the line cycle but reaches zero current around line zero crossings.
- Current-loop estimate: 3.04 kHz crossover, 80.66 deg phase margin.
- Voltage-loop estimate: 8.13 Hz crossover, 79.55 deg phase margin.
- Loop results are continuous averaged estimates. Switching delay, saturation and operating-point variation are excluded. There is no useful finite -180 deg phase crossover in this simplified PI-plus-integrator model, so a finite gain margin is not claimed.

## Component calculations

- Hold-up requirement: `Cmin = 2*P*th/(V1^2-V2^2) = 1801.8 uF`; 2200 uF passes the analytical minimum.
- This hold-up result is analytical only. A dedicated source-interruption simulation has not yet been run.
- The initial 100 Hz ripple estimate supports using 2200 uF; the actual nominal simulation produced 1.615 V peak-to-peak.

## Actual simulation results

### Rated 24 Vac / 40 ohm

- Output mean: 39.821 V; error: -0.447% — pass (target ±2%).
- Output ripple: 1.615 Vpp — pass (target <=2 Vpp).
- Cycle-average 2% settling time: 0.760 s.
- Output maximum in the current 200 ms precharge/delayed-load version: 40.604 V; overshoot relative to 40 V: 1.51%.
- PF: 0.9965 — pass (target >=0.95).
- THD: 5.45% for harmonics 2–40 (through 2 kHz) — pass against the project target of 10%. This is not an IEC compliance measurement.
- PWM: 0/1 logic levels, measured frequency 50.000 kHz.
- Steady inductor maximum: 2.804 A; estimated switching ripple near the line peak: 0.325 App.
- Port-power efficiency estimate: 92.82%, but this value is **not accepted as validated**. The ideal-loss comparison produced 100.38%, revealing about 0.38% numerical energy-balance error in the behavioral discretization/sample alignment.

### Input-voltage sweep

| Input | Vout mean | Ripple | PF | THD (2–40) | Mean duty near line peak | Status |
|---|---:|---:|---:|---:|---:|---|
| 20 Vac | 39.787 V | 1.639 Vpp | 0.9971 | 5.44% | 35.12% | Voltage/ripple/PF/THD pass |
| 24 Vac | 39.821 V | 1.615 Vpp | 0.9965 | 5.45% | 21.83% | Voltage/ripple/PF/THD pass |
| 28 Vac | 39.775 V | 1.640 Vpp | 0.9955 | 6.31% | 5.22% | Pass in this behavioral model; boost headroom is narrow |

At 28 Vac the steady minimum duty was about 3.20%, and mean duty near the line peak was about 5.22%. The case did not lose regulation, but its THD increased and the small duty/headroom make it a sensitive boundary case. It must be rechecked in a device-level model before being called robust.

### Load steps at 24 Vac

- 50% -> 100% (80 -> 40 ohm): minimum 36.178 V, maximum 40.590 V, final mean 39.800 V, final ripple 1.631 Vpp.
- 100% -> 50% (40 -> 80 ohm): minimum 38.686 V, maximum 42.848 V, final mean 40.087 V, final ripple 0.812 Vpp.
- No separate transient-deviation acceptance limit was specified; values are recorded without assigning pass/fail.

## Startup protection debugging

All versions and raw results below were preserved.

| Version | Change | Peak inductor current | Conclusion |
|---|---|---:|---|
| Baseline | No precharge | 33.92 A | Fail |
| Revision 1 | 10 ohm, bypass/PWM enable at 80 ms | 20.86 A | Fail |
| Revision 2 | 10 ohm, bypass/PWM enable at 200 ms | 20.09 A | Fail |
| Revision 3 | 10 ohm, 200 ms, load open during precharge | 6.875 A | Improved, but still above the 4.5 A reference limit |
| Revision 4 | Voltage qualified, load open during precharge | 7.873 A | Fail; 14.51% worse than Revision 3 |

Revision 3 changes only the load sequence. The precharge resistor, 200 ms release time, L/C, controller gains and 50 kHz PWM remain unchanged. Peak current fell by 65.77% relative to Revision 2 and by 79.73% relative to the no-precharge baseline. The cycle-average 2% settling time remained 0.760 s.

Immediately before load connection, the capacitor voltage was 29.511 V. The connection command occurred at a rectified-input zero crossing; at the following rectified peak (0.205 s), the rectified input was 32.541 V and the output was 29.520 V, a 3.022 V forward-driving difference. Current peaked at 6.875 A after connection. Thus delayed load connection is effective but does **not** prove the surge is fully limited.

The present completion condition is only a fixed 200 ms timer; there is no voltage-threshold or input/output-difference qualification. A later design step should evaluate a voltage-qualified bypass/load-enable condition or active current limiting. That is a recommendation only; no further startup change was made in this revision.

Steady operation did not materially regress versus Revision 2: output mean changed by +0.00009 V, ripple by +0.00057 Vpp, PF by -0.00000001, THD by +0.0047 percentage point and output power by +0.00037 W.

### Revision 4: voltage-qualified startup

Revision 4 is an independent work model; `BoostPFC_Design.slx` remains byte-identical to the archived Revision 3 baseline. The work model is `BoostPFC_Design_VoltageQualified.slx`.

The passive-precharge ceiling is derived from the actual modeled path:

`Vpre,max = sqrt(2)*Vac,rms - 2*Vf,bridge - Vf,boost = 31.891 V` at 24 Vac.

The qualification threshold is 90% of that ceiling, or 28.702 V. This represents 81% of the maximum passive-precharge energy while retaining 10% voltage headroom for passive-path drops and numerical/sampling margin. The signal must remain above threshold for 5 ms. Timeout is 0.500 s, equivalent to 25 line cycles and much longer than the 22 ms value of `10 ohm * 2200 uF`.

One latched `startup_enable` command synchronizes the precharge-resistor bypass, 40 ohm load connection and PWM release. State encoding is 0=precharging, 1=qualified/enabled and -1=timeout safe state.

Actual nominal result:

- Qualification occurred at 0.16949 s.
- AC phase at trigger: 170.82 degrees; rectified input: 4.0149 V.
- Output voltage at trigger: 28.8997 V; inductor current at trigger: 0.0085 A.
- At the next rectified peak (0.175 s), input was 32.5411 V and output was 29.4620 V, leaving a 3.0791 V forward-driving difference.
- Peak inductor current: 7.8732 A — fail against the 4.5 A reference limit.
- Cycle-average 2% settling time: 0.720 s.

The voltage-only criterion did not improve surge current. The 5 ms persistence interval caused release near an input zero crossing, so the following rectified crest reintroduced a voltage difference and a larger current pulse. This is a retained negative result; the threshold was not retuned to manufacture a pass.

Normal steady operation still passed the present targets: Vout 39.8554 V, error -0.3616%, ripple 1.5925 Vpp, PF 0.9965, THD 5.4786% and PWM 50.000 kHz. Against Revision 3, peak current increased 14.51%, while steady-state changes remained small.

Timeout behavior was separately verified with an intentionally unreachable 32.891 V threshold. At 0.500 s the state changed to -1; `startup_enable` and PWM remained zero, the load remained at 1 Gohm, and the bypass remained open. Timeout safety therefore passes.

Status after Revision 4:

- Passed: voltage regulation, output ripple, PF, THD, PWM operation, timeout safe state and clean-session execution.
- Failed: startup peak current limit (7.8732 A > 4.5 A).
- Not yet verified: active startup current limiting, phase/differential-voltage-qualified transfer and device-level surge stress.

## Reproducibility

`Verify_Clean_Session.m` restored the default MATLAB path, changed to the Windows temporary directory, loaded the model by full path and successfully ran it. The model `InitFcn` locates `BoostPFC_Design_Init.m` relative to its own saved filename.

## Main artifacts

- `BoostPFC_Design.slx`: current independent design model.
- `BoostPFC_Design_Init.m`: specification, component assumptions, controller gains and test defaults.
- `Run_BoostPFC_Design.m`: nominal run, metrics and waveform export.
- `Run_BoostPFC_Design_Cases.m`: input sweep and load-step automation.
- `BoostPFC_Design_LoopAnalysis.m`: averaged loop estimates and Bode plots.
- `results/`: MAT/JSON data and PNG figures.
- `Compare_Startup_Load_Enable.m`: recalculates all startup versions with one settling-time algorithm and exports the comparison.
- `BoostPFC_Design_VoltageQualified.slx`: independent Revision 4 work model.
- `BoostPFC_Design_VoltageQualified_Init.m`: derived threshold, debounce and timeout parameters.
- `Run_BoostPFC_VoltageQualified.m`: nominal run and structured measurement export.
- `Test_Precharge_Timeout.m`: unreachable-threshold safe-state verification.
- `Compare_Startup_VoltageQualified.m`: five-way startup comparison.
- `results/startup_load_enable_comparison.*`: structured startup comparison and plot.
- `results/voltage_qualified/`: Revision 4 raw data, metrics, waveforms and timeout evidence.
- `archive/`: preserved all four earlier baselines plus `voltage_qualified_90pct_5ms`.

## Revision 5: safe bypass and controlled soft start

This revision is implemented in the independent work model
`BoostPFC_Design_ControlledStartup.slx`. The original design model and all
earlier startup variants remain preserved. The power stage, L/C values, input
and output specifications, switching frequency and PI gains were not changed.

### Safe-bypass qualification

The passive ceiling remains 31.8911 V at 24 Vac. Bypass requires all of the
following for 0.2 ms: output at least 98% of that ceiling (31.2533 V),
rectified input at least 98% of its estimated peak (31.8903 V), absolute
input/output difference no more than 1.5 V, and inductor current no more than
0.25 A. Failure to qualify by 0.5 s leaves PWM and load disabled.

The stand-alone safe-bypass test qualified at 0.464701 s and 84.618 electrical
degrees. At the command, rectified input was 32.3915 V, output was 31.2560 V,
the difference was 1.1355 V and inductor current was 0.04387 A. Peak current
before bypass was 2.7818 A and after bypass was 0.7571 A. This stage therefore
passed its declared qualification checks.

### Controlled startup sequence

After bypass the sequence waits at least 1 ms and requires current below
0.10 A for 0.2 ms. PWM then starts, the output reference ramps from the actual
captured output voltage to 40 V, and the current-amplitude limit ramps from
0.5 A to the existing 4.5 A reference limit. The controller uses conditional
PI integration. A separate measured-current cycle limiter is 4.0 A and a
latched measured-current fault threshold is 4.5 A. These are not the same as
the 4.5 A reference-amplitude limit. The 40 ohm load connects only after the
output is within 0.4 V of target for 10 ms.

For every nominal ramp case, bypass occurred at 0.464701 s and PWM began at
0.466194 s. No timeout, cycle-limit event or overcurrent fault occurred.

| Ramp | Load connect | Full-cycle peak iL | Ramp peak iL | Vout overshoot | 2% settling | Steady Vout | Ripple | PF | THD |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 50 ms | 0.545199 s | 2.8115 A | 1.0676 A | 1.623% | 0.880 s | 39.8878 V | 1.5690 Vpp | 0.9965 | 5.4449% |
| 100 ms | 0.584349 s | 2.8057 A | 0.7719 A | 1.561% | 0.920 s | 39.8503 V | 1.5974 Vpp | 0.9965 | 5.4480% |
| 200 ms | 0.676196 s | 2.7818 A | 0.7719 A | 1.307% | 1.020 s | 39.7073 V | 1.6881 Vpp | 0.9964 | 5.5315% |

All three cases passed the current project targets for measured peak current
below the 4.5 A fault threshold, steady output regulation, output ripple, PF
and THD. Duty reached its existing 0.95 maximum during about 4.8--5.4% of the
PWM-enabled samples, but the runs remained stable. The 50 ms ramp is the
fastest of the tested choices; the 200 ms ramp has the lowest overshoot but the
longest settling time.

Load connection remains the main unresolved transient. During the first
100 ms after connection, output minimum was 34.1237, 34.0422 and 33.9130 V for
the 50, 100 and 200 ms ramps respectively. Return to the 2% band took 0.3217,
0.3234 and 0.3273 s. No dynamic-sag acceptance limit was specified, so these
values are recorded without manufacturing a pass/fail claim.

Protection logic was tested separately with diagnostic-only forced thresholds.
A forced 0.2 A cycle limit activated without a fault. A forced 0.2 A fault
threshold latched state -2; after the designed one-sample (1 us) feedback
delay, PWM, load and bypass commands were all zero. These forced tests are not
nominal performance results.

Clean-session verification passed from the Windows temporary directory after
`restoredefaultpath`: the 100 ms case reached state 4, had no fault and ended
at 39.8488 V. The model is therefore independent of manual path setup and
prior workspace contents.

Status after Revision 5:

- Passed: safe bypass qualification, nominal 50/100/200 ms startup runs,
  measured peak below 4.5 A, steady regulation/ripple/PF/THD, protection-path
  diagnostics and clean-session execution.
- Recorded but not graded: load-connect voltage sag and recovery, because no
  transient acceptance limit has been specified.
- Not yet verified: device-level switching stress, magnetic saturation,
  diode recovery, gate-driver delay and a hardware-realistic protection latch.
- Efficiency remains not accepted as validated because the earlier behavioral
  energy-balance check showed numerical error.

New artifacts include `Run_Controlled_Startup_Cases.m`,
`Test_Controlled_Startup_Protection.m`,
`Verify_Controlled_Startup_Clean_Session.m`,
`Compare_All_Startup_Strategies.m`, `results/controlled_startup/` and
`archive/controlled_startup_safe_bypass_ramps/`.

## Load-connection dynamic study (fixed 100 ms startup)

This study changes only the effective load connection after the existing
sequencer asserts its load-enable output. Safe bypass, the 100 ms output and
current-reference ramps, L/C values, input/output specification, current
limits and both PI controllers remain unchanged. The verified controlled
startup model is preserved; the work model is
`BoostPFC_Design_LoadConnection.slx`.

Three profiles were compared:

1. Direct connection to 40 ohm.
2. 160 ohm for 40 ms, 80 ohm for 40 ms, then 40 ohm.
3. A linear conductance ramp from effectively open circuit to 1/40 S over
   80 ms.

The 40 ms stage interval is about twice the 19.6 ms time scale associated
with the existing 8.13 Hz averaged voltage-loop crossover. The complete
80 ms transition is exactly four 50 Hz line cycles, so the staged and ramped
profiles reach full load at essentially the same AC phase at which they
started. This is a study choice, not a new project specification.

Candidate dynamic criteria were declared before comparison: instantaneous
minimum output at least 34 V and recovery of the 20 ms moving-average output
to 39.2--40.8 V within 0.35 s from the initial load-enable event. The 34 V
level is borrowed only as a conservative reference from the separate hold-up
requirement; it was not previously a load-step limit. The 0.35 s value is a
comparison criterion slightly above the measured direct-connect baseline,
not a formal product requirement.

All three profiles started at exactly 0.584349 s and 78.282 AC electrical
degrees. Immediately before load enable, output was 40.105296 V. At the event,
rectified input was 31.833760 V and inductor current was 0.022985 A. The
resulting comparison is:

| Profile | Full 40 ohm time | Minimum Vout | Recovery from initial enable | Recovery from full load | Full-run peak iL |
|---|---:|---:|---:|---:|---:|
| Direct 40 ohm | 0.584349 s | 34.0422 V | 0.323389 s | 0.323389 s | 2.8134 A |
| 160 -> 80 -> 40 ohm | 0.664350 s | 34.5923 V | 0.379346 s | 0.299345 s | 2.8244 A |
| 80 ms conductance ramp | 0.664349 s | 34.4259 V | 0.367662 s | 0.287662 s | 2.8107 A |

All profiles passed the 34 V candidate. Only direct connection passed the
0.35 s recovery candidate when timing begins at the common initial
load-enable event. If timing begins only after full 40 ohm load is reached,
the staged and ramped profiles recover faster, but that convention hides the
80 ms delivery interval; both time references are therefore retained.

The staged profile improved the minimum by 0.5502 V and the conductance ramp
by 0.3837 V relative to direct connection. They did not provide an
unambiguous overall improvement because total recovery from the initial
request increased by 55.96 ms and 44.27 ms respectively. Peak current changed
by less than 0.014 A, and no nominal case activated the cycle limiter or
overcurrent fault.

All steady targets remained satisfied in the 1.4 s comparison runs:

| Profile | Mean Vout | Ripple | PF | THD (2--40) |
|---|---:|---:|---:|---:|
| Direct 40 ohm | 39.9631 V | 1.5211 Vpp | 0.99653 | 5.4398% |
| 160 -> 80 -> 40 ohm | 39.9450 V | 1.5336 Vpp | 0.99652 | 5.4519% |
| 80 ms conductance ramp | 39.9495 V | 1.5312 Vpp | 0.99652 | 5.4429% |

The THD calculation remains harmonics 2--40 over the final 0.20 s and is not
an IEC compliance measurement. The 4.5 A threshold remains a behavioral
diagnostic fault threshold, not a validated hardware current protection.

Clean-session verification passed from the Windows temporary directory with
the default MATLAB path: final state 4, no fault and final 100 ms mean output
39.8503 V in the 1.2 s verification run.

Decision after this study: no profile is a clear overall winner under the
candidate criteria. Freeze the verified 100 ms direct-connect baseline rather
than continue load-profile tuning. If a formal application requirement later
prioritizes minimum voltage over total recovery time, the staged profile is a
documented alternative, but it is not selected here.

Evidence is in `results/load_connection_study/`; the independent archive is
`archive/load_connection_dynamic_study_100ms/`.

## Final controlled-startup input-range validation

The frozen baseline was tested at 20, 24 and 28 Vac: safe-bypass state
machine, 100 ms reference ramp, direct 40 ohm connection, PI gains, 470 uH,
2200 uF, 50 kHz PWM and all current/timing limits were unchanged. The only
independent input was `Vac_rms`. The safe rectified peak, passive-precharge
ceiling and 98% voltage thresholds were recalculated from the existing
formulas for each input voltage. The 98% factors, 1.5 V difference limit,
0.25 A bypass-current limit, 0.2 ms persistence and 0.5 s timeout were not
tuned.

### Startup and load-connection results

“Startup peak” below covers precharge through 100 ms after direct load
connection. “Full-run peak” also includes the later steady observation window.

| Input | Passive precharge peak iL | Bypass time / AC phase | Vrect / Vout / difference at bypass | iL at bypass | PWM start | Load connect | Startup peak iL | Full-run peak iL |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 20 Vac | 2.2904 A | 0.465091 s / 91.638 deg | 26.8727 / 25.7142 / 1.1585 V | 0.0521 A | 0.466291 s | 0.592110 s | 2.8673 A | 3.4209 A |
| 24 Vac | 2.7818 A | 0.464701 s / 84.618 deg | 32.3915 / 31.2560 / 1.1355 V | 0.0439 A | 0.466194 s | 0.584349 s | 2.7818 A | 2.8351 A |
| 28 Vac | 3.2731 A | 0.455508 s / 279.144 deg | 37.6948 / 36.8014 / 0.8934 V | 0.0330 A | 0.456708 s | 0.566710 s | 3.9677 A | 3.9677 A |

All bypass events satisfied the unchanged differential-voltage, current and
persistence conditions. Every case reached state 4 without precharge timeout,
startup timeout, cycle-limit event or overcurrent fault. The 28 Vac peak
occurred at 0.585479 s, 18.769 ms after load connection. It remained below
the 4.5 A behavioral fault threshold, but was only 0.0323 A below the 4.0 A
cycle-limit setting. This is small simulation margin and is not evidence of
hardware protection capability.

Load recovery uses the 20 ms moving-average output, searches after the
post-load minimum, then requires continuous residence in 39.2--40.8 V for
10 ms. These data have no formal pass/fail limit:

| Input | Vout before load | Instantaneous minimum | Recovery delay |
|---:|---:|---:|---:|
| 20 Vac | 40.3366 V | 33.6644 V | 0.360489 s |
| 24 Vac | 40.1053 V | 34.0422 V | 0.323389 s |
| 28 Vac | 39.9150 V | 35.4249 V | 0.330622 s |

### Final steady results

Output mean/ripple use the final 0.10 s. PF, THD, current and duty statistics
use the final 0.20 s, exactly ten 50 Hz line cycles. THD includes harmonics
2--40 (through 2 kHz) and is not an IEC compliance test.

| Input | Mean Vout | Error | Ripple | PF | THD | Steady iL / input-current peak | Duty range | Mean duty near rectified peak |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 20 Vac | 39.9829 V | -0.0427% | 1.5213 Vpp | 0.99714 | 5.3722% | 3.4107 A | 0.2874--0.9500 | 0.36385 |
| 24 Vac | 39.9910 V | -0.0225% | 1.5035 Vpp | 0.99652 | 5.4714% | 2.8351 A | 0.1832--0.9500 | 0.22282 |
| 28 Vac | 39.9920 V | -0.0201% | 1.4910 Vpp | 0.99558 | 6.2925% | 2.3826 A | 0.0322--0.9500 | 0.05369 |

All three cases pass the formal regulation, ripple, PF and THD targets in the
behavioral model.

### 28 Vac boundary interpretation

- Measured rectified peak was 38.1980 V, leaving only 1.7940 V between that
  peak and the steady mean output.
- Minimum steady duty was 3.221%; mean duty for samples above 98% of the
  rectified peak was 5.369%. No sample fell below 2% duty. Duty was below 5%
  for 5.364% of all steady samples and 36.54% of near-peak samples.
- The duty-saturation flag was active for 4.752% of the steady window, but
  these were upper-limit (0.95) samples at line zero crossing. No upper-limit
  sample occurred near the line peak, and no near-peak sample showed zero
  duty with a nonzero current reference.
- THD increased by 0.821 percentage point from 24 to 28 Vac. The third
  harmonic rose from 4.870% to 5.954% of the fundamental. With “peak region”
  defined as |Vac| >=90% of its peak, normalized residual RMS decreased
  slightly in that region and increased outside it. Therefore the additional
  distortion is not attributed to a narrow line-peak loss-of-control interval;
  it is a broader third-harmonic waveform-shape change.
- The bypass criterion remained internally consistent: at bypass, output was
  4.4 mV above its derived threshold, rectified input was 0.261 V above its
  threshold, the differential limit retained 0.607 V margin and the current
  criterion retained 0.217 A margin.
- Load sag was smaller than at 24 Vac, and recovery was 7.23 ms longer. The
  main boundary concern is the 3.9677 A post-load transient close to the 4.0 A
  behavioral cycle limit, not loss of final voltage regulation.

Clean-session boundary reruns passed from the Windows temporary directory
after `restoredefaultpath`: 20 Vac reached state 4 with final 100 ms mean
39.9382 V, and 28 Vac reached state 4 with 39.9698 V; neither faulted.

Status:

- Passed: 20/24/28 Vac state-machine completion and the four formal steady
  targets in the switched behavioral model.
- Recorded without a formal acceptance limit: load minimum and recovery time.
- Warning, not a formal failure: 28 Vac startup/load peak is very close to the
  behavioral 4.0 A cycle-limit setting.
- Not verified: device-level commutation/headroom, MOSFET/diode stress,
  magnetic saturation, hardware protection behavior and IEC-compliant THD.

Evidence is in `results/final_input_range/`; the self-contained archive is
`archive/final_input_range_20_24_28Vac_100ms_direct/`.

## Original 10 ms / 34 V hold-up specification verification

The frozen final model has an autonomous Sine Wave source, so an independent
test copy `BoostPFC_Design_HoldUpTest.slx` was created. The only model change
is a 1-to-0 gate between the AC source and bridge rectifier. The logged AC
voltage, bridge input, polarity reconstruction and input-current measurement
all use the gated signal. PI gains, L/C, startup timing, current limits, state
machine and direct 40 ohm load are unchanged.

Hold time starts at the first sample at/after the gate falling edge for which
both gated Vac and Vrect remain zero for 1 ms. It does not start at an
arbitrary script timestamp. Both tests waited until state 4 and used the
continuous 40 ohm load.

### Analytical check

Using the original constant-power specification:

`Cmin = 2*P*t/(V1^2-V2^2)`

with 40 W, 10 ms, 40 V and 34 V gives:

- Minimum capacitance: 1.801802 mF = 1801.8 uF.
- Installed capacitance: 2.200 mF, 398.2 uF above the minimum or 22.1% margin.
- Ideal constant-40-W discharge time for 2200 uF: 12.210 ms.

The simulated load is a constant 40 ohm resistor, not a constant-power load.
Its ideal capacitor-only discharge time is
`R*C*ln(40/34) = 14.3017 ms`, because output power decreases as voltage falls.

### Actual dropout results

| Drop phase | Actual input-zero event | 20 ms pre-drop mean | Instantaneous Vout at loss | iL / stored L energy at loss | Vout at +10 ms | First 34 V | Formal result |
|---|---:|---:|---:|---:|---:|---:|---|
| AC zero crossing | 1.200000 s / 0.000 deg | 39.8894 V | 39.8488 V | 0 A / 0 J | 35.5683 V | 13.969 ms | Pass |
| AC positive peak | 1.205001 s / 90.018 deg | 39.8932 V | 39.9828 V | 2.5593 A / 1.539 mJ | 35.7036 V | 14.303 ms | Pass |

In both cases Vac and Vrect remained exactly zero after the measured event and
the load remained 40 ohm. Pre-drop mean output power was 39.786 W and
39.794 W. At +10 ms, resistive-load power had fallen to 31.628 W and
31.869 W respectively.

The zero-crossing simulation agrees with the resistor/capacitor theory using
the actual instantaneous 39.8488 V start: 13.9690 ms simulated versus
13.9684 ms theoretical. At the peak, the same calculation gives 14.2637 ms,
while simulation gives 14.3030 ms. The additional 0.0393 ms is consistent
with residual inductor energy transferring through the boost diode plus the
1 us discrete integration/threshold sampling.

Both simulations exceed the 12.210 ms ideal constant-40-W result because the
behavioral model's 40 ohm load is not constant power. The phase-to-phase
difference also includes different instantaneous capacitor voltages: the
20 ms averages are nearly equal, but Vout at the actual cut differs by
0.1339 V. The peak case additionally has 1.539 mJ in the inductor.

Formal status: **pass**. Vout at 10 ms was above 34 V in both representative
input phases.

Model limitations remain important: capacitor ESR/ESL is not modeled, so
there is no instantaneous terminal-voltage step at dropout; component
tolerances and hardware losses are not included. The result verifies the
specified behavior of the current software model, not physical hold-up
compliance of a built converter.

Evidence is in `results/hold_up_test/`; the independent archive is
`archive/hold_up_24Vac_40ohm_zero_and_peak/`.

## Control-loop stability audit of the frozen final model

The original `BoostPFC_Design_LoopAnalysis.m` was audited before adding any
new calculation. It computes only two 24 Vac continuous-time ideal estimates:

- current open loop: `(Kp_i + Ki_i/s) * Vout/(L*s)`;
- voltage open loop: `(Kp_v + Ki_v/s) * Vac/(sqrt(2)*C*Vout*s)`.

It does not include the 40 ohm load pole, conduction resistance, the closed
current loop inside the voltage loop, PWM/sampling delay, duty/current limits,
conditional-integration anti-windup, or the 20/28 Vac operating points. Its
previous results (3.0403 kHz / 80.6609 deg current loop and 8.1349 Hz /
79.5525 deg voltage loop) are therefore early ideal design estimates rather
than final switched-model or hardware stability verification. Neither ideal
loop has a finite -180 degree phase crossover, so its gain margin is infinite
in that mathematical model, not a measured robustness limit.

`BoostPFC_Design_LoopAudit.m` is an independent analytical audit; it does not
edit or simulate the frozen model. The controller implementation was read
from `BoostPFC_Design_ControlledStartup.slx` and confirmed as:

- voltage PI: Kp = 0.260649132372, Ki = 2.45656019827 1/s;
- current PI: Kp = 0.221482282078, Ki = 695.807110277 1/s;
- current-amplitude reference limit: 4.5 A;
- duty range: 0 to 0.95;
- behavioral measured-current actions: PWM suppression at 4.0 A and fault
  latch at 4.5 A;
- conditional-integration anti-windup in both PI loops;
- controller function step 1 us and PWM frequency 50 kHz.

The working-point-aware current plant is the line-peak CCM approximation
`Gid(s)=Vout/(L*s+rL+Dpeak*Rds_on)` with unity iL feedback. The voltage plant
comes from line-cycle capacitor energy balance with the actual 40 ohm load:
`Gvi(s)=(Vac/sqrt(2))/(C*Vout*s+2*Vout/R)`. The voltage open loop includes the
closed current-loop transfer. Measured Vout and near-peak duty from the frozen
20/24/28 Vac results define each operating point.

| Input | Current crossover / PM | Current GM | Voltage crossover / PM | Voltage GM | fsw/fci | fci/fcv |
|---:|---:|---|---:|---|---:|---:|
| 20 Vac | 3038.793 Hz / 81.388 deg | Inf, no finite phase crossing | 5.858 Hz / 107.323 deg | Inf, no finite phase crossing | 16.45 | 518.7 |
| 24 Vac | 3039.415 Hz / 81.353 deg | Inf, no finite phase crossing | 7.324 Hz / 104.700 deg | Inf, no finite phase crossing | 16.45 | 415.0 |
| 28 Vac | 3039.513 Hz / 81.311 deg | Inf, no finite phase crossing | 8.754 Hz / 102.716 deg | Inf, no finite phase crossing | 16.45 | 347.2 |

All closed-loop poles are in the open left half-plane for these unsaturated
continuous averaged linear models. The current-to-voltage crossover separation
is strong. Current crossover is about `f_sw/16.45`, below `f_sw/10`, but PWM
delay is still material.

Because the actual effective PWM/modulation delay has not been identified, a
0.5/1.0/1.5 switching-period phase-delay sensitivity was calculated at 24 Vac
rather than claimed as an exact discrete model:

| Assumed delay | Current-loop PM | Approximate GM / phase crossing |
|---:|---:|---:|
| 0.5 Tsw | 70.412 deg | 18.312 dB / 24.702 kHz |
| 1.0 Tsw | 59.470 deg | 12.178 dB / 12.198 kHz |
| 1.5 Tsw | 48.528 deg | 8.535 dB / 8.028 kHz |

The finite delayed gain margins are sensitivity estimates only. Phase
crossings approaching the 25 kHz Nyquist region are outside a trustworthy
continuous averaged-model range.

At 28 Vac the linear margins remain acceptable around the selected line-peak
operating point, but this does not remove the existing headroom warning. The
measured boost headroom is only 1.7940 V, minimum duty is 3.221%, and mean
near-peak duty is 5.369%. A negative perturbation can therefore hit zero duty,
where this unsaturated Bode model no longer applies. The 20/24/28 Vac switched
steady results support regulation, but do not supply injected loop gain.

Status:

- Passed only within the stated continuous averaged, unsaturated models:
  left-half-plane closed-loop poles and positive phase margins at all three
  working points.
- Not available as a finite continuous-model number: gain margin, because no
  finite -180 degree phase crossing exists.
- Sensitivity estimate, not validation: 0.5--1.5 Tsw delay results.
- Not verified: exact sampled-data/PWM model, switched-model loop injection,
  saturated/line-zero stability, subharmonic behavior, sensing/computation
  delay, device parasitics and hardware loop gain.

Evidence is in `results/loop_audit/`; the reproducible archive is
`archive/control_loop_stability_audit/`. The frozen models were not changed.

