// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LendingProtocol{
    enum LendingState{
        REQUESTED,
        BIDDING,
        CLOSED,
        PAYED,
        DEFAULTED
    };

    struct Loan{
        uint256 id
        address owner
        LendingState status
        uint256 amount
        uint256 startDate
        uint256 dueDate
    }

    Loan[] private loansCollection;
    uint256 loanCounter;

    mapping(uint256=>Loan) idToLoan;

    function createLoan(uint256 amount){
        raffleCollection.push(
            Loan({
                id: loanCounter
                address: msg.sender,
                amount,
                status: LendingState.REQUESTED
            })
        )
        userToLoan[loanCounter] = loanCounter;
        loanCounte++;
    }
}