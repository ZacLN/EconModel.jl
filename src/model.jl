type ModelMeta
  foc::Expr
  parameters::Expr
  endogenous::Expr
  exogenous::Expr
  policy::Expr
  static::Expr
  auxillary::Expr
end

type Model
  F::Function
  J::Function
  E::Function
  state::StateVariables
  policy::PolicyVariables
  future::FutureVariables
  static::StaticVariables
  auxillary::AuxillaryVariables
  error::Array{Float64,2}
  meta::ModelMeta
end


function show(io::IO,M::Model)
  println("State: $(M.state.names)")
  println("Policy: $(M.policy.names)")
  println("\n FOC: \n")
  for i = 1:length(M.meta.foc.args)
  	println("\t$(M.meta.foc.args[i])")
  end
end


function Model(foc::Expr,endogenous::Expr,exogenous::Expr,policy::Expr,static::Expr,params::Expr,aux=:[];gtype=CurtisClenshaw)

    @assert length(foc.args) == length(policy.args) "equations doesn't equal numer of policy variables"


    meta                   = ModelMeta(deepcopy(foc),
                                        params,
                                        deepcopy(endogenous),
                                        deepcopy(exogenous),
                                        deepcopy(policy),
                                        deepcopy(static),
                                        deepcopy(aux))

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

    variablelist            = getMnames(allvariables,State,Policy,Future,Auxillary)



    for i = 1:length(aux.args)
        if !in(aux.args[i].args[1],[x.args[1] for x in variablelist[:,1]])
            x = copy(aux.args[i].args[1])
            x = addindex(x,iglist)
            x = hcat(x,:(M.auxillary.X[i,$i]),symbol("A$i"))
            variablelist = vcat(variablelist,x)
        end
    end

    for i = State.nendo+1:State.n
        if !in(State.names[i],[x.args[1] for x in variablelist[:,1]])
            x = Expr(:ref,State.names[i],0)
            x = hcat(x,:(M.state.G.grid[i,$i]),symbol("S$i"))
            variablelist = vcat(variablelist,x)
        end
    end


    Efunc                   = buildE(Future,variablelist)
    Ffunc                   = buildF(foc,variablelist)
    j                       = buildJ(foc,variablelist,Policy)
    Jname                   = symbol("J"*string(round(Int,rand()*100000)))
    Jarg                    = Expr(:call,Jname,Expr(:(::),:M,:Model),Expr(:(::),:i,:Int64))
    Static                  = StaticVariables(static,variablelist,State)


  return Model(eval(Ffunc),
               eval(:($Jarg = $(j))),
               eval(Efunc),
               State,
               Policy,
               Future,
               Static,
               Auxillary,
               zeros(State.G.n,Policy.n),
               meta)
end





function steadystate(foc::Expr,params::Expr,static1::Expr,exogenous::Expr)
  static = deepcopy(static1)
  SS = deepcopy(foc)

  # get parameters
  plist = genlist(params,Any,Any)
  for p in collect(keys(plist))
    push!(ignorelist,p)
  end

  addindex(static,ignorelist)
  addindex(SS,ignorelist)

  # get static variables
  for i = 1:length(static.args)
    static.args[i].args[2]=simplify(static.args[i].args[2])
    for ii=i+1:length(static.args)
      subs1!(static.args[ii].args[2],static.args[i].args[1],static.args[i].args[2])
    end
  end
  subs!(static,plist)

  slist = genlist(static,Expr,Expr)

  # get future/past statics
  slistprime = Dict{Expr,Expr}()
  for s in keys(slist)
    merge!(slistprime,Dict{Expr,Expr}(tchange(s,ignorelist,1)=>tchange(slist[s],ignorelist,1)))
  end

  # substitute for foc
  subs!(SS,slistprime)
  subs!(SS,slist)
  subs!(SS,plist)

  etasub=Dict()
  for e in  Symbol[x.args[1] for x in exogenous.args]
    merge!(etasub,Dict(e=>1.0))
  end
  SS = subs!(removeindex(removeexpect(SS)),etasub)

  args = sort(Symbol[x[1] for x in unique(getv(SS,Any[]))])


  targ = Expr(:call,:S)
  for v in args
    # push!(targ.args,parse(string(v)*"::Float64" ))
    push!(targ.args,parse(string(v) ))
  end
  # exS= submfun!(exS)
  @eval $targ = $(SS)
  return S
end