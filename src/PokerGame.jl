module PokerGame

export Player,PokerHand,Board,PokerHandState,Table, playerconts, profit

using Cards
using Decimals
using Dates

import Base.empty
import Cards.Hand
import Cards.Card

include("handparser.jl")

@enum Street PREFLOP=0 FLOP=3 TURN=4 RIVER=5
#@enum Action FOLD CHECK CALL BET RAISE

abstract type Action end
struct Raise <: Action
    amount::Decimal
end
struct Bet <: Action
    amount::Decimal
end
struct Call <: Action
end
struct Check <: Action
end
struct Fold <: Action
end

const CALL = Call()
const CHECK = Check()
const FOLD = Fold()


struct Board
    board::Array{Card}
end
Board(board::Union{String,SubString}) = Board([Card(card.match) for card in eachmatch(r"[\dTJQKA][cdhs]",board)])
flop(board::Board) = board.board[1:3]
turn(board::Board) = board.board[4]
river(board::Board) = board.board[5]
Cards.Hand(board::Board) = Hand(board.board)
Base.empty(Board) = Board([])

struct Player
    playername::String
    stacksize::Decimal
    cards:: Hand
end

struct Table
    tablename::String
    maxplayers::Int
    site::String
end

struct PokerHand
    gametype::AbstractString
    table::Table
    handno::Int
    datetime::DateTime
    timezone::AbstractString
    smallblind::Decimal
    bigblind::Decimal
    button::Int
    players::Vector{Player}
    posts::Dict{Int,Decimal}
    straddles::Dict{Int,Decimal}
    laststraddle::Int
    actions::AbstractString
    betsizes::Vector{Decimal}
    board::Board
    secondboard::Board
    totalpot::Decimal
    rake::Decimal
    deductions::Dict
    wins::Dict
    hhtext::AbstractString
end
struct PokerHandState
    pokerhand::PokerHand
    actionno::Int
    stacks::Array{Decimal}
    street::Street
    pot::Decimal
    playerturn::Int
    board::Array{Card}
end

headsup(game) = length(game.players) == 2

function playerconts(game::PokerHand)
    active = fill(true,length(game.players))
    toact = fill(true,length(game.players))
    playercont = fill(Decimal(0),length(game.players))
    playerdead = fill(Decimal(0),length(game.players))

    function nextplayer!()
        i = 0
        while true
            player = mod(player + 1,1:length(game.players))
            active[player] && break
            i += 1
            if i>length(game.players)
                @warn "Hand no $(game.handno) stuck in while loop"
                break
            end
        end
    end
    player = game.button

    amtid = 0
    function getamt()
        amtid += 1
        game.betsizes[amtid]
    end
    
    prevstreets = 0
    street = 1
    #postblinds
    !headsup(game) && nextplayer!()
    smallblind = player
    playercont[player] += game.smallblind
    nextplayer!()
    bigblind = player
    playercont[player] += game.bigblind

    for (k,v) in game.posts
        if k in [smallblind,bigblind]
            continue
        elseif v >= game.bigblind
            playercont[k] = game.bigblind
            playerdead[k] = v - game.bigblind
        elseif v < game.bigblind
            playerdead[k] = v
        end
    end
    for (k,v) in game.straddles
        playercont[k] = v
    end
    function stack(player)
        game.players[player].stacksize - playerdead[player]
    end
    currcall = game.bigblind
    if game.laststraddle > 0
        player = game.laststraddle
        currcall = playercont[game.laststraddle]
        if currcall >= stack(player)
            active[player] = false
            toact[player] = false
        end
    end
    for (i,action) in enumerate(game.actions)
        nextplayer!()
        if action == 'c'
            if currcall >= stack(player)
                playercont[player] = stack(player)
                active[player] = false
            else
                playercont[player] = currcall
            end
        elseif action in "rb"
            amt = getamt()
            currcall = amt + prevstreets
            playercont[player] = currcall
            if currcall == stack(player)
                active[player] = false
            end
            toact .= active
        elseif action == 'f'
            active[player] = false
        end
        toact[player] = false
        if !any(toact)
            ps = sort(playercont,rev=true)
            if ps[1] > ps[2]
                playercont[argmax(playercont)] = ps[2]
            end
            prevstreets = currcall
            street += 1
            player = game.button
            toact .= active
        end
    end
    ps = sort(playercont,rev=true)
    if ps[1] > ps[2]
        playercont[argmax(playercont)] = ps[2]
    end

    #@info game.handno

    playercont .+= playerdead
    if round(sum(playercont),digits=2) != game.totalpot
        @warn "Hand #$(game.handno) total pot of $(game.totalpot) does not match player conts of $(round(sum(playercont),digits=2))"
    end
    playercont
end

function conts(game::PokerHand,playername)
    playerconts(game)[findfirst(player->player.playername == playername,game.players)]
end

winnings(game,playername) = !haskey(game.wins,playername) ? 0 : game.wins[playername]

profit(game,playername) = winnings(game,playername) - conts(game,playername)

end # Module PokerGame