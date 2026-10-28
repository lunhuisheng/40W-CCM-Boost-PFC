# RevB PCB 静态审查状态

来源文件：`revb/BoostPFC_40W_RevB_ManualLayout.kicad_pcb`。原始工程本地 SHA-256：`2BB23CBACD7A38E5F8491438F23DFACB0250224D6A2BCA3105C27D4691244414`。

截至 2026-10-27：83 个封装、557 段走线、81 个过孔、2 个 B.Cu 地区、73 个网络；KiCad 10.0.7 完整 DRC 0 Error、0 Unconnected、34 Warning。原理图一致性另有 H1–H4 四个 PCB-only 安装孔警告。

- D1 的两个物理阳极焊盘 D1.1/D1.2 连接 `/SW`，阴极大焊盘 D1.3 连接 `/VOUT`。
- R2 四端分流器的功率端为 `/PGND`、`/BRIDGE_NEG`，Kelvin 端为 `/ISENSE_P`、`/ISENSE_N`。
- AGND/PGND 的静态几何和网络检查表明只经 NT1 单点相连；真实噪声与电流/温升性能尚待实物验证。
- 34 项警告中 18 项是丝印压铜，15 项是丝印重叠，1 项是已排除检查的 `/RECT_IN` 悬空过孔（42.8, 42.2 mm）。制造前需逐项处理或明确接受。

这些结论是静态设计审查结果。尚未通过厂家审图，也没有裸板、焊接或上电实测。此 RevB 工程不是最终制造放行版本。
