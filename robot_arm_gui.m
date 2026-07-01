function robot_arm_gui()
%% ROBOT_ARM_GUI  7-axis robot arm — unified kinematics & trajectory planner.
%
%  Tab 1 "Explore / 探索"
%    FK Mode : 7 joint-angle sliders → live 3D view + EE pose
%    IK Mode : 6 XYZ/RPY sliders → auto-solve IK → animate transition
%
%  Tab 2 "Plan / 轨迹规划"
%    Editable waypoints, 4 trajectory methods (trapveltraj, cubicpolytraj,
%    quinticpolytraj, bsplinepolytraj), parameter tuning, animation playback.

% ═══════════════════════════════════════════════════════════════════
%  SHARED RESOURCES
% ═══════════════════════════════════════════════════════════════════
robot = build_7axis_arm();
robot.DataFormat = 'row';
homeCfg = zeros(1, 7);

% ── Shared state ──────────────────────────────────────────────────
state.kinMode   = 'FK';      % 'FK' or 'IK' (Explore tab sub-mode)
state.config    = homeCfg;   % current displayed joint configuration
state.targetCfg = homeCfg;   % FK slider target
state.animGen   = 0;         % incremented on each new animation request
state.animating = false;
state.ikOK      = true;
state.trajData  = struct('eePath', [], 'wpPos', [], 'method', '');  % Plan tab cache

% ── Debounce timer placeholder (created in buildExploreTab) ──────
debounceTimer = [];

% ═══════════════════════════════════════════════════════════════════
%  FIGURE & MAIN LAYOUT
% ═══════════════════════════════════════════════════════════════════
fig = uifigure('Name', '7-Axis Robot Arm — Kinematics & Trajectory Planner', ...
               'Position', [40 40 1300 780], 'Resize', 'on');
fig.CloseRequestFcn = @(~,~) cleanup();

mainGrid = uigridlayout(fig, [1 2], ...
    'ColumnWidth', {'3x', '2x'}, ...
    'Padding', [6 6 6 6], 'ColumnSpacing', 6);

% ═══════════════════════════════════════════════════════════════════
%  LEFT — SHARED 3D VIEW
% ═══════════════════════════════════════════════════════════════════
viewPanel = uipanel(mainGrid, 'BorderType', 'none');
ax = axes(viewPanel);
title(ax, '7-Axis Robotic Arm', 'FontSize', 12, 'FontWeight', 'bold');
view(ax, [40 28]);  hold(ax, 'on');
axis(ax, 'equal');  grid(ax, 'on');
xlim(ax, [-0.9 0.9]);  ylim(ax, [-0.9 0.9]);  zlim(ax, [-0.1 1.0]);

show(robot, homeCfg, 'Visuals', 'on', 'Collisions', 'off', ...
     'PreservePlot', false, 'Parent', ax);
restoreLighting();

% ═══════════════════════════════════════════════════════════════════
%  RIGHT — TAB GROUP
% ═══════════════════════════════════════════════════════════════════
tabGroup = uitabgroup(mainGrid);
tabGroup.SelectionChangedFcn = @(~, evt) onTabSwitch(evt);

tabExplore = uitab(tabGroup, 'Title', '🔍 Explore / 探索');
tabPlan    = uitab(tabGroup, 'Title', '📐 Plan / 轨迹规划');

buildExploreTab(tabExplore);
buildPlanTab(tabPlan);

% ═══════════════════════════════════════════════════════════════════
%  TAB SWITCH HANDLER
% ═══════════════════════════════════════════════════════════════════
    function onTabSwitch(evt)
        state.animGen = state.animGen + 1;   % kill any running animation
        if ~isempty(debounceTimer)
            stop(debounceTimer);
        end
        % Call tab-specific refresh stored in UserData
        if ~isempty(evt.NewValue.UserData) && isa(evt.NewValue.UserData, 'function_handle')
            feval(evt.NewValue.UserData);
        end
    end

% ═══════════════════════════════════════════════════════════════════
%  CLEANUP
% ═══════════════════════════════════════════════════════════════════
    function cleanup()
        if ~isempty(debounceTimer)
            stop(debounceTimer);
            delete(debounceTimer);
        end
        delete(fig);
    end

    function restoreLighting()
        % Re-apply lights & material after show/cla clears them
        delete(findobj(ax, 'Type', 'Light'));
        light(ax, 'Position', [3 2 4],    'Style', 'infinite');
        light(ax, 'Position', [-2 -1 -0.5], 'Style', 'infinite');
        lighting(ax, 'gouraud');
        material(ax, [0.6 0.6 0.4 25]);
    end

