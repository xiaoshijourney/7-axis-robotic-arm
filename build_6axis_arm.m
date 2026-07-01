function robot = build_6axis_arm()
% 构建一个6自由度机械臂的刚体树模型
%
%   robot = build_6axis_arm() 返回一个带6个旋转关节、
%   一个固定底座和一个固定末端法兰的 rigidBodyTree。
%   每个连杆都带有长方体/圆柱体可视化几何体，用于3D渲染。
%
%   从7轴版本精简而来，原冗余自由度 J3（大臂横滚）被移除。
%   坐标变换沿用原7轴交替 Rz2y/Ry2z 模式。
%
%   关节布局（零位：机械臂竖直向上沿 +Z）：
%     J1 — 底座旋转（腰），绕 Z 轴
%     J2 — 肩部俯仰，绕 Y 轴
%     J3 — 肘部俯仰，绕 Y 轴
%     J4 — 小臂横滚，绕 Z 轴
%     J5 — 腕部俯仰，绕 Y 轴
%     J6 — 末端横滚，绕 Z 轴
%
%   最大伸展距离 ≈ 0.87 m

    robot = rigidBodyTree('DataFormat', 'row', 'MaxNumBodies', 10);

    % 两个常用的旋转变换，用于在相邻关节之间切换坐标轴方向
    % R_x(-90°) 和 R_x(+90°) 成对使用，相邻两对互相抵消
    Rz2y = axang2rotm([1 0 0 -pi/2]);   % Z 轴转 Y 轴
    Ry2z = axang2rotm([1 0 0  pi/2]);   % Y 轴转 Z 轴

    % ── 各段尺寸（单位：米） ──
    baseH = 0.12;    % 底座高度
    baseR = 0.10;    % 底座半径
    L0 = 0.05;       % J1 到 J2 的偏距
    L1 = 0.28;       % 大臂长度（J2 到 J3，原7轴 J2→J4 合并了中间偏距）
    L2 = 0.04;       % J3 到 J4 的偏距（原7轴 J3-J4 距离，合并入大臂总长）
    L3 = 0.22;       % 小臂长度（J4 到 J5）
    L4 = 0.04;       % J5 到 J6 的偏距
    L5 = 0.06;       % 腕部长度（J6 到末端法兰）
    L6 = 0.06;       % 末端法兰偏距
    jR  = 0.040;     % 关节外壳半径
    jH  = 0.035;     % 关节外壳高度
    bW  = 0.060;     % 连杆方盒宽度（大臂）
    bW2 = 0.050;     % 连杆方盒宽度（中段）
    bW3 = 0.040;     % 连杆方盒宽度（腕部）

    % ═══════════════════════════════════════════════════
    %  底座（固定，连接到机器人根节点 'base'）
    % ═══════════════════════════════════════════════════
    pedestal = rigidBody('pedestal');
    pedestal.Joint = rigidBodyJoint('pedestal_joint', 'fixed');
    % 底座圆柱 + 底板
    addVisual(pedestal, 'Cylinder', [baseR baseH], trvec2tform([0 0 baseH/2]));
    addVisual(pedestal, 'Box', [0.24 0.24 0.02], trvec2tform([0 0 0.01]));
    addBody(robot, pedestal, robot.BaseName);

    % ═══════════════════════════════════════════════════
    %  连杆1：J1 — 腰部旋转，绕 Z 轴
    %  零位时：连杆坐标系 = 世界坐标系（z = baseH）
    %  连杆沿自身 +Z 方向从 J1 延伸到 J2
    % ═══════════════════════════════════════════════════
    body1 = rigidBody('link1');
    j1 = rigidBodyJoint('jnt1', 'revolute');
    j1.PositionLimits = deg2rad([-170 170]);
    j1.HomePosition = 0;
    j1.setFixedTransform(trvec2tform([0 0 baseH]));
    body1.Joint = j1;
    addVisual(body1, 'Cylinder', [jR jH], trvec2tform([0 0 jH/2]));
    addVisual(body1, 'Box', [bW bW L0], trvec2tform([0 0 L0/2]));
    addBody(robot, body1, 'pedestal');

    % ═══════════════════════════════════════════════════
    %  连杆2：J2 — 肩部俯仰，绕 Y 轴
    %  固定变换：沿 Z 平移 L0，再绕 X 转 -90°
    %  零位时：本体系 Z = 父系 Y = 世界 Y，本体系 Y = 世界 -Z
    %  连杆沿本体系 -Y（= 世界 Z）从 J2 延伸到 J3（合并原 J3 长度）
    % ═══════════════════════════════════════════════════
    body2 = rigidBody('link2');
    j2 = rigidBodyJoint('jnt2', 'revolute');
    j2.PositionLimits = deg2rad([-120 120]);
    j2.HomePosition = 0;
    j2.setFixedTransform(trvec2tform([0 0 L0]) * rotm2tform(Rz2y));
    body2.Joint = j2;
    addVisual(body2, 'Cylinder', [jR jH], trvec2tform([0 0 jH/2]));
    addVisual(body2, 'Box', [bW (L1+L2) bW], trvec2tform([0 -(L1+L2)/2 0]));
    addBody(robot, body2, 'link1');

    % ═══════════════════════════════════════════════════
    %  连杆3：J3 — 肘部俯仰，绕 Y 轴（原7轴的 J4）
    %  固定变换：沿 Y 平移 -(L1+L2)，不旋转（继承 J2 的 Rz2y 姿态）
    %  零位时：本体系 = J2 本体系（Z=世界 Y，Y=世界 -Z）
    %  连杆沿本体系 -Y（= 世界 +Z）延伸 —— 小臂
    % ═══════════════════════════════════════════════════
    body3 = rigidBody('link3');
    j3 = rigidBodyJoint('jnt3', 'revolute');
    j3.PositionLimits = deg2rad([-120 120]);
    j3.HomePosition = 0;
    j3.setFixedTransform(trvec2tform([0 -(L1+L2) 0]));
    body3.Joint = j3;
    addVisual(body3, 'Cylinder', [jR*0.85 jH*0.85], trvec2tform([0 0 jH/2]));
    addVisual(body3, 'Box', [bW2 L3 bW2], trvec2tform([0 -L3/2 0]));
    addBody(robot, body3, 'link2');

    % ═══════════════════════════════════════════════════
    %  连杆4：J4 — 小臂横滚，绕 Z 轴（沿小臂方向，原7轴的 J5）
    %  固定变换：沿 Y 平移 -L3，再绕 X 转 +90°（抵消 J2/J3 的 Rz2y）
    %  零位时：本体系 = 世界坐标系
    % ═══════════════════════════════════════════════════
    body4 = rigidBody('link4');
    j4 = rigidBodyJoint('jnt4', 'revolute');
    j4.PositionLimits = deg2rad([-170 170]);
    j4.HomePosition = 0;
    j4.setFixedTransform(trvec2tform([0 -L3 0]) * rotm2tform(Ry2z));
    body4.Joint = j4;
    addVisual(body4, 'Cylinder', [jR*0.75 jH*0.75], trvec2tform([0 0 jH/2]));
    addVisual(body4, 'Box', [bW3 bW3 L4], trvec2tform([0 0 L4/2]));
    addBody(robot, body4, 'link3');

    % ═══════════════════════════════════════════════════
    %  连杆5：J5 — 腕部俯仰，绕 Y 轴（原7轴的 J6）
    %  固定变换：沿 Z 平移 L4，再绕 X 转 -90°（从世界回到 Rz2y）
    %  零位时：本体系 Z = 世界 Y，本体系 Y = 世界 -Z
    %  连杆沿本体系 -Y（= 世界 +Z）—— 腕部
    % ═══════════════════════════════════════════════════
    body5 = rigidBody('link5');
    j5 = rigidBodyJoint('jnt5', 'revolute');
    j5.PositionLimits = deg2rad([-120 120]);
    j5.HomePosition = 0;
    j5.setFixedTransform(trvec2tform([0 0 L4]) * rotm2tform(Rz2y));
    body5.Joint = j5;
    addVisual(body5, 'Cylinder', [jR*0.65 jH*0.65], trvec2tform([0 0 jH/2]));
    addVisual(body5, 'Box', [bW3 L5 bW3], trvec2tform([0 -L5/2 0]));
    addBody(robot, body5, 'link4');

    % ═══════════════════════════════════════════════════
    %  连杆6：J6 — 末端横滚，绕 Z 轴（沿工具方向，原7轴的 J7）
    %  固定变换：沿 Y 平移 -L5，再绕 X 转 +90°（从 Rz2y 回到世界）
    %  零位时：本体系 = 世界坐标系
    % ═══════════════════════════════════════════════════
    body6 = rigidBody('link6');
    j6 = rigidBodyJoint('jnt6', 'revolute');
    j6.PositionLimits = deg2rad([-175 175]);
    j6.HomePosition = 0;
    j6.setFixedTransform(trvec2tform([0 -L5 0]) * rotm2tform(Ry2z));
    body6.Joint = j6;
    addVisual(body6, 'Cylinder', [jR*0.55 jH*0.55], trvec2tform([0 0 jH/2]));
    addBody(robot, body6, 'link5');

    % ═══════════════════════════════════════════════════
    %  末端执行器（固定法兰 + 夹爪）
    % ═══════════════════════════════════════════════════
    ee = rigidBody('ee');
    ee.Joint = rigidBodyJoint('ee_joint', 'fixed');
    ee.Joint.setFixedTransform(trvec2tform([0 0 L6]));
    % 法兰
    addVisual(ee, 'Cylinder', [0.025 0.012], trvec2tform([0 0 0.006]));
    % 夹爪手指（两个小方块）
    addVisual(ee, 'Box', [0.045 0.006 0.028], trvec2tform([0  0.014 0.022]));
    addVisual(ee, 'Box', [0.045 0.006 0.028], trvec2tform([0 -0.014 0.022]));
    addBody(robot, ee, 'link6');

    % 设置重力方向
    robot.Gravity = [0 0 -9.81];

end
