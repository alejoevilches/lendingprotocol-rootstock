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
        address owner
        uint256 amount
        uint256 startDate
        uint256 dueDate
    }

    Loan[] private loansCollection;

    mapping(address=>Loan) userToLoan;

    function createLoan(uint256 amount){
        raffleCollection.push(
            Loan({
                address: msg.sender,
                amount,
                startDate: block.timestamp
            })
        )
    }
}