% ╔══════════════════════════════════════════════════════════════════╗
% ║  TAB 1 — EXPLORE / 探索  (FK/IK interactive kinematics)         ║
% ╚══════════════════════════════════════════════════════════════════╝
    function buildExploreTab(tab)
        % 4-row layout
        ctrlGrid = uigridlayout(tab, [4 1], ...
            'RowHeight', {'fit', '1x', 'fit', 22}, ...
            'Padding', [4 4 4 4], 'RowSpacing', 5);

        % ── Row 1: FK / IK mode toggle ────────────────────────────
        modePanel = uipanel(ctrlGrid, 'Title', 'Mode / 模式', 'FontWeight', 'bold');
        modePanel.Layout.Row = 1;
        modeSub = uigridlayout(modePanel, [1 2], 'Padding', [5 5 5 5], 'ColumnSpacing', 5);
        fkBtn = uibutton(modeSub, 'state', 'Text', 'FK 正运动学', 'Value', true, ...
                         'FontSize', 11, 'FontWeight', 'bold');
        ikBtn = uibutton(modeSub, 'state', 'Text', 'IK 逆运动学', ...
                         'FontSize', 11, 'FontWeight', 'bold');
        fkBtn.ValueChangedFcn = @(src, ~) modeToggle('FK', src.Value);
        ikBtn.ValueChangedFcn = @(src, ~) modeToggle('IK', src.Value);

        % ── Row 2a: FK slider panel ───────────────────────────────
        fkPanel = uipanel(ctrlGrid, 'Title', 'Joint Angles / 关节角度 (deg)', ...
                          'FontWeight', 'bold');
        fkPanel.Layout.Row = 2;
        fkGrid = uigridlayout(fkPanel, [7 3], ...
            'ColumnWidth', {60, '1x', 42}, ...
            'RowHeight', repmat({28}, 1, 7), ...
            'Padding', [4 4 4 4], 'RowSpacing', 2, 'ColumnSpacing', 3);

        jointNames = {'J1 腰', 'J2 肩', 'J3 臂滚', 'J4 肘', 'J5 前臂', 'J6 腕', 'J7 工具'};
        fkSliders  = gobjects(1, 7);
        fkVals     = gobjects(1, 7);

        for i = 1:7
            lims = robot.Bodies{i+1}.Joint.PositionLimits;
            uilabel(fkGrid, 'Text', jointNames{i}, ...
                    'HorizontalAlignment', 'right', 'FontSize', 9);
            sld = uislider(fkGrid, 'Limits', lims, 'Value', 0, ...
                           'MajorTicks', [], 'MinorTicks', []);
            sld.Layout.Row = i;  sld.Layout.Column = 2;
            idx = i;
            sld.ValueChangingFcn = @(src, evt) onFKDrag(idx, evt.Value);
            sld.ValueChangedFcn  = @(src, ~)   onFKRelease(idx, src.Value);
            fkSliders(i) = sld;
            vl = uilabel(fkGrid, 'Text', '0.0', ...
                         'HorizontalAlignment', 'left', 'FontSize', 9);
            vl.Layout.Row = i;  vl.Layout.Column = 3;
            fkVals(i) = vl;
        end

        % ── Row 2b: IK slider panel ───────────────────────────────
        ikPanel = uipanel(ctrlGrid, 'Title', 'Target Pose / 目标位姿', ...
                          'FontWeight', 'bold');
        ikPanel.Layout.Row = 2;
        ikGrid = uigridlayout(ikPanel, [6 3], ...
            'ColumnWidth', {48, '1x', 50}, ...
            'RowHeight', repmat({28}, 1, 6), ...
            'Padding', [4 4 4 4], 'RowSpacing', 2, 'ColumnSpacing', 3);

        ikLabels  = {'X (m)', 'Y (m)', 'Z (m)', 'Roll°', 'Pitch°', 'Yaw°'};
        ikLimits  = [-0.75 0.75;  -0.75 0.75;  0.04 0.88;  -180 180;  -180 180;  -180 180];
        ikStarts  = [0, 0, 0.87, 0, 0, 0];
        ikSliders = gobjects(1, 6);
        ikValLbls = gobjects(1, 6);

        for i = 1:6
            uilabel(ikGrid, 'Text', ikLabels{i}, ...
                    'HorizontalAlignment', 'right', 'FontSize', 9);
            sld = uislider(ikGrid, 'Limits', ikLimits(i,:), 'Value', ikStarts(i), ...
                           'MajorTicks', [], 'MinorTicks', []);
            sld.Layout.Row = i;  sld.Layout.Column = 2;
            sld.ValueChangedFcn = @(~,~) onIKSlider();
            ikSliders(i) = sld;
            vl = uilabel(ikGrid, 'Text', fmtslider(i, ikStarts(i)), ...
                         'HorizontalAlignment', 'left', 'FontSize', 9);
            vl.Layout.Row = i;  vl.Layout.Column = 3;
            ikValLbls(i) = vl;
        end
        ikPanel.Visible = 'off';

        % ── Row 3: EE pose display ────────────────────────────────
        eePanel = uipanel(ctrlGrid, 'Title', 'End-Effector Pose / 末端位姿', ...
                          'FontWeight', 'bold');
        eePanel.Layout.Row = 3;
        eeGrid = uigridlayout(eePanel, [2 6], ...
            'ColumnWidth', {28, '1x', 28, '1x', 28, '1x'}, ...
            'RowHeight', {20, 20}, ...
            'Padding', [4 2 4 2], 'RowSpacing', 1, 'ColumnSpacing', 2);

        posLabels = {'X:', 'Y:', 'Z:'};
        oriLabels = {'R:', 'P:', 'Y:'};
        posFields = gobjects(1, 3);
        oriFields = gobjects(1, 3);
        for j = 1:3
            pl = uilabel(eeGrid, 'Text', posLabels{j}, ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 10);
            pl.Layout.Row = 1;  pl.Layout.Column = 2*j - 1;
            pf = uilabel(eeGrid, 'Text', '0.000', ...
                'BackgroundColor', [0.95 0.95 0.95], 'HorizontalAlignment', 'center', 'FontSize', 10);
            pf.Layout.Row = 1;  pf.Layout.Column = 2*j;
            posFields(j) = pf;
            ol = uilabel(eeGrid, 'Text', oriLabels{j}, ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 10);
            ol.Layout.Row = 2;  ol.Layout.Column = 2*j - 1;
            of = uilabel(eeGrid, 'Text', '0.0', ...
                'BackgroundColor', [0.95 0.95 0.95], 'HorizontalAlignment', 'center', 'FontSize', 10);
            of.Layout.Row = 2;  of.Layout.Column = 2*j;
            oriFields(j) = of;
        end

        % ── Row 4: Status ─────────────────────────────────────────
        kinStatusLbl = uilabel(ctrlGrid, 'Text', 'Ready — drag sliders to explore.', ...
            'FontColor', [0.35 0.35 0.35], 'FontSize', 9);
        kinStatusLbl.Layout.Row = 4;

        % ========================= CALLBACKS =========================

        % Debounce timer for FK drag (stored in main scope for cleanup)
        debounceTimer = timer('ExecutionMode', 'singleShot', ...
                              'StartDelay', 0.08, ...
                              'TimerFcn', @(~,~) debounceUpdate());

        function modeToggle(newMode, isOn)
            if ~isOn
                if strcmp(newMode, 'FK'), fkBtn.Value = true;
                else, ikBtn.Value = true; end
                return;
            end
            if strcmp(newMode, 'FK')
                ikBtn.Value = false;
                fkPanel.Visible = 'on';
                ikPanel.Visible = 'off';
                syncFKSlidersFromConfig();
                kinStatusLbl.Text = 'FK mode — drag joint sliders to see EE pose.';
            else
                fkBtn.Value = false;
                fkPanel.Visible = 'off';
                ikPanel.Visible = 'on';
                syncIKSlidersFromEE();
                kinStatusLbl.Text = 'IK mode — drag XYZ sliders, joints auto-solve.';
            end
            state.kinMode = newMode;
            kinStatusLbl.FontColor = [0.35 0.35 0.35];
            updateEEPose();
            updateKinView();
        end

        function onFKDrag(idx, val)
            state.targetCfg(idx) = val;
            fkVals(idx).Text = sprintf('%.1f', rad2deg(val));
            stop(debounceTimer);
            start(debounceTimer);
        end

        function onFKRelease(idx, val)
            stop(debounceTimer);
            state.targetCfg(idx) = val;
            fkVals(idx).Text = sprintf('%.1f', rad2deg(val));
            animateFK();
            updateEEPose();
        end

        function debounceUpdate()
            if ~strcmp(state.kinMode, 'FK'), return; end
            animateFK();
        end

        function animateFK()
            if all(abs(state.config - state.targetCfg) < 1e-6), return; end
            state.animGen = state.animGen + 1;
            myGen = state.animGen;
            state.animating = true;
            qFrom = state.config;
            qTo   = state.targetCfg;
            nSteps = max(3, round(20 * max(abs(qTo - qFrom)) / pi));
            nSteps = min(nSteps, 30);
            tvec = linspace(0, 1, nSteps);
            [qTraj, ~, ~] = cubicpolytraj([qFrom', qTo'], [0 1], tvec);
            completed = true;
            for k = 1:nSteps
                if state.animGen ~= myGen, completed = false; break; end
                state.config = qTraj(:, k)';
                updateKinView();
                drawnow limitrate;
            end
            if completed, state.config = qTo; end
            state.animating = false;
        end

        function onIKSlider()
            x     = ikSliders(1).Value;
            y     = ikSliders(2).Value;
            z     = ikSliders(3).Value;
            roll  = deg2rad(ikSliders(4).Value);
            pitch = deg2rad(ikSliders(5).Value);
            yaw   = deg2rad(ikSliders(6).Value);

            ikValLbls(1).Text = sprintf('%.3f', x);
            ikValLbls(2).Text = sprintf('%.3f', y);
            ikValLbls(3).Text = sprintf('%.3f', z);
            ikValLbls(4).Text = sprintf('%.0f', rad2deg(roll));
            ikValLbls(5).Text = sprintf('%.0f', rad2deg(pitch));
            ikValLbls(6).Text = sprintf('%.0f', rad2deg(yaw));

            Ttgt = eul2tform([yaw pitch roll], 'ZYX');
            Ttgt(1:3, 4) = [x; y; z];

            gik = generalizedInverseKinematics('RigidBodyTree', robot, ...
                'ConstraintInputs', {'pose', 'joint'});
            gik.SolverParameters.MaxIterations = 400;
            gik.SolverParameters.MaxTime = 1.0;
            poseCon = constraintPoseTarget('ee');
            poseCon.TargetTransform = Ttgt;
            jointCon = constraintJointBounds(robot);

            qOld = state.config;
            [qSol, solInfo] = gik(qOld, poseCon, jointCon);

            if strcmp(solInfo.Status, 'success')
                state.ikOK = true;
                kinStatusLbl.Text = sprintf('IK solved (%d iter) — animating...', solInfo.Iterations);
                kinStatusLbl.FontColor = [0.0 0.55 0.0];
                animateTransition(qOld, qSol);
                syncFKSlidersFromConfig();
                updateEEPose();
                updateKinView();
                kinStatusLbl.Text = sprintf('IK solved (%d iterations).', solInfo.Iterations);
            else
                state.ikOK = false;
                kinStatusLbl.Text = sprintf('IK: %s — unreachable.', solInfo.Status);
                kinStatusLbl.FontColor = [0.85 0.25 0.0];
                updateEEPose();
                updateKinView();
            end
        end

        function animateTransition(qFrom, qTo)
            state.animGen = state.animGen + 1;
            myGen = state.animGen;
            state.animating = true;
            steps = 25;
            tvec = linspace(0, 1, steps);
            [qTraj, ~, ~] = cubicpolytraj([qFrom', qTo'], [0 1], tvec);
            completed = true;
            for k = 1:steps
                if state.animGen ~= myGen, completed = false; break; end
                state.config = qTraj(:, k)';
                updateKinView();
                drawnow limitrate;
            end
            if completed, state.config = qTo; end
            state.animating = false;
        end

        % ========================= HELPERS ===========================

        function syncFKSlidersFromConfig()
            for k = 1:7
                fkSliders(k).Value = state.config(k);
                fkVals(k).Text = sprintf('%.1f', rad2deg(state.config(k)));
            end
        end

        function syncIKSlidersFromEE()
            T = getTransform(robot, state.config, 'ee');
            eul = rotm2eul(T(1:3,1:3), 'ZYX');
            ikSliders(1).Value = T(1,4);
            ikSliders(2).Value = T(2,4);
            ikSliders(3).Value = T(3,4);
            ikSliders(4).Value = rad2deg(eul(3));
            ikSliders(5).Value = rad2deg(eul(2));
            ikSliders(6).Value = rad2deg(eul(1));
            for k = 1:6
                ikValLbls(k).Text = fmtslider(k, ikSliders(k).Value);
            end
        end

        function s = fmtslider(k, v)
            if k <= 3, s = sprintf('%.3f', v); else, s = sprintf('%.0f', v); end
        end

        function updateEEPose()
            T = getTransform(robot, state.config, 'ee');
            eul = rad2deg(rotm2eul(T(1:3,1:3), 'ZYX'));
            posFields(1).Text = sprintf('%.3f', T(1,4));
            posFields(2).Text = sprintf('%.3f', T(2,4));
            posFields(3).Text = sprintf('%.3f', T(3,4));
            oriFields(1).Text = sprintf('%.1f', eul(3));
            oriFields(2).Text = sprintf('%.1f', eul(2));
            oriFields(3).Text = sprintf('%.1f', eul(1));
        end

        function updateKinView()
            T = getTransform(robot, state.config, 'ee');
            show(robot, state.config, 'Visuals', 'on', 'Collisions', 'off', ...
                 'PreservePlot', false, 'Parent', ax);
            restoreLighting();
            if strcmp(state.kinMode, 'FK')
                tstr = 'Forward Kinematics';
            else
                tstr = 'Inverse Kinematics';
            end
            title(ax, sprintf('7-Axis Robotic Arm  —  %s', tstr), ...
                  'FontSize', 12, 'FontWeight', 'bold');
            subtitle(ax, sprintf('EE: [%.3f  %.3f  %.3f] m', ...
                    T(1,4), T(2,4), T(3,4)));
            axis(ax, 'equal');  grid(ax, 'on');
        end

        % Tab-refresh entry point (called on tab switch)
        function refreshExploreTab()
            cla(ax);  % 清掉 Plan 标签残留的路径点和轨迹线
            if strcmp(state.kinMode, 'FK')
                syncFKSlidersFromConfig();
            else
                syncIKSlidersFromEE();
            end
            updateEEPose();
            updateKinView();
        end

        % Store refresh handle on the tab for the switch handler
        tab.UserData = @refreshExploreTab;
    end

