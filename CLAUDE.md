# CLAUDE.md

## 分支与推送规则
main分支用来保存7轴版本， refactor/6-axis分支用来保存6轴版本。不要混淆
不要合并我的任何分支到主分支，除非我明确告诉你这样做。
不要推送到 remote，除非我明确告诉你这样做。

## 项目概述

这是一个基于 MATLAB Robotics System Toolbox 的六自由度机械臂运动学仿真与轨迹规划项目。

关节布局：腰 → 肩 → 肘 → 前臂横滚 → 腕 → 工具（Z-Y-Y-Z-Y-Z 构型）。

## 运行环境

- **MATLAB R2020b+**
- **Robotics System Toolbox**

## 文件结构

| 文件 | 用途 |
|------|------|
| `build_6axis_arm.m` | 机械臂刚体树模型定义 |
| `robot_arm_gui.m` | **主程序** — 探索（FK/IK 滑块）+ 轨迹规划合一界面 |
| `interactive_robot_gui.m` | FK/IK 滑块交互（已合并入主程序） |
| `trajectory_planner_gui.m` | 轨迹规划独立版（已合并入主程序） |
| `demo_simulation.m` | pick-and-place 动画演示脚本 |
| `run_tests.m` | 模型 / FK / IK / 雅可比 / 碰撞 / 轨迹测试 |

## 常用命令

```matlab
robot_arm_gui      % 启动主界面
demo_simulation    % 运行 pick-and-place 演示
run_tests          % 运行基础测试
```
