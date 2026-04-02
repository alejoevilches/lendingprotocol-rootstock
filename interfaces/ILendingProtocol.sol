// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILendingProtocol {
    enum LendingState {
        REQUESTED,
        BIDDING,
        CLOSED,
        PAYED,
        DEFAULTED
    }

    struct Loan {
        uint256 id;
        address owner;
        LendingState status;
        uint256 amount;
        uint256 startDate;
        uint256 dueDate;
        address lender;
        uint256 bestBidId;
        bool hasBestBid;
    }

    struct Bid {
        uint256 id;
        uint256 loanId;
        address bidder;
        uint256 interest;
        uint256 principal;
        bool withdrawn;
    }

    event LoanCreated(uint256 indexed loanId, address indexed owner, uint256 amount);
    event BiddingStarted(uint256 indexed loanId);
    event BidPlaced(uint256 indexed loanId, uint256 indexed bidId, address indexed bidder, uint256 interest);
    event LoanClosed(uint256 indexed loanId, uint256 indexed winningBidId, address indexed lender);
    event LoanPayed(uint256 indexed loanId, uint256 amount);
    event LoanDefaulted(uint256 indexed loanId);

    function createLoan(uint256 amount) external;
    function startBiddingProcess(uint256 loanId) external;
    function bidLoan(uint256 loanId, uint256 interest) external payable;
    function closeLoan(uint256 loanId) external;
    function payLoan(uint256 loanId) external payable;
    function defaultLoan(uint256 loanId) external;
    function withdraw() external;
    function withdrawBid(uint256 bidId) external;

    function getLoan(uint256 loanId) external view returns (Loan memory);
    function getBid(uint256 bidId) external view returns (Bid memory);
    function getLoanBidIds(uint256 loanId) external view returns (uint256[] memory);
    function getWinningBidId(uint256 loanId) external view returns (uint256);
    function getPendingWithdrawal(address account) external view returns (uint256);

    function loanCounter() external view returns (uint256);
    function bidCounter() external view returns (uint256);
    function ADMIN() external view returns (address);
}