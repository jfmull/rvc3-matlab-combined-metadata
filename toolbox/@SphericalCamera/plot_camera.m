%SphericalCamera.plot_camera Display camera icon in world view
%
% C.plot_camera(T) draws the spherical image plane (unit sphere) at pose given by
% the SE3 object T.
%
% C.plot_camera(T, P) as above but also display world points, given by the
% columns of P (3xN), as small spheres.
%
%
% Reference::
%
% "Spherical image-based visual servo and structure estimation",
% P. I. Corke, 
% in Proc. IEEE Int. Conf. Robotics and Automation, (Anchorage),
% pp. 5550-5555, May 3-7 2010.
%
% See also CentralCamera.visjac_p_polar, CentralCamera.visjac_l, CentralCamera.visjac_e.

% TODO
%  - proper animation, keep handles within the camera object

% Copyright 2022-2023 Peter Corke, Witold Jachimczyk, Remo Pillat 

function plot_camera(cam, varargin)
    
    
    opt.pose = cam.T;
    opt.points = [];

    
    [opt,arglist] = tb_optparse(opt, varargin);
    
    
    if isgraphics(cam.h_3dview)
        % if a handle already exists just update the transform
        set(cam.h_3dview, 'Matrix', opt.pose.T);
        
    else
        % otherwise draw the graphical object from scratch in this figure
        
        
        %clf
        axis([-3, 3, -3, 3, -3 3])
        daspect([1 1 1])
        hold on
        grid
        [x,y,z] = sphere(20);
        
        
        hg = hgtransform;
        surf(x,y,z, 'FaceColor', [0.8 0.8 1], 'EdgeColor', 0.5*[0.8 0.8 1], ...
            'EdgeLighting', 'gouraud', 'Parent', hg)
        light
        lighting gouraud
        
        
        T = transl(0,0,0);
        h = trplot(T, 'length', 1.6, 'arrow');
        h.Parent = hg;
        
        cam.h_3dview = hg;  % save handle for later
        
        axis
        limits = reshape(axis, 2, []);
        maxdim = max(diff(limits));
        rotate3d
    end
end