% ╔══════════════════════════════════════════════════════════════════╗
% ║  TAB 2 — PLAN / 轨迹规划  (waypoint editor + trajectory sim)     ║
% ╚══════════════════════════════════════════════════════════════════╝
    function buildPlanTab(tab)
        % ── Default waypoints ─────────────────────────────────────
        T_home = getTransform(robot, homeCfg, 'ee');
        defaultWP = [...
             0.00,  0.00, T_home(3,4);
             0.20,  0.15, 0.55;
             0.20,  0.15, 0.38;
             0.20,  0.15, 0.60;
            -0.15, -0.20, 0.60;
            -0.15, -0.20, 0.42;
            -0.15, -0.20, 0.65;
             0.00,  0.00, T_home(3,4)];

        % 6-row layout
        planGrid = uigridlayout(tab, [6 1], ...
            'RowHeight', {240, 'fit', 'fit', 'fit', 52, 24}, ...
            'Padding', [4 4 4 4], 'RowSpacing', 5);

        % ── 1. Waypoints ──────────────────────────────────────────
        pWP = uipanel(planGrid, 'Title', '1. Waypoints / 路径点  (X Y Z in meters)', ...
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

        % ── 2. IK Settings ────────────────────────────────────────
        pIK = uipanel(planGrid, 'Title', '2. IK Settings / 逆运动学设置', ...
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

        % ── 3. Trajectory Method ──────────────────────────────────
        pTraj = uipanel(planGrid, 'Title', '3. Trajectory Method / 轨迹规划方法', ...
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

        % ── 4. Advanced Parameters ────────────────────────────────
        pAdv = uipanel(planGrid, 'Title', '4. Advanced Parameters / 高级参数', ...
                       'FontWeight', 'bold');
        pAdv.Layout.Row = 4;
        gAdv = uigridlayout(pAdv, [1 2], 'ColumnWidth', {90, '1x'}, ...
                            'RowHeight', {28}, 'Padding', [5 5 5 5], ...
                            'RowSpacing', 4, 'ColumnSpacing', 6);

        uilabel(gAdv, 'Text', 'Peak Vel (rad/s):', 'HorizontalAlignment', 'right');
        peakVelFld = uieditfield(gAdv, 'numeric', 'Value', 0, ...
            'Limits', [0 100], 'ValueDisplayFormat', '%.2f', ...
            'Tooltip', '0 = auto (MATLAB default). Nonzero = max joint velocity (rad/s).');
        peakVelFld.Layout.Row = 1;  peakVelFld.Layout.Column = 2;

        % ── 5. Run / Stop ─────────────────────────────────────────
        btnRow = uigridlayout(planGrid, [1 2], 'ColumnWidth', {'2x','1x'}, ...
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

        % ── 6. Status ─────────────────────────────────────────────
        trajStatusLbl = uilabel(planGrid, 'Text', 'Ready — set waypoints and click Run.', ...
            'FontColor', [0.4 0.4 0.4], 'FontSize', 10);
        trajStatusLbl.Layout.Row = 6;

        % ========================= CALLBACKS =========================

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
                trajStatusLbl.Text = 'Need at least 2 waypoints.';
                trajStatusLbl.FontColor = [0.85 0.3 0.0];
                return;
            end
            data(end, :) = [];
            wpTable.Data = data;
        end

        function resetWP()
            wpTable.Data = defaultWP;
        end

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

        function stopSimulation()
            state.animGen = state.animGen + 1;
            runBtn.Enable = 'on';
            stopBtn.Enable = 'off';
            trajStatusLbl.Text = 'Stopped by user.';
            trajStatusLbl.FontColor = [0.85 0.3 0.0];
        end

        function finishRun()
            runBtn.Enable = 'on';
            stopBtn.Enable = 'off';
        end

        function runSimulation()
            wpData = wpTable.Data;
            numWP = size(wpData, 1);
            if numWP < 2
                trajStatusLbl.Text = 'Need at least 2 waypoints.';
                trajStatusLbl.FontColor = [0.85 0.3 0.0];
                return;
            end
            wpPos = wpData';

            usePose = strcmp(ikModeDD.Value, 'Position + Orientation');
            maxIter = ikIters.Value;
            method  = methodDD.Value;
            T_total = endTimeFld.Value;
            N_samp  = numSmpFld.Value;
            pkVel   = peakVelFld.Value;

            runBtn.Enable = 'off';
            stopBtn.Enable = 'on';
            state.animGen = state.animGen + 1;
            myGen = state.animGen;

            % --- Solve IK ---
            trajStatusLbl.Text = sprintf('Solving IK for %d waypoints...', numWP);
            trajStatusLbl.FontColor = [0.0 0.45 0.7];
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

            jointWP = zeros(7, numWP);
            qCurrent = state.config;  % start from current config

            for i = 1:numWP
                if usePose
                    tgtCon.TargetTransform = trvec2tform(wpPos(:, i)');
                else
                    tgtCon.TargetPosition = wpPos(:, i);
                end
                [qSol, solInfo] = gik(qCurrent, tgtCon, jointCon);

                if ~strcmp(solInfo.Status, 'success')
                    trajStatusLbl.Text = sprintf('IK failed at WP%d: %s', i, solInfo.Status);
                    trajStatusLbl.FontColor = [0.85 0.25 0.0];
                    finishRun();
                    return;
                end
                jointWP(:, i) = qSol';
                qCurrent = qSol;
            end

            if state.animGen ~= myGen, finishRun(); return; end

            % --- Generate trajectory ---
            trajStatusLbl.Text = 'Generating trajectory...';
            drawnow;
            try
                [qTraj, qdTraj, qddTraj, tVec] = generateTrajectory(jointWP, method, T_total, N_samp, pkVel);
            catch ME
                trajStatusLbl.Text = sprintf('Trajectory error: %s', ME.message);
                trajStatusLbl.FontColor = [0.85 0.25 0.0];
                finishRun();
                return;
            end

            totalPts = size(qTraj, 2);
            if state.animGen ~= myGen, finishRun(); return; end

            % --- Pre-compute EE path & actual waypoint EE positions ---
            eePath = zeros(3, totalPts);
            for k = 1:totalPts
                T = getTransform(robot, qTraj(:, k)', 'ee');
                eePath(:, k) = T(1:3, 4);
            end
            % IK 实际解出的关节角对应的 EE 位置（一定在轨迹线上）
            wpEE = zeros(3, numWP);
            for i = 1:numWP
                T = getTransform(robot, jointWP(:, i)', 'ee');
                wpEE(:, i) = T(1:3, 4);
            end

            % --- Draw ---
            cla(ax);
            show(robot, qTraj(:, 1)', 'Visuals', 'on', 'Collisions', 'off', ...
                 'PreservePlot', false, 'Parent', ax, 'FastUpdate', true);
            hold(ax, 'on');
            plot3(ax, eePath(1, :), eePath(2, :), eePath(3, :), ...
                  'g-', 'LineWidth', 1.5);
            scatter3(ax, wpEE(1, :), wpEE(2, :), wpEE(3, :), ...
                     80, 'r', 'filled', 'MarkerEdgeColor', 'k');
            title(ax, sprintf('7-Axis Robotic Arm — %s', extractMethodName(method)), ...
                  'FontSize', 12, 'FontWeight', 'bold');
            axis(ax, 'equal');
            xlim(ax, [-0.9 0.9]);  ylim(ax, [-0.9 0.9]);  zlim(ax, [-0.1 1.0]);
            grid(ax, 'on');
            restoreLighting();

            if state.animGen ~= myGen, finishRun(); return; end

            % --- Animate ---
            trajStatusLbl.Text = sprintf('Playing %d frames...', totalPts);
            trajStatusLbl.FontColor = [0.0 0.55 0.0];
            drawnow;

            for frame = 1:totalPts
                if state.animGen ~= myGen
                    finishRun();
                    return;
                end
                show(robot, qTraj(:, frame)', 'Visuals', 'on', 'Collisions', 'off', ...
                     'PreservePlot', false, 'Parent', ax, 'FastUpdate', true);
                title(ax, sprintf('7-Axis Robotic Arm — %s  |  t = %.1f / %.1f s', ...
                      extractMethodName(method), tVec(min(frame, end)), tVec(end)), ...
                      'FontSize', 12, 'FontWeight', 'bold');
                drawnow;
                pause(0.02);
            end

            % --- Cache trajectory data for tab-switch redraw ---
            state.trajData.eePath = eePath;
            state.trajData.wpPos  = wpEE;    % 用 IK 实际解出的位置，不用表格目标值
            state.trajData.method = extractMethodName(method);
            % Update shared config to final frame
            state.config = qTraj(:, end)';

            finishRun();

            % --- Summary ---
            eeDist = sum(sqrt(sum(diff(eePath, 1, 2).^2, 1)));
            trajStatusLbl.Text = sprintf(...
                'Done. %d WPs, %d frames, %.1f s, EE path = %.3f m  |  Method: %s', ...
                numWP, totalPts, tVec(end), eeDist, extractMethodName(method));
            trajStatusLbl.FontColor = [0.0 0.4 0.0];

            % --- Popup: joint profiles ---
            plotJointProfiles(qTraj, qdTraj, qddTraj, tVec, extractMethodName(method));
        end

        function plotJointProfiles(q, qd, qdd, tv, methodName)
            % 弹窗显示各关节角度/角速度/角加速度曲线
            jointNames = {'J1 腰', 'J2 肩', 'J3 臂滚', 'J4 肘', 'J5 前臂', 'J6 腕', 'J7 工具'};
            colors = lines(7);

            figProf = figure('Name', sprintf('关节曲线 — %s', methodName), ...
                             'Position', [100 60 1100 780], 'Color', 'w');

            % 关节角度（deg）
            ax1 = subplot(3, 1, 1);
            hold(ax1, 'on');  grid(ax1, 'on');
            for j = 1:7
                plot(ax1, tv, rad2deg(q(j, :)), 'Color', colors(j,:), 'LineWidth', 1.2);
            end
            ylabel(ax1, '角度 (deg)', 'FontSize', 10);
            title(ax1, sprintf('关节角度 — %s', methodName), 'FontSize', 13, 'FontWeight', 'bold');
            legend(ax1, jointNames, 'Location', 'bestoutside', 'FontSize', 8);
            xlim(ax1, [tv(1) tv(end)]);

            % 角速度（deg/s）
            ax2 = subplot(3, 1, 2);
            hold(ax2, 'on');  grid(ax2, 'on');
            for j = 1:7
                plot(ax2, tv, rad2deg(qd(j, :)), 'Color', colors(j,:), 'LineWidth', 1.2);
            end
            ylabel(ax2, '角速度 (deg/s)', 'FontSize', 10);
            title(ax2, '关节角速度', 'FontSize', 13, 'FontWeight', 'bold');
            legend(ax2, jointNames, 'Location', 'bestoutside', 'FontSize', 8);
            xlim(ax2, [tv(1) tv(end)]);

            % 角加速度（deg/s²）
            ax3 = subplot(3, 1, 3);
            hold(ax3, 'on');  grid(ax3, 'on');
            for j = 1:7
                plot(ax3, tv, rad2deg(qdd(j, :)), 'Color', colors(j,:), 'LineWidth', 1.2);
            end
            xlabel(ax3, '时间 (s)', 'FontSize', 10);
            ylabel(ax3, '角加速度 (deg/s^2)', 'FontSize', 10);
            title(ax3, '关节角加速度', 'FontSize', 13, 'FontWeight', 'bold');
            legend(ax3, jointNames, 'Location', 'bestoutside', 'FontSize', 8);
            xlim(ax3, [tv(1) tv(end)]);

            sgtitle(sprintf('7-Axis Robot Arm — Joint Profiles (%s)', methodName), ...
                    'FontSize', 16, 'FontWeight', 'bold');
        end

        function [q, qd, qdd, tv] = generateTrajectory(wpts, method, Ttot, Nseg, pkv)
            numWPs = size(wpts, 2);
            if startsWith(method, 'trapveltraj')
                opts = {'EndTime', Ttot};
                if pkv > 0, opts = [opts, {'PeakVelocity', pkv}]; end
                [q, qd, qdd, tv] = trapveltraj(wpts, Nseg, opts{:});
            elseif startsWith(method, 'cubicpolytraj')
                tWPs = linspace(0, Ttot, numWPs);
                tv   = linspace(0, Ttot, Nseg * numWPs);
                [q, qd, qdd] = cubicpolytraj(wpts, tWPs, tv);
            elseif startsWith(method, 'quinticpolytraj')
                tWPs = linspace(0, Ttot, numWPs);
                tv   = linspace(0, Ttot, Nseg * numWPs);
                [q, qd, qdd] = quinticpolytraj(wpts, tWPs, tv);
            elseif startsWith(method, 'bsplinepolytraj')
                tv = linspace(0, Ttot, Nseg * numWPs);
                [q, qd, qdd] = bsplinepolytraj(wpts, [0 Ttot], tv);
            else
                error('Unknown trajectory method.');
            end
            if iscolumn(tv), tv = tv'; end
        end

        function name = extractMethodName(method)
            parts = strsplit(method, ' (');
            name = parts{1};
        end

        % ========================= PLAN TAB VIEW REFRESH =============

        function refreshPlanTab()
            cla(ax);
            if ~isempty(state.trajData.eePath)
                % Re-draw last trajectory
                show(robot, state.config, 'Visuals', 'on', 'Collisions', 'off', ...
                     'PreservePlot', false, 'Parent', ax);
                hold(ax, 'on');
                plot3(ax, state.trajData.eePath(1, :), ...
                         state.trajData.eePath(2, :), ...
                         state.trajData.eePath(3, :), ...
                      'g-', 'LineWidth', 1.5);
                scatter3(ax, state.trajData.wpPos(1, :), ...
                            state.trajData.wpPos(2, :), ...
                            state.trajData.wpPos(3, :), ...
                         80, 'r', 'filled', 'MarkerEdgeColor', 'k');
                title(ax, sprintf('7-Axis Robotic Arm — %s (last run)', ...
                      state.trajData.method), 'FontSize', 12, 'FontWeight', 'bold');
            else
                show(robot, state.config, 'Visuals', 'on', 'Collisions', 'off', ...
                     'PreservePlot', false, 'Parent', ax);
                title(ax, '7-Axis Robotic Arm', 'FontSize', 12, 'FontWeight', 'bold');
            end
            axis(ax, 'equal');
            xlim(ax, [-0.9 0.9]);  ylim(ax, [-0.9 0.9]);  zlim(ax, [-0.1 1.0]);
            grid(ax, 'on');
            restoreLighting();
        end

        % Store refresh handle on the tab for the switch handler
        tab.UserData = @refreshPlanTab;

        % Init
        updateMethodUI();
    end

% ═══════════════════════════════════════════════════════════════════
%  INIT
% ═══════════════════════════════════════════════════════════════════
% Initial render already done above; figure is ready

end
