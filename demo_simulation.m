%% demo_simulation.m
% 7-Axis Robotic Arm — Pick-and-Place Trajectory Planning & Simulation
%
% Demonstrates:
%   1. Robot model visualization (3D box/cylinder geometry)
%   2. Cartesian waypoint definition (pick-and-place task)
%   3. Inverse kinematics for redundant 7-DOF arm
%   4. Joint-space trajectory smoothing (trapveltraj)
%   5. Animated simulation with EE path trace

clear; close all;

%% ── 1. Build the robot ──────────────────────────────────────────
fprintf('Building 7-axis robotic arm model...\n');
robot = build_7axis_arm();
robot.DataFormat = 'row';
homeConfig = zeros(1, 7);

% Display home configuration
fprintf('Displaying home configuration (3D figure)...\n');
fig = figure('Name', '7-Axis Robotic Arm Simulation', ...
             'Position', [100 100 900 700], 'Color', 'w');
ax = axes('Parent', fig);
show(robot, homeConfig, 'Visuals', 'on', 'Collisions', 'off', ...
     'PreservePlot', false, 'Parent', ax);
title(ax, '7-Axis Robotic Arm — Home Configuration', 'FontSize', 14);
view(ax, [45 25]);
axis(ax, 'equal');
grid(ax, 'on');
drawnow;

%% ── 2. Define pick-and-place waypoints ──────────────────────────
fprintf('\nDefining Cartesian waypoints (pick-and-place)...\n');

% Waypoint 1: Home (arm straight up)
wpPos = cell(1, 8);
T_home = getTransform(robot, homeConfig, 'ee');
wpPos{1} = T_home(1:3, 4)';          % [0, 0, 0.87]

% Waypoint 2: Approach above object
wpPos{2} = [ 0.20,  0.15, 0.55];

% Waypoint 3: Grasp object
wpPos{3} = [ 0.20,  0.15, 0.38];

% Waypoint 4: Lift object
wpPos{4} = [ 0.20,  0.15, 0.60];

% Waypoint 5: Move to place location
wpPos{5} = [-0.15, -0.20, 0.60];

% Waypoint 6: Lower to place
wpPos{6} = [-0.15, -0.20, 0.42];

% Waypoint 7: Retract after place
wpPos{7} = [-0.15, -0.20, 0.65];

% Waypoint 8: Return to home
wpPos{8} = wpPos{1};

numWP = length(wpPos);
fprintf('  Defined %d waypoints\n', numWP);

%% ── 3. Solve IK for each waypoint ───────────────────────────────
fprintf('\nSolving inverse kinematics...\n');

% Use generalized IK with position constraint (redundancy-friendly)
gik = generalizedInverseKinematics('RigidBodyTree', robot, ...
    'ConstraintInputs', {'position', 'joint'});
gik.SolverParameters.MaxIterations = 500;
posCon = constraintPositionTarget('ee');
jointCon = constraintJointBounds(robot);

jointWP = zeros(7, numWP);
qCurrent = homeConfig;

for i = 1:numWP
    posCon.TargetPosition = wpPos{i}';
    [qSol, solInfo] = gik(qCurrent, posCon, jointCon);

    jointWP(:, i) = qSol';
    qCurrent = qSol;

    % Verify
    Tcheck = getTransform(robot, qSol, 'ee');
    posErr = norm(Tcheck(1:3,4) - wpPos{i}');
    if strcmp(solInfo.Status, 'success')
        fprintf('  WP%d: OK  (err=%.4f m, iters=%d)\n', ...
                i, posErr, solInfo.Iterations);
    else
        fprintf('  WP%d: %s (err=%.4f m)\n', i, solInfo.Status, posErr);
    end
end

%% ── 4. Generate smooth joint trajectory ─────────────────────────
fprintf('\nGenerating smooth trajectory via trapveltraj...\n');
numSamples = 80;
segmentTime = 3;  % seconds per segment

[qTraj, qdTraj] = trapveltraj(jointWP, numSamples, 'EndTime', segmentTime);

totalPts = size(qTraj, 2);
fprintf('  Trajectory: %d waypoints x %d samples = %d total points\n', ...
        numWP, numSamples, totalPts);

% Check joint limits
allOK = true;
for j = 1:7
    limits = robot.Bodies{j+1}.Joint.PositionLimits;  % +1 skip pedestal
    if any(qTraj(j,:) < limits(1)) || any(qTraj(j,:) > limits(2))
        fprintf('  WARNING: Joint %d exceeds limits!\n', j);
        allOK = false;
    end
end
if allOK
    fprintf('  All joints within limits.\n');
end

%% ── 5. Animate the arm along the trajectory ─────────────────────
fprintf('\nAnimating trajectory (close figure to stop)...\n');

cla(ax);
show(robot, qTraj(:,1)', 'Visuals', 'on', 'Collisions', 'off', ...
     'PreservePlot', false, 'Parent', ax);
title(ax, '7-Axis Robotic Arm — Pick & Place Simulation', 'FontSize', 14);
view(ax, [45 25]);
axis(ax, 'equal');
grid(ax, 'on');
hold(ax, 'on');

% Pre-compute EE path
eePath = zeros(3, totalPts);
for k = 1:totalPts
    T = getTransform(robot, qTraj(:,k)', 'ee');
    eePath(:,k) = T(1:3,4);
end

% Plot EE path
plot3(ax, eePath(1,:), eePath(2,:), eePath(3,:), ...
      'g-', 'LineWidth', 1.5);

% Plot waypoints as red spheres
hold(ax, 'on');
for i = 1:numWP
    scatter3(ax, wpPos{i}(1), wpPos{i}(2), wpPos{i}(3), ...
             100, 'r', 'filled', 'MarkerEdgeColor', 'k');
end

legend(ax, {'EE Path', 'Waypoints'}, 'Location', 'best');

% Animation loop
fps = 25;
totalTime = segmentTime * numWP;
tVec = linspace(0, totalTime, totalPts);

fprintf('  Running at ~%d fps...\n', fps);
for frame = 1:totalPts
    qNow = qTraj(:, frame)';

    show(robot, qNow, 'Visuals', 'on', 'Collisions', 'off', ...
         'PreservePlot', false, 'Parent', ax, 'FastUpdate', true);
    title(ax, sprintf('7-Axis Robotic Arm  |  t = %.1f / %.0f s  |  WP %d/%d', ...
          tVec(frame), totalTime, ...
          min(ceil(frame / numSamples), numWP), numWP), ...
          'FontSize', 14);
    drawnow;
    pause(0.03);
end

%% ── 6. Summary ──────────────────────────────────────────────────
fprintf('\n========== Simulation Complete ==========\n');
fprintf('Robot:    7-DOF, reach = %.2f m\n', norm(T_home(1:3,4)));
fprintf('Waypoints: %d\n', numWP);
fprintf('Duration:  %.0f s\n', totalTime);
fprintf('EE path:   %.3f m\n', sum(sqrt(sum(diff(eePath,1,2).^2, 1))));
fprintf('==========================================\n');
