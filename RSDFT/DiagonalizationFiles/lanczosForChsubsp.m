function [W, lam,bound]=lanczosForChsubsp(B, nev, v, m)
%% function [W, lam] = lan(B, nev, v, m)
%% B   = matrix;
%% nev = number of wanted egenvalues;
%% v   = initial vector
%% m   = number of steps
%% tol = tolerance for stopping
%% can do with (full) reorthogonalization (reorth=1)
%% or no -- reorthogonalization (reorth=0)
% call by chsubsp and finds all the return values that the original lanczos did in
% lan.m
reorth = 0;
tol=1.e-05;
%%

global OPTIMIZATIONLEVEL;% get access to global variable

% testing has shown that most of the time when B is large, the
% sum of the eigenvalues does not converge, so testing for convergence
% just wastes cpu time
if (size(B,1)>35000)
    enableConvergenceTest=0;
else
    enableConvergenceTest=1;
end

n = size(B,1);
v = v/norm(v);
v1 = v;
v0 = zeros(n,1);
k = 0 ;
bet = 0;
ll = 0;
%--------------------pre-allocating
Tmat = zeros(m+1,m+1);
tr   = zeros(1,m);
%%-------------------- main lanczos loop

if (OPTIMIZATIONLEVEL~=0)
    VV=malloc(n,m);
    % VV is directly changed an thus does not need to be returned
    [rr,X1,indx,k,bound]=lanWhileLoopForChsubsp(m,v0,v1,B,reorth,nev,VV,Tmat);
else
    VV=zeros(n,m);
    %%-------------------- main lanczos loop
    while (k < m)
        k   = k+1;

        VV(:,k) = v1;

        v   =  B*v1 - bet*v0;
        if (enableMexFilesTest==1)
            v2=BTimesv1MinusbetTimesv0(B,v0,v1,bet,findFirstColumnWithNonZeroElement(B));
            if (any(abs(v-v2)>0.000001))
                exception=struct('message','Mex file descreptency for BTimesv1MinusbetTimesv0','identifier',[],'stack',{mfilename('fullpath') 'filler'});
                logError(exception);
            end
        end

        alp = v1'*v;

        if (enableMexFilesTest==0)
            v   = v-alp*v1 ;
        else
            vTemp=v-alp*v1;
            vTemp2=vMinusalpTimesv1(v,v1,alp);
            v=vTemp;
            if (any(abs(vTemp-vTemp2)>0.000001))
                exception=struct('message','Mex file descreptency for vMinusalpTimesv1','identifier',[],'stack',{mfilename('fullpath') 'filler'});
                logError(exception);
            end
        end

        %%-----------------------------
        %% reorth  -- test for reorth. needed!
        %%-----------------------------
        if (reorth)
            subVV=VV(:,1:k);
            v = v - subVV*(subVV'*v);
        end
        %%-------------------- normalize and store v1
        bet = norm(v);
        v0 = v1;
        inverseOfbet=1.0/bet;
        v1 = v*inverseOfbet;

        %%-------------------- update tmat
        Tmat(k,k)   = alp;
        Tmat(k+1,k) = bet;
        Tmat(k,k+1) = bet;
        NTest  = min(8*nev,m) ;     %% when to   start testing
        %%-------------------- tr, ll,  == for plotting
        indx = [];
        if (enableConvergenceTest && (((k >= NTest) && (mod(k,10) == 0 )) || k == m))
            if (k~=m)
                rr  = eig(Tmat(1:k,1:k));
                [rr, indx]  = sort(rr) ;      %% sort increasingly
            else
                [X1,rr]  = eig(Tmat(1:k,1:k));
                rr=diag(rr);
                [rr, indx]  = sort(rr) ;      %% sort increasingly
            end

            bound = max(abs(rr)) + bet;
            tr1 = sum(rr(1:nev));
            ll = ll+1;
            tr(ll) = tr1;
        end
        %
        % stopping criterion based on sum of eigenvalues.
        % make sure this is is well-converged!
        %
        if (enableConvergenceTest && (ll>1 && (abs(tr(ll)-tr(ll-1)) < tol*tr(ll-1))))
            [X1,rr]  = eig(Tmat(1:k,1:k));
            rr = diag(rr);
            [rr, indx]  = sort(rr) ;      %% sort increasingly
            break
        end
        % end - big while loop
    end
    if (enableConvergenceTest==0)
        [X1,rr]  = eig(Tmat(1:k,1:k));
        rr=diag(rr);

        [rr, indx]  = sort(rr) ;      %% sort increasingly
    end
end

%%-------------------- save e.values and compute e.vectors
%% clean up unused memory to avoid "Out of Memory" errors
clear Tmat;
clear v;
clear v0;
clear v1;

%%
if (reorth)
    lam = rr(1:nev);
    Y = X1(:,indx(1:nev));
    if (k==size(VV,2))
        W = VV*Y;
    else
        W = VV(:,1:k)*Y;
    end
else
    rrCopy=rr;

    % find out how many eigenvalues are copies
    counter=1;
    while(counter<numel(rrCopy))
        rrCopy(abs(rrCopy(counter)-rrCopy(counter+1:end))<0.00001)=[];
        counter=counter+1;
    end
    mevMultiplier=min(1.8^(numel(rr)/numel(rrCopy)),3.2);
    %%-------------------- if no reorth. to get meaningful
    %%-------------------- eigenvectors.. get twice as many
    %%-------------------- eigenvectors and use RayleighRitz
    mev = floor(min(nev*mevMultiplier,k));
    Y = X1(:,indx(1:mev));

    if (k==size(VV,2))
        W = VV*Y;
    else
        W = VV(:,1:k)*Y;
    end
    %% VV matrix no longer used so it can be deleted
    clear VV;
    %% add an orthogonalization step
    [W,G] = qr(W,0) ;

    Vin = B*W;
    if (OPTIMIZATIONLEVEL~=0)
        G=Rayleighritz(Vin,W,mev);
    else
        for j=1:mev
            for i=1:j
                G(i,j) = Vin(:,i)'*W(:,j);
                G(j,i) = G(i,j);
            end
        end
        if (enableMexFilesTest==1)
            G2=Rayleighritz(Vin,W,mev);
            if (any(abs(G-G2)>0.000001))
                exception=struct('message','Mex file descreptency for Rayleighritz.c','identifier',[],'stack',{mfilename('fullpath') 'filler'});
                logError(exception);
            end
        end
    end


    [X1,rr]  = eig(G);
    rr = diag(rr);
    [rr, indx]  = sort(rr) ;      %% sort increasingly
    lam = rr(1:nev);
    Y = X1(:,indx(1:nev));
    W = W*Y;
end
%%-----------------------------------------------------------
