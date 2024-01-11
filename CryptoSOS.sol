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
    GameState private state;

    event StartGame(address player1, address player2);
    event Move(uint8 square, uint8 symbol, address player);
    event Winner(address winner);
    event Tie(address player1, address player2);

    address payable public owner;
    address payable public player1;
    address payable public player2;
    address public player_turn;
    
    //Contains the game board (1s and 2s). 1 = 'S', 2 = 'O'
    uint8[9] public game_grid;  

    uint256 public GAME_COST = 1 ether;
    uint256 private OWNER_PROFIT = 0 ether;

    constructor() {
        owner = payable (msg.sender);
        //by default (and obviously) when this contract starts there is no game nor players, so set to WAITING
        state = GameState.WAITING;  
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

    modifier checksBeforePlacing(uint8 position) {
        //check that the caller is one of the players
        require(msg.sender == player1 || msg.sender == player2, "[!] place: you are not a participant in this game");
        //check that there is an ongoing game
        require(state == GameState.PLAYING, "[!] place: no game is currently active to place symbol");
        //check who's turn it is to play
        require(msg.sender == player_turn, "[!] place: not your turn to play"); 
        //check for position input ([1-9])
        require(position >= 1 && position <= 9, "[!] place: position given must be between 1 and 9");
        //do not let player rewrite a previously played block
        require(game_grid[position-1] == 0, "[!] place: cannot overwrite a previously played block");
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
        if (containsSOS()) {  //if 'SOS' is in the grid, end the game
            state = GameState.FINISHED;
            payable(player_turn).transfer(1.7 ether);
            OWNER_PROFIT += 0.3 ether;
            emit Winner(player_turn);
            player1 = payable(address(0));
            player2 = payable(address(0));
            player_turn = payable(address(0));
            delete game_grid;
            return;
        } else if (outOfPlaces()) {  //if the grid does not contain 'SOS' but is out of places, it's a tie
            state = GameState.FINISHED;
            payable(player1).transfer(0.8 ether);
            payable(player2).transfer(0.8 ether);
            OWNER_PROFIT += 0.4 ether;
            emit Tie(player1, player2);
            player1 = payable(address(0));
            player2 = payable(address(0));
            player_turn = payable(address(0));
            delete game_grid;
            return;
        }

        //update player turn
        if (player_turn == player1) {
            player_turn = player2;
        } else {
            player_turn = player1;
        }
    }

    //public api

    function play() public payable {
        require(state != GameState.PLAYING, "[!] play: game is already ongoing, cannot join.");
        require(msg.sender != player1, "[!] play: you cannot play with yourself.");
        require(msg.value == GAME_COST, "[!] play: you must send exactly 1 ether to play.");

        //see which player has joined and set the corresponding address (by default addresses are 0x000..0)
        if (player1 == address(0)) {
            player1 = payable(msg.sender);
            //assume by default, player1 starts playing first
            player_turn = player1;
            last_join = block.timestamp;
            state = GameState.WAITING;
        } else if (player2 == address(0)) {
            player2 = payable(msg.sender);
            state = GameState.PLAYING;
            last_move = block.timestamp;  //no move has been made, just to know when the game started
        }
        emit StartGame(player1, player2);
    }

    function sweepProfit() public onlyOwner noReentrant {
        payable(address(owner)).transfer(OWNER_PROFIT);
        OWNER_PROFIT = 0 ether;
    }

    function placeS(uint8 position) public checksBeforePlacing(position) checksAfterPlacing {
        emit Move(position, 1, player_turn);
        position--;  //input is between 1 and 9, array 0 and 8, decrement
        game_grid[position] = 1;  //set the symbol
        last_move = block.timestamp;
    }

    function placeO(uint8 position) public checksBeforePlacing(position) checksAfterPlacing {
        emit Move(position, 2, player_turn);
        position--;
        game_grid[position] = 2;
        last_move = block.timestamp;
    }

    function getGameState() public view returns(string memory) {
        string memory board = "";
        //for each symbol saved on the board check if it is 1 or 2, and accordingly concatenate it on the string board
        for (uint8 i=0; i < game_grid.length; i++) {
            if (game_grid[i] == 1) {
                board = string.concat(board, "S");
            } else if (game_grid[i] == 2) {
                board = string.concat(board, "O");
            } else {
                board = string.concat(board, "-");
            }
        }
        return board;
    }

    function cancel() public {
        //game state must be waiting
        require(state == GameState.WAITING, "[!] cancel: cannot make this call right now");
        //only the player waiting (player1) can make this call, since only player1 is waiting
        require(msg.sender == player1 && player1 != address(0), "[!] cancel: you have no right to make this call");
        //check that 2 minutes have passed by
        require(block.timestamp - last_join >= CANCEL_TIME, "[!] cancel: cannot cancel yet");

        player1.transfer(GAME_COST);
        player1 = payable(address(0));
        player_turn = address(0);
    }

    function tooslow() public {
        //there must be an ongoing game
        require(state == GameState.PLAYING, "[!] tooslow: there is no active game");
        //the caller must be either the owner or one of the players
        require(msg.sender == owner || msg.sender == player1 || msg.sender == player2, "[!] tooslow: you have no right to make this call");
        
        if (msg.sender == owner) {
            uint t = block.timestamp - last_move;
            if (t >= TOOSLOW_TIME && t < TOOSLOW_TIME_OWNER && (owner == player1 || owner == player2)) {
                owner.transfer(1.9 ether); 
                OWNER_PROFIT += 0.1 ether;
                state = GameState.FINISHED;
                emit Winner(owner);
                player1 = payable(address(0));
                player2 = payable(address(0));
                player_turn = payable(address(0));
                delete game_grid;
            } else if (t >= TOOSLOW_TIME_OWNER) {
                //declare tie
                state = GameState.FINISHED;
                player1.transfer(0.8 ether);
                player2.transfer(0.8 ether);
                OWNER_PROFIT += 0.4 ether;
                emit Tie(player1, player2);
                player1 = payable(address(0));
                player2 = payable(address(0));
                player_turn = payable(address(0));
                delete game_grid;
            } else {
                revert("[!] tooslow: cannot make this call right now");
            }
        } else {
            if (msg.sender == player1) {
                require(player_turn == player2, "[!] tooslow: you cannot make this call since it's your turn");
            } else {
                require(player_turn == player1, "[!] tooslow: you cannot make this call since it's your turn");
            }
            require(block.timestamp - last_move >= TOOSLOW_TIME, "[!] tooslow: cannot stop the game yet");
            state = GameState.FINISHED;
            player_turn == player1 ? player2.transfer(1.9 ether) : player1.transfer(1.9 ether);
            OWNER_PROFIT += 0.1 ether;
            emit Winner(player_turn == player1 ? player2 : player1);
            player1 = payable(address(0));
            player2 = payable(address(0));
            player_turn = payable(address(0));
            delete game_grid;
        }
    }

    //private-internal functions 

    /*
    This function checks if the grid contains the word 'SOS'. If it does, it returns true (the game must end), else returns false.
    */
    function containsSOS() private view returns(bool) {
        /* sample grid, just to visualize
        S O S
        O O O
        S O S
        consider all cases manually */
        if (game_grid[0] == 1 && game_grid[1] == 2 && game_grid[2] == 1)  //1st row
            return true;
        else if (game_grid[3] == 1 && game_grid[4] == 2 && game_grid[5] == 1)  //2rd row
            return true;
        else if (game_grid[6] == 1 && game_grid[7] == 2 && game_grid[8] == 1)  //3rd row
            return true;

        else if (game_grid[0] == 1 && game_grid[3] == 2 && game_grid[6] == 1)  //1st column
            return true;
        else if (game_grid[1] == 1 && game_grid[4] == 2 && game_grid[7] == 1)  //2nd column
            return true;
        else if (game_grid[2] == 1 && game_grid[5] == 2 && game_grid[8] == 1)  //3rd column
            return true;

        else if (game_grid[0] == 1 && game_grid[4] == 2 && game_grid[8] == 1)  //main diagonal
            return true;
        else if (game_grid[2] == 1 && game_grid[4] == 2 && game_grid[6] == 1)  //secondary diagonal
            return true;
        return false;
    }

    /*
    This function checks if all blocks contain a symbol, i.e., all 9 positions are occupied
    */
    function outOfPlaces() private view returns(bool){
        for (uint8 i=0; i < game_grid.length; i++) {
            if (game_grid[i] == 0)  //if one zero exists, obviously not all positions are occupied
                return false;
        }
        return true;
    }
}

