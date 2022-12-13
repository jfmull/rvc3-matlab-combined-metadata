%% RVC3: Chapter 6 (Localization)
format compact
close all
clear
clc

%% 6.1 - Dead Reckoning Odometry
%% 6.1.1 - Modeling the Robot
V = diag([0.02 deg2rad(0.5)].^2);

robot = BicycleVehicle(Covariance=V)

rng(0) % obtain repeatable results
odo = robot.step(1,0.3)

robot.q'  % transpose for display
robot.f([0 0 0],odo)

robot.addDriver(RandomDriver([-10 10 -10 10]))
robot.run(100);


%% 6.1.2 - Estimating Pose
robot.Fx([0 0 0],[0.5 0.1])
P0 = diag([0.05 0.05 deg2rad(0.5)].^2);

ekf = EKF(robot,V,P0);
rng(0) % obtain repeatable results
ekf.run(400);

clf
robot.plotxy
hold on
ekf.plotxy

P150 = ekf.history(150).P
sqrt(P150(1,1))
ekf.plotellipse(fillcolor="g",alpha=0.3)

clf
ekf.plotP;

%% 6.2 - Landmark Maps
%% 6.2.1 - Localizing in a Landmark Map
rng(0) % obtain repeatable results
map = LandmarkMap(20,10)
map.plot

W = diag([0.1 deg2rad(1)].^2);
sensor = LandmarkSensor(robot,map,covar=W, ...
  range=10,angle=[-pi/2 pi/2]);

[z,i] = sensor.reading
map.landmark(14)

rng(0) % obtain repeatable results
map = LandmarkMap(20,10);
V = diag([0.02 deg2rad(0.5)].^2);
robot = BicycleVehicle(Covariance=V);
robot.addDriver(RandomDriver(map.dim));
sensor = LandmarkSensor(robot,map,covar=W, ...
  range=4,angle=[-pi/2 pi/2],animate=true);
P0 = diag([0.05 0.05 deg2rad(0.5)].^2);
ekf = EKF(robot,V,P0,sensor,W,map);
ekf.run(400)

clf
map.plot
robot.plotxy("b");
ekf.plotxy("r");
ekf.plotellipse(fillcolor="g",alpha=0.3)

%% 6.2.2 - Creating a Landmark Map
rng(0) % obtain repeatable results
map = LandmarkMap(20,10);
robot = BicycleVehicle; % error free vehicle
robot.addDriver(RandomDriver(map.dim));
W = diag([0.1 deg2rad(1)].^2);
sensor = LandmarkSensor(robot,map,covar=W);
ekf = EKF(robot,[],[],sensor,W,[]);

ekf.run(1000);

map.plot;
ekf.plotmap("g");
robot.plotxy("b");
ekf.landmarks(:,17)'  % transpose for display
ekf.x_est(1:2)'  % transpose for display
ekf.P_est(1:2,1:2)

%% 6.2.3 - EKF SLAM
rng(0) % obtain repeatable results
map = LandmarkMap(20,10);
V = diag([0.1 deg2rad(1)].^2);
robot = BicycleVehicle(covar=V, q0=[3 6 deg2rad(-45)]);
robot.addDriver(RandomDriver(map.dim));
W = diag([0.1 deg2rad(1)].^2);
sensor = LandmarkSensor(robot,map,covar=W);
P0 = diag([0.05 0.05 deg2rad(0.5)].^2);
ekf = EKF(robot,V,P0,sensor,W,[]);

ekf.run(500,x_est0=[0 0 0]);

clf
map.plot;           % plot true map
robot.plotxy("b"); % plot true path

clf
ekf.plotmap("g");  % plot estimated landmarks + covariances
ekf.plotxy("r");   % plot estimated robot path

T = ekf.transform(map)


%% 6.2.4 - Sequential Monte-Carlo Localization
rng(0) % obtain repeatable results
map = LandmarkMap(20,10);
V = diag([0.1 deg2rad(1)].^2)
robot = BicycleVehicle(covar=V);
robot.addDriver(RandomDriver(10));

W = diag([0.02 deg2rad(0.5)].^2);
sensor = LandmarkSensor(robot,map,covar=W);

Q = diag([0.1 0.1 deg2rad(1)]).^2;

L = diag([0.1 0.1]);

pf = ParticleFilter(robot,sensor,Q,L,1000);
pf.run(1000);

map.plot;
robot.plotxy("b--");

pf.plotxy("r");

plot(1:100,abs(pf.std(1:100,:)))

pf.plotpdf

%% 6.2.5 - Rao-Blackwellized SLAM

%% 6.3 - Occupancy Grid Maps
%% 6.3.1 - Application: Lidar
%% 6.3.2 - Lidar-based Odometry
[~,lidarData,lidarTimes,odoTruth] = g2oread("killian.g2o");
whos lidarData

