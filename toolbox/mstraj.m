%MSTRAJ Multi-segment multi-axis trajectory
%
% TRAJ = MSTRAJ(WP, QDMAX, TSEG, Q0, DT, TACC, OPTIONS) is a trajectory
% (KxN) for N axes moving simultaneously through M segment.  Each segment
% is linear motion and polynomial blends connect the segments.  The axes
% start at Q0 (1xN) and pass through M-1 via points defined by the rows of
% the matrix WP (MxN), and finish at the point defined by the last row of WP.
% The  trajectory matrix has one row per time step, and one column per
% axis.  The number of steps in the trajectory K is a function of the
% number of via points and the time or velocity limits that apply.
%
% - WP (MxN) is a matrix of via points, 1 row per via point, one column
%   per axis.  The last via point is the destination.
% - QDMAX (1xN) are axis speed limits which cannot be exceeded,
% - TSEG (1xM) are the durations for each of the K segments
% - Q0 (1xN) are the initial axis coordinates
% - DT is the time step
% - TACC (1x1) is the acceleration time used for all segment transitions
% - TACC (1xM) is the acceleration time per segment, TACC(i) is the acceleration
%   time for the transition from segment i to segment i+1.  TACC(1) is also
%   the acceleration time at the start of segment 1.
%
% TRAJ = MSTRAJ(WP, QDMAX, TSEG, [], DT, TACC, OPTIONS) as above but the
% initial coordinates are taken from the first row of WP.
%
% TRAJ = MSTRAJ(WP, QDMAX, Q0, DT, TACC, QD0, QDF, OPTIONS) as above
% but additionally specifies the initial and final axis velocities (1xN).
%
% Options::
% 'verbose'    Show details.
%
% Notes::
% - Only one of QDMAX or TSEG can be specified, the other is set to [].
% - If no output arguments are specified the trajectory is plotted.
% - The path length K is a function of the number of via points, Q0, DT
%   and TACC.
% - The final via point P(end,:) is the destination.
% - The motion has M segments from Q0 to P(1,:) to P(2,:) ... to P(end,:).
% - All axes reach their via points at the same time.
% - Can be used to create joint space trajectories where each axis is a joint
%   coordinate.
% - Can be used to create Cartesian trajectories where the "axes"
%   correspond to translation and orientation in RPY or Euler angle form.
% - If qdmax is a scalar then all axes are assumed to have the same
%   maximum speed.
%
% See also MTRAJ, LSPB, CTRAJ.

% Copyright 2022-2023 Peter Corke, Witold Jachimczyk, Remo Pillat

function [TG, t, info]  = mstraj(segments, qdmax, tsegment, q0, dt, Tacc, varargin)

if isempty(q0)
    q0 = segments(1,:);
    segments = segments(2:end,:);
end

assert(size(segments,2) == size(q0,2), 'RTB:mstraj:badarg', 'WP and Q0 must have same number of columns');
assert(xor(~isempty(qdmax), ~isempty(tsegment)), 'RTB:mstraj:badarg', 'Must specify either qdmax or tsegment, but not both');
if isempty(qdmax)
    assert(length(tsegment) == size(segments,1), 'RTB:mstraj:badarg', 'Length of TSEG does not match number of segments');
end
if isempty(tsegment)
    if length(qdmax) == 1
        % if qdmax is a scalar assume all axes have the same speed
        qdmax = repmat(qdmax, 1, size(segments,2));
    end
    assert(length(qdmax) == size(segments,2), 'RTB:mstraj:badarg', 'Length of QDMAX does not match number of axes');
end

ns = size(segments,1);
nj = size(segments,2);

[opt,args] = tb_optparse([], varargin);

if ~isempty(args)
    qd0 = args{1};
else
    qd0 = zeros(1, nj);
end

% set the initial conditions
q_prev = q0;
qd_prev = qd0;

clock = 0;      % keep track of time
arrive = [];    % record planned time of arrival at via points

