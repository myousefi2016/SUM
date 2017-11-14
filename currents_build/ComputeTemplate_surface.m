% 'exoShape' is a derived software by Stanley Durrleman, Copyright (C) INRIA (Asclepios team), All Rights Reserved, 2006-2009, version 1.0
%--------------------------------------------------------------------------
% Based on MATCHINE v1.0 software.
% Copyright Universit� Paris Descartes
% Contributor: Joan Alexis GLAUNES (2006)
% alexis.glaunes@mi.parisdescartes.fr
% 
% This software is a computer program whose purpose is to calculate an optimal 
% diffeomorphic transformation in 3D-space that allows to match two datasets 
% like points, curves or surfaces.
% 
% This software is governed by the CeCILL-B license under French law and
% abiding by the rules of distribution of free software. You can use, 
% modify and/ or redistribute the software under the terms of the CeCILL-B 
% license as circulated by CEA, CNRS and INRIA at the following URL
% "http://www.cecill.info". 
% 
% As a counterpart to the access to the source code and rights to copy,
% modify and redistribute granted by the license, users are provided only
% with a limited warranty  and the software's author, the holder of the
% economic rights, and the successive licensors have only limited 
% liability. 
% 
% In this respect, the user's attention is drawn to the risks associated
% with loading, using, modifying and/or developing or reproducing the
% software by the user in light of its specific status of free software,
% that may mean that it is complicated to manipulate, and that also
% therefore means that it is reserved for developers and experienced
% professionals having in-depth computer knowledge. Users are therefore
% encouraged to load and test the software's suitability as regards their
% requirements in conditions enabling the security of their systems and/or 
% data to be ensured and, more generally, to use and operate it in the 
% same conditions as regards security. 
% 
% The fact that you are presently reading this means that you have had
% knowledge of the CeCILL-B license and that you accept its terms.
%--------------------------------------------------------------------------
  
