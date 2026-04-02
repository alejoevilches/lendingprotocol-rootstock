// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "./interfaces/ILendingProtocol.sol";

/// @title LendingProtocol
/// @author Alejo Vilches
/// @notice A lending protocol contract for managing loans and bids. Final project for the Rootstock Rootcamp.
contract LendingProtocol is ILendingProtocol{

    error CreateLoan_ZeroAmount();
    error BidLoan_LoanNotInBiddingStatus();
    error BidLoan_InvalidInterestRate();
    error BidLoan_InvalidPrincipalAmount();
    error BidLoan_OwnerCannotBid();
    error BidLoan_DuplicateBidder();
    error StartBiddingProcess_InvalidStateOfLoan();
    error InvalidLoanId();
    error CloseLoan_InvalidStateOfLoan();
    error CloseLoan_LoanHasNoBids();
    error CloseLoan_ErrorFundingBorrower();
    error DefaultLoan_LoanNotInClosedStatus();
    error PayLoan_NotEnoughRBTC();
    error PayLoan_ErrorRefundingRBTC();
    error PayLoan_ErrorPayingLoan();
    error PayLoan_InvalidState();
    error PayLoan_ZeroLender();
    error PayLoan_PastDueDate();
    error Withdraw_NoFunds();
    error Withdraw_ErrorSendingRBTC();
    error OnlyLoanOwner_NotOwner();
    error InvalidBidId();
    error WithdrawBid_AlreadyWithdrawn();
    error WithdrawBid_NotYourBid();
    error WithdrawBid_WinnerCannotWithdraw();
    error WithdrawBid_LoanStillActive();

    uint256 private constant MAX_INTEREST_BASIS_POINT=10000;

    uint256 public loanCounter;
    uint256 public bidCounter;

    mapping(uint256=>Loan) private idToLoan;
    mapping(uint256=>Bid) private idToBid;
    mapping(uint256=>uint256[]) private loanIdToBidId;
    mapping(uint256=>uint256) private loanIdToWinningBidId;
    mapping(address=>uint256) private pendingWithdrawals;
    mapping(uint256=>mapping(address=>bool)) private hasBidForLoan;

    address public immutable ADMIN;

    constructor(){
        ADMIN = msg.sender;
    }

    modifier validLoan(uint256 loanId){
        if(loanId >= loanCounter) revert InvalidLoanId();
        _;
    }

    modifier onlyLoanOwner(uint256 loanId){
        if(idToLoan[loanId].owner != msg.sender) revert OnlyLoanOwner_NotOwner();
        _;
    }

    modifier onlyLoanOwnerOrAdmin(uint256 loanId){
        if(idToLoan[loanId].owner != msg.sender && msg.sender != ADMIN) revert OnlyLoanOwner_NotOwner();
        _;
    }

    function createLoan(uint256 amount) external{
        if(amount == 0) revert CreateLoan_ZeroAmount();
        Loan memory payload = Loan({
            id: loanCounter,
            owner: msg.sender,
            amount: amount,
            status: LendingState.REQUESTED,
            startDate: 0,
            dueDate: 0,
            lender: address(0),
            bestBidId: 0,
            hasBestBid: false
        });
        idToLoan[loanCounter] = payload;
        ++loanCounter;
        emit LoanCreated(loanCounter - 1, msg.sender, amount);
    }

    function startBiddingProcess(uint256 loanId) external validLoan(loanId) onlyLoanOwnerOrAdmin(loanId){
        if(idToLoan[loanId].status != LendingState.REQUESTED) revert StartBiddingProcess_InvalidStateOfLoan();
        idToLoan[loanId].status = LendingState.BIDDING;
        emit BiddingStarted(loanId);
    }

    function bidLoan(uint256 loanId, uint256 interest) external payable validLoan(loanId){
        Loan storage loan = idToLoan[loanId];
        if(loan.status != LendingState.BIDDING) revert BidLoan_LoanNotInBiddingStatus();
        if(interest == 0 || interest > MAX_INTEREST_BASIS_POINT) revert BidLoan_InvalidInterestRate();
        if(loan.owner == msg.sender) revert BidLoan_OwnerCannotBid();
        if(hasBidForLoan[loanId][msg.sender]) revert BidLoan_DuplicateBidder();
        if(msg.value != loan.amount) revert BidLoan_InvalidPrincipalAmount();

        Bid memory payload = Bid({
            id: bidCounter,
            loanId: loanId,
            bidder: msg.sender,
            interest: interest,
            principal: msg.value,
            withdrawn: false
        });
        idToBid[bidCounter] = payload;
        loanIdToBidId[loanId].push(bidCounter);
        hasBidForLoan[loanId][msg.sender] = true;

        if(!loan.hasBestBid || interest < idToBid[loan.bestBidId].interest){
            loan.bestBidId = bidCounter;
            loan.hasBestBid = true;
        }

        ++bidCounter;
        emit BidPlaced(loanId, bidCounter - 1, msg.sender, interest);
    }

    function closeLoan(uint256 loanId) external validLoan(loanId) onlyLoanOwnerOrAdmin(loanId){
        Loan storage loan = idToLoan[loanId];
        if(loan.status != LendingState.BIDDING) revert CloseLoan_InvalidStateOfLoan();
        if(!loan.hasBestBid) revert CloseLoan_LoanHasNoBids();

        uint256 bestBidId = loan.bestBidId;
        Bid storage winningBid = idToBid[bestBidId];

        loanIdToWinningBidId[loanId] = bestBidId;
        loan.lender = winningBid.bidder;
        loan.status = LendingState.CLOSED;
        loan.startDate = block.timestamp;
        loan.dueDate = block.timestamp + 30 days;

        (bool success, ) = payable(loan.owner).call{value: loan.amount}("");
        if(!success) revert CloseLoan_ErrorFundingBorrower();

        emit LoanClosed(loanId, bestBidId, winningBid.bidder);
    }

    function payLoan(uint256 loanId) payable external validLoan(loanId) onlyLoanOwner(loanId){
        Loan storage selectedLoan = idToLoan[loanId];
        if(selectedLoan.status != LendingState.CLOSED) revert PayLoan_InvalidState();
        if(selectedLoan.lender == address(0)) revert PayLoan_ZeroLender();
        if(block.timestamp > selectedLoan.dueDate) revert PayLoan_PastDueDate();

        uint256 winningBidId = loanIdToWinningBidId[loanId];
        Bid memory winnerBid = idToBid[winningBidId];
        uint256 totalAmount = selectedLoan.amount + (selectedLoan.amount * winnerBid.interest / MAX_INTEREST_BASIS_POINT);

        if(msg.value < totalAmount) revert PayLoan_NotEnoughRBTC();

        selectedLoan.status = LendingState.PAYED;

        if(msg.value > totalAmount){
            uint256 difference = msg.value - totalAmount;
            (bool refundSuccess, ) = payable(msg.sender).call{value: difference}("");
            if(!refundSuccess) revert PayLoan_ErrorRefundingRBTC();
        }

        (bool paySuccess, ) = payable(selectedLoan.lender).call{value: totalAmount}("");
        if(!paySuccess) revert PayLoan_ErrorPayingLoan();

        emit LoanPayed(loanId, totalAmount);
    }

    function defaultLoan(uint256 loanId) external validLoan(loanId){
        Loan storage selectedLoan = idToLoan[loanId];
        if(selectedLoan.status != LendingState.CLOSED) revert DefaultLoan_LoanNotInClosedStatus();
        if(block.timestamp <= selectedLoan.dueDate) revert DefaultLoan_LoanNotInClosedStatus();
        selectedLoan.status = LendingState.DEFAULTED;
        emit LoanDefaulted(loanId);
    }

    function withdraw() external{
        uint256 amount = pendingWithdrawals[msg.sender];
        if(amount == 0) revert Withdraw_NoFunds();
        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if(!success) revert Withdraw_ErrorSendingRBTC();
    }

    function withdrawBid(uint256 bidId) external{
        if(bidId >= bidCounter) revert InvalidBidId();
        Bid storage bid = idToBid[bidId];
        if(bid.bidder != msg.sender) revert WithdrawBid_NotYourBid();
        if(bid.withdrawn) revert WithdrawBid_AlreadyWithdrawn();

        uint256 winningBidId = loanIdToWinningBidId[bid.loanId];
        if(winningBidId != 0 && winningBidId == bidId) revert WithdrawBid_WinnerCannotWithdraw();

        bid.withdrawn = true;
        (bool success, ) = payable(msg.sender).call{value: bid.principal}("");
        if(!success) revert Withdraw_ErrorSendingRBTC();
    }

    function getLoan(uint256 loanId) external view validLoan(loanId) returns (Loan memory){
        return idToLoan[loanId];
    }

    function getBid(uint256 bidId) external view returns (Bid memory){
        if(bidId >= bidCounter) revert InvalidBidId();
        return idToBid[bidId];
    }

    function getLoanBidIds(uint256 loanId) external view validLoan(loanId) returns (uint256[] memory){
        return loanIdToBidId[loanId];
    }

    function getWinningBidId(uint256 loanId) external view validLoan(loanId) returns (uint256){
        return loanIdToWinningBidId[loanId];
    }

    function getPendingWithdrawal(address account) external view returns (uint256){
        return pendingWithdrawals[account];
    }
}