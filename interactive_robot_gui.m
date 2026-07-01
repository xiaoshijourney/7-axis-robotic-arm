function interactive_robot_gui()
%% INTERACTIVE_ROBOT_GUI  6-axis robot kinematics demo with dual-mode sliders.
%
%  FK Mode : 6 joint-angle sliders → live 3D view + end-effector pose
%  IK Mode : XYZ position sliders → auto-solve joint angles → live 3D view

% ── Build robot ───────────────────────────────────────────────────
robot = build_6axis_arm();
robot.DataFormat = 'row';
homeCfg = zeros(1, 6);

% ── Shared state ──────────────────────────────────────────────────
state.mode      = 'FK';
state.config    = homeCfg;      % currently displayed joint config
state.targetCfg = homeCfg;      % slider target (may differ during drag)
state.ikOK      = true;
state.animating = false;        % true during transition animation
state.animGen   = 0;            % incremented each new animation request

% Debounce timer: only redraw when user pauses dragging (reduces overhead)
debounceTimer = timer('ExecutionMode', 'singleShot', ...
                      'StartDelay', 0.08, ...
                      'TimerFcn', @(~,~) debounceUpdate());

% ── Figure ────────────────────────────────────────────────────────
fig = uifigure('Name', '6-Axis Robot Arm — Interactive Kinematics', ...
               'Position', [40 40 1200 750], 'Resize', 'on');
fig.CloseRequestFcn = @(~,~) cleanup();

% ── Main layout ───────────────────────────────────────────────────
mainGrid = uigridlayout(fig, [1 2], ...
                        'ColumnWidth', {'3x', '2x'}, ...
                        'Padding', [6 6 6 6], 'ColumnSpacing', 6);

% ── Left: 3D view ─────────────────────────────────────────────────
viewPanel = uipanel(mainGrid, 'BorderType', 'none');
ax = axes(viewPanel);
title(ax, '6-Axis Robotic Arm', 'FontSize', 12, 'FontWeight', 'bold');
axis(ax, 'equal');  grid(ax, 'on');
view(ax, [40 28]);  hold(ax, 'on');

% ── Lighting (two-point + ambient for 3D depth perception) ────────
light(ax, 'Position', [3 2 4], 'Style', 'infinite');
light(ax, 'Position', [-2 -1 -0.5], 'Style', 'infinite');
lighting(ax, 'gouraud');
material(ax, [0.5 0.5 0.4 20]);  % [ambient diffuse specular shininess]

% ── Right: control stack ──────────────────────────────────────────
ctrlGrid = uigridlayout(mainGrid, [4 1], ...
                        'RowHeight', {'fit', '1x', 'fit', 'fit'}, ...
                        'Padding', [0 0 0 0], 'RowSpacing', 5);
ctrlGrid.ColumnWidth = {'1x'};

% ── Row 1: Mode toggle ────────────────────────────────────────────
modePanel = uipanel(ctrlGrid, 'Title', 'Mode / 模式', 'FontWeight', 'bold');
modePanel.Layout.Row = 1;
modeSub = uigridlayout(modePanel, [1 2], 'Padding', [5 5 5 5], 'ColumnSpacing', 5);
fkBtn = uibutton(modeSub, 'state', 'Text', 'FK 正运动学', 'Value', true, ...
                 'FontSize', 11, 'FontWeight', 'bold');
ikBtn = uibutton(modeSub, 'state', 'Text', 'IK 逆运动学', ...
                 'FontSize', 11, 'FontWeight', 'bold');

% ── Row 2: FK slider panel ────────────────────────────────────────
fkPanel = uipanel(ctrlGrid, 'Title', 'Joint Angles / 关节角度 (deg)', ...
                  'FontWeight', 'bold');
fkPanel.Layout.Row = 2;
fkGrid = uigridlayout(fkPanel, [6 3], ...
                      'ColumnWidth', {60, '1x', 42}, ...
                      'RowHeight', repmat({28}, 1, 6), ...
                      'Padding', [4 4 4 4], 'RowSpacing', 2, 'ColumnSpacing', 3);

jointNames = {'J1 腰', 'J2 肩', 'J3 肘', 'J4 前臂', 'J5 腕', 'J6 工具'};
fkSliders  = gobjects(1, 6);
fkVals     = gobjects(1, 6);

for i = 1:6
    lims = robot.Bodies{i+1}.Joint.PositionLimits;
    uilabel(fkGrid, 'Text', jointNames{i}, ...
            'HorizontalAlignment', 'right', 'FontSize', 9);
    sld = uislider(fkGrid, 'Limits', lims, 'Value', 0, ...
                   'MajorTicks', [], 'MinorTicks', []);
    sld.Layout.Row = i;  sld.Layout.Column = 2;
    idx = i;  % capture by value for anonymous function
    sld.ValueChangingFcn = @(src, evt) onFKDrag(idx, evt.Value);
    sld.ValueChangedFcn  = @(src, ~)   onFKRelease(idx, src.Value);
    fkSliders(i) = sld;

    vl = uilabel(fkGrid, 'Text', '0.0', ...
                 'HorizontalAlignment', 'left', 'FontSize', 9);
    vl.Layout.Row = i;  vl.Layout.Column = 3;
    fkVals(i) = vl;
