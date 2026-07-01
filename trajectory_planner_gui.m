function trajectory_planner_gui()
%% TRAJECTORY_PLANNER_GUI  6-axis robot trajectory planning & simulation GUI.
%
%  Left  — 3D robot view with animation playback.
%  Right — Waypoint editor, trajectory method selection, parameter tuning,
%          and Run/Stop buttons.
%
%  Supported trajectory methods:
%    trapveltraj      Trapezoidal velocity profile (position + velocity output)
%    cubicpolytraj    Cubic polynomial (C² continuous)
%    quinticpolytraj  Quintic polynomial (C⁴ continuous)
%    bsplinepolytraj  B-spline interpolation
%
%  IK is solved via generalizedInverseKinematics with a position constraint
%  on the end-effector.

% ── Build robot ───────────────────────────────────────────────────
robot = build_6axis_arm();
robot.DataFormat = 'row';
homeCfg = zeros(1, 6);

% ── Shared state ──────────────────────────────────────────────────
state.animGen = 0;       % incremented each run → kills previous animation

% ── Default waypoints (pick-and-place demo) ────────────────────────
T_home = getTransform(robot, homeCfg, 'ee');
defaultWP = [...
     0.00,  0.00, T_home(3,4);   % 1. Home
     0.20,  0.15, 0.55;          % 2. Approach
     0.20,  0.15, 0.38;          % 3. Grasp
     0.20,  0.15, 0.60;          % 4. Lift
    -0.15, -0.20, 0.60;          % 5. Move
    -0.15, -0.20, 0.42;          % 6. Place
    -0.15, -0.20, 0.65;          % 7. Retract
     0.00,  0.00, T_home(3,4)];  % 8. Home

% ═══════════════════════════════════════════════════════════════════
%  FIGURE & MAIN LAYOUT
% ═══════════════════════════════════════════════════════════════════
fig = uifigure('Name', '6-Axis Robot Arm — Trajectory Planner', ...
               'Position', [40 40 1300 730], 'Resize', 'on');
fig.CloseRequestFcn = @(~,~) delete(fig);

mainGrid = uigridlayout(fig, [1 2], ...
    'ColumnWidth', {'2.5x', '1.5x'}, ...
    'Padding', [6 6 6 6], 'ColumnSpacing', 6);

% ═══════════════════════════════════════════════════════════════════
%  LEFT PANEL — 3D VIEW
% ═══════════════════════════════════════════════════════════════════
viewPanel = uipanel(mainGrid, 'BorderType', 'none');
ax = axes(viewPanel);
title(ax, '6-Axis Robotic Arm', 'FontSize', 12, 'FontWeight', 'bold');
axis(ax, 'equal');  grid(ax, 'on');
view(ax, [45 25]);  hold(ax, 'on');
xlim(ax, [-0.9 0.9]);  ylim(ax, [-0.9 0.9]);  zlim(ax, [-0.1 1.0]);

light(ax, 'Position', [3 2 4],    'Style', 'infinite');
light(ax, 'Position', [-2 -1 -0.5], 'Style', 'infinite');
lighting(ax, 'gouraud');
material(ax, [0.5 0.5 0.4 20]);

show(robot, homeCfg, 'Visuals', 'on', 'Collisions', 'off', ...
     'PreservePlot', false, 'Parent', ax);

% ═══════════════════════════════════════════════════════════════════
%  RIGHT PANEL — CONTROLS
% ═══════════════════════════════════════════════════════════════════
right = uigridlayout(mainGrid, [6 1], ...
    'RowHeight', {240, 'fit', 'fit', 'fit', 52, 24}, ...
    'Padding', [0 0 0 0], 'RowSpacing', 5);

% ── 1. Waypoints ──────────────────────────────────────────────────
pWP = uipanel(right, 'Title', '1. Waypoints / 路径点  (X Y Z in meters)', ...
              'FontWeight', 'bold');
pWP.Layout.Row = 1;
gWP = uigridlayout(pWP, [2 1], 'RowHeight', {'1x', 32}, ...
                   'Padding', [4 4 4 4], 'RowSpacing', 4);

wpTable = uitable(gWP, 'Data', defaultWP, ...
    'ColumnName', {'X (m)', 'Y (m)', 'Z (m)'}, ...
    'ColumnEditable', [true true true], ...
    'ColumnWidth', {80, 80, 80}, ...
    'RowName', 'numbered', 'Tag', 'wpTable');

btnWP = uigridlayout(gWP, [1 3], 'ColumnWidth', {'1x','1x','1x'}, ...
                     'Padding', [0 0 0 0], 'ColumnSpacing', 4);
uibutton(btnWP, 'push', 'Text', '+ Add Waypoint', ...
         'ButtonPushedFcn', @(~,~) addWP());
