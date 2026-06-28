function robot = build_7axis_arm()
% BUILD_7AXIS_ARM  Construct a 7-DOF robotic arm rigidBodyTree.
%
%   robot = build_7axis_arm() returns a rigidBodyTree with 7 revolute
%   joints, a fixed base pedestal, and a fixed end-effector flange.
%   Each link includes box/cylinder visual geometry for realistic 3D
%   rendering (not stick-figure lines).
%
%   Joint layout (home: arm extends straight up along +Z):
%     J1 - Base rotation (waist), axis Z
%     J2 - Shoulder pitch, axis Y
%     J3 - Upper arm roll (redundant DOF), axis Z
%     J4 - Elbow pitch, axis Y
%     J5 - Forearm roll, axis Z
%     J6 - Wrist pitch, axis Y
%     J7 - Tool roll, axis Z
%
%   Total reach ≈ 0.87 m from base origin.

    robot = rigidBodyTree('DataFormat', 'row', 'MaxNumBodies', 10);

    % Rotation helpers
    Rx_neg = axang2rotm([1 0 0 -pi/2]);  % Z→Y (maps parent Z to child Y)
    Rx_pos = axang2rotm([1 0 0  pi/2]);  % Z→-Y (maps parent Z to child -Y)
    % Combined: Rx_pos * Rx_neg = I, so pairs cancel out

    % ── Link dimensions (meters) ──
    BASE_H  = 0.12;   % pedestal height
    BASE_R  = 0.10;   % pedestal radius
    L0      = 0.05;   % J1→J2 offset
    L1      = 0.28;   % upper arm (J2→J3)
    L2      = 0.04;   % J3→J4 offset
    L3      = 0.22;   % forearm (J4→J5)
    L4      = 0.04;   % J5→J6 offset
    L5      = 0.06;   % wrist (J6→J7)
    L6      = 0.06;   % J7→EE flange
    JR      = 0.040;  % joint housing radius
    JH      = 0.035;  % joint housing height
    LW      = 0.060;  % link box width/depth
    LW2     = 0.050;  % thinner link width (forearm)
    LW3     = 0.040;  % thinnest link width (wrist)

    % ═══════════════════════════════════════════════════════════════
    % PEDESTAL (fixed, child of robot root 'base')
    % ═══════════════════════════════════════════════════════════════
    p = rigidBody('pedestal');
    p.Joint = rigidBodyJoint('pedestal_joint', 'fixed');
    addVisual(p, 'Cylinder', [BASE_R BASE_H], trvec2tform([0 0 BASE_H/2]));
    addVisual(p, 'Box', [0.24 0.24 0.02], trvec2tform([0 0 0.01]));
    addBody(robot, p, robot.BaseName);

    % ═══════════════════════════════════════════════════════════════
    % BODY 1: link1 (J1 — waist rotation, axis Z)
    %   At home: body frame = world frame at z = BASE_H
    %   Link extends along body +Z from J1 to J2
    % ═══════════════════════════════════════════════════════════════
    b1 = rigidBody('link1');
    j1 = rigidBodyJoint('jnt1', 'revolute');
    j1.PositionLimits = deg2rad([-170 170]);
    j1.HomePosition = 0;
    j1.setFixedTransform(trvec2tform([0 0 BASE_H]));
    b1.Joint = j1;
    addVisual(b1, 'Cylinder', [JR JH], trvec2tform([0 0 JH/2]));
    % Link box along body +Z
    addVisual(b1, 'Box', [LW LW L0], trvec2tform([0 0 L0/2]));
    addBody(robot, b1, 'pedestal');

    % ═══════════════════════════════════════════════════════════════
    % BODY 2: link2 (J2 — shoulder pitch, axis Y)
    %   Fixed: translate [0,0,L0] then rotate Rx(-pi/2)
    %   At home: body Z = parent Y = world Y; body Y = parent -Z = world -Z
    %   Link extends along body -Y (= world Z) from J2 to J3
    % ═══════════════════════════════════════════════════════════════
    b2 = rigidBody('link2');
    j2 = rigidBodyJoint('jnt2', 'revolute');
    j2.PositionLimits = deg2rad([-120 120]);
    j2.HomePosition = 0;
    j2.setFixedTransform(trvec2tform([0 0 L0]) * rotm2tform(Rx_neg));
    b2.Joint = j2;
    addVisual(b2, 'Cylinder', [JR JH], trvec2tform([0 0 JH/2]));
    % Upper arm: link along body -Y (= world Z at home)
    addVisual(b2, 'Box', [LW L1 LW], trvec2tform([0 -L1/2 0]));
    addBody(robot, b2, 'link1');

    % ═══════════════════════════════════════════════════════════════
    % BODY 3: link3 (J3 — upper arm roll, axis Z along arm)
    %   Fixed: translate [0,-L1,0] then rotate Rx(pi/2) → cancels prev Rx(-pi/2)
    %   At home: body frame = world frame
    %   Link extends along body +Z from J3 to J4
    % ═══════════════════════════════════════════════════════════════
    b3 = rigidBody('link3');
    j3 = rigidBodyJoint('jnt3', 'revolute');
    j3.PositionLimits = deg2rad([-170 170]);
    j3.HomePosition = 0;
    j3.setFixedTransform(trvec2tform([0 -L1 0]) * rotm2tform(Rx_pos));
    b3.Joint = j3;
    addVisual(b3, 'Cylinder', [JR*0.9 JH*0.9], trvec2tform([0 0 JH/2]));
    addVisual(b3, 'Box', [LW2 LW2 L2], trvec2tform([0 0 L2/2]));
    addBody(robot, b3, 'link2');

    % ═══════════════════════════════════════════════════════════════
    % BODY 4: link4 (J4 — elbow pitch, axis Y)
    %   Fixed: translate [0,0,L2] then rotate Rx(-pi/2)
    %   At home: body Z = world Y, body Y = world -Z
    %   Link along body -Y (= world Z) — forearm
    % ═══════════════════════════════════════════════════════════════
    b4 = rigidBody('link4');
    j4 = rigidBodyJoint('jnt4', 'revolute');
    j4.PositionLimits = deg2rad([-120 120]);
    j4.HomePosition = 0;
    j4.setFixedTransform(trvec2tform([0 0 L2]) * rotm2tform(Rx_neg));
    b4.Joint = j4;
    addVisual(b4, 'Cylinder', [JR*0.85 JH*0.85], trvec2tform([0 0 JH/2]));
    addVisual(b4, 'Box', [LW2 L3 LW2], trvec2tform([0 -L3/2 0]));
    addBody(robot, b4, 'link3');

    % ═══════════════════════════════════════════════════════════════
    % BODY 5: link5 (J5 — forearm roll, axis Z along arm)
    %   Fixed: translate [0,-L3,0] then rotate Rx(pi/2) → back to world frame
    %   Link along body +Z from J5 to J6
    % ═══════════════════════════════════════════════════════════════
    b5 = rigidBody('link5');
    j5 = rigidBodyJoint('jnt5', 'revolute');
    j5.PositionLimits = deg2rad([-170 170]);
    j5.HomePosition = 0;
    j5.setFixedTransform(trvec2tform([0 -L3 0]) * rotm2tform(Rx_pos));
    b5.Joint = j5;
    addVisual(b5, 'Cylinder', [JR*0.75 JH*0.75], trvec2tform([0 0 JH/2]));
    addVisual(b5, 'Box', [LW3 LW3 L4], trvec2tform([0 0 L4/2]));
    addBody(robot, b5, 'link4');

    % ═══════════════════════════════════════════════════════════════
    % BODY 6: link6 (J6 — wrist pitch, axis Y)
    %   Fixed: translate [0,0,L4] then rotate Rx(-pi/2)
    %   Link along body -Y (= world Z) — wrist body
    % ═══════════════════════════════════════════════════════════════
    b6 = rigidBody('link6');
    j6 = rigidBodyJoint('jnt6', 'revolute');
    j6.PositionLimits = deg2rad([-120 120]);
    j6.HomePosition = 0;
    j6.setFixedTransform(trvec2tform([0 0 L4]) * rotm2tform(Rx_neg));
    b6.Joint = j6;
    addVisual(b6, 'Cylinder', [JR*0.65 JH*0.65], trvec2tform([0 0 JH/2]));
    addVisual(b6, 'Box', [LW3 L5 LW3], trvec2tform([0 -L5/2 0]));
    addBody(robot, b6, 'link5');

    % ═══════════════════════════════════════════════════════════════
    % BODY 7: link7 (J7 — tool roll, axis Z along tool)
    %   Fixed: translate [0,-L5,0] then rotate Rx(pi/2) → back to world frame
    % ═══════════════════════════════════════════════════════════════
    b7 = rigidBody('link7');
    j7 = rigidBodyJoint('jnt7', 'revolute');
    j7.PositionLimits = deg2rad([-175 175]);
    j7.HomePosition = 0;
    j7.setFixedTransform(trvec2tform([0 -L5 0]) * rotm2tform(Rx_pos));
    b7.Joint = j7;
    addVisual(b7, 'Cylinder', [JR*0.55 JH*0.55], trvec2tform([0 0 JH/2]));
    addBody(robot, b7, 'link6');

    % ═══════════════════════════════════════════════════════════════
    % END EFFECTOR (fixed flange + gripper)
    % ═══════════════════════════════════════════════════════════════
    ee = rigidBody('ee');
    ee.Joint = rigidBodyJoint('ee_joint', 'fixed');
    ee.Joint.setFixedTransform(trvec2tform([0 0 L6]));
    addVisual(ee, 'Cylinder', [0.025 0.012], trvec2tform([0 0 0.006]));
    % Gripper fingers
    addVisual(ee, 'Box', [0.045 0.006 0.028], trvec2tform([0  0.014 0.022]));
    addVisual(ee, 'Box', [0.045 0.006 0.028], trvec2tform([0 -0.014 0.022]));
    addBody(robot, ee, 'link7');

    % Set gravity
    robot.Gravity = [0 0 -9.81];

end
