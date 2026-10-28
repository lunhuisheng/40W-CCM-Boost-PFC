# 项目证据索引与待核实项（2026-10-27）

## 当前权威源文件

| 对象 | 路径/哈希 | 可证明的事实 |
|---|---|---|
| 当前 RevB PCB | [PCB](../../hardware/BoostPFC_40W_KiCad/pcb_revB_manual_layout_modular/BoostPFC_40W_RevB_ManualLayout.kicad_pcb)；SHA-256 `2BB23CBACD7A38E5F8491438F23DFACB0250224D6A2BCA3105C27D4691244414` | 83 封装、557 走线、81 过孔、2 zone、73 net |
| 当前 RevB 原理图 | [SCH](../../hardware/BoostPFC_40W_KiCad/pcb_revB_manual_layout_modular/BoostPFC_40W_RevB_ManualLayout.kicad_sch)；SHA-256 `2C48EE15A7AB56400A25E550534BDA38973D15C336F68315AF6E2D29CF0975B0` | 当前 KiCad 电气定义，含 U1 C42–C48 |
| 工程规则 | 同目录 `.kicad_pro`；SHA-256 `C0FD3749F61E2074AE71FF0E2F1B34CB35B4C61E5B0AA9E16F726896EB9365D6` | Net Class 与 DRC 设置 |
| 覆铜终审 | [报告及原始 DRC/几何数据](../../hardware/BoostPFC_40W_KiCad/revb_ground_final_review_2026-10-27/REVB_GROUND_POUR_FINAL_REVIEW.md) | DRC 0 Error、34 Warning、0 未连接、4 预期机械孔 parity Warning；NT1 静态 PASS、Kelvin CONDITIONAL |
| 输入范围仿真 | [最终 JSON](../../simulation/simulink/BoostPFC_Design/results/final_input_range/final_input_range_summary.json) | 20/24/28 Vac 行为模型电压、PF、THD、纹波 |
| 掉电保持 | [JSON](../../simulation/simulink/BoostPFC_Design/results/hold_up_test/hold_up_summary.json) | 24 Vac 两相位输入真正归零后 10 ms Vout |
| D1 修复 | [D1_FIX_REPORT](../../hardware/BoostPFC_40W_KiCad/pcb_revA_2026-10-26_d1fix/D1_FIX_REPORT.md) | 旧 RevA D1 阳极/阴极映射纠正，RevB 继承三端定义 |
| MCU 去耦 | [U1_DECOUPLING_REVISION_REPORT](../../hardware/BoostPFC_40W_KiCad/u1_decoupling_revision_2026-10-27/U1_DECOUPLING_REVISION_REPORT.md) | C42–C48 增加及引脚映射 |
| 网络规则 | [REVB_NETCLASS_RULES_REPORT](../../hardware/BoostPFC_40W_KiCad/revb_netclass_rules_2026-10-27/REVB_NETCLASS_RULES_REPORT.md) | 线宽、间距与过孔预设 |

## 图片和推断边界

`figures/18`～`30` 均由上述 RevB PCB 或当前 RevB 原理图经 KiCad 10.0.7 导出并裁剪，属于**当前设计图**；01～07 为先前仿真结果图，09 为**历史 RevA** CAM，不能当 RevB 制造图。用户附的两张聊天图片仅是课堂目标/概念结构参考，未用作本次电气或仿真证据；其中 PF≥0.98 等不能覆盖项目原有的 PF≥0.95 验收口径。

尚未取得：RevB 最新制造文件及 CAM、厂家审图/报价与订单、裸板、固件、焊接和任何实物电气测试。警告与分割地面详见终审，不得将 CONDITIONAL GO 改写成直接打板批准。