uibutton(btnWP, 'push', 'Text', '- Remove Last', ...
         'ButtonPushedFcn', @(~,~) removeWP());
uibutton(btnWP, 'push', 'Text', '↺ Reset Demo WPs', ...
         'ButtonPushedFcn', @(~,~) resetWP());

% ── 2. IK Settings ──────────────────────────────────────────────────
pIK = uipanel(right, 'Title', '2. IK Settings / 逆运动学设置', ...
              'FontWeight', 'bold');
pIK.Layout.Row = 2;
gIK = uigridlayout(pIK, [2 2], 'ColumnWidth', {90, '1x'}, ...
                   'RowHeight', {28, 28}, 'Padding', [5 5 5 5], ...
                   'RowSpacing', 4, 'ColumnSpacing', 6);

uilabel(gIK, 'Text', 'Constraint:', 'HorizontalAlignment', 'right');
ikModeDD = uidropdown(gIK, ...
    'Items', {'Position Only', 'Position + Orientation'}, ...
    'Value', 'Position Only');
ikModeDD.Layout.Row = 1;  ikModeDD.Layout.Column = 2;

uilabel(gIK, 'Text', 'Max Iterations:', 'HorizontalAlignment', 'right');
ikIters = uieditfield(gIK, 'numeric', 'Value', 500, ...
    'Limits', [10 2000], 'RoundFractionalValues', true, ...
    'ValueDisplayFormat', '%d');
ikIters.Layout.Row = 2;  ikIters.Layout.Column = 2;

% ── 3. Trajectory Method ───────────────────────────────────────────
pTraj = uipanel(right, 'Title', '3. Trajectory Method / 轨迹规划方法', ...
                'FontWeight', 'bold');
pTraj.Layout.Row = 3;
gTraj = uigridlayout(pTraj, [3 2], 'ColumnWidth', {90, '1x'}, ...
                     'RowHeight', {28, 28, 28}, 'Padding', [5 5 5 5], ...
                     'RowSpacing', 4, 'ColumnSpacing', 6);

uilabel(gTraj, 'Text', 'Method:', 'HorizontalAlignment', 'right');
methodDD = uidropdown(gTraj, ...
    'Items', {'trapveltraj (梯形速度)', ...
              'cubicpolytraj (三次多项式)', ...
              'quinticpolytraj (五次多项式)', ...
              'bsplinepolytraj (B样条)'}, ...
    'Value', 'trapveltraj (梯形速度)', ...
    'ValueChangedFcn', @(~,~) updateMethodUI());
methodDD.Layout.Row = 1;  methodDD.Layout.Column = 2;

uilabel(gTraj, 'Text', 'Total Time (s):', 'HorizontalAlignment', 'right');
endTimeFld = uieditfield(gTraj, 'numeric', 'Value', 6, ...
    'Limits', [0.1 600], 'ValueDisplayFormat', '%.1f');
endTimeFld.Layout.Row = 2;  endTimeFld.Layout.Column = 2;

uilabel(gTraj, 'Text', 'Samples / Segment:', 'HorizontalAlignment', 'right');
numSmpFld = uieditfield(gTraj, 'numeric', 'Value', 80, ...
    'Limits', [5 10000], 'RoundFractionalValues', true, ...
    'ValueDisplayFormat', '%d');
numSmpFld.Layout.Row = 3;  numSmpFld.Layout.Column = 2;

% ── 4. Advanced Parameters (method-dependent) ─────────────────────
pAdv = uipanel(right, 'Title', '4. Advanced Parameters / 高级参数', ...
               'FontWeight', 'bold');
pAdv.Layout.Row = 4;
gAdv = uigridlayout(pAdv, [1 2], 'ColumnWidth', {90, '1x'}, ...
                    'RowHeight', {28}, 'Padding', [5 5 5 5], ...
                    'RowSpacing', 4, 'ColumnSpacing', 6);

uilabel(gAdv, 'Text', 'Peak Vel (rad/s):', 'HorizontalAlignment', 'right');
peakVelFld = uieditfield(gAdv, 'numeric', 'Value', 0, ...
    'Limits', [0 100], 'ValueDisplayFormat', '%.2f', ...
    'Tooltip', '0 = auto (MATLAB default). Nonzero = max joint velocity (rad/s).', ...
    'Tag', 'peakVelFld');
peakVelFld.Layout.Row = 1;  peakVelFld.Layout.Column = 2;

% ── 5. Run / Stop ─────────────────────────────────────────────────
btnRow = uigridlayout(right, [1 2], 'ColumnWidth', {'2x','1x'}, ...
                      'Padding', [0 0 0 0], 'ColumnSpacing', 5);
btnRow.Layout.Row = 5;

runBtn = uibutton(btnRow, 'push', 'Text', '▶  Run Simulation', ...
    'FontSize', 14, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.25 0.70 0.30], 'FontColor', 'white', ...
    'ButtonPushedFcn', @(~,~) runSimulation());

