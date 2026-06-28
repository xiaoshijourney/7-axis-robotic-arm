# 7-Axis Robotic Arm

基于 MATLAB Robotics System Toolbox 的七自由度机械臂运动学与轨迹规划仿真。

## 文件说明

| 文件 | 用途 |
|------|------|
| `build_7axis_arm.m` | 机械臂模型构建（刚体树 + 可视化几何体） |
| `robot_arm_gui.m` | **主程序** — 集成运动学探索 + 轨迹规划的 GUI 界面 |
| `demo_simulation.m` | pick-and-place 演示脚本（8 个路径点，梯形速度轨迹动画） |
| `interactive_robot_gui.m` | FK/IK 交互探索界面（滑块控制关节或末端位姿） |
| `trajectory_planner_gui.m` | 轨迹规划界面（路径点编辑 + 多种轨迹方法 + 动画播放） |
| `run_tests.m` | 基础测试（模型结构、FK、IK、雅可比、自碰撞、轨迹） |

> `robot_arm_gui.m` 是 `interactive_robot_gui.m` 和 `trajectory_planner_gui.m` 的合并版本，推荐使用。

## 运行

```matlab
% 主界面（推荐）
robot_arm_gui

% 或单独运行演示脚本
demo_simulation

% 或运行测试
run_tests
```

需要 **MATLAB R2020b+** 和 **Robotics System Toolbox**。

## 机械臂参数

- 自由度：7（全旋转关节）
- 总伸展：约 0.87 m
- 关节布局：Z-Y-Z-Y-Z-Y-Z（参考 LBR iiwa 的轴线方案）
- 关节范围：±120° ~ ±175°

## 支持的轨迹方法

- `trapveltraj` — 梯形速度剖面
- `cubicpolytraj` — 三次多项式
- `quinticpolytraj` — 五次多项式
- `bsplinepolytraj` — B 样条

## 截图

运行 `robot_arm_gui` 后，左侧为 3D 机械臂视图，右侧可在"Explore"（关节/位姿滑块探索）和"Plan"（路径点编辑 + 轨迹生成）两个标签页之间切换。