% Any use of this code should make reference to:
% - S. Durrleman, X. Pennec, A. Trouve and N. Ayache, Statistical Models of Sets of Curves and Surfaces based on Currents, Medical Image Analysis, (2009), DOI: 10.1016/j.media.2009.07.007
% - M. Vaillant and J. Glaunes, Surface Matching via Currents, Proc. of Information Processing in Medical Imaging (IPMI'05), Lecture Notes in Computer Science vol. 3565, Springer 2005, pp. 381--392



function TempL = ComputeTemplate_surface(data,grille,param,flag)

  %computes a template
  % for each subject suj, data.x{suj} is a 3-by-Nx matrix of point coordinates and data.vx{suj} is a 3-by-Nvx array, whose columns contain the indices in data.x{suj} of the vertices of each mesh cell.
  % grille contain the grid parameters:
  %   grille.long: size of the grid (3-by-one matrix)
  %   grille.pas: grid step
  %   grille.origine: coordinate of the bottom-left corner of the grid
  %   grille.fft3kd: FFT of the Gaussian Kernel (generated by Noyau3D_PAIR)
  %   
  % param contains the parameters
  % param.lambdaV: standard deviation of the Gaussian kernel for the deformations
  % param.gammaR: trade-off between regularity and fidelity to data for registrations
  % param.sigmaV = power before the Gaussian kernel for deformations
  % param.lambdaI = standard deviation of the Gaussian kernel for the currents.
  % 
  % flag is a string used to save results

%%%%%%%%%
% initialisations %
%%%%%%%%%
n_sujets = length(data.x);
data.c = cell(1,n_sujets);
data.N = cell(1,n_sujets);
for suj = 1:n_sujets
  [data.c{suj} data.N{suj}] = computeCentersNormals(data.x{suj},data.vx{suj});
end

% parametres du recalage %
lambdaW = param.lambdaW;
lambdaV = param.lambdaV;
gammaR = param.gammaR;
sigmaV = param.sigmaV;
lambdaW2 = lambdaW^2;
%parametre de l'approximation des courants
tau = 0.05;

paramStr = ['_lambdaV' num2str(lambdaV) '_lambdaW' num2str(lambdaW) '_gR' param.gRstr '_tau' num2str(100*(1-tau)) '_iter_'];

% parametres de la descente de gradient
stepmult = 1.2;
stepdiv = 2;
breakratio = 1e-4;
loopbreak = 10;
maxiterM = 20;

% parametres de la grille
nx = grille.long(1);
ny = grille.long(2);
nz = grille.long(3);

[x y z] = ndgrid(0:(nx-1),0:(ny-1),0:(nz-1));
x = x*grille.pas + grille.origine(1);
y = y*grille.pas + grille.origine(2);
z = z*grille.pas + grille.origine(3);
Gr = [x(:)';y(:)';z(:)'];


% calcul de l'ecart-type
etype = 0;
MoyC = [data.c{:}];
MoyN = [data.N{:}]/n_sujets;
for suj = 1:n_sujets
    auxC = cat(2,MoyC,data.c{suj});
    auxN = cat(2,MoyN,-data.N{suj});
    gamma = projConvol(auxN,auxC,grille.long,grille.pas,grille.origine,grille.fft3k_d);
    gammaN = sum(gamma.^2,4);
    etype = etype + max(gammaN(:));
end
etype = sqrt(etype/(n_sujets-1));
disp(['etype = ' num2str(etype)]);


% initialisation par le courant moyen %
gamma = projConvol(MoyN,MoyC, grille.long, grille.pas, grille.origine, grille.fft3k_d);
% figure;
% mesh(gamma(:,:,end/2+1));
% pause;
 [TempL.x TempL.vx] = MatchingPursuit_surface(gamma,grille,tau,etype);
 TempL.param = param;
 save([flag '_TemplateIteree_0.mat'],'TempL');

%%%%%%%%%%%%%%%%%%%%%%%%
% calcul de la moyenne par minimisation alternee %
%%%%%%%%%%%%%%%%%%%%%%%%
target = cell(1,1);
n_iter = 10;
for iter=1:1:n_iter

    disp(['iteration :' num2str(iter)]);

    %   STEP 1: Recalage de la moyenne sur chacune des instances
    for suj=1:n_sujets
        clear s target

        s.sigmaV = lambdaV;
        s.stdV = sigmaV;
        s.gammaR = gammaR;
        s.rigidmatching = 0;
        s.numbminims = 1;
        s.optim_verbosemode = 0;
        s.x = TempL.x;

        target{1}.method = 'surfcurr';
        target{1}.y = data.x{suj};
        target{1}.vy = data.vx{suj};
        target{1}.vx = TempL.vx;
        target{1}.sigmaW = lambdaW;
        target{1}.usegrid = 1;
        target{1}.ratio = .2;
        s = match(s,target);
        fprintf('dist(id,phi)=%f    nNiter=%d\n',s.distIdPhi,length(s.J));

        % on sauve les matchings
        nom_fichier = [flag '_matchingTemplateSurSujet_' num2str(suj) paramStr num2str(iter) '.mat'];
        save(nom_fichier,'s');
    end % FIN STEP 1
    
    diffeos = cell(1,n_sujets);
    for suj=1:n_sujets
        s = load([flag '_matchingTemplateSurSujet_' num2str(suj) paramStr num2str(iter) '.mat']);
        s.s.optim_verbosemode = 0;
        diffeos{suj} = s.s;
    end

    %   STEP 2: Mise a jour de la moyenne pour chaque surface
    J = [];
    grad = computeGradient;
    gradN = sum(grad.^2,4);
    normeGrad2 = max(gradN(:));
    J(1) = computeFunct(TempL);
    stepsize = J(1)/normeGrad2/16;
    ok = 1;
    iterM = 1;
    disp([' stepsize : ' num2str(stepsize) '  functionnal : ' num2str(J(end))]);
    while(ok && (iterM<maxiterM))
        if (iterM > 1)
            grad = computeGradient;
        end
        % calcul du champ gamma associe au courant moyen
        [Tx Tnx] = computeCentersNormals(TempL.x,TempL.vx);
        temp = projConvol(Tnx,Tx,grille.long,grille.pas,grille.origine,grille.fft3k_d);

        stepsize = stepsize * stepdiv;
        minimtest = 0;
        loop = 0;
        while(~minimtest && (loop<loopbreak))
            stepsize = stepsize / stepdiv;
            tempnew = temp - stepsize*grad;

            [TL_new.x TL_new.vx] = MatchingPursuit_surface(tempnew,grille,tau,etype);
            if (TL_new.x == -1)
                minimtest = 0;
                J(iterM+1) = -Inf;
            else
                J(iterM+1) = computeFunct(TL_new);
                minimtest = (J(iterM+1) < J(iterM));
            end
            loop = loop + 1;
            disp([' stepsize : ' num2str(stepsize) '  functionnal : ' num2str(J(end))]);
        end
        stepsize = stepsize * stepmult;
        if (loop~=loopbreak)
            TempL = TL_new;
            disp(['mise a jour du template : iteration ' num2str(iterM+1) '     functional = ' num2str(J(iterM+1)),...
             '     stepsize = ' num2str(stepsize)]);
        end
        ok = ( (J(iterM)-J(iterM+1)) > breakratio*(J(1)-J(iterM+1)) && loop~=loopbreak );
        iterM = iterM + 1;
    end %fin STEP 2

    filename = [flag '_TemplateIteree_' num2str(iter) '.mat'];
    TempL.param = param;
    save(filename,'TempL');

end %fin iteration



  %%%%%%%%%%%%%%%%%%%
  % computeGradient %
  %%%%%%%%%%%%%%%%%%%
  function grad = computeGradient

   grad = zeros(nx,ny,nz,3);
   for sujet=1:n_sujets
     % deforms the template and substract the subject's line
     phiS = flow(diffeos{sujet},TempL.x,1,diffeos{sujet}.T);
     [cm taum] = computeCentersNormals(phiS,TempL.vx);
     cx = [cm data.c{sujet}];
     taux = [taum (-data.N{sujet})];
     
     % deforms the grid
     diffeos{sujet}.usegrid = 1; diffeos{sujet}.ratio = 0.3; diffeos{sujet}.optim_verbosemode = 0;
     phiGrille = flow(diffeos{sujet},Gr,1,diffeos{sujet}.T);
          
     % computes the deformed gamma field
     grilleAux = setgrid(min([cx phiGrille],[],2),max([cx phiGrille],[],2),lambdaW,0.2);
     aux = gridOptim(cx,taux,phiGrille,grilleAux.long,grilleAux.pas,grilleAux.origine,grilleAux.fft3k_d);

     %multiplication par la jacobienne inverse * determinant de la jacobienne
     for p=1:(nx*ny*(nz-1))
       pGX=phiGrille(1,p); pGY=phiGrille(2,p); pGZ = phiGrille(3,p);
	     q = p+nx;
       r = p+nx*ny;
       DpG = [phiGrille(1,p+1)-pGX, phiGrille(1,q)-pGX, phiGrille(1,r)-pGX;...
              phiGrille(2,p+1)-pGY, phiGrille(2,q)-pGY, phiGrille(2,r)-pGY;...
              phiGrille(3,p+1)-pGZ, phiGrille(3,q)-pGZ, phiGrille(3,r)-pGZ]/grille.pas;

       DpG = DpG/det(DpG);
       gradient = 2*DpG^(-1)*aux(:,p);
       grad(p)              = grad(p) + gradient(1);
       grad(p + nx*ny*nz)   = grad(p+ nx*ny*nz) + gradient(2);
       grad(p + 2*nx*ny*nz) = grad(p + 2*nx*ny*nz) + gradient(3);
     end
   end
  end

  %%%%%%%%%%%%%%%%
  % computeFunct %
  %%%%%%%%%%%%%%%%
  function J = computeFunct(TL)
   J = 0;
   for sujet=1:n_sujets
    phiS = flow(diffeos{sujet}, TL.x, 1,diffeos{sujet}.T);
    [cm taum] = computeCentersNormals(phiS,TL.vx);
    cx = [cm data.c{sujet}];
    taux = [taum (-data.N{sujet})];
    nfx = size(cx,2);
    for p=1:nfx
     for q=1:nfx
      argin = -((cx(1,p)-cx(1,q))^2+(cx(2,p)-cx(2,q))^2+(cx(3,p)-cx(3,q))^2)/lambdaW2;
      argout = exp(argin);
      J = J + argout * (taux(1,p)*taux(1,q)+taux(2,p)*taux(2,q)+taux(3,p)*taux(3,q));
     end
    end
   end
  end

  function grille = setgrid(mini,maxi,sV,ratio)
        pas = ratio * sV; %grid's step
        long = (maxi-mini)/pas + 3/ratio; %circonf??rence du tore
        long = (long<=16)*16 + (long>16).*((long<=32)*32 + (long>32).*((long<=64)*64 + (long>64).*2.*ceil(long/2)));
        grille.pas = pas;
        grille.origine = mini - (long*pas-maxi+mini)/2;
        grille.long = long';
        grille.fft3k_d = noyau3D_PAIR(grille,sV);
  end

  function [cS NS] = computeCentersNormals(Sx,Svx)
   nfx = size(Svx,2);
   cS = zeros(3,nfx); %centers
   NS = zeros(3,nfx); %normals
   v = zeros(1,9);
   for f = 1:nfx
        locf = 3*(f-1);
        for k = 1:3
            for j = 1:3
                v(k+3*(j-1)) = Sx(k+3*(Svx(j+locf)-1));
            end
        end
        % c = (v1+v2+v3)/3;
        cS(1+locf) = (v(1)+v(4)+v(7))/3;
        cS(2+locf) = (v(2)+v(5)+v(8))/3;
        cS(3+locf) = (v(3)+v(6)+v(9))/3;
       % N = [(v2-v1)a(v3-v1)]/2;
        NS(1+locf) = ((v(5)-v(2))*(v(9)-v(3))-(v(6)-v(3))*(v(8)-v(2)))/2;
        NS(2+locf) = ((v(6)-v(3))*(v(7)-v(1))-(v(4)-v(1))*(v(9)-v(3)))/2;
        NS(3+locf) = ((v(4)-v(1))*(v(8)-v(2))-(v(5)-v(2))*(v(7)-v(1)))/2;
   end
  end




end






