p100 = lidarData(100)
p100.plot

p131 = lidarData(131);
p133 = lidarData(133);

pose = matchScans(p133,p131)
pose = matchScans(p133,p131,InitialPose=[1 0 0])
seconds(lidarTimes(133)-lidarTimes(131))
pose = matchScansGrid(p133,p131)
timeit(@() matchScansGrid(p133,p131)) / ...
  timeit(@() matchScans(p133,p131))

%% 6.3.3 - Lidar-based Map Building
cellSize = 0.1; maxRange = 40;

og = occupancyMap(10,10,1/cellSize, ...
  LocalOriginInWorld=[0 -5]);
og.insertRay([0 0 0],p131,maxRange)
og.insertRay(pose,p133,maxRange)

og.show; view(-90,90)

omap = buildMap(num2cell(lidarData),odoTruth,1/cellSize,maxRange);
omap.show

%% 6.3.4 - Lidar-based Localization
mcl = monteCarloLocalization(UseLidarScan=true)

motion = mcl.MotionModel;
motion.Noise = [0.2 0.2 0.1 0.1];
motion.showNoiseDistribution(OdometryPoseChange=[0.5 0.2 pi/4]);

sensor = mcl.SensorModel;
sensor.Map = omap

rng(0) % obtain repeatable results
mcl.GlobalLocalization = 1;
mcl.ParticleLimits = [500 20000];

[isUpdated,pose,covar] = mcl(odoTruth(100,:),lidarData(100))
mp = mclPlot(omap);
mp.plot(mcl,pose,odoTruth(100,:),lidarData(100));

for i = 101:150
  [isUpdated, pose] = mcl(odoTruth(i,:),lidarData(i));
  mp.plot(mcl,pose,odoTruth(i,:),lidarData(i));
end

%% 6.3.5 - Simulating Lidar Sensors
lidar = rangeSensor
lidar.Range = [0 50];
lidar.HorizontalAngle = deg2rad([-90 90]);
lidar.HorizontalAngleResolution = deg2rad(1);

[ranges,angles] = lidar(odoTruth(131,:),omap);
clf
lidarScan(ranges,angles).plot
hold on
lidarData(131).plot

%% 6.4 - Pose-Graph SLAM
syms xi yi ti xj yj tj xm ym tm assume real
xi_e = inv(tform2d(xm,ym,tm))*inv(tform2d(xi,yi,ti)) * ...
  tform2d(xj,yj,tj);
xyt = [xi_e(1,3); xi_e(2,3); ...
  atan2(xi_e(2,1),xi_e(1,1))]; % Extract [x;y;theta] vector
fk = simplify(xyt);

Ai = simplify(jacobian(fk,[xi yi ti]))
size(Ai)

pg = g2oread("pg1.g2o")
pg.nodeEstimates
pg.show(IDs="nodes");

pgopt = optimizePoseGraph(pg,VerboseOutput="on");

pg = tororead("killian-small.toro")
pg.show(IDs="off");

pgopt = optimizePoseGraph(pg,"g2o-levenberg-marquardt",VerboseOutput="on");
pgopt = optimizePoseGraph(pg,"g2o-levenberg-marquardt", ...
  FirstNodePose=[-50 20 deg2rad(95)]);
pgopt.show(IDs="off");

%% 6.4.1 - Pose Graph Landmark SLAM
openExample("nav/LandmarkSLAMUsingAprilTagMarkersExample")

%% 6.4.2 - Pose-Graph Lidar SLAM
load("offlineSlamData.mat","scans");
maxLidarRange = 9;  % meters
mapResolution = 20; % cells per meter, cell size = 5 cm
slam = lidarSLAM(mapResolution,maxLidarRange)

slam.LoopClosureThreshold = 200;  
slam.LoopClosureSearchRadius = 8;

for i = 1:70
  slam.addScan(scans{i});
end
clf
slam.show;

[scansAtPoses, optimizedPoses] = slam.scansAndPoses;
map = buildMap(scansAtPoses,optimizedPoses,mapResolution,maxLidarRange);
map.show;

pg = slam.PoseGraph;
pg.show;
figure; plot(pg.edgeResidualErrors)

pgwrong = pg.copy;
[~,id] = pgwrong.addRelativePose([0 0 0],[1 0 0 1 0 1],59,44)
pgwrongopt = optimizePoseGraph(pgwrong);
pgwrongopt.show;
figure; plot(pgwrongopt.edgeResidualErrors)

trimParams.TruncationThreshold = 2;
trimParams.MaxIterations = 10;
[pgFixed,trimInfo] = trimLoopClosures(pgwrongopt,trimParams,poseGraphSolverOptions);
trimInfo


