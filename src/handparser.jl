using PokerGame
using Cards
using Dates
using Decimals
using DataFrames

# in private you can set defaultfolder and hero name
include("private.jl")

function getHandHistories(folderpath=defaultfolder;hero=hero)
    hhs = parsehandhistoryfolder(folderpath;subfolders=true);
    df = DataFrame(hh = hhs, profit=profit.(hhs,hero))
end

function parsehandhistoryfolder(folderpath;subfolders=false,filt="")
    hhs::Array{PokerHand} = []
    for filepath in readdir(folderpath,join=true)
        if isdir(filepath) && subfolders
            append!(hhs,parsehandhistoryfolder(filepath;subfolders=false,filt=filt))
        elseif occursin(filt,filepath)
            append!(hhs,parsehandhistoryfile(filepath))
        end
    end
    hhs
end

function gethandarray(filename)
    text = read(filename,String)
    text = replace(text,'\ufeff'=>"")
    # GG Poker uses \n\n\n and Pokerstars uses \r\n\r\n\r\n\r\n to seperate hand histories
    hands = split(text,r"\r?\n\r?\n\r?\n\r?\n?")
    # Filter makes sure no empty hands
    filter!(!=(""),hands)
end

function parsehandhistoryfile(filename)
    hands = gethandarray(filename)
    hhs::Vector{PokerHand}=[]
    for (i,hand) in enumerate(hands)
        try
            push!(hhs,parsehandhistory(hand))
        catch err
            @info "Hand number $i in $filename failed to parse"
            #rethrow()
        end
    end
    hhs
end

function parsehandhistory(hand;site="PokerStars")

    game = match(r"Poker(?:Stars)?(?: Zoom)? Hand #(?<handcode>\w\w)?(?<handno>\d+):  ?(?<gametype>.+) \(\$(?<smallblind>\d+(?:\.\d\d?)?)/\$(?<bigblind>\d+(?:\.\d\d?)?)(?: (?<curr>\w\w\w))?\) - (?<datetime>\d\d\d\d\/\d\d\/\d\d \d\d?:\d\d:\d\d)(?: (?<timezone>\w\w\w?))?",hand)
    gametype = game["gametype"]
    handno = parse(Int,game["handno"])
    smallblind = parse(Decimal,game["smallblind"])
    bigblind = parse(Decimal,game["bigblind"])
    datetime = DateTime(game["datetime"],dateformat"y/m/d H:M:S")
    timezone = something(game["timezone"],"UTC")

    table = match(r"Table '(?<tablename>[\w -]+)' (?<tablesize>\d{1,2})-max Seat #(?<buttonseat>\d\d?) is the button",hand)
    tablename = table["tablename"]
    tablesize = parse(Int,table["tablesize"])
    buttonseat = parse(Int,table["buttonseat"])

    playersregex = eachmatch(r"Seat (?<seatno>\d): (?<playername>.+) \(\$(?<stacksize>\d+(?:\.\d\d?)?) in chips\)(?! is sitting out)",hand)
    players = Player[]

    herocards = match(r"Dealt to (?<playername>.+) \[(?<cards>[\w\d ]+)\]",hand)
    playerhands = Dict(getindex.(playersregex,"playername") .=> Ref(empty(Hand)))
    playerhands[herocards["playername"]] = Hand(herocards["cards"])

    playercards = eachmatch(r"Seat (?<seatno>\d\d?): (?<playername>.+) (?:\((?:big blind|small blind|button)\) )(?:showed|mucked) \[(?<cards>[\w ]+)\]",hand)

    for hand in playercards
        playerhands[hand["playername"]] = Hand(hand["cards"])
    end
    button = 0
    for (i,player) in enumerate(playersregex)
        seat = parse(Int,player["seatno"])
        seat == buttonseat && (button = i)
        playername = player["playername"]
        stacksize = parse(Decimal,player["stacksize"])
        push!(players,Player(playername,stacksize,playerhands[playername]))
    end

    boards = match(r"Board \[(?<board>.+)\](?:\r?\nSECOND Board \[(?<board2>.+)\])?",hand)
    board = empty(Board)
    board2 = empty(Board)
    if !isnothing(boards)
        board = Board(boards["board"])
        if !isnothing(boards["board2"])
            board2 = Board(boards["board2"])
        end
    end

    blinds = eachmatch(r"(?<playername>.+): (?<action>posts (?:small|big|small & big|missed) blinds?)(?: \$(?<amount1>[\d\.]+))",hand)
    posts = Dict{Int,Decimal}()
    for blind in blinds
        player = findfirst(x->x.playername==blind["playername"],players)
        if !haskey(posts,player)
            posts[player] = 0
        end
        posts[player] += parse(Decimal,blind["amount1"])
    end
    straddlesregex = eachmatch(r"(?<playername>.+): straddle \$(?<amount>[\d\.]+)",hand)
    straddles = Dict{Int,Decimal}()
    laststraddle = 0
    for straddle in straddlesregex
        player = findfirst(x->x.playername==straddle["playername"],players)
        straddles[player] = parse(Decimal,straddle["amount"])
        laststraddle = player
    end

    actionsection = match(r"\*\*\* HOLE CARDS \*\*\*\r?\n(?<actions>.+)\*\*\* SUMMARY \*\*\*"s,hand)
    actions = eachmatch(r"(?<playername>.+): (?<action>checks|folds|raises|calls|bets)(?: \$(?<amount1>[\d\.]+))?(?: to \$(?<amount2>[\d\.]+))?",actionsection["actions"])
    actionstring = ""
    actionamounts = []
    for action in actions
        actionstring *= action["action"][1]
        if action["action"][1] in "rb"
            if !isnothing(action["amount2"])
                push!(actionamounts,parse(Decimal,action["amount2"]))
            elseif !isnothing(action["amount1"])
                push!(actionamounts,parse(Decimal,action["amount1"]))
            end
        end
    end

    winnings = eachmatch(r"(?<playername>.+) (?:collected|cashed out the hand for) \$(?<amount>[\d\.]+)",hand)
    winningplayers = []
    winningamounts = []
    for win in winnings
        push!(winningplayers,win["playername"])
        push!(winningamounts,parse(Decimal,win["amount"]))
    end
    wins = Dict(x=>sum(winningamounts[x.==winningplayers]) for x in unique(winningplayers))

    pot = match(r"Total pot \$(?<totalpot>[\d\.]+)(?: \| Rake \$(?<rake>[\d\.]+))?(?: \| Jackpot \$(?<jackpot>[\d\.]+))?",hand)
    totalpot = parse(Decimal,pot["totalpot"])
    rake =  parse(Decimal,something(pot["rake"],"0"))
    deductions = Dict{String,Decimal}()
    if !isnothing(pot["jackpot"])
        deductions["jackpot"] = parse(Decimal,pot["jackpot"])
    end

    PokerHand(gametype,Table(tablename,tablesize,site),handno,datetime,timezone,
        smallblind,bigblind,button,players,posts,straddles,laststraddle,
        actionstring,actionamounts,board,board2,totalpot,rake,deductions,wins,hand)

end