tg = [];
taxis = []; %#ok<NASGU>

for seg=1:ns
    if opt.verbose
        fprintf('------------------- segment %d\n', seg);
    end
    
    % set the blend time, just half an interval for the first segment
    
    if length(Tacc) > 1
        tacc = Tacc(seg);
    else
        tacc = Tacc;
    end
    
    tacc = ceil(tacc/dt)*dt;
    tacc2 = ceil(tacc/2/dt) * dt;
    if seg == 1
        taccx = tacc2;
    else
        taccx = tacc;
    end
    
    % estimate travel time
    %    could better estimate distance travelled during the blend
    q_next = segments(seg,:);    % current target
    dq = q_next - q_prev;    % total distance to move this segment
    
    %% probably should iterate over the next section to get qb right...
    % while 1
    %   qd_next = (qnextnext - qnext)
    %   tb = abs(qd_next - qd) ./ qddmax;
    %   qb = f(tb, max acceleration)
    %   dq = q_next - q_prev - qb
    %   tl = abs(dq) ./ qdmax;
    
    if ~isempty(qdmax)
        % qdmax is specified, compute slowest axis        
        tb = taccx;
        
        % convert to time
        tl = abs(dq) ./ qdmax;
        %tl = abs(dq - qb) ./ qdmax;
        tl = ceil(tl/dt) * dt;
        
        % find the total time and slowest axis
        tt = tb + tl;
        [tseg,slowest] = max(tt);
        
        info(seg).slowest = slowest; %#ok<*AGROW>
        info(seg).segtime = tseg;
        info(seg).axtime = tt;
        info(seg).clock = clock;
        
        % best if there is some linear motion component
        if tseg <= 2*tacc
            tseg = 2 * tacc;
        end
    elseif ~isempty(tsegment)
        % segment time specified, use that
        tseg = tsegment(seg);
        slowest = NaN;
    end
    
    % log the planned arrival time
    arrive(seg) = clock + tseg;
    if seg > 1
        arrive(seg) = arrive(seg) + tacc2;
    end
    
    if opt.verbose
        fprintf('seg %d, slowest axis %d, time required %.4g\n', ...
            seg, slowest, tseg);
    end
    
    %% create the trajectories for this segment
    
    % linear velocity from qprev to qnext
    qd = dq / tseg;
    
    % add the blend polynomial
    if taccx == 0
        qb = zeros(0,2);
    else
        qb = quinticpolytraj([q0', (q_prev+tacc2*qd)'], [0, taccx], 0:dt:taccx, 'VelocityBoundaryCondition', [qd_prev' qd'])';
    end
    tg = [tg; qb(2:end,:)];
    
    clock = clock + taccx;     % update the clock
    
    % add the linear part, from tacc/2+dt to tseg-tacc/2
    for t=tacc2+dt:dt:tseg-tacc2
        s = t/tseg;
        q0 = (1-s) * q_prev + s * q_next;       % linear step
        tg = [tg; q0];
        clock = clock + dt;
    end
    
    q_prev = q_next;    % next target becomes previous target
    qd_prev = qd;
end
% add the final blend
if taccx == 0
    qb = zeros(0,2);
else
    qb = quinticpolytraj([q0', (q_prev+tacc2*qd)'], [0, taccx], 0:dt:taccx, 'VelocityBoundaryCondition', [qd_prev' qd'])';
end
tg = [tg; qb(2:end,:)];
info(seg+1).segtime = tacc2;
info(seg+1).clock = clock;

% plot a graph if no output argument
if nargout == 0
    t = (0:size(tg,1)-1)'*dt;
    clf
    plot(t, tg, '-o');
    hold on
    plot(arrive, segments, 'bo', 'MarkerFaceColor', 'k');
    hold off
    grid
    xlabel('time');
    xaxis(t(1), t(end))
    return
end
if nargout > 0
    TG = tg;
end
if nargout > 1
    t = (0:size(tg,1)-1)'*dt;
end
