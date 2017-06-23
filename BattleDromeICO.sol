pragma solidity ^0.4.11;

import "FAMEToken.sol"; 

//------------------------------------------------------------------------------------------------
// ICO Crowd Sale Contract
// Works like a kickstarter. Minimum goal required, or everyone gets their money back
// Contract holds all tokens, upon success (passing goal on time) sends out all bought tokens
// It then burns the rest.
// In the event of failure, it sends tokens back to creator, and all payments back to senders.
// Each time tokens are bought, a percentage is also issued to the "Developer" account.
// Pay-out of collected Ether to creators is managed through an Escrow address.
// Copyright 2017 BattleDrome
//------------------------------------------------------------------------------------------------

//------------------------------------------------------------------------------------------------
// LICENSE
//
// This file is part of BattleDrome.
// 
// BattleDrome is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// BattleDrome is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with BattleDrome.  If not, see <http://www.gnu.org/licenses/>.
//------------------------------------------------------------------------------------------------

contract BattleDromeICO {
	uint public constant ratio = 100 szabo;				//Ratio of how many tokens (in absolute uint256 form) are issued per ETH
	uint public constant minimumPurchase = 1 finney;	//Minimum purchase size (of incoming ETH)
	uint public constant startBlock = 3960000;			//Starting Block Number of Crowsd Sale
	uint public constant duration = 190000;				//16s block times 190k is about 35 days, from July 1st, to approx first Friday of August.
	uint public constant fundingGoal = 500 ether;		//Minimum Goal in Ether Raised
	uint public constant fundingMax = 20000 ether;		//Maximum Funds in Ether that we will accept before stopping the crowdsale
	uint public constant devRatio = 20;					//Ratio of Sold Tokens to Dev Tokens (ie 20 = 20:1 or 5%)
	address public constant tokenAddress 	= "0x0000000000000000000000000000000000000000";	//Address of ERC20 Token Contract
	address public constant escrow 			= "0x50115D25322B638A5B8896178F7C107CFfc08144"; //Address of Escrow Provider Wallet

	FAMEToken public Token;
	address public creator;
	uint public savedBalance;

	mapping(address => uint) balances;			//Balances in incoming Ether
	mapping(address => uint) savedBalances;		//Saved Balances in incoming Ether (for after withdrawl validation)

	//Constructor, initiate the crowd sale
	function BattleDromeICO() {
		Token = FAMEToken(tokenAddress);				//Establish the Token Contract to handle token transfers					
		creator = msg.sender;							//Establish the Creator address for receiving payout if/when appropriate.
	}

	//Default Function, accepts incoming payments and tracks balances
	function () payable {
		require(isStarted());								//Has the crowdsale even started yet?
		require(this.balance<=fundingMax); 					//Does this payment send us over the max?
		require(msg.value >= minimumPurchase);              //Require that the incoming amount is at least the minimum purchase size.
		require(!isComplete()); 							//Has the crowdsale completed? We only want to accept payments if we're still active.
		balances[msg.sender] += msg.value;					//If all checks good, then accept contribution and record new balance.
		savedBalances[msg.sender] += msg.value;		    	//Save contributors balance for later	
		savedBalance += msg.value;							//Save the balance for later when we're doing pay-outs so we know what it was.
		Contribution(msg.sender,msg.value,now);             //Woohoo! Log the new contribution!
	}

	//Function to view current token balance of the crowdsale contract
	function tokenBalance() constant returns(uint balance) {
		return Token.balanceOf(address(this));
	}

	//Function to check if crowdsale has started yet, have we passed the start block?
	function isStarted() constant returns(bool) {
		return block.number >= startBlock;
	}

	//Function to check if crowdsale is complete (have we eigher hit our max, or passed the crowdsale completion block?)
	function isComplete() constant returns(bool) {
		return (savedBalance >= fundingMax) || (block.number > (startBlock + duration));
	}

	//Function to check if crowdsale has been successful (has incoming contribution balance met, or exceeded the minimum goal?)
	function isSuccessful() constant returns(bool) {
		return (savedBalance >= fundingGoal);
	}

	//Function to check the Ether balance of a contributor
	function checkEthBalance(address _contributor) constant returns(uint balance) {
		return balances[_contributor];
	}

	//Function to check the Saved Ether balance of a contributor
	function checkSavedEthBalance(address _contributor) constant returns(uint balance) {
		return savedBalances[_contributor];
	}

	//Function to check the Token balance of a contributor
	function checkTokBalance(address _contributor) constant returns(uint balance) {
		return (balances[_contributor] * ratio) / 1 ether;
	}

	//Function to check the current Tokens Sold in the ICO
	function checkTokSold() constant returns(uint total) {
		return (savedBalance * ratio) / 1 ether;
	}

	//Function to get Dev Tokens issued during ICO
	function checkTokDev() constant returns(uint total) {
		return checkTokSold() / devRatio;
	}

	//Function to get Total Tokens Issued during ICO (Dev + Sold)
	function checkTokTotal() constant returns(uint total) {
		return checkTokSold() + checkTokDev();
	}

	//function to check percentage of goal achieved
	function percentOfGoal() constant returns(uint16 goalPercent) {
		return uint16((savedBalance*100)/fundingGoal);
	}

	//function to initiate payout of either Tokens or Ether payback.
	function payMe() {
		require(isComplete()); //No matter what must be complete
		if(isSuccessful()) {
			payTokens();
		}else{
			payBack();
		}
	}

	//Function to pay back Ether
	function payBack() internal {
		require(balances[msg.sender]>0);				//Does the requester have a balance?
		msg.sender.transfer(balances[msg.sender]);		//Send them back their balance in Ether
		PayEther(msg.sender,balances[msg.sender],now); 	//Log payback of ether
		balances[msg.sender] = 0;						//And zero their balance.
	}

	//Function to pay out Tokens
	function payTokens() internal {
		require(balances[msg.sender]>0);					//Does the requester have a balance?
		uint tokenAmount = checkTokBalance(msg.sender);		//If so, then let's calculate how many Tokens we owe them
		Token.transfer(msg.sender,tokenAmount);				//And transfer the tokens to them
		balances[msg.sender] = 0;							//Zero their balance
		PayTokens(msg.sender,tokenAmount,now);          	//Log payout of tokens to contributor
	}

	//Function to pay the creator upon success
	function payCreator() {
		require(isComplete());										//Creator can only request payout once ICO is complete
		if(isSuccessful()){
			uint tokensToBurn = tokenBalance() - checkTokTotal();	//How many left-over tokens after sold, and dev tokens are accounted for? (calculated before we muck with balance)
			PayEther(escrow,this.balance,now);      				//Log the payout to escrow
			escrow.transfer(this.balance);							//We were successful, so transfer the balance to the escrow address
			PayTokens(creator,checkTokDev(),now);       			//Log payout of tokens to creator
			Token.transfer(creator,checkTokDev());					//And since successful, send DevRatio tokens to devs directly			
			Token.burn(tokensToBurn);								//Burn any excess tokens;
			BurnTokens(tokensToBurn,now);        					//Log the burning of the tokens.
		}else{
			PayTokens(creator,tokenBalance(),now);       			//Log payout of tokens to creator
			Token.transfer(creator,tokenBalance());					//We were not successful, so send ALL tokens back to creator.
		}
	}
	
	//Event to record new contributions
	event Contribution(
	    address indexed _contributor,
	    uint indexed _value,
	    uint indexed _timestamp
	    );
	    
	//Event to record each time tokens are paid out
	event PayTokens(
	    address indexed _receiver,
	    uint indexed _value,
	    uint indexed _timestamp
	    );

	//Event to record each time Ether is paid out
	event PayEther(
	    address indexed _receiver,
	    uint indexed _value,
	    uint indexed _timestamp
	    );
	    
	//Event to record when tokens are burned.
	event BurnTokens(
	    uint indexed _value,
	    uint indexed _timestamp
	    );

}
