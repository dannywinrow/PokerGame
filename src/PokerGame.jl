module PokerGame

using Cards
using Decimals
using Dates

import Base.empty
import Cards.Hand
import Cards.Card

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
Main.Cards.Hand(board::Board) = Hand(board.board)
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
    gametype::String
    table::Table
    handno::Int
    datetime::DateTime
    timezone::String
    smallblind::Decimal
    bigblind::Decimal
    players::Vector{Player}
    actions::String
    betsizes::Vector{Decimal}
    board::Board
    secondboard::Board
    totalpot::Decimal
    rake::Decimal
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

end # Module PokerGame