# Control-loop stability audit

Generated: 2026-10-25 12:05:07 Asia/Shanghai

This is an analytical continuous-averaged baseline. It does **not** claim sampled-data, device-level, or hardware stability. The frozen Simulink model and all controller values were left unchanged.

## Controller values verified from the frozen model

| Item | Value |
|---|---:|
| Voltage PI Kp | 0.260649132372 |
| Voltage PI Ki | 2.45656019827 1/s |
| Current PI Kp | 0.221482282078 |
| Current PI Ki | 695.807110277 1/s |
| Current-amplitude reference limit | 4.500 A |
| Duty range | 0.000 to 0.950 |
| Behavioral cycle limiter | 4.000 A |
| Behavioral fault latch | 4.500 A |
| Controller execution step | 1e-06 s |
| PWM frequency | 50000 Hz |

Anti-windup: conditional integration in both PI loops when the limited output would be driven farther into saturation.

## Plants, feedback paths and method

- Current loop: Unity feedback of measured iL.  Around the line peak, Gid(s)=Vout/(L*s+rL+Dpeak*Rds_on).  The feed-forward duty term is constant for the local iRef-to-iL perturbation.
- Voltage loop: Unity feedback of Vout.  vLoop commands sinusoidal peak current through iRef=vLoop*vrect/Vpeak.  Line-cycle energy linearization gives Gvi(s)=(Vac/sqrt(2))/(C*Vout*s+2*Vout/R). The outer open loop also includes the closed current loop Ti(s).
- Continuous margins: MATLAB margin(): phase margin at the 0 dB gain crossover and gain margin at a finite -180 degree phase crossover.
- Stability test: All poles of feedback(open_loop,1) must have strictly negative real part.
- Delay sensitivity: Frequency response multiplied by exp(-j*w*Tdelay); crossings found by logarithmic-frequency interpolation.

The gains come from `BoostPFC_Design_Init.m`: the current PI was sized for a 3 kHz crossover and 500 Hz zero using Vout/(L*s); the voltage PI was sized for an 8 Hz crossover and 1.5 Hz zero at 24 Vac using Vac/(sqrt(2)*C*Vout*s). They were not retuned in this audit.

## What the original loop script calculated

24 Vac ideal continuous averaged PI-times-integrator; no load pole, losses, delay, limits or inner-loop closure in outer loop.

| Loop | Crossover | Phase margin | Gain margin |
|---|---:|---:|---|
| Current | 3040.299 Hz | 80.661 deg | Inf (no finite phase crossing) |
| Voltage | 8.135 Hz | 79.552 deg | Inf (no finite phase crossing) |

## Working-point-aware continuous averaged audit

Continuous CCM line-peak current plant with averaged conduction resistance; line-cycle averaged voltage plant with 40-ohm load damping and closed inner loop.

| Input | Current fc | Current PM | Current GM | Voltage fc | Voltage PM | Voltage GM | fsw/fci | fci/fcv |
|---:|---:|---:|---|---:|---:|---|---:|---:|
| 20 Vac | 3038.793 Hz | 81.388 deg | Inf (no finite phase crossing) | 5.858 Hz | 107.323 deg | Inf (no finite phase crossing) | 16.45 | 518.7 |
| 24 Vac | 3039.415 Hz | 81.353 deg | Inf (no finite phase crossing) | 7.324 Hz | 104.700 deg | Inf (no finite phase crossing) | 16.45 | 415.0 |
| 28 Vac | 3039.513 Hz | 81.311 deg | Inf (no finite phase crossing) | 8.754 Hz | 102.716 deg | Inf (no finite phase crossing) | 16.45 | 347.2 |

All listed closed-loop poles are in the open left half-plane for these linear models. That conclusion applies only around the stated unsaturated working points.

## 24 Vac current-loop delay sensitivity

| Assumed delay | PM | GM | Phase crossing | Below 25 kHz Nyquist? |
|---:|---:|---:|---:|---|
| 0.5 Tsw | 70.412 deg | 18.312 dB | 24701.652 Hz | true |
| 1.0 Tsw | 59.470 deg | 12.178 dB | 12198.053 Hz | true |
| 1.5 Tsw | 48.528 deg | 8.535 dB | 8027.704 Hz | true |

The delay range is an explicit sensitivity assumption. The actual effective modulator delay has not been identified, so these finite gain margins are not accepted as measured margins.

## Limits of applicability

- Current-loop linearization is at the rectified-line peak. Line zero crossings and discontinuous/saturated intervals are not covered.
- The outer model assumes the inner current loop follows a sinusoidal amplitude command and averages energy over a complete line cycle.
- At 28 Vac the measured mean near-peak duty and minimum duty are small; downward control authority is limited and large perturbations can hit zero duty.
- The current crossover is about 3.04 kHz, or f_sw/f_ci about 16.45. It is below f_sw/10, but the delay sensitivity shows that switching and modulation delay still materially reduce phase margin.
- The current/voltage crossover separation is 347 to 519, so the cascade bandwidth hierarchy is strong in these averaged models.
- Conditional-integration anti-windup and current protection are nonlinear and therefore absent from the unsaturated Bode model.
- Device parasitics, sensing filters and delays, magnetic saturation and digital implementation effects are absent.

## Not yet verified

- Frequency-response injection into the frozen switched behavioral model
- Exact sampled-data/PWM small-signal model and effective actuation delay
- Linearization during duty saturation, cycle current limiting or fault latch
- Line-zero-crossing time-periodic stability and subharmonic behavior
- Device parasitics, current-sense/filter delay, computation delay and hardware loop gain
