%% run_tests.m — Validation tests for 6-axis robotic arm
clear; close all;
fprintf('========================================\n');
fprintf('  6-Axis Robotic Arm — Test Suite\n');
fprintf('========================================\n\n');

robot = build_6axis_arm();
robot.DataFormat = 'row';
home = zeros(1, 6);
pass = 0;
fail = 0;

% ── Test 1: Model structure ──────────────────────────────────
fprintf('Test 1: Model structure... ');
try
    assert(robot.NumBodies == 8);
    expected = {'pedestal','link1','link2','link3','link4','link5','link6','ee'};
    assert(isequal(robot.BodyNames, expected));
    fprintf('PASS (%d bodies)\n', robot.NumBodies);
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Test 2: FK at home ───────────────────────────────────────
fprintf('Test 2: FK at home... ');
try
    T = getTransform(robot, home, 'ee');
    pos = T(1:3,4);
    assert(abs(pos(1)) < 1e-6 && abs(pos(2)) < 1e-6);
    assert(abs(pos(3) - 0.87) < 0.02);
    fprintf('PASS (EE at [%.3f %.3f %.3f])\n', pos);
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Test 3: FK consistency (random configs) ──────────────────
fprintf('Test 3: FK consistency... ');
try
    rng(123);
    for k = 1:10
        q = randomConfiguration(robot);
        T = getTransform(robot, q, 'ee');
        assert(abs(det(T(1:3,1:3)) - 1) < 1e-6);
    end
    fprintf('PASS (10 random configs)\n');
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Test 4: Jacobian rank ────────────────────────────────────
fprintf('Test 4: Jacobian... ');
try
    qBent = [0, -pi/6, -pi/3, 0, -pi/6, 0];
    J = geometricJacobian(robot, qBent, 'ee');
    assert(isequal(size(J), [6 6]));
    assert(rank(J) == 6);
    fprintf('PASS (6x6, rank 6)\n');
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Test 5: IK ───────────────────────────────────────────────
fprintf('Test 5: Inverse kinematics... ');
try
    gik = generalizedInverseKinematics('RigidBodyTree', robot, ...
        'ConstraintInputs', {'position', 'joint'});
    posCon = constraintPositionTarget('ee');
    jointCon = constraintJointBounds(robot);

    % Home → home
    T_home = getTransform(robot, home, 'ee');
    posCon.TargetPosition = T_home(1:3,4);
    [qSol, solInfo] = gik(home, posCon, jointCon);
    assert(strcmp(solInfo.Status, 'success'));
    assert(norm(qSol) < 1e-3);

    % Random targets
    rng(456);
    for k = 1:5
        qStart = randomConfiguration(robot);
        Ttgt = getTransform(robot, qStart, 'ee');
        Ttgt(1,4) = Ttgt(1,4) + 0.02;
        Ttgt(3,4) = max(0.3, min(0.8, Ttgt(3,4)));
        posCon.TargetPosition = Ttgt(1:3,4);
        [qs2, si2] = gik(home, posCon, jointCon);
        assert(strcmp(si2.Status, 'success'));
        Tchk = getTransform(robot, qs2, 'ee');
        assert(norm(Tchk(1:3,4) - Ttgt(1:3,4)) < 0.01);
    end
    fprintf('PASS (home+5 random targets)\n');
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Test 6: Joint limits ─────────────────────────────────────
fprintf('Test 6: Joint limits... ');
try
    for i = 1:6
        body = robot.Bodies{i+1};
        lim = body.Joint.PositionLimits;
        assert(lim(1) < lim(2));
        assert(lim(2) - lim(1) > 0.5);
    end
    fprintf('PASS (all 6 joints valid)\n');
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Test 7: Self-collision ───────────────────────────────────
fprintf('Test 7: Self-collision... ');
try
    [inCol, ~] = checkCollision(robot, home, 'SkippedSelfCollisions', 'parent');
    assert(~inCol);
    fprintf('PASS (home OK)\n');
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Test 8: Trajectory ───────────────────────────────────────
fprintf('Test 8: Trajectory generation... ');
try
    wpts = [home', home'+[0.2;0;0.1;0;0;0], home'];
    [qTraj, qdTraj] = trapveltraj(wpts, 50, 'EndTime', 2);
    assert(isequal(size(qTraj), [6 50]));
    assert(norm(qTraj(:,1) - home') < 1e-6);
    assert(norm(qTraj(:,end) - home') < 1e-6);
    fprintf('PASS (50 samples, start/end match)\n');
    pass = pass + 1;
catch ME
    fprintf('FAIL: %s\n', ME.message);
    fail = fail + 1;
end

% ── Results ──────────────────────────────────────────────────
fprintf('\n========================================\n');
fprintf('  Results: %d passed, %d failed\n', pass, fail);
fprintf('========================================\n');