end

% ── Row 2 (shared): IK slider panel ───────────────────────────────
ikPanel = uipanel(ctrlGrid, 'Title', 'Target Pose / 目标位姿', ...
                  'FontWeight', 'bold');
ikPanel.Layout.Row = 2;   % same row as FK — only one visible
ikGrid = uigridlayout(ikPanel, [6 3], ...
                      'ColumnWidth', {48, '1x', 50}, ...
                      'RowHeight', repmat({28}, 1, 6), ...
                      'Padding', [4 4 4 4], 'RowSpacing', 2, 'ColumnSpacing', 3);

ikLabels  = {'X (m)', 'Y (m)', 'Z (m)', 'Roll°', 'Pitch°', 'Yaw°'};
ikLimits  = [-0.75 0.75;  -0.75 0.75;  0.04 0.88;  -180 180;  -180 180;  -180 180];
ikStarts  = [ 0,      0,      0.87,   0,      0,      0];
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

% ── Row 3: EE pose display ────────────────────────────────────────
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

% ── Row 4: Status bar ─────────────────────────────────────────────
statusLbl = uilabel(ctrlGrid, 'Text', 'Ready — drag sliders to explore.', ...
                    'FontColor', [0.35 0.35 0.35], 'FontSize', 9);
statusLbl.Layout.Row = 4;

% ═══════════════════════════════════════════════════════════════════
%  CALLBACKS
% ═══════════════════════════════════════════════════════════════════

fkBtn.ValueChangedFcn = @(src, ~) modeToggle('FK', src.Value);
ikBtn.ValueChangedFcn = @(src, ~) modeToggle('IK', src.Value);

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
            statusLbl.Text = 'FK mode — drag joint sliders to see EE pose.';
        else
            fkBtn.Value = false;
            fkPanel.Visible = 'off';
            ikPanel.Visible = 'on';
            syncIKSlidersFromEE();
            statusLbl.Text = 'IK mode — drag XYZ sliders, joints auto-solve.';
        end
        state.mode = newMode;
        statusLbl.FontColor = [0.35 0.35 0.35];
        refreshAll();
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
            updateRobotView();
            drawnow limitrate;
        end
        if completed, state.config = qTo; end
        state.animating = false;
    end

    function onIKSlider()
        x = ikSliders(1).Value;
        y = ikSliders(2).Value;
        z = ikSliders(3).Value;
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
            statusLbl.Text = sprintf('IK solved (%d iter) — animating...', solInfo.Iterations);
            statusLbl.FontColor = [0.0 0.55 0.0];
            animateTransition(qOld, qSol);
            syncFKSlidersFromConfig();
            updateEEPose();
            updateRobotView();
            statusLbl.Text = sprintf('IK solved (%d iterations).', solInfo.Iterations);
        else
            state.ikOK = false;
            statusLbl.Text = sprintf('IK: %s — unreachable.', solInfo.Status);
            statusLbl.FontColor = [0.85 0.25 0.0];
            updateEEPose();
            updateRobotView();
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
            updateRobotView();
            drawnow limitrate;
        end
        if completed, state.config = qTo; end
        state.animating = false;
    end

% ═══════════════════════════════════════════════════════════════════
%  HELPERS
% ═══════════════════════════════════════════════════════════════════

    function syncFKSlidersFromConfig()
        for k = 1:6
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

    function updateRobotView()
        T = getTransform(robot, state.config, 'ee');
        show(robot, state.config, 'Visuals', 'on', 'Collisions', 'off', ...
             'PreservePlot', false, 'Parent', ax);
        if strcmp(state.mode, 'FK')
            tstr = 'Forward Kinematics';
        else
            tstr = 'Inverse Kinematics';
        end
        title(ax, sprintf('6-Axis Robotic Arm  —  %s', tstr), ...
              'FontSize', 12, 'FontWeight', 'bold');
        subtitle(ax, sprintf('EE: [%.3f  %.3f  %.3f] m', ...
                T(1,4), T(2,4), T(3,4)));
        axis(ax, 'equal');  grid(ax, 'on');
    end

    function refreshAll()
        updateEEPose();
        updateRobotView();
    end

    function cleanup()
        stop(debounceTimer);
        delete(debounceTimer);
        delete(fig);
    end

% ═══════════════════════════════════════════════════════════════════
%  INIT
% ═══════════════════════════════════════════════════════════════════
syncFKSlidersFromConfig();
updateEEPose();
show(robot, state.config, 'Visuals', 'on', 'Collisions', 'off', ...
     'PreservePlot', false, 'Parent', ax);
title(ax, '6-Axis Robotic Arm  —  Forward Kinematics', ...
      'FontSize', 12, 'FontWeight', 'bold');
subtitle(ax, 'EE: [0.000  0.000  0.870] m');
axis(ax, 'equal');  grid(ax, 'on');
view(ax, [40 28]);

end
