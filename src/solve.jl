function getfuture(M::Model)
    for i = 1:M.state.nendo
        if in(M.state.names[i],M.policy.names)
            @inbounds M.future.state[:,i] = repmat(M.policy.X[:,findfirst(M.state.names[i].==M.policy.names)],M.future.nP)
        elseif in(M.state.names[i],M.auxillary.names)
            @inbounds M.future.state[:,i] = repmat(M.auxillary.X[:,findfirst(M.state.names[i].==M.auxillary.names)],M.future.nP)
        elseif in(M.state.names[i],M.static.names)
            M.static.sget(M)
            @inbounds M.future.state[:,i] = repmat(M.static.X[:,findfirst(M.state.names[i].==M.static.names)],M.future.nP)
        else
          error("Can't find any policy or auxillary variable for $(M.state.names[i])")
        end
    end

    M.future.X[:] =  interp(M.future.state,M.state.G,hcat([M[n,0] for n ∈ M.future.names]...))[:]

    for j= 1:length(M.future.names)
        if in(M.future.names[j],M.policy.names)
            ub = M.policy.ub[findfirst(M.future.names[j].==M.policy.names)]
            lb = M.policy.lb[findfirst(M.future.names[j].==M.policy.names)]
            for i = 1:length(M.state.G)*M.future.nP
                M.future.X[i,j]=max(M.future.X[i,j],lb)
                M.future.X[i,j]=min(M.future.X[i,j],ub)
            end
        end
    end
end

function solve(M::Model,
                n::Int,
                ϕ::Float64;
                crit::Float64=1e-6,
                mn::Int=1,
                disp::Int=div(n,10),
                upag::Int=500,
                Φ::Float64=0.0,
                f::Tuple{Int,Function}=(1000000,f()=nothing))

    dp = 1.0
    Merror = 1.0
    for iter = 1:n
        mod(iter,20)==0 ? Merror =maximum(abs(M.error),1) : nothing
        if (mod(iter,upag)==0 || maximum(Merror)<crit) && M.aggregate.n>0  &&  upag != -1
            updateaggregate!(M,Φ)
        end

        if (dp<1e-8 || maximum(Merror)<crit) && iter>mn
            upag!=-1 ? updateaggregate!(M) : nothing
            disp!=-1 ? printerr(M,Merror,iter,crit) : nothing
            break
        end

        Pold = deepcopy(M.policy.X)
        solveit(M,ϕ)
        mod(iter,20)==0 ? (dp = maximum(abs(Pold-M.policy.X))) : nothing

        if disp!==-1 && mod(iter,disp) == 0
            println(iter," ",round(log10(Merror)),'\t',1-sum(Merror.>crit)/(length(Merror)*length(M)))
        end

        if mod(iter,f[1]) == 0
            f[2]()
        end
    end
    M.static.sget(M)
end


function solveS(M::Model,
                n::Int,
                ϕ::Float64;
                crit::Float64=1e-6,
                mn::Int=1,
                disp::Int=div(n,10),
                upag::Int=500,
                Φ::Float64=0.0,
                f::Tuple{Int,Function}=(1000000,f()=nothing))

    dp = 1.0
    Merror = 1.0
    for iter = 1:n
        mod(iter,20)==0 ? Merror =maximum(abs(M.error),1) : nothing
        if (mod(iter,upag)==0 || maximum(Merror)<crit) && M.aggregate.n>0  &&  upag != -1
            updateaggregate!(M,Φ)
        end

        if (dp<1e-8 || maximum(Merror)<crit) && iter>mn
            upag!=-1 ? updateaggregate!(M) : nothing
            disp!=-1 ? printerr(M,Merror,iter,crit) : nothing
            break
        end

        Pold = deepcopy(M.policy.X)
        solveSit(M,ϕ)
        mod(iter,20)==0 ? (dp = maximum(abs(Pold-M.policy.X))) : nothing

        if disp!==-1 && mod(iter,disp) == 0
            println(iter," ",round(log10(Merror)),'\t',1-sum(Merror.>crit)/(length(Merror)*length(M)))
        end

        if mod(iter,f[1]) == 0
            f[2]()
        end
    end
    M.static.sget(M)
end

function solveit(M::Model, ϕ=0.2)
    getfuture(M)
    M.E(M)
    M.F(M)
    for i = 1:length(M.state.G)
        M.J(M,i)
        x = M.policy.X[i,:]-M.temporaries.J\M.error[i,:]
        @simd for j = 1:M.policy.n
            @inbounds M.policy.X[i,j] *= ϕ
            @inbounds M.policy.X[i,j] += (1-ϕ)*clamp(x[j],M.policy.lb[j],M.policy.ub[j])
        end
    end
end

function solveSit(M::Model, ϕ=0.2)
    getfuture(M)
    M.Fs(M)
    for i = 1:length(M.state.G)
        M.Js(M,i)
        x = M.policy.X[i,:]-M.temporaries.J\M.error[i,:]
        @simd for j = 1:M.policy.n
            @inbounds M.policy.X[i,j] *= ϕ
            @inbounds M.policy.X[i,j] += (1-ϕ)*clamp(x[j],M.policy.lb[j],M.policy.ub[j])
        end
    end
end
