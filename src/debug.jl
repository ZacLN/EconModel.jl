import EconModel:ModelMeta,StateVariables,PolicyVariables,subs!,addindex!,tchange!,getv,FutureVariables,AggregateVariables,AuxillaryVariables,getMnames,buildE,buildF,buildJ,StaticVariables,ModelDistribution,genlist,ndgrid

gtype=CurtisClenshaw

(foc,endogenous,exogenous,policy,static,params,aux,agg)=
(:[
            h*η+R*b[-1]-b-c
            (λ*W*η+Uh)*h
		    (b-blb)+β*Expect(R*λ[+1]*(b-blb))/(-λ)
],:[
    b       = (-2.,6.,7)
],:[
    η       = (1,0.9,0.1,1)
],:[
    b       = (-2.,8.,b,0.9)
    c       = (0,5,0.4)
    h       = (0,1,.95)
],:[
    λ 	    = c^-σc
    Uh  	= -ϕh*(1-h)^-σh
    hh      = η*h
    bp      = b*1
    R       = SR*exp(-0.001*B)
],:[
    β       = 0.98
    σc      = 2.5
    ϕh      = 1.6181788
    σh      = 2.0
    blb     = -2.0
    SR       = 1.0144
    W 	    = 1.3
],:[],:[
    B       = (b,0,100)
])


@assert length(foc.args) == length(policy.args) "equations doesn't equal numer of policy variables"


meta                   = ModelMeta(deepcopy(foc),
                                    params,
                                    deepcopy(endogenous),
                                    deepcopy(exogenous),
                                    deepcopy(policy),
                                    deepcopy(static),
                                    deepcopy(aux),
                                    deepcopy(agg))

State                  = StateVariables(endogenous,exogenous,gtype)
Policy                 = PolicyVariables(policy,State)

params = Dict{Symbol,Float64}(zip([x.args[1] for x in params.args],[x.args[2] for x in params.args]))
subs!(foc,params)
addindex!(foc)
subs!(static,params)
addindex!(static)

for i = 1:length(static.args)
    d=Dict(zip([x.args[1] for x in static.args[1:i]],[x.args[2] for x in static.args[1:i]]))
    for j = i+1:length(static.args)
        subs!(static.args[j],d)
    end
end
for i = 1:length(static.args)
    push!(static.args,tchange!(copy(static.args[i]),1))
end

static = Dict(zip([x.args[1] for x in static.args],[x.args[2] for x in static.args]))
subs!(foc,static)


allvariables            = unique(getv(foc,Any[]))
Future                  = FutureVariables(foc,aux,State)
Auxillary               = AuxillaryVariables(aux,State,Future)
Aggregate               = AggregateVariables(agg,State,Future,Policy)

variablelist            = getMnames(allvariables,State,Policy,Future,Auxillary,Aggregate)



for i = 1:length(aux.args)
    if !in(aux.args[i].args[1],[x.args[1] for x in variablelist[:,1]])
        println ("Added $(aux.args[i].args[1]) to variable list")
        x = copy(aux.args[i].args[1])
        x = addindex!(x)
        x = hcat(x,:(M.auxillary.X[i,$i]),symbol("A$i"))
        variablelist = vcat(variablelist,x)
    end
end

for i = State.nendo+1:State.n
    if !in(State.names[i],[x.args[1] for x in variablelist[:,1]])
        x = Expr(:ref,State.names[i],0)
        x = hcat(x,:(M.state.X[i,$i]),symbol("S$i"))
        variablelist = vcat(variablelist,x)
    end
end


Efunc                   = buildE(Future,variablelist)
Ffunc                   = buildF(foc,variablelist)
j                       = buildJ(foc,variablelist,Policy)
Jname                   = symbol("J"*string(round(Int,rand()*100000)))
Jarg                    = Expr(:call,Jname,Expr(:(::),:M,:Model),Expr(:(::),:i,:Int64))
Static                  = StaticVariables(static,variablelist,State)