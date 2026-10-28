# 40 W CCM Boost PFC — 设计、仿真与 RevB PCB

面向电源研发岗位展示的学习与工程设计项目。规格：20–28 Vac / 50 Hz 输入，40 V / 1 A / 40 W 输出，50 kHz CCM Boost PFC，平均电流模式双闭环控制。

## 当前状态（2026-10-28）

- 已完成自主行为级 Simulink 模型、组合启动方案、20/24/28 Vac 输入范围及掉电保持时间仿真。
- 已完成 KiCad 原理图及 RevB PCB 的人工器件摆放、手工布线、PGND/AGND 分区覆铜；用户本人完成器件摆放与手工布线，工具用于辅助检查和整理。
- 最新 RevB 静态检查：0 Error、0 Unconnected；34 项 PCB Warning 中 33 项为丝印问题，1 项为已排除检查的 `/RECT_IN` 悬空过孔。H1–H4 是预期的 PCB 专用机械安装孔。详见 [PCB 状态](hardware/REVB_STATUS.md)。
- 制造文件仅作为预览和本地检查材料；尚未完成厂家审图、裸板下单、焊接、上电或实物性能测试。**不要将本仓库作为可直接生产或安全上电的硬件放行包。**

## 仓库内容

| 目录 | 内容 |
|---|---|
| [`hardware/revb/`](hardware/revb/) | 当前 RevB KiCad 工程、项目本地符号与封装库 |
| [`simulation/BoostPFC_Design/`](simulation/BoostPFC_Design/) | 自主行为级模型、MATLAB 脚本、结构化结果和波形图 |
| [`docs/`](docs/) | 求职快速展示 PDF、项目文档及关键图 |

## 结果边界

仿真指标仅是 **Simulink 行为模型结果**，不代表硬件实测。KiCad ERC/DRC 与本地 CAM 是静态设计/制造检查，不证明效率、功率因数、谐波、温升、开关过冲或 EMI 的硬件表现。原始 `.mat` 波形数据在本地约 887 MB，未纳入本公开仓库；仓库保留测量 JSON、波形图、模型和复现脚本。

## 来源与署名

本项目早期学习参考了 [DeepooBelief/BoostPFC](https://github.com/DeepooBelief/BoostPFC)。本仓库中的 40 W 自主设计、后续控制/启动仿真与 RevB KiCad 工程作为独立作品展示；不声称早期参考工程由本人从零设计。原仓库代码、第三方器件数据手册、厂商模型及其他项目未复制进本仓库。详见 [来源说明](ATTRIBUTION.md)。

## 工程注意事项

在 KiCad 中打开 `hardware/revb/BoostPFC_40W_RevB_ManualLayout.kicad_pro`。运行前先核对本地符号、封装映射及原理图网络。当前项目尚处于制造前审查阶段，不应凭 DRC 结果直接制作或上电。
