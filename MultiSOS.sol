// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

//todo: owner may be player when calling tooslow
contract CryptoSOS {

    bool internal locked;  //to avoid re-entrancy

    uint constant CANCEL_TIME = 2 minutes;
    uint constant TOOSLOW_TIME = 1 minutes;
    uint constant TOOSLOW_TIME_OWNER = 5 minutes;

    uint last_join;  //store when the last play call was made
    uint last_move;  //store when the last move was made

    enum GameState{WAITING, PLAYING, FINISHED}

    event StartGame(address player1, address player2);
    event Move(uint8 square, uint8 symbol, address player);
    event Winner(address winner);
    event Tie(address player1, address player2);

    struct Game {
        GameState state;
        address payable p1;
        address payable p2;
        address p_turn;
        uint8[] game_grid;  
        uint last_join;
        uint last_move;
    }

    Game[] public games;

    address payable public owner;

    uint256 public GAME_COST = 1 ether;
    uint256 public WINNER_AWARD = 1.7 ether;
    uint256 public TIE_AWARD = 0.8 ether;
    uint256 private OWNER_PROFIT = 0 ether;

    constructor() {
        owner = payable (msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "[!] onlyOwner: only the owner can make this call.");
        _;
    }

    modifier noReentrant() {  //modifier that "locks" a function to ensure no-reentrancy
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier gameExists() {
        Game memory g = lookupGame(msg.sender);
        require(g.p1 != payable(address(0)) && g.p1 != payable(address(0)) && g.last_join != 0, "[!] gameExists: this game does not exist");
        _;
    }

    modifier checksBeforePlacing(uint8 position) {
        uint last_pos = getLastGame(msg.sender);
        Game memory g;
        if (last_pos == games.length) {
            g = lookupGameStorage(msg.sender);
        } else {
            g = games[last_pos];
        }
        //check that the caller is one of the players
        require(msg.sender == g.p1 || msg.sender == g.p2, "[!] place: you are not a participant in this game");
        //check that there is an ongoing game
        require(g.state == GameState.PLAYING, "[!] place: no game is currently active to place symbol");
        //check who's turn it is to play
        require(msg.sender == g.p_turn, "[!] place: not your turn to play"); 
        //check for position input ([1-9])
        require(position >= 1 && position <= 9, "[!] place: position given must be between 1 and 9");
        //do not let player rewrite a previously played block
        require(g.game_grid[position-1] == 0, "[!] place: cannot overwrite a previously played block");
        _;
    }

    /*
    This modifier:
    1. Checks if there is a win => awards the player, ends the game
    2. Checks if there is a tie => awards the players, ends the game
    3. If none of these happens, just update the player turn
    */
    modifier checksAfterPlacing() {
        _;
        uint last_pos = getLastGame(msg.sender);
        Game storage g;
        if (last_pos == games.length) {
            g = lookupGameStorage(msg.sender);
        } else {
            g = games[last_pos];
        }
        //Game storage g = lookupGameStorage(msg.sender);
        if (containsSOS(g.game_grid)) {  //if 'SOS' is in the grid, end the game
            g.state = GameState.FINISHED;
            payable(g.p_turn).transfer(WINNER_AWARD);
            OWNER_PROFIT += 0.3 ether;
            emit Winner(g.p_turn);
            return;
        } else if (outOfPlaces(g.game_grid)) {  //if the grid does not contain 'SOS' but is out of places, it's a tie
            g.state = GameState.FINISHED;
            payable(g.p1).transfer(TIE_AWARD);
            payable(g.p2).transfer(TIE_AWARD);
            OWNER_PROFIT += 0.4 ether;
            emit Tie(g.p1, g.p2);
            return;
        }
        //update player turn
        if (g.p_turn == g.p1) {
            g.p_turn = g.p2;
        } else {
            g.p_turn = g.p1;
        }
    }

    //public api

    function play() public payable {
        require(msg.value == GAME_COST, "[!] play: you must send exactly 1 ether to play.");
        uint last_pos = getLastGame(msg.sender);
        Game memory g;
        if (last_pos == games.length) {
            g = lookupGame(msg.sender);
        } else {
            g = games[last_pos];
            require(g.state == GameState.FINISHED, "[!] play: cannot join another game");
            matchPlayerToGame(msg.sender);
            return;
        }
        require(g.state != GameState.PLAYING, "[!] play: game is already ongoing, cannot join.");
        require(msg.sender != g.p1, "[!] play: you cannot play with yourself.");
        matchPlayerToGame(msg.sender);
    }

    function sweepProfit() public onlyOwner noReentrant {  //todo noReentrant
        payable(address(owner)).transfer(OWNER_PROFIT);
        OWNER_PROFIT = 0 ether;
    }

    function placeS(uint8 position) public gameExists checksBeforePlacing(position) checksAfterPlacing {
        //Game storage g = lookupGameStorage(msg.sender);
        uint last_pos = getLastGame(msg.sender);
        Game storage g;
        if (last_pos == games.length) {
            g = lookupGameStorage(msg.sender);
        } else {
            g = games[last_pos];
        }
        emit Move(position, 1, g.p_turn);
        position--;  //input is between 1 and 9, array 0 and 8, decrement
        g.game_grid[position] = 1;  //set the symbol
        g.last_move = block.timestamp;
    }

    function placeO(uint8 position) public gameExists checksBeforePlacing(position) checksAfterPlacing {
        //Game storage g = lookupGameStorage(msg.sender);
        uint last_pos = getLastGame(msg.sender);
        Game storage g;
        if (last_pos == games.length) {
            g = lookupGameStorage(msg.sender);
        } else {
            g = games[last_pos];
        }
        emit Move(position, 2, g.p_turn);
        position--;
        g.game_grid[position] = 2;
        g.last_move = block.timestamp;
    }

    function getGameState() public gameExists view returns(string memory) {
        string memory board = "";
        uint last_pos = getLastGame(msg.sender);
        Game memory g;
        if (last_pos == games.length) {
            g = lookupGameStorage(msg.sender);
        } else {
            g = games[last_pos];
        }
        //for each symbol saved on the board check if it is 1 or 2, and accordingly concatenate it on the string board
        for (uint8 i=0; i < g.game_grid.length; i++) {
            if (g.game_grid[i] == 1) {
                board = string.concat(board, "S");
            } else if (g.game_grid[i] == 2) {
                board = string.concat(board, "O");
            } else {
                board = string.concat(board, "-");
            }
        }
        return board;
    }

    function cancel() public gameExists(){
        Game memory g = lookupGame(msg.sender);
        //game state must be waiting
        require(g.state == GameState.WAITING, "[!] cancel: cannot make this call right now");
        //only the player waiting (player1) can make this call, since only player1 is waiting
        require(msg.sender == g.p1 && g.p1 != address(0), "[!] cancel: you have no right to make this call");
        //check that 2 minutes have passed by
        require(block.timestamp - g.last_join >= CANCEL_TIME, "[!] cancel: cannot cancel yet");

        g.p1.transfer(GAME_COST);
        //in the last game, meaning the last element of the games array, if p1 is waiting p2
        //and p1 decides to click cancel, pop the element. there cannot be any game ongoing or waiting
        //after this one, because p2 would have been matched with p1 making this call right now 
        games.pop();  
    }

    function tooslow() public gameExists{
        uint last_pos = getLastGame(msg.sender);
        Game storage g;
        if (last_pos == games.length) {
            g = lookupGameStorage(msg.sender);
        } else {
            g = games[last_pos];
        }
        //there must be an ongoing game
        require(g.state == GameState.PLAYING, "[!] tooslow: there is no active game");
        //the caller must be either the owner or one of the players
        require(msg.sender == owner || msg.sender == g.p1 || msg.sender == g.p2, "[!] tooslow: you have no right to make this call");
        
        if (msg.sender == owner) {
            uint t = block.timestamp - g.last_move;
            if (t >= TOOSLOW_TIME && t < TOOSLOW_TIME_OWNER && (owner == g.p1 || owner == g.p2)) {
                owner.transfer(1.9 ether); 
                OWNER_PROFIT += 0.1 ether;
                g.state = GameState.FINISHED;
                emit Winner(owner);
            } else if (t >= TOOSLOW_TIME_OWNER) {
                //declare tie
                g.state = GameState.FINISHED;
                g.p1.transfer(TIE_AWARD);
                g.p2.transfer(TIE_AWARD);
                OWNER_PROFIT += 0.4 ether;
                emit Tie(g.p1, g.p2);
            } else {
                revert("[!] tooslow: cannot make this call right now");
            }
        } else {
            if (msg.sender == g.p1) {
                require(g.p_turn == g.p2, "[!] tooslow: you cannot make this call since it's your turn");
            } else {
                require(g.p_turn == g.p1, "[!] tooslow: you cannot make this call since it's your turn");
            }
            require(block.timestamp - g.last_move >= TOOSLOW_TIME, "[!] tooslow: cannot stop the game yet");
            g.state = GameState.FINISHED;
            g.p_turn == g.p1 ? g.p2.transfer(1.9 ether) : g.p1.transfer(1.9 ether);
            OWNER_PROFIT += 0.1 ether;
            emit Winner(g.p_turn == g.p1 ? g.p2 : g.p1);
        }
    }

    //private-internal functions 

    /*
    This function checks if the grid contains the word 'SOS'. If it does, it returns true (the game must end), else returns false.
    */
    function containsSOS(uint8[] memory grid) private pure returns(bool) {
        /* sample grid, just to visualize
        S O S
        O O O
        S O S
        consider all cases manually */
        if (grid[0] == 1 && grid[1] == 2 && grid[2] == 1)  //1st row
            return true;
        else if (grid[3] == 1 && grid[4] == 2 && grid[5] == 1)  //2rd row
            return true;
        else if (grid[6] == 1 && grid[7] == 2 && grid[8] == 1)  //3rd row
            return true;

        else if (grid[0] == 1 && grid[3] == 2 && grid[6] == 1)  //1st column
            return true;
        else if (grid[1] == 1 && grid[4] == 2 && grid[7] == 1)  //2nd column
            return true;
        else if (grid[2] == 1 && grid[5] == 2 && grid[8] == 1)  //3rd column
            return true;

        else if (grid[0] == 1 && grid[4] == 2 && grid[8] == 1)  //main diagonal
            return true;
        else if (grid[2] == 1 && grid[4] == 2 && grid[6] == 1)  //secondary diagonal
            return true;
        return false;
    }

    /*
    This function checks if all blocks contain a symbol, i.e., all 9 positions are occupied
    */
    function outOfPlaces(uint8[] memory grid) private pure returns(bool){
        for (uint8 i=0; i < grid.length; i++) {
            if (grid[i] == 0)  //if one zero exists, obviously not all positions are occupied
                return false;
        }
        return true;
    }

    /*
    This function checks if an address is already playing a game
    */
    function lookupGame(address player) private view returns(Game memory) {
        for (uint i=0; i<games.length; i++) {
            Game storage game = games[i];
            if (player == game.p1 || player == game.p2) {
                return game;
            }
        }
        Game memory g = Game(GameState.WAITING, payable(address(0)), payable(address(0)), address(0), new uint8[](9), 0, 0);
        return g;
    }

    function lookupGameStorage(address player) private view returns(Game storage) {
        Game storage game = games[0];  //this is not going to be true, just initialize
        for (uint i=0; i<games.length; i++) {
            Game storage currentGame = games[i];
            if (player == currentGame.p1 || player == currentGame.p2) {
                game = currentGame;
                break;
            }
        }
        return game;
    }

    /*
    This function returns the position in the game array of the last game that a specific address played.
    */
    function getLastGame(address player) private view returns(uint) {
        uint pos = games.length;
        for (uint i=0; i<games.length; i++) {
            Game storage game = games[i];
            if (player == game.p1 || player == game.p2) {
                pos = i;
            }
        }
        return pos;
    }

    /*
    This function is called inside the play function, and matches the caller to a game, 
    either with someone waiting, or creates a new game and sets the game to Waiting for a second player
    If games list is empty, create a new game.
    If games list is not empty, go to the last element in the list.
        If p1 and p2 are not address(0), then the last game is full -> create a new one
        If not, logically, p2 is address(0), so just assign the sender address to p2
    */
    function matchPlayerToGame(address player) private {
        if (games.length == 0) {
            games.push(Game(GameState.WAITING, payable(player), payable(address(0)), payable(player), new uint8[](9), block.timestamp, 0)); 
            emit StartGame(games[0].p1, games[0].p2);
            return;
        }
        Game storage g = games[games.length-1];
        if (g.p1 != address(0) && g.p2 != address(0)) {  //or just, if g.state == GameState.PLAYING
            games.push(Game(GameState.WAITING, payable(player), payable(address(0)), payable(player), new uint8[](9), block.timestamp, 0)); 
            emit StartGame(games[games.length-1].p1, games[games.length-1].p2);
        } else if (g.p1 != payable(address(0)) && g.p2 == payable(address(0))) {
            //require(player != g.p1, "[!] play: cannot play with yourself");
            g.p2 = payable(player);
            g.state = GameState.PLAYING;
            g.last_join = block.timestamp;
            g.last_move = block.timestamp;
            emit StartGame(g.p1, g.p2);
        }        
    }
}