stopBtn = uibutton(btnRow, 'push', 'Text', '■ Stop', ...
    'FontSize', 14, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.85 0.25 0.25], 'FontColor', 'white', ...
    'ButtonPushedFcn', @(~,~) stopSimulation(), 'Enable', 'off');

% ── 6. Status bar ─────────────────────────────────────────────────
statusLbl = uilabel(right, 'Text', 'Ready — set waypoints and click Run.', ...
    'FontColor', [0.4 0.4 0.4], 'FontSize', 10);
statusLbl.Layout.Row = 6;

% ═══════════════════════════════════════════════════════════════════
%  CALLBACKS
% ═══════════════════════════════════════════════════════════════════

    % ── Waypoint table helpers ──────────────────────────────────
    function addWP()
        data = wpTable.Data;
        if isempty(data)
            data = [0, 0, 0.5];
        else
            data(end+1, :) = data(end, :);
        end
        wpTable.Data = data;
    end

    function removeWP()
        data = wpTable.Data;
        if size(data, 1) <= 2
            statusLbl.Text = 'Need at least 2 waypoints.';
            statusLbl.FontColor = [0.85 0.3 0.0];
            return;
        end
        data(end, :) = [];
        wpTable.Data = data;
    end

    function resetWP()
        wpTable.Data = defaultWP;
    end

    % ── Method-dependent UI ─────────────────────────────────────
    function updateMethodUI()
        method = methodDD.Value;
        if startsWith(method, 'trapveltraj')
            peakVelFld.Enable = 'on';
            peakVelFld.Tooltip = '0 = auto (MATLAB default). Nonzero = max joint velocity (rad/s).';
        else
            peakVelFld.Enable = 'off';
            peakVelFld.Tooltip = 'Peak velocity only applies to trapveltraj.';
        end
    end

    % ── Stop ────────────────────────────────────────────────────
    function stopSimulation()
        state.animGen = state.animGen + 1;  % kill running animation
        runBtn.Enable = 'on';
        stopBtn.Enable = 'off';
        statusLbl.Text = 'Stopped by user.';
        statusLbl.FontColor = [0.85 0.3 0.0];
    end

    % ── Run ─────────────────────────────────────────────────────
    function runSimulation()
        % --- Read parameters ---
        wpData = wpTable.Data;
        numWP = size(wpData, 1);
        if numWP < 2
            statusLbl.Text = 'Need at least 2 waypoints.';
            statusLbl.FontColor = [0.85 0.3 0.0];
            return;
        end
        wpPos = wpData';   % 3×N

        usePose = strcmp(ikModeDD.Value, 'Position + Orientation');
        maxIter = ikIters.Value;
        method  = methodDD.Value;
        T_total = endTimeFld.Value;
        N_samp  = numSmpFld.Value;
        pkVel   = peakVelFld.Value;

        % --- Disable Run, enable Stop ---
        runBtn.Enable = 'off';
        stopBtn.Enable = 'on';
        state.animGen = state.animGen + 1;
        myGen = state.animGen;

        % --- Solve IK for each waypoint ---
        statusLbl.Text = sprintf('Solving IK for %d waypoints...', numWP);
        statusLbl.FontColor = [0.0 0.45 0.7];
        drawnow;

        if usePose
            gik = generalizedInverseKinematics('RigidBodyTree', robot, ...
                'ConstraintInputs', {'pose', 'joint'});
        else
            gik = generalizedInverseKinematics('RigidBodyTree', robot, ...
                'ConstraintInputs', {'position', 'joint'});
        end
        gik.SolverParameters.MaxIterations = maxIter;

        jointCon = constraintJointBounds(robot);
        if usePose
            tgtCon = constraintPoseTarget('ee');
        else
            tgtCon = constraintPositionTarget('ee');
        end

        jointWP = zeros(6, numWP);
        qCurrent = homeCfg;

        for i = 1:numWP
            if usePose
                tgtCon.TargetTransform = trvec2tform(wpPos(:, i)');
            else
                tgtCon.TargetPosition = wpPos(:, i);
            end
            [qSol, solInfo] = gik(qCurrent, tgtCon, jointCon);

            if ~strcmp(solInfo.Status, 'success')
                statusLbl.Text = sprintf('IK failed at WP%d: %s', i, solInfo.Status);
                statusLbl.FontColor = [0.85 0.25 0.0];
                runBtn.Enable = 'on';
                stopBtn.Enable = 'off';
                return;
            end
            jointWP(:, i) = qSol';
            qCurrent = qSol;
        end

        % --- Generate trajectory ---
        statusLbl.Text = 'Generating trajectory...';
        drawnow;

        try
            [qTraj, qdTraj, tVec] = generateTrajectory(jointWP, method, ...
                T_total, N_samp, pkVel);
        catch ME
            statusLbl.Text = sprintf('Trajectory error: %s', ME.message);
            statusLbl.FontColor = [0.85 0.25 0.0];
            runBtn.Enable = 'on';
            stopBtn.Enable = 'off';
            return;
        end

        totalPts = size(qTraj, 2);
        if state.animGen ~= myGen, finishRun(); return; end

        % --- Pre-compute EE path ---
        eePath = zeros(3, totalPts);
        for k = 1:totalPts
            T = getTransform(robot, qTraj(:, k)', 'ee');
            eePath(:, k) = T(1:3, 4);
        end

        % --- Clear axes & draw waypoints / path ---
        cla(ax);
        show(robot, qTraj(:, 1)', 'Visuals', 'on', 'Collisions', 'off', ...
             'PreservePlot', false, 'Parent', ax, 'FastUpdate', true);
        hold(ax, 'on');
        plot3(ax, eePath(1, :), eePath(2, :), eePath(3, :), ...
              'g-', 'LineWidth', 1.5);
        scatter3(ax, wpPos(1, :), wpPos(2, :), wpPos(3, :), ...
                 80, 'r', 'filled', 'MarkerEdgeColor', 'k');
        title(ax, sprintf('6-Axis Robotic Arm — %s', ...
              extractMethodName(method)), 'FontSize', 12, 'FontWeight', 'bold');
        axis(ax, 'equal');
        xlim(ax, [-0.9 0.9]);  ylim(ax, [-0.9 0.9]);  zlim(ax, [-0.1 1.0]);
        grid(ax, 'on');

        if state.animGen ~= myGen, finishRun(); return; end

        % --- Animate ---
        statusLbl.Text = sprintf('Playing %d frames...', totalPts);
        statusLbl.FontColor = [0.0 0.55 0.0];
        drawnow;

        for frame = 1:totalPts
            if state.animGen ~= myGen
                finishRun();
                return;
            end
            show(robot, qTraj(:, frame)', 'Visuals', 'on', 'Collisions', 'off', ...
                 'PreservePlot', false, 'Parent', ax, 'FastUpdate', true);
            title(ax, sprintf('6-Axis Robotic Arm — %s  |  t = %.1f / %.1f s', ...
                  extractMethodName(method), ...
                  tVec(min(frame, end)), tVec(end)), ...
                  'FontSize', 12, 'FontWeight', 'bold');
            drawnow;
            pause(0.02);
        end

        finishRun();

        % --- Summary ---
        eeDist = sum(sqrt(sum(diff(eePath, 1, 2).^2, 1)));
        statusLbl.Text = sprintf(...
            'Done. %d WPs, %d frames, %.1f s, EE path = %.3f m  |  Method: %s', ...
            numWP, totalPts, tVec(end), eeDist, extractMethodName(method));
        statusLbl.FontColor = [0.0 0.4 0.0];
    end

    function finishRun()
        runBtn.Enable = 'on';
        stopBtn.Enable = 'off';
    end

% ═══════════════════════════════════════════════════════════════════
%  TRAJECTORY GENERATION
% ═══════════════════════════════════════════════════════════════════

    function [q, qd, tv] = generateTrajectory(wpts, method, Ttot, Nseg, pkv)
        % wpts: 6×N joint-space waypoints
        numWPs = size(wpts, 2);

        if startsWith(method, 'trapveltraj')
            opts = {'EndTime', Ttot};
            if pkv > 0
                opts = [opts, {'PeakVelocity', pkv}];
            end
            [q, qd, ~, tv] = trapveltraj(wpts, Nseg, opts{:});

        elseif startsWith(method, 'cubicpolytraj')
            tWPs = linspace(0, Ttot, numWPs);
            tv   = linspace(0, Ttot, Nseg * numWPs);
            [q, qd, ~] = cubicpolytraj(wpts, tWPs, tv);

        elseif startsWith(method, 'quinticpolytraj')
            tWPs = linspace(0, Ttot, numWPs);
            tv   = linspace(0, Ttot, Nseg * numWPs);
            [q, qd, ~] = quinticpolytraj(wpts, tWPs, tv);

        elseif startsWith(method, 'bsplinepolytraj')
            tv   = linspace(0, Ttot, Nseg * numWPs);
            [q, qd, ~] = bsplinepolytraj(wpts, [0 Ttot], tv);

        else
            error('Unknown trajectory method.');
        end
        if iscolumn(tv), tv = tv'; end
    end

    function name = extractMethodName(method)
        parts = strsplit(method, ' (');
        name = parts{1};
    end

% ═══════════════════════════════════════════════════════════════════
%  INIT
% ═══════════════════════════════════════════════════════════════════
updateMethodUI();

end
