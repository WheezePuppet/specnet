#!/usr/bin/env julia

using Gadfly
using LightGraphs
using GraphPlot, Compose
using ColorSchemes, Colors
using Misc
using Random

Random.seed!(1234)

################################ functions ################################
in_proto(node) = any(node in proto for proto in protos)

eligible_for_proto(node) = wealths[node] > proto_threshold && !in_proto(node)

function form_proto(node1, node2)
    prd("Forming proto with $(node1) and $(node2)!")
    global protos
    push!(protos, Set{Int64}([node1,node2]))
end

function compute_colors()
    global protos, possible_colors
    [ in_proto(n) ?
        possible_colors[findfirst(x -> n in x, protos)] :
        (n in dead ? colorant"black" : colorant"lightgrey") for n in 1:N ]
end

function remove_node(node)
    # See warnings at http://juliagraphs.github.io/LightGraphs.jl/latest/generators.html#LightGraphs.SimpleGraphs.rem_vertex!
    # For now, let's just mark the node as "dead" and keep it in the graph.
    # We could sever the node from its neighbors and put it in an isolated 
    # place. Or, we could remove it from the graph altogether, but we'd have to
    # adjust all the external data structures (wealths, colors, etc.) and the
    # node numbers would suddenly change making things difficult to track.
    global graph, dead
    friends = collect(neighbors(graph, node))
    for friend in friends
        prd("Removing edge between $(node) and $(friend)...")
        #rem_edge!(graph, node, friend)
    end
    push!(dead, node)
end
###########################################################################


params = Dict(
    "N" => 20,
    "openness" => 0,
    "num_iter" => 100,
    "max_starting_wealth" => 100,
    "salary_range" => 10,
    "proto_threshold" => 50,
    "make_anim" => false
)

if length(ARGS) == 6
    using_defaults = false
    params["N"] = parse(Int64,ARGS[1])
    params["openness"] = parse(Float16,ARGS[2])
    params["num_iter"] = parse(Int64,ARGS[3])
    params["max_starting_wealth"] = parse(Float16,ARGS[4])
    params["salary_range"] = parse(Float16,ARGS[5])
    params["proto_threshold"] = parse(Float16,ARGS[6])
    params["make_anim"] = parse(Bool,ARGS[7])
elseif length(ARGS) == 0
    using_defaults = true
else
    println("Usage: sim.jl N openness num_iter max_starting_wealth salary_range proto_threshold make_anim.")
    exit(1)
end

println("Running sim...")
println("Using" * (using_defaults ? " defaults" : "") * ":")
display(params)
println()

# There must be a better way to do this using eval():
N = params["N"]
openness = params["openness"]
num_iter = params["num_iter"]
max_starting_wealth = params["max_starting_wealth"]
salary_range = params["salary_range"]
proto_threshold = params["proto_threshold"]
make_anim = params["make_anim"]


# A list of proto-institutions, each of which is a set of member vertex
# numbers. (Could be a set, but we're using it as an index to the colors
# array, to uniquely color members of each proto.)
protos = Set{Int64}[]

# The nodes that have perished (initially none).
dead = Set{Int64}()

# The initial social network.
graph = LightGraphs.SimpleGraphs.erdos_renyi(N,.2)
while !is_connected(graph)
    pri("Not connected; regenerating...")
    graph = LightGraphs.SimpleGraphs.erdos_renyi(N,.2)
end

wealths = rand(Float16, N) * max_starting_wealth
possible_colors = Random.shuffle(ColorSchemes.rainbow.colors)


# Erase old images.
run(`rm -f $(tempdir())/output"*".svg`)

locs_x, locs_y = nothing, nothing

for iter in 1:num_iter

    pri("Iteration $(iter)...")

    global locs_x, locs_y

    if locs_x == nothing
        locs_x, locs_y = spring_layout(graph)
    else
        locs_x, locs_y = spring_layout(graph, locs_x, locs_y)
    end

    node1 = rand(setdiff(1:N,dead))
    if rand(Float16) < openness  ||
            length(setdiff(neighbors(graph,node1),dead)) == 0
        # Choose from the graph at large.
        node2 = rand(filter(x->x!=node1,1:N))
        prd("$(node1) encounters at-large $(node2)")
    else
        # Choose from a neighbor.
        node2 = rand(setdiff(neighbors(graph,node1),dead))
        prd("$(node1) encounters neighbor $(node2)")
    end
    if eligible_for_proto(node1) && eligible_for_proto(node2)
        form_proto(node1, node2)
        # Since they're forming a proto, they also become socially connected
        # (if they weren't already.)
        if !has_edge(graph, node1, node2)
            add_edge!(graph, node1, node2)
        end
    end

    colors = compute_colors()

    remember_layout = x -> spring_layout(x, locs_x, locs_y)

    plot = gplot(graph,
        layout=remember_layout,
        nodelabel=1:N,
        NODESIZE=.08,
        nodesize=ifelse.(wealths .> 0, wealths*4, maximum(wealths)*2),
        nodestrokec=colorant"grey",
        nodestrokelw=.5,
        nodefillc=colors)
    draw(SVG("$(tempdir())/output$(lpad(string(iter),3,'0')).svg"), plot)

    # Payday!
    wealths .+= (rand(Float16, N) .- .5) .* salary_range
    for d in dead
        wealths[d] = -500
    end
    proto_payoffs = [ in_proto(n) ? rand(Float16)*10 : 0 for n in 1:N ]
    wealths .+= proto_payoffs

    dying_nodes = setdiff((1:N)[wealths .< 0], dead)
    for dying_node in dying_nodes
        pri("Agent $(dying_node) died!")
        remove_node(dying_node)
    end
end

if make_anim
    println("Building animation...")
    run(`convert -delay 20 $(tempdir())/output"*".svg $(tempdir())/output.gif`